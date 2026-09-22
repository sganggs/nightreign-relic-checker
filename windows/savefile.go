//go:build windows

// Windows-side glue for the「存档检查」page. The save-archive binary format
// lives in internal/savefile (platform-free, so its tests run on any OS);
// this file only holds the thin wrapper and shell helpers used by the
// __nightreignOpenSaveFile binding. Save files are opened strictly read-only.
package main

import (
	"errors"
	"os"
	"path/filepath"

	"golang.org/x/sys/windows"

	"nightreign/relicchecker/internal/savefile"
)

// parseSaveFile parses a .sl2/.co2 archive into the bridge payload.
func parseSaveFile(data []byte, fileName string) (*savefile.Payload, error) {
	return savefile.Parse(data, fileName)
}

// parseSaveData parses a base64-encoded archive handed over by the renderer
// (拖拽打开：WebView2 里拿不到 File.path，只能把内容读成 ArrayBuffer 送过来).
func parseSaveData(encoded, fileName string) (*savefile.Payload, error) {
	return savefile.ParseBase64(encoded, fileName)
}

// roamingAppDataDir returns %APPDATA% (the env var is the fallback for the
// unlikely case KnownFolderPath fails).
func roamingAppDataDir() string {
	if roaming, err := windows.KnownFolderPath(windows.FOLDERID_RoamingAppData, 0); err == nil && roaming != "" {
		return roaming
	}
	return os.Getenv("APPDATA")
}

// saveFileDialogDir returns the default directory for the open-save dialog:
// %APPDATA%\Nightreign (where the game keeps NR0000.sl2), falling back to the
// user's home directory, or "" to let the dialog pick its own default.
func saveFileDialogDir() string {
	if roaming := roamingAppDataDir(); roaming != "" {
		return filepath.Join(roaming, savefile.SaveDirName)
	}
	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return ""
}

// locateSaveFiles 扫描 %APPDATA%\Nightreign\<Steam ID>\ 下的 .sl2/.co2。
// 目录不存在时返回空列表（界面提示路径规则），不算错误。
func locateSaveFiles() ([]savefile.Location, error) {
	roaming := roamingAppDataDir()
	if roaming == "" {
		return nil, errors.New("无法确定 %APPDATA% 目录")
	}
	return savefile.Locate(roaming)
}

// readLocatedSave 读取并解析「自动查找」结果里的某个存档。路径必须仍然出现在
// 当前的查找结果中，渲染层因此只能打开存档目录里的文件，不能借这个绑定读任意
// 文件。存档始终以只读方式打开。
func readLocatedSave(path string) (*savefile.Payload, error) {
	list, err := locateSaveFiles()
	if err != nil {
		return nil, err
	}
	location, ok := savefile.FindLocation(list, path)
	if !ok {
		return nil, errors.New("该存档已不在自动查找结果里，请重新查找")
	}
	data, err := os.ReadFile(location.Path)
	if err != nil {
		return nil, err
	}
	return savefile.Parse(data, location.FileName)
}
