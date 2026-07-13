# 遗物词条数据集：来源与计数

生成文件：`affixes.json`  
目标数据版本：v1.03.4 + DLC1  
生成时间：2026-07-10T01:36:40+00:00

## 可直接用于第一版普通遗物检查器的规则

- 下拉列表过滤：`eligibleForNormalChecker == true`（共 340 条）。
- 三条词条必须是三个不同 `effectId`，且非 `-1` 的 `compatibilityId` 两两不同。
- 正确显示／存档顺序：按 `(sortId, effectId)` 升序；`sortId` 就是游戏参数的 `overrideEffectId`。
- 普通随机遗物的红、蓝、黄、绿四种颜色使用相同词条池，颜色不改变组合合法性。
- 旧池为 100/200/300，共 290 条；当前池为 110/210/310，共 340 条。三个槽的候选集合相同，仅权重不同。
- 30 个远征奖励池的当前可抽候选集合也都与上述 340 条完全相同；商店 72 行、远征奖励 360 行中，每一种池序列都覆盖红蓝黄绿四色。

## 计数

- 数据记录：527
- 普通旧池可抽：290
- 普通当前池可抽：340
- 深夜正面可抽：332
- 深夜 A 池且需要负面词条：49
- 深夜负面词条：24
- 固定／参考词条（不能进入随机普通检查器）：30
- 官方简中 FMG 直接命名：527
- QuickRef／旧 API 补名：0
- 仍无名称：0
- 带 QuickRef 分类／说明：520
- 带旧站热门查询量：19

## 来源

1. 游戏参数、简中 FMG：[0d2ad1494c37](https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor/tree/0d2ad1494c372098e689c23159656df70ff2d76d)。参数文件最后更新于 2026-01，QuickRef 同期提交明确标注为 v1.03.4 数据。
2. 说明与分类：[3e23450094c1](https://github.com/xxiixi/NightreignQuickRef/tree/3e23450094c18125ae5665927ed240b18189a040)。
3. 参数字段语义：[Smithbox Nightreign annotations](https://github.com/vawser/Smithbox/blob/b1b644a770f8cc4c8cab452da3a72ff7b91e105a/src/Smithbox.Data/Assets/PARAM/NR/Param%20Annotations/English/ATTACHEFFECT_PARAM_ST.json)。其中明确说明相同 `compatibilityId` 不能同时出现在同一遗物／武器；`exclusivityId` 只控制已装备遗物间的红色感叹号提示，不能拿来判定单件遗物组合。
4. 热度与旧称：Wayback 保存的 [`relics-with-ID`](https://web.archive.org/web/20260312030547id_/https://elden-api-v2.dingdangmarket.com/relics-with-ID) 与 [`hot-relics`](https://web.archive.org/web/20260312030548id_/https://elden-api-v2.dingdangmarket.com/hot-relics)，快照日期 2026-03-12。

游戏参数决定合法性；QuickRef 与旧站数据只用于展示、别名、说明和热度，不覆盖参数字段。

许可提示：Save Editor 与 Smithbox 为 MIT；NightreignQuickRef 为 GPL-3.0。公开分发内嵌 QuickRef 说明的版本时，应保留来源、许可证并履行 GPL 要求；游戏 FMG 文本仍受游戏权利方权利约束。此处仅记录来源，不构成法律意见。

## 合并异常／保守处理

- QuickRef 中有 11 个 ID 已不在当前 `AttachEffectParam`，已排除：6800000, 6800200, 6810100, 6850000, 6850100, 7033300, 7043900, 7331600, 7341600, 7351600, 7370500。
- 热门词条成功按旧 API 的 effect ID 唯一匹配 19 条；歧义 0 条；未匹配 1 条。
- 未匹配热门项：加快累积绝招量表＋３。
- 旧站 20 个热门组合中，19 个能唯一还原为 effect ID；其中按 `(sortId, effectId)` 排序正确 19 个，`compatibilityId` 两两不同 19 个。其余 1 个因旧站名称无法唯一映射而未用于结论。
- 对深夜遗物，本数据保留 A/B/C 池和诅咒标记，但第一版普通检查器不应显示 `isCurse == true` 或 `eligibleNormalCurrent == false` 的记录。
