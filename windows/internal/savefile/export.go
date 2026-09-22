// 「导出报告」绑定（exportText）用到的平台无关小工具：文件名消毒与文本编码。
// 报告正文由渲染层生成，这里只负责落盘前的处理。
//
// 放在本包而不是 package main，是为了能在任意系统上跑单元测试
// （package main 依赖 Win32 API，只在 GOOS=windows 下可编译）。
package savefile

import (
	"fmt"
	"strings"
)

// MaxExportBytes 是报告正文的大小上限（远超正常报告体积，仅作防御）。
const MaxExportBytes = 32 << 20

// utf8BOM 让 Excel 以 UTF-8 打开 CSV，否则中文会乱码。
var utf8BOM = []byte{0xEF, 0xBB, 0xBF}

// invalidNameChars 是 Windows 文件名里不允许出现的字符。
const invalidNameChars = `<>:"/\|?*`

// SafeExportName 把建议文件名收拾成能直接喂给保存对话框的纯文件名：去掉目录
// 部分与非法字符、去掉首尾空白和点号、限制长度；为空时退回 fallback。
//
// 注意：词条库导出（exportCatalog）用的是 catalog.go 里的 safeSuggestedName，
// 两者故意不合并——后者是 Electron 版同名函数的逐行移植，连 String.trim 的
// 空白集合、180 个 UTF-16 code unit 的截断长度、把 \ / 就地换成 '_' 这些细节都
// 要求逐字节一致（catalog_test.go / edge_test.go 就是按这个断言的），用来保证
// 从 Electron 迁过来的用户导出的文件名不变。本函数是新导出路径的规则，可以按
// 需要调整；改动任一处时看一眼另一处即可。
func SafeExportName(suggested, fallback string) string {
	name := strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7F || strings.ContainsRune(invalidNameChars, r) {
			return '-'
		}
		return r
	}, baseName(suggested))
	name = strings.Trim(name, " .")
	if runes := []rune(name); len(runes) > 120 {
		name = strings.Trim(string(runes[:120]), " .")
	}
	if name == "" {
		return fallback
	}
	return name
}

// NormalizeCRLF 把混杂的换行统一成 CRLF，便于在记事本 / Excel 里打开。
func NormalizeCRLF(content string) string {
	normalized := strings.ReplaceAll(content, "\r\n", "\n")
	normalized = strings.ReplaceAll(normalized, "\r", "\n")
	return strings.ReplaceAll(normalized, "\n", "\r\n")
}

// CheckExportSize 只做大小校验，供调用方在打开保存对话框之前先挡一道。
func CheckExportSize(content string) error {
	if len(content) > MaxExportBytes {
		return fmt.Errorf("报告内容过大：超过 %d MB 的上限", MaxExportBytes>>20)
	}
	return nil
}

// TextFileBytes 返回写盘用的字节：统一 CRLF，.csv 额外加 UTF-8 BOM。
// fileName 要用用户最终选定的路径的文件名（而不是建议名），BOM 才会跟着真实
// 扩展名走。
func TextFileBytes(fileName, content string) ([]byte, error) {
	if err := CheckExportSize(content); err != nil {
		return nil, err
	}
	body := []byte(NormalizeCRLF(content))
	if strings.EqualFold(extOf(fileName), ".csv") {
		return append(append([]byte{}, utf8BOM...), body...), nil
	}
	return body, nil
}

func extOf(name string) string {
	if idx := strings.LastIndex(name, "."); idx >= 0 {
		return name[idx:]
	}
	return ""
}
