// 存档对比模块（renderer/savediff.js）测试：身份归一、多重集差、槽位配对。
import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";

const require = createRequire(import.meta.url);
const Diff = require("../renderer/savediff.js");

// 存档页的渲染在 renderer/app.js 里，它是个依赖 window / document 的 IIFE，
// node 下 require 不进来。要给「页面上真正写出去的那一串」留回归保护，只能
// 按源码断言——比拿常量和它自己比（恒真）强。
const appSource = readFileSync(
  new URL("../renderer/app.js", import.meta.url),
  "utf8"
);

const relic = (itemId, effects = [], curses = [], index = 0) => ({
  index,
  itemId,
  effects: [effects[0] ?? -1, effects[1] ?? -1, effects[2] ?? -1],
  curses: [curses[0] ?? -1, curses[1] ?? -1, curses[2] ?? -1],
});

const payload = (fileName, characters) => ({ fileName, checksumOk: true, characters });
const character = (slot, name, relics) => ({ slot, name, parseError: null, relics });

test("relicIdentity: 空词条的几种写法等价（与 macOS 端同一条归一规则）", () => {
  const a = Diff.relicIdentity({ itemId: 202, effects: [7000000, 0, 0xFFFFFFFF], curses: [0, -1, null] });
  const b = Diff.relicIdentity({ itemId: 202, effects: [7000000, -1, -1], curses: [-1, -1, -1] });
  assert.equal(a, b);
  // 负值也算空：Swift 端 SaveRelicIdentity.normalized 用的是 <= 0
  assert.equal(Diff.relicIdentity({ itemId: 202, effects: [7000000, -5, -1], curses: [] }), b);
});

test("relicIdentity: itemId / 词条 / 诅咒 / 顺序任一不同即不同遗物", () => {
  const base = Diff.relicIdentity(relic(202, [1, 2, 3], [4, 5, 6]));
  assert.notEqual(base, Diff.relicIdentity(relic(203, [1, 2, 3], [4, 5, 6])));
  assert.notEqual(base, Diff.relicIdentity(relic(202, [1, 2, 9], [4, 5, 6])));
  assert.notEqual(base, Diff.relicIdentity(relic(202, [1, 2, 3], [4, 5, 9])));
  // 顺序会影响合法性判定，所以换序算不同遗物
  assert.notEqual(base, Diff.relicIdentity(relic(202, [2, 1, 3], [4, 5, 6])));
});

test("relicIdentity: 缺字段的坏数据不抛异常", () => {
  assert.equal(typeof Diff.relicIdentity(null), "string");
  assert.equal(Diff.relicIdentity({}), Diff.relicIdentity({ itemId: -1, effects: null, curses: undefined }));
});

test("countRelics: 同款遗物合并计数", () => {
  const counts = Diff.countRelics([relic(202, [1]), relic(202, [1]), relic(300, [2])]);
  assert.equal(counts.size, 2);
  assert.equal(counts.get(Diff.relicIdentity(relic(202, [1]))).count, 2);
  assert.equal(counts.get(Diff.relicIdentity(relic(300, [2]))).count, 1);
});

test("diffRelicLists: 多重集差（含重复件数）", () => {
  const base = [relic(202, [1]), relic(202, [1]), relic(300, [2]), relic(400, [3])];
  const other = [relic(202, [1]), relic(300, [2]), relic(300, [2]), relic(500, [4])];
  const diff = Diff.diffRelicLists(base, other);

  assert.equal(diff.base, 4);
  assert.equal(diff.other, 4);
  // 共有件数 = 每个身份取两边较小值之和：202 取 1、300 取 1、400/500 各 0
  assert.equal(diff.common, 2);
  assert.deepEqual(
    diff.added.map((entry) => [entry.relic.itemId, entry.count]).sort(),
    [[300, 1], [500, 1]]
  );
  assert.deepEqual(
    diff.removed.map((entry) => [entry.relic.itemId, entry.count]).sort(),
    [[202, 1], [400, 1]]
  );
  assert.equal(diff.addedCount, 2);
  assert.equal(diff.removedCount, 2);
});

test("diffRelicLists: 两份相同 → 无差异", () => {
  const relics = [relic(202, [1]), relic(300, [2, 3], [4])];
  const diff = Diff.diffRelicLists(relics, relics.map((item) => ({ ...item })));
  assert.deepEqual(diff.added, []);
  assert.deepEqual(diff.removed, []);
  assert.equal(diff.common, 2);
});

