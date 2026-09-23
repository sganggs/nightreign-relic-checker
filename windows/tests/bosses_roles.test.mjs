// 首领数据页：按出场场合（bossesSchemaVersion 4 的 roles）分组的专项测试。
// 分组规则的正文是 macOS 端 RelicCore 的 BossCard.Group 文档注释（两端唯一正式版本），
// 这边照抄，断言的数字与 macos/Sources/RelicCoreChecks/BossDataChecks.swift 同一批：
//   · 默认六个分组：夜王 / 守夜首领 / 据点首领 / 场景头目 / 封印监牢 / 其它场合；
//     打开「显示隐藏实体」后再多「随从/召唤物」「未放置」两个；
//   · 守夜前哨 / 坑道精英 / 大空洞高塔首领 / 突袭事件 / 黑夜入侵者 / 地图事件 / 其他地图 → 其它场合；
//   · 夜王卡只进「夜王」；守夜 / 野外首领一组属于几个场合就在几个分组里都出现；
//   · 全部场合都是「未放置」「随从/召唤物」的组默认不显示；展开区默认收起只有这两种场合的行；
//   · 代表行第一步按当前分组过滤 roles，之后 isMain → isStagingRow → noReward → 血量最高；
//   · tier / tiers / 行级 threat 只剩展开区「威胁档位」小字。
// 与 macOS 源码逐项比对的部分（文案表、对照表）在 bosses_parity.test.mjs。
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
const fold = Core.foldForSearch;
const items = B.buildItems(data, fold);
const byUid = new Map(items.map((item) => [item.uid, item]));
// 只对应一个场合的分组 → 那个场合
const SINGLE = {
  night: "night", stronghold: "stronghold", field: "field", evergaol: "evergaol",
  summon: "summon", unplaced: "unplaced",
};

const allEntries = [
  ...data.nightlords.flatMap((lord) => lord.fights),
  ...data.nightBosses.flatMap((boss) => boss.variants),
];
const entryById = new Map(allEntries.map((entry) => [entry.npcId, entry]));

// ------------------------------------------------------------------ 常量表

test("场合常量表与数据集 roleNames 对得上（取值、顺序、中文名、分组）", () => {
  assert.equal(data.bossesSchemaVersion, 4);
  // 规范顺序 = roleNames 的键序（含复核后插在 stronghold 之后的 mine）。
  assert.deepEqual(B.ROLE_ORDER, Object.keys(data.roleNames));
  assert.equal(B.ROLE_ORDER.length, 14);
  for (const role of B.ROLE_ORDER) {
    // 内置中文名与数据逐字一致（数据集改了名，这里先红）
    assert.equal(B.ROLE_TEXT.builtinRoleNames[role], data.roleNames[role].zh, role);
    assert.equal(B.roleTitle(data, role), data.roleNames[role].zh, role);
    assert.equal(B.roleTitle(null, role), data.roleNames[role].zh, `${role}：数据缺 roleNames 时走内置表`);
    assert.ok(Object.prototype.hasOwnProperty.call(B.ROLE_GROUP, role), `ROLE_GROUP 缺少 ${role}`);
  }
  assert.equal(data.roleNames.field.zh, "场景头目", "游戏文本对 Field Boss 的叫法（TutorialBody 403200）");

  // 八个分组，键序 = macOS 的 BossCard.Group.allCases
  assert.deepEqual(B.GROUP_ORDER, ["nightlords", "night", "stronghold", "field", "evergaol", "other", "summon", "unplaced"]);
  assert.deepEqual(B.HIDDEN_GROUPS, ["summon", "unplaced"]);
  assert.deepEqual(B.TABS.map((tab) => [tab.key, tab.hiddenByDefault]), [
    ["nightlords", false], ["night", false], ["stronghold", false], ["field", false],
    ["evergaol", false], ["other", false], ["summon", true], ["unplaced", true],
  ]);
  assert.deepEqual(B.visibleTabs(false).map((tab) => tab.key), ["nightlords", "night", "stronghold", "field", "evergaol", "other"]);
  assert.deepEqual(B.visibleTabs(true).map((tab) => tab.key), B.GROUP_ORDER);
  // 单一场合分组的标题 = 对应场合的中文名；夜王分组叫「夜王」不叫「夜王战」
  for (const [group, role] of Object.entries(SINGLE)) {
    assert.equal(B.GROUP_TITLES[group], data.roleNames[role].zh, group);
  }
  assert.equal(B.GROUP_TITLES.nightlords, "夜王");
  assert.equal(B.GROUP_TITLES.other, "其它场合");

  // 场合 → 分组（macOS 的 Group.forRole）
  assert.deepEqual(B.ROLE_GROUP, {
    nightlord: "nightlords",
    night: "night",
    stronghold: "stronghold",
    field: "field",
    evergaol: "evergaol",
    summon: "summon",
    unplaced: "unplaced",
    prelude: "other",
    mine: "other",
    tower: "other",
    raid: "other",
    invader: "other",
    event: "other",
    other: "other",
  });
  assert.deepEqual(B.OTHER_GROUP_ROLES, ["prelude", "mine", "tower", "raid", "invader", "event", "other"]);
  assert.deepEqual(B.HIDDEN_ROLES, ["summon", "unplaced"]);
  // 表外的新取值：归「其它场合」，中文名依次退到英文名、键名
  assert.equal(B.roleGroup("brandNew"), "other");
  assert.equal(B.roleTitle(data, "brandNew"), "brandNew");
  assert.equal(B.roleTitle({ roleNames: { brandNew: { zh: "", en: "Brand New" } } }, "brandNew"), "Brand New");
});

