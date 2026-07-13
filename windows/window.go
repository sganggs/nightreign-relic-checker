//go:build windows

// 夜幕验物 WebView2 shell window.
//
// Based on github.com/jchv/go-webview2 webview.go (MIT License,
// Copyright (c) 2020 John Chadwick, some portions Copyright (c) 2017
// Serge Zaitsev).
// Modifications for parity with the previous Electron shell:
//   - the window stays hidden until the first navigation completes
//     (equivalent to Electron's show:false + ready-to-show);
//   - the window class uses a dark background brush and the WebView2
//     default background color is set to the app background (#090b10);
//   - bound functions run on background goroutines so modal file dialogs
//     never nest a message pump inside a WebView2 event handler;
//   - WebView2 settings are hardened (no context menu, no DevTools, no
//     browser accelerator keys, no zoom, no autofill, permissions denied);
//   - per-monitor DPI: initial size, minimum size and WM_DPICHANGED.
package main

import (
	"encoding/json"
	"errors"
	"log"
	"reflect"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	"github.com/jchv/go-webview2/pkg/edge"
	"golang.org/x/sys/windows"

	"nightreign/relicchecker/internal/w32"
)

const shellClassName = "NightreignRelicChecker"

type shellOptions struct {
	Title     string
	Width     int // logical (96-DPI) pixels, outer window size
	Height    int
	MinWidth  int
	MinHeight int
	IconID    uint
	Debug     bool
	DataPath  string
	// Background is the window and WebView2 background color, used
	// before the document paints (prevents white flash).
	Background edge.COREWEBVIEW2_COLOR
}

type shell struct {
	hwnd       uintptr
	mainthread uintptr
	chromium   *edge.Chromium
	opts       shellOptions
	minsz      w32.Point // logical
	shown      uintptr   // atomic; window made visible
	m          sync.Mutex
	bindings   map[string]interface{}
	dispatchq  []func()
}

var (
	windowContext     = map[uintptr]*shell{}
	windowContextSync sync.RWMutex
)

func getWindowContext(wnd uintptr) *shell {
	windowContextSync.RLock()
	defer windowContextSync.RUnlock()
	return windowContext[wnd]
}

func setWindowContext(wnd uintptr, data *shell) {
	windowContextSync.Lock()
	defer windowContextSync.Unlock()
	windowContext[wnd] = data
}

func newShell(opts shellOptions) (*shell, error) {
	w := &shell{
		opts:     opts,
		bindings: map[string]interface{}{},
		minsz:    w32.Point{X: int32(opts.MinWidth), Y: int32(opts.MinHeight)},
	}

	chromium := edge.NewChromium()
	chromium.MessageCallback = w.msgcb
	chromium.DataPath = opts.DataPath
	// The Electron shell denied every permission request
	// (session.setPermissionRequestHandler -> callback(false)).
	chromium.SetGlobalPermission(edge.CoreWebView2PermissionStateDeny)
	chromium.NavigationCompletedCallback = func(_ *edge.ICoreWebView2, _ *edge.ICoreWebView2NavigationCompletedEventArgs) {
		w.showOnce()
	}
	w.chromium = chromium

	w.mainthread, _, _ = w32.Kernel32GetCurrentThreadID.Call()
	if err := w.createWindow(); err != nil {
		return nil, err
	}

	if !chromium.Embed(w.hwnd) {
		return nil, errors.New("无法初始化 WebView2 运行时。请确认已安装 Microsoft Edge WebView2 Runtime。")
	}

	settings, err := chromium.GetSettings()
	if err != nil {
		return nil, err
	}
	for _, apply := range []func() error{
		func() error { return settings.PutAreDefaultContextMenusEnabled(opts.Debug) },
		func() error { return settings.PutAreDevToolsEnabled(opts.Debug) },
		func() error { return settings.PutIsStatusBarEnabled(false) },
		func() error { return settings.PutAreBrowserAcceleratorKeysEnabled(opts.Debug) },
		func() error { return settings.PutIsZoomControlEnabled(false) },
		func() error { return settings.PutIsPinchZoomEnabled(false) },
		func() error { return settings.PutIsSwipeNavigationEnabled(false) },
		func() error { return settings.PutIsBuiltInErrorPageEnabled(true) },
	} {
		if err := apply(); err != nil {
			// Non-fatal and independent: a runtime that rejects one newer
			// setting must not skip the remaining hardening (continue, not break).
			log.Printf("webview2 settings: %v", err)
			continue
		}
	}

	if controller2 := chromium.GetController().GetICoreWebView2Controller2(); controller2 != nil {
		if err := controller2.PutDefaultBackgroundColor(opts.Background); err != nil {
			log.Printf("webview2 background color: %v", err)
		}
	}

	w.chromium.Resize()
	return w, nil
}

