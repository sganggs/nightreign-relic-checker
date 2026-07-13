// window.nightreign bridge. Replaces the Electron preload + ipcMain pair
// with the same five methods and identical result shapes.
package main

import (
	"errors"
	"fmt"
	"path/filepath"

	"github.com/ncruces/zenity"
	"golang.org/x/sys/windows"
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
    }
  });
  // Parity with the hardened Electron shell: no popups, and dropping a
  // file onto the window must not navigate away from the app.
  window.open = function () { return null; };
  window.addEventListener('dragover', function (event) { event.preventDefault(); }, false);
  window.addEventListener('drop', function (event) { event.preventDefault(); }, false);
})();`

func registerBindings(w *shell, builtIn []byte) error {
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

	return nil
}
