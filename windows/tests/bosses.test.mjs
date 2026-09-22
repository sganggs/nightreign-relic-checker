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

test("深夜徽标扫描整张卡：首条 isMain 没有深夜值不等于整张卡没有", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  const byUid = new Map(items.map((item) => [item.uid, item]));

  // menuId 12 = 格诺斯塔·永夜之王：6 条 fights 里 3 条有 deepOfNight，但首条 isMain 没有。
  const gnoster = byUid.get("nl:12");
  assert.ok(gnoster);
  assert.equal(Boolean(B.mainEntry(gnoster.entries).deepOfNight), false, "首条 isMain 确实没有深夜值");
  assert.equal(B.deepCoverage(gnoster), "some", "整张卡应判为「部分行有深夜数值」");

  const allDeep = items.find((item) => item.entries.length && item.entries.every((e) => e.deepOfNight));
  assert.equal(B.deepCoverage(allDeep), "all");

  const noDeep = items.find((item) => item.entries.length && item.entries.every((e) => !e.deepOfNight));
  assert.equal(B.deepCoverage(noDeep), "none");
  assert.equal(B.deepCoverage({ entries: [] }), "none");

  // 代表行没有深夜值、卡里其余行却有的卡片，一张都不能漏判成 none。
  const misjudged = items.filter((item) => {
    const main = B.mainEntry(item.entries);
    return B.deepCoverage(item) !== "none" && !(main && main.deepOfNight);
  }).map((item) => item.uid);
  assert.deepEqual(
    misjudged.sort(),
    ["nb:Dreg Wormface@7660", "nl:12", "nl:13", "nl:18"],
    "格诺斯塔 / 玛利斯 / 哈尔莫妮亚·救世旗手 与废弃物蚯蚓脸靠扫描全部行才判得对"
  );
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

test("GROUP_LABELS 覆盖数据集里出现的全部档位分组", () => {
  const groups = new Set(
    Object.values(data.scalingTiers).map((tier) => tier.group).filter(Boolean)
  );
  for (const group of groups) {
    assert.ok(B.GROUP_LABELS[group], `档位分组缺少中文标签：${group}`);
  }
});