test("normalizeRoles / roleGroups：规范顺序、去重，多重归属与默认隐藏", () => {
  // 已知场合按规范顺序，未知场合按键名排在最后（macOS 的 BossRoleCatalog.normalized）
  assert.deepEqual(B.normalizeRoles(["unplaced", "night", "", "night", "zzz", "aaa"]), ["night", "unplaced", "aaa", "zzz"]);
  assert.deepEqual(B.normalizeRoles(["unplaced", "tower", "night", "tower", null, 3]), ["night", "tower", "unplaced"]);
  assert.deepEqual(B.normalizeRoles(undefined), []);

  // 与 macOS 宽容样本里的 Dual Boss 同一组输入
  assert.deepEqual(B.roleGroups(["tower", "night", "night", "unplaced", "field", "futureRole"], false), {
    groups: ["night", "field", "other", "unplaced"], roleHidden: false, roleMissing: false,
  });
  // 高塔 / 突袭 / 入侵 / 事件 / 前哨 / 坑道 / 其他地图 都合并进「其它场合」
  for (const role of B.OTHER_GROUP_ROLES) {
    assert.deepEqual(B.roleGroups([role], false).groups, ["other"], role);
  }
  // 「随从/召唤物」「未放置」各是一个分组；全部场合都是这两种时默认隐藏
  assert.deepEqual(B.roleGroups(["unplaced"], false), { groups: ["unplaced"], roleHidden: true, roleMissing: false });
  assert.deepEqual(B.roleGroups(["summon", "unplaced"], false), { groups: ["summon", "unplaced"], roleHidden: true, roleMissing: false });
  // 还有别的场合时照常显示，同时也在「未放置」分组里（开关打开时）
  assert.deepEqual(B.roleGroups(["night", "unplaced"], false), { groups: ["night", "unplaced"], roleHidden: false, roleMissing: false });
  // 夜王卡恒只在「夜王」：突袭 / 事件 / 未放置只挂徽标
  assert.deepEqual(B.roleGroups(["raid", "event", "nightlord", "unplaced"], true).groups, ["nightlords"]);
  // 守夜 / 野外首领万一带了 nightlord 场合，归「其它场合」，夜王分组不混进非夜王
  assert.deepEqual(B.roleGroups(["nightlord", "field"], false).groups, ["field", "other"]);
  // roles 缺失：不猜，归「其它场合」、标 roleMissing，不隐藏
  assert.deepEqual(B.roleGroups([], false), { groups: ["other"], roleHidden: false, roleMissing: true });
  assert.deepEqual(B.roleGroups(undefined, true), { groups: ["nightlords"], roleHidden: false, roleMissing: true });

  assert.deepEqual(B.rolesInGroup(["night", "tower", "raid", "unplaced"], "other"), ["tower", "raid"]);
  assert.deepEqual(B.rolesInGroup(["summon", "unplaced"], "unplaced"), ["unplaced"]);
  assert.deepEqual(B.rolesInGroup(["nightlord", "raid"], "nightlords"), ["nightlord"]);
  assert.equal(B.onlyHiddenRoles([]), false, "缺数据不能被当成「未放置」藏起来");
  assert.equal(B.onlyHiddenRoles(["summon"]), true);
});

// ---------------------------------------------------------- 数据侧前提与计数

test("数据侧前提：组级 roles = 各行 roles 的并集，行级 roles = rowRoles 的并集", () => {
  for (const boss of data.nightBosses) {
    const union = B.normalizeRoles(boss.variants.flatMap((v) => v.roles));
    assert.deepEqual(B.normalizeRoles(boss.roles), union, boss.id);
    assert.deepEqual(B.unionRoles(boss, boss.variants), union, boss.id);
    // 组级 roles 缺了时由页面自己并
    assert.deepEqual(B.unionRoles({}, boss.variants), union, boss.id);
  }
  for (const lord of data.nightlords) {
    assert.deepEqual(B.normalizeRoles(lord.roles), B.normalizeRoles(lord.fights.flatMap((f) => f.roles)), lord.nameZh);
  }
  for (const entry of allEntries) {
    assert.deepEqual(B.entryRoles(entry), entry.roles, `npcId ${entry.npcId} 的 roles 已是规范顺序`);
    const fromRows = B.normalizeRoles(Object.values(entry.rowRoles).flat());
    assert.deepEqual(fromRows, entry.roles, `npcId ${entry.npcId}`);
    assert.deepEqual(Object.keys(entry.roleEvidence).sort(), [...entry.roles].sort(), `npcId ${entry.npcId} 每个场合都有证据`);
  }
});

test("分组计数与 roleSummary 一致（含开关前后的条数）", () => {
  // 1. 单一场合的六个分组：打开开关后的卡片数 = roleSummary[role]，卡片都是带该场合的首领组
  for (const [group, role] of Object.entries(SINGLE)) {
    const cards = B.filterItems(items, group, "", fold, true);
    assert.equal(cards.length, data.roleSummary[role], `${group}`);
    assert.equal(cards.length, data.roleSummaryDetail[role].groups, `${group}：roleSummaryDetail.groups`);
    assert.ok(cards.every((item) => item.kind === "boss" && item.roles.includes(role)), group);
  }
  assert.deepEqual(
    ["night", "stronghold", "field", "evergaol", "summon", "unplaced"].map((role) => data.roleSummary[role]),
    [40, 51, 35, 10, 11, 93]
  );

  // 2. 「其它场合」= 七个合并场合的并集 45 组（只有首领组，夜王卡不进）；每个合并场合各自的组数 = roleSummary
  const other = B.filterItems(items, "other", "", fold, true);
  const union = data.nightBosses.filter((boss) => boss.roles.some((role) => B.OTHER_GROUP_ROLES.includes(role)));
  assert.equal(other.length, 45);
  assert.deepEqual(other.map((item) => item.uid).sort(), union.map((boss) => "nb:" + boss.id).sort());
  for (const role of B.OTHER_GROUP_ROLES) {
    assert.equal(other.filter((item) => item.roles.includes(role)).length, data.roleSummary[role], role);
  }

  // 3. 夜王：18 张卡都只进「夜王」，roles 都含 nightlord；其余分组里没有夜王卡
  const lords = B.filterItems(items, "nightlords", "", fold, true);
  assert.equal(lords.length, data.roleSummaryDetail.nightlord.nightlords);
  assert.ok(lords.every((item) => item.kind === "nightlord" && item.roles.includes("nightlord")));
  assert.ok(items.filter((item) => item.kind === "nightlord").every((item) => item.groups.join() === "nightlords"));
  for (const group of B.GROUP_ORDER.filter((key) => key !== "nightlords")) {
    assert.ok(B.filterItems(items, group, "", fold, true).every((item) => item.kind === "boss"), group);
  }

  // 4. 首领组的分组集合 = roles 逐个映射出来的分组集合，一组都不丢
  for (const item of items.filter((card) => card.kind === "boss")) {
    assert.deepEqual([...new Set(item.roles.map(B.roleGroup))].sort(), [...item.groups].sort(), item.uid);
  }
  const shown = new Set(B.GROUP_ORDER.flatMap((group) => B.filterItems(items, group, "", fold, true).map((item) => item.uid)));
  assert.equal(shown.size, items.length, "打开隐藏开关后，每张卡都至少出现在一个分组里");

  // 5. 顶部按钮上的数字（groupCounts）与筛选结果一致：开关关 / 开
  assert.deepEqual(B.groupCounts(items, false), {
    nightlords: 18, night: 40, stronghold: 51, field: 35, evergaol: 10, other: 45, summon: 0, unplaced: 0,
  });
  assert.deepEqual(B.groupCounts(items, true), {
    nightlords: 18, night: 40, stronghold: 51, field: 35, evergaol: 10, other: 45, summon: 11, unplaced: 93,
  });
  for (const showHidden of [false, true]) {
    const counts = B.groupCounts(items, showHidden);
    for (const group of B.GROUP_ORDER) {
      assert.equal(counts[group], B.filterItems(items, group, "", fold, showHidden).length, `${group} / ${showHidden}`);
    }
  }
});

