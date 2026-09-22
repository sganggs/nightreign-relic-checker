// 词条反查页（renderer/pages/lookup.js）纯逻辑测试。
// lookup.js 在 node 下只导出反查逻辑，不接触 document / window。
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const Core = require("../renderer/core.js");
const lookup = require("../renderer/pages/lookup.js");

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const readJSON = (...parts) => JSON.parse(readFileSync(path.join(repoRoot, ...parts), "utf8"));

const catalog = readJSON("windows", "resources", "affixes.json");
const relicData = readJSON("windows", "resources", "relics.json");
const index = lookup.buildLookupIndex(Core, catalog, relicData);

const affixById = new Map(catalog.affixes.map((affix) => [affix.effectId, affix]));
const poolModeKeys = Object.keys(Core.MODES).filter((key) => Core.MODES[key].slotPoolPatterns.length > 0);

// 用作样本的真实数据（与 resources/*.json 对齐）
const NORMAL_EFFECT = 7000000;   // 生命力＋１：100/110/200/210/300/310 六池
const DEEP_A_EFFECT = 6001400;   // 提升物理攻击力＋３：深夜 A 池，requiresCurse
const DEEP_BC_EFFECT = 6003000;  // 提升对中毒的抵抗力＋１：深夜 B/C 池
const CURSE_EFFECT = 6820000;    // 受到损伤时，会累积中毒量表：诅咒池
const FIXED_RELIC_ID = 1660;     // 辽阔的火燃情景（唯一遗物，三槽均为单成员池）
const RANDOM_RELIC_ID = 202;     // 辽阔的火燃情景（商店遗物，三槽 310/210/110）

test("buildLookupIndex：词条 → 池 → 遗物反向索引完整", () => {
  assert.equal(index.relicRows.length, relicData.relics.length);
  assert.equal(index.base.poolSets.size, Object.keys(relicData.pools).length);

  // effectPools 覆盖每个池的全部成员
  const memberTotal = Object.values(relicData.pools).reduce((sum, list) => sum + list.length, 0);
  let indexed = 0;
  index.effectPools.forEach((pools) => { indexed += pools.length; });
  assert.equal(indexed, memberTotal);

  // poolSlots 覆盖每个遗物的每个非空槽（含诅咒槽）
  const slotRefs = relicData.relics.reduce((sum, relic) => sum +
    relic.slots.filter((pool) => pool !== -1).length +
    relic.curseSlots.filter((pool) => pool !== -1).length, 0);
  let slotIndexed = 0;
  index.poolSlots.forEach((refs) => { slotIndexed += refs.length; });
  assert.equal(slotIndexed, slotRefs);

  // 遗物行按 ID 升序，且带好搜索文本与标签
  const ids = index.relicRows.map((row) => row.id);
  assert.deepEqual(ids, ids.slice().sort((a, b) => a - b));
  const unique = index.relicRowsById.get(FIXED_RELIC_ID);
  assert.equal(unique.kindLabel, "唯一遗物");
  assert.equal(unique.unique, true);
  assert.equal(unique.colorLabel, "红");
});

test("buildLookupIndex：遗物物品表缺失或版本不符时抛错（页面据此降级）", () => {
  assert.throws(() => lookup.buildLookupIndex(Core, catalog, null), /无法读取遗物数据文件/);
  assert.throws(() => lookup.buildLookupIndex(Core, catalog, { relics: [] }), /不支持的遗物数据版本/);
});

test("searchAffixes：名称 / 别名 / 分类 / effectId，并做 foldForSearch 归一化", () => {
  const byName = lookup.searchAffixes(Core, catalog, "生命力＋１");
  assert.ok(byName.rows.some((affix) => affix.effectId === NORMAL_EFFECT));

  const byId = lookup.searchAffixes(Core, catalog, String(NORMAL_EFFECT));
  assert.ok(byId.rows.some((affix) => affix.effectId === NORMAL_EFFECT));

  // 大小写 / 空格差异不影响命中
  const spaced = lookup.searchAffixes(Core, catalog, "  生命力 ＋１ ");
  assert.ok(spaced.rows.some((affix) => affix.effectId === NORMAL_EFFECT));

  const byCategory = lookup.searchAffixes(Core, catalog, "攻击力");
  assert.ok(byCategory.total > 10);

  // 结果按 (sortId, effectId) 升序
  const all = lookup.searchAffixes(Core, catalog, "", { limit: 10000 });
  assert.equal(all.total, catalog.affixes.length);
  for (let i = 1; i < all.rows.length; i += 1) {
    const prev = all.rows[i - 1];
    const cur = all.rows[i];
    assert.ok(prev.sortId < cur.sortId || (prev.sortId === cur.sortId && prev.effectId <= cur.effectId));
  }

  // 限制行数
  const limited = lookup.searchAffixes(Core, catalog, "", { limit: 200 });
  assert.equal(limited.rows.length, 200);
  assert.equal(limited.truncated, true);

  // 可排除负面词条
  const positives = lookup.searchAffixes(Core, catalog, "", { limit: 10000, includeCurse: false });
  assert.equal(positives.total, catalog.affixes.filter((affix) => !affix.isCurse).length);
});

