# 页面模块契约（Windows / WebView2 渲染层）

四个新页面 —— `bosses`（首领数据）、`heroes`（角色属性）、`lookup`（词条反查）、
`ranker`（增伤排名）—— 各自只由一对文件实现：

```
renderer/pages/<key>.js    页面逻辑（功能开发者独占）
renderer/pages/<key>.css   页面样式（功能开发者独占）
```

**脚手架已经接好，功能开发只需要改上面两个文件**；`index.html`、`app.js`、
`core.js`、`styles.css`、`main.go`、`bindings.go` 都不需要再动，四个页面之间也
不会产生冲突。

## 1. 注册方式

`pages/<key>.js` 是一个 IIFE，往全局注册表挂一个对象：

```js
(function () {
  "use strict";

  window.NightreignPages = window.NightreignPages || {};
  window.NightreignPages.bosses = {
    init: function (mount, ctx) { /* 首次进入本页时调用一次 */ },
    refresh: function (ctx) { /* 可选：数据变化时调用 */ }
  };
})();
```

- `init(mount, ctx)`：**首次**切换到该页时由 `app.js` 调用一次，`mount` 是
  `index.html` 里的 `<div class="page-mount" data-mount="<key>"></div>` 元素，
  页面的全部 DOM 由模块自己写进 `mount`。
- `refresh(ctx)`：可选。词条库（导入 / 恢复内置）或存档数据发生变化后调用；
  页面还没 `init` 过时不会被调用。
- 模块抛出的异常会被 `app.js` 捕获，只影响本页（显示「页面载入失败」），
  不会影响其它页面。
- 页面状态请全部放在模块闭包里，**不要往 `app.js` 的 `state` 上加字段**。
- `index.html` 已经按顺序引入 `pages/bosses.js`、`pages/heroes.js`、
  `pages/lookup.js`、`pages/ranker.js`（都在 `app.js` 之前，`defer`），
  以及四个 `pages/<key>.css`。

## 2. `ctx` 的内容

| 字段 | 说明 |
| --- | --- |
| `ctx.Core` | `core.js` 导出的规则模块（`MODES`、`isEligible`、`check`、`buildRelicIndex`、`auditRelic`、`relicKindLabel`…） |
| `ctx.catalog` | 当前已通过 `Core.validateCatalog` 校验的词条库对象（`{ schemaVersion, gameVersion, affixes: [...] , ... }`）。词条库载入失败时可能为 `null`，请判空 |
| `ctx.relicData` | 遗物物品表（`resources/relics.json`）。**只有进过「存档检查」页之后才有值**，否则为 `null`；需要时自行判空或提示用户。也可以像 `lookup.js` 那样在判空后自行调 `window.nightreign.loadRelicData()` 桥补载并在闭包里缓存（浏览器预览模式下退回 `fetch("../resources/relics.json")`） |
| `ctx.getGameData(name)` | `name ∈ "bosses" \| "skills" \| "buffs" \| "heroes"`，返回 `Promise`，懒加载并缓存 |
| `ctx.helpers` | 见下表 |

`ctx` 每次调用（`init` / `refresh`）都是新对象，请不要长期持有里面的
`catalog` / `relicData` 引用，用 `refresh(ctx)` 传进来的最新值。

### `ctx.helpers`

| 函数 | 说明 |
| --- | --- |
| `escapeHtml(value)` | 拼 HTML 字符串前转义，等同 `app.js` 内部的 `esc` |
| `pill(text, color)` | 生成 `<span class='pill pill--<color>'>`，`color ∈ purple \| green \| amber \| red \| blue \| gray`（默认 `purple`） |
| `foldForSearch(value)` | 搜索用的大小写 / 空白归一化（`Core.foldForSearch`） |
| `searchableText(affix)` | 词条的可搜索文本（`Core.searchableText`） |
| `showToast(message, isError)` | 右下角 toast 提示 |
| `query(selector, root)` | `querySelector` 简写，`root` 默认 `document` |
| `queryAll(selector, root)` | `querySelectorAll` → 数组 |
| `byTestId(name)` | `document.querySelector("[data-testid='name']")` |

这些函数就是 `app.js` 现有实现本身，行为完全一致。

## 3. `ctx.getGameData(name)`

```js
ctx.getGameData("bosses").then(function (data) {
  if (!data) { /* 数据未内置 → 页面降级显示 */ return; }
  /* data 是不透明 JSON，结构由数据流水线决定 */
});
```

- 懒加载 + 进程内缓存：同一个 `name` 只会真正读取一次。
- **永不 reject**。以下情况一律 `resolve(null)`：
  - `resources/<name>.json` 不存在或读取失败；
  - 文件还是脚手架占位内容（顶层 `{"placeholder": true}`）；
  - `name` 不在 `"bosses" | "skills" | "buffs" | "heroes"` 之内。