test("「未放置」「随从/召唤物」默认隐藏：分组、卡片、搜索都沿用隐藏开关", () => {
  const hidden = items.filter(B.isItemHiddenByDefault).map((item) => item.uid).sort();
  assert.deepEqual(hidden, [
    "nb:Borealis the Freezing Fog@4503",
    "nb:Centipede Grub@7711",
    "nb:Decaying Ekzykes@4501",
    "nb:Dreg Wormface@7660",
    "nb:Elder Dragon Greyoll@4504",
    "nb:Funeral Steed@3160",
    "nb:Giant Skeleton Torso@4960",
    "nb:Lake Glintstone Dragon@4502",
    "nb:Lord of Blood Spear@4801",
    "nb:Storm King@7910",
    "nb:Unknown Enemy (c7931)@7931",
    "nb:Unknown Enemy (c7932)@7932",
  ]);
  // 4 组 hidden（非首领实体）的场合也只有这两种——两种隐藏共用一个开关
  assert.ok(items.filter((item) => item.hidden).every((item) => item.roleHidden));
  // 默认隐藏的卡只落在两个默认隐藏的分组里，默认可见的分组一张都没有
  for (const item of items.filter(B.isItemHiddenByDefault)) {
    assert.ok(item.groups.every(B.isHiddenGroup), item.uid);
  }
  // 两个默认隐藏的分组：开关关着时整组为空（带搜索也一样）
  assert.equal(B.filterItems(items, "summon", "", fold).length, 0);
  assert.equal(B.filterItems(items, "summon", "", fold, true).length, 11);
  assert.equal(B.filterItems(items, "unplaced", "铃珠猎人", fold).length, 0);
  assert.equal(B.filterItems(items, "unplaced", "铃珠猎人", fold, true).length, 1);
  // 「Centipede」会命中可见的百足恶魔，这里用只属于幼虫那一组的词
  for (const group of B.GROUP_ORDER) {
    assert.equal(B.filterItems(items, group, "Centipede Grub", fold).length, 0, group);
  }
  assert.equal(B.filterItems(items, "summon", "Centipede Grub", fold, true).length, 1);
  // 古龙桂奥尔只有未放置：开关打开后在「未放置」
  assert.deepEqual(B.filterItems(items, "unplaced", "Greyoll", fold, true).map((item) => item.uid), ["nb:Elder Dragon Greyoll@4504"]);
  // 有未放置行、但也有别的场合的组照常显示；打开开关后同时出现在「未放置」
  const flying = byUid.get("nb:Flying Dragon@4500");
  assert.deepEqual(flying.roles, ["field", "unplaced"]);
  assert.deepEqual(flying.groups, ["field", "unplaced"]);
  assert.equal(flying.roleHidden, false);
  assert.equal(B.filterItems(items, "field", "丘陵飞龙", fold).length, 1);
  assert.equal(B.filterItems(items, "other", "丘陵飞龙", fold, true).length, 0, "不会因为未放置行跑进「其它场合」");

  // 列表计数文案（v4 下只在打开开关、停在这两个分组时出现「含隐藏」）
  assert.equal(B.hiddenCountText(0, false), "");
  assert.equal(B.hiddenCountText(12, false), "已隐藏 12 组（未放置 / 随从 / 非首领实体）");
  assert.equal(B.hiddenCountText(12, true), "含隐藏 12 组");
});

test("底部隐藏说明：非首领实体 + 只有未放置/随从场合的组，与 macOS 的 hiddenSummary 同一句", () => {
  // 与 macOS 自检的 expectedHiddenSummary 同一串（bosses_parity.test.mjs 另从 Swift 源码读来比对）。
  const expected =
    "另有 4 组被判定为非首领实体（Centipede Grub、鲜血君王的长枪、未知敌人 c7931、未知敌人 c7932），" +
    "判据是整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出 / 社区标为杂兵；" +
    "另有 8 组只出现在「未放置」「随从/召唤物」两个场合（“冻结冰雾”玻列琉斯、步入腐败仇恨龙、" +
    "Elder Dragon Greyoll、湖之辉石龙、Storm King、废弃物蚯蚓脸、葬送战马、Giant Skeleton Torso）。" +
    "它们默认不在列表里，展开区里只出现在这两个场合的数值行也默认隐藏；" +
    "需要时打开工具条的「显示隐藏实体」，分组筛选里会多出「随从/召唤物」「未放置」两项。";
  assert.equal(B.hiddenSummaryText(items), expected);
  // 两类的名单正好是默认隐藏的 12 组（4 + 8），名字 = 卡头主标题，按数据集顺序
  const flagged = items.filter((item) => item.hidden);
  const roleOnly = items.filter((item) => !item.hidden && B.isItemHiddenByDefault(item));
  assert.equal(flagged.length + roleOnly.length, items.filter(B.isItemHiddenByDefault).length);
  assert.equal(B.hiddenSummaryText(items), B.ROLE_TEXT.hiddenSummary(flagged.map((item) => item.name), roleOnly.map((item) => item.name)));
  // 只有一类时只写那一类；两类都没有时是空串，页面不出这一段
  assert.equal(
    B.ROLE_TEXT.hiddenSummary([], ["丙"]),
    "另有 1 组只出现在「未放置」「随从/召唤物」两个场合（丙）。它们默认不在列表里，" +
      "展开区里只出现在这两个场合的数值行也默认隐藏；" +
      "需要时打开工具条的「显示隐藏实体」，分组筛选里会多出「随从/召唤物」「未放置」两项。"
  );
  assert.equal(B.ROLE_TEXT.hiddenSummary([], []), "");
  assert.equal(B.hiddenSummaryText([]), "");
  assert.equal(B.hiddenSummaryText(items.filter((item) => !B.isItemHiddenByDefault(item))), "");
  // 渲染：不折叠的一段，带测试钩子；没有隐藏的组时整块不出
  const block = B.hiddenSummaryBlock(data);
  assert.ok(block.includes("data-testid='bosses-hidden-summary'"));
  assert.ok(block.includes("另有 4 组被判定为非首领实体") && !block.includes("<details"));
  assert.equal(B.hiddenSummaryBlock({ nightlords: [], nightBosses: [] }), "");
});