test("compatibilityPeers：同互斥组的其他词条，-1 视为无互斥组", () => {
  const affix = affixById.get(NORMAL_EFFECT);
  const peers = lookup.compatibilityPeers(Core, catalog, affix);
  assert.ok(peers.length > 0);
  assert.ok(peers.every((peer) => peer.compatibilityId === affix.compatibilityId));
  assert.ok(peers.every((peer) => peer.effectId !== affix.effectId));
  for (let i = 1; i < peers.length; i += 1) {
    assert.ok(peers[i - 1].sortId <= peers[i].sortId);
  }

  const loner = catalog.affixes.find((item) => item.compatibilityId === -1);
  assert.deepEqual(lookup.compatibilityPeers(Core, catalog, loner), []);
});

test("modeSources：逐口径给出能否掉落与槽位池", () => {
  const normal = lookup.modeSources(Core, index, NORMAL_EFFECT);
  assert.deepEqual(normal.map((entry) => entry.key), poolModeKeys);
  assert.ok(!normal.some((entry) => entry.key === "compatibilityOnly"), "顺序/互斥口径不算掉落来源");

  const current = normal.find((entry) => entry.key === "currentNormal");
  assert.equal(current.available, true);
  assert.equal(current.multiPattern, false);
  assert.deepEqual(current.slots.map((slot) => slot.poolId), [310, 210, 110]);
  assert.ok(current.slots.every((slot) => slot.member && slot.size === 340));

  const legacy = normal.find((entry) => entry.key === "legacyNormal");
  assert.deepEqual(legacy.slots.map((slot) => slot.poolId), [300, 200, 100]);
  assert.ok(legacy.slots.every((slot) => slot.member));

  // 深夜 A 池词条不会从普通遗物掉落
  const deepOnly = lookup.modeSources(Core, index, DEEP_A_EFFECT);
  assert.equal(deepOnly.find((entry) => entry.key === "currentNormal").available, false);
  assert.equal(deepOnly.find((entry) => entry.key === "legacyNormal").available, false);
  const deepMode = deepOnly.find((entry) => entry.key === "deepPositive");
  assert.equal(deepMode.available, true);
  assert.equal(deepMode.multiPattern, true, "深夜有 7 种三槽模板");
  assert.deepEqual(deepMode.pools.map((pool) => pool.poolId), [2000000, 2100000, 2200000]);
  assert.deepEqual(deepMode.pools.map((pool) => pool.member), [true, false, false]);
});

test("modeSources：与 Core.isEligible 对全部词条逐一对拍", () => {
  for (const affix of catalog.affixes) {
    const rows = lookup.modeSources(Core, index, affix.effectId);
    for (const row of rows) {
      assert.equal(
        row.available,
        Core.isEligible(affix, row.key),
        `词条 ${affix.effectId} 在口径 ${row.key} 的判定与 Core.isEligible 不一致`
      );
    }
  }
});

