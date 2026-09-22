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
  const peers = lookup.compatibilityPeers(Core, index, affix, catalog);
  assert.ok(peers.length > 0);
  assert.ok(peers.every((peer) => peer.compatibilityId === affix.compatibilityId));
  assert.ok(peers.every((peer) => peer.effectId !== affix.effectId));
  for (let i = 1; i < peers.length; i += 1) {
    assert.ok(peers[i - 1].sortId <= peers[i].sortId);
  }

  const loner = catalog.affixes.find((item) => item.compatibilityId === -1);
  assert.deepEqual(lookup.compatibilityPeers(Core, index, loner, catalog), []);

  // 遗物物品表不可用时退回词条库内的同组词条
  const degraded = lookup.compatibilityPeers(Core, null, affix, catalog);
  assert.ok(degraded.every((peer) => affixById.has(peer.effectId)));
});

test("compatibilityPeers：只算「能出现在遗物上」的词条，与 core.js auditRelic §4.6 同口径", () => {
  // 物品表里有一千多条从不进任何槽位池的效果（庇佑等），它们共用参数表的默认
  // compatibilityId 100；列进互斥组会把最大组从 102 条撑到 1128 条。
  const sample = catalog.affixes.find((affix) => affix.compatibilityId === 100);
  const peers = lookup.compatibilityPeers(Core, index, sample, catalog);
  const catalogGroup = catalog.affixes.filter((affix) => affix.compatibilityId === 100);
  assert.equal(catalogGroup.length, 102);
  assert.equal(peers.length + 1, 102, "互斥池 100 共 102 条，不含从不进池的参数表效果");

  const pooled = new Set();
  index.effectPools.forEach((unused, effectId) => pooled.add(effectId));
  const strays = [...index.base.affixIndex.keys()].filter((effectId) =>
    index.base.affixIndex.get(effectId).compatibilityId === 100 &&
    !lookup.isCatalogAffix(index, effectId) && !pooled.has(effectId));
  assert.ok(strays.length > 900, "数据里确实有大量不进池、却挂着 compatibilityId 100 的效果");
  assert.ok(strays.every((effectId) => !peers.some((peer) => peer.effectId === effectId)));

  // 反过来：进了池的 extraAffixes 必须算进互斥组（存档审计会判它们互斥）
  const pooledExtra = [...pooled].find((effectId) => {
    const entry = index.base.affixIndex.get(effectId);
    return entry && !lookup.isCatalogAffix(index, effectId) && entry.compatibilityId !== -1 &&
      catalog.affixes.some((affix) => affix.compatibilityId === entry.compatibilityId);
  });
  assert.ok(pooledExtra, "应存在与词条库共组的池内 extraAffixes");
  const host = catalog.affixes.find((affix) =>
    affix.compatibilityId === index.base.affixIndex.get(pooledExtra).compatibilityId);
  assert.ok(lookup.compatibilityPeers(Core, index, host, catalog)
    .some((peer) => peer.effectId === pooledExtra));
});

test("modeSources：逐口径给出能否掉落与候选池（只报池，不报槽序号）", () => {
  const normal = lookup.modeSources(Core, index, NORMAL_EFFECT);
  assert.deepEqual(normal.map((entry) => entry.key), poolModeKeys);
  assert.ok(!normal.some((entry) => entry.key === "compatibilityOnly"), "顺序/互斥口径不算掉落来源");
  assert.ok(normal.every((entry) => !("slots" in entry)),
    "普通大遗物按孔数分层取池，模板下标不是槽序号，不能打出「第 N 槽」");

  const current = normal.find((entry) => entry.key === "currentNormal");
  assert.equal(current.available, true);
  assert.deepEqual(current.pools.map((pool) => pool.poolId), [110, 210, 310], "候选池按 id 升序");
  assert.ok(current.pools.every((pool) => pool.member && pool.size === 340));
  assert.ok(current.pools.every((pool) => pool.relicCount > 0));

  const legacy = normal.find((entry) => entry.key === "legacyNormal");
  assert.deepEqual(legacy.pools.map((pool) => pool.poolId), [100, 200, 300]);
  assert.ok(legacy.pools.every((pool) => pool.member));

  // 深夜 A 池词条不会从普通遗物掉落
  const deepOnly = lookup.modeSources(Core, index, DEEP_A_EFFECT);
  assert.equal(deepOnly.find((entry) => entry.key === "currentNormal").available, false);
  assert.equal(deepOnly.find((entry) => entry.key === "legacyNormal").available, false);
  const deepMode = deepOnly.find((entry) => entry.key === "deepPositive");
  assert.equal(deepMode.available, true);
  assert.deepEqual(deepMode.pools.map((pool) => pool.poolId), [2000000, 2100000, 2200000]);
  assert.deepEqual(deepMode.pools.map((pool) => pool.member), [true, false, false]);
});