test("救世旗手（nl:18）：按场合过滤后代表行由未放置的蠕虫行换成二阶段行（与 macOS 同一组 npcId）", () => {
  const bearers = byUid.get("nl:18");
  assert.equal(bearers.variantName, "救世旗手");
  assert.deepEqual(bearers.groups, ["nightlords"]);
  assert.deepEqual(bearers.roles, ["nightlord", "unplaced"]);
  // 三条 isMain：蠕虫 46410000（6797，未放置）与两条阶段行；另一条联机突袭蠕虫 46410010 不是主战行
  assert.deepEqual(B.mainRows(bearers.entries).map((entry) => entry.npcId), [46410000, 76200210, 76200310]);
  assert.deepEqual(entryById.get(46410000).roles, ["unplaced"]);
  // 旧口径（夜王没有 threat → 不过滤场合，直接收敛 isMain）取的是蠕虫行
  assert.equal(B.representativeEntry(bearers.entries, null).npcId, 46410000);
  // 新口径：第一步按「夜王战」过滤，候选只剩两条阶段行（整池 noReward 不排），取血量高的二阶段
  assert.deepEqual(B.candidateEntries(bearers.entries, "nightlords").map((entry) => entry.npcId), [76200210, 76200310]);
  assert.ok(B.candidateEntries(bearers.entries, "nightlords").every((entry) => entry.noReward));
  assert.equal(B.representativeEntry(bearers.entries, "nightlords").npcId, 76200210);
  assert.equal(bearers.main.npcId, 76200210, "卡片自身主分组下的代表行同样是 76200210");
  // 展开区默认收起那条未放置的蠕虫行，卡头写「3 条数值行（另 1 条已隐藏）」
  assert.equal(B.hiddenEntryCount(bearers.entries, false), 1);
  assert.equal(
    B.ROLE_TEXT.rowCount(B.displayEntries(bearers.entries, false).length, B.hiddenEntryCount(bearers.entries, false)),
    "3 条数值行（另 1 条已隐藏）"
  );
});

test("展开区默认收起只有「未放置」「随从/召唤物」场合的行（macOS 的 displayRows）", () => {
  let hiddenTotal = 0;
  let shownTotal = 0;
  for (const item of items) {
    hiddenTotal += B.hiddenEntryCount(item.entries, false);
    shownTotal += B.displayEntries(item.entries, false).length;
    assert.equal(B.displayEntries(item.entries, true).length, item.entries.length, "打开开关全部列出");
  }
  assert.equal(hiddenTotal, 148);
  assert.equal(shownTotal, 246);
  assert.equal(hiddenTotal + shownTotal, 394);

  const hunter = byUid.get("nb:Bell Bearing Hunter@3100");
  assert.deepEqual(B.displayEntries(hunter.entries, false).map((entry) => entry.npcId).sort(), [31000010, 31000020, 31000030, 31000040]);
  assert.equal(B.hiddenEntryCount(hunter.entries, false), 1, "未放置的 31000000 默认收起");
  // 整卡都是这种行（只在开关打开时可见的卡）：全部列出，免得展开后是空的
  const greyoll = byUid.get("nb:Elder Dragon Greyoll@4504");
  assert.equal(B.displayEntries(greyoll.entries, false).length, greyoll.entries.length);
  assert.equal(B.hiddenEntryCount(greyoll.entries, false), 0);
  // 与 macOS 宽容样本同一组行：只有「未放置」的 13 收起；11 虽含未放置但也是场景头目，照常列出；
  // 没有 roles 的 15 不算默认隐藏
  const sample = [
    { npcId: 10, roles: ["tower", "night"] },
    { npcId: 11, roles: ["unplaced", "field"] },
    { npcId: 13, roles: ["unplaced"] },
    { npcId: 14, roles: ["futureRole"] },
    { npcId: 15 },
  ];
  assert.deepEqual(B.displayEntries(sample, false).map((entry) => entry.npcId), [10, 11, 14, 15]);
  assert.equal(B.hiddenEntryCount(sample, false), 1);
  // 卡头计数与展开区底部那句（macOS 的 BossRoleText.rowCount / hiddenRows）
  assert.equal(B.ROLE_TEXT.rowCount(4, 1), "4 条数值行（另 1 条已隐藏）");
  assert.equal(B.ROLE_TEXT.rowCount(4, 0), "4 条数值行");
  assert.equal(B.ROLE_TEXT.hiddenRows(1), "另有 1 条「未放置」/「随从/召唤物」行已隐藏，打开「显示隐藏实体」查看");
});

// ------------------------------------------------------------ 铃珠猎人四行

test("铃珠猎人四行的 roles 各不相同，且都能在对应分组搜到", () => {
  const hunter = data.nightBosses.find((boss) => boss.id === "Bell Bearing Hunter@3100");
  const card = byUid.get("nb:Bell Bearing Hunter@3100");
  // v3 的 tier 是 night（五行挂的都是 Night Boss Threat 档位），按 tier 会全塞进守夜。
  assert.equal(hunter.tier, "night");
  assert.deepEqual(card.tiers, ["night"], "tier 只剩展开区「威胁档位」小字");
  assert.equal(B.ROLE_TEXT.threatTierCaption(card.tiers), "威胁档位 · 守夜首领威胁档");
  assert.deepEqual(card.roles, ["night", "field", "stronghold", "tower", "unplaced"]);
  assert.deepEqual(card.groups, ["night", "stronghold", "field", "other", "unplaced"]);
  assert.deepEqual(
    Object.fromEntries(hunter.variants.map((v) => [v.npcId, v.roles])),
    {
      31000020: ["night", "tower"], 31000010: ["field"], 31000030: ["field"],
      31000040: ["stronghold"], 31000000: ["unplaced"],
    }
  );
  assert.ok(hunter.variants.every((v) => v.threat === "night"), "五行的 threat 都是 night——不能拿来分组");

  // 四行两两不同；每一行的每个场合对应一个分组，按 npcId 在那个分组里搜得到，且在该分组的候选里
  const four = [31000020, 31000010, 31000040, 31000000].map((id) => entryById.get(id).roles.join("+"));
  assert.equal(new Set(four).size, 4);
  for (const entry of hunter.variants) {
    for (const role of entry.roles) {
      const group = B.roleGroup(role);
      const showHidden = B.isHiddenGroup(group);
      assert.ok(B.filterItems(items, group, String(entry.npcId), fold, showHidden).includes(card), `${entry.npcId} / ${group}`);
      assert.ok(B.candidateEntries(card.entries, group).some((row) => row.npcId === entry.npcId), `${entry.npcId} 在 ${group} 的候选里`);
    }
    // 展开区逐行徽标 = 该行全部场合
    assert.deepEqual(B.entryRoleBadges(entry, data).map((badge) => badge.text), entry.roles.map((role) => data.roleNames[role].zh));
  }
  // 代表行：四个可见分组 + 未放置各给各的
  assert.deepEqual(
    ["night", "field", "stronghold", "other", "unplaced"].map((group) => B.representativeEntry(card.entries, group).npcId),
    [31000020, 31000010, 31000040, 31000020, 31000000]
  );
  // 按名字：守夜首领 / 据点首领 / 场景头目 / 其它场合 四个分组都搜得到，封印监牢里没有
  for (const group of ["night", "stronghold", "field", "other"]) {
    assert.ok(B.filterItems(items, group, "铃珠猎人", fold).includes(card), group);
  }
  assert.equal(B.filterItems(items, "evergaol", "铃珠猎人", fold).length, 0);
  // 场合名也能搜：在「据点首领」里搜「场景头目」同样命中（它同时是场景头目）
  assert.ok(B.filterItems(items, "stronghold", "场景头目", fold).includes(card));
  // 另一条场景头目行 31000030（城堡地下）与 31000010 同场合，候选池两行
  assert.deepEqual(B.candidateEntries(card.entries, "field").map((v) => v.npcId), [31000010, 31000030]);
});