- 因此页面必须能在 `data === null` 时正常渲染（显示「数据未内置」）——四个 JSON
  由另一条数据流水线生成，换版本或重新生成期间随时可能缺位。
- bosses / heroes / skills / buffs 四份数据现已全部就位（regulation 1.03.5 导出，当前
  `bossesSchemaVersion` 4 / heroes `schemaVersion` 1 / skills `schemaVersion` 2 /
  buffs `schemaVersion` 6——这四个数字在页面与测试里是写死的（增伤排名页与 `ranker.test.mjs`
  要求 buffs ≥ 6，旧数据缺配置页要用的字段时页面会提示结果不可信），重新生成数据集时要连同
  `PROVENANCE.md` 的数据集总览表一起改）。**字段含义、数值口径与已知局限以
  [`macos/DataSources/PROVENANCE.md`](../../../macos/DataSources/PROVENANCE.md)
  和 JSON 自带的 `notes` / `usage` / `caveats` / `fieldNotes` 为准**，页面不要另立说法，
  也不要把参数表数值当成实测值展示。
- 即便数据已就位，`data === null` 的分支仍然必须保留：重新生成数据集或换版本期间，
  `resources/<name>.json` 随时可能缺位或退回占位 JSON。

数据文件的来源与落地：

| 页面 | data/ 下的源文件 | 两端内置文件名 |
| --- | --- | --- |
| bosses | `data/nightreign-bosses-v1.03.5.json` | `bosses.json` |
| ranker | `data/nightreign-skills-v1.03.5.json` | `skills.json` |
| ranker | `data/nightreign-buffs-v1.03.5.json` | `buffs.json` |
| heroes | `data/nightreign-heroes-v1.03.5.json` | `heroes.json` |

源文件生成后运行仓库根的 `zsh scripts/sync-data.sh` 覆盖 `windows/resources/`
与 macOS 的 `Resources/`，两端都不需要改代码。

> **底层实现（一般不用关心）**：打包后的应用里，数据走 Go 壳的
> `window.nightreign.loadGameData(name)` 桥（`resources/*.json` 由 `go:embed`
> 内嵌）。Chromium 不允许 `file://` 页面 `fetch()` 本地文件，所以
> `fetch("../resources/<name>.json")` 只是浏览器预览模式（用 HTTP 伺服
> `renderer/` 时）的回退路径。**页面代码一律只调用 `ctx.getGameData`**，
> 不要自己 `fetch`。

### bosses 数据在页面上的分组口径

- 分组按数据集的出场场合 `roles`（`bossesSchemaVersion` 4），**不看** `tier` / `tiers` / `threat`
  （那只是多人缩放档位名，只在展开区留一行「威胁档位」小字）。默认六组：夜王 / 守夜首领 /
  据点首领 / 场景头目 / 封印监牢 / 其它场合；守夜前哨、坑道精英、大空洞高塔首领、突袭事件、
  黑夜入侵者、地图事件、其他地图并进「其它场合」。夜王卡只进「夜王」（突袭 / 事件 / 未放置只作
  卡头徽标）；其余首领一组有几个场合就同时出现在几个分组里。
- 「随从/召唤物」「未放置」是两个默认隐藏的分组，与 `hidden` 的非首领实体共用「显示隐藏实体」
  开关：全部场合都是这两种的组默认不显示，展开区里只属于这两种场合的行默认收起，页面底部列出
  默认隐藏了哪些组。
- 折叠态代表行：按当前分组过滤 `roles` → `isMain` → 排掉登场演出 / 血条实体 → 排掉 `noReward`
  → 血量最高（同血量取 npcId 小者），任一步会清空候选池就跳过那一步。
- 规则正文只有一份，在 macOS 的 `macos/Sources/RelicCore/BossData.swift`（`BossCard.Group`、
  `BossCard.rows(in:)` 的文档注释），`pages/bosses.js` 照抄；文案表 `ROLE_TEXT` ↔ `BossRoleText`、
  `TEXT` ↔ `BossRowText` 键名同名、逐字相同。`tests/bosses_parity.test.mjs` 直接读仓库内的 Swift
  源码与 `RelicCoreChecks` 的对照表（代表行、开关前后八个分组的条数、出处摘要、收录统计、
  底部隐藏说明）来跑本页实现，一项都不跳过；分组专项在 `tests/bosses_roles.test.mjs`。
  改分组规则或文案必须两端一起改。

### ranker（增伤排名）页的配置口径

