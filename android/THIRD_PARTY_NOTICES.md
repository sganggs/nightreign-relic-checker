# Android 版第三方组件说明

夜幕验物 Android 版整体以 GNU GPL v3.0 发布（见仓库根 `LICENSE`）。

## 运行时依赖（均为 Apache License 2.0）

- **AndroidX / Jetpack Compose / Material 3**（androidx.compose、androidx.activity、
  androidx.core、androidx.datastore 等）— The Android Open Source Project
- **Kotlin 标准库与协程**（org.jetbrains.kotlin / kotlinx-coroutines）— JetBrains s.r.o. 及贡献者
- **kotlinx.serialization**（kotlinx-serialization-json）— JetBrains s.r.o. 及贡献者

Apache License 2.0 全文见 https://www.apache.org/licenses/LICENSE-2.0

## 内置数据与移植来源

v0.3.0 起，APK 内置仓库根 `data/` 下的全部六个数据集，与桌面端是同一批文件：词条库
`nightreign-affixes-v1.03.4.json`、遗物物品表 `nightreign-relics-v1.03.4.json`，以及首领数据、
战技 / 法术 / 武器、增伤手段、角色属性四套参数表数据集（`nightreign-{bosses,skills,buffs,heroes}-v1.03.5.json`）。
各数据集的完整来源、修订与许可见仓库根 `windows/THIRD_PARTY_NOTICES.md`、`macos/THIRD_PARTY_NOTICES.md` 与
`macos/DataSources/PROVENANCE.md`，与本包相关的要点如下：

- **Elden Ring Nightreign Save Editor**（https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor，
  修订 `0d2ad1494c372098e689c23159656df70ff2d76d`，MIT）：词条库与遗物物品表的参数来源、官方简中 FMG；
  「存档检查」的存档格式（BND4 容器 / AES-CBC / 遗物记录布局）解析按其实现移植（经 Windows 端 `savefile.go`
  转写为 Kotlin）。
- **Smithbox / Paramdex**（https://github.com/vawser/Smithbox，修订 `f5969c060cea240476e9dd4d6a64eafa9dbafaab`，MIT）：
  四套参数表数据集里的英文行名、字段名与枚举标签来自 Paramdex，数值本身来自游戏参数表。
- **NightreignQuickRef**（https://github.com/xxiixi/NightreignQuickRef，修订 `3e23450094c18125ae5665927ed240b18189a040`，
  GPL-3.0）：词条的中文分类、效果说明、叠加性与别名。
- **游戏参数与游戏内文本**：本机已安装游戏的 `regulation.bin`（regulation 1.03.5）与 msg 归档导出后筛选生成，
  原始参数表与文本不随本包分发。

Elden Ring Nightreign Save Editor 与 Smithbox 的 MIT 许可条款如下（两者条款文字相同）：

```
MIT License

Copyright (c) the Elden Ring Nightreign Save Editor contributors
Copyright (c) the Smithbox contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

夜幕验物是非官方社区工具，不隶属于 FromSoftware、Bandai Namco Entertainment
或原参考网站。应用内置的游戏参数数值与游戏内简体中文 / 英文文本均来自
《艾尔登法环 黑夜君临》本体，其权利归 FromSoftware、Bandai Namco Entertainment
等各自权利方所有；本仓库不分发游戏文件本身，这些数据只用于本工具的离线展示与
合法性校验。