test("多重归属的组在各分组都出现，卡头徽标列出全部场合", () => {
  const sentinel = byUid.get("nb:Tree Sentinel@3251");
  assert.deepEqual(sentinel.groups, ["night", "stronghold", "field", "other", "unplaced"]);
  for (const group of B.visibleGroups(sentinel)) {
    assert.ok(B.filterItems(items, group, "", fold).includes(sentinel), `大树守卫应出现在 ${group}`);
  }
  assert.equal(B.filterItems(items, "evergaol", "", fold).includes(sentinel), false);
  // 卡头徽标：全部场合（含未放置），属于当前分组的着色、其余中性
  assert.deepEqual(
    B.cardRoleBadges(sentinel, data, "field").map((badge) => [badge.text, badge.current, badge.hidden]),
    [["守夜首领", false, false], ["场景头目", true, false], ["据点首领", false, false],
      ["大空洞高塔首领", false, false], ["未放置", false, true]]
  );
  assert.deepEqual(
    B.cardRoleBadges(sentinel, data, "other").filter((badge) => badge.current).map((badge) => badge.text),
    ["大空洞高塔首领"]
  );
  assert.ok(B.cardRoleBadges(sentinel, data, null).every((badge) => badge.current), "不传分组时全部着色");

  // 多重归属的组数：49；默认视图 122 张不同的卡在 6 个分组里共出现 199 次（macOS 同一组数）
  const multi = B.multiGroupItems(items);
  assert.equal(multi.length, 49);
  assert.ok(multi.includes(byUid.get("nb:Bell Bearing Hunter@3100")));
  assert.ok(multi.every((item) => B.hasMultipleGroups(item) && item.kind === "boss"));
  const visibleKeys = B.visibleTabs(false).map((tab) => tab.key);
  const appearances = visibleKeys.reduce((sum, group) => sum + B.filterItems(items, group, "", fold).length, 0);
  const unique = new Set(visibleKeys.flatMap((group) => B.filterItems(items, group, "", fold).map((item) => item.uid)));
  assert.equal(unique.size, 122);
  assert.equal(appearances, 199);

  // 丘陵飞龙野外版 45000010 挂守夜档位 7753，但只作为场景头目出现：
  // 用户反馈的「野外首领被归到守夜首领」就是这一类。
  const flyingRow = entryById.get(45000010);
  assert.equal(flyingRow.scalingId, 7753);
  assert.equal(flyingRow.threat, "night");
  assert.deepEqual(flyingRow.roles, ["field"]);
  assert.equal(B.filterItems(items, "night", "丘陵飞龙", fold).length, 0, "不再出现在守夜首领");
  assert.equal(B.filterItems(items, "field", "丘陵飞龙", fold).length, 1);

  // 夜王卡只在「夜王」；突袭 / 地图事件 / 未放置只挂徽标，卡头也挂「夜王战」
  const lipra = byUid.get("nl:4");
  assert.deepEqual(lipra.groups, ["nightlords"]);
  assert.deepEqual(
    B.cardRoleBadges(lipra, data, "nightlords").map((badge) => [badge.text, badge.current]),
    [["突袭事件", false], ["地图事件", false], ["夜王战", true], ["未放置", false]]
  );
  // 「其它场合」里搜「突袭」只剩恶兆妖鬼；六位带突袭行的夜王在「夜王」里搜得到
  assert.deepEqual(B.filterItems(items, "other", "突袭", fold).map((item) => item.uid), ["nb:Morgott@2130"]);
  assert.deepEqual(
    B.filterItems(items, "nightlords", "突袭事件", fold).map((item) => item.uid),
    ["nl:0", "nl:2", "nl:3", "nl:4", "nl:6", "nl:8"]
  );
});

// ------------------------------------------------------------- 展开区：出处

test("出处摘要「表名 行 · 地图」与 macOS 的 BossRoleEvidence.summary 同一口径", () => {
  // 与 macOS 的 evidenceCases 同一张表（bosses_parity.test.mjs 另从 Swift 源码读这张表再跑一遍）
  const cases = [
    [31000020, "night", "LotResultPlayAreaParam bossId1 = 4924 · m49_24_00_00"],
    [31000020, "tower", "LotResultSmallBaseAndSpot smallBaseMapId = 4924 · m49_24_00_00"],
    [31000010, "field", "ChaosMatchingMutationEnemyTableParam 46560000 · m46_56_00_00"],
    [31000040, "stronghold", "SmallBaseMapVariationParam 5380 · m53_80_00_00"],
    // 未放置：row 是「—」占位，只写表名
    [31000000, "unplaced", "MSB"],
    // 其他地图：row 就是地图名，不重复
    [21300520, "other", "MSB m35_90_00_00"],
    // 入侵者：不经过 MSB，msb 为 null
    [600030010, "invader", "SmallbaseInvationNpcParam 100"],
  ];
  for (const [npcId, role, expected] of cases) {
    assert.equal(B.evidenceSummaryText(B.roleEvidenceList(entryById.get(npcId), role)[0]), expected, `${npcId} / ${role}`);
  }
  assert.equal(B.evidenceSummaryText({ npcId: 1, msb: null, table: "", row: "—", note: "" }), "出处：数据未内置");
  assert.equal(B.evidenceSummaryText(null), "出处：数据未内置");

  // 据点首领的 note 就是 Paramdex 名：摘要里不再重复写一遍地图名（上一版「…（Eastern Underground
  // Fort (Icon) - Rot）：Eastern Underground Fort (Icon) - Rot」），地图名只进悬停提示
  const stronghold = B.roleEvidenceLines(entryById.get(31000040), data, false)[0];
  assert.equal(stronghold.items[0].summary, "SmallBaseMapVariationParam 5380 · m53_80_00_00");
  assert.equal(stronghold.items[0].note, "Eastern Underground Fort (Icon) - Rot");
  assert.ok(stronghold.items[0].hint.startsWith("m53_80_00_00："), stronghold.items[0].hint);
  const night = B.roleEvidenceLines(entryById.get(31000020), data, false)[0];
  assert.equal(night.items[0].hint, "m49_24_00_00：Night Boss - Bell-bearing Hunter (Elemer) · c3100_9000（entityId 49240800）");
});

