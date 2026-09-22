// 首领数据页（renderer/pages/bosses.js）纯计算层测试。
// 口径以 data/nightreign-bosses-v1.03.5.json 的字段说明为准：
//   hp 已含常驻缩放；多人血量 = hp × scaling.<duo|trio>.hp；
//   有效韧性 = poise / (poiseTakenBase × scaling.<tier>.poiseTaken)。
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const Core = require("../renderer/core.js");
const Page = require("../renderer/pages/bosses.js");
const B = Page._internals;

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const data = JSON.parse(readFileSync(path.join(repoRoot, "windows", "resources", "bosses.json"), "utf8"));

const allEntries = [
  ...data.nightlords.flatMap((lord) => lord.fights),
  ...data.nightBosses.flatMap((boss) => boss.variants),
];

test("模块注册：导出 init / refresh，不依赖 window", () => {
  assert.equal(typeof Page.init, "function");
  assert.equal(typeof Page.refresh, "function");
  assert.equal(typeof globalThis.NightreignPages, "undefined", "node 下不应尝试注册页面");
});

test("数据集本身就是 schema 2，且能被页面读懂", () => {
  assert.equal(data.bossesSchemaVersion, 2);
  assert.ok(data.nightlords.length > 0);
  assert.ok(data.nightBosses.length > 0);
  assert.ok(Array.isArray(data.caveats) && data.caveats.length > 0, "页面底部要展示 caveats");
  assert.ok(Object.keys(data.scalingTiers).length > 0);
});

test("tierKey：1 人无缩放，2/3 人取 duo/trio", () => {
  assert.equal(B.tierKey(1), null);
  assert.equal(B.tierKey(2), "duo");
  assert.equal(B.tierKey(3), "trio");
  assert.equal(B.tierKey(0), null);
});

test("血量：1 人直接用 hp（已含常驻缩放），多人 = hp × scaling.hp", () => {
  const gladius = data.nightlords.find((lord) => lord.menuId === 0);
  const main = B.mainEntry(gladius.fights);
  assert.equal(main.isMain, true);
  assert.equal(main.hp, Math.round(main.hpBase * main.hpMultiplier), "hp 应等于 hpBase × hpMultiplier");

  assert.equal(B.computeStats(main, 1, false).hp, main.hp);
  assert.equal(B.computeStats(main, 2, false).hp, Math.round(main.hp * main.scaling.duo.hp));
  assert.equal(B.computeStats(main, 3, false).hp, Math.round(main.hp * main.scaling.trio.hp));
  // 最终 Boss 档位：双人 ×2、三人 ×3
  assert.equal(B.computeStats(main, 2, false).hp, main.hp * 2);
  assert.equal(B.computeStats(main, 3, false).hp, main.hp * 3);
});

test("有效韧性 = poise / (poiseTakenBase × scaling.poiseTaken)", () => {
  const entry = allEntries.find((item) => item.poise > 0 && item.scaling && item.scaling.duo);
  const solo = B.computeStats(entry, 1, false);
  const duo = B.computeStats(entry, 2, false);
  assert.equal(solo.effectivePoise, entry.poise / entry.poiseTakenBase);
  assert.equal(duo.effectivePoise, entry.poise / (entry.poiseTakenBase * entry.scaling.duo.poiseTaken));
  assert.ok(duo.effectivePoise > solo.effectivePoise, "多人承受削韧变低 → 有效韧性变高");
});

test("poise = -1（不吃削韧）时有效韧性为 null", () => {
  const entry = allEntries.find((item) => item.poise === -1);
  assert.ok(entry, "数据集里应存在 poise = -1 的行");
  const stats = B.computeStats(entry, 2, false);
  assert.equal(stats.poise, null);
  assert.equal(stats.effectivePoise, null);
  assert.equal(B.fmtPoise(stats.effectivePoise), "不吃削韧");
});

