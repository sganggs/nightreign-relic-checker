// 存档对比模块（renderer/savediff.js）测试：身份归一、多重集差、槽位配对。
import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const Diff = require("../renderer/savediff.js");

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