test("poolLabel：孔数层标签不带槽序号，与 macOS 端 affixPoolLabel 同表", () => {
  assert.equal(lookup.poolLabel(100), "旧池 · 1 孔层");
  assert.equal(lookup.poolLabel(200), "旧池 · 2 孔层");
  assert.equal(lookup.poolLabel(300), "旧池 · 3 孔层");
  assert.equal(lookup.poolLabel(110), "1.03 · 1 孔层");
  assert.equal(lookup.poolLabel(210), "1.03 · 2 孔层");
  assert.equal(lookup.poolLabel(310), "1.03 · 3 孔层");
  assert.equal(lookup.poolLabel(2000000), "深夜 A 池");
  assert.equal(lookup.poolLabel(3000000), "深夜诅咒池");
  assert.equal(lookup.poolLabel(707121100), "池 707121100");
  for (const poolId of [100, 200, 300, 110, 210, 310]) {
    assert.ok(!lookup.poolLabel(poolId).includes("槽"), `池 ${poolId} 的标签不应含「槽」`);
    assert.ok(lookup.poolLabel(poolId).includes("孔层"));
  }
  assert.ok(lookup.poolDetail(2000000).includes("同一行"));
  assert.equal(lookup.poolDetail(707121100), "");
});

test("孔数层池：三层嵌套，且 3 孔遗物的第 1 槽用的是 3 孔层池", () => {
  for (const tiers of [[100, 200, 300], [110, 210, 310]]) {
    const sets = tiers.map((poolId) => index.base.poolSets.get(poolId));
    assert.ok(sets.every((set) => set && set.size > 0));
    assert.ok([...sets[0]].every((id) => sets[1].has(id)), `${tiers[0]} 应 ⊆ ${tiers[1]}`);
    assert.ok([...sets[1]].every((id) => sets[2].has(id)), `${tiers[1]} 应 ⊆ ${tiers[2]}`);
  }
  let threeSlot = 0;
  for (const row of index.relicRows) {
    if (row.meta.deep || !row.obtainable) continue;
    const pools = row.meta.slots.filter((poolId) => poolId !== -1);
    if (pools.length !== 3 || !pools.every((poolId) => [100, 200, 300, 110, 210, 310].includes(poolId))) continue;
    threeSlot += 1;
    assert.ok(
      String(pools) === String([300, 200, 100]) || String(pools) === String([310, 210, 110]),
      `3 孔遗物 ${row.id} 的 slots 应为 [300,200,100] / [310,210,110]，实际 ${pools}`
    );
  }
  assert.ok(threeSlot > 0, "应存在使用孔数层池的 3 孔遗物");
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
  assert.deepEqual(poolA.pools.map((pool) => pool.label), ["深夜 A 池", "深夜 B 池", "深夜 C 池"]);
  assert.equal(poolA.cursePool.poolId, 3000000);
  assert.equal(poolA.cursePool.member, false);
  assert.equal(poolA.cursePool.size, relicData.pools["3000000"].length);
  assert.ok(poolA.cursePool.relicCount > 0, "诅咒池应有正常可获得的深夜遗物在用");
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
  assert.equal(curse.cursePool.member, true);

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
  assert.equal(fixedRow.role, "slot");
  assert.ok(fixedRow.poolIds.every((poolId) => index.base.poolSets.get(poolId).size === 1));
  assert.ok(sources.random.length > 0, "该词条同时在深夜 B/C 随机池里");
  assert.equal(sources.total, sources.fixed.length + sources.random.length);
  assert.equal(lookup.relicSourcesFor(index, fixedEffectId), sources, "同一词条应命中缓存");

  // 普通随机词条：商店遗物 202 从随机池出，没有任何固定来源
  const normal = lookup.relicSourcesFor(index, NORMAL_EFFECT);
  const shopRow = normal.random.find((row) => row.id === RANDOM_RELIC_ID);
  assert.ok(shopRow);
  assert.equal(shopRow.kindLabel, "商店遗物");
  assert.equal(shopRow.role, "slot");
  // 命中记录只报池、按 id 升序，不报槽序号（3 孔遗物的 slots 是 [310, 210, 110]）
  assert.deepEqual(shopRow.poolIds, [110, 210, 310]);
  assert.ok(!("slot" in shopRow) && !("entries" in shopRow));
  // 同一条词条也可能是某些唯一遗物的固定词条（单成员池 707000000）；
  // 7000000 是参数表里的无名称内部条目，不会正常获得，只计入 hidden
  assert.deepEqual(normal.fixed.map((row) => row.id), [10002, 11003]);
  assert.ok(normal.fixed.every((row) => row.named && row.obtainable));
  assert.ok(normal.hidden > 0, "无名称参数行应计入 hidden 而不是列出来");
  assert.ok(!normal.random.some((row) => row.id === 10002), "同一件遗物不会同时出现在两个分组里");

  // 诅咒词条只挂在正常可获得的深夜遗物的诅咒槽上
  const curse = lookup.relicSourcesFor(index, CURSE_EFFECT);
  assert.ok(curse.total > 0);
  const curseRows = curse.fixed.concat(curse.random);
  assert.ok(curseRows.every((row) => row.role === "curse"));
  assert.ok(curseRows.every((row) => row.deep === true && row.named && row.obtainable));

  // 出处行按 ID 升序
  const ids = normal.random.map((row) => row.id);
  assert.deepEqual(ids, ids.slice().sort((a, b) => a - b));
});