test("diffRelicLists: 空列表 / 非数组输入", () => {
  const diff = Diff.diffRelicLists(undefined, null);
  assert.deepEqual(diff, { base: 0, other: 0, common: 0, added: [], removed: [], addedCount: 0, removedCount: 0 });
  const onlyOther = Diff.diffRelicLists([], [relic(202)]);
  assert.equal(onlyOther.addedCount, 1);
  assert.equal(onlyOther.removedCount, 0);
});

test("diffPayloads: 按槽位配对并汇总", () => {
  const base = payload("NR0000.sl2", [
    character(0, "夜巡者", [relic(202, [1]), relic(300, [2])]),
    character(2, "追踪者", [relic(400, [3])]),
  ]);
  const other = payload("NR0000.co2", [
    character(0, "夜巡者", [relic(202, [1]), relic(500, [9])]),
    character(2, "追踪者", [relic(400, [3])]),
    character(5, "复仇者", [relic(600, [7]), relic(600, [7])]),
  ]);

  const result = Diff.diffPayloads(base, other);
  assert.deepEqual(result.characters.map((item) => item.slot), [0, 2, 5]);

  const slot0 = result.characters[0];
  assert.equal(slot0.addedCount, 1);
  assert.equal(slot0.removedCount, 1);
  assert.equal(slot0.added[0].relic.itemId, 500);
  assert.equal(slot0.removed[0].relic.itemId, 300);
  assert.equal(slot0.changed, true);

  const slot2 = result.characters[1];
  assert.equal(slot2.changed, false);
  assert.equal(slot2.common, 1);

  const slot5 = result.characters[2];
  assert.equal(slot5.inBase, false);
  assert.equal(slot5.inOther, true);
  assert.equal(slot5.baseName, "");
  assert.equal(slot5.otherName, "复仇者");
  assert.equal(slot5.addedCount, 2, "只存在于对比存档的角色，整份算新增");

  assert.deepEqual(result.totals, {
    base: 3, other: 5, added: 3, removed: 1, changedCharacters: 2, unreadableCharacters: 0,
  });
});

test("diffPayloads: 角色只在当前存档里 → 整份算减少", () => {
  const base = payload("a.sl2", [character(1, "甲", [relic(202), relic(203)])]);
  const other = payload("b.sl2", []);
  const result = Diff.diffPayloads(base, other);
  assert.equal(result.characters.length, 1);
  assert.equal(result.characters[0].inOther, false);
  assert.equal(result.characters[0].removedCount, 2);
  assert.equal(result.totals.removed, 2);
});

test("diffPayloads: 不修改入参，坏数据不抛异常", () => {
  const base = payload("a.sl2", [character(0, "甲", [relic(202)])]);
  const snapshot = JSON.stringify(base);
  Diff.diffPayloads(base, null);
  Diff.diffPayloads(null, undefined);
  Diff.diffPayloads({ characters: "坏数据" }, { characters: [{ relics: null }] });
  assert.equal(JSON.stringify(base), snapshot, "入参不应被修改");
});

// 解析失败的槽位在 savefile.Parse 里就是 parseError != null、relics 为空数组，
// 直接拿去比会把「读不出来」报成「遗物被删光」。
const brokenCharacter = (slot, name, reason) => ({ slot, name, parseError: reason, relics: [] });

test("diffPayloads: 对比存档的槽位解析失败 → 不算减少，标 unreadable", () => {
  const base = payload("a.sl2", [character(0, "夜巡者", [relic(202), relic(203), relic(204), relic(205)])]);
  const other = payload("b.sl2", [brokenCharacter(0, "夜巡者", "槽位数据损坏")]);

  const result = Diff.diffPayloads(base, other);
  const slot0 = result.characters[0];
  assert.equal(slot0.unreadable, true);
  assert.equal(slot0.otherParseError, "槽位数据损坏");
  assert.equal(slot0.baseParseError, null);
  assert.deepEqual(slot0.removed, []);
  assert.deepEqual(slot0.added, []);
  assert.equal(slot0.removedCount, 0);
  assert.equal(slot0.changed, false, "解析失败不是「有差异」");
  assert.equal(result.totals.removed, 0, "读不出来的槽位不能计入减少");
  assert.equal(result.totals.added, 0);
  assert.equal(result.totals.changedCharacters, 0);
  assert.equal(result.totals.unreadableCharacters, 1);
});