- 页面是「自己组一套局内配置」：输出手段（战技 + 武器，或法术；分段勾选与伤害构成沿用旧版算法）→
  常规 / 深夜开关（buffs 的 `slotRules.modes`：常规每把武器 1 条局内词条、3 件遗物；深夜诅咒武器每把
  2 条正面词条且深夜专属正面每把 ≤ 1 条、3 普通 + 3 深夜遗物）→ 局内武器词条栏（`weaponAffixes`，
  数量步进，按当前武器 / 施法器的类别过滤）→ 遗物栏（`fixedRelics` 整件，或自组 ≤ 3 条：普通遗物走
  `Core.check("currentNormal")`，深夜遗物走 `Core.check("deepPositive")` + 诅咒逐行配对，需诅咒的词条
  自动配诅咒）→ 护符栏（2 槽）→ 其它增益栏（按 `sourceSlot` 分道具 / 增益法术 / 战技自增益 / 武器固有 /
  角色 / 永久强化 / 局内叠层 / 其它）→ 汇总（总倍率、各栏小计、槽位用量、「按推荐填满」）。
- 生效判定一律用 `buffs[].appliesTo[输出类别]`（战技 → `skill`，魔法 → `sorcery`，祷告 → `incantation`），
  `conditional` 按 `appliesToDetail.<类别>.requires` 逐项判定；不生效项默认隐藏，「显示不生效项」
  打开后虚化并写明原因。去重按 `stacking.exclusiveKey`（同键只留一份、不同键相乘），同一 spEffectId
  多份时只有 `stackSelf`（且按 ID 互斥）的按份数相乘、其余只算一份；`affixVariant` 的 4 档只算选中的一档；叠层按 `stackInput` 手填层数。
  这些叠加取舍都是参数推断、未实测，页面在对应位置标注。
- 口径正文写在 `ranker.js` 的顶部注释，与 macOS 端 `macos/Sources/RelicCore/BuffLoadout.swift` 顶部注释是同一套口径。
  配置部分的文案全部在 `ranker.js` 的 `TEXT` 常量表，与 macOS 的 `LoadoutText.table` 按点号路径逐键同文，
  两端测试校验同一个摘要；整套配置口径的测试在 `tests/ranker_config.test.mjs`，与 macOS 自检
  `checkLoadoutParity` 对拍的三组固定配置在 `tests/ranker_crosscheck.test.mjs`。改口径或文案必须两端一起改。

## 4. 样式约定

- 共用外壳类写在 `styles.css`，可直接用：`.page-content`（页面宽度与留白）、
  `.page-title`、`.page-placeholder-card`、`.page-status-row`、`.page-error`。
- 现有通用类同样可用：`.card`、`.section-heading` / `.section-icon`、`.pill`、
  `.button`、`.search-field`、`.select-field`、`.switch-control`、
  `.segmented-control` / `.segment-button`、`.table-wrap`、`.empty-state`、
  `.issue-row`、`.data-hint` 等（照抄 `index.html` 里现有页面的结构即可）。
- 页面自己的新样式一律写进 `pages/<key>.css`，类名建议带页面前缀
  （`.bosses-*` / `.lookup-*` / `.ranker-*`），**不要改 `styles.css`**，
  否则三个人会冲突。
- 颜色只用 `styles.css` `:root` 里的变量（`--bg`、`--card`、`--border`、
  `--text`、`--text-secondary`、`--purple`、`--green`、`--amber`、`--red`…），
  不要写死色值。

## 5. 约束

- CSP 是 `default-src 'self'; script-src 'self'`：**不能内联 `<script>`、不能
  `eval`、不能引外部资源**。事件请用 `addEventListener`（或在 `mount` 上做事件
  委托），不要用 `onclick=""` 属性。
- 渲染层完全离线，不得发起任何网络请求。
- 需要新的测试钩子时，沿用 `data-testid="<key>-xxx"` 命名。
- 纯计算层建议写成既能被浏览器加载、又能被 node `require` 的模块（顶层不碰
  `document` / `window`，渲染部分放进 `install(root)` 之后再执行，见 `lookup.js`），
  这样可以直接用 `node --test tests/*.test.mjs` 覆盖，不必起浏览器。当前这四页的纯逻辑测试是：
  首领数据 `tests/bosses.test.mjs`、`tests/bosses_roles.test.mjs`、`tests/bosses_parity.test.mjs`
  （后者直接读仓库内的 macOS 源码对照）；角色属性 `tests/heroes.test.mjs`；词条反查
  `tests/lookup_index.test.mjs`；增伤排名 `tests/ranker.test.mjs`、`tests/ranker_config.test.mjs`、
  `tests/ranker_crosscheck.test.mjs`（与 macOS 对拍）。改页面时请一并更新，整套测试的条数只增不减。
- 新增数据文件（除上面四个以外）需要同时改 `main.go` 的 `go:embed` 与
  `scripts/sync-data.sh`，请先与维护者确认。