test("relicSourcesFor：作弊器区段 / 超范围 / 无名参数行一律不列出，只计 hidden", () => {
  // 20000–30035 的 72 件遗物有名字，单靠「有没有名字」滤不掉，必须显式排除区段
  const cheats = index.relicRows.filter((row) => row.id >= 20000 && row.id <= 30035);
  assert.equal(cheats.length, 72);
  assert.ok(cheats.every((row) => row.named), "作弊器区段的遗物都有名字");
  assert.ok(cheats.every((row) => !row.obtainable));
  assert.ok(cheats.every((row) => row.unobtainableReason.includes("作弊器")));
  // 它们的槽位池是空池 1，当成正常遗物展示只会渲染出「随机 0 条」
  assert.ok(cheats.every((row) => row.meta.slots.every((poolId) =>
    poolId === -1 || (index.base.poolSets.get(poolId) || new Set()).size === 0)));

  // 空池 1 没有任何成员，所以作弊器遗物不会出现在任何词条的出处里；
  // 逐条词条兜底：列出来的行必须全部是正常可获得的遗物
  for (const affix of catalog.affixes) {
    const sources = lookup.relicSourcesFor(index, affix.effectId);
    for (const row of sources.fixed.concat(sources.random)) {
      assert.ok(row.obtainable, `词条 ${affix.effectId} 列出了不会正常获得的遗物 ${row.id}`);
      assert.ok(row.id >= lookup.RELIC_ID_MIN && row.id <= lookup.RELIC_ID_MAX);
      assert.ok(row.id < lookup.CHEAT_ID_MIN || row.id > lookup.CHEAT_ID_MAX);
    }
  }

  // 超范围但有名字的参数行（10 暗痕 / 11 为王之证 / 20 情景原石）同样排除
  for (const relicId of [10, 11, 20]) {
    const row = index.relicRowsById.get(relicId);
    assert.ok(row && row.named && !row.obtainable);
    assert.ok(row.unobtainableReason.includes("超出合法 ID 区间"));
  }
});

test("relicSlotSummary：三槽 + 诅咒槽的池成员数与预览词条", () => {
  const shop = lookup.relicSlotSummary(Core, index, RANDOM_RELIC_ID, 8);
  assert.equal(shop.slotCount, 3);
  assert.equal(shop.curseSlotCount, 0);
  assert.equal(shop.poolGroups, null, "非深夜遗物按槽位展示，不做按池归并");
  assert.deepEqual(shop.slots.map((slot) => slot.poolId), [310, 210, 110]);
  // 槽序号与孔数层：第 1 槽用的是 3 孔层池，标签只能写孔数层
  assert.deepEqual(shop.slots.map((slot) => slot.label),
    ["1.03 · 3 孔层", "1.03 · 2 孔层", "1.03 · 1 孔层"]);
  assert.ok(shop.slots.every((slot) => slot.size === 340 && slot.fixed === false));
  assert.equal(shop.slots[0].preview.length, 8);
  assert.equal(shop.slots[0].more, 332);
  assert.equal(shop.fixedEffects, null, "随机池遗物没有固定词条");
  assert.ok(shop.slots.every((slot) => slot.cursePoolId === -1 && slot.curseSize === 0));

  // 唯一遗物：各槽池均为单成员 → 直接给出固定词条（与 core.js officialFixedEffects 同口径）
  const unique = lookup.relicSlotSummary(Core, index, FIXED_RELIC_ID, 8);
  assert.equal(unique.unique, true);
  assert.ok(unique.slots.every((slot) => slot.fixed === true));
  assert.deepEqual(unique.fixedEffects.map((item) => item.effectId), [6641000, 7000302, 7000402]);
  assert.ok(unique.fixedEffects.every((item) => item.name.length > 0));

  assert.equal(lookup.relicSlotSummary(Core, index, 999999999, 8), null);
});