test("削韧恢复 / 异常发动伤害 / 异常累积按人数叠乘", () => {
  const entry = allEntries.find((item) => item.scaling && item.scaling.trio && item.poiseRecover > 0);
  const trio = B.computeStats(entry, 3, false);
  assert.equal(
    trio.poiseRecover,
    entry.poiseRecover * entry.poiseRecoverMultiplier * entry.scaling.trio.poiseRecover
  );
  assert.equal(trio.ailmentDamageRate, entry.ailmentDamageRateBase * entry.scaling.trio.ailmentDamageRate);
  assert.equal(trio.buildupRate, entry.scaling.trio.buildupRate);
  assert.equal(B.computeStats(entry, 1, false).buildupRate, 1, "1 人时异常累积倍率为 1");
});

test("深夜：有 deepOfNight 时换用深夜数值，没有时回落常规值", () => {
  assert.equal(B.hasDeepData(data), true);
  assert.equal(B.hasDeepData({ nightlords: [], nightBosses: [] }), false);

  const deepEntry = allEntries.find((item) => item.deepOfNight);
  const normal = B.computeStats(deepEntry, 1, false);
  const deep = B.computeStats(deepEntry, 1, true);
  assert.equal(deep.isDeep, true);
  assert.equal(normal.isDeep, false);
  assert.equal(deep.hp, deepEntry.deepOfNight.hp);
  assert.notEqual(deep.hp, normal.hp);

  const plainEntry = allEntries.find((item) => !item.deepOfNight);
  const plain = B.computeStats(plainEntry, 2, true);
  assert.equal(plain.isDeep, false);
  assert.equal(plain.hp, B.computeStats(plainEntry, 2, false).hp);
});

test("承伤倍率分类：>1 弱点、<1 抗性、=1 正常", () => {
  assert.equal(B.rateClass(1.35), "up");
  assert.equal(B.rateNote(1.35), "弱点");
  assert.equal(B.rateClass(0.5), "down");
  assert.equal(B.rateNote(0.5), "抗性");
  assert.equal(B.rateClass(1), "flat");
  assert.equal(B.rateNote(1), "");

  const gladius = B.mainEntry(data.nightlords.find((lord) => lord.menuId === 0).fights);
  assert.equal(B.rateClass(gladius.damageRates.holy), "up");
  assert.equal(B.rateClass(gladius.damageRates.fire), "down");
});

test("异常抗性 999 判为免疫，并与 immune 列表一致", () => {
  assert.equal(B.isImmune(999), true);
  assert.equal(B.isImmune(542), false);
  for (const entry of allEntries) {
    const immune = B.AILMENTS.filter((item) => B.isImmune(entry.resist[item.key])).map((item) => item.key);
    assert.deepEqual(immune.sort(), [...entry.immune].sort(), "immune 列表应等于 resist 里 999 的项");
  }
});

test("名字缺失时的显示口径与灰色徽标", () => {
  const englishOnly = data.nightBosses.find((boss) => boss.nameSource === "english-only");
  assert.ok(englishOnly, "数据集里应存在 english-only 的 Boss");
  const infoEn = B.displayName(englishOnly);
  assert.equal(infoEn.primary, englishOnly.nameEn);
  assert.equal(infoEn.fallback, true);
  assert.deepEqual(B.nameBadge(infoEn, englishOnly.nameSource), { text: "仅英文名", kind: "gray" });

  const fallback = data.nightBosses.find((boss) => boss.nameSource === "chrid-fallback");
  assert.ok(fallback, "数据集里应存在 chrid-fallback 的 Boss");
  const infoZh = B.displayName(fallback);
  assert.match(infoZh.primary, /^未知敌人 c\d+$/);
  assert.equal(infoZh.fallback, true);
  assert.deepEqual(B.nameBadge(infoZh, fallback.nameSource), { text: "无游戏内名称", kind: "gray" });

  const normal = data.nightBosses.find((boss) => boss.nameSource === "npcname" && !boss.nameInferred);
  assert.equal(B.nameBadge(B.displayName(normal), normal.nameSource), null);
});

