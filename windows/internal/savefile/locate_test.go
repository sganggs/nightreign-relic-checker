package savefile

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// writeFile 在临时目录里造一个假存档文件，并指定修改时间（排序用）。
func writeFile(t *testing.T, path string, size int, modTime time.Time) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, make([]byte, size), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, modTime, modTime); err != nil {
		t.Fatal(err)
	}
}

// appDataFixture 模拟 %APPDATA%：两个 Steam ID 目录、一个无关目录、
// 若干非存档文件。
func appDataFixture(t *testing.T) string {
	t.Helper()
	appData := t.TempDir()
	root := filepath.Join(appData, SaveDirName)
	base := time.Date(2026, 3, 4, 5, 6, 7, 0, time.Local)

	writeFile(t, filepath.Join(root, "76561198000000001", "NR0000.sl2"), 2048, base.Add(2*time.Hour))
	writeFile(t, filepath.Join(root, "76561198000000001", "NR0000.co2"), 1024, base.Add(time.Hour))
	writeFile(t, filepath.Join(root, "76561198000000001", "NR0000.sl2.bak"), 4096, base)
	writeFile(t, filepath.Join(root, "76561198000000001", "steam_autocloud.vdf"), 16, base)
	writeFile(t, filepath.Join(root, "76561198000000002", "NR0000.SL2"), 512, base.Add(3*time.Hour))
	writeFile(t, filepath.Join(root, "steam_autocloud.vdf"), 16, base)
	if err := os.MkdirAll(filepath.Join(root, "76561198000000003"), 0o700); err != nil {
		t.Fatal(err)
	}
	return appData
}

func TestLocateFindsEverySteamID(t *testing.T) {
	appData := appDataFixture(t)

	found, err := Locate(appData)
	if err != nil {
		t.Fatalf("Locate: %v", err)
	}
	if len(found) != 3 {
		t.Fatalf("找到 %d 个存档，期望 3：%+v", len(found), found)
	}

	// 最近改动的排最前。
	if found[0].FileName != "NR0000.SL2" || found[0].SteamID != "76561198000000002" {
		t.Errorf("首条 = %+v，期望 76561198000000002/NR0000.SL2", found[0])
	}
	if found[0].Size != 512 {
		t.Errorf("size = %d，期望 512", found[0].Size)
	}
	if _, err := time.Parse(time.RFC3339, found[0].ModifiedAt); err != nil {
		t.Errorf("modifiedAt %q 不是 RFC3339：%v", found[0].ModifiedAt, err)
	}
	if found[1].FileName != "NR0000.sl2" || found[2].FileName != "NR0000.co2" {
		t.Errorf("排序错误：%q, %q", found[1].FileName, found[2].FileName)
	}
	for _, item := range found {
		if _, err := os.Stat(item.Path); err != nil {
			t.Errorf("path %q 不可用：%v", item.Path, err)
		}
	}
}

func TestLocateMissingDirectory(t *testing.T) {
	found, err := Locate(t.TempDir()) // 没有 Nightreign 目录
	if err != nil {
		t.Fatalf("目录缺失不应报错：%v", err)
	}
	if len(found) != 0 {
		t.Fatalf("期望空列表，得到 %+v", found)
	}

	appData := t.TempDir()
	if err := os.WriteFile(filepath.Join(appData, SaveDirName), []byte("不是目录"), 0o600); err != nil {
		t.Fatal(err)
	}
	found, err = Locate(appData)
	if err != nil || len(found) != 0 {
		t.Fatalf("Nightreign 是文件时应返回空列表，得到 %+v, %v", found, err)
	}
}

func TestLocateRejectsEmptyAppData(t *testing.T) {
	if _, err := Locate("  "); err == nil {
		t.Fatal("空 APPDATA 应报错")
	}
}

func TestIsSaveFileName(t *testing.T) {
	for _, name := range []string{"NR0000.sl2", "NR0000.CO2", "a.Sl2"} {
		if !IsSaveFileName(name) {
			t.Errorf("%q 应判为存档", name)
		}
	}
	for _, name := range []string{"NR0000.sl2.bak", "steam_autocloud.vdf", "NR0000", ""} {
		if IsSaveFileName(name) {
			t.Errorf("%q 不应判为存档", name)
		}
	}
}