test("diffPayloads: 当前存档的槽位解析失败 → 不算新增", () => {
  const base = payload("a.sl2", [brokenCharacter(1, "追踪者", "解密失败")]);
  const other = payload("b.sl2", [character(1, "追踪者", [relic(400), relic(401)])]);

  const result = Diff.diffPayloads(base, other);
  const slot = result.characters[0];
  assert.equal(slot.unreadable, true);
  assert.equal(slot.baseParseError, "解密失败");
  assert.equal(slot.addedCount, 0);
  assert.deepEqual(slot.added, []);
  assert.equal(result.totals.added, 0, "读不出来的槽位不能计入新增");
  assert.equal(result.totals.unreadableCharacters, 1);
});

test("diffPayloads: 解析失败的槽位不影响其它槽位的对比", () => {
  const base = payload("a.sl2", [
    brokenCharacter(0, "夜巡者", "槽位数据损坏"),
    character(1, "追踪者", [relic(400), relic(401)]),
  ]);
  const other = payload("b.sl2", [
    character(0, "夜巡者", [relic(202)]),
    character(1, "追踪者", [relic(400), relic(402)]),
  ]);

  const result = Diff.diffPayloads(base, other);
  assert.equal(result.characters[0].unreadable, true);
  assert.equal(result.characters[1].unreadable, false);
  assert.equal(result.characters[1].addedCount, 1);
  assert.equal(result.characters[1].removedCount, 1);
  assert.deepEqual(result.totals, {
    base: 2, other: 3, added: 1, removed: 1, changedCharacters: 1, unreadableCharacters: 1,
  });
});

test("diffPayloads: 空字符串 parseError 不算解析失败", () => {
  const base = payload("a.sl2", [{ slot: 0, name: "甲", parseError: "", relics: [relic(202)] }]);
  const other = payload("b.sl2", [{ slot: 0, name: "甲", parseError: "   ", relics: [] }]);
  const result = Diff.diffPayloads(base, other);
  assert.equal(result.characters[0].unreadable, false);
  assert.equal(result.characters[0].removedCount, 1);
});

test("countRelics / diff 条目带出 positions，供调用方取整体审查结果", () => {
  const relics = [relic(202, [1]), relic(300, [2]), relic(202, [1])];
  const counts = Diff.countRelics(relics);
  assert.deepEqual(counts.get(Diff.relicIdentity(relic(202, [1]))).positions, [0, 2]);
  assert.deepEqual(counts.get(Diff.relicIdentity(relic(300, [2]))).positions, [1]);

  const diff = Diff.diffRelicLists(relics, [relic(300, [2])]);
  assert.deepEqual(diff.removed.find((entry) => entry.relic.itemId === 202).positions, [0, 2]);
  assert.equal(diff.removed.find((entry) => entry.relic.itemId === 202).count, 2);
});

test("diffPayloads: 带出 baseIndex / otherIndex 以便对上各自的 audits 数组", () => {
  const base = payload("a.sl2", [character(3, "丙", [relic(202)]), character(0, "甲", [relic(300)])]);
  const other = payload("b.sl2", [character(0, "甲", [relic(301)])]);
  const result = Diff.diffPayloads(base, other);
  const slot0 = result.characters.find((entry) => entry.slot === 0);
  assert.equal(slot0.baseIndex, 1);
  assert.equal(slot0.otherIndex, 0);
  const slot3 = result.characters.find((entry) => entry.slot === 3);
  assert.equal(slot3.baseIndex, 0);
  assert.equal(slot3.otherIndex, -1);
});

// ---- 存档页的两端口径：空词条归一 / 对比面板提示 ----

const Report = require("../renderer/savereport.js");
const Core = require("../renderer/core.js");