test("buildItems：夜王 / 守夜 / 野外三组齐全，主键用 id 而不是 nameEn", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  assert.equal(items.length, data.nightlords.length + data.nightBosses.length);

  const uids = new Set(items.map((item) => item.uid));
  assert.equal(uids.size, items.length, "uid 必须唯一");

  const counts = items.reduce((acc, item) => {
    acc[item.group] = (acc[item.group] || 0) + 1;
    return acc;
  }, {});
  assert.equal(counts.nightlords, data.nightlords.length);
  assert.equal(counts.night + counts.field, data.nightBosses.length, "每个 Boss 恰好一张卡片");

  // nameEn 会重复，页面必须用 id 做 key
  const nameEnList = data.nightBosses.map((boss) => boss.nameEn);
  assert.ok(new Set(nameEnList).size < nameEnList.length, "nameEn 本就不唯一");

  items.forEach((item) => {
    assert.ok(item.main || item.entries.length === 0, "每张卡片都要有代表数值行");
  });
});

test("夜王卡片带远征名与变体名，永夜之王用 variantKey 判定", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  const everdark = data.nightlords.find((lord) => lord.variantKey === "everdark");
  const card = items.find((item) => item.uid === "nl:" + everdark.menuId);
  assert.equal(card.variantName, everdark.variantNameZh);
  assert.equal(card.variantPill.text, "永夜之王");
  assert.equal(card.expedition, everdark.expeditionZh);

  // menuId 18 的 everdark 字段是 false，但它是「救世旗手」变体
  const bearers = data.nightlords.find((lord) => lord.variantKey === "standardBearers");
  if (bearers) {
    assert.equal(bearers.everdark, false);
    const bearerCard = items.find((item) => item.uid === "nl:" + bearers.menuId);
    assert.equal(bearerCard.variantPill.text, "救世旗手");
  }

  const normal = items.find((item) => item.uid === "nl:0");
  assert.equal(normal.variantPill, null);
});

test("filterItems：按分组过滤，中文 / 英文名都能搜到", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  const lords = B.filterItems(items, "nightlords", "", Core.foldForSearch);
  assert.equal(lords.length, data.nightlords.length);

  const zh = B.filterItems(items, "nightlords", "格拉狄乌斯", Core.foldForSearch);
  assert.ok(zh.length >= 2, "普通形态与永夜之王都应命中");
  zh.forEach((item) => assert.equal(item.name, "格拉狄乌斯"));

  const en = B.filterItems(items, "nightlords", "GLADIUS", Core.foldForSearch);
  assert.equal(en.length, zh.length, "英文名大小写不敏感");

  const expedition = B.filterItems(items, "nightlords", "三头野兽", Core.foldForSearch);
  assert.ok(expedition.length >= 1, "远征名也应可搜");

  assert.equal(B.filterItems(items, "field", "绝无此物", Core.foldForSearch).length, 0);
});

test("数字格式化", () => {
  assert.equal(B.fmtInt(11328), "11,328");
  assert.equal(B.fmtInt(176), "176");
  assert.equal(B.fmtInt(1234567), "1,234,567");
  assert.equal(B.fmtNumber(0.5, 2), "0.5");
  assert.equal(B.fmtNumber(1.35, 2), "1.35");
  assert.equal(B.fmtNumber(null, 2), "—");
  assert.equal(B.fmtMul(2), "×2");
  assert.equal(B.fmtMul(0.889), "×0.889");
  assert.equal(B.fmtPoise(218.18181818), "218.2");
});

test("每条数值行都能算出有限的血量，且档位 id 能查到 scalingTiers", () => {
  for (const entry of allEntries) {
    for (const party of [1, 2, 3]) {
      const stats = B.computeStats(entry, party, false);
      assert.ok(Number.isFinite(stats.hp) && stats.hp > 0, "血量必须是正数");
      assert.ok(Number.isFinite(stats.ailmentDamageRate));
    }
    if (entry.scalingId !== null && entry.scalingId !== undefined) {
      assert.ok(data.scalingTiers[String(entry.scalingId)], `scalingTiers 缺少档位 ${entry.scalingId}`);
    }
  }
});

