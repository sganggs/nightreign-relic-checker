package main

import "testing"

func TestFileURL(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{`C:\a\b.html`, "file:///C:/a/b.html"},
		{`C:\Users\user\AppData\Local\NightreignRelicChecker\ui\v0.1.1\index.html`,
			"file:///C:/Users/user/AppData/Local/NightreignRelicChecker/ui/v0.1.1/index.html"},
		{`C:\a b\c.html`, "file:///C:/a%20b/c.html"},
		{`C:\用户\索引.html`, "file:///C:/%E7%94%A8%E6%88%B7/%E7%B4%A2%E5%BC%95.html"},
	}
	for _, tc := range cases {
		if got := fileURL(tc.in); got != tc.want {
			t.Errorf("fileURL(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