test("展开区「出场场合」小节：每个场合第一条出处，另有几条、展开全部、出处来自哪条原始行", () => {
  // 格拉狄乌斯远征首领 75000020 合并了 4 行：夜王战的出处 3 条，未放置那条来自 75001020
  const gladius = entryById.get(75000020);
  assert.deepEqual(gladius.npcIds, [75000020, 75001020, 75002020, 75003020]);
  const lines = B.roleEvidenceLines(gladius, data, false);
  assert.deepEqual(lines.map((line) => [line.text, line.total, line.items.length, line.more]), [
    ["夜王战", 3, 1, 2],
    ["未放置", 1, 1, 0],
  ]);
  assert.equal(lines[0].items[0].npcId, null, "出处就是本行时不标「行 N」");
  assert.equal(lines[1].items[0].npcId, 75001020, "出处来自被合并掉的原始行时标出来");
  assert.equal(B.ROLE_TEXT.evidenceMore(lines[0].more), "另有 2 条出处");
  assert.equal(B.hasMoreEvidence(gladius), true);
  // 展开全部：每条出处都给出来，不再有「另有 N 条」
  const all = B.roleEvidenceLines(gladius, data, true);
  assert.deepEqual(all.map((line) => [line.items.length, line.more]), [[3, 0], [1, 0]]);
  // 铃珠猎人守夜行每个场合只有一条：没有「展开全部出处」
  assert.equal(B.hasMoreEvidence(entryById.get(31000020)), false);

  // 坏元素跳过；某个场合没有出处时 missing（页面写「出处：数据未内置」）
  const broken = {
    npcId: 10, roles: ["tower", "night", "night"],
    roleEvidence: { night: [{ npcId: 10, msb: "m49_24_00_00", table: "LotResultPlayAreaParam", row: "bossId1 = 4924", note: "测试" }, 42, null] },
  };
  assert.deepEqual(B.roleEvidenceList(broken, "night").length, 1);
  const brokenLines = B.roleEvidenceLines(broken, data, false);
  assert.deepEqual(brokenLines.map((line) => [line.role, line.missing]), [["night", false], ["tower", true]]);
  assert.equal(brokenLines[0].items[0].summary, "LotResultPlayAreaParam bossId1 = 4924 · m49_24_00_00");
  assert.deepEqual(B.roleEvidenceLines({ npcId: 2 }, data, false), [], "没有 roles 的行页面写「出场场合：数据未内置」");

  // 每条数值行的每个场合都有出处，摘要不会渲染出 undefined / null
  for (const entry of allEntries) {
    for (const line of B.roleEvidenceLines(entry, data, true)) {
      assert.equal(line.missing, false, `npcId ${entry.npcId} / ${line.role}`);
      for (const item of line.items) {
        assert.ok(item.summary && !/undefined|null/.test(item.summary), `npcId ${entry.npcId}：${item.summary}`);
      }
    }
  }
});

test("合并行的逐行场合（macOS 的 rowRolesSummary）", () => {
  assert.equal(
    B.rowRolesSummary(entryById.get(75000020), data),
    "逐行场合：夜王战 75000020 / 75002020 / 75003020；未放置 75001020"
  );
  const withLines = allEntries.filter((entry) => B.rowRolesSummary(entry, data));
  assert.equal(withLines.length, 50, "各原始行场合不同的合并行 50 个");
  assert.equal(
    withLines.length,
    allEntries.filter((entry) => new Set(Object.values(entry.rowRoles).map((roles) => roles.join("+"))).size > 1).length
  );
  // 单行变体、或各行场合相同的合并行都不写
  assert.equal(B.rowRolesSummary(entryById.get(31000020), data), "");
  // 与 macOS 宽容样本同一组输入：转不成 npcId 的键丢掉；roleNames 缺失时用内置中文名
  const row10 = { npcId: 10, roles: ["night", "tower"], rowRoles: { 10: ["night", "tower"], x: ["field"] } };
  assert.deepEqual(B.rowRoleGroups(row10), [{ roles: ["night", "tower"], npcIds: [10] }]);
  assert.equal(B.rowRolesSummary(row10, null), "");
  const row11 = { npcId: 11, npcIds: [11, 12], roles: ["field", "unplaced"], rowRoles: { 11: ["field"], 12: ["unplaced"] } };
  assert.equal(B.rowRolesSummary(row11, null), "逐行场合：场景头目 11；未放置 12");
  // 同一组场合用「 + 」连接
  const combo = { npcId: 1, npcIds: [1, 2], rowRoles: { 1: ["tower", "night"], 2: ["unplaced"] } };
  assert.equal(B.rowRolesSummary(combo, data), "逐行场合：守夜首领 + 大空洞高塔首领 1；未放置 2");
});