// ---------------------------------------------------------------- 审查回归

test("weakness 只有夜王有：守夜 / 野外 Boss 不得被写成「官方标注：无弱点」", () => {
  // 数据侧前提：nightBosses 根本没有 weakness 字段（caveat 8：weakness 来自 NightBossMenuParam）。
  assert.equal(data.nightBosses.some((boss) => "weakness" in boss), false);
  assert.equal(data.nightlords.every((lord) => Array.isArray(lord.weakness)), true);

  const items = B.buildItems(data, Core.foldForSearch);
  for (const item of items) {
    if (item.kind === "nightlord") {
      assert.ok(Array.isArray(item.weakness), "夜王要带官方弱点数组");
    } else {
      assert.equal(item.weakness, null, "守夜 / 野外 Boss 没有官方弱点数据，必须是 null 而不是空数组");
    }
  }
});

test("承伤偏高：代表行 damageRates > 1 的属性按倍率降序取前几个", () => {
  assert.deepEqual(
    B.topDamageTypes({ damageRates: { standard: 1, fire: 2, holy: 1.4, magic: 0.5 } }, 3),
    [{ zh: "火", rate: 2 }, { zh: "圣", rate: 1.4 }]
  );
  assert.deepEqual(B.topDamageTypes({ damageRates: { standard: 1, fire: 0.9 } }, 3), []);
  assert.deepEqual(B.topDamageTypes(null, 3), []);

  // 守夜 / 野外卡片里大多数代表行其实是有「弱点」的，正是这些卡被写成了「无弱点」。
  const items = B.buildItems(data, Core.foldForSearch);
  const hot = items.filter((item) => item.kind === "boss" && B.topDamageTypes(item.main, 3).length);
  assert.ok(hot.length > 60, `代表行承伤 > 1 的 Boss 应该很多，实际 ${hot.length}`);
});

test("深夜徽标扫描整张卡：代表行没有深夜值不等于整张卡没有", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  const byUid = new Map(items.map((item) => [item.uid, item]));

  // menuId 12 = 格诺斯塔·永夜之王：6 条 fights 里 3 条有 deepOfNight。
  const gnoster = byUid.get("nl:12");
  assert.ok(gnoster);
  assert.equal(B.deepCoverage(gnoster), "some", "整张卡应判为「部分行有深夜数值」");

  const allDeep = items.find((item) => item.entries.length && item.entries.every((e) => e.deepOfNight));
  assert.equal(B.deepCoverage(allDeep), "all");

  const noDeep = items.find((item) => item.entries.length && item.entries.every((e) => !e.deepOfNight));
  assert.equal(B.deepCoverage(noDeep), "none");
  assert.equal(B.deepCoverage({ entries: [] }), "none");

  // 代表行没有深夜值、卡里其余行却有的卡片，一张都不能漏判成 none。
  // 与 macOS 端 BossDataChecks 的同名断言对着同一组卡片。
  const misjudged = items.filter((item) => {
    const main = B.representativeEntry(item.entries, item.group);
    return B.deepCoverage(item) !== "none" && !(main && main.deepOfNight);
  }).map((item) => item.uid);
  assert.deepEqual(
    misjudged.sort(),
    ["nb:Dreg Wormface@7660", "nl:18"],
    "哈尔莫妮亚·救世旗手与废弃物蚯蚓脸靠扫描全部行才判得对"
  );
  assert.equal(
    items.filter((item) => B.deepCoverage(item) !== "none").length, 22,
    "带深夜专属数值的卡片共 22 张（与 macOS 自检同一个数）"
  );
  assert.equal(items.filter((item) => B.deepCoverage(item) === "all").length, 4);
});