test("空词条归一：savereport.js 与 savediff.js / RelicAudit 同一条规则（负值都算空）", () => {
  // 口径以审计器为准：macOS 端 RelicAudit.padded() 与 SaveRelicIdentity.normalized()
  // 都是 `raw <= 0 || raw == 0xFFFFFFFF`，savediff.js 的 normalizeEffectId 也是 `<= 0`。
  // savereport.js 原来只认 0 / -1，-2 会被当成真词条 ID 写进报告。
  const lookup = {
    affixName: (id) => `词条 ${id}`,
    relicName: (id) => `遗物 ${id}`,
    kindLabel: () => "大遗物",
    colorText: () => "红",
  };
  for (const empty of [-1, 0, -2, -12345, 0xFFFFFFFF, null, undefined]) {
    assert.equal(Report.affixLabel(empty, lookup), "（空）", `${empty} 应算空词条`);
  }
  assert.equal(Report.affixLabel(7000000, lookup), "词条 7000000（7000000）");

  // savediff.js 的身份键对负值一视同仁（本来就对，这里锁住两个模块的一致性）
  const withMinusOne = Diff.relicIdentity({ itemId: 202, effects: [7000000, -1, -1], curses: [-1, -1, -1] });
  const withMinusTwo = Diff.relicIdentity({ itemId: 202, effects: [7000000, -2, 0], curses: [-7, -1, 0] });
  assert.equal(withMinusOne, withMinusTwo, "负值与 0 都归一成空槽，身份键必须相同");

  // 报告正文：-2 的那一行不该出现「词条 -2」
  const relicWithJunk = { index: 0, itemId: 202, effects: [7000000, -2, 0], curses: [-1, -1, -1] };
  const audit = { status: "invalid", issues: [{ title: "问题", detail: "说明" }], warnings: [] };
  const text = Report.text({
    payload: payload("NR0000.sl2", [character(0, "夜巡者", [relicWithJunk])]),
    audits: [[audit]],
    lookup,
  });
  assert.ok(!text.includes("词条 -2"), "负值不能被当成真词条 ID 查名字");
  assert.ok(text.includes("词条1：词条 7000000（7000000）"));

  const csv = Report.csv({
    payload: payload("NR0000.sl2", [character(0, "夜巡者", [relicWithJunk])]),
    audits: [[audit]],
    lookup,
  });
  const cells = csv.split("\r\n")[1].split(",");
  assert.equal(cells[8], "", "CSV 里第 2 条词条应留空");
  assert.equal(cells[9], "", "CSV 里第 3 条词条应留空");
});

test("报告层不改写审计文案：issue.title / issue.detail 原样输出", () => {
  const lookup = {
    affixName: (id) => `词条 ${id}`,
    relicName: () => "遗物",
    kindLabel: () => "大遗物",
    colorText: () => "红",
  };
  const audit = {
    status: "invalid",
    issues: [{ kind: "duplicate", title: "词条重复", detail: "同一词条在一件遗物上重复出现：生命力＋１" }],
    warnings: [{ kind: "x", title: "提醒", detail: "随便写点什么" }],
  };
  const text = Report.text({
    payload: payload("NR0000.sl2", [character(0, "夜巡者", [relic(202, [7000000])])]),
    audits: [[audit]],
    lookup,
  });
  assert.ok(text.includes("    ✗ 词条重复：同一词条在一件遗物上重复出现：生命力＋１"));
  assert.ok(text.includes("    ! 提醒：随便写点什么"));
  assert.deepEqual(Report.issueSummary(audit), [
    "词条重复：同一词条在一件遗物上重复出现：生命力＋１",
    "警告：提醒：随便写点什么",
  ]);
});

