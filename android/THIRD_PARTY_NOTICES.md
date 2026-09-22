# Android 版第三方组件说明

夜幕验物 Android 版整体以 GNU GPL v3.0 发布（见仓库根 `LICENSE`）。

## 运行时依赖（均为 Apache License 2.0）

- **AndroidX / Jetpack Compose / Material 3**（androidx.compose、androidx.activity、
  androidx.core、androidx.datastore 等）— The Android Open Source Project
- **Kotlin 标准库与协程**（org.jetbrains.kotlin / kotlinx-coroutines）— JetBrains s.r.o. 及贡献者
- **kotlinx.serialization**（kotlinx-serialization-json）— JetBrains s.r.o. 及贡献者

Apache License 2.0 全文见 https://www.apache.org/licenses/LICENSE-2.0

## 词条数据

内置词条库 `nightreign-affixes-v1.03.4.json` 与桌面端同源，来源与许可见仓库根
`windows/THIRD_PARTY_NOTICES.md`、`macos/THIRD_PARTY_NOTICES.md` 与
`macos/DataSources/PROVENANCE.md`。桌面端 v0.3.0 新增的三套游戏数据集
（bosses / skills / buffs）**没有**打进 Android 版，本包内只有上述词条库。

夜幕验物是非官方社区工具，不隶属于 FromSoftware、Bandai Namco Entertainment
或原参考网站。应用内置的游戏参数数值与游戏内简体中文 / 英文文本均来自
《艾尔登法环 黑夜君临》本体，其权利归 FromSoftware、Bandai Namco Entertainment
等各自权利方所有；本仓库不分发游戏文件本身，这些数据只用于本工具的离线展示与
合法性校验。