test("卡片级场合一览与「威胁档位」小字", () => {
  const sentinel = byUid.get("nb:Tree Sentinel@3251");
  assert.deepEqual(B.roleEntryCounts(sentinel.entries, sentinel.roles), [
    { role: "night", rows: 1 },
    { role: "field", rows: 1 },
    { role: "stronghold", rows: 1 },
    { role: "tower", rows: 1 },
    { role: "unplaced", rows: 4 },
  ]);
  assert.equal(B.ROLE_PAGE_TEXT.roleRowsChip("场景头目", 2), "场景头目 · 2 行");
  // 组级威胁档位（macOS 的 BossCard.tiers）：tiers 非空用 tiers，否则 tier；tier 缺字段按 field
  assert.deepEqual(B.cardTiers({ tier: "night", tiers: ["field", "night"] }), ["field", "night"]);
  assert.deepEqual(B.cardTiers({ tier: "night", tiers: [] }), ["night"]);
  assert.deepEqual(B.cardTiers({}), ["field"]);
  assert.deepEqual(B.cardTiers({ tier: "" }), []);
  assert.deepEqual(byUid.get("nb:Large Golden Hippopotamus@5010").tiers, ["field", "night"]);
  assert.deepEqual(byUid.get("nl:0").tiers, [], "夜王没有 tier");
  for (const boss of data.nightBosses) {
    assert.ok(byUid.get("nb:" + boss.id).tiers.length, `${boss.id} 应有威胁档位小字`);
  }
  // 「威胁档位 · …」：档位组名去重保序，空时写「无」，未知取值原样
  assert.equal(B.ROLE_TEXT.threatTierCaption(["night"]), "威胁档位 · 守夜首领威胁档");
  assert.equal(B.ROLE_TEXT.threatTierCaption(["night", "field", "night"]), "威胁档位 · 守夜首领威胁档 / 野外首领威胁档");
  assert.equal(B.ROLE_TEXT.threatTierCaption([]), "威胁档位 · 无");
  assert.equal(B.ROLE_TEXT.threatTierCaption(["brandNew"]), "威胁档位 · brandNew");

  // 「多人缩放（档位 #7753 · 守夜首领威胁档）」只在最容易误读的 45 行后补一句说明：
  // 不当守夜首领却挂守夜首领威胁档（35 行），或守夜首领行挂野外首领威胁档（10 行）
  const tiers = data.scalingTiers;
  assert.equal(B.threatRoleMismatch(entryById.get(31000010), tiers), true, "铃珠猎人野外版挂 7753");
  assert.equal(B.threatRoleMismatch(entryById.get(31000020), tiers), false, "守夜行挂守夜档，不补");
  assert.equal(B.threatRoleMismatch(entryById.get(31000000), tiers), false, "默认收起的未放置行不补");
  assert.equal(B.threatRoleMismatch({ npcId: 1, scalingId: 7753 }, tiers), false, "没有 roles 的行不补");
  assert.equal(allEntries.filter((entry) => B.threatRoleMismatch(entry, tiers)).length, 45);
  const crucible = data.nightBosses.find((boss) => boss.id === "Crucible Knight@2500");
  assert.ok(crucible.variants.some((entry) => B.threatRoleMismatch(entry, tiers) && entry.roles.includes("night")));
});

test("搜索索引收全部场合的 roleNames 中英文名，不收取值 key 与判定口径", () => {
  assert.deepEqual(B.roleSearchTerms(data, ["unplaced", "night"]), ["守夜首领", "Night Boss", "未放置", "Not Placed"]);
  assert.deepEqual(B.roleSearchTerms(null, ["tower"]), ["大空洞高塔首领"], "缺 roleNames 时退内置中文名，没有英文名就不收");
  // 英文名可搜（大小写不敏感）
  const evergaolCount = B.filterItems(items, "evergaol", "", fold).length;
  assert.equal(B.filterItems(items, "evergaol", "EVERGAOL", fold).length, evergaolCount);
  const towerCards = B.filterItems(items, "other", "", fold).filter((item) => item.roles.includes("tower"));
  assert.equal(B.filterItems(items, "other", "高塔", fold).filter((item) => item.roles.includes("tower")).length, towerCards.length);
  assert.equal(B.filterItems(items, "other", "Great Hollow Tower", fold).length, towerCards.length);
  // description 里的词（如 LotResultPlayAreaParam）不进索引
  assert.equal(B.filterItems(items, "night", "LotResultPlayAreaParam", fold).length, 0);
  // 取值 key 不进索引：「unplaced」只是 key（英文名是 Not Placed）
  for (const group of B.GROUP_ORDER) {
    assert.equal(B.filterItems(items, group, "unplaced", fold, true).length, 0, group);
  }
  // 「未放置」写在卡头徽标上（全部场合都挂），所以搜得到带未放置行的组，搜到的卡头上都看得见
  const unplacedHits = B.filterItems(items, "night", "未放置", fold);
  assert.ok(unplacedHits.length > 0);
  for (const item of unplacedHits) {
    assert.ok(B.cardRoleBadges(item, data, "night").some((badge) => badge.text === "未放置"), item.uid);
  }
  // 夜王卡的「夜王战」同理：卡头挂着，搜 Nightlord Battle 命中全部 18 位
  assert.equal(B.filterItems(items, "nightlords", "nightlord battle", fold).length, 18);
  assert.ok(items.filter((item) => item.kind === "nightlord")
    .every((item) => B.cardRoleBadges(item, data, "nightlords").some((badge) => badge.text === "夜王战")));
  // 合并分组的名字「其它场合」不是场合，不进搜索串
  assert.ok(items.every((item) => item.search.indexOf(fold("其它场合")) === -1));
  // 「坑道精英」只在两组山妖上
  assert.deepEqual(
    B.filterItems(items, "other", "坑道精英", fold).map((item) => item.uid),
    ["nb:Stonedigger Troll@4603", "nb:Troll@4600"]
  );
});

test("代表行第一步按当前分组过滤 roles，其后四步顺序不变", () => {
  // 构造一组：守夜行血量最高，场景头目两行（一行演出、一行不掉奖励），据点首领一行，未放置一行
  const rows = [
    { npcId: 1, hp: 9000, roles: ["night"] },
    { npcId: 2, hp: 5000, roles: ["field"], labelZh: "血条实体" },
    { npcId: 3, hp: 4000, roles: ["field"], noReward: true },
    { npcId: 4, hp: 3000, roles: ["field"] },
    { npcId: 5, hp: 2000, roles: ["stronghold", "unplaced"] },
    { npcId: 6, hp: 9999, roles: ["unplaced"] },
  ];
  assert.equal(B.representativeEntry(rows, "night").npcId, 1);
  assert.equal(B.representativeEntry(rows, "field").npcId, 4, "排掉演出行与无奖励行");
  assert.equal(B.representativeEntry(rows, "stronghold").npcId, 5);
  // 「未放置」分组：5 与 6 都带未放置，取血量高的 6
  assert.deepEqual(B.candidateEntries(rows, "unplaced").map((row) => row.npcId), [5, 6]);
  assert.equal(B.representativeEntry(rows, "unplaced").npcId, 6);
  // 分组里一行都对不上时整池放行
  assert.equal(B.representativeEntry(rows, "evergaol").npcId, 6);
  assert.equal(B.representativeEntry(rows, null).npcId, 6, "不带分组时不按场合过滤");
  // isMain 在场合过滤之后：别的场合的主战行不会抢位（救世旗手的未放置蠕虫行就是这样）
  const mains = [
    { npcId: 10, hp: 100, roles: ["nightlord"], isMain: true },
    { npcId: 11, hp: 900, roles: ["unplaced"], isMain: true },
    { npcId: 12, hp: 500, roles: ["nightlord"] },
  ];
  assert.equal(B.representativeEntry(mains, "nightlords").npcId, 10);
  // noReward 那一层在「未放置」分组里的实例：神皮使徒的 Paramdex 模板行 35600900 让位
  const apostle = byUid.get("nb:Godskin Apostle@3560");
  assert.equal(entryById.get(35600900).noReward, true);
  assert.equal(B.representativeEntry(apostle.entries, "unplaced").npcId, 35600000);
});

