// 首领数据页（renderer/pages/bosses.js）纯计算层测试。
// 数值口径以 bossesSchemaVersion 3 的字段说明为准（v4 只增 roles 等场合字段，数值不变）；
// 分组口径以 v4 的 roles 为准（出场场合分组的专项测试见 bosses_roles.test.mjs）：
//   常规：hp 已含常驻缩放；多人血量 = hp × scaling.<duo|trio>.hp；
//   深夜：血量 = depthStats[N].hp × scaling.<tier>.hp（depthStats 已含常驻 × 深夜修正 × 深度倍率）；
//   有效韧性 = poise / (poiseTakenBase × scaling.<tier>.poiseTaken)，深夜用 depthStats[N].poiseTakenBase；
//   攻击力 = attackRateBase × scaling.<tier>.attackRate，变异个体的三个倍率再乘一层。
// 「双端对照表」那一节与 macos/Sources/RelicCoreChecks/BossDataChecks.swift 是同一组输入与期望值。
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

test("数据集本身就是 schema 4，且能被页面读懂", () => {
  // schemaVersion 4 相对 3 只增字段（roles / rowRoles / roleEvidence / roleNames /
  // roleSummary / placementMaps…），tier / tiers 与全部数值原样保留；页面改按 roles 分组。
  // 这里钉住版本号，数据契约再变时必须同步改本文件。
  assert.equal(data.bossesSchemaVersion, 4);
  assert.ok(data.nightlords.length > 0);
  assert.ok(data.nightBosses.length > 0);
  assert.ok(Array.isArray(data.caveats) && data.caveats.length > 0, "页面底部要展示 caveats");
  assert.ok(Object.keys(data.scalingTiers).length > 0);
  assert.ok(data.roleNames && data.roleSummary, "v4 的出场场合字段必须在");
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

test("深夜：模式换成深度 1–5，血量直接取 depthStats[N].hp", () => {
  assert.equal(B.hasDepthData(data), true);
  assert.equal(B.hasDepthData({ nightlords: [], nightBosses: [] }), false);

  // depthValue 把下拉里的一切取值归一化成 0–5，别让 depthStats["true"] 这种取法蒙混过关。
  assert.equal(B.depthValue(0), 0);
  assert.equal(B.depthValue(3), 3);
  assert.equal(B.depthValue("4"), 4);
  assert.equal(B.depthValue(true), 0, "布尔不再是合法模式（原来的深夜开关已经换成下拉）");
  assert.equal(B.depthValue(null), 0);
  assert.equal(B.depthValue(9), 5);
  assert.equal(B.depthValue(-1), 0);

  // schemaVersion 3：394 条数值行全都有 depthStats（深度 1–5 各一组）。
  assert.equal(allEntries.every((entry) => entry.depthStats), true);
  for (const entry of allEntries) {
    for (const depth of [1, 2, 3, 4, 5]) {
      const stats = B.computeStats(entry, 1, depth, null);
      assert.equal(stats.depth, depth);
      assert.equal(stats.hasDepth, true);
      assert.equal(stats.hp, entry.depthStats[String(depth)].hp, `npcId ${entry.npcId} 深度 ${depth}`);
      assert.equal(stats.attackRate, entry.depthStats[String(depth)].attackRateBase);
    }
  }

  // v2 的 deepOfNight 只算到「深夜修正」，缺了深度倍率那一乘——现在 depthStats 已经含齐。
  const deepEntry = allEntries.find((item) => item.deepOfNight);
  assert.ok(B.computeStats(deepEntry, 1, 1, null).hp > deepEntry.deepOfNight.hp,
    "深度 1 的血量应比只算深夜修正的旧值高");

  // 没有 depthStats 的行（当前数据里没有，页面仍要优雅降级）回落到常规值并标记 hasDepth = false。
  const bare = { hp: 1000, hpBase: 1000, hpMultiplier: 1, poise: 100, poiseTakenBase: 1 };
  const bareStats = B.computeStats(bare, 1, 4, null);
  assert.equal(bareStats.hasDepth, false);
  assert.equal(bareStats.hp, 1000);
  assert.equal(B.depthRows(bare, 1, null), null, "无 depthStats 时深度小表为 null（页面写「该行无深夜数值」）");
});

test("深夜：深度换算后再乘人数，有效韧性分母换成 depthStats[N].poiseTakenBase", () => {
  const gladius = allEntries.find((entry) => entry.npcId === 75000020);
  const depth5 = gladius.depthStats["5"];

  const solo = B.computeStats(gladius, 1, 5, null);
  const trio = B.computeStats(gladius, 3, 5, null);
  assert.equal(solo.hp, depth5.hp);
  assert.equal(trio.hp, depth5.hp * gladius.scaling.trio.hp, "深度血量再乘人数缩放");
  assert.equal(trio.hp, 73404);
  assert.equal(trio.hpSingle, 24468);
  assert.ok(Math.abs(solo.effectivePoise - gladius.poise / depth5.poiseTakenBase) < 1e-9);
  assert.ok(
    Math.abs(trio.effectivePoise - gladius.poise / (depth5.poiseTakenBase * gladius.scaling.trio.poiseTaken)) < 1e-9
  );
  assert.equal(trio.attackRate, depth5.attackRateBase, "格拉狄乌斯档位多人不加攻击力");

  // 攻击力涨得比血量快：深度 5 的伤害是深度 1 的 2.27 倍，血量只有 1.32 倍。
  const d1 = B.computeStats(gladius, 1, 1, null);
  assert.ok(solo.attackRate / d1.attackRate > 2.2);
  assert.ok(solo.hp / d1.hp < 1.8);

  // 常规模式仍然是 depth = 0、走 hp 字段。
  const normal = B.computeStats(gladius, 1, 0, null);
  assert.equal(normal.depth, 0);
  assert.equal(normal.hasDepth, false);
  assert.equal(normal.hp, gladius.hp);
  assert.equal(normal.attackRate, gladius.attackRateBase);
});

test("深夜各深度小表：五行都按当前人数换算，当前深度可高亮", () => {
  const bird = allEntries.find((entry) => entry.npcId === 49800030);
  const rows = B.depthRows(bird, 2, null);
  assert.equal(rows.length, 5);
  rows.forEach((row, index) => {
    assert.equal(row.depth, index + 1);
    assert.equal(row.hp, B.computeStats(bird, 2, row.depth, null).hp);
    assert.equal(row.attackRate, bird.depthStats[String(row.depth)].attackRateBase * bird.scaling.duo.attackRate);
    assert.equal(row.poiseTaken, bird.depthStats[String(row.depth)].poiseTakenBase * bird.scaling.duo.poiseTaken);
  });
  // 血量与攻击倍率都随深度单调上升
  for (let i = 1; i < rows.length; i += 1) {
    assert.ok(rows[i].hp >= rows[i - 1].hp);
    assert.ok(rows[i].attackRate > rows[i - 1].attackRate);
  }
});

test("变异个体：选中档位后在其它缩放之上再乘一层", () => {
  // 链路：NpcParam.chaosMatchingSpEffectSetParamId → mutationSetId / mutationPool → mutations[id]。
  assert.ok(Object.keys(data.mutations).length > 0);
  const withPool = allEntries.filter((entry) => Array.isArray(entry.mutationPool) && entry.mutationPool.length);
  assert.equal(withPool.length, 327, "327 条数值行能变异");
  for (const entry of withPool) {
    for (const id of entry.mutationPool) {
      assert.ok(data.mutations[String(id)], `mutations 缺少档位 ${id}`);
    }
  }

  const bird = allEntries.find((entry) => entry.npcId === 49800030);
  const mutation = data.mutations["113340"];
  assert.deepEqual(
    [mutation.hp, mutation.attackRate, mutation.runeRate],
    [1.15, 1.15, 1.35]
  );

  const plain = B.computeStats(bird, 2, 3, null);
  const mutated = B.computeStats(bird, 2, 3, mutation);
  assert.equal(plain.hasMutation, false);
  assert.equal(mutated.hasMutation, true);
  // 变异倍率是乘在「深度 × 人数」之上的第四层，不是替换
  assert.equal(mutated.hp, Math.round(bird.depthStats["3"].hp * bird.scaling.duo.hp * mutation.hp));
  assert.equal(mutated.hp, 5770);
  assert.equal(mutated.attackRate, plain.attackRate * mutation.attackRate);
  assert.equal(mutated.runeRate, 1.35);
  assert.equal(plain.runeRate, 1, "没选变异时卢恩倍率是 1");
  // 韧性 / 异常相关不受变异影响（mutations 只有 hp / attackRate / runeRate 三个倍率）
  assert.equal(mutated.effectivePoise, plain.effectivePoise);
  assert.equal(mutated.buildupRate, plain.buildupRate);

  assert.equal(B.mutationFor(data, 113340), mutation);
  assert.equal(B.mutationFor(data, "113340"), mutation);
  assert.equal(B.mutationFor(data, ""), null);
  assert.equal(B.mutationFor(data, 999999), null);
  assert.match(B.mutationOptionLabel(113340, mutation), /血量 ×1\.15 · 攻击 ×1\.15 · 卢恩 ×1\.35（档位 113340）/);
});

test("隐藏实体：默认不显示，开关打开后才出现", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  const hidden = items.filter((item) => item.hidden);
  assert.deepEqual(
    hidden.map((item) => item.uid).sort(),
    [
      "nb:Centipede Grub@7711",
      "nb:Lord of Blood Spear@4801",
      "nb:Unknown Enemy (c7931)@7931",
      "nb:Unknown Enemy (c7932)@7932",
    ],
    "4 组召唤物 / 投射物实体"
  );
  // v4：四组的场合都只有「随从/召唤物」（+ 未放置），只落在这两个默认隐藏的分组里；
  // 与另外 8 组只有这两种场合的组一起由同一个开关放出来（12 组，见 bosses_roles.test.mjs）。
  for (const item of hidden) {
    assert.ok(item.groups.includes("summon"), `${item.uid} 在「随从/召唤物」`);
    assert.ok(item.groups.every((group) => B.isHiddenGroup(group)), `${item.uid} 只在默认隐藏的分组里`);
    assert.equal(item.roleHidden, true);
  }
  // 六个默认可见的分组一个隐藏的组都没有，开关不影响条数
  for (const group of ["nightlords", "night", "stronghold", "field", "evergaol", "other"]) {
    assert.equal(
      B.filterItems(items, group, "", Core.foldForSearch).length,
      B.filterItems(items, group, "", Core.foldForSearch, true).length,
      group
    );
  }
  // 搜索也搜不到隐藏实体，除非开关打开
  assert.equal(B.filterItems(items, "summon", "7931", Core.foldForSearch).length, 0);
  assert.equal(B.filterItems(items, "summon", "7931", Core.foldForSearch, true).length, 1);

  // noReward 不等于 hidden：蚯蚓脸 / Storm King / 巨大骷髅躯干不掉奖励，也不是「隐藏实体」；
  // v4 起它们只有「随从/召唤物」「未放置」场合，另由 roleHidden 默认收起（同一个开关）。
  const noRewardVisible = items.filter((item) => item.noReward && !item.hidden);
  assert.deepEqual(
    noRewardVisible.map((item) => item.uid).sort(),
    ["nb:Dreg Wormface@7660", "nb:Giant Skeleton Torso@4960", "nb:Storm King@7910"]
  );
  assert.ok(noRewardVisible.every((item) => item.roleHidden));
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

test("名字四级回退：nameZh → nameZhFallback → displayFallbackZh → nameEn", () => {
  // 与 macOS 端 BossCard.displayName 同一套顺序（两端唯一正式版本）。
  // 副标题恒为英文名，主标题已经是英文名时不重复。

  // 1. 有游戏内简中名：主标题中文、副标题英文
  const zhNamed = data.nightBosses.find((boss) => boss.nameZh && boss.nameSource === "npcname");
  const zhInfo = B.displayName(zhNamed);
  assert.equal(zhInfo.primary, zhNamed.nameZh);
  assert.equal(zhInfo.secondary, zhNamed.nameEn);
  assert.equal(zhInfo.usesFallback, false);
  assert.equal(zhInfo.usesPlaceholder, false);
  assert.deepEqual(B.nameBadges(zhInfo, zhNamed), [], "游戏文本名不挂任何名称徽标");

  // 2. nameZh 为空但有 nameZhFallback：参考译名当主标题 + 「参考译名」徽标，英文名当副标题
  const hippo = data.nightBosses.find((boss) => boss.id === "Large Golden Hippopotamus@5010");
  assert.equal(hippo.nameZh, "");
  assert.equal(hippo.nameZhFallback, "大型黄金河马");
  const hippoInfo = B.displayName(hippo);
  assert.equal(hippoInfo.primary, "大型黄金河马");
  assert.equal(hippoInfo.secondary, "Large Golden Hippopotamus");
  assert.equal(hippoInfo.usesFallback, true);
  assert.deepEqual(B.nameBadges(hippoInfo, hippo), [
    { text: "仅英文名", kind: "gray" },
    { text: "参考译名 · 非本作游戏文本", kind: "gray" },
  ]);

  // 3. 占位名 displayFallbackZh：这是本轮修掉的回归——数据集第二版把「未知敌人 cXXXX」
  //    从 nameZh 挪进了新字段，页面没跟着读，卡头就变成了「Unknown Enemy (c7931)」。
  const placeholderCards = data.nightBosses.filter((boss) => boss.displayFallbackZh);
  assert.deepEqual(
    placeholderCards.map((boss) => boss.id).sort(),
    ["Unknown Enemy (c7931)@7931", "Unknown Enemy (c7932)@7932"],
    "只有 c7931 / c7932 两组带占位名"
  );
  const unknown = placeholderCards.find((boss) => boss.id === "Unknown Enemy (c7931)@7931");
  assert.equal(unknown.nameZh, "", "占位名不进 nameZh（它不是游戏文本）");
  assert.equal(unknown.displayFallbackZh, "未知敌人 c7931");
  const unknownInfo = B.displayName(unknown);
  assert.equal(unknownInfo.primary, "未知敌人 c7931");
  assert.equal(unknownInfo.secondary, "Unknown Enemy (c7931)");
  assert.equal(unknownInfo.usesPlaceholder, true);
  assert.equal(unknownInfo.usesFallback, false);
  assert.deepEqual(B.nameBadges(unknownInfo, unknown), [{ text: "无游戏内名称", kind: "gray" }]);

  // 4. 三级都空才显示英文名，且不再重复一行副标题
  const greyoll = data.nightBosses.find((boss) => boss.id === "Elder Dragon Greyoll@4504");
  assert.equal(greyoll.nameZh, "");
  assert.equal(greyoll.nameZhFallback, "");
  assert.equal(greyoll.displayFallbackZh, "");
  const greyollInfo = B.displayName(greyoll);
  assert.equal(greyollInfo.primary, "Elder Dragon Greyoll");
  assert.equal(greyollInfo.secondary, "");
  assert.equal(greyollInfo.unknown, false);

  // 5. 四级全空才自己拼 chrId（数据里不存在，构造一条守住这一支）
  const blank = B.displayName({ nameZh: "", nameEn: "", nameZhFallback: "", chrIds: [7931] });
  assert.equal(blank.primary, "未知敌人 c7931");
  assert.equal(blank.unknown, true);
  assert.equal(B.displayName({ chrIds: [] }).primary, "未知敌人");

  // 逐组核对：全 116 组的主标题都只能来自这四级之一
  for (const boss of data.nightBosses) {
    const info = B.displayName(boss);
    const expected = boss.nameZh || boss.nameZhFallback || boss.displayFallbackZh || boss.nameEn;
    assert.equal(info.primary, expected, boss.id);
    assert.equal(info.secondary, boss.nameEn === expected ? "" : boss.nameEn, boss.id);
  }
  const fallbackNamed = data.nightBosses.filter((boss) => !boss.nameZh && boss.nameZhFallback);
  assert.equal(fallbackNamed.length, 14, "14 组走参考译名那一级");
  const englishTitled = data.nightBosses.filter(
    (boss) => !boss.nameZh && !boss.nameZhFallback && !boss.displayFallbackZh
  );
  assert.equal(englishTitled.length, 5, "5 组只剩英文名");
});

test("名称徽标：两层判定（名字缺不缺 / 身份谁认的）+ 近似匹配 + 参考译名", () => {
  assert.equal(B.NAME_SOURCE_BADGES["english-only"], "仅英文名");
  assert.equal(B.NAME_SOURCE_BADGES["chrid-fallback"], "无游戏内名称");
  assert.equal(B.NAME_SOURCE_BADGES["manual"], "名称手工补录");
  assert.equal(B.NAME_SOURCE_BADGES["community"], "社区资料");
  assert.equal(B.NAME_SOURCE_BADGES["community-npcname"], "社区资料");

  // nameSource = community 且 nameZh 为空：两件事都要说清楚。
  // 上一版只挂了「社区资料」，把用户最关心的「本作游戏文本里没有它的简中名」
  // 从页面上抹掉了，与 macOS 端 BossCard.nameBadges 的两层判定对不上。
  const community = data.nightBosses.find((boss) => boss.id === "Storm King@7910");
  assert.equal(community.nameSource, "community");
  assert.equal(community.nameZh, "");
  assert.deepEqual(B.nameBadges(B.displayName(community), community), [
    { text: "无游戏内名称", kind: "gray" },
    { text: "社区资料", kind: "gray" },
  ]);
  for (const id of ["Elder Dragon Greyoll@4504", "Centipede Grub@7711"]) {
    const boss = data.nightBosses.find((item) => item.id === id);
    assert.deepEqual(
      B.nameBadges(B.displayName(boss), boss).map((badge) => badge.text),
      ["无游戏内名称", "社区资料"],
      id
    );
  }

  // community-npcname 且拿到了游戏文本依据：只说名字，不再挂「社区资料」，
  // 否则会和展开区同时显示的「游戏文本依据」自相矛盾（macOS 的同一条守卫）。
  const troll = data.nightBosses.find((boss) => boss.id === "Stonedigger Troll@4603");
  assert.equal(troll.nameZh, "挖石山妖");
  assert.ok(troll.nameEvidence && troll.nameEvidence.id);
  assert.deepEqual(B.nameBadges(B.displayName(troll), troll), []);

  // nameApprox（非逐字命中）另挂「近似匹配」，依据写在 nameNote / nameEvidence 里
  const approx = data.nightBosses.filter((boss) => boss.nameApprox);
  assert.equal(approx.length, 7);
  const dragon = data.nightBosses.find((boss) => boss.id === "Flying Dragon@4500");
  assert.equal(dragon.nameApprox, true);
  assert.deepEqual(B.nameBadges(B.displayName(dragon), dragon), [{ text: "近似匹配", kind: "gray" }]);
  assert.ok(dragon.nameEvidence && dragon.nameEvidence.id, "近似匹配的行要能给出游戏文本依据");

  // nameInferred 仍走旧文案（前三支都不命中时才轮到它）
  const inferred = { nameZh: "某某", nameEn: "Whoever", nameSource: "npcname", nameInferred: true };
  assert.deepEqual(
    B.nameBadges(B.displayName(inferred), inferred),
    [{ text: "名称按 ID 推断", kind: "gray" }]
  );
  // nameZh 为空优先于 nameInferred：墓地幽魂两者都成立，写的是「仅英文名」
  const shade = data.nightBosses.find((boss) => boss.id === "Cemetery Shade@3664");
  assert.equal(shade.nameSource, "english-only");
  assert.equal(shade.nameInferred, true);
  assert.deepEqual(
    B.nameBadges(B.displayName(shade), shade).map((badge) => badge.text),
    ["仅英文名", "参考译名 · 非本作游戏文本"]
  );

  // 凡是用参考译名当主标题的卡片都必须挂「参考译名 · 非本作游戏文本」
  const items = B.buildItems(data, Core.foldForSearch);
  for (const boss of data.nightBosses) {
    const info = B.displayName(boss);
    const texts = B.nameBadges(info, boss).map((badge) => badge.text);
    assert.equal(
      texts.includes("参考译名 · 非本作游戏文本"), info.usesFallback,
      `${boss.id}：参考译名徽标应与主标题来源一致`
    );
  }

  // 卡片上的徽标就是这一组
  const hippoCard = items.find((item) => item.uid === "nb:Large Golden Hippopotamus@5010");
  assert.deepEqual(hippoCard.nameBadges.map((badge) => badge.text), ["仅英文名", "参考译名 · 非本作游戏文本"]);
  assert.equal(hippoCard.name, "大型黄金河马");
  assert.equal(hippoCard.nameEn, "Large Golden Hippopotamus");
  assert.ok(hippoCard.nameNote.length > 0, "让出 nameZh 的原因要能显示在展开区");
});

test("搜索索引收进 nameZhFallback：搜「河马」仍能搜到让出中文名的那一组", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  // v4：大型黄金河马只在据点首领出场（地下堡垒），不再在守夜 / 野外分组里。
  const hits = B.filterItems(items, "stronghold", "河马", Core.foldForSearch);
  assert.ok(
    hits.some((item) => item.uid === "nb:Large Golden Hippopotamus@5010"),
    "nameZh 被让出后，旧译名必须仍然可搜"
  );
  // 其余 13 组参考译名同样可搜（在各自的第一个分组里搜）
  const withFallback = data.nightBosses.filter((boss) => boss.nameZhFallback);
  assert.equal(withFallback.length, 14);
  const byUid = new Map(items.map((item) => [item.uid, item]));
  for (const boss of withFallback) {
    const group = byUid.get("nb:" + boss.id).groups[0];
    const found = B.filterItems(items, group, boss.nameZhFallback, Core.foldForSearch, true);
    assert.ok(found.some((item) => item.uid === "nb:" + boss.id), `搜不到参考译名：${boss.nameZhFallback}`);
  }
});

test("buildItems：夜王与首领组各一张卡片，主键用 id 而不是 nameEn", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  assert.equal(items.length, data.nightlords.length + data.nightBosses.length);

  const uids = new Set(items.map((item) => item.uid));
  assert.equal(uids.size, items.length, "uid 必须唯一");

  // 主分组 = groups[0]；夜王卡的主分组恒为「夜王」，首领组不会落到「夜王」。
  for (const item of items) {
    assert.ok(item.groups.length > 0, `${item.uid} 至少属于一个分组`);
    assert.equal(item.group, item.groups[0]);
    assert.equal(item.kind === "nightlord", item.group === "nightlords", item.uid);
  }
  assert.equal(items.filter((item) => item.group === "nightlords").length, data.nightlords.length);
  assert.equal(items.filter((item) => item.kind === "boss").length, data.nightBosses.length, "每个 Boss 恰好一张卡片");

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
  // 两套口径的名字与 macOS 端 BossCard 的两个同名属性一一对应（上一版**正好反着**）：
  //   deepCoverage        数 depthStats ——「深度模式下这张卡的数值变不变」；
  //   deepOfNightCoverage 数 deepOfNight ——「有没有额外那组深夜专属常驻修正」。
  const items = B.buildItems(data, Core.foldForSearch);
  const byUid = new Map(items.map((item) => [item.uid, item]));

  // menuId 12 = 格诺斯塔·永夜之王：6 条 fights 里 3 条有 deepOfNight。
  const gnoster = byUid.get("nl:12");
  assert.ok(gnoster);
  assert.equal(B.deepOfNightCoverage(gnoster), "some", "整张卡应判为「部分行有深夜专属修正」");

  const allDeep = items.find((item) => item.entries.length && item.entries.every((e) => e.deepOfNight));
  assert.equal(B.deepOfNightCoverage(allDeep), "all");

  const noDeep = items.find((item) => item.entries.length && item.entries.every((e) => !e.deepOfNight));
  assert.equal(B.deepOfNightCoverage(noDeep), "none");
  assert.equal(B.deepOfNightCoverage({ entries: [] }), "none");

  // 代表行没有深夜值、卡里其余行却有的卡片，一张都不能漏判成 none。
  // 与 macOS 端 BossDataChecks 的同名断言对着同一组卡片：v4 按 roles 取代表行后，各卡主分组
  // 的代表行都带深夜专属修正了（咒剑士 50400120 / 死骑士 50701010 / 救世旗手 76200210），
  // 但「据点首领」分组下的神兽战士 / 咒剑士 / 死骑士仍是代表行没有、守夜行有。
  const misjudged = items.filter((item) => B.deepOfNightCoverage(item) !== "none" &&
    B.visibleGroups(item).some((group) => {
      const main = B.representativeEntry(item.entries, group);
      return !(main && main.deepOfNight);
    })).map((item) => item.uid);
  assert.deepEqual(
    misjudged.sort(),
    ["nb:Curseblade@5040", "nb:Death Knight@5070", "nb:Divine Beast Warrior@5250"],
    "这 3 张卡靠扫描全部行才判得对"
  );
  for (const uid of misjudged) {
    assert.equal(Boolean(B.representativeEntry(byUid.get(uid).entries, "stronghold").deepOfNight), false, `${uid} 在据点首领下判错`);
  }
  for (const [uid, npcId] of [["nb:Curseblade@5040", 50400120], ["nb:Death Knight@5070", 50701010], ["nl:18", 76200210]]) {
    const item = byUid.get(uid);
    const main = B.representativeEntry(item.entries, item.group);
    assert.equal(main.npcId, npcId, uid);
    assert.ok(main.deepOfNight, `${uid} 的代表行自己带深夜修正`);
  }
  assert.equal(
    items.filter((item) => B.deepOfNightCoverage(item) !== "none").length, 22,
    "带深夜专属数值的卡片共 22 张（与 macOS 自检同一个数）"
  );
  assert.equal(items.filter((item) => B.deepOfNightCoverage(item) === "all").length, 4);

  // 卡头徽标文案（macOS 端 BossDeepCoverage.badgeText / exclusiveBadgeText）
  assert.equal(B.deepCoverageBadge("all"), "深夜数值");
  assert.equal(B.deepCoverageBadge("some"), "部分行有深夜数值");
  assert.equal(B.deepCoverageBadge("none"), "");
  assert.equal(B.deepOfNightCoverageBadge("all"), "深夜专属修正");
  assert.equal(B.deepOfNightCoverageBadge("some"), "部分行有深夜专属修正");
  assert.equal(B.deepOfNightCoverageBadge("none"), "");
});

test("深夜数值并非夜王独有：守夜首领 / 据点首领里也有带 deepOfNight 的条目", () => {
  // 审查意见称「30 条深夜行全部属于 nightlords」，实际 nightBosses 里有 14 条 / 12 张卡。
  const bossDeepRows = data.nightBosses.flatMap((boss) => boss.variants).filter((v) => v.deepOfNight);
  assert.ok(bossDeepRows.length > 0, "nightBosses 确实存在深夜行，徽标不能只画给夜王");

  const items = B.buildItems(data, Core.foldForSearch);
  const deepBossCards = items.filter((item) => item.kind === "boss" && B.deepOfNightCoverage(item) !== "none");
  assert.equal(deepBossCards.length, 12);
  assert.ok(deepBossCards.some((item) => item.groups.includes("night")));
  assert.ok(deepBossCards.some((item) => item.groups.includes("stronghold")));
});

test("分组不再看 tiers：tier / tiers 只是缩放档位，与出场场合对不上", () => {
  // bossGroups 的名字沿用，口径已换成 roles：tiers 写什么都不影响分组。
  assert.deepEqual(B.bossGroups({ tier: "night", tiers: ["field", "night"], roles: ["stronghold"] }), ["stronghold"]);
  assert.deepEqual(B.bossGroups({ tier: "field", tiers: ["field"], roles: ["night", "tower"] }), ["night", "other"]);
  // roles 缺失时不退回 tier 去猜（那正是要修的错），归「其它场合」、卡上写「数据未内置」。
  assert.deepEqual(B.bossGroups({ tier: "night" }), ["other"]);

  // 数据侧：notes.roleAudit 统计的 tier 与实际场合对不上的组，页面必须按 roles 分。
  const items = B.buildItems(data, Core.foldForSearch);
  const byUid = new Map(items.map((item) => [item.uid, item]));
  // tier = night 却从不当守夜首领：丘陵飞龙只是场景头目、腐败化身只是据点首领、
  // 卡利亚禁卫骑士只是场景头目（另各有未放置行，开关打开时也在「未放置」）。
  const flying = byUid.get("nb:Flying Dragon@4500");
  assert.equal(data.nightBosses.find((boss) => boss.id === "Flying Dragon@4500").tier, "night");
  assert.deepEqual(B.visibleGroups(flying), ["field"]);
  assert.deepEqual(B.visibleGroups(byUid.get("nb:Putrid Avatar@4811")), ["stronghold"]);
  const carian = byUid.get("nb:Royal Carian Knight@3252");
  assert.deepEqual(carian.tiers, ["night"]);
  assert.deepEqual(carian.groups, ["field", "unplaced"]);
  // tier = field 却确实当守夜首领：熔炉骑士进「守夜首领」、不进「场景头目」。
  const crucible = byUid.get("nb:Crucible Knight@2500");
  assert.equal(data.nightBosses.find((boss) => boss.id === "Crucible Knight@2500").tier, "field");
  assert.deepEqual(B.visibleGroups(crucible), ["night", "stronghold", "evergaol", "other"]);
  assert.equal(crucible.groups.includes("field"), false);
  // 大型黄金河马：v3 的 tiers = field + night，实际只出现在地下堡垒（据点首领），另有未放置行。
  const large = data.nightBosses.find((boss) => boss.id === "Large Golden Hippopotamus@5010");
  assert.deepEqual(large.tiers, ["field", "night"]);
  assert.deepEqual(byUid.get("nb:Large Golden Hippopotamus@5010").groups, ["stronghold", "unplaced"]);
  // schemaVersion 3 起它的 nameZh 为空（游戏文本只有 c5011 那条「黄金河马」，
  // 同一个中文名不允许同时挂在两组首领上，见 notes.nameCollisions），按英文名也能搜到。
  const hippo = B.filterItems(items, "stronghold", "Golden Hippopotamus", Core.foldForSearch);
  assert.ok(hippo.some((item) => item.uid === "nb:Large Golden Hippopotamus@5010"));
  assert.equal(large.nameZh, "");
  assert.equal(large.nameSource, "english-only");
  assert.equal(large.nameZhFallback, "大型黄金河马", "旧手工译名仍在 nameZhFallback 里可兜底");
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
  // schemaVersion 3 起 nameSource = manual 不再产出（手工译名移到 nameZhFallback），
  // 拿一条有游戏内简中名的条目来验证「中文名仍可搜」。
  const zhNamed = data.nightBosses.find((boss) => boss.nameZh && boss.nameSource !== "chrid-fallback");
  assert.ok(zhNamed, "数据集里应存在带游戏内简中名的条目");
  assert.ok(B.filterItems(items, "night", zhNamed.nameZh, Core.foldForSearch).length +
    B.filterItems(items, "field", zhNamed.nameZh, Core.foldForSearch).length > 0, "中文名仍可搜");
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
    // v4：「夜王」分组先只留 nightlord 场合的行，再在主战行里取血量最高。
    const mains = lord.fights.filter((f) => f.isMain && f.roles.includes("nightlord"));
    const rep = B.representativeEntry(lord.fights, "nightlords");
    assert.equal(rep.isMain, true);
    assert.equal(rep.hp, Math.max(...mains.map((f) => f.hp)), `${lord.nameZh} 应取血量最高的主战行`);
  }
  // 救世旗手：isMain 的「哈尔莫妮亚 · 蠕虫」46410000（6797）只有未放置场合，不再抢代表位。
  const bearers = data.nightlords.find((lord) => lord.menuId === 18);
  assert.deepEqual(bearers.fights.find((f) => f.npcId === 46410000).roles, ["unplaced"]);
  assert.equal(B.representativeEntry(bearers.fights, "nightlords").npcId, 76200210);

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

test("首领卡片的代表行随分组切换（按 roles 过滤），不再恒取 variants[0]", () => {
  const apostle = data.nightBosses.find((boss) => boss.id === "Godskin Apostle@3560");
  assert.equal(apostle.variants[0].threat, "night", "变体按守夜优先排序，rows[0] 是守夜档位行");

  // 35600900「基准（行 35600900）」血量最高（7347）却 noReward = true 且未放置，是模板行。
  assert.equal(apostle.variants.find((v) => v.npcId === 35600900).noReward, true);
  // 上一版按 threat 取的「守夜代表行」35600110 其实是「最古老的牢狱」——封印监牢行，
  // 只是挂着守夜档位 7754。v4 按 roles 取：守夜首领 → 守夜双人组，封印监牢 → 它。
  const night = B.representativeEntry(apostle.variants, "night");
  const evergaol = B.representativeEntry(apostle.variants, "evergaol");
  const stronghold = B.representativeEntry(apostle.variants, "stronghold");
  assert.equal(night.npcId, 35600010);
  assert.deepEqual(night.roles, ["night", "tower"]);
  assert.equal(evergaol.npcId, 35600110);
  assert.equal(evergaol.threat, "night", "封印监牢行挂的是守夜档位——threat 不能拿来分组");
  assert.equal(stronghold.npcId, 35600050);

  // 全量：每张卡在它出现的每个分组下（含两个默认隐藏的分组），代表行的场合都落在该分组里。
  const items = B.buildItems(data, Core.foldForSearch);
  for (const item of items) {
    for (const group of item.groups) {
      const rep = B.representativeEntry(item.entries, group);
      assert.ok(B.rolesInGroup(rep.roles, group).length > 0, `${item.uid} / ${group} → ${rep.npcId}`);
    }
  }

  // 只有一个场合、且没有无奖励 / 演出行的组不受影响：按分组取出来的仍是血量最高的那行。
  const single = items.find((item) => item.kind === "boss" && item.roles.length === 1 &&
    item.entries.length > 1 && item.entries.every((v) => !v.noReward && !B.isStagingRow(v) && !v.isMain));
  assert.ok(single, "数据里应存在单一场合的多行组");
  const rep = B.representativeEntry(single.entries, single.group);
  assert.equal(rep.hp, Math.max(...single.entries.map((v) => v.hp)));

  // 候选行：夜王收敛到 isMain，首领组收敛到该分组的场合，最后都排掉无奖励行。
  assert.equal(B.candidateEntries(apostle.variants, "stronghold").length, 2, "据点首领两行（群体首领 / 精英）");
  assert.equal(B.candidateEntries(apostle.variants, "evergaol").length, 2, "封印监牢两行（最古老的牢狱 / 封印监牢）");
  // 分组里没有一行对得上时整池放行（再排掉 2 条无奖励行）
  assert.equal(B.candidateEntries(apostle.variants, "nightlords").length, apostle.variants.length - 2);
  assert.equal(B.candidateEntries(data.nightlords.find((l) => l.menuId === 13).fights, "nightlords").length, 2);
});

test("代表行第三步：排掉登场演出 / 血条实体 / 教程行（isStagingRow）", () => {
  // 演出行**不一定** noReward —— 这正是 noReward 那一层拦不住它们的原因：
  // 「鲜血君王 · 登场演出」35500020 与巨鸦群的「血条实体」45601020 都是 noReward = false。
  // 判据与 macOS 端 BossFight.isStagingRow 同一张关键词表，扫的是页面上写着的那个标签。
  assert.deepEqual(B.STAGING_LABEL_KEYWORDS, ["登场演出", "血条实体", "教程"]);

  const staging = allEntries.filter((entry) => B.isStagingRow(entry));
  assert.deepEqual(
    staging.map((entry) => entry.npcId).sort((a, b) => a - b),
    [21300520, 35500020, 36000010, 36001010, 42600110, 44600015, 45050020, 45601020, 46300030, 71000115],
    "数据里共 10 条演出行"
  );
  assert.equal(
    staging.filter((entry) => !entry.noReward).length, 7,
    "其中 7 条照样掉奖励，noReward 那一层拦不住"
  );

  // 巨鸦群就是少了这一步会选错的：「血条实体」45601020 与实战行 45601010 同在场景头目场合，
  // 上一版 Windows 取的是血量更高的演出行。
  const crow = data.nightBosses.find((boss) => boss.id === "Giant Crow@4560");
  const crowStaging = crow.variants.find((v) => v.npcId === 45601020);
  assert.equal(crowStaging.labelZh, "血条实体");
  assert.equal(crowStaging.noReward, false, "血条实体也掉奖励，只能靠标签认");
  assert.equal(crowStaging.hp, 2117);
  assert.deepEqual(crowStaging.roles, ["field"]);
  assert.equal(B.representativeEntry(crow.variants, "field").npcId, 45601010);
  assert.equal(B.representativeEntry(crow.variants, "field").hp, 1779, "宁可取血量更低的实战行");

  // 鲜血贵族：「鲜血君王 · 登场演出」35500020 是它唯一的守夜前哨行，在「其它场合」下
  // 整池都是演出行，按规则不排除；据点首领分组则取沼泽群体首领。
  const sanguine = data.nightBosses.find((boss) => boss.id === "Sanguine Noble@3550");
  const sanguineStaging = sanguine.variants.find((v) => v.npcId === 35500020);
  assert.equal(sanguineStaging.labelZh, "鲜血君王 · 登场演出");
  assert.deepEqual(sanguineStaging.roles, ["prelude"]);
  assert.equal(B.representativeEntry(sanguine.variants, "other").npcId, 35500020);
  assert.equal(B.representativeEntry(sanguine.variants, "stronghold").npcId, 35500040);

  // 演出行只在评选代表行时被排除，展开区仍然逐行列出来
  const items = B.buildItems(data, Core.foldForSearch);
  const crowCard = items.find((item) => item.uid === "nb:Giant Crow@4560");
  assert.ok(crowCard.entries.some((entry) => entry.npcId === 45601020), "展开区不隐藏演出行");

  // 整池都是演出行时不排除（否则候选池会空）
  const allStaging = [
    { hp: 100, npcId: 2, labelZh: "教程" },
    { hp: 300, npcId: 1, labelZh: "血条实体" },
  ];
  assert.equal(B.candidateEntries(allStaging, null).length, 2);
  assert.equal(B.representativeEntry(allStaging, null).npcId, 1);

  // 全量核对：代表行只有在整池都是演出行时才允许是演出行（macOS 的同一条断言）
  for (const item of items) {
    for (const group of item.groups) {
      const pool = B.candidateEntries(item.entries, group);
      const primary = B.representativeEntry(item.entries, group);
      assert.ok(
        !B.isStagingRow(primary) || pool.every((entry) => B.isStagingRow(entry)),
        `${item.uid} / ${group} 的代表行不该是演出行`
      );
    }
  }
});

test("代表行对照表：卡片 + 分组 → npcId，与 macOS 的 representativeCases 同一张", () => {
  // 同一张表也写在 macos/Sources/RelicCoreChecks/BossDataChecks.swift（12e 节）。
  // ParityCase 那张表按 npcId 直接取行，断言的是换算公式，钉不住「折叠态会选中哪一行」；
  // 任一端改了过滤顺序，这里必须立刻红。
  const items = B.buildItems(data, Core.foldForSearch);
  const byUid = new Map(items.map((item) => [item.uid, item]));
  // bossesSchemaVersion 4 起第一步按 roles 过滤（分组 = 夜王 / 守夜首领 / 据点首领 / 场景头目 /
  // 封印监牢 / 其它场合 / 随从/召唤物 / 未放置），整张表按新口径重排，逐条照抄 macOS 那张
  //（bosses_parity.test.mjs 另从 Swift 源码读 representativeCases 再跑一遍）。
  const cases = [
    // 夜王：整池都 noReward，先排 noReward 会退化成 75000000 参数标签行
    ["格拉狄乌斯 · 夜王", "nl:0", "nightlords", 75000020],
    ["玛利斯 · 夜王", "nl:3", "nightlords", 75400020],
    ["卡莉果 · 夜王", "nl:6", "nightlords", 49000010],
    // isMain 那一层：75802000 与 75802010 同血量同场合，只有后者是主战行
    ["布德奇冥 · 夜王", "nl:7", "nightlords", 75802010],
    // roles 那一层（夜王分组同样过滤）：isMain 的「哈尔莫妮亚 · 蠕虫」46410000 是未放置行
    ["救世旗手 · 夜王", "nl:18", "nightlords", 76200210],
    // 铃珠猎人：野外版与守夜版是不同行，四个可见分组 + 未放置各给各的
    ["铃珠猎人 · 守夜首领", "nb:Bell Bearing Hunter@3100", "night", 31000020],
    ["铃珠猎人 · 场景头目", "nb:Bell Bearing Hunter@3100", "field", 31000010],
    ["铃珠猎人 · 据点首领", "nb:Bell Bearing Hunter@3100", "stronghold", 31000040],
    ["铃珠猎人 · 其它场合（高塔）", "nb:Bell Bearing Hunter@3100", "other", 31000020],
    ["铃珠猎人 · 未放置", "nb:Bell Bearing Hunter@3100", "unplaced", 31000000],
    // 大型黄金河马：旧「守夜代表行」其实在地下堡垒；旧「野外代表行」未放置、整池 noReward 不排
    ["大型黄金河马 · 据点首领", "nb:Large Golden Hippopotamus@5010", "stronghold", 50100010],
    ["大型黄金河马 · 未放置", "nb:Large Golden Hippopotamus@5010", "unplaced", 50100000],
    // 神皮使徒：守夜首领是「守夜双人组」（旧版按 threat 取了封印监牢的 35600110）；
    // 未放置分组里 noReward 那一层把 Paramdex 模板行 35600900 让给 35600000
    ["神皮使徒 · 守夜首领", "nb:Godskin Apostle@3560", "night", 35600010],
    ["神皮使徒 · 据点首领", "nb:Godskin Apostle@3560", "stronghold", 35600050],
    ["神皮使徒 · 封印监牢", "nb:Godskin Apostle@3560", "evergaol", 35600110],
    ["神皮使徒 · 未放置", "nb:Godskin Apostle@3560", "unplaced", 35600000],
    // isStagingRow 那一层：「血条实体」45601020 血量更高（2117）且 noReward = false，只能靠标签认出来
    ["巨鸦群 · 场景头目", "nb:Giant Crow@4560", "field", 45601010],
    // 演出行 + noReward 两层：「教程」21300520（其他地图，9920 血）两层都会排掉
    ["恶兆妖鬼 · 其它场合", "nb:Morgott@2130", "other", 21300510],
    ["恶兆妖鬼 · 守夜首领", "nb:Morgott@2130", "night", 21300510],
    // 整池都是演出行时不排：鲜血贵族在「其它场合」下只有守夜前哨那一行「登场演出」
    ["鲜血贵族 · 其它场合（守夜前哨）", "nb:Sanguine Noble@3550", "other", 35500020],
    ["鲜血贵族 · 据点首领", "nb:Sanguine Noble@3550", "stronghold", 35500040],
    // 火焰战车：旧版的「营地 · 血条实体」44600015 未放置；未放置分组里靠演出行那层排掉它
    ["火焰战车 · 据点首领", "nb:Flame Chariot@4460", "stronghold", 44600010],
    ["火焰战车 · 场景头目", "nb:Flame Chariot@4460", "field", 44600000],
    ["火焰战车 · 未放置", "nb:Flame Chariot@4460", "unplaced", 44600000],
    // 死亡仪式鸟：7 个场合；场景头目 / 据点首领共用一条多场合行
    ["死亡仪式鸟 · 场景头目", "nb:Death Rite Bird@4980", "field", 49801040],
    ["死亡仪式鸟 · 据点首领", "nb:Death Rite Bird@4980", "stronghold", 49801040],
    ["死亡仪式鸟 · 封印监牢", "nb:Death Rite Bird@4980", "evergaol", 49801030],
    ["死亡仪式鸟 · 守夜首领", "nb:Death Rite Bird@4980", "night", 49801010],
    // noReward + 同血量两层：排掉无奖励的 35500015 后 35500030 / 35500040 同为 920 血，按 npcId 取小
    ["鲜血贵族 · 未放置", "nb:Sanguine Noble@3550", "unplaced", 35500030],
  ];
  for (const [title, uid, group, npcId] of cases) {
    const item = byUid.get(uid);
    assert.ok(item, `对照表找不到卡片 ${uid}（${title}）`);
    assert.ok(item.groups.includes(group), `${title}：卡片确实出现在这个分组里`);
    assert.equal(B.representativeEntry(item.entries, group).npcId, npcId, title);
  }
  assert.equal(cases.length, 29, "与 macOS 的 representativeCases 同样 29 条");
});

test("代表行先排掉 noReward，但必须排在 isMain 之后（两端同一顺序）", () => {
  // 约定的顺序：分组过滤（roles；v3 为 threat）→ isMain 收敛 → 排除演出行（isStagingRow）→
  // 排除 noReward（池内全是 noReward 就不排除）→ 血量最高（同血量取 npcId 小者），
  // 每一步没有候选就原样放行。
  //
  // 为什么 noReward 必须在 isMain 之后：夜王的主战行几乎都是 noReward = true
  //（奖励挂在远征结算上，不在 NpcParam 的 getSoul / 掉落表里）。提到 isMain 之前
  // 会把整组主战行踢掉，下面三条断言就是守着这件事。
  const gladius = data.nightlords.find((lord) => lord.menuId === 0);
  const gladiusMain = B.representativeEntry(gladius.fights, "nightlords");
  assert.equal(gladiusMain.npcId, 75000020, "格拉狄乌斯代表行不能被 noReward 挤成 75000000");
  assert.equal(gladiusMain.noReward, true, "它自己就是 noReward 行，靠「整组都 noReward 则不排除」留住");
  assert.equal(gladiusMain.hp, 11328);

  const maris = data.nightlords.find((lord) => lord.menuId === 3);
  assert.equal(B.representativeEntry(maris.fights, "nightlords").hp, 12687, "玛利斯不能掉到一阶段的 3045");

  // 反过来，模板 / 血条实体 / 教程行确实要被排掉。
  const morgott = data.nightBosses.find((boss) => boss.id === "Morgott@2130");
  const tutorial = morgott.variants.find((v) => v.npcId === 21300520);
  assert.equal(tutorial.hp, 9920);
  assert.equal(tutorial.noReward, true, "「教程」行不掉奖励");
  assert.deepEqual(tutorial.roles, ["other"], "教程地图 m35_90 是「其他地图」");
  assert.equal(B.representativeEntry(morgott.variants, "other").npcId, 21300510, "代表行要让给真正的实战行");
  assert.equal(B.representativeEntry(morgott.variants, "night").npcId, 21300510);

  // v4 按场合过滤后，noReward 真正起作用的一处：神皮使徒在「未放置」分组下，
  // Paramdex 模板行 35600900（7,347）不掉奖励，让给 35600000。
  const apostle = data.nightBosses.find((boss) => boss.id === "Godskin Apostle@3560");
  const template = apostle.variants.find((v) => v.npcId === 35600900);
  assert.equal(template.noReward, true);
  assert.deepEqual(template.roles, ["unplaced"]);
  assert.equal(B.representativeEntry(apostle.variants, "unplaced").npcId, 35600000);

  const chariot = data.nightBosses.find((boss) => boss.id === "Flame Chariot@4460");
  const chariotBar = chariot.variants.find((v) => v.npcId === 44600015);
  assert.equal(chariotBar.noReward, true, "「血条实体」行不掉奖励");
  assert.deepEqual(chariotBar.roles, ["unplaced"], "而且根本没放进地图");
  assert.equal(B.representativeEntry(chariot.variants, "stronghold").npcId, 44600010);
  assert.equal(B.representativeEntry(chariot.variants, "field").npcId, 44600000);

  // 整组都 noReward 时不排除（否则候选池会空）。
  const allNoReward = [
    { hp: 100, npcId: 2, noReward: true },
    { hp: 300, npcId: 1, noReward: true },
  ];
  assert.equal(B.representativeEntry(allNoReward, null).npcId, 1);
  assert.equal(B.candidateEntries(allNoReward, null).length, 2);

  // 18 位夜王的代表行没有一条因为这一步而改变（macOS 端同样的断言）。
  for (const lord of data.nightlords) {
    const rep = B.representativeEntry(lord.fights, "nightlords");
    const mains = lord.fights.filter((f) => f.isMain);
    assert.ok(mains.some((f) => f.npcId === rep.npcId), `${lord.nameZh} 的代表行仍必须是主战行`);
  }
});

test("搜索：纯数字按行号前缀匹配，文本串收场合名、不收内部枚举值", () => {
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
  const withNameIdGroup = items.find((item) => item.uid === "nb:" + withNameId.id).groups[0];
  assert.ok(
    B.filterItems(items, withNameIdGroup, String(withNameId.npcNameId), fold)
      .some((item) => item.uid === "nb:" + withNameId.id),
    "npcNameId 也应能搜到"
  );
  // v4：场合名（roleNames 中英文）进搜索串——同一分组里按场合名搜，整组都命中。
  const fieldCount = B.filterItems(items, "field", "", fold).length;
  assert.equal(B.filterItems(items, "field", "场景头目", fold).length, fieldCount);
  // 「其它场合」这个分组名本身不是任何场合的名字，不进搜索串。
  assert.equal(B.filterItems(items, "other", "其它场合", fold).length, 0);
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

  // [标题, npcId, 人数, 深度, 变异档位, 血量, 有效韧性, 削韧槽语义, 削韧恢复, 异常发动伤害, 异常累积, 攻击力倍率]
  const cases = [
    ["格拉狄乌斯 · 远征首领 / 1 人", 75000020, 1, 0, null, 11328, 120, "value", 0.058, 0.5, 1, 3.36],
    ["格拉狄乌斯 · 远征首领 / 2 人", 75000020, 2, 0, null, 22656, 218.181818, "value", 0.0319, 0.375, 0.85, 3.36],
    ["格拉狄乌斯 · 远征首领 / 3 人", 75000020, 3, 0, null, 33984, 400, "value", 0.0174, 0.25, 0.7, 3.36],
    // 双端对照输入 ①：格拉狄乌斯 3 人深度 5
    ["格拉狄乌斯 · 远征首领 / 3 人 · 深度 5", 75000020, 3, 5, null, 73404, 476.190476, "value", 0.0174, 0.25, 0.7, 11.1216],
    ["格拉狄乌斯 · 远征首领 / 1 人 · 深度 1", 75000020, 1, 1, null, 14160, 136.363636, "value", 0.058, 0.5, 1, 4.2],
    ["玛利斯 · 永夜之王 · 二阶段 / 2 人", 75410000, 2, 0, null, 58906, 1090.909091, "value", 0, 0.375, 0.85, 3.864],
    ["史柴格斯 · 远征首领 / 3 人 · 深度 3", 76100010, 3, 3, null, 54423, 581.58132, "value", 0.0174, 0.25, 0.7, 6.4512],
    // 行标题按 v4 的场合改写（npcId 与期望值不变）：35600110 是「最古老的牢狱」封印监牢行
    ["神皮使徒 · 最古老的牢狱（封印监牢）/ 2 人", 35600110, 2, 0, null, 7687, 145.454545, "value", 0.1595, 0.41, 0.889, 3.3],
    ["神皮使徒 · 封印监牢 / 2 人", 35600020, 2, 0, null, 6535, 106.666667, "value", 0.2175, 0.82, 0.889, 2.97],
    // 双端对照输入 ②：神皮使徒封印监牢 2 人深度 3，以及同一行叠变异档位 113140
    ["神皮使徒 · 封印监牢 / 2 人 · 深度 3", 35600020, 2, 3, null, 9723, 124.031008, "value", 0.2175, 0.82, 0.889, 5.46777],
    ["神皮使徒 · 封印监牢 / 2 人 · 深度 3 · 变异 113140", 35600020, 2, 3, 113140, 11182, 124.031008, "value", 0.2175, 0.82, 0.889, 6.2879355],
    // 双端对照输入 ③：死亡仪式鸟 49800030（据点首领行）2 人深度 3 变异档位 113340
    ["死亡仪式鸟 · 49800030（据点首领）/ 2 人 · 深度 3", 49800030, 2, 3, null, 5017, 186.046512, "value", 0.2175, 0.98, 0.985, 2.7615],
    ["死亡仪式鸟 · 49800030（据点首领）/ 2 人 · 深度 3 · 变异 113340", 49800030, 2, 3, 113340, 5770, 186.046512, "value", 0.2175, 0.98, 0.985, 3.175725],
    ["大型黄金河马 · 地下堡垒首领（据点首领代表行）/ 3 人", 50100010, 3, 0, null, 17747, 266.666667, "value", 0.087, 0.315, 0.778, 3.672],
    ["大型黄金河马 · 基准（未放置）/ 3 人", 50100000, 3, 0, null, 5606, 160, "value", 0.145, 0.95, 0.97, 1.5],
    ["未知敌人 c7931（poise = 0）/ 2 人", 79310000, 2, 0, null, 6851, null, "zero", 0.1595, 0.46, 0.955, 1.75],
    ["鲜血君王的长枪 · 召唤物（poise = -1）/ 2 人", 48010010, 2, 0, null, 674, null, "none", 0.0319, 0.375, 0.85, 3.64],
    // 双端对照输入 ④：第二版核验里取整口径统一后 +1 的两条
    ["贪食魔龙（大口龙）/ 1 人", 77000000, 1, 0, null, 5399, 120, "value", 0.29, 0.5, 1, 1.75],
    ["神皮贵族 · 守夜双人组 / 1 人", 35700010, 1, 0, null, 5549, 80, "value", 0.058, 0.5, 1, 2.8],
  ];

  for (const [title, npcId, party, depth, mutationId, hp, poise, kind, recover, ailment, buildup, attack] of cases) {
    const entry = rows.get(npcId);
    assert.ok(entry, `对照表找不到 npcId ${npcId}（${title}）`);
    const stats = B.computeStats(entry, party, depth, mutationId ? data.mutations[String(mutationId)] : null);
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
    assert.ok(Math.abs(stats.attackRate - attack) < 1e-6, `${title}：攻击力倍率 ${stats.attackRate}`);
  }

  // 对照表里标着「代表行」的行必须就是折叠态会选中的那一行（v4 分组口径）。
  const hippo = data.nightBosses.find((boss) => boss.id === "Large Golden Hippopotamus@5010");
  assert.equal(B.representativeEntry(hippo.variants, "stronghold").npcId, 50100010);
  assert.equal(B.representativeEntry(data.nightlords.find((l) => l.menuId === 0).fights, "nightlords").npcId, 75000020);
  const apostle = data.nightBosses.find((boss) => boss.id === "Godskin Apostle@3560");
  assert.equal(B.representativeEntry(apostle.variants, "evergaol").npcId, 35600110);
  const bird = data.nightBosses.find((boss) => boss.id === "Death Rite Bird@4980");
  assert.ok(B.candidateEntries(bird.variants, "stronghold").some((v) => v.npcId === 49800030));

  // 双端对照输入 ⑤：隐藏开关前后八个分组的条数（macOS 的 toggleCounts 同一组数）
  const items = B.buildItems(data, Core.foldForSearch);
  assert.deepEqual(
    B.GROUP_ORDER.map((group) => [
      B.filterItems(items, group, "", Core.foldForSearch).length,
      B.filterItems(items, group, "", Core.foldForSearch, true).length,
    ]),
    [[18, 18], [40, 40], [51, 51], [35, 35], [10, 10], [45, 45], [0, 11], [0, 93]]
  );
});

test("收录统计与 macOS 的 inventorySummary 是同一组数字", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  const counts = B.inventoryCounts(items);

  assert.equal(data.nightlords.length, 18);
  // v4 按出场场合：「收录」说的是数据集收录了多少，各分组（含默认隐藏的两个）按打开开关计；
  // 单一场合的分组与 roleSummary 同数，其它场合 45 是七个合并场合的并集。
  assert.deepEqual(counts.groups, {
    nightlords: 18, night: 40, stronghold: 51, field: 35, evergaol: 10, other: 45, summon: 11, unplaced: 93,
  });
  assert.equal(counts.multi, 49, "49 组首领同时属于多个默认可见分组");
  // 数值行 394（schemaVersion 3 起不变）
  assert.equal(counts.rows, 394);
  assert.equal(
    B.inventoryText(counts),
    "夜王 18 · 守夜首领 40 · 据点首领 51 · 场景头目 35 · 封印监牢 10 · 其它场合 45 · " +
      "随从/召唤物 11 · 未放置 93（含 49 组同时属于多个分组） · 数值行 394"
  );
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
  assert.deepEqual(B.GROUP_TITLES, {
    nightlords: "夜王",
    night: "守夜首领",
    stronghold: "据点首领",
    field: "场景头目",
    evergaol: "封印监牢",
    other: "其它场合",
    summon: "随从/召唤物",
    unplaced: "未放置",
  });
  assert.deepEqual(
    B.TABS.map((tab) => tab.label),
    ["夜王", "守夜首领", "据点首领", "场景头目", "封印监牢", "其它场合", "随从/召唤物", "未放置"]
  );
  // 分组标题都取自 ROLE_TEXT（macOS 的 BossRoleText.groupXxx）
  assert.deepEqual(
    B.GROUP_ORDER.map((key) => B.GROUP_TITLES[key]),
    ["groupNightlord", "groupNight", "groupStronghold", "groupField", "groupEvergaol", "groupOther", "groupSummon", "groupUnplaced"]
      .map((key) => B.ROLE_TEXT[key])
  );
});

test("group = null 的 4 个档位写「其它档位」，展开态与底部档位表同名", () => {
  // macOS 端 BossScalingGroup.title(for:) 对 group = nil 返回「其它档位」；
  // Windows 端此前在展开态的「多人缩放」标题里什么都不写，两端对不上。
  const nullGroupIds = Object.keys(data.scalingTiers)
    .filter((key) => !data.scalingTiers[key].group)
    .map(Number)
    .sort((a, b) => a - b);
  assert.deepEqual(nullGroupIds, [98810, 98815, 98818, 98822]);

  assert.equal(B.tierGroupLabel(null), "其它档位");
  assert.equal(B.tierGroupLabel(undefined), "其它档位");
  assert.equal(B.tierGroupLabel(""), "其它档位");
  assert.equal(B.tierGroupLabel("Final Boss Threat"), "最终首领威胁档");
  // 表里没有的分组名照原样显示（macOS 的 `case .some(let name)` 同支）
  assert.equal(B.tierGroupLabel("Brand New Threat"), "Brand New Threat");

  // 整串说明与 macOS 端 BossRowText.scalingCaption(scalingID:groupTitle:) 逐字一致，
  // 包括 id 前面的「#」。上一轮两端各自把不同的字面量写死（这边「档位 98815」、
  // 那边「档位 #98815」），两份注释却都写着「逐字一致」。
  for (const id of nullGroupIds) {
    assert.equal(
      B.scalingCaption({ scalingId: id }, data.scalingTiers),
      `档位 #${id} · 其它档位`,
      `档位 ${id} 的展开态标题应写「其它档位」`
    );
  }
  // 与 macOS 的 scalingCaption 同样的两条边界（「没有 scalingId」那一支此前
  // Windows 给空串、macOS 写「无缩放档位」，也是一端有话一端空白）
  assert.equal(B.scalingCaption({ scalingId: null }, data.scalingTiers), "无缩放档位");
  assert.equal(B.scalingCaption({}, data.scalingTiers), "无缩放档位");
  assert.equal(B.scalingCaption({ scalingId: 4040404 }, data.scalingTiers), "档位 #4040404");
});

test("每条数值行的 scalingId 都能查到档位，且档位名非空", () => {
  for (const entry of allEntries) {
    if (entry.scalingId === null || entry.scalingId === undefined) continue;
    const caption = B.scalingCaption(entry, data.scalingTiers);
    assert.ok(caption.startsWith(`档位 #${entry.scalingId}`), `档位标题异常：${caption}`);
    assert.ok(caption.includes(" · "), `档位 ${entry.scalingId} 少了分组名：${caption}`);
  }
});

test("行内徽标 / 卡头计数文案与 macOS 逐字一致", () => {
  // macOS：Pill("标签为社区推测") / Pill("深夜数值") / Text("N 条数值行")
  const uncertain = allEntries.find((entry) => entry.labelUncertain);
  assert.ok(uncertain, "数据集里应存在 labelUncertain 的行");
  const badges = B.entryBadgeTexts(
    { kind: "boss" },
    uncertain,
    B.computeStats(uncertain, 1, false)
  );
  assert.ok(badges.includes("标签为社区推测"), `实际徽标：${badges.join(" / ")}`);
  assert.ok(!badges.includes("标签存疑"), "旧文案「标签存疑」不该再出现");

  // 行内深夜徽标：macOS 写「深夜数值」（depthStats 口径，不带深度数字），
  // 上一版 Windows 写的是「深夜 4」——两边注释都声称「逐字一致」，实际两套说法。
  const deepEntry = allEntries.find((entry) => entry.deepOfNight);
  const deepBadges = B.entryBadgeTexts({ kind: "nightlord" }, deepEntry, B.computeStats(deepEntry, 1, 4, null));
  assert.ok(deepBadges.includes("深夜数值"), `实际徽标：${deepBadges.join(" / ")}`);
  assert.ok(deepBadges.includes("深夜专属修正"), "带 deepOfNight 的行另挂一枚");
  assert.equal(deepBadges.some((text) => /深夜 \d/.test(text)), false, "徽标里不写深度数字");
  // 只有 depthStats、没有 deepOfNight 的行只挂前一枚
  const plainDepth = allEntries.find((entry) => entry.depthStats && !entry.deepOfNight);
  const plainBadges = B.entryBadgeTexts({ kind: "boss" }, plainDepth, B.computeStats(plainDepth, 1, 4, null));
  assert.ok(plainBadges.includes("深夜数值"));
  assert.equal(plainBadges.includes("深夜专属修正"), false);
  assert.equal(
    B.entryBadgeTexts({ kind: "nightlord" }, deepEntry, B.computeStats(deepEntry, 1, 0, null))
      .some((text) => text.startsWith("深夜")),
    false,
    "常规模式下不挂深夜徽标"
  );

  // 选了变异档位的行另挂一枚「变异个体」（游戏内正式叫法）。
  const mutable = allEntries.find((entry) => entry.mutationPool && entry.mutationPool.length);
  const mutation = data.mutations[String(mutable.mutationPool[0])];
  assert.ok(
    B.entryBadgeTexts({ kind: "boss" }, mutable, B.computeStats(mutable, 1, 0, mutation)).includes("变异个体")
  );
  assert.equal(
    B.entryBadgeTexts({ kind: "boss" }, mutable, B.computeStats(mutable, 1, 0, null)).includes("变异个体"),
    false
  );

  // v4：行级威胁档位「守夜 / 野外」不再当徽标（它只是缩放档位，挨着场合徽标会被读成
  // 出场位置），改在行标题下方写小字，与 macOS 的 BossFight.threatTierCaption 同一串。
  assert.ok(allEntries.some((entry) => entry.threat === "night"), "数据集里应存在 threat = night 的行");
  assert.deepEqual(B.THREAT_TIER_GROUPS, { night: "Night Boss Threat", field: "Field Boss Threat" });
  assert.equal(B.ROLE_TEXT.threatTierCaption(["night"]), "威胁档位 · 守夜首领威胁档");
  assert.equal(B.ROLE_TEXT.threatTierCaption(["field"]), "威胁档位 · 野外首领威胁档");
  // 顺序与 macOS 的 Pill 顺序一致：主战 → 标签为社区推测 → …
  assert.deepEqual(
    B.entryBadgeTexts({ kind: "boss" }, { threat: "night", isMain: true }, { isDeep: false }),
    ["主战"]
  );
  assert.deepEqual(
    B.entryBadgeTexts({ kind: "boss" }, { threat: "field", isMain: false, labelUncertain: true }, { isDeep: false }),
    ["标签为社区推测"]
  );

  assert.equal(B.rowCountText(5), "5 条数值行");
  assert.equal(B.rowCountText(1), "1 条数值行");
  // v4：默认收起的「未放置」「随从/召唤物」行另补一句（macOS 的 BossRoleText.rowCount）
  assert.equal(B.ROLE_TEXT.rowCount(5, 0), "5 条数值行");
  assert.equal(B.ROLE_TEXT.rowCount(4, 1), "4 条数值行（另 1 条已隐藏）");
});

test("「代表行承伤偏高」倍率统一两位小数", () => {
  // macOS：BossFormat.multiplier(item.rate, digits: 2)
  assert.equal(B.fmtMul(1.2346), "×1.235", "默认仍是三位（缩放档位表要用）");
  assert.equal(B.fmtMul(1.2345, 2), "×1.23");
  assert.equal(B.fmtMul(1.1, 2), "×1.1");
  assert.equal(B.fmtMul(1.006, 2), "×1.01");
  assert.equal(B.fmtMul(null, 2), "—");

  const boss = data.nightBosses.find((item) => item.variants.some((entry) => entry.damageRates));
  const entry = B.representativeEntry(boss.variants, "field") || boss.variants[0];
  for (const row of B.topDamageTypes(entry, 3)) {
    const text = B.fmtMul(row.rate, 2);
    const decimals = text.includes(".") ? text.split(".")[1].length : 0;
    assert.ok(decimals <= 2, `承伤徽标小数位过多：${text}`);
  }
});

test("poise > 0 但承受削韧倍率为 0 / 非有限：两端都显示「—」+ 异常说明", () => {
  // macOS：effectivePoise 的 `factor > 0, factor.isFinite` 守卫 → nil，
  // 值格用 BossPoiseKind.value 的占位符，小字写「承受削韧倍率异常（…）」。
  const broken = {
    hp: 1000, hpBase: 1000, hpMultiplier: 1, poise: 120, poiseRecover: 1,
    poiseTakenBase: 0, poiseRecoverMultiplier: 1, ailmentDamageRateBase: 0,
    scaling: { duo: { hp: 2, poiseTaken: 0.55, poiseRecover: 0.55, buildupRate: 1, ailmentDamageRate: 1 } },
  };
  const stats = B.computeStats(broken, 2, false);
  assert.equal(stats.poiseKind, "value", "poise = 120 仍然是「有削韧槽」");
  assert.equal(stats.poiseTakenTotal, 0, "数据里的 0 不能被改写成 1");
  assert.equal(stats.effectivePoise, null, "分母为 0 时算不出有效韧性");
  assert.equal(B.fmtPoise(stats.effectivePoise, stats.poiseKind), "—");
  assert.equal(B.poiseCaption(stats), "承受削韧倍率异常（0）");

  // 另外两种算不出的来源，文案必须分开（与 macOS 的三条分支一致）
  assert.equal(B.fmtPoise(null, "zero"), "无削韧槽");
  assert.equal(B.fmtPoise(null, "none"), "不吃削韧");

  // 正常行不受影响
  const normal = allEntries.find((item) => item.poise > 0 && item.scaling && item.scaling.duo);
  const ok = B.computeStats(normal, 2, false);
  assert.ok(ok.effectivePoise > 0);
});

test("有效韧性小字的四支都与 macOS 的 BossRowText.poiseCaption 逐字一致", () => {
  // 上一轮只统一了「倍率异常」那一支，另外三支仍是两套说法：
  // Windows 写「承受削韧 ×0.55」/ 空串，macOS 写「韧性 120 ÷ 承受削韧 0.55」/
  //「superArmorDurability = 0，该实体没有削韧槽」/「superArmorDurability = -1」。
  assert.equal(
    B.poiseCaption({ effectivePoise: 218.18, poiseRaw: 120, poiseTakenTotal: 0.55, poiseKind: "value" }),
    "韧性 120 ÷ 承受削韧 0.55"
  );
  assert.equal(
    B.poiseCaption({ effectivePoise: null, poiseRaw: 0, poiseTakenTotal: 1, poiseKind: "zero" }),
    "superArmorDurability = 0，该实体没有削韧槽"
  );
  assert.equal(
    B.poiseCaption({ effectivePoise: null, poiseRaw: -1, poiseTakenTotal: 1, poiseKind: "none" }),
    "superArmorDurability = -1"
  );
  assert.equal(
    B.poiseCaption({ effectivePoise: null, poiseRaw: 120, poiseTakenTotal: 0, poiseKind: "value" }),
    "承受削韧倍率异常（0）"
  );

  // 真实数据走同一支：poise < 0 / poise = 0 的行两端都会写出原始值
  const noPoise = allEntries.find((item) => Number(item.poise) < 0);
  if (noPoise) {
    const stats = B.computeStats(noPoise, 1, false);
    assert.equal(stats.poiseKind, "none");
    assert.equal(B.poiseCaption(stats), `superArmorDurability = ${noPoise.poise}`);
  }
  const normal = allEntries.find((item) => item.poise > 0 && item.scaling && item.scaling.duo);
  const ok = B.computeStats(normal, 2, false);
  assert.equal(
    B.poiseCaption(ok),
    `韧性 ${B.fmtNumber(normal.poise, 0)} ÷ 承受削韧 ${B.fmtNumber(ok.poiseTakenTotal, 3)}`
  );
  // 缺字段时两端都回落到 -1（macOS 的 bossDouble(.poise, default: -1)）
  assert.equal(B.computeStats({}, 1, false).poiseRaw, -1);
});

test("numberOr：只在缺字段 / null / 空串 / 非有限时回落，真实的 0 照原样用", () => {
  // macOS 的 bossDouble 走 decodeIfPresent：JSON null 与空串都解不出来 → default。
  // Windows 这边如果只判 isFinite(Number(x))，Number(null) === 0、Number("") === 0
  // 都是有限数，null 那一格反而会和 macOS 对不上。
  assert.equal(B.numberOr(0, 1), 0, "数据里真实的 0 不能被改写成 1");
  assert.equal(B.numberOr(0.55, 1), 0.55);
  assert.equal(B.numberOr(null, 1), 1);
  assert.equal(B.numberOr(undefined, 1), 1);
  assert.equal(B.numberOr("", 1), 1);
  assert.equal(B.numberOr("abc", 1), 1);
  assert.equal(B.numberOr(Infinity, 1), 1);
  assert.equal(B.numberOr("0.55", 1), 0.55, "字符串数字仍按数字用（macOS 的 Double(text) 同支）");

  // 其余几个倍率此前还是 `Number(x) || 1`，同一类问题
  const zeroed = {
    hp: 1000, hpBase: 1000, hpMultiplier: 0, poise: 120, poiseRecover: 2,
    poiseTakenBase: 1, poiseRecoverMultiplier: 0, ailmentDamageRateBase: 2,
    scaling: { duo: { hp: 0, poiseTaken: 1, poiseRecover: 0, buildupRate: 0, ailmentDamageRate: 0 } },
  };
  const stats = B.computeStats(zeroed, 2, false);
  assert.equal(stats.hp, 0, "hpMultiplier / tier.hp 为 0 时不该被改写成 1");
  assert.equal(stats.poiseRecover, 0);
  assert.equal(stats.ailmentDamageRate, 0);
  assert.equal(stats.buildupRate, 0);

  // null 这一格与 macOS 一样回落到 1
  const nulled = {
    hp: 1000, hpBase: 1000, hpMultiplier: null, poise: 120, poiseRecover: 1,
    poiseTakenBase: null, poiseRecoverMultiplier: 1, ailmentDamageRateBase: 1,
    scaling: { duo: { hp: null, poiseTaken: null, poiseRecover: 1, buildupRate: 1, ailmentDamageRate: 1 } },
  };
  const nullStats = B.computeStats(nulled, 2, false);
  assert.equal(nullStats.poiseTakenTotal, 1, "poiseTakenBase / tier.poiseTaken 为 null 时回落到 1");
  assert.equal(nullStats.hp, 1000, "hpMultiplier / tier.hp 为 null 时回落到 1");
});

// ------------------------------------------------ schemaVersion 3 的新展示面

test("多人缩放明细多一列「攻击力」：1 时写「不变」，四个档位真会上浮", () => {
  assert.equal(B.fmtAttackRate(1), "不变");
  assert.equal(B.fmtAttackRate(1.1), "×1.1");
  assert.equal(B.fmtAttackRate(1.2), "×1.2");
  assert.equal(B.fmtAttackRate(null), "—");
  assert.equal(B.fmtAttackRate("abc"), "—");

  // 只有 7744 / 7753 / 7754 / 7758 四档的 attackRate 不是 1（双人 1.1 / 三人 1.2）。
  const raised = Object.keys(data.scalingTiers)
    .filter((key) => data.scalingTiers[key].duo && data.scalingTiers[key].duo.attackRate !== 1)
    .map(Number)
    .sort((a, b) => a - b);
  assert.deepEqual(raised, [7744, 7753, 7754, 7758]);
  for (const key of raised) {
    assert.equal(data.scalingTiers[String(key)].duo.attackRate, 1.1);
    assert.equal(data.scalingTiers[String(key)].trio.attackRate, 1.2);
  }
  // staminaAttackRate 在所有人数缩放行里都是 1，页面不单独展示
  for (const tier of Object.values(data.scalingTiers)) {
    for (const which of ["duo", "trio"]) {
      if (tier[which]) assert.equal(tier[which].staminaAttackRate, 1);
    }
  }

  // 卡片上「多人攻击 ×1.1」的判据就是 stats.partyAttackRate。
  // 神皮使徒「最古老的牢狱」（封印监牢代表行）挂 7754。
  const apostle = data.nightBosses.find((boss) => boss.id === "Godskin Apostle@3560");
  const night = B.representativeEntry(apostle.variants, "evergaol");
  assert.equal(night.scalingId, 7754);
  assert.equal(B.computeStats(night, 1, 0, null).partyAttackRate, 1);
  assert.equal(B.computeStats(night, 2, 0, null).partyAttackRate, 1.1);
  assert.equal(B.computeStats(night, 3, 0, null).partyAttackRate, 1.2);
  assert.equal(
    B.computeStats(night, 3, 0, null).attackRate,
    night.attackRateBase * 1.2,
    "多人攻击力倍率乘在常驻攻击倍率之上"
  );
  // 格拉狄乌斯所在的最终 Boss 档不加攻击力，血量却 ×2 / ×3——「多人不是简单乘倍」的两头
  const gladius = allEntries.find((entry) => entry.npcId === 75000020);
  assert.equal(B.computeStats(gladius, 3, 0, null).partyAttackRate, 1);
  assert.equal(data.scalingTiers["7740"].duo.hp, 1.1, "野外常见档只加 10% 血");
  assert.equal(data.scalingTiers["98810"].duo.hp, 1, "突袭档完全不加血");
});

test("底部人数缩放说明带上 notes.multiplayerScalingAudit 的核实结论", () => {
  const audit = data.notes.multiplayerScalingAudit;
  assert.ok(Array.isArray(audit) && audit.length === 9, "9 条中文结论");
  assert.ok(audit[0].includes("不是"), "第一条就是「多人不是简单乘倍」的结论");
  assert.ok(audit.some((line) => line.includes("攻击力上浮")));
  assert.ok(audit.some((line) => line.includes("防御")));
  assert.ok(audit.some((line) => line.includes("阈值")));
  // 页面把这 9 条原样列在底部折叠区，不做删改
  assert.ok(audit.every((line) => typeof line === "string" && line.length > 0));
});

test("深夜 / 深度 / 变异个体的中文一律取游戏文本", () => {
  assert.equal(B.deepText(data, "deepOfNight"), "深夜");
  assert.equal(B.deepText(data, "depth"), "深度");
  assert.equal(data.deepOfNightText.deepOfNight.textId, 131150);
  assert.equal(data.deepOfNightText.depth.textId, 131011);
  assert.equal(data.deepOfNightText.mutation.textId, 338806);
  assert.ok(data.deepOfNightText.description.zh.includes("深夜"));

  assert.equal(B.depthLabel(data, 0), "常规");
  assert.equal(B.depthLabel(data, 3), "深夜 · 深度 3");
  // 数据缺失时才用兜底串，不会渲染出 undefined
  assert.equal(B.deepText(null, "depth"), "深度");
  assert.equal(B.depthLabel(null, 5), "深夜 · 深度 5");
});

test("底部：深夜各深度概览与变异个体出现只数（是只数不是概率）", () => {
  const depths = data.deepOfNightDepths;
  assert.deepEqual(Object.keys(depths).sort(), ["1", "2", "3", "4", "5"]);
  for (const key of Object.keys(depths)) {
    const row = depths[key];
    assert.equal(row.rankId, Number(key));
    assert.equal(typeof row.cursedUncommonRate, "number");
    assert.equal(typeof row.cursedRareRate, "number");
    assert.equal(typeof row.mapChallengeWeight.map, "number");
    assert.equal(typeof row.cataclysmWeight["2"], "number");
  }
  // 深度 3 起地图挑战权重才从 0/0/100 变成 10/10/80
  assert.deepEqual(depths["1"].mapChallengeWeight, { map: 0, nightlord: 0, none: 100 });
  assert.deepEqual(depths["3"].mapChallengeWeight, { map: 10, nightlord: 10, none: 80 });
  // 这张表里没有任何血量 / 攻击倍率——倍率在每行的 depthStats 里
  for (const row of Object.values(depths)) {
    assert.equal("hp" in row, false);
    assert.equal("attackRate" in row, false);
  }

  const categories = data.mutationCategories;
  assert.equal(categories.length, 46);
  const fieldBoss = categories.filter((row) => row.categoryId === 120);
  assert.ok(fieldBoss.length > 0);
  for (const row of fieldBoss) {
    assert.equal(row.mutatedCount["1"], 0, "深度 1 不会遇到变异的野外首领");
    assert.ok(row.mutatedCount["2"] > 0);
  }
  const gaol = categories.filter((row) => row.categoryId === 160);
  assert.ok(gaol.every((row) => row.mutatedCount["1"] === 0), "封印监牢首领深度 1 同样是 0");
  // 全是整数「只数」，不是 0–100 的百分比
  for (const row of categories) {
    for (const depth of B.DEPTHS) {
      const value = row.mutatedCount[String(depth)];
      assert.equal(Number.isInteger(value), true);
      assert.ok(value >= 0);
    }
  }
});

test("夜王卡片带各深度出现权重，0 表示该深度不会出现", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  for (const lord of data.nightlords) {
    const card = items.find((item) => item.uid === "nl:" + lord.menuId);
    assert.deepEqual(card.depthChanceWeights, lord.depthChanceWeights);
  }
  // 守夜 / 野外 Boss 没有这个参数表，页面不能凭空画一张
  assert.ok(items.filter((item) => item.kind === "boss").every((item) => item.depthChanceWeights === null));

  const gladius = data.nightlords.find((lord) => lord.menuId === 0);
  assert.deepEqual(gladius.depthChanceWeights, { 1: 1000, 2: 800, 3: 650, 4: 500, 5: 500 });

  // 永夜之王与救世旗手深度 1 权重 0 = 深度 1 打不到永夜形态
  const everdark = data.nightlords.filter((lord) => lord.variantKey !== "normal");
  assert.ok(everdark.length > 0);
  for (const lord of everdark) {
    assert.equal(lord.depthChanceWeights["1"], 0, `${lord.nameZh} 深度 1 不该出现`);
  }
  assert.ok(data.nightlords.filter((lord) => lord.variantKey === "normal")
    .every((lord) => lord.depthChanceWeights["1"] > 0));
});

