//go:build windows

// Windows-side glue for the「存档检查」page. The save-archive binary format
// lives in internal/savefile (platform-free, so its tests run on any OS);
// this file only holds the thin wrapper and shell helpers used by the
// __nightreignOpenSaveFile binding. Save files are opened strictly read-only.
package main

import (
	"os"
	"path/filepath"

	"golang.org/x/sys/windows"

	"nightreign/relicchecker/internal/savefile"
)

// parseSaveFile parses a .sl2/.co2 archive into the bridge payload.
func parseSaveFile(data []byte, fileName string) (*savefile.Payload, error) {
	return savefile.Parse(data, fileName)
}

// saveFileDialogDir returns the default directory for the open-save dialog:
// %APPDATA%\Nightreign (where the game keeps NR0000.sl2), falling back to the
// user's home directory, or "" to let the dialog pick its own default.
func saveFileDialogDir() string {
	if roaming, err := windows.KnownFolderPath(windows.FOLDERID_RoamingAppData, 0); err == nil && roaming != "" {
		return filepath.Join(roaming, "Nightreign")
	}
	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return ""
}
