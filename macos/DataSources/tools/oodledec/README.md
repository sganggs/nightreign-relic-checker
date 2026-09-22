# oodledec

`extract_msg.py` 解 KRAK（Oodle Kraken）压缩时用的小工具。黑夜君临的归档用 Oodle 2.9
压缩，开源解码器 ooz（对应 2.7）解不开，因此这里直接借用游戏目录自带的
`oo2core_9_win64.dll`：把本程序交叉编译成 Windows 可执行文件，在 CrossOver / Wine 的
Steam bottle 里运行。

```bash
cd macos/DataSources/tools/oodledec
GOOS=windows GOARCH=amd64 go build -o oodledec.exe .
```

调用约定：`oodledec.exe <oo2core_9_win64.dll> <in.krak> <out.bin> <解压后字节数>`。
在 Wine 下路径写成 `Z:\...` 形式；`extract_msg.py --krak-cmd` 的模板里可用
`{win_in}` `{win_out}` `{size}` 占位符，例如：

```
"<CrossOver.app>/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wine" \
  --bottle Steam --no-gui "Z:\path\to\oodledec.exe" \
  "Z:\...\ELDEN RING NIGHTREIGN\Game\oo2core_9_win64.dll" {win_in} {win_out} {size}
```

编译产物 `*.exe` 已被仓库 .gitignore 排除。