test("buildItems 带齐 schemaVersion 3 的展示字段", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  assert.equal(items.length, data.nightlords.length + data.nightBosses.length);
  for (const item of items) {
    assert.equal(typeof item.hidden, "boolean");
    assert.equal(typeof item.noReward, "boolean");
    assert.equal(typeof item.nameNote, "string");
    assert.equal(typeof item.nameFallback, "string");
    assert.equal(typeof item.nameSourceUrl, "string");
    assert.ok(Array.isArray(item.nameBadges));
  }
  // hidden 的四组都带判据说明，展开区才有话可说
  const hidden = items.filter((item) => item.hidden);
  assert.equal(hidden.length, 4);
  assert.ok(hidden.filter((item) => item.nameNote).length >= 3);
  // 社区来源的组要把链接带出来
  const storm = items.find((item) => item.uid === "nb:Storm King@7910");
  assert.ok(storm.nameSourceUrl.startsWith("https://"));
  // 夜王没有这些字段，一律给稳定的空值
  const lord = items.find((item) => item.kind === "nightlord");
  assert.deepEqual(lord.nameBadges, []);
  assert.equal(lord.hidden, false);
});

test("双端文案表：TEXT 的每一串都与 macOS 的 BossRowText 逐字相同", () => {
  // macOS 端由 checkBossDataParityText() 断言 BossRowText 的同名常量，
  // 两边各自钉死同一批字面量；任一端改文案，另一端立刻红。
  assert.deepEqual(B.TEXT, {
    labelUncertainBadge: "标签为社区推测",
    deepRowBadge: "深夜数值",
    deepRowBadgePartial: "部分行有深夜数值",
    deepExclusiveBadge: "深夜专属修正",
    deepExclusiveBadgePartial: "部分行有深夜专属修正",
    nameFallbackBadge: "参考译名 · 非本作游戏文本",
    nameApproxBadge: "近似匹配",
    nameEnglishOnlyBadge: "仅英文名",
    nameNoGameNameBadge: "无游戏内名称",
    nameManualBadge: "名称手工补录",
    nameInferredBadge: "名称按 ID 推断",
    nameCommunityBadge: "社区资料",
    hiddenToggleTitle: "显示隐藏实体",
    hiddenToggleHelp: "召唤物 / 投射物等非首领实体",
    noRewardGroupNote: "该组不掉任何奖励（getSoul / 掉落表全为 0 或 -1）",
    noRewardRowNote: "该行不掉任何奖励",
    noDepthStatsText: "该行无深夜数值",
    mutationTitle: "变异个体",
    mutationPickerTitle: "按变异个体计算",
    mutationPickerNone: "无",
    mutationStackNote: "变异倍率在其它缩放之上再乘一层，按参数结构推断",
    mutationCountNote: "表里是「有几只被变异」的只数，不是百分比概率",
    attackRateUnchanged: "不变",
    depthWeightZero: "该深度不会出现",
    multiplayerAuditSummary:
      "多人不是简单乘倍：血量按档位从 ×1 到 ×3 不等（最终 Boss 档才是 ×2 / ×3，" +
      "野外常见档 7740 只有 ×1.1 / ×1.2，突袭档 98810 / 98815 完全不加血）；" +
      "7744 / 7753 / 7754 / 7758 四档的敌人攻击力还会上浮 10% / 20%；" +
      "防御、卢恩与掉落、异常触发阈值三项人数缩放一概不碰，" +
      "变的只是异常累积量与发动伤害倍率（都往下走，人越多越难上异常）。",
  });

  // 这几串是靠函数拼出来的，单独钉住（macOS 的同名函数）
  assert.equal(B.multiplayerAttackBadge(1.1), "多人攻击 ×1.1");
  assert.equal(B.multiplayerAttackBadge(1.2), "多人攻击 ×1.2");
  assert.equal(B.depthWeightText(0), "该深度不会出现");
  assert.equal(B.depthWeightText(500), "权重 500");
  assert.equal(B.depthWeightText(1600), "权重 1600", "不加千位分隔符，与 macOS 同串");
  assert.equal(B.fmtAttackRate(1), "不变");

  // 文案表里的串必须真的用在页面上，别留成只给测试看的摆设
  const source = readFileSync(
    path.join(repoRoot, "windows", "renderer", "pages", "bosses.js"), "utf8"
  );
  for (const key of Object.keys(B.TEXT)) {
    assert.ok(source.includes("TEXT." + key), `TEXT.${key} 定义了却没有被用到`);
  }
});

