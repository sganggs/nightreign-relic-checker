package savefile

import (
	"encoding/base64"
	"reflect"
	"strings"
	"testing"
)

func TestParseBase64Fixture(t *testing.T) {
	raw := buildFixture(t)
	encoded := base64.StdEncoding.EncodeToString(raw)

	payload, err := ParseBase64(encoded, "NR0000.sl2")
	if err != nil {
		t.Fatalf("ParseBase64: %v", err)
	}
	direct, err := Parse(raw, "NR0000.sl2")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if !reflect.DeepEqual(payload, direct) {
		t.Fatalf("拖拽解析结果与直接解析不一致：\n%+v\n%+v", payload, direct)
	}
}

func TestParseBase64FileName(t *testing.T) {
	encoded := base64.StdEncoding.EncodeToString(buildFixture(t))

	cases := map[string]string{
		`C:\Users\a\AppData\Roaming\Nightreign\1\NR0000.sl2`: "NR0000.sl2",
		"/tmp/NR0000.co2": "NR0000.co2",
		"  NR0000.sl2  ":  "NR0000.sl2",
		"":                "拖入的存档",
		"   ":             "拖入的存档",
	}
	for input, want := range cases {
		payload, err := ParseBase64(encoded, input)
		if err != nil {
			t.Fatalf("ParseBase64(%q): %v", input, err)
		}
		if payload.FileName != want {
			t.Errorf("fileName(%q) = %q，期望 %q", input, payload.FileName, want)
		}
	}
}

func TestParseBase64ToleratesWhitespace(t *testing.T) {
	encoded := base64.StdEncoding.EncodeToString(buildFixture(t))
	var wrapped strings.Builder
	for i := 0; i < len(encoded); i += 76 {
		end := i + 76
		if end > len(encoded) {
			end = len(encoded)
		}
		wrapped.WriteString(encoded[i:end])
		wrapped.WriteString("\r\n")
	}
	if _, err := ParseBase64(wrapped.String(), "NR0000.sl2"); err != nil {
		t.Fatalf("带换行的 base64 应能解析：%v", err)
	}
}

func TestParseBase64Errors(t *testing.T) {
	cases := []struct {
		name    string
		encoded string
		want    string
	}{
		{"空输入", "", "没有读到文件内容"},
		{"只有空白", " \n\t ", "没有读到文件内容"},
		{"非 base64", "这不是 base64!!!", "文件内容编码无效"},
		{"不是存档", base64.StdEncoding.EncodeToString([]byte("PNG\r\n\x1a\n随便什么文件")), "不是有效的存档文件"},
		{"截断的存档", base64.StdEncoding.EncodeToString([]byte("BND4")), "文件头不完整"},
	}
	for _, item := range cases {
		t.Run(item.name, func(t *testing.T) {
			payload, err := ParseBase64(item.encoded, "x.sl2")
			if err == nil {
				t.Fatalf("期望报错，得到 %+v", payload)
			}
			if !strings.Contains(err.Error(), item.want) {
				t.Fatalf("错误信息 %q 不含 %q", err.Error(), item.want)
			}
		})
	}
}

func TestParseBase64RejectsOversize(t *testing.T) {
	// 不真的造 96MB 数据：直接给一个超过编码长度上限的串，尺寸防御应先生效。
	huge := strings.Repeat("A", base64.StdEncoding.EncodedLen(MaxSaveDataBytes)+8)
	if _, err := ParseBase64(huge, "NR0000.sl2"); err == nil || !strings.Contains(err.Error(), "文件过大") {
		t.Fatalf("超大输入应被拒绝，得到 %v", err)
	}
}
