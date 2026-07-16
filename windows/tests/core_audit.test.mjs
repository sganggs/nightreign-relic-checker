// 存档检查审计模块（core.js §3/§4）测试。
// 用例数据以仓库根 testdata/audit_cases.json 为权威（macOS 端 RelicCoreChecks 用同一文件对拍）。
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const Core = require("../renderer/core.js");

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const readJSON = (...parts) => JSON.parse(readFileSync(path.join(repoRoot, ...parts), "utf8"));

const catalog = readJSON("windows", "resources", "affixes.json");
const relicData = readJSON("windows", "resources", "relics.json");
const casesDoc = readJSON("testdata", "audit_cases.json");

const ctx = Core.buildRelicIndex(catalog, relicData);

test("buildRelicIndex: 索引结构完整", () => {
  assert.equal(ctx.relicsById.size, relicData.relics.length);
  assert.equal(ctx.affixIndex.size, catalog.affixes.length + relicData.extraAffixes.length);
  // extraAffixes 视为 isCurse:false / requiresCurse:false / poolIds:[]
  const extra = ctx.affixIndex.get(relicData.extraAffixes[0].effectId);
  assert.equal(extra.isCurse, false);
  assert.equal(extra.requiresCurse, false);
  assert.deepEqual(extra.poolIds, []);
  // 深夜三池并集
  for (const poolId of [2000000, 2100000, 2200000]) {
    for (const effectId of relicData.pools[String(poolId)]) {
      assert.ok(ctx.deepPoolUnion.has(effectId), `deepPoolUnion 缺少 ${effectId}`);
    }
  }
});

test("buildRelicIndex: 拒绝坏数据", () => {
  assert.throws(() => Core.buildRelicIndex(catalog, null), /无法读取遗物数据文件/);
  assert.throws(() => Core.buildRelicIndex(catalog, { relics: [] }), /不支持的遗物数据版本/);
});

test("relicKindLabel / relicColorLabel: 契约 §3", () => {
  const deepMeta = ctx.relicsById.get(2000002);
  assert.equal(Core.relicKindLabel(2000002, deepMeta), "深夜遗物");
  assert.equal(Core.relicKindLabel(1000, ctx.relicsById.get(1000)), "唯一遗物");
  assert.equal(Core.relicKindLabel(10000, ctx.relicsById.get(10000)), "唯一遗物");
  assert.equal(Core.relicKindLabel(100, ctx.relicsById.get(100)), "商店遗物（旧版）");
  assert.equal(Core.relicKindLabel(202, ctx.relicsById.get(202)), "商店遗物");
  assert.equal(Core.relicKindLabel(1000000, ctx.relicsById.get(1000000)), "对局奖励");
  assert.equal(Core.relicKindLabel(6001400, ctx.relicsById.get(6001400)), "遗物");
  assert.equal(Core.relicColorLabel(0), "红");
  assert.equal(Core.relicColorLabel(1), "蓝");
  assert.equal(Core.relicColorLabel(2), "黄");
  assert.equal(Core.relicColorLabel(3), "绿");
  assert.equal(Core.relicColorLabel(4), "白");
});

test("auditRelic: 0 与 0xFFFFFFFF 归一化为空词条", () => {
  const result = Core.auditRelic(
    { itemId: 202, effects: [6630000, 7000000, 7000100], curses: [0, 4294967295, 0] },
    ctx
  );
  assert.equal(result.status, "valid");
  assert.deepEqual(result.issues, []);
});

for (const item of casesDoc.cases) {
  test(`audit case: ${item.name}`, () => {
    const result = Core.auditRelic(item.relic, ctx);
    assert.equal(result.status, item.expectStatus, "status 不一致");
    assert.deepEqual(result.issues.map((issue) => issue.kind), item.expectIssueKinds, "issue kind 序列不一致");
    assert.deepEqual(result.warnings.map((issue) => issue.kind), item.expectWarningKinds ?? [], "warning kind 序列不一致");
    if (item.expectOrderedEffects) {
      assert.deepEqual(result.orderedEffects, item.expectOrderedEffects, "orderedEffects 不一致");
    }
    for (const issue of result.issues.concat(result.warnings)) {
      assert.equal(typeof issue.kind, "string");
      assert.equal(typeof issue.title, "string");
      assert.equal(typeof issue.detail, "string");
      assert.ok(Array.isArray(issue.effectIds));
    }
  });
}

for (const item of casesDoc.uniqueCases) {
  test(`unique case: ${item.name}`, () => {
    const audits = item.relics.map((relic) => Core.auditRelic(relic, ctx));
    const returned = Core.applyUniqueDuplicates(audits, item.relics);
    assert.equal(returned, audits, "applyUniqueDuplicates 应原地修改并返回同一数组");
    assert.deepEqual(
      audits.map((audit) => audit.issues.map((issue) => issue.kind)),
      item.expectKindsPerRelic,
      "各遗物 issue kind 序列不一致"
    );
    audits.forEach((audit) => {
      assert.equal(audit.status, audit.issues.length > 0 ? "invalid" : "valid");
    });
  });
}

test("用例覆盖契约 §4 全部 kind", () => {
  const covered = new Set();
  for (const item of casesDoc.cases) {
    item.expectIssueKinds.forEach((kind) => covered.add(kind));
    (item.expectWarningKinds ?? []).forEach((kind) => covered.add(kind));
  }
  for (const item of casesDoc.uniqueCases) {
    item.expectKindsPerRelic.flat().forEach((kind) => covered.add(kind));
  }
  const required = [
    "unknownItem", "illegalRange", "outOfRange", "unknownEffect",
    "duplicate", "conflict",
    "effectUnexpected", "effectMissing", "slotMismatch",
    "curseUnexpected", "curseMissing", "curseMismatch",
    "wrongOrder", "uniqueDuplicate", "fixedPool",
  ];
  for (const kind of required) {
    assert.ok(covered.has(kind), `用例未覆盖 kind：${kind}`);
  }
  assert.ok(casesDoc.cases.length >= 14, "对拍用例应不少于 14 例");
});