test("relicSlotSummary：深夜遗物按池归并展示，不打槽序号", () => {
  // 参数表里深夜遗物的行排列与游戏实际生成不符（RelicAudit 的按行配对模型只认
  // 存档里的 effects[i]/curses[i]），所以本页只给池构成。
  const deepRelic = relicData.relics.find((relic) => relic.deep && relic.curseSlots.some((pool) => pool !== -1));
  const deep = lookup.relicSlotSummary(Core, index, deepRelic.id, 5);
  assert.equal(deep.deep, true);
  assert.ok(Array.isArray(deep.poolGroups) && deep.poolGroups.length > 0);
  assert.deepEqual(deep.poolGroups.map((group) => group.poolId),
    deep.poolGroups.map((group) => group.poolId).slice().sort((a, b) => a - b), "按池 id 升序");
  assert.equal(
    deep.poolGroups.reduce((sum, group) => sum + group.count, 0),
    deep.slotCount,
    "归并后的条数之和应等于孔数"
  );
  assert.ok(deep.poolGroups.every((group) => [2000000, 2100000, 2200000].includes(group.poolId)));

  // A 池的那一组带诅咒池信息；数据集里 A 槽数 = 诅咒槽数
  const groupA = deep.poolGroups.find((group) => group.poolId === 2000000);
  assert.ok(groupA);
  assert.equal(groupA.slot.cursePoolId, 3000000);
  assert.equal(groupA.slot.curseSize, relicData.pools["3000000"].length);
  assert.equal(deep.curseSlotCount, groupA.count, "槽位模板只保证 A 槽数 = 诅咒槽数");

  // 全库兜底：每件深夜遗物的 A 槽数都等于诅咒槽数
  for (const row of index.relicRows) {
    if (!row.meta.deep) continue;
    const aCount = row.meta.slots.filter((poolId) => poolId === 2000000).length;
    const curseCount = row.meta.curseSlots.filter((poolId) => poolId !== -1).length;
    assert.equal(aCount, curseCount, `深夜遗物 ${row.id} 的 A 槽数应等于诅咒槽数`);
    assert.ok(row.meta.curseSlots.every((poolId) => poolId === -1 || poolId === 3000000));
  }

  // 非深夜遗物一律没有诅咒槽
  assert.ok(index.relicRows.every((row) =>
    row.meta.deep || row.meta.curseSlots.every((poolId) => poolId === -1)));
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
  const peers = lookup.compatibilityPeers(Core, index, sample, catalog);
  assert.equal(biggestSize, 102, "最大互斥组 102 条");
  assert.equal(peers.length, biggestSize - 1, "compatibilityPeers 不截断，截断只发生在渲染层");
  assert.ok(peers.every((peer) => peer.compatibilityId === biggestId));
  assert.ok(peers.length > lookup.PEER_PREVIEW, "渲染层默认只列前 24 条，必须提供「展开全部」");

  // Core.searchableText 不含 compatibilityId：词条库页搜互斥池 ID 是搜不出这一组的，
  // 所以「去词条库按互斥池查看」不是可执行的指引
  assert.ok(!Core.searchableText(sample).includes(String(biggestId)));
});