test("数值行标签的四级回退与 macOS 的 displayLabel 一致", () => {
  // isStagingRow 照着这个标签判，两端判据一旦不同代表行就会分叉。
  assert.equal(B.entryLabel({ npcId: 1, labelZh: "甲", labelEn: "A", paramdexName: "P" }), "甲");
  assert.equal(B.entryLabel({ npcId: 1, labelZh: "", labelEn: "A", paramdexName: "P" }), "A");
  assert.equal(B.entryLabel({ npcId: 1, labelZh: "", labelEn: "", paramdexName: "P" }), "P");
  assert.equal(B.entryLabel({ npcId: 12345 }), "行 12345");
  // 数据里 394 行的 labelZh 都非空，走第一支
  assert.equal(allEntries.every((entry) => entry.labelZh), true);
});

test("最新数据集的两个取整事实：hp +1 的 4 行、unmatchedNames 12 条", () => {
  // 第二版核验把整数血量统一成「倍率量化到 6 位小数后 ROUND_HALF_UP」，4 条记录各 +1
  //（大口龙三个变体 5398→5399、神皮贵族 5548→5549）。这 4 行的 hpBase × hpMultiplier
  // 正好落在 .5 上，取整方向一变数字就变，所以逐条钉住。
  const bumped = [
    ["Gaping Dragon@7700", 77000000, 5399],
    ["Gaping Dragon@7700", 77000010, 5399],
    ["Gaping Dragon@7700", 77009010, 5399],
    ["Godskin Noble@3570", 35700010, 5549],
  ];
  for (const [id, npcId, hp] of bumped) {
    const boss = data.nightBosses.find((item) => item.id === id);
    const row = boss.variants.find((item) => item.npcId === npcId);
    assert.equal(row.hp, hp, `${id} / ${npcId}`);
    assert.equal(row.hpBase * row.hpMultiplier, hp - 0.5, "乘积正好落在 .5 上");
    assert.equal(B.computeStats(row, 1, 0, null).hp, hp, "1 人常规血量直接取 hp，不重算");
  }
  // 这 4 行正是全表里唯一落在 .5 上的
  const halves = allEntries.filter((entry) => Math.abs(entry.hpBase * entry.hpMultiplier % 1) === 0.5);
  assert.equal(halves.length, 4);
  // JS 的 Math.round 与 Swift 的 .rounded() 都是「.5 向上」，两端与生成器同向；
  // 页面仍然一律直接读 hp，不给取整口径留第二个实现。
  assert.equal(allEntries.every((entry) => Math.round(entry.hpBase * entry.hpMultiplier) === entry.hp), true);

  // notes.unmatchedNames 只留「游戏文本里查无此名」的 12 条；
  // 4 条「匹配到但因重名让出」的只记在 nameCollisions 里。
  assert.equal(data.notes.unmatchedNames.length, 12);
  assert.equal(data.notes.nameCollisions.length, 4);
  for (const item of data.notes.unmatchedNames) {
    assert.equal(typeof item.nameEn, "string");
    assert.equal(typeof item.chrId, "number");
  }
});

