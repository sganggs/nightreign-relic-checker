// window.nightreign bridge. Replaces the Electron preload + ipcMain pair
// with the same five catalog methods and identical result shapes, plus the
// two save-check methods (openSaveFile/loadRelicData) added in 0.2.0 and the
// save-page additions (locateSaveFiles/openLocatedSave/parseSaveData/
// exportText) that have no Electron history.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/ncruces/zenity"
	"golang.org/x/sys/windows"

	"nightreign/relicchecker/internal/savefile"
)

// Electron IPC channel names, preserved so rejected-promise messages match
// Electron's "Error invoking remote method '<channel>': ..." wrapper.
const (
	chLoad   = "catalog:load"
	chImport = "catalog:import"
	chSave   = "catalog:save-custom"
	chReset  = "catalog:reset"
	chExport = "catalog:export"
)

// wrapErr reproduces the message the renderer sees under Electron, where
// ipcRenderer.invoke rejects with:
//
//	Error invoking remote method '<channel>': <ErrType>: <message>
//
// The only structural error (assertCatalog) was a TypeError in Electron; every
// other rejection was a plain Error. The message body is already byte-identical
// to Electron (see catalog.go), so only this wrapper had to be restored.
func wrapErr(channel string, err error) error {
	if err == nil {
		return nil
	}
	errType := "Error"
	if errors.Is(err, errInvalidCatalog) {
		errType = "TypeError"
	}
	return fmt.Errorf("Error invoking remote method '%s': %s: %s", channel, errType, err.Error())
}

// bridgeJS recreates the API exposed by the Electron preload script. The
// renderer is byte-for-byte identical to the Electron version and only
// talks to window.nightreign.
//
// Catalogs travel to Go pre-serialized with JSON.stringify(catalog, null, 2)
// so saved/exported files stay byte-identical to Electron's output.
//
// The leading origin guard is the equivalent of Electron's
// assertTrustedIpcSender: the privileged bridge (with disk read/write
// capability) is only exposed when the document is the app's own extracted
// index.html. Because this script runs via AddScriptToExecuteOnDocumentCreated
// — before any page script — a page reached by an unexpected navigation never
// gets window.nightreign, and app.js falls back to its read-only browser mode.
const bridgeJS = `(function () {
  'use strict';
  if (window.nightreign) { return; }
  if (location.protocol !== 'file:' || !/\/ui\/v[0-9.]+\/index\.html$/i.test(location.pathname)) {
    return;
  }
  var toError = function (value) {
    if (value instanceof Error) { return value; }
    if (typeof value === 'string') { return new Error(value); }
    if (value && typeof value.message === 'string') { return new Error(value.message); }
    return new Error(String(value));
  };
  var call = function (invoke) {
    try {
      return Promise.resolve(invoke()).catch(function (reason) { throw toError(reason); });
    } catch (error) {
      return Promise.reject(toError(error));
    }
  };
  window.nightreign = Object.freeze({
    platform: 'win32',
    loadCatalog: function () {
      return call(function () { return window.__nightreignLoadCatalog(); });
    },
    importCatalog: function () {
      return call(function () { return window.__nightreignImportCatalog(); });
    },
    saveCustomCatalog: function (catalog) {
      return call(function () { return window.__nightreignSaveCustomCatalog(JSON.stringify(catalog, null, 2)); });
    },
    resetCatalog: function () {
      return call(function () { return window.__nightreignResetCatalog(); });
    },
    exportCatalog: function (catalog, suggestedName) {
      return call(function () {
        return window.__nightreignExportCatalog(
          JSON.stringify(catalog, null, 2),
          typeof suggestedName === 'string' ? suggestedName : ''
        );
      });
    },
    openSaveFile: function () {
      return call(function () { return window.__nightreignOpenSaveFile(); });
    },
    // 自动查找：列出 %APPDATA%\Nightreign\<Steam ID>\ 下的 .sl2/.co2；
    // openLocatedSave 只接受列表里出现过的路径。
    locateSaveFiles: function () {
      return call(function () { return window.__nightreignLocateSaveFiles(); });
    },
    openLocatedSave: function (path) {
      return call(function () { return window.__nightreignOpenLocatedSave(String(path == null ? '' : path)); });
    },
    // 拖拽打开：WebView2 里拿不到 File.path，渲染层把文件读成 base64 送过来。
    parseSaveData: function (base64, fileName) {
      return call(function () {
        return window.__nightreignParseSaveData(
          String(base64 == null ? '' : base64),
          typeof fileName === 'string' ? fileName : ''
        );
      });
    },
    // 导出报告：把纯文本 / CSV 通过保存对话框写到用户选的位置。
    exportText: function (defaultName, content) {
      return call(function () {
        return window.__nightreignExportText(
          typeof defaultName === 'string' ? defaultName : '',
          String(content == null ? '' : content)
        );
      });
    },
    loadRelicData: function () {
      return call(function () { return window.__nightreignLoadRelicData(); });
    },
    // 新页面（首领数据 / 词条反查 / 增伤排名）的数据：name 为
    // 'bosses' | 'skills' | 'buffs'，未内置时返回 null（渲染层据此降级）。
    loadGameData: function (name) {
      return call(function () { return window.__nightreignLoadGameData(String(name)); });
    }
  });
  // Parity with the hardened Electron shell: no popups, and dropping a
  // file onto the window must not navigate away from the app.
  window.open = function () { return null; };
  window.addEventListener('dragover', function (event) { event.preventDefault(); }, false);
  window.addEventListener('drop', function (event) { event.preventDefault(); }, false);
})();`