func (w *shell) createWindow() error {
	var hinstance windows.Handle
	_ = windows.GetModuleHandleEx(0, nil, &hinstance)

	var icon uintptr
	if w.opts.IconID != 0 {
		icon, _, _ = w32.User32LoadImageW.Call(uintptr(hinstance), uintptr(w.opts.IconID), 1, 0, 0, w32.LR_DEFAULTSIZE|w32.LR_SHARED)
	}

	bg := w.opts.Background
	colorref := uintptr(bg.R) | uintptr(bg.G)<<8 | uintptr(bg.B)<<16
	brush, _, _ := w32.Gdi32CreateSolidBrush.Call(colorref)

	className, _ := windows.UTF16PtrFromString(shellClassName)
	wc := w32.WndClassExW{
		CbSize:        uint32(unsafe.Sizeof(w32.WndClassExW{})),
		HInstance:     hinstance,
		LpszClassName: className,
		HIcon:         windows.Handle(icon),
		HIconSm:       windows.Handle(icon),
		HbrBackground: windows.Handle(brush),
		LpfnWndProc:   windows.NewCallback(wndproc),
	}
	if atom, _, _ := w32.User32RegisterClassExW.Call(uintptr(unsafe.Pointer(&wc))); atom == 0 {
		return errors.New("RegisterClassExW failed")
	}

	// Scale the logical size by the system DPI, the same way Electron
	// interprets BrowserWindow width/height as device-independent pixels.
	dpi := w32.DpiForSystem()
	width := w.opts.Width * int(dpi) / 96
	height := w.opts.Height * int(dpi) / 96

	screenWidth, _, _ := w32.User32GetSystemMetrics.Call(w32.SM_CXSCREEN)
	screenHeight, _, _ := w32.User32GetSystemMetrics.Call(w32.SM_CYSCREEN)
	posX := (int(screenWidth) - width) / 2
	posY := (int(screenHeight) - height) / 2
	if posX < 0 {
		posX = 0
	}
	if posY < 0 {
		posY = 0
	}

	windowName, _ := windows.UTF16PtrFromString(w.opts.Title)
	w.hwnd, _, _ = w32.User32CreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(windowName)),
		w32.WSOverlappedWindow,
		uintptr(posX),
		uintptr(posY),
		uintptr(width),
		uintptr(height),
		0,
		0,
		uintptr(hinstance),
		0,
	)
	if w.hwnd == 0 {
		return errors.New("CreateWindowExW failed")
	}
	setWindowContext(w.hwnd, w)
	// The window is intentionally NOT shown here; showOnce() reveals it
	// after the first navigation completes (Electron ready-to-show parity).
	return nil
}

func (w *shell) showOnce() {
	if !atomic.CompareAndSwapUintptr(&w.shown, 0, 1) {
		return
	}
	_, _, _ = w32.User32ShowWindow.Call(w.hwnd, w32.SWShow)
	_, _, _ = w32.User32UpdateWindow.Call(w.hwnd)
	_, _, _ = w32.User32SetForegroundWindow.Call(w.hwnd)
	_, _, _ = w32.User32SetFocus.Call(w.hwnd)
	// The controller was embedded while the window was hidden; refresh its
	// visibility and bounds so composition starts painting.
	_ = w.chromium.Show()
	w.chromium.Resize()
	w.chromium.Focus()
}