test("deepSources：A/B/C 池归属与诅咒配对", () => {
  const poolA = lookup.deepSources(Core, index, DEEP_A_EFFECT);
  assert.deepEqual(poolA.pools.map((pool) => pool.member), [true, false, false]);
  assert.equal(poolA.requiresCurse, true);
  assert.equal(poolA.isCurse, false);
  assert.equal(poolA.cursePoolId, 3000000);
  assert.equal(poolA.curses.length, relicData.pools["3000000"].length);
  assert.ok(poolA.curses.every((curse) => curse.isCurse === true));
  for (let i = 1; i < poolA.curses.length; i += 1) {
    assert.ok(poolA.curses[i - 1].sortId <= poolA.curses[i].sortId);
  }

  const poolBC = lookup.deepSources(Core, index, DEEP_BC_EFFECT);
  assert.deepEqual(poolBC.pools.map((pool) => pool.member), [false, true, true]);
  assert.equal(poolBC.requiresCurse, false);

  const curse = lookup.deepSources(Core, index, CURSE_EFFECT);
  assert.equal(curse.isCurse, true);
  assert.equal(curse.inAny, false, "诅咒词条不在 A/B/C 正面池里");

  // 数据集里「A 池成员」与「requiresCurse」应完全一致
  const poolAIds = new Set(relicData.pools["2000000"]);
  const requiresCurseIds = new Set(catalog.affixes.filter((affix) => affix.requiresCurse).map((affix) => affix.effectId));
  assert.deepEqual([...poolAIds].sort(), [...requiresCurseIds].sort());
});

test("relicSourcesFor：固定词条与随机池可出分开，且结果缓存", () => {
  const fixedEffectId = relicData.pools[String(relicData.relics.find((relic) => relic.id === FIXED_RELIC_ID).slots[0])][0];
  const sources = lookup.relicSourcesFor(index, fixedEffectId);
  const fixedRow = sources.fixed.find((row) => row.id === FIXED_RELIC_ID);
  assert.ok(fixedRow, "唯一遗物 1660 应作为固定词条来源出现");
  assert.equal(fixedRow.kindLabel, "唯一遗物");
  assert.equal(fixedRow.colorLabel, "红");
  assert.ok(fixedRow.entries.every((entry) => entry.poolSize === 1));
  assert.ok(sources.random.length > 0, "该词条同时在深夜 B/C 随机池里");
  assert.ok(sources.random.every((row) => row.entries.some((entry) => entry.poolSize > 1)));
  assert.equal(sources.total, sources.fixed.length + sources.random.length);
  assert.equal(lookup.relicSourcesFor(index, fixedEffectId), sources, "同一词条应命中缓存");

  // 普通随机词条：商店遗物 202 从随机池出，没有任何固定来源
  const normal = lookup.relicSourcesFor(index, NORMAL_EFFECT);
  const shopRow = normal.random.find((row) => row.id === RANDOM_RELIC_ID);
  assert.ok(shopRow);
  assert.equal(shopRow.kindLabel, "商店遗物");
  assert.deepEqual(shopRow.entries.map((entry) => entry.poolId), [310, 210, 110]);
  assert.deepEqual(shopRow.entries.map((entry) => entry.slot), [0, 1, 2]);
  assert.ok(shopRow.entries.every((entry) => entry.kind === "slot" && entry.poolSize === 340));
  // 同一条词条也可能是某些唯一遗物的固定词条（单成员池 707000000）
  // 10002 / 11003 是唯一遗物，7000000 是参数表里的无名称内部条目（页面默认隐藏）
  assert.deepEqual(normal.fixed.map((row) => row.id), [10002, 11003, 7000000]);
  assert.deepEqual(normal.fixed.map((row) => row.named), [true, true, false]);
  assert.ok(normal.fixed.every((row) => row.entries.some((entry) => entry.poolSize === 1)));
  assert.ok(!normal.random.some((row) => row.id === 10002), "同一件遗物不会同时出现在两个分组里");

  // 诅咒词条只出现在有名称遗物的诅咒槽（无名称条目是参数表里的词条道具本体）
  const curse = lookup.relicSourcesFor(index, CURSE_EFFECT);
  assert.ok(curse.total > 0);
  const curseNamed = curse.fixed.concat(curse.random).filter((row) => row.named);
  assert.ok(curseNamed.length > 0);
  assert.ok(curseNamed.every((row) => row.entries.every((entry) => entry.kind === "curse")));
  assert.ok(curseNamed.every((row) => row.deep === true));
  assert.equal(curse.namedTotal, curseNamed.length);

  // 出处行按 ID 升序
  const ids = normal.random.map((row) => row.id);
  assert.deepEqual(ids, ids.slice().sort((a, b) => a - b));
});

