package savefile

import (
	"bytes"
	"strings"
	"testing"
)

func TestSafeExportName(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"nightreign-save-report-20260304.txt", "nightreign-save-report-20260304.txt"},
		{`C:\Users\a\报告.csv`, "报告.csv"},
		{"报告/2026:03*04.txt", "2026-03-04.txt"},
		{"  存档报告.txt  ", "存档报告.txt"},
		{"...", "默认.txt"},
		{"", "默认.txt"},
		{"   ", "默认.txt"},
		{"a\x00b.txt", "a-b.txt"},
	}
	for _, item := range cases {
		if got := SafeExportName(item.in, "默认.txt"); got != item.want {
			t.Errorf("SafeExportName(%q) = %q，期望 %q", item.in, got, item.want)
		}
	}

	long := SafeExportName(strings.Repeat("名", 300)+".txt", "默认.txt")
	if runes := []rune(long); len(runes) > 120 {
		t.Errorf("超长名字未被截断：%d 个字符", len(runes))
	}
}

func TestNormalizeCRLF(t *testing.T) {
	got := NormalizeCRLF("a\nb\r\nc\rd")
	if got != "a\r\nb\r\nc\r\nd" {
		t.Errorf("NormalizeCRLF = %q", got)
	}
	if NormalizeCRLF("") != "" {
		t.Error("空串应保持为空")
	}
}

func TestTextFileBytes(t *testing.T) {
	txt, err := TextFileBytes("报告.txt", "第一行\n第二行")
	if err != nil {
		t.Fatalf("TextFileBytes: %v", err)
	}
	if bytes.HasPrefix(txt, utf8BOM) {
		t.Error(".txt 不应带 BOM")
	}
	if string(txt) != "第一行\r\n第二行" {
		t.Errorf("txt 内容 = %q", string(txt))
	}

	csv, err := TextFileBytes("报告.CSV", "角色,遗物\n甲,乙\n")
	if err != nil {
		t.Fatalf("TextFileBytes: %v", err)
	}
	if !bytes.HasPrefix(csv, utf8BOM) {
		t.Error(".csv 应带 UTF-8 BOM，否则 Excel 打开中文乱码")
	}
	if string(csv[len(utf8BOM):]) != "角色,遗物\r\n甲,乙\r\n" {
		t.Errorf("csv 内容 = %q", string(csv[len(utf8BOM):]))
	}
}

func TestTextFileBytesRejectsOversize(t *testing.T) {
	huge := strings.Repeat("x", MaxExportBytes+1)
	if _, err := TextFileBytes("报告.txt", huge); err == nil || !strings.Contains(err.Error(), "过大") {
		t.Fatalf("超大报告应被拒绝，得到 %v", err)
	}
}

// BOM 跟着传进来的文件名走：绑定层要传用户在保存对话框里最终选定的路径的
// 文件名，而不是建议名，否则把 .txt 改存成 .csv 就没有 BOM（Excel 乱码）。
func TestTextFileBytesFollowsGivenName(t *testing.T) {
	const content = "角色,遗物\n甲,乙\n"
	suggested := "nightreign-save-report-20261101-0130.txt"
	chosen := "我的报告.csv"

	if data, err := TextFileBytes(suggested, content); err != nil || bytes.HasPrefix(data, utf8BOM) {
		t.Errorf("按建议名 %q 不应带 BOM（err=%v）", suggested, err)
	}
	data, err := TextFileBytes(chosen, content)
	if err != nil {
		t.Fatalf("TextFileBytes: %v", err)
	}
	if !bytes.HasPrefix(data, utf8BOM) {
		t.Errorf("用户最终选的 %q 是 CSV，应带 BOM", chosen)
	}
	// 反过来：建议名是 .csv、用户存成 .txt，就不该平白带上 BOM。
	if data, err := TextFileBytes("报告.txt", content); err != nil || bytes.HasPrefix(data, utf8BOM) {
		t.Errorf(".txt 不应带 BOM（err=%v）", err)
	}
}

func TestCheckExportSize(t *testing.T) {
	if err := CheckExportSize(strings.Repeat("x", 1024)); err != nil {
		t.Errorf("正常大小不应报错：%v", err)
	}
	if err := CheckExportSize(strings.Repeat("x", MaxExportBytes+1)); err == nil {
		t.Error("超过上限应报错")
	}
}
