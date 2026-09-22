// 夜幕验物 — 《艾尔登法环 黑夜君临》遗物词条合法性检查工具（Windows 轻量壳）。
//
// The renderer (renderer/) is unchanged from the Electron distribution;
// this program only replaces the Electron container with the system
// WebView2 runtime so the executable stays a few megabytes.
package main

//go:generate go-winres make

import (
	"bytes"
	"embed"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"runtime"

	"github.com/jchv/go-webview2/pkg/edge"

	"nightreign/relicchecker/internal/w32"
)

const appVersion = "0.3.0"

//go:embed renderer
var rendererFS embed.FS

//go:embed resources/affixes.json
var builtInCatalog []byte

//go:embed resources/relics.json
var builtInRelicData []byte

// 三个新页面（首领数据 / 词条反查 / 增伤排名）的数据文件。内容由另一条数据
// 流水线生成，未生成前 resources/ 下是最小占位 JSON（`{"placeholder": true}`），
// 渲染层据此显示「数据未内置」。go:embed 要求文件必须存在，所以占位文件不能删；
// 拿到真实数据后运行 scripts/sync-data.sh 覆盖即可，本文件无需改动。

//go:embed resources/bosses.json
var builtInBossData []byte

//go:embed resources/skills.json
var builtInSkillData []byte

//go:embed resources/buffs.json
var builtInBuffData []byte

// builtInGameData 的键就是渲染层 ctx.getGameData(name) 的 name。
var builtInGameData = map[string][]byte{
	"bosses": builtInBossData,
	"skills": builtInSkillData,
	"buffs":  builtInBuffData,
}

// uiResourcesDir 是 ui\ 下存放上述数据文件的目录名（与版本目录同级，对应
// index.html 的 ../resources/<name>.json）。
const uiResourcesDir = "resources"

func init() {
	// The Win32 message loop and WebView2's STA COM must stay on one thread.
	runtime.LockOSThread()
}

func main() {
	debug := os.Getenv("NIGHTREIGN_DEBUG") == "1"

	dataDir, err := appDataDir()
	if err != nil {
		fatal("无法确定应用数据目录：" + err.Error())
	}

	uiDir, err := extractUI(filepath.Join(dataDir, "ui", "v"+appVersion))
	if err != nil {
		fatal("无法准备界面文件：" + err.Error())
	}

	w, err := newShell(shellOptions{
		Title:      "夜幕验物",
		Width:      1320,
		Height:     860,
		MinWidth:   1040,
		MinHeight:  700,
		IconID:     1,
		Debug:      debug,
		DataPath:   filepath.Join(dataDir, "WebView2"),
		Background: edge.COREWEBVIEW2_COLOR{A: 255, R: 0x09, G: 0x0b, B: 0x10},
	})
	if err != nil {
		fatal(err.Error())
	}

	if err := registerBindings(w, builtInCatalog, builtInRelicData, builtInGameData); err != nil {
		fatal("无法注册应用接口：" + err.Error())
	}
	w.Init(bridgeJS)
	w.Navigate(fileURL(filepath.Join(uiDir, "index.html")))
	w.Run()
}

// extractUI copies the embedded renderer to disk (WebView2 cannot navigate
// into an embedded filesystem). Files are rewritten only when their content
// changed, so a running second instance is never disturbed needlessly.
func extractUI(target string) (string, error) {
	sub, err := fs.Sub(rendererFS, "renderer")
	if err != nil {
		return "", err
	}
	err = fs.WalkDir(sub, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		dest := filepath.Join(target, filepath.FromSlash(path))
		if d.IsDir() {
			return os.MkdirAll(dest, 0o700)
		}
		data, err := fs.ReadFile(sub, path)
		if err != nil {
			return err
		}
		if existing, err := os.ReadFile(dest); err == nil && bytes.Equal(existing, data) {
			return nil
		}
		// Atomic replace (temp file + rename), consistent with the catalog
		// writer, so a concurrent instance's WebView2 never reads a truncated
		// file mid-write.
		return writeFileAtomic(dest, data, 0o600)
	})
	if err != nil {
		return "", err
	}
	if err := extractGameData(filepath.Join(filepath.Dir(target), uiResourcesDir)); err != nil {
		return "", err
	}
	pruneOldUIVersions(target)
	return target, nil
}

// extractGameData 把内嵌的新页面数据写到 ui\resources\，与 index.html 的
// ../resources/<name>.json 相对路径对应。打包后的应用实际走
// window.nightreign.loadGameData 桥（Chromium 不允许 file:// 页面 fetch 本地
// 文件），落盘的副本供浏览器预览与排障使用；写入规则与 extractUI 一致：
// 内容未变则不重写，需要重写时走原子替换。
func extractGameData(dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	for name, data := range builtInGameData {
		dest := filepath.Join(dir, name+".json")
		if existing, err := os.ReadFile(dest); err == nil && bytes.Equal(existing, data) {
			continue
		}
		if err := writeFileAtomic(dest, data, 0o600); err != nil {
			return err
		}
	}
	return nil
}

// writeFileAtomic writes data to a same-directory temp file, fsyncs it, and
// renames it over dest, so readers see either the old or the new file whole.
func writeFileAtomic(dest string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(dest)
	f, err := os.CreateTemp(dir, "."+filepath.Base(dest)+".*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(tmp)
		}
	}()
	if _, err := f.Write(data); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	_ = os.Chmod(tmp, perm)
	if err := os.Rename(tmp, dest); err != nil {
		return err
	}
	cleanup = false
	return nil
}

// pruneOldUIVersions removes sibling ui\v* directories from previous versions
// so upgrades do not accumulate stale copies. ui\resources\ (written by
// extractGameData and shared across versions) is kept. Best-effort; failures
// (e.g. a directory held open by another running instance) are ignored.
func pruneOldUIVersions(currentDir string) {
	uiRoot := filepath.Dir(currentDir)
	keep := filepath.Base(currentDir)
	entries, err := os.ReadDir(uiRoot)
	if err != nil {
		return
	}
	for _, e := range entries {
		if e.IsDir() && e.Name() != keep && e.Name() != uiResourcesDir {
			_ = os.RemoveAll(filepath.Join(uiRoot, e.Name()))
		}
	}
}

func fileURL(path string) string {
	u := url.URL{Scheme: "file", Path: "/" + filepath.ToSlash(path)}
	return u.String()
}

func fatal(message string) {
	w32.MessageBoxError("夜幕验物", message)
	os.Exit(1)
}