test("深夜数值并非夜王独有：守夜 / 野外里也有带 deepOfNight 的条目", () => {
  // 审查意见称「30 条深夜行全部属于 nightlords」，实际 nightBosses 里有 14 条 / 12 张卡。
  const bossDeepRows = data.nightBosses.flatMap((boss) => boss.variants).filter((v) => v.deepOfNight);
  assert.ok(bossDeepRows.length > 0, "nightBosses 确实存在深夜行，徽标不能只画给夜王");

  const items = B.buildItems(data, Core.foldForSearch);
  const deepBossCards = items.filter((item) => item.kind === "boss" && B.deepCoverage(item) !== "none");
  assert.equal(deepBossCards.length, 12);
  assert.ok(deepBossCards.some((item) => item.groups.includes("field")));
});

test("分组按 tiers 判定：同属守夜与野外的 Boss 两个分组都能找到", () => {
  assert.deepEqual(B.bossGroups({ tier: "night", tiers: ["field", "night"] }), ["night", "field"]);
  assert.deepEqual(B.bossGroups({ tier: "field", tiers: ["field"] }), ["field"]);
  assert.deepEqual(B.bossGroups({ tier: "night" }), ["night"]);

  const dual = data.nightBosses.filter((boss) => new Set(boss.tiers || [boss.tier]).size > 1);
  assert.equal(dual.length, 6, "数据里有 6 组 tiers 同时含 field 与 night");

  const items = B.buildItems(data, Core.foldForSearch);
  const night = B.filterItems(items, "night", "", Core.foldForSearch);
  const field = B.filterItems(items, "field", "", Core.foldForSearch);
  assert.equal(night.length, data.nightBosses.filter((b) => (b.tiers || [b.tier]).includes("night")).length);
  assert.equal(field.length, data.nightBosses.filter((b) => (b.tiers || [b.tier]).includes("field")).length);
  assert.equal(night.length + field.length, data.nightBosses.length + dual.length);

  for (const boss of dual) {
    const uid = "nb:" + boss.id;
    assert.ok(night.some((item) => item.uid === uid), `${boss.id} 应出现在守夜分组`);
    assert.ok(field.some((item) => item.uid === uid), `${boss.id} 应出现在野外分组`);
  }

  // 大金河马的「基准」行 threat 就是 field，之前在野外分组里彻底搜不到。
  const hippo = B.filterItems(items, "field", "河马", Core.foldForSearch);
  assert.ok(hippo.some((item) => item.uid === "nb:Large Golden Hippopotamus@5010"));
});

test("搜索串不含 nameSource 内部枚举值", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  for (const token of ["npcname", "chrid-fallback", "npcparam-nameid", "english-only"]) {
    assert.equal(
      B.filterItems(items, "night", token, Core.foldForSearch).length, 0,
      `「${token}」是内部枚举值，不该命中任何卡片`
    );
  }
  // 提示语里写明支持的几种搜法仍然有效。
  assert.ok(B.filterItems(items, "night", "7800", Core.foldForSearch).length > 0, "chrId 仍可搜");
  const manual = data.nightBosses.find((boss) => boss.nameSource === "manual" && boss.nameZh);
  assert.ok(B.filterItems(items, "night", manual.nameZh, Core.foldForSearch).length +
    B.filterItems(items, "field", manual.nameZh, Core.foldForSearch).length > 0, "中文名仍可搜");
});

test("poise = 0 与 poise = -1 语义分开：无削韧槽 ≠ 不吃削韧", () => {
  const zero = allEntries.find((item) => item.poise === 0);
  assert.ok(zero, "数据集里应存在 poise = 0 的行");
  const zeroStats = B.computeStats(zero, 1, false);
  assert.equal(zeroStats.poiseKind, "zero");
  assert.equal(zeroStats.effectivePoise, null);
  assert.equal(B.fmtPoise(zeroStats.effectivePoise, zeroStats.poiseKind), "无削韧槽");

  const negative = allEntries.find((item) => item.poise === -1);
  const negStats = B.computeStats(negative, 1, false);
  assert.equal(negStats.poiseKind, "none");
  assert.equal(B.fmtPoise(negStats.effectivePoise, negStats.poiseKind), "不吃削韧");

  const normal = allEntries.find((item) => item.poise > 0);
  assert.equal(B.computeStats(normal, 1, false).poiseKind, "value");
});