func TestFindLocation(t *testing.T) {
	found, err := Locate(appDataFixture(t))
	if err != nil {
		t.Fatalf("Locate: %v", err)
	}

	hit, ok := FindLocation(found, found[0].Path)
	if !ok || hit.Path != found[0].Path {
		t.Fatalf("精确路径应命中：%+v %v", hit, ok)
	}
	// 分隔符写法不同也应命中（渲染层回传的路径可能被规整过）。
	if _, ok := FindLocation(found, filepath.ToSlash(found[0].Path)); !ok {
		t.Error("正斜杠写法应命中")
	}
	if _, ok := FindLocation(found, filepath.Join(filepath.Dir(found[0].Path), ".", found[0].FileName)); !ok {
		t.Error("含 . 的路径应命中")
	}
	// 目录外的路径必须落空：按路径读文件只允许命中查找结果。
	if _, ok := FindLocation(found, filepath.Join(t.TempDir(), "NR0000.sl2")); ok {
		t.Error("不在结果里的路径不应命中")
	}
	if _, ok := FindLocation(found, "   "); ok {
		t.Error("空路径不应命中")
	}
	if _, ok := FindLocation(nil, "C:\\x\\NR0000.sl2"); ok {
		t.Error("空列表不应命中")
	}
}

// 夏令时切换前后本地偏移不同，RFC3339 字符串的字典序会和真实时间反过来：
// 2026-11-01T01:30:00-04:00（EDT）比 2026-11-01T01:15:00-05:00（EST）早 25 分钟，
// 但按字符串比会判前者更新。排序必须用绝对时间。
func TestLocateSortsAcrossDSTChange(t *testing.T) {
	newYork, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Skipf("没有时区数据：%v", err)
	}
	oldLocal := time.Local
	time.Local = newYork
	t.Cleanup(func() { time.Local = oldLocal })

	appData := t.TempDir()
	dir := filepath.Join(appData, SaveDirName, "76561198000000001")
	// 两个时刻都落在 2026-11-01 01:xx 这个「重复的一小时」里：
	// earlier 是 EDT（-04:00），later 是 EST（-05:00），later 晚 25 分钟。
	earlier := time.Date(2026, 11, 1, 5, 30, 0, 0, time.UTC) // 01:30 EDT
	later := time.Date(2026, 11, 1, 6, 15, 0, 0, time.UTC)   // 01:15 EST
	if !later.After(earlier) {
		t.Fatal("fixture 时间搞反了")
	}
	writeFile(t, filepath.Join(dir, "NR0000.sl2"), 16, earlier)
	writeFile(t, filepath.Join(dir, "NR0001.sl2"), 16, later)

	found, err := Locate(appData)
	if err != nil {
		t.Fatalf("Locate: %v", err)
	}
	if len(found) != 2 {
		t.Fatalf("找到 %d 个存档，期望 2", len(found))
	}
	byName := map[string]Location{}
	for _, item := range found {
		byName[item.FileName] = item
	}
	newer, older := byName["NR0001.sl2"], byName["NR0000.sl2"]
	// 前提：这两条的 RFC3339 字符串字典序与真实时间顺序相反，否则这个用例
	// 盯不住回归（例如某些环境没有夏令时）。
	if !(newer.ModifiedAt < older.ModifiedAt) {
		t.Skipf("当前环境没有复现出偏移差异：%q / %q", newer.ModifiedAt, older.ModifiedAt)
	}
	if found[0].FileName != "NR0001.sl2" {
		t.Errorf("首条 = %q（%s），期望最近修改的 NR0001.sl2（%s）",
			found[0].FileName, found[0].ModifiedAt, newer.ModifiedAt)
	}
	if !newer.ModTime().Equal(later.In(newYork)) {
		t.Errorf("ModTime = %v，期望 %v", newer.ModTime(), later)
	}
}