func wndproc(hwnd, msg, wp, lp uintptr) uintptr {
	w := getWindowContext(hwnd)
	if w == nil {
		r, _, _ := w32.User32DefWindowProcW.Call(hwnd, msg, wp, lp)
		return r
	}
	switch msg {
	case w32.WMMove, w32.WMMoving:
		_ = w.chromium.NotifyParentWindowPositionChanged()
	case w32.WMNCLButtonDown:
		_, _, _ = w32.User32SetFocus.Call(w.hwnd)
		r, _, _ := w32.User32DefWindowProcW.Call(hwnd, msg, wp, lp)
		return r
	case w32.WMSize:
		w.chromium.Resize()
	case w32.WMActivate:
		if wp == w32.WAInactive {
			break
		}
		w.chromium.Focus()
	case w32.WMClose:
		_, _, _ = w32.User32DestroyWindow.Call(hwnd)
	case w32.WMDestroy:
		w.Terminate()
	case w32.WMGetMinMaxInfo:
		lpmmi := (*w32.MinMaxInfo)(lparamPointer(lp))
		if w.minsz.X > 0 && w.minsz.Y > 0 {
			dpi := int32(w32.DpiForWindow(hwnd))
			lpmmi.PtMinTrackSize = w32.Point{
				X: w.minsz.X * dpi / 96,
				Y: w.minsz.Y * dpi / 96,
			}
		}
	case w32.WMDpiChanged:
		suggested := (*w32.Rect)(lparamPointer(lp))
		_, _, _ = w32.User32SetWindowPos.Call(
			hwnd, 0,
			uintptr(suggested.Left), uintptr(suggested.Top),
			uintptr(suggested.Right-suggested.Left), uintptr(suggested.Bottom-suggested.Top),
			w32.SWPNoZOrder|w32.SWPNoActivate)
	default:
		r, _, _ := w32.User32DefWindowProcW.Call(hwnd, msg, wp, lp)
		return r
	}
	return 0
}

// lparamPointer converts an LPARAM that the OS guarantees to be a pointer
// into OS-owned memory (never a Go heap address, so untouched by the GC).
func lparamPointer(lp uintptr) unsafe.Pointer {
	return *(*unsafe.Pointer)(unsafe.Pointer(&lp))
}

type rpcMessage struct {
	ID     int               `json:"id"`
	Method string            `json:"method"`
	Params []json.RawMessage `json:"params"`
}

func jsString(v interface{}) string { b, _ := json.Marshal(v); return string(b) }

func (w *shell) msgcb(msg string) {
	d := rpcMessage{}
	if err := json.Unmarshal([]byte(msg), &d); err != nil {
		log.Printf("invalid RPC message: %v", err)
		return
	}

	// Run the binding on a background goroutine: modal file dialogs and
	// file I/O must not block (or re-enter) the WebView2 event handler.
	go func() {
		id := strconv.Itoa(d.ID)
		if res, err := w.callbinding(d); err != nil {
			w.Dispatch(func() {
				w.Eval("window._rpc[" + id + "].reject(" + jsString(err.Error()) + "); window._rpc[" + id + "] = undefined")
			})
		} else if b, err := json.Marshal(res); err != nil {
			w.Dispatch(func() {
				w.Eval("window._rpc[" + id + "].reject(" + jsString(err.Error()) + "); window._rpc[" + id + "] = undefined")
			})
		} else {
			w.Dispatch(func() {
				w.Eval("window._rpc[" + id + "].resolve(" + string(b) + "); window._rpc[" + id + "] = undefined")
			})
		}
	}()
}