test("searchRelics：默认只给正常可获得的遗物（与 macOS 端 onlyObtainable 同口径）", () => {
  const obtainable = lookup.searchRelics(Core, index, "", { limit: 10000 });
  assert.equal(obtainable.total, 768,
    "1397 件里滤掉超范围 / 无名参数行与 20000-30035 作弊器区段后应剩 768 件");
  assert.equal(obtainable.total, index.obtainableCount);
  assert.ok(obtainable.rows.every((row) => row.obtainable));
  // 可查遗物不允许有空成员的槽位池，否则详情面板会渲染出「随机 0 条」的空面板
  assert.ok(obtainable.rows.every((row) =>
    row.meta.slots.some((poolId) => poolId !== -1 && index.base.poolSets.get(poolId).size > 0)));
  assert.ok(!obtainable.rows.some((row) => row.id >= 20000 && row.id <= 30035));

  const all = lookup.searchRelics(Core, index, "", { limit: 10000, includeUnobtainable: true });
  assert.equal(all.total, relicData.relics.length);
  assert.ok(all.rows.some((row) => row.id === 20000), "关掉过滤后仍能取到作弊器区段的遗物");

  const byId = lookup.searchRelics(Core, index, String(FIXED_RELIC_ID));
  assert.ok(byId.rows.some((row) => row.id === FIXED_RELIC_ID));

  const byName = lookup.searchRelics(Core, index, "辽阔的火燃情景");
  assert.ok(byName.rows.some((row) => row.id === RANDOM_RELIC_ID));
  assert.ok(!byName.rows.some((row) => row.id >= 20000 && row.id <= 30035),
    "作弊器区段里也有同名的「辽阔的火燃情景」，不能混进结果");

  const byKind = lookup.searchRelics(Core, index, "深夜遗物", { limit: 10000 });
  assert.ok(byKind.total > 100);
  assert.ok(byKind.rows.every((row) => row.meta.deep === true));

  const onlyDeep = lookup.searchRelics(Core, index, "", { limit: 10000, onlyDeep: true });
  assert.equal(onlyDeep.total, 216);
  assert.ok(onlyDeep.rows.every((row) => row.meta.deep && row.obtainable));

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

// 与 macOS 端 RelicCoreChecks/AffixLookupChecks.swift 的 checkWindowsParitySamples
// 断言同一张表：同一份内置数据，两端对同一输入必须给出同样的结论。
// 表里任何一格改动都要两端一起改，否则一端的测试会红。
const AFFIX_PARITY = [
  {
    effectId: 7000000, name: "生命力＋１",
    modes: [true, true, false], deepPools: [false, false, false],
    inCursePool: false, requiresCurse: false, isCurse: false,
    fixedRelicIds: [10002, 11003], randomRelicCount: 432,
    hiddenCount: 1, conflictGroupSize: 4,
  },
  {
    effectId: 6001400, name: "提升物理攻击力＋３",
    modes: [false, false, true], deepPools: [true, false, false],
    inCursePool: false, requiresCurse: true, isCurse: false,
    fixedRelicIds: [], randomRelicCount: 144,
    hiddenCount: 1, conflictGroupSize: 102,
  },
  {
    effectId: 6003000, name: "提升对中毒的抵抗力＋１",
    modes: [false, false, true], deepPools: [false, true, true],
    inCursePool: false, requiresCurse: false, isCurse: false,
    fixedRelicIds: [], randomRelicCount: 144,
    hiddenCount: 1, conflictGroupSize: 3,
  },
  {
    effectId: 6820000, name: "受到损伤时，会累积中毒量表",
    modes: [false, false, false], deepPools: [false, false, false],
    inCursePool: true, requiresCurse: false, isCurse: true,
    fixedRelicIds: [], randomRelicCount: 144,
    hiddenCount: 1, conflictGroupSize: 1,
  },
  {
    effectId: 7121100, name: "出击时，会持有“火焰壶”",
    modes: [true, true, false], deepPools: [false, false, false],
    inCursePool: false, requiresCurse: false, isCurse: false,
    fixedRelicIds: [1000], randomRelicCount: 432,
    hiddenCount: 2, conflictGroupSize: 1,
  },
];

const RELIC_PARITY = [
  {
    relicId: 202, name: "辽阔的火燃情景", kindLabel: "商店遗物", colorLabel: "红",
    deep: false, unique: false, slotCount: 3, curseSlotCount: 0,
    slotPools: [310, 210, 110],
    slotLabels: ["1.03 · 3 孔层", "1.03 · 2 孔层", "1.03 · 1 孔层"],
    slotSizes: [340, 340, 340], deepGroups: null, fixedEffectIds: null,
  },
  {
    relicId: 1000, name: "细腻的火燃情景", kindLabel: "唯一遗物", colorLabel: "红",
    deep: false, unique: true, slotCount: 1, curseSlotCount: 0,
    slotPools: [707121100, -1, -1],
    slotLabels: ["池 707121100", "", ""],
    slotSizes: [1, 0, 0], deepGroups: null, fixedEffectIds: [7121100],
  },
  {
    relicId: 2000002, name: "辽阔的火燃暗淡情景", kindLabel: "深夜遗物", colorLabel: "红",
    deep: true, unique: false, slotCount: 3, curseSlotCount: 1,
    slotPools: [2000000, 2100000, 2100000],
    slotLabels: ["深夜 A 池", "深夜 B 池", "深夜 B 池"],
    slotSizes: [49, 277, 277],
    deepGroups: [[2000000, 1], [2100000, 2]], fixedEffectIds: null,
  },
];

test("双端对照：5 条词条的反查结论与 macOS 端逐字段一致", () => {
  assert.deepEqual(poolModeKeys, ["currentNormal", "legacyNormal", "deepPositive"],
    "反查页按「普通 1.03 / 普通旧池 / 深夜正面」三种口径展示");

  for (const sample of AFFIX_PARITY) {
    const affix = affixById.get(sample.effectId);
    assert.equal(affix.name, sample.name, `${sample.effectId} 的名称`);

    const modes = lookup.modeSources(Core, index, sample.effectId);
    assert.deepEqual(modes.map((entry) => entry.available), sample.modes,
      `${sample.effectId} 的三口径可掉落判定`);

    const deep = lookup.deepSources(Core, index, sample.effectId);
    assert.deepEqual(deep.pools.map((pool) => pool.member), sample.deepPools,
      `${sample.effectId} 的深夜 A/B/C 归属`);
    assert.equal(deep.cursePool.member, sample.inCursePool, `${sample.effectId} 的诅咒池归属`);
    assert.equal(deep.requiresCurse, sample.requiresCurse);
    assert.equal(deep.isCurse, sample.isCurse);

    const sources = lookup.relicSourcesFor(index, sample.effectId);
    assert.deepEqual(sources.fixed.map((row) => row.id), sample.fixedRelicIds,
      `${sample.effectId} 的固定出处`);
    assert.equal(sources.random.length, sample.randomRelicCount, `${sample.effectId} 的随机池出处件数`);
    assert.equal(sources.hidden, sample.hiddenCount, `${sample.effectId} 被剔除的不可正常获得条目数`);
    assert.ok(sources.fixed.concat(sources.random).every((row) => row.obtainable));

    const peers = lookup.compatibilityPeers(Core, index, affix, catalog);
    const groupSize = affix.compatibilityId === -1 ? 0 : peers.length + 1;
    assert.equal(groupSize, sample.conflictGroupSize, `${sample.effectId} 的互斥组条数`);
  }
});

test("双端对照：3 件遗物的槽位池结论与 macOS 端逐字段一致", () => {
  for (const sample of RELIC_PARITY) {
    const summary = lookup.relicSlotSummary(Core, index, sample.relicId, 8);
    assert.equal(summary.name, sample.name, `遗物 ${sample.relicId} 的名称`);
    assert.equal(summary.kindLabel, sample.kindLabel, `遗物 ${sample.relicId} 的种类标签`);
    assert.equal(summary.colorLabel, sample.colorLabel, `遗物 ${sample.relicId} 的颜色标签`);
    assert.equal(summary.deep, sample.deep);
    assert.equal(summary.unique, sample.unique);
    assert.equal(summary.obtainable, true, `遗物 ${sample.relicId} 应判为正常可获得`);
    assert.equal(summary.slotCount, sample.slotCount, `遗物 ${sample.relicId} 的孔数`);
    assert.equal(summary.curseSlotCount, sample.curseSlotCount, `遗物 ${sample.relicId} 的诅咒槽数`);
    assert.deepEqual(summary.slots.map((slot) => slot.poolId), sample.slotPools);
    assert.deepEqual(summary.slots.map((slot) => slot.label), sample.slotLabels);
    assert.deepEqual(summary.slots.map((slot) => slot.size), sample.slotSizes);
    assert.deepEqual(
      summary.fixedEffects ? summary.fixedEffects.map((item) => item.effectId) : null,
      sample.fixedEffectIds
    );

    if (sample.deepGroups) {
      assert.deepEqual(summary.poolGroups.map((group) => [group.poolId, group.count]), sample.deepGroups,
        `深夜遗物 ${sample.relicId} 的按池归并`);
      // 槽位模板只保证 A 槽数 = 诅咒槽数
      const aCount = summary.slots.filter((slot) => slot.poolId === 2000000).length;
      assert.equal(aCount, sample.curseSlotCount);
    } else {
      assert.equal(summary.poolGroups, null);
    }
  }

  assert.equal(lookup.searchRelics(Core, index, "", { limit: 10000 }).total, 768,
    "两端的「可查遗物」件数都应是 768 件");
});
