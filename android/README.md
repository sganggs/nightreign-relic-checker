# 夜幕验物 Android

> **版本说明（仓库 v0.3.0）**：本轮只做桌面双端的新功能与文档收尾，**Android 版没有任何新功能**，
> `versionName` 仍是 **0.2.1**，Release 附件也仍是 `NightreignRelicChecker-Android-v0.2.1.apk`。
> 桌面端 v0.3.0 新增的「首领数据」「角色属性」「词条反查」「增伤排名」四页与存档检查的四项增强
> （自动查找、拖拽打开、导出报告、存档对比）都不在手机版里。内置词条库与判定规则与桌面端同源，未变。

Android 首版是一个完全离线、手机优先的三词条手动验物工具。包名为
`com.nightreign.relicchecker`，使用 Kotlin、Jetpack Compose、Material 3 与 Preferences DataStore。
界面沿用桌面版的深黑紫色视觉语言，并针对手机的触控、底部导航和底部抽屉重新布局。

## 已实现

- 三词条手动检查，支持“普通 1.03”“普通旧池”“深夜正面”“顺序/互斥”四种口径。
- `effectId` 去重、非 `-1` 的 `compatibilityId` 互斥、槽池一一分配，以及
  `(sortId, effectId)` 规范排序。
- 深夜正面使用 AAA、AAB、ABB、BBB、AAC、ACC、CCC 七种真实三槽模板；界面始终说明这只是正面预检，完整遗物仍需验证具体遗物 ID 与负面词条逐行配对。
- 三个全宽词条槽、支持名称/别名/分类/effectId 的归一化搜索、合法随机组合、规范排序与清空。
- 词条库浏览、搜索、模式过滤、高密度列表与底部抽屉详情。
- 设置页可持久化默认模式、自动检查、选择器默认过滤和词条库紧凑显示。
- 设置页同时展示离线与隐私说明、GPL、数据版本、来源和真实记录数。
- Manifest 未声明 `android.permission.INTERNET`。

## 工程结构

工程采用三个模块，避免 Android UI 与规则、数据解析相互耦合：

- `:rules`：纯 Kotlin。包含领域模型、四种模式、合法性检查、搜索归一化和随机组合。
- `:catalog`：纯 Kotlin + kotlinx.serialization。负责校验并解析权威词条 JSON，依赖 `:rules`。
- `:app`：Android/Compose UI 与 DataStore 设置，依赖前两个模块。

根目录 `data/` 是唯一权威数据源。没有在 Android 工程中复制 JSON：

- `:app` 的 `main` assets source set 指向 `../../data`；
- `:catalog` 的 `test` resources source set 指向 `../../data`。

因此更新根数据后，重新构建 APK 和运行测试即可使用同一份数据。

## 发布构建与签名

`./gradlew assembleRelease` 产出未签名 APK；正式发布使用 `zipalign` 对齐后以
`apksigner` 签名（签名密钥不入库）。同一签名密钥必须长期保留，否则已安装用户
无法覆盖升级。第三方组件许可见 `THIRD_PARTY_NOTICES.md`。

## 工具链

- Android Gradle Plugin 8.13.2
- Gradle Wrapper 8.13
- Kotlin / Compose Compiler Plugin 2.2.20
- compileSdk / targetSdk 36
- minSdk 26
- Java 17 字节码目标（可使用 JDK 17 或更新 JDK 构建）

本机需安装 Android SDK Platform 36，并配置 `ANDROID_HOME` / `ANDROID_SDK_ROOT`，或在未提交的
`local.properties` 中设置 `sdk.dir`。

## 构建与测试

在本目录运行：

```bash
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

根 `testDebugUnitTest` 任务会同时执行 `:rules:test`、`:catalog:test` 与
`:app:testDebugUnitTest`。当前 JVM 测试覆盖：

- 合法、重复 effectId、互斥冲突与 `-1` 豁免；
- 池外词条、槽池模板不匹配和一一分配；
- 七个深夜模板、非法 ABC 模板与深夜警告；
- `(sortId, effectId)` 排序、随机组合与通用模式；
- 搜索的大小写、重音、全半角、标点、别名、分类与 ID 归一化；
- 直接读取根数据得到 527 条总记录、340 条当前普通池和 290 条旧普通池等固定事实。

Debug APK 输出到 `app/build/outputs/apk/debug/app-debug.apk`。

## 与桌面版的差异

本轮优先交付稳定的手动验物 MVP。Android 首版不解析 `.sl2` / `.co2`，也没有不可用的存档按钮；
桌面端的具体遗物 ID、正负词条配对、唯一遗物重复等存档审计功能尚未移植。后续如移植，应使用
Android Storage Access Framework 做只读文件选择，并复用桌面端对拍用例，不能把“深夜正面”预检当作完整存档结论。

桌面端 v0.3.0 还新增了四个基于游戏参数表的数据页（首领数据 / 角色属性 / 词条反查 / 增伤排名），
手机版同样没有。其中「角色属性」是 10 个夜行者 1–15 级的属性与派生值表，含转职遗物与利普拉的交易；
「首领数据」按出场场合分组（夜王 / 守夜首领 / 据点首领 / 场景头目 / 封印监牢 / 其它场合，可多重归属），
简中名只按本作游戏文本对照、深夜按深度 1–5 分档、变异个体倍率可连乘、多人缩放按敌人档位差别很大；
「增伤排名」是自己组一套局内配置（常规 / 深夜、局内武器词条、遗物、护符、其它增益）看总增伤，
自组遗物复用词条检查的合法性规则。这四页依赖 `data/` 下约 6.3 MB 的新数据集
（`nightreign-{bosses,skills,buffs,heroes}-v1.03.5.json`），如果后续要移植，建议先评估 APK 体积
与低端机的解析耗时，并沿用 `macos/DataSources/PROVENANCE.md` 里记录的数值口径与已知局限，
不要另起一套说法。

## 许可与数据来源

Android 版沿用仓库根目录的 GNU GPL v3.0。词条数据来源、修订与第三方许可记录在权威 JSON 的
`sources` 元数据、根 README 及现有第三方说明中；应用设置页会离线展示这些元数据。
