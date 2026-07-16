// 临时调试工具：将存档解析结果导出为 JSON（仅本地调试用）。
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"nightreign/relicchecker/internal/savefile"
)

func main() {
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	payload, err := savefile.Parse(data, "NR0000.sl2")
	if err != nil {
		panic(err)
	}
	out, _ := json.Marshal(payload)
	fmt.Println(string(out))
}
