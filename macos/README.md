# 夜幕验物（macOS）

《艾尔登法环 黑夜君临》三词条遗物离线合法性检查器。界面参考已失效的在线检查站，但数据和判定均在本机完成。

## 功能

- 严格检查普通遗物当前 1.03.4 + DLC 词条池（340 条）
- 可切换旧版 / 无 DLC 词条池（290 条）
- 检查重复 `effectId` 与 `compatibilityId` 互斥
- 按 `(overrideEffectId, effectId)` 给出正确保存顺序
- 搜索完整词条库、热门词条快捷填入、合法随机组合
- 导入 / 导出离线 JSON 词条库
- 按游戏参数中的七种真实三正面槽位模板预检深夜词条
- **存档检查**（v0.2.0）：只读解析 `.sl2` / `.co2` 存档，逐件校验全部角色的全部遗物（含深夜遗物正负词条配对、唯一遗物重复、保存顺序），指出非法遗物的种类与词条

## 运行

双击 `夜幕验物.app`。这是本地临时签名版本；若 macOS 首次阻止打开，请在 Finder 中右键应用并选择“打开”。

最低系统版本：macOS 13。发行包为 Universal 2，同时支持 Apple Silicon 与 Intel Mac。

## 从源码构建

```sh
swift run RelicCoreChecks
zsh Scripts/build_app.sh
```

产物位于 `build/夜幕验物.app`。

## 数据更新

应用词条库位于 `Sources/NightreignRelicChecker/Resources/affixes.json`，schema 版本为 1。应用内“数据设置”可以导入相同格式的 JSON。存档检查所用的遗物物品表位于同目录 `relics.json`（由 `DataSources/generate_relics.py` 生成，见 `DataSources/PROVENANCE.md`）。

## 许可

本项目以 GPL-3.0 发布。第三方数据、修订号及许可见 `THIRD_PARTY_NOTICES.md`。