test("relicSlotSummary：三槽 + 诅咒槽的池成员数与预览词条", () => {
  const shop = lookup.relicSlotSummary(Core, index, RANDOM_RELIC_ID, 8);
  assert.equal(shop.slotCount, 3);
  assert.equal(shop.curseSlotCount, 0);
  assert.deepEqual(shop.slots.map((slot) => slot.poolId), [310, 210, 110]);
  assert.ok(shop.slots.every((slot) => slot.size === 340 && slot.fixed === false));
  assert.equal(shop.slots[0].preview.length, 8);
  assert.equal(shop.slots[0].more, 332);
  assert.equal(shop.fixedEffects, null, "随机池遗物没有固定词条");
  assert.ok(shop.curseSlots.every((slot) => slot.poolId === -1));

  // 唯一遗物：各槽池均为单成员 → 直接给出固定词条（与 core.js officialFixedEffects 同口径）
  const unique = lookup.relicSlotSummary(Core, index, FIXED_RELIC_ID, 8);
  assert.equal(unique.unique, true);
  assert.ok(unique.slots.every((slot) => slot.fixed === true));
  assert.deepEqual(unique.fixedEffects.map((item) => item.effectId), [6641000, 7000302, 7000402]);
  assert.ok(unique.fixedEffects.every((item) => item.name.length > 0));

  // 深夜遗物：正面槽来自 A/B/C 池，诅咒槽来自诅咒池
  const deepRelic = relicData.relics.find((relic) => relic.deep && relic.curseSlots.some((pool) => pool !== -1));
  const deep = lookup.relicSlotSummary(Core, index, deepRelic.id, 5);
  assert.equal(deep.deep, true);
  assert.ok(deep.curseSlotCount > 0);
  const curseSlot = deep.curseSlots.find((slot) => slot.poolId !== -1);
  assert.equal(curseSlot.poolId, 3000000);
  assert.equal(curseSlot.size, relicData.pools["3000000"].length);

  assert.equal(lookup.relicSlotSummary(Core, index, 999999999, 8), null);
});

test("relicSlotSummary：空池槽位不会被当成固定词条", () => {
  const emptyPoolRelic = relicData.relics.find((relic) =>
    relic.slots.some((pool) => pool !== -1 && relicData.pools[String(pool)].length === 0));
  const summary = lookup.relicSlotSummary(Core, index, emptyPoolRelic.id, 8);
  const emptySlot = summary.slots.find((slot) => slot.poolId !== -1 && slot.size === 0);
  assert.equal(emptySlot.empty, true);
  assert.equal(summary.fixedEffects, null);
});

// core.js 的 officialFixedEffects 没有导出，但 auditRelic 会在「唯一遗物被改动」时
// 用它算出官方固定词条，可以当作对拍用的预言机。
function coreOfficialEffects(data, itemId) {
  const ctx = Core.buildRelicIndex(catalog, data);
  // 传一条肯定不在槽池里的词条，让配对检查失败，auditRelic 才会填 officialEffects
  const audit = Core.auditRelic({ itemId, effects: [7000302, -1, -1], curses: [-1, -1, -1] }, ctx);
  assert.equal(audit.status, "invalid", "构造数据应当配对失败，否则拿不到 officialEffects");
  return audit.officialEffects;
}

function syntheticRelicData(slots, pools) {
  return {
    relicsSchemaVersion: 1,
    relics: [{ id: 1500, name: "对拍用遗物", color: 0, deep: false, slots, curseSlots: [-1, -1, -1] }],
    pools,
    extraAffixes: [],
  };
}

function syntheticFixedEffects(data) {
  const built = lookup.buildLookupIndex(Core, catalog, data);
  const summary = lookup.relicSlotSummary(Core, built, 1500, 8);
  return summary.fixedEffects;
}

