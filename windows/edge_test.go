package main

import (
	"errors"
	"strings"
	"testing"
)

func TestWrapErr(t *testing.T) {
	if wrapErr(chImport, nil) != nil {
		t.Fatal("wrapErr(nil) must be nil")
	}

	// assertCatalog was a TypeError in Electron.
	got := wrapErr(chExport, errInvalidCatalog).Error()
	want := "Error invoking remote method 'catalog:export': TypeError: 词条库格式无效：顶层必须是对象，并包含 affixes 数组。"
	if got != want {
		t.Errorf("TypeError wrap:\n got %q\nwant %q", got, want)
	}

	// Every other rejection was a plain Error.
	got = wrapErr(chLoad, errors.New("无法解析 JSON 词条库：x.json")).Error()
	want = "Error invoking remote method 'catalog:load': Error: 无法解析 JSON 词条库：x.json"
	if got != want {
		t.Errorf("Error wrap:\n got %q\nwant %q", got, want)
	}
}

func TestSafeSuggestedNameEdgeCases(t *testing.T) {
	const bom = "\uFEFF"
	const nel = "\u0085"
	emoji := "\U0001F600" // astral char: UTF-16 surrogate pair D83D DE00

	cases := []struct {
		name string
		in   string
		want string
	}{
		// U+FEFF is stripped by JS trim (Go's unicode.IsSpace is not enough).
		{"leading BOM trimmed", bom + "data", "data.json"},
		{"trailing BOM trimmed", "data" + bom, "data.json"},
		// U+0085 (NEL) is NOT stripped by JS trim, and is >0x1F so it survives.
		{"NEL preserved", nel + "data", nel + "data.json"},
		// Truncating across a surrogate pair must not yield U+FFFD.
		{"surrogate split avoids U+FFFD",
			strings.Repeat("a", 179) + emoji,
			strings.Repeat("a", 179) + ".json"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := safeSuggestedName(tc.in)
			if got != tc.want {
				t.Errorf("safeSuggestedName(%q) = %q, want %q", tc.in, got, tc.want)
			}
			if strings.ContainsRune(got, '�') {
				t.Errorf("result %q contains U+FFFD replacement char", got)
			}
		})
	}
}
