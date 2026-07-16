# 第三方数据与许可说明

夜幕验物是非官方社区工具，不隶属于 FromSoftware、Bandai Namco Entertainment 或原参考网站。游戏名称与游戏内简体中文效果文本的权利归其各自权利方所有。

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

## Smithbox

- 项目：https://github.com/vawser/Smithbox
- 参考修订：`b1b644a770f8cc4c8cab452da3a72ff7b91e105a`
- 用途：确认 `compatibilityId` 的参数语义
- 许可：MIT License

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
