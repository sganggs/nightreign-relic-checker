// Catalog storage. Mirrors the behavior (paths, atomic writes and
// user-facing error messages) of the previous Electron main process.
package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"unicode"
	"unicode/utf16"
)

const (
	appDataDirectory = "NightreignRelicChecker"
	catalogFileName  = "affixes.json"
)

// errInvalidCatalog mirrors Electron's assertCatalog TypeError.
var errInvalidCatalog = errors.New("词条库格式无效：顶层必须是对象，并包含 affixes 数组。")

// errSyntax marks a JSON parse failure; callers wrap it with the file name.
var errSyntax = errors.New("json syntax error")

type catalogPayload struct {
	Catalog json.RawMessage `json:"catalog"`
	Origin  string          `json:"origin"`
}

type importResult struct {
	Catalog  json.RawMessage `json:"catalog"`
	FileName string          `json:"fileName"`
}

type saveResult struct {
	OK     bool   `json:"ok"`
	Origin string `json:"origin"`
}

type exportResult struct {
	Canceled bool   `json:"canceled"`
	FilePath string `json:"filePath,omitempty"`
}

// appDataDir returns %LOCALAPPDATA%\NightreignRelicChecker, matching the
// Electron shell (with os.UserConfigDir as the unlikely fallback).
func appDataDir() (string, error) {
	if local := os.Getenv("LOCALAPPDATA"); local != "" {
		return filepath.Join(local, appDataDirectory), nil
	}
	base, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, appDataDirectory), nil
}

func customCatalogPath() (string, error) {
	dir, err := appDataDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, catalogFileName), nil
}

// assertCatalogBytes validates the same invariants as Electron's
// assertCatalog: valid JSON whose top level is an object containing an
// "affixes" array.
func assertCatalogBytes(data []byte) error {
	if !json.Valid(data) {
		return errSyntax
	}
	var top map[string]json.RawMessage
	if err := json.Unmarshal(data, &top); err != nil {
		return errInvalidCatalog
	}
	affixes, ok := top["affixes"]
	if !ok {
		return errInvalidCatalog
	}
	trimmed := bytes.TrimSpace(affixes)
	if len(trimmed) == 0 || trimmed[0] != '[' {
		return errInvalidCatalog
	}
	return nil
}

// readCatalog loads and validates a catalog file. Parse failures carry the
// same message Electron produced: 无法解析 JSON 词条库：<file name>.
func readCatalog(path string) (json.RawMessage, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if err := assertCatalogBytes(data); err != nil {
		if errors.Is(err, errSyntax) {
			return nil, fmt.Errorf("无法解析 JSON 词条库：%s", filepath.Base(path))
		}
		return nil, err
	}
	return json.RawMessage(data), nil
}

// writeJSONAtomic writes the serialized catalog with a trailing newline via
// a same-directory temp file + rename, like Electron's writeJsonAtomic.
func writeJSONAtomic(path string, serialized string) error {
	if err := assertCatalogBytes([]byte(serialized)); err != nil {
		if errors.Is(err, errSyntax) {
			return errInvalidCatalog
		}
		return err
	}

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	var suffix [16]byte
	if _, err := rand.Read(suffix[:]); err != nil {
		return err
	}
	tmpPath := filepath.Join(dir, fmt.Sprintf(".%s.%d.%s.tmp", filepath.Base(path), os.Getpid(), hex.EncodeToString(suffix[:])))

	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(tmpPath)
		}
	}()

	f, err := os.OpenFile(tmpPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	if _, err := f.WriteString(serialized + "\n"); err != nil {
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
	if err := os.Rename(tmpPath, path); err != nil {
		return err
	}
	cleanup = false
	return nil
}

// loadCatalog prefers the custom catalog and falls back to the built-in
// one only when the custom file does not exist; any other failure (e.g. a
// corrupted custom file) propagates, matching Electron.
func loadCatalog(builtIn []byte) (catalogPayload, error) {
	path, err := customCatalogPath()
	if err != nil {
		return catalogPayload{}, err
	}
	catalog, err := readCatalog(path)
	if err == nil {
		return catalogPayload{Catalog: catalog, Origin: "custom"}, nil
	}
	if !errors.Is(err, fs.ErrNotExist) {
		return catalogPayload{}, err
	}
	return builtInPayload(builtIn)
}

// resetCatalog deletes the custom catalog and returns the built-in one.
func resetCatalog(builtIn []byte) (catalogPayload, error) {
	path, err := customCatalogPath()
	if err != nil {
		return catalogPayload{}, err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return catalogPayload{}, err
	}
	return builtInPayload(builtIn)
}

func builtInPayload(builtIn []byte) (catalogPayload, error) {
	if err := assertCatalogBytes(builtIn); err != nil {
		if errors.Is(err, errSyntax) {
			return catalogPayload{}, fmt.Errorf("无法解析 JSON 词条库：%s", catalogFileName)
		}
		return catalogPayload{}, err
	}
	return catalogPayload{Catalog: json.RawMessage(builtIn), Origin: "built-in"}, nil
}

// isJSWhitespace reports whether r is stripped by JavaScript's String.trim,
// whose set (ECMAScript WhiteSpace + LineTerminator) differs from Go's
// unicode.IsSpace in exactly two edge cases: it includes U+FEFF (BOM) and
// excludes U+0085 (NEL).
func isJSWhitespace(r rune) bool {
	if r == '\uFEFF' {
		return true
	}
	if r == '\u0085' {
		return false
	}
	return unicode.IsSpace(r)
}

// safeSuggestedName ports Electron's safeSuggestedName, including String.trim's
// whitespace set and the UTF-16 based 180 code-unit truncation of
// String.prototype.slice.
func safeSuggestedName(suggested string) string {
	const fallback = "nightreign-affixes.json"

	name := strings.TrimFunc(suggested, isJSWhitespace)
	if name == "" {
		return fallback
	}

	replaced := make([]rune, 0, len(name))
	for _, r := range name {
		switch {
		case r == '\\' || r == '/':
			replaced = append(replaced, '_')
		case r == '<' || r == '>' || r == ':' || r == '"' || r == '|' || r == '?' || r == '*' || r <= 0x1F:
			replaced = append(replaced, '_')
		default:
			replaced = append(replaced, r)
		}
	}
	name = strings.TrimRight(string(replaced), ". ")

	units := utf16.Encode([]rune(name))
	if len(units) > 180 {
		units = units[:180]
		// Avoid utf16.Decode mapping a split surrogate pair to U+FFFD: drop a
		// trailing unpaired high surrogate so the result stays a valid,
		// whole-character string. (Electron's slice keeps the lone surrogate,
		// but the real call path — a fixed "nightreign-affixes-<ver>.json"
		// name — never reaches 180 units, so this only guards the general API.)
		if n := len(units); units[n-1] >= 0xD800 && units[n-1] <= 0xDBFF {
			units = units[:n-1]
		}
	}
	name = string(utf16.Decode(units))

	if name == "" {
		return fallback
	}
	if !strings.HasSuffix(strings.ToLower(name), ".json") {
		name += ".json"
	}
	return name
}