test("roles 缺失时页面照常出卡，写「出场场合：数据未内置」而不是按 tier 猜", () => {
  const legacy = {
    nightlords: [{ menuId: 1, nameZh: "旧夜王", fights: [{ npcId: 1, hp: 100, isMain: true }] }],
    nightBosses: [{ id: "Old@1", nameEn: "Old", tier: "night", tiers: ["night"], chrIds: [1], variants: [{ npcId: 2, hp: 50 }] }],
  };
  const legacyItems = B.buildItems(legacy, fold);
  assert.deepEqual(legacyItems.map((item) => [item.uid, item.groups, item.roleMissing, item.roleHidden]), [
    ["nl:1", ["nightlords"], true, false],
    ["nb:Old@1", ["other"], true, false],
  ]);
  assert.equal(B.filterItems(legacyItems, "night", "", fold).length, 0, "tier = night 不再把它塞进守夜首领");
  assert.equal(B.filterItems(legacyItems, "other", "", fold).length, 1);
  assert.deepEqual(legacyItems[1].tiers, ["night"]);
  assert.equal(B.ROLE_TEXT.rolesMissing, "出场场合：数据未内置");
  // 展开区的行全部照常列出（没有 roles 不算「未放置」）
  assert.equal(B.displayEntries(legacyItems[1].entries, false).length, 1);

  // 与 macOS 宽容样本里的 Dual Boss 同一组输入：组级 roles 缺失时取各行并集，代表行按 roles 选
  const dual = B.buildItems({
    nightBosses: [{
      id: "Dual Boss@4600", nameEn: "Dual Boss", chrIds: [4600], tier: "night", tiers: ["field", "night"],
      variants: [
        { npcId: 10, hp: 100, threat: "night", roles: ["tower", "night", "night"] },
        { npcId: 11, npcIds: [11, 12], hp: 90, threat: "night", roles: ["unplaced", "field"] },
        { npcId: 13, hp: 80, threat: "field", roles: ["unplaced"] },
        { npcId: 14, hp: 70, roles: ["futureRole"] },
      ],
    }],
  }, fold)[0];
  assert.deepEqual(dual.roles, ["night", "field", "tower", "unplaced", "futureRole"]);
  assert.deepEqual(dual.groups, ["night", "field", "other", "unplaced"]);
  assert.equal(dual.group, "night", "主分组取第一个");
  assert.equal(B.representativeEntry(dual.entries, "field").npcId, 11, "它的 threat 是 night 也不影响");
  assert.equal(B.representativeEntry(dual.entries, "night").npcId, 10);
  assert.deepEqual(B.displayEntries(dual.entries, false).map((entry) => entry.npcId), [10, 11, 14]);
});

test("底部「出场场合说明」：场合 → 分组、卡片计数、默认隐藏的分组标注", () => {
  const rows = B.roleOverviewRows(data, items);
  assert.equal(rows.length, 14);
  assert.equal(B.ROLE_TEXT.overviewTitle(rows.length), "出场场合说明（14 种）");
  const table = Object.fromEntries(rows.map((row) => [row.role, [row.groupText, row.countText]]));
  assert.deepEqual(table, {
    night: ["守夜首领", "40 组"],
    prelude: ["其它场合", "6 组"],
    field: ["场景头目", "35 组"],
    stronghold: ["据点首领", "51 组"],
    mine: ["其它场合", "2 组"],
    evergaol: ["封印监牢", "10 组"],
    tower: ["其它场合", "26 组"],
    raid: ["其它场合", "1 组 · 夜王 6"],
    invader: ["其它场合", "10 组"],
    event: ["其它场合", "5 组 · 夜王 1"],
    nightlord: ["夜王", "夜王 18"],
    summon: ["随从/召唤物（默认隐藏）", "11 组"],
    other: ["其它场合", "8 组"],
    // 「未放置」自己是一个默认隐藏的分组：打开开关后那个分组里正好 93 张卡——
    // 不再写成上一版的「其它场合（默认隐藏）· 93 组」（读起来像「其它场合」要多出 93 组）
    unplaced: ["未放置（默认隐藏）", "93 组 · 夜王 15"],
  });
  // 首领组的计数 = roleSummary，夜王另计 = roleSummaryDetail.nightlords
  for (const role of B.ROLE_ORDER) {
    const text = table[role][1];
    const lords = data.roleSummaryDetail[role].nightlords;
    assert.equal(text, B.ROLE_TEXT.roleCountText(data.roleSummary[role], lords), role);
  }
  // 数据集里多出来的未知场合按键名排在后面
  assert.deepEqual(B.orderedRoles({ roleNames: { zeta: {}, alpha: {} }, roleSummary: { beta: 1 } }).slice(14), ["alpha", "beta", "zeta"]);
});

test("场合文案都来自常量表，并且真的用在了页面上", () => {
  const source = readFileSync(path.join(repoRoot, "windows", "renderer", "pages", "bosses.js"), "utf8");
  for (const key of Object.keys(B.ROLE_TEXT)) {
    assert.ok(source.includes("ROLE_TEXT." + key), `ROLE_TEXT.${key} 定义了却没有被用到`);
  }
  for (const key of Object.keys(B.ROLE_PAGE_TEXT)) {
    assert.ok(source.includes("ROLE_PAGE_TEXT." + key), `ROLE_PAGE_TEXT.${key} 定义了却没有被用到`);
  }
  // 上一版自拟、macOS 没有对应常量的几条不能再出现
  for (const stale of ["场合依据", "全部依据", "roleHiddenNote", "threatNote", "roleEvidenceAll"]) {
    assert.equal(source.includes(stale), false, `旧文案 / 旧键「${stale}」还在`);
  }
  // 页面上不再出现把 tier 当分组的旧文案
  assert.equal(source.includes("两边都出现"), false);
  assert.equal(/野外首领"/.test(source), false, "分组名不再写「野外首领」");
});