test("relicSlotSummary：固定词条判定与 core.js officialFixedEffects 完全同口径", () => {
  // 对照组：单槽单成员池 → 两边都认为词条完全确定
  const okData = syntheticRelicData([900001, -1, -1], { 900001: [7000000] });
  assert.deepEqual(coreOfficialEffects(okData, 1500), [7000000, -1, -1]);
  assert.deepEqual(syntheticFixedEffects(okData).map((item) => item.effectId), [7000000]);

  // 边界 1：还有一个已声明但池为空的槽（poolId !== -1、成员 0 条）→ 都不算固定
  const emptyPool = syntheticRelicData([900001, 900002, -1], { 900001: [7000000], 900002: [] });
  assert.equal(coreOfficialEffects(emptyPool, 1500), null);
  assert.equal(syntheticFixedEffects(emptyPool), null, "空池槽位不能算固定词条");

  // 边界 2：单成员池里的 effectId 在 affixIndex 里查不到 → 都不算固定
  const unknownMember = syntheticRelicData([900001, -1, -1], { 900001: [999999901] });
  assert.equal(coreOfficialEffects(unknownMember, 1500), null);
  assert.equal(syntheticFixedEffects(unknownMember), null, "查不到的池成员不能算固定词条");

  // 边界 3：槽池 ID 指向数据集里根本不存在的池 → 都不算固定
  const missingPool = syntheticRelicData([900001, 900009, -1], { 900001: [7000000] });
  assert.equal(coreOfficialEffects(missingPool, 1500), null);
  assert.equal(syntheticFixedEffects(missingPool), null);

  // 随包数据逐件对拍：固定与否的判定不能与 core.js 的规则分歧
  for (const row of index.relicRows) {
    const summary = lookup.relicSlotSummary(Core, index, row.id, 3);
    const declared = row.meta.slots.filter((pool) => pool !== -1);
    const coreFixed = declared.length > 0 && declared.every((pool) => {
      const members = index.base.poolSets.get(pool);
      return Boolean(members) && members.size === 1 && Boolean(index.base.affixIndex.get(members.values().next().value));
    });
    assert.equal(summary.fixedEffects !== null, coreFixed, `遗物 ${row.id} 的固定词条判定与 core.js 口径不一致`);
    if (coreFixed) {
      assert.equal(summary.fixedEffects.length, declared.length);
    }
  }
});

test("isCatalogAffix：区分词条库词条与只存在于 extraAffixes 的池成员", () => {
  assert.equal(lookup.isCatalogAffix(index, NORMAL_EFFECT), true);
  assert.equal(lookup.isCatalogAffix(index, 10000), false, "10000 是角色专属词条，只在 extraAffixes 里");
  assert.ok(index.base.affixIndex.has(10000), "buildRelicIndex 仍会把 extraAffixes 并进 affixIndex");
  assert.equal(lookup.isCatalogAffix(index, -1), false);

  // 池成员里确实存在词条库查不到的 ID（角色专属词条），页面据此把 chip 做成不可点
  const poolMembers = new Set();
  index.base.poolSets.forEach((members) => members.forEach((effectId) => poolMembers.add(effectId)));
  const outsiders = [...poolMembers].filter((effectId) => !lookup.isCatalogAffix(index, effectId));
  assert.ok(outsiders.length > 0);
  assert.ok(outsiders.every((effectId) => !affixById.has(effectId)));

  // 槽位预览与固定词条都要带上 inCatalog 标记
  const watch = lookup.relicSlotSummary(Core, index, 10000, 8); // 老旧怀表：第 1 槽固定为词条 10000
  assert.equal(watch.slots[0].preview[0].effectId, 10000);
  assert.equal(watch.slots[0].preview[0].inCatalog, false);
  assert.ok(watch.fixedEffects.some((item) => item.effectId === 10000 && item.inCatalog === false));
  assert.ok(watch.fixedEffects.some((item) => item.inCatalog === true), "同一件遗物也有词条库里的词条");

  const shop = lookup.relicSlotSummary(Core, index, RANDOM_RELIC_ID, 8);
  assert.ok(shop.slots.every((slot) => slot.preview.every((item) => item.inCatalog === true)));
});

test("compatibilityPeers：最大的互斥组要能被整组取出（页面上可就地展开）", () => {
  const groups = new Map();
  for (const affix of catalog.affixes) {
    if (affix.compatibilityId === -1) continue;
    groups.set(affix.compatibilityId, (groups.get(affix.compatibilityId) || 0) + 1);
  }
  const [biggestId, biggestSize] = [...groups.entries()].sort((a, b) => b[1] - a[1])[0];
  assert.ok(biggestSize > 24, "数据里存在超过 24 条的互斥组，页面不能只列前 24 条就了事");

  const sample = catalog.affixes.find((affix) => affix.compatibilityId === biggestId);
  const peers = lookup.compatibilityPeers(Core, catalog, sample);
  assert.equal(peers.length, biggestSize - 1, "compatibilityPeers 不截断，截断只发生在渲染层");
  assert.ok(peers.every((peer) => peer.compatibilityId === biggestId));

  // Core.searchableText 不含 compatibilityId：词条库页搜互斥池 ID 是搜不出这一组的，
  // 所以「去词条库按互斥池查看」不是可执行的指引
  assert.ok(!Core.searchableText(sample).includes(String(biggestId)));
});