// ------------------------------------------------------ 双端一致性（macOS 对照）

test("夜王代表行取主战行里血量最高的一条，而不是第一条", () => {
  const multiMain = data.nightlords.filter((lord) => lord.fights.filter((f) => f.isMain).length > 1);
  assert.equal(multiMain.length, 5, "当前数据里有 5 位夜王带多条 isMain 行");

  for (const lord of multiMain) {
    const mains = lord.fights.filter((f) => f.isMain);
    const rep = B.representativeEntry(lord.fights, "nightlords");
    assert.equal(rep.isMain, true);
    assert.equal(rep.hp, Math.max(...mains.map((f) => f.hp)), `${lord.nameZh} 应取血量最高的主战行`);
  }

  // 玛利斯·永夜之王：一阶段 3172 排在前面，二阶段 29453 才是该显示的那条。
  const maris = data.nightlords.find((lord) => lord.menuId === 13);
  const marisMains = maris.fights.filter((f) => f.isMain);
  assert.equal(marisMains[0].hp, 3172, "首条 isMain 确实是血量更低的一阶段");
  assert.equal(B.representativeEntry(maris.fights, "nightlords").npcId, 75410000);
  assert.equal(B.representativeEntry(maris.fights, "nightlords").hp, 29453);

  // 格诺斯塔·永夜之王 5 条主战行里最高的是弗堤士一阶段 8564。
  assert.equal(B.representativeEntry(data.nightlords.find((l) => l.menuId === 12).fights, "nightlords").hp, 8564);

  // 同血量按 npcId 升序兜底，两端排序结果一致。
  const tie = [
    { hp: 100, npcId: 20, isMain: true },
    { hp: 100, npcId: 10, isMain: true },
    { hp: 90, npcId: 1, isMain: true },
  ];
  assert.equal(B.representativeEntry(tie, "nightlords").npcId, 10);
});

test("守夜 / 野外卡片的代表行随分组切换，不再恒取 variants[0]", () => {
  const apostle = data.nightBosses.find((boss) => boss.id === "Godskin Apostle@3560");
  assert.equal(apostle.variants[0].threat, "night", "变体按守夜优先排序，rows[0] 是守夜行");

  const night = B.representativeEntry(apostle.variants, "night");
  const field = B.representativeEntry(apostle.variants, "field");
  assert.equal(night.npcId, 35600900);
  assert.equal(field.npcId, 35600020, "野外分组要取「封印监牢」，不是血量更高的守夜行");
  assert.equal(field.threat, "field");
  assert.ok(night.hp > field.hp, "守夜行血量更高，正是它会盖掉野外数值");

  const dual = data.nightBosses.filter((boss) => new Set(boss.tiers || [boss.tier]).size > 1);
  for (const boss of dual) {
    assert.equal(B.representativeEntry(boss.variants, "night").threat, "night", boss.id);
    assert.equal(B.representativeEntry(boss.variants, "field").threat, "field", boss.id);
  }

  // 只有一种档位的组不受影响：按分组取出来的仍是血量最高的那行。
  const single = data.nightBosses.find((boss) => (boss.tiers || [boss.tier]).length === 1 && boss.variants.length > 2);
  const rep = B.representativeEntry(single.variants, single.tier);
  assert.equal(rep.hp, Math.max(...single.variants.map((v) => v.hp)));

  // 候选行：夜王收敛到 isMain，守夜 / 野外收敛到该档位。
  assert.equal(B.candidateEntries(apostle.variants, "field").length, 4);
  assert.equal(B.candidateEntries(apostle.variants, "nightlords").length, apostle.variants.length);
  assert.equal(B.candidateEntries(data.nightlords.find((l) => l.menuId === 13).fights, "nightlords").length, 2);
});

