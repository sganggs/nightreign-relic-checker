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
- 因此页面必须能在 `data === null` 时正常渲染（显示「数据未内置」）——三个 JSON
  由另一条数据流水线生成，换版本或重新生成期间随时可能缺位。
- 自 v0.3.0 起 bosses / skills / buffs 三份数据都已就位（regulation 1.03.5 导出，当前
  `bossesSchemaVersion` 2 / skills 2 / buffs 5——这三个数字是写死的，重新生成数据集时
  要连同 `PROVENANCE.md` 的数据集总览表一起改）。**字段含义、数值口径与已知局限以
  [`macos/DataSources/PROVENANCE.md`](../../../macos/DataSources/PROVENANCE.md)
  和 JSON 自带的 `notes` / `usage` / `caveats` / `fieldNotes` 为准**，页面不要另立说法，
  也不要把参数表数值当成实测值展示。
- `heroes`（角色属性）的数据还在生成中：`data/nightreign-heroes-v1.03.5.json` 与
  `macos/DataSources/generate_heroes.py` 由另一位同事负责，两端 `resources/heroes.json`
  目前是占位 JSON，页面会走「数据未内置」分支。结构以生成后的 JSON 自带说明为准。

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
  这样可以直接用 `node --test tests/*.test.mjs` 覆盖，不必起浏览器。当前
  `tests/bosses.test.mjs`、`tests/lookup_index.test.mjs`、`tests/ranker.test.mjs`
  就是这三页的纯逻辑测试（`heroes` 还是占位实现，尚无测试文件）；改页面时请一并
  更新，整套测试的条数只增不减。
- 新增数据文件（除上面四个以外）需要同时改 `main.go` 的 `go:embed` 与
  `scripts/sync-data.sh`，请先与维护者确认。