test("searchRelics：按名称 / ID / 种类搜索，默认隐藏无名称条目", () => {
  const named = lookup.searchRelics(Core, index, "", { limit: 10000 });
  assert.equal(named.total, relicData.relics.filter((relic) => relic.name).length);

  const all = lookup.searchRelics(Core, index, "", { limit: 10000, includeUnnamed: true });
  assert.equal(all.total, relicData.relics.length);

  const byId = lookup.searchRelics(Core, index, String(FIXED_RELIC_ID));
  assert.ok(byId.rows.some((row) => row.id === FIXED_RELIC_ID));

  const byName = lookup.searchRelics(Core, index, "辽阔的火燃情景");
  assert.ok(byName.rows.some((row) => row.id === RANDOM_RELIC_ID));

  const byKind = lookup.searchRelics(Core, index, "深夜遗物", { limit: 10000 });
  assert.ok(byKind.total > 100);
  assert.ok(byKind.rows.every((row) => row.meta.deep === true));

  const limited = lookup.searchRelics(Core, index, "", { limit: 50 });
  assert.equal(limited.rows.length, 50);
  assert.equal(limited.truncated, true);
});

test("paginate：分页边界安全", () => {
  const rows = Array.from({ length: 450 }, (unused, i) => i);
  const first = lookup.paginate(rows, 0, 200);
  assert.equal(first.rows.length, 200);
  assert.equal(first.pageCount, 3);
  assert.equal(first.from, 1);
  assert.equal(first.to, 200);

  const last = lookup.paginate(rows, 99, 200);
  assert.equal(last.page, 2, "页码越界应夹到最后一页");
  assert.equal(last.rows.length, 50);
  assert.equal(last.to, 450);

  const negative = lookup.paginate(rows, -5, 200);
  assert.equal(negative.page, 0);

  const empty = lookup.paginate([], 0, 200);
  assert.equal(empty.pageCount, 1);
  assert.equal(empty.total, 0);
  assert.equal(empty.from, 0);
});

test("datasetCaveats：数据集没有 caveats 时返回空数组", () => {
  assert.deepEqual(lookup.datasetCaveats(catalog), []);
  assert.deepEqual(lookup.datasetCaveats(relicData), []);
  assert.deepEqual(lookup.datasetCaveats(null), []);
  assert.deepEqual(lookup.datasetCaveats({ caveats: "仅供参考" }), ["仅供参考"]);
  assert.deepEqual(lookup.datasetCaveats({ caveats: ["甲", { text: "乙" }] }), ["甲", "乙"]);
});

test("isUniqueRelicId：与 core.js 的唯一遗物 ID 区间一致", () => {
  assert.equal(lookup.isUniqueRelicId(1000), true);
  assert.equal(lookup.isUniqueRelicId(2100), true);
  assert.equal(lookup.isUniqueRelicId(2101), false);
  assert.equal(lookup.isUniqueRelicId(10000), true);
  assert.equal(lookup.isUniqueRelicId(19999), true);
  assert.equal(lookup.isUniqueRelicId(202), false);
  // 与 core.js 的 relicKindLabel 对拍：区间内的遗物都应标为「唯一遗物」，
  // 区间外的都不应该（深夜遗物优先级更高，先排除）
  for (const row of index.relicRows) {
    if (row.meta.deep) continue;
    assert.equal(
      row.kindLabel === "唯一遗物",
      lookup.isUniqueRelicId(row.id),
      `遗物 ${row.id} 的种类标签与唯一 ID 区间不一致`
    );
  }
});

test("lookup.js 在 node 下不接触 DOM，且导出渲染入口", () => {
  assert.equal(typeof lookup.install, "function");
  assert.equal(typeof globalThis.NightreignPages, "undefined", "require 时不应注册页面模块");
  assert.equal(lookup.ROW_LIMIT, 200);
  assert.equal(lookup.SEARCH_LIMIT, 200);
});