func (w *shell) callbinding(d rpcMessage) (interface{}, error) {
	w.m.Lock()
	f, ok := w.bindings[d.Method]
	w.m.Unlock()
	if !ok {
		return nil, nil
	}

	v := reflect.ValueOf(f)
	if len(d.Params) != v.Type().NumIn() {
		return nil, errors.New("function arguments mismatch")
	}
	args := []reflect.Value{}
	for i := range d.Params {
		arg := reflect.New(v.Type().In(i))
		if err := json.Unmarshal(d.Params[i], arg.Interface()); err != nil {
			return nil, err
		}
		args = append(args, arg.Elem())
	}

	errorType := reflect.TypeOf((*error)(nil)).Elem()
	res := v.Call(args)
	switch len(res) {
	case 0:
		return nil, nil
	case 1:
		if res[0].Type().Implements(errorType) {
			if res[0].Interface() != nil {
				return nil, res[0].Interface().(error)
			}
			return nil, nil
		}
		return res[0].Interface(), nil
	case 2:
		if !res[1].Type().Implements(errorType) {
			return nil, errors.New("second return value must be an error")
		}
		if res[1].Interface() == nil {
			return res[0].Interface(), nil
		}
		return res[0].Interface(), res[1].Interface().(error)
	default:
		return nil, errors.New("unexpected number of return values")
	}
}

func (w *shell) Run() {
	// Safety net: if navigation never completes (e.g. the extracted UI was
	// deleted mid-run), reveal the window anyway so the error is visible.
	timer := time.AfterFunc(4*time.Second, func() {
		w.Dispatch(w.showOnce)
	})
	defer timer.Stop()

	var msg w32.Msg
	for {
		_, _, _ = w32.User32GetMessageW.Call(
			uintptr(unsafe.Pointer(&msg)),
			0,
			0,
			0,
		)
		if msg.Message == w32.WMApp {
			w.m.Lock()
			q := append([]func(){}, w.dispatchq...)
			w.dispatchq = []func(){}
			w.m.Unlock()
			for _, v := range q {
				v()
			}
		} else if msg.Message == w32.WMQuit {
			return
		}
		r, _, _ := w32.User32GetAncestor.Call(uintptr(msg.Hwnd), w32.GARoot)
		r, _, _ = w32.User32IsDialogMessage.Call(r, uintptr(unsafe.Pointer(&msg)))
		if r != 0 {
			continue
		}
		_, _, _ = w32.User32TranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		_, _, _ = w32.User32DispatchMessageW.Call(uintptr(unsafe.Pointer(&msg)))
	}
}

func (w *shell) Terminate() {
	_, _, _ = w32.User32PostQuitMessage.Call(0)
}

func (w *shell) Window() uintptr {
	return w.hwnd
}

func (w *shell) Navigate(url string) {
	w.chromium.Navigate(url)
}

func (w *shell) Init(js string) {
	w.chromium.Init(js)
}

func (w *shell) Eval(js string) {
	w.chromium.Eval(js)
}

func (w *shell) Dispatch(f func()) {
	w.m.Lock()
	w.dispatchq = append(w.dispatchq, f)
	w.m.Unlock()
	_, _, _ = w32.User32PostThreadMessageW.Call(w.mainthread, w32.WMApp, 0, 0)
}

func (w *shell) Bind(name string, f interface{}) error {
	v := reflect.ValueOf(f)
	if v.Kind() != reflect.Func {
		return errors.New("only functions can be bound")
	}
	if n := v.Type().NumOut(); n > 2 {
		return errors.New("function may only return a value or a value+error")
	}
	w.m.Lock()
	w.bindings[name] = f
	w.m.Unlock()

	w.Init("(function() { var name = " + jsString(name) + ";" + `
		var RPC = window._rpc = (window._rpc || {nextSeq: 1});
		window[name] = function() {
		  var seq = RPC.nextSeq++;
		  var promise = new Promise(function(resolve, reject) {
			RPC[seq] = {
			  resolve: resolve,
			  reject: reject,
			};
		  });
		  window.external.invoke(JSON.stringify({
			id: seq,
			method: name,
			params: Array.prototype.slice.call(arguments),
		  }));
		  return promise;
		}
	})()`)

	return nil
}