test("深度缺失退常规 + 异常发动伤害基准缺字段回落 1（与 macOS 的解码默认值一致）", () => {
  // macOS 的 BossFight.baseline(mode:)：请求了深度但没有 depthStats 时**整组**退回常规，
  // 不是退回 deepOfNight。上一版 Windows 会退到 deepOfNight，同一条假想行两端给不同的数。
  const noDepth = {
    npcId: 1, hp: 1000, hpBase: 1000, hpMultiplier: 1, poise: 100,
    poiseTakenBase: 1, poiseRecover: 1, poiseRecoverMultiplier: 1,
    ailmentDamageRateBase: 0.5, attackRateBase: 2,
    deepOfNight: {
      hp: 700, hpMultiplier: 0.7, poiseTakenBase: 0.8, attackRateBase: 1.4,
      poiseRecoverMultiplier: 0.2, ailmentDamageRateBase: 0.25, permScalingIds: [999],
    },
  };
  const stats = B.computeStats(noDepth, 1, 3, null);
  assert.equal(stats.hasDepth, false);
  assert.equal(stats.hp, 1000, "退回常规血量，不是 deepOfNight 的 700");
  assert.equal(stats.attackRate, 2);
  assert.equal(stats.poiseTakenTotal, 1);
  assert.equal(stats.poiseRecover, 1, "削韧恢复倍率也退回常规");
  assert.equal(stats.ailmentDamageRate, 0.5);
  assert.deepEqual(stats.permScalingIds, []);

  // 有 depthStats 时才轮到 deepOfNight 供那三项
  const withDepth = Object.assign({}, noDepth, {
    depthStats: { 3: { hp: 2000, hpMultiplier: 2, poiseTakenBase: 0.86, attackRateBase: 5, depthSpEffectId: 7 } },
  });
  const deep = B.computeStats(withDepth, 1, 3, null);
  assert.equal(deep.hasDepth, true);
  assert.equal(deep.hp, 2000);
  assert.equal(deep.poiseTakenTotal, 0.86);
  assert.equal(deep.poiseRecover, 0.2, "削韧恢复倍率取 deepOfNight");
  assert.equal(deep.ailmentDamageRate, 0.25);
  assert.deepEqual(deep.permScalingIds, [999]);
  assert.equal(deep.depthSpEffectId, 7);

  // ailmentDamageRateBase 缺字段时回落到 1（中性倍率），不是 0。
  // macOS 走 `bossDouble(.ailmentDamageRateBase, default: 1)`；上一版 Windows 回落到 0，
  // 会把「数据里没写」显示成「异常发动完全不造成伤害」。
  const bare = { npcId: 2, hp: 100, hpBase: 100, hpMultiplier: 1, poise: 10, poiseTakenBase: 1 };
  assert.equal(B.computeStats(bare, 1, 0, null).ailmentDamageRate, 1);
  // 数据里 394 行都写了这个字段，走不到回落支
  assert.equal(allEntries.every((entry) => typeof entry.ailmentDamageRateBase === "number"), true);
});

