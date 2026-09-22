# 第三方数据与许可说明

夜幕验物是非官方社区工具，不隶属于 FromSoftware、Bandai Namco Entertainment 或原参考网站。应用内置的游戏参数数值与游戏内简体中文 / 英文文本均来自《艾尔登法环 黑夜君临》本体，其权利归 FromSoftware、Bandai Namco Entertainment 等各自权利方所有；本仓库不分发游戏文件本身，这些数据只用于本工具的离线展示与合法性校验。

## Elden Ring Nightreign Save Editor

- 项目：https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor
- 数据修订：`0d2ad1494c372098e689c23159656df70ff2d76d`
- 用途：游戏参数导出、官方简体中文 FMG、合法性实现交叉验证；
  「存档检查」的存档格式（BND4 容器 / AES-CBC / 遗物记录布局）解析
  按其实现移植（`RelicCore/SaveFile.swift`），遗物物品表数据（`Resources/relics.json`，
  由 `EquipParamAntique`、`AttachEffectTableParam`、`AntiqueName` FMG 经
  `DataSources/generate_relics.py` 生成）与深夜遗物正负词条配对规则
  亦以其校验器实现为参考
- 许可：MIT License

MIT License

Copyright (c) the Elden Ring Nightreign Save Editor contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## NightreignQuickRef

- 项目：https://github.com/xxiixi/NightreignQuickRef
- 数据修订：`3e23450094c18125ae5665927ed240b18189a040`
- 用途：中文分类、效果说明、叠加性与别名
- 许可：GNU General Public License v3.0

本发行版整体以 GPL-3.0 发布，完整许可证见 `LICENSE`（应用包内为 `Contents/Resources/LICENSE.txt`）；可修改的词条数据以 JSON 形式随应用与源码一并提供。

## Smithbox / Paramdex（NR、ER）

- 项目：https://github.com/vawser/Smithbox
- 参考修订：`b1b644a770f8cc4c8cab452da3a72ff7b91e105a`（词条库时期：确认 `compatibilityId`
  的参数语义）与 `f5969c060cea240476e9dd4d6a64eafa9dbafaab`（v0.3.0 的三套游戏数据集）
- 用途：`src/Smithbox.Data/Assets/PARAM/` 下的 Paramdex——NR 的 paramdef（字段布局，
  按容器版本号 10350000 做版本感知过滤）、`Param Row Names/English`（英文参数行名）、
  `Param Meta`（字段的 Enum / Refs 标注）与 `Param Enums`（`WEP_TYPE`、`RARITY`、
  `ATKPARAM_ATKATTR_TYPE`、`MAGIC_CATEGORY`、`ATK_SUB_CATEGORY`、`SP_EFFECT_TYPE`、
  `SP_EFFECT_SPCATEGORY`、`EFFECTIVE_AFFINITY` 等）；ER 的 `Defs/SpEffect.xml` 仅取其
  日文字段说明作语义参考（NR paramdef 是精简版、不含说明）；`EldenRingNightreignDictionary.txt`
  用于核验归档条目的命中率
- **派生数据说明**：`Resources/bosses.json`、`skills.json`、`buffs.json` 是用上述 Paramdex
  元数据解析本机游戏参数表得到的**派生数据**——其中的英文行名、字段名与枚举标签来自
  Paramdex，数值本身来自游戏参数表，中文标签为本项目翻译。所需的枚举与行名表已转写进
  `DataSources/generate_*.py` 的常量表，生成过程不联网
- 许可：MIT License（Copyright (c) the Smithbox contributors），条款内容与上面 Save Editor
  一节引用的 MIT 全文相同

## 游戏参数与游戏内文本（本机导出）

- 来源：本机已安装的《艾尔登法环 黑夜君临》，`regulation.bin` 容器版本号 `10350000`
  （即 regulation 1.03.5，exe 1.3.3.0）与游戏归档中的 msg（简中 / 英文 FMG）
- 导出工具：本仓库的 `DataSources/dump_regulation.py`、`DataSources/extract_msg.py` 与
  `DataSources/tools/oodledec`（借游戏自带的 `oo2core_9_win64.dll` 解 Oodle Kraken 压缩，
  macOS 下经 CrossOver / Wine 调用）
- 解密所用常量：`regulation.bin` 的 AES 密钥与归档 `.bhd` 的 RSA 公钥取自 UXM /
  BinderTool / Smithbox 等公开工具长期公布的常量（`Keys.NR_REGULATION_KEY`、
  `Keys.NightreignKeys`）。这些解密只发生在开发者本机的数据生成阶段：分发的程序里
  没有这些密钥，运行时既不读取也不修改游戏安装目录下的任何文件，只读入上面生成的 JSON
  （「存档检查」解密的是玩家自己的存档文件，同样只读、不写回）
- 权利：导出的原始参数表与文本受游戏权利方权利约束，**不随本仓库或本程序分发**
  （`DataSources/raw/` 已在 `.gitignore` 中）；随程序分发的只有经过筛选、重排并加注中文
  标签的数值 JSON，用途限于本工具的离线展示与校验
- 完整的来源表、字段映射、推断部分与已知局限见 `DataSources/PROVENANCE.md`

## 叮当市场旧站公开 API 归档

- 原网站：https://elden.dingdangmarket.com
- Wayback 快照：2026-03-12
- 用途：恢复 19 条热门词条查询次数与历史别名；不包含原站源代码、品牌素材或用户数据

## 规则实现说明

应用中的校验器为独立 Swift 实现，依据公开游戏参数事实重建：

1. 三条词条必须在所选版本的非零权重池；
2. `effectId` 不能重复；
3. 非 `-1` 的 `compatibilityId` 不能重复；
4. 保存顺序按 `(overrideEffectId, effectId)` 升序。

应用不修改游戏存档，不绕过反作弊，也不与游戏服务器通信。
