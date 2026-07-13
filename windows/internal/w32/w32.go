// Package w32 contains the Win32 bindings used by the shell window.
//
// Forked from github.com/jchv/go-webview2/internal/w32 (MIT License,
// Copyright (c) 2020 John Chadwick, some portions Copyright (c) 2017
// Serge Zaitsev),
// because that package is internal and cannot be imported directly.
// Additions: solid brush, DPI helpers, MessageBoxW and a few constants.
package w32

import (
	"syscall"
	"unicode/utf16"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	kernel32                   = windows.NewLazySystemDLL("kernel32")
	Kernel32GetCurrentThreadID = kernel32.NewProc("GetCurrentThreadId")

	gdi32                = windows.NewLazySystemDLL("gdi32")
	Gdi32CreateSolidBrush = gdi32.NewProc("CreateSolidBrush")

	user32                   = windows.NewLazySystemDLL("user32")
	User32LoadImageW         = user32.NewProc("LoadImageW")
	User32GetSystemMetrics   = user32.NewProc("GetSystemMetrics")
	User32RegisterClassExW   = user32.NewProc("RegisterClassExW")
	User32CreateWindowExW    = user32.NewProc("CreateWindowExW")
	User32DestroyWindow      = user32.NewProc("DestroyWindow")
	User32ShowWindow         = user32.NewProc("ShowWindow")
	User32UpdateWindow       = user32.NewProc("UpdateWindow")
	User32SetForegroundWindow = user32.NewProc("SetForegroundWindow")
	User32SetFocus           = user32.NewProc("SetFocus")
	User32GetMessageW        = user32.NewProc("GetMessageW")
	User32TranslateMessage   = user32.NewProc("TranslateMessage")
	User32DispatchMessageW   = user32.NewProc("DispatchMessageW")
	User32DefWindowProcW     = user32.NewProc("DefWindowProcW")
	User32PostQuitMessage    = user32.NewProc("PostQuitMessage")
	User32PostMessageW       = user32.NewProc("PostMessageW")
	User32SetWindowTextW     = user32.NewProc("SetWindowTextW")
	User32PostThreadMessageW = user32.NewProc("PostThreadMessageW")
	User32GetWindowLongPtrW  = user32.NewProc("GetWindowLongPtrW")
	User32SetWindowLongPtrW  = user32.NewProc("SetWindowLongPtrW")
	User32AdjustWindowRect   = user32.NewProc("AdjustWindowRect")
	User32SetWindowPos       = user32.NewProc("SetWindowPos")
	User32IsDialogMessage    = user32.NewProc("IsDialogMessage")
	User32GetAncestor        = user32.NewProc("GetAncestor")
	User32GetDpiForWindow    = user32.NewProc("GetDpiForWindow")
	User32GetDpiForSystem    = user32.NewProc("GetDpiForSystem")
	User32MessageBoxW        = user32.NewProc("MessageBoxW")
)

const (
	SM_CXSCREEN = 0
	SM_CYSCREEN = 1
)

const (
	CW_USEDEFAULT = 0x80000000
)

const (
	LR_DEFAULTSIZE = 0x0040
	LR_SHARED      = 0x8000
)

const (
	SWShow = 5
)

const (
	SWPNoZOrder     = 0x0004
	SWPNoActivate   = 0x0010
	SWPNoMove       = 0x0002
	SWPFrameChanged = 0x0020
)

const (
	WMDestroy       = 0x0002
	WMMove          = 0x0003
	WMSize          = 0x0005
	WMActivate      = 0x0006
	WMClose         = 0x0010
	WMQuit          = 0x0012
	WMGetMinMaxInfo = 0x0024
	WMNCLButtonDown = 0x00A1
	WMMoving        = 0x0216
	WMDpiChanged    = 0x02E0
	WMApp           = 0x8000
)

const (
	GARoot = 2
)

const (
	MBIconError = 0x00000010
)

const (
	WSOverlapped       = 0x00000000
	WSMaximizeBox      = 0x00010000
	WSThickFrame       = 0x00040000
	WSCaption          = 0x00C00000
	WSSysMenu          = 0x00080000
	WSMinimizeBox      = 0x00020000
	WSOverlappedWindow = WSOverlapped | WSCaption | WSSysMenu | WSThickFrame | WSMinimizeBox | WSMaximizeBox
)

const (
	WAInactive = 0
)

type WndClassExW struct {
	CbSize        uint32
	Style         uint32
	LpfnWndProc   uintptr
	CnClsExtra    int32
	CbWndExtra    int32
	HInstance     windows.Handle
	HIcon         windows.Handle
	HCursor       windows.Handle
	HbrBackground windows.Handle
	LpszMenuName  *uint16
	LpszClassName *uint16
	HIconSm       windows.Handle
}

type Rect struct {
	Left   int32
	Top    int32
	Right  int32
	Bottom int32
}

type MinMaxInfo struct {
	PtReserved     Point
	PtMaxSize      Point
	PtMaxPosition  Point
	PtMinTrackSize Point
	PtMaxTrackSize Point
}

type Point struct {
	X, Y int32
}

type Msg struct {
	Hwnd     syscall.Handle
	Message  uint32
	WParam   uintptr
	LParam   uintptr
	Time     uint32
	Pt       Point
	LPrivate uint32
}

func Utf16PtrToString(p *uint16) string {
	if p == nil {
		return ""
	}
	end := unsafe.Pointer(p)
	n := 0
	for *(*uint16)(end) != 0 {
		end = unsafe.Pointer(uintptr(end) + unsafe.Sizeof(*p))
		n++
	}
	s := (*[(1 << 30) - 1]uint16)(unsafe.Pointer(p))[:n:n]
	return string(utf16.Decode(s))
}

// DpiForWindow returns the window DPI, or 96 when unavailable (pre-1607).
func DpiForWindow(hwnd uintptr) uint {
	if User32GetDpiForWindow.Find() != nil {
		return 96
	}
	dpi, _, _ := User32GetDpiForWindow.Call(hwnd)
	if dpi == 0 {
		return 96
	}
	return uint(dpi)
}

// DpiForSystem returns the system DPI, or 96 when unavailable.
func DpiForSystem() uint {
	if User32GetDpiForSystem.Find() != nil {
		return 96
	}
	dpi, _, _ := User32GetDpiForSystem.Call()
	if dpi == 0 {
		return 96
	}
	return uint(dpi)
}

// MessageBoxError shows a modal error dialog; usable before any window exists.
func MessageBoxError(title, text string) {
	t, _ := windows.UTF16PtrFromString(title)
	m, _ := windows.UTF16PtrFromString(text)
	_, _, _ = User32MessageBoxW.Call(0, uintptr(unsafe.Pointer(m)), uintptr(unsafe.Pointer(t)), MBIconError)
}

func GetWindowLong(hwnd uintptr, index int) uintptr {
	ret, _, _ := User32GetWindowLongPtrW.Call(hwnd, uintptr(index))
	return ret
}

func SetWindowLong(hwnd uintptr, index int, newLong uintptr) uintptr {
	ret, _, _ := User32SetWindowLongPtrW.Call(hwnd, uintptr(index), newLong)
	return ret
}
