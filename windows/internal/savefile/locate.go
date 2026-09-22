// 自动定位存档（「自动查找」按钮）的平台无关实现。
//
// 游戏把存档放在 %APPDATA%\Nightreign\<Steam ID>\NR0000.sl2（无缝联机存档为 .co2），
// 一台机器上可能有多个 Steam 账号目录。扫描逻辑只读目录项与文件元数据，
// 不打开任何存档文件；Windows 壳负责把 %APPDATA% 的真实路径传进来，
// 因此本文件可以在任意系统上用临时目录做单元测试。
package savefile

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// SaveDirName 是游戏在 %APPDATA% 下创建的目录名。
const SaveDirName = "Nightreign"

// maxLocatedFiles 给结果数量封顶，避免被塞满的目录拖垮界面。
const maxLocatedFiles = 200

// Location 是一条自动查找结果。字段的 json tag 即渲染层拿到的形状。
type Location struct {
	SteamID    string `json:"steamId"`    // 上层目录名（通常是 17 位 Steam ID）；直接放在根目录时为空
	FileName   string `json:"fileName"`   // NR0000.sl2 / NR0000.co2
	Path       string `json:"path"`       // 完整路径，供 openLocatedSave 回传
	Size       int64  `json:"size"`       // 字节
	ModifiedAt string `json:"modifiedAt"` // RFC3339（本地时区），渲染层负责格式化

	// modTime 是排序用的绝对时间。不能拿 ModifiedAt 字符串排：RFC3339 带的是
	// 本地偏移量，夏令时切换前后偏移不同（例如 2026-11-01T01:30:00-04:00 的绝对
	// 时间比 2026-11-01T01:15:00-05:00 早 25 分钟，字典序却判它更新），
	// 「最近改动的排最前」就会反过来。
	modTime time.Time
}

// ModTime 返回这条结果的文件修改时间（序列化给渲染层的只有 ModifiedAt 字符串）。
func (l Location) ModTime() time.Time { return l.modTime }

// IsSaveFileName 判断文件名是否是存档扩展名（不区分大小写）。
func IsSaveFileName(name string) bool {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".sl2", ".co2":
		return true
	}
	return false
}

// Locate 扫描 <appData>\Nightreign 下的存档文件：先看各 <Steam ID> 子目录，
// 也兼容直接丢在根目录的存档。目录不存在时返回空列表而不是错误（界面据此
// 提示路径规则）；根目录读取失败（例如没有权限）才返回错误。单个子目录读不
// 动只跳过它，不影响其它账号。
func Locate(appData string) ([]Location, error) {
	if strings.TrimSpace(appData) == "" {
		return nil, errors.New("无法确定 %APPDATA% 目录")
	}
	root := filepath.Join(appData, SaveDirName)
	info, err := os.Stat(root)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return []Location{}, nil
		}
		return nil, err
	}
	if !info.IsDir() {
		return []Location{}, nil
	}

	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}

	found := make([]Location, 0, 8)
	collect := func(dir, steamID string, entry fs.DirEntry) {
		if entry.IsDir() || !IsSaveFileName(entry.Name()) {
			return
		}
		stat, err := entry.Info()
		if err != nil {
			return // 扫描期间文件被删掉 / 无法读取元数据：跳过
		}
		modTime := stat.ModTime()
		found = append(found, Location{
			SteamID:    steamID,
			FileName:   entry.Name(),
			Path:       filepath.Join(dir, entry.Name()),
			Size:       stat.Size(),
			ModifiedAt: modTime.Format(time.RFC3339),
			modTime:    modTime,
		})
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			collect(root, "", entry)
			continue
		}
		dir := filepath.Join(root, entry.Name())
		children, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, child := range children {
			collect(dir, entry.Name(), child)
		}
	}

	// 最近改动的排在最前（一键打开多半要的就是它），同一时间按路径稳定排序。
	// 比的是绝对时间而不是 RFC3339 字符串，见 Location.modTime 的说明。
	sort.SliceStable(found, func(i, j int) bool {
		if !found[i].modTime.Equal(found[j].modTime) {
			return found[i].modTime.After(found[j].modTime)
		}
		return found[i].Path < found[j].Path
	})
	if len(found) > maxLocatedFiles {
		found = found[:maxLocatedFiles]
	}
	return found, nil
}

// FindLocation 在一次 Locate 的结果里按路径找条目。渲染层回传的路径只允许命中
// 这里列出的文件，等于把「按路径读文件」限制在存档目录内。Windows 路径不区分
// 大小写，也容忍分隔符写法的差异。
func FindLocation(list []Location, path string) (Location, bool) {
	needle := normalizePath(path)
	if needle == "" {
		return Location{}, false
	}
	for _, item := range list {
		if normalizePath(item.Path) == needle {
			return item, true
		}
	}
	return Location{}, false
}

func normalizePath(path string) string {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return ""
	}
	return strings.ToLower(filepath.Clean(strings.ReplaceAll(trimmed, "/", string(filepath.Separator))))
}