test("搜索索引收进 displayFallbackZh：卡头上写着的占位名必须搜得到", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  // v4：这两组只有「随从/召唤物」场合，在那个默认隐藏的分组里（macOS 同一条断言）。
  const hits = B.filterItems(items, "summon", "未知敌人", Core.foldForSearch, true);
  assert.deepEqual(
    hits.map((item) => item.uid).sort(),
    ["nb:Unknown Enemy (c7931)@7931", "nb:Unknown Enemy (c7932)@7932"]
  );
  // 它们是隐藏实体，开关关着时照旧搜不到
  assert.equal(B.filterItems(items, "summon", "未知敌人", Core.foldForSearch).length, 0);
  // 卡片模型里保留原串给展开区说明
  const card = items.find((item) => item.uid === "nb:Unknown Enemy (c7931)@7931");
  assert.equal(card.namePlaceholder, "未知敌人 c7931");
  assert.equal(card.name, "未知敌人 c7931");
  assert.equal(card.nameEn, "Unknown Enemy (c7931)");
});

test("深度覆盖：394 条数值行全有 depthStats，卡片一律判 all", () => {
  const items = B.buildItems(data, Core.foldForSearch);
  assert.equal(items.every((item) => B.deepCoverage(item) === "all"), true);
  assert.equal(B.deepCoverage({ entries: [] }), "none");
  assert.equal(B.deepCoverage({ entries: [{ depthStats: {} }, {}] }), "some");
  assert.equal(B.deepCoverage({ entries: [{}, {}] }), "none");
});