func registerBindings(w *shell, builtIn, relicData []byte, gameData map[string][]byte) error {
	owner := zenity.Attach(w.Window())

	bind := func(name string, fn interface{}) error { return w.Bind(name, fn) }

	if err := bind("__nightreignLoadCatalog", func() (catalogPayload, error) {
		p, err := loadCatalog(builtIn)
		return p, wrapErr(chLoad, err)
	}); err != nil {
		return err
	}

	if err := bind("__nightreignImportCatalog", func() (*importResult, error) {
		path, err := zenity.SelectFile(
			zenity.Title("导入词条库"),
			zenity.FileFilters{
				{Name: "JSON 词条库", Patterns: []string{"*.json"}, CaseFold: true},
				{Name: "所有文件", Patterns: []string{"*.*"}},
			},
			owner,
		)
		if errors.Is(err, zenity.ErrCanceled) {
			return nil, nil
		}
		if err != nil {
			return nil, wrapErr(chImport, err)
		}
		catalog, err := readCatalog(path)
		if err != nil {
			return nil, wrapErr(chImport, err)
		}
		return &importResult{Catalog: catalog, FileName: filepath.Base(path)}, nil
	}); err != nil {
		return err
	}

	if err := bind("__nightreignSaveCustomCatalog", func(serialized string) (saveResult, error) {
		path, err := customCatalogPath()
		if err != nil {
			return saveResult{}, wrapErr(chSave, err)
		}
		if err := writeJSONAtomic(path, serialized); err != nil {
			return saveResult{}, wrapErr(chSave, err)
		}
		return saveResult{OK: true, Origin: "custom"}, nil
	}); err != nil {
		return err
	}

	if err := bind("__nightreignResetCatalog", func() (catalogPayload, error) {
		p, err := resetCatalog(builtIn)
		return p, wrapErr(chReset, err)
	}); err != nil {
		return err
	}

	if err := bind("__nightreignExportCatalog", func(serialized, suggestedName string) (exportResult, error) {
		// Electron validated the catalog before opening the save dialog.
		if err := assertCatalogBytes([]byte(serialized)); err != nil {
			return exportResult{}, wrapErr(chExport, errInvalidCatalog)
		}
		defaultPath := safeSuggestedName(suggestedName)
		if docs, err := windows.KnownFolderPath(windows.FOLDERID_Documents, 0); err == nil {
			defaultPath = filepath.Join(docs, defaultPath)
		}
		path, err := zenity.SelectFileSave(
			zenity.Title("导出词条库"),
			zenity.Filename(defaultPath),
			zenity.ConfirmOverwrite(),
			zenity.FileFilters{{Name: "JSON 词条库", Patterns: []string{"*.json"}, CaseFold: true}},
			owner,
		)
		if errors.Is(err, zenity.ErrCanceled) {
			return exportResult{Canceled: true}, nil
		}
		if err != nil {
			return exportResult{}, wrapErr(chExport, err)
		}
		if err := writeJSONAtomic(path, serialized); err != nil {
			return exportResult{}, wrapErr(chExport, err)
		}
		return exportResult{Canceled: false, FilePath: path}, nil
	}); err != nil {
		return err
	}

	// The two save-check bindings are new in 0.2.0 and have no Electron
	// history, so their errors are not wrapped in the IPC-channel format.

	if err := bind("__nightreignOpenSaveFile", func() (*savefile.Payload, error) {
		opts := []zenity.Option{
			zenity.Title("选择存档文件"),
			zenity.FileFilters{
				{Name: "黑夜君临存档", Patterns: []string{"*.sl2", "*.co2"}, CaseFold: true},
				{Name: "所有文件", Patterns: []string{"*.*"}},
			},
			owner,
		}
		// Point the dialog at the game's save directory; the trailing
		// separator marks the path as a directory, not a file name.
		if dir := saveFileDialogDir(); dir != "" {
			opts = append(opts, zenity.Filename(dir+string(filepath.Separator)))
		}
		path, err := zenity.SelectFile(opts...)
		if errors.Is(err, zenity.ErrCanceled) {
			return nil, nil // 取消 → JSON null
		}
		if err != nil {
			return nil, err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		return parseSaveFile(data, filepath.Base(path))
	}); err != nil {
		return err
	}

	// 自动查找：返回 JSON 数组（可能为空），扫描失败才返回错误。
	if err := bind("__nightreignLocateSaveFiles", func() ([]savefile.Location, error) {
		list, err := locateSaveFiles()
		if err != nil {
			return nil, err
		}
		if list == nil {
			list = []savefile.Location{}
		}
		return list, nil
	}); err != nil {
		return err
	}

	// 一键打开自动查找到的存档；路径不在查找结果里会被拒绝（见 readLocatedSave）。
	if err := bind("__nightreignOpenLocatedSave", func(path string) (*savefile.Payload, error) {
		return readLocatedSave(path)
	}); err != nil {
		return err
	}

	// 拖拽打开：解码 base64 后复用同一套解析逻辑。
	if err := bind("__nightreignParseSaveData", func(encoded, fileName string) (*savefile.Payload, error) {
		return parseSaveData(encoded, fileName)
	}); err != nil {
		return err
	}

	// 导出报告（文本 / CSV）。写法与 __nightreignExportCatalog 一致：
	// Documents 作为默认目录，取消返回 canceled，落盘走原子替换。
	if err := bind("__nightreignExportText", func(defaultName, content string) (exportResult, error) {
		name := savefile.SafeExportName(defaultName, "nightreign-report.txt")
		// 大小先挡一道，免得走完对话框才失败。
		if err := savefile.CheckExportSize(content); err != nil {
			return exportResult{}, err
		}
		filter := zenity.FileFilters{{Name: "文本文件", Patterns: []string{"*.txt"}, CaseFold: true}}
		if strings.EqualFold(filepath.Ext(name), ".csv") {
			filter = zenity.FileFilters{{Name: "CSV 表格", Patterns: []string{"*.csv"}, CaseFold: true}}
		}
		defaultPath := name
		if docs, err := windows.KnownFolderPath(windows.FOLDERID_Documents, 0); err == nil {
			defaultPath = filepath.Join(docs, name)
		}
		path, err := zenity.SelectFileSave(
			zenity.Title("导出存档检查报告"),
			zenity.Filename(defaultPath),
			zenity.ConfirmOverwrite(),
			filter,
			owner,
		)
		if errors.Is(err, zenity.ErrCanceled) {
			return exportResult{Canceled: true}, nil
		}
		if err != nil {
			return exportResult{}, err
		}
		// UTF-8 BOM 要按用户最终选定的扩展名决定，不是按建议名：对话框里把
		// .txt 改存成 .csv 时，落盘的 CSV 也要带 BOM（Excel 才不乱码）。
		data, err := savefile.TextFileBytes(filepath.Base(path), content)
		if err != nil {
			return exportResult{}, err
		}
		if err := writeFileAtomic(path, data, 0o600); err != nil {
			return exportResult{}, err
		}
		return exportResult{Canceled: false, FilePath: path}, nil
	}); err != nil {
		return err
	}

	if err := bind("__nightreignLoadRelicData", func() (json.RawMessage, error) {
		return json.RawMessage(relicData), nil
	}); err != nil {
		return err
	}

	// 新页面数据：未知名称或空内容返回 JSON null，渲染层的 getGameData 会把它
	// 当作「数据未内置」处理，不抛错。
	if err := bind("__nightreignLoadGameData", func(name string) (json.RawMessage, error) {
		data, ok := gameData[name]
		if !ok || len(data) == 0 {
			return json.RawMessage("null"), nil
		}
		return json.RawMessage(data), nil
	}); err != nil {
		return err
	}

	return nil
}