test("搜索：纯数字按行号前缀匹配，文本串不含分组名与内部枚举值", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  const fold = Core.foldForSearch;

  // 被合并掉的 npcId 也能搜到（格拉狄乌斯主战行是合并行）。
  assert.ok(B.filterItems(items, "nightlords", "75001020", fold).some((item) => item.name === "格拉狄乌斯"));
  assert.ok(B.filterItems(items, "nightlords", "75000020", fold).some((item) => item.name === "格拉狄乌斯"));
  // 「1」不该命中任何夜王：夜王的 npcId 都以 75/76/46 开头。
  assert.equal(B.filterItems(items, "nightlords", "1", fold).length, 0);
  // chrId 与 NpcName ID 仍可搜。
  assert.ok(B.filterItems(items, "night", "7800", fold).length > 0, "chrId 仍可搜");
  const withNameId = data.nightBosses.find((boss) => boss.npcNameId);
  assert.ok(
    B.filterItems(items, withNameId.tier, String(withNameId.npcNameId), fold)
      .some((item) => item.uid === "nb:" + withNameId.id),
    "npcNameId 也应能搜到"
  );
  // 分组名不进搜索串。
  const fieldCount = B.filterItems(items, "field", "", fold).length;
  assert.ok(B.filterItems(items, "field", "野外", fold).length < fieldCount);
  // 官方弱点文字可搜（与 macOS 端同一组搜索键）。
  assert.ok(B.filterItems(items, "nightlords", "圣", fold).length > 0);

  assert.equal(B.itemMatches({ search: "abc", numbers: ["12345"] }, ""), true);
  assert.equal(B.itemMatches({ search: "abc", numbers: ["12345"] }, "123"), true);
  assert.equal(B.itemMatches({ search: "abc", numbers: ["12345"] }, "234"), false, "数字只按前缀匹配");
  assert.equal(B.itemMatches({ search: "abc", numbers: [] }, "b"), true);
});

