package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func setTempAppData(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("LOCALAPPDATA", dir)
	return filepath.Join(dir, appDataDirectory)
}

const validCatalog = `{"schemaVersion":1,"affixes":[{"effectId":1}]}`

func TestAssertCatalogBytes(t *testing.T) {
	cases := []struct {
		name    string
		data    string
		wantErr error
	}{
		{"valid", validCatalog, nil},
		{"valid empty affixes", `{"affixes":[]}`, nil},
		{"syntax error", `{"affixes":[`, errSyntax},
		{"top-level array", `[1,2,3]`, errInvalidCatalog},
		{"top-level string", `"hello"`, errInvalidCatalog},
		{"top-level null", `null`, errInvalidCatalog},
		{"missing affixes", `{"schemaVersion":1}`, errInvalidCatalog},
		{"affixes null", `{"affixes":null}`, errInvalidCatalog},
		{"affixes object", `{"affixes":{}}`, errInvalidCatalog},
		{"affixes number", `{"affixes":42}`, errInvalidCatalog},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := assertCatalogBytes([]byte(tc.data))
			if tc.wantErr == nil && err != nil {
				t.Fatalf("expected nil error, got %v", err)
			}
			if tc.wantErr != nil && err != tc.wantErr {
				t.Fatalf("expected %v, got %v", tc.wantErr, err)
			}
		})
	}
}

func TestBuiltInCatalogIsValid(t *testing.T) {
	if err := assertCatalogBytes(builtInCatalog); err != nil {
		t.Fatalf("embedded built-in catalog is invalid: %v", err)
	}
}

func TestReadCatalogParseErrorMessage(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "broken.json")
	if err := os.WriteFile(path, []byte("{oops"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := readCatalog(path)
	if err == nil || err.Error() != "无法解析 JSON 词条库：broken.json" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestWriteJSONAtomic(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "nested", "affixes.json")

	if err := writeJSONAtomic(path, validCatalog); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != validCatalog+"\n" {
		t.Fatalf("content mismatch: %q", got)
	}

	// Overwrite an existing file.
	second := `{"affixes":[]}`
	if err := writeJSONAtomic(path, second); err != nil {
		t.Fatal(err)
	}
	got, _ = os.ReadFile(path)
	if string(got) != second+"\n" {
		t.Fatalf("overwrite mismatch: %q", got)
	}

	// No stray temp files left behind.
	entries, _ := os.ReadDir(filepath.Dir(path))
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".tmp") {
			t.Fatalf("leftover temp file: %s", e.Name())
		}
	}

	// Invalid payloads are rejected before touching the disk.
	if err := writeJSONAtomic(path, `[]`); err != errInvalidCatalog {
		t.Fatalf("expected errInvalidCatalog, got %v", err)
	}
	if err := writeJSONAtomic(path, `{nope`); err != errInvalidCatalog {
		t.Fatalf("expected errInvalidCatalog for syntax error, got %v", err)
	}
}

func TestLoadCatalogFallsBackToBuiltIn(t *testing.T) {
	setTempAppData(t)
	builtIn := []byte(validCatalog)

	payload, err := loadCatalog(builtIn)
	if err != nil {
		t.Fatal(err)
	}
	if payload.Origin != "built-in" {
		t.Fatalf("expected built-in origin, got %s", payload.Origin)
	}
	if string(payload.Catalog) != validCatalog {
		t.Fatalf("catalog mismatch")
	}
}

func TestLoadCatalogPrefersCustom(t *testing.T) {
	appDir := setTempAppData(t)
	custom := `{"dataVersion":"custom","affixes":[]}`
	if err := os.MkdirAll(appDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(appDir, catalogFileName), []byte(custom), 0o600); err != nil {
		t.Fatal(err)
	}

	payload, err := loadCatalog([]byte(validCatalog))
	if err != nil {
		t.Fatal(err)
	}
	if payload.Origin != "custom" {
		t.Fatalf("expected custom origin, got %s", payload.Origin)
	}
	if string(payload.Catalog) != custom {
		t.Fatalf("catalog mismatch: %s", payload.Catalog)
	}
}

func TestLoadCatalogPropagatesCorruptCustom(t *testing.T) {
	appDir := setTempAppData(t)
	if err := os.MkdirAll(appDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(appDir, catalogFileName), []byte("{bad"), 0o600); err != nil {
		t.Fatal(err)
	}

	_, err := loadCatalog([]byte(validCatalog))
	if err == nil || err.Error() != "无法解析 JSON 词条库：affixes.json" {
		t.Fatalf("expected corrupt-custom error, got %v", err)
	}
}

func TestResetCatalogRemovesCustom(t *testing.T) {
	appDir := setTempAppData(t)
	customPath := filepath.Join(appDir, catalogFileName)
	if err := os.MkdirAll(appDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(customPath, []byte(validCatalog), 0o600); err != nil {
		t.Fatal(err)
	}

	payload, err := resetCatalog([]byte(validCatalog))
	if err != nil {
		t.Fatal(err)
	}
	if payload.Origin != "built-in" {
		t.Fatalf("expected built-in origin, got %s", payload.Origin)
	}
	if _, err := os.Stat(customPath); !os.IsNotExist(err) {
		t.Fatalf("custom catalog should be gone, stat err: %v", err)
	}

	// Reset with no custom file present must succeed too.
	if _, err := resetCatalog([]byte(validCatalog)); err != nil {
		t.Fatal(err)
	}
}

func TestSafeSuggestedName(t *testing.T) {
	longRuns := strings.Repeat("字", 200)
	cases := []struct {
		in   string
		want string
	}{
		{"", "nightreign-affixes.json"},
		{"   ", "nightreign-affixes.json"},
		{"data", "data.json"},
		{"data.JSON", "data.JSON"},
		{"nightreign-affixes-v1.03.4.json", "nightreign-affixes-v1.03.4.json"},
		{`a/b\c`, "a_b_c.json"},
		{`a<b>c:d"e|f?g*h`, "a_b_c_d_e_f_g_h.json"},
		{"name...  ", "name.json"},
		{"...", "nightreign-affixes.json"},
		{"\x01\x02", "__.json"},
		{longRuns, strings.Repeat("字", 180) + ".json"},
	}
	for _, tc := range cases {
		if got := safeSuggestedName(tc.in); got != tc.want {
			t.Errorf("safeSuggestedName(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestCatalogPayloadMarshalsRawJSON(t *testing.T) {
	payload := catalogPayload{Catalog: json.RawMessage(`{"affixes":[]}`), Origin: "built-in"}
	b, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	want := `{"catalog":{"affixes":[]},"origin":"built-in"}`
	if string(b) != want {
		t.Fatalf("got %s want %s", b, want)
	}

	// Export result shapes must match the Electron IPC contract.
	b, _ = json.Marshal(exportResult{Canceled: true})
	if string(b) != `{"canceled":true}` {
		t.Fatalf("canceled shape: %s", b)
	}
	b, _ = json.Marshal(exportResult{Canceled: false, FilePath: `C:\x.json`})
	if string(b) != `{"canceled":false,"filePath":"C:\\x.json"}` {
		t.Fatalf("export shape: %s", b)
	}
	b, _ = json.Marshal(saveResult{OK: true, Origin: "custom"})
	if string(b) != `{"ok":true,"origin":"custom"}` {
		t.Fatalf("save shape: %s", b)
	}
	var nilImport *importResult
	b, _ = json.Marshal(nilImport)
	if string(b) != `null` {
		t.Fatalf("nil import shape: %s", b)
	}
}