test("对比面板：「只改角色名」的槽位仍要说明遗物没变（两端同一句话）", () => {
  // Windows 端 compareCharacterBlock：!changed 且有 presenceNote → 显示这句话。
  // macOS 端此前的条件是 presenceNote == nil，正好把这些槽位全挡掉了。
  const base = payload("a.sl2", [character(0, "旧名", [relic(202, [1])])]);
  const other = payload("b.sl2", [character(0, "新名", [relic(202, [1])])]);
  const result = Diff.diffPayloads(base, other);
  const slot = result.characters[0];

  assert.equal(slot.changed, false, "遗物没有增减");
  assert.equal(slot.unreadable, false);
  assert.equal(slot.baseName, "旧名");
  assert.equal(slot.otherName, "新名");
  assert.equal(slot.addedCount, 0);
  assert.equal(slot.removedCount, 0);
  assert.equal(result.totals.changedCharacters, 0, "改名不算「有差异角色」");

  // 这一句是两端共用的文案（macOS：SaveCompareCharacter.identicalNote）。
  // 上一轮这里写的是 assert.equal(常量, 同一个常量)，恒真——改坏 app.js 也照样过。
  // app.js 是浏览器端的 IIFE，node 下 require 不进来（要 window / document），
  // 所以直接按源码断言渲染出去的那一整串，连同它所在的分支一起锁住。
  assert.match(
    appSource,
    /if \(!entry\.changed\) \{\s*\n\s*return comparePresenceNote\(entry\)\s*\n\s*\? section\("<p class='save-diff-same'>该角色的遗物与当前存档一致。<\/p>"\)/,
    "app.js 的「只改角色名」分支应渲染这句两端共用的文案"
  );
});

test("对比面板：两份存档完全一致时只有一个出口（不会同一句话说两遍）", () => {
  const base = payload("a.sl2", [character(0, "夜巡者", [relic(202, [1])])]);
  const other = payload("b.sl2", [character(0, "夜巡者", [relic(202, [1])])]);
  const result = Diff.diffPayloads(base, other);

  assert.equal(result.totals.added, 0);
  assert.equal(result.totals.removed, 0);
  assert.equal(result.totals.unreadableCharacters, 0);
  // 没有增减、没有改名、没有解析失败 → 这个槽位在两端都不画区块，
  // 「两份存档的遗物完全一致」只由空列表那一个分支输出。
  const slot = result.characters[0];
  assert.equal(slot.changed, false);
  assert.equal(slot.baseName, slot.otherName);
  assert.equal(slot.unreadable, false);
});

// savediff.js 的空槽定义：0 / -1 / 0xFFFFFFFF 都是空。
// （core.js 的 normalizeEffectId 还是 `=== 0 || === -1`，-2 之类的坏值在审计器里
//  仍会被当成真词条 ID。core.js 不在本轮允许改动的文件里，留作单独一轮；
//  下面那条 todo 用例是给那一轮准备的回归位。）
test("savediff 的空槽定义：0 / -1 / 0xFFFFFFFF 都是空", () => {
  assert.equal(typeof Core.auditRelic, "function");
  const identity = Diff.relicIdentity({ itemId: 1, effects: [0, -1, 0xFFFFFFFF], curses: [] });
  assert.equal(identity, "1|-1,-1,-1|-1,-1,-1");
});

test("core.js 的 normalizeEffectId 也该把 -2 当空槽", { todo: "core.js 不在本轮允许改动的文件里" }, () => {
  // core.js 没有导出 normalizeEffectId，只能按源码断言。
  // 改成 `value <= 0` 的那一轮，这条会自动从 todo 变成通过。
  const coreSource = readFileSync(new URL("../renderer/core.js", import.meta.url), "utf8");
  assert.match(
    coreSource,
    /function normalizeEffectId\(value\) \{[^}]*value <= 0/,
    "审计器的空槽定义仍是 `=== 0 || === -1`，-2 之类的坏值会被当成真词条 ID"
  );
});

// ⑨ 同一个 Windows 版里有三处空词条归一：存档页卡片（app.js）、导出报告
// （savereport.js）、存档对比（savediff.js）。上一轮只改了 savereport.js，于是
// effects = [7000000, -2, 0] 的存档在页面上渲染成「未知词条 #-2」，同一个应用
// 导出的 TXT / CSV 却写「（空）」——把「Windows 报告 vs macOS 报告」的不一致
// 换成了「Windows 页面 vs Windows 报告」的不一致。这条把三处锁在一起。
test("空词条归一：app.js / savereport.js / savediff.js 三处同一条规则", () => {
  // app.js 在 node 下 require 不进来，直接从源码里取出那个函数来跑。
  const matched = appSource.match(/var normId = (function \(value\) \{[^}]*\});/);
  assert.ok(matched, "app.js 里应有存档页自用的 normId");
  // eslint-disable-next-line no-new-func
  const appNormId = new Function("return " + matched[1])();

  const lookup = {
    affixName: (id) => `词条 ${id}`,
    relicName: (id) => `遗物 ${id}`,
    kindLabel: () => "大遗物",
    colorText: () => "红",
  };
  for (const empty of [-1, 0, -2, -12345, 0xFFFFFFFF, null, undefined]) {
    assert.equal(appNormId(empty), -1, `app.js：${empty} 应算空词条`);
    assert.equal(Report.affixLabel(empty, lookup), "（空）", `savereport.js：${empty} 应算空词条`);
  }
  assert.equal(appNormId(7000000), 7000000, "真词条 ID 照原样");

  // savediff.js：-2 与 -1 归一到同一个身份键
  assert.equal(
    Diff.relicIdentity({ itemId: 202, effects: [7000000, -2, 0], curses: [] }),
    Diff.relicIdentity({ itemId: 202, effects: [7000000, -1, -1], curses: [] }),
    "savediff.js：负值与 0 都算空槽"
  );

  // 逐个坏值对照：三处必须同进同退
  for (const value of [-2, -1, 0, 1, 7000000, 0xFFFFFFFF]) {
    const appEmpty = appNormId(value) === -1;
    const reportEmpty = Report.affixLabel(value, lookup) === "（空）";
    const diffEmpty = Diff.relicIdentity({ itemId: 1, effects: [value], curses: [] })
      === Diff.relicIdentity({ itemId: 1, effects: [-1], curses: [] });
    assert.equal(appEmpty, reportEmpty, `${value}：app.js 与 savereport.js 的归一不一致`);
    assert.equal(appEmpty, diffEmpty, `${value}：app.js 与 savediff.js 的归一不一致`);
  }
});
