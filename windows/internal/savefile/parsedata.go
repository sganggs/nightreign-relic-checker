// 拖拽打开存档的平台无关实现。
//
// WebView2 里 File.path 取不到，所以渲染层用 FileReader 把拖进来的文件读成
// ArrayBuffer 再转 base64，经 parseSaveData 绑定送到这里解码，复用 Parse 的
// 解析逻辑。这里只解码与做尺寸/名字的防御，不写任何文件。
package savefile

import (
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
)

// MaxSaveDataBytes 是允许解码的存档大小上限。正常存档只有几 MB，这里留足余量，
// 同时挡住把整个大文件塞进桥接通道的情况。
const MaxSaveDataBytes = 96 << 20

// ParseBase64 解码 base64 并解析存档。fileName 只用于回显，会被裁成纯文件名。
func ParseBase64(encoded, fileName string) (*Payload, error) {
	cleaned := stripASCIIWhitespace(encoded)
	if cleaned == "" {
		return nil, errors.New("没有读到文件内容")
	}
	if len(cleaned) > base64.StdEncoding.EncodedLen(MaxSaveDataBytes) {
		return nil, fmt.Errorf("文件过大：超过 %d MB 的上限", MaxSaveDataBytes>>20)
	}
	data, err := base64.StdEncoding.DecodeString(cleaned)
	if err != nil {
		return nil, errors.New("文件内容编码无效")
	}
	if len(data) > MaxSaveDataBytes {
		return nil, fmt.Errorf("文件过大：超过 %d MB 的上限", MaxSaveDataBytes>>20)
	}
	return Parse(data, DisplayFileName(fileName))
}

// DisplayFileName 从可能带路径的名字里取出文件名部分，并在拿不到名字时给一个
// 占位，供回显使用。
func DisplayFileName(name string) string {
	if base := baseName(name); base != "" {
		return base
	}
	return "拖入的存档"
}

// baseName 取路径的最后一段（同时认 / 和 \，因为拖拽来源不一定是 Windows
// 写法），拿不到有效名字时返回空串。
func baseName(name string) string {
	trimmed := strings.TrimSpace(name)
	if idx := strings.LastIndexAny(trimmed, `/\`); idx >= 0 {
		trimmed = trimmed[idx+1:]
	}
	trimmed = strings.TrimSpace(trimmed)
	if trimmed == "." || trimmed == ".." {
		return ""
	}
	return trimmed
}

// stripASCIIWhitespace 去掉 base64 串里可能夹带的换行/空白（btoa 不产生，
// 但别的来源可能有），其余字符原样交给解码器判断。
func stripASCIIWhitespace(value string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case ' ', '\t', '\r', '\n':
			return -1
		}
		return r
	}, value)
}