test("双端对照表：同一条行 + 同一组输入，五个数值必须与 macOS 完全一致", () => {
  // 同一张表也写在 macos/Sources/RelicCoreChecks/BossDataChecks.swift（12b 节）里。
  const rows = new Map(allEntries.map((entry) => [entry.npcId, entry]));
  assert.equal(rows.size, allEntries.length, "npcId 在全量行里唯一，对照表才能按它定位");

  const cases = [
    ["格拉狄乌斯 · 远征首领 / 1 人", 75000020, 1, false, 11328, 120, "value", 0.058, 0.5, 1],
    ["格拉狄乌斯 · 远征首领 / 2 人", 75000020, 2, false, 22656, 218.181818, "value", 0.0319, 0.375, 0.85],
    ["格拉狄乌斯 · 远征首领 / 3 人", 75000020, 3, false, 33984, 400, "value", 0.0174, 0.25, 0.7],
    ["玛利斯 · 永夜之王 · 二阶段 / 2 人", 75410000, 2, false, 58906, 1090.909091, "value", 0, 0.375, 0.85],
    ["史柴格斯 · 远征首领 / 3 人 · 深夜", 76100010, 3, true, 34665, 500.160051, "value", 0.0174, 0.25, 0.7],
    ["神皮使徒 · 守夜代表行 / 2 人", 35600900, 2, false, 9551, 145.454545, "value", 0.1595, 0.46, 0.955],
    ["神皮使徒 · 野外代表行 / 2 人", 35600020, 2, false, 6535, 106.666667, "value", 0.2175, 0.82, 0.889],
    ["大型黄金河马 · 守夜代表行 / 3 人", 50100010, 3, false, 17747, 266.666667, "value", 0.087, 0.315, 0.778],
    ["大型黄金河马 · 野外代表行 / 3 人", 50100000, 3, false, 5606, 160, "value", 0.145, 0.95, 0.97],
    ["未知敌人 c7931（poise = 0）/ 2 人", 79310000, 2, false, 6851, null, "zero", 0.1595, 0.46, 0.955],
    ["鲜血君王的长枪 · 召唤物（poise = -1）/ 2 人", 48010010, 2, false, 674, null, "none", 0.0319, 0.375, 0.85],
  ];

  for (const [title, npcId, party, deep, hp, poise, kind, recover, ailment, buildup] of cases) {
    const entry = rows.get(npcId);
    assert.ok(entry, `对照表找不到 npcId ${npcId}（${title}）`);
    const stats = B.computeStats(entry, party, deep);
    assert.equal(stats.hp, hp, `${title}：血量`);
    assert.equal(stats.poiseKind, kind, `${title}：削韧槽语义`);
    if (poise === null) {
      assert.equal(stats.effectivePoise, null, `${title}：有效韧性应算不出来`);
    } else {
      assert.ok(Math.abs(stats.effectivePoise - poise) < 1e-4, `${title}：有效韧性 ${stats.effectivePoise}`);
    }
    assert.ok(Math.abs(stats.poiseRecover - recover) < 1e-6, `${title}：削韧恢复 ${stats.poiseRecover}`);
    assert.ok(Math.abs(stats.ailmentDamageRate - ailment) < 1e-6, `${title}：异常发动伤害 ${stats.ailmentDamageRate}`);
    assert.ok(Math.abs(stats.buildupRate - buildup) < 1e-6, `${title}：异常累积 ${stats.buildupRate}`);
  }

  // 对照表里的代表行必须就是折叠态会选中的那一行。
  const hippo = data.nightBosses.find((boss) => boss.id === "Large Golden Hippopotamus@5010");
  assert.equal(B.representativeEntry(hippo.variants, "night").npcId, 50100010);
  assert.equal(B.representativeEntry(hippo.variants, "field").npcId, 50100000);
  assert.equal(B.representativeEntry(data.nightlords.find((l) => l.menuId === 0).fights, "nightlords").npcId, 75000020);
});

test("收录统计与 macOS 的 inventorySummary 是同一组数字", () => {
  const counts = { night: 0, field: 0, both: 0, rows: 0 };
  for (const boss of data.nightBosses) {
    const groups = B.bossGroups(boss);
    if (groups.includes("night")) counts.night += 1;
    if (groups.includes("field")) counts.field += 1;
    if (groups.length > 1) counts.both += 1;
    counts.rows += boss.variants.length;
  }
  for (const lord of data.nightlords) counts.rows += lord.fights.length;

  assert.equal(data.nightlords.length, 18);
  assert.equal(counts.night, 51);
  assert.equal(counts.field, 72);
  assert.equal(counts.both, 6);
  assert.equal(counts.rows, 384);
});

test("GROUP_LABELS 覆盖数据集里出现的全部档位分组", () => {
  const groups = new Set(
    Object.values(data.scalingTiers).map((tier) => tier.group).filter(Boolean)
  );
  for (const group of groups) {
    assert.ok(B.GROUP_LABELS[group], `档位分组缺少中文标签：${group}`);
  }
  // 与 macOS 端 BossScalingGroup.title(for:) 一一对应。
  assert.equal(B.GROUP_LABELS["Field Boss Threat"], "野外首领威胁档");
  assert.equal(B.GROUP_LABELS["Night Boss Threat"], "守夜首领威胁档");
  assert.equal(B.GROUP_LABELS["Final Boss Threat"], "最终首领威胁档");
  assert.ok(Object.values(data.scalingTiers).some((tier) => !tier.group), "数据里存在 group = null 的档位");
});

test("分组名与 macOS 的 BossCard.Group.title 一致", () => {
  assert.deepEqual(B.GROUP_TITLES, { nightlords: "夜王", night: "守夜首领", field: "野外首领" });
});
