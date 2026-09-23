// 增伤排名页「自己组一套配置」的整套口径测试（真实数据 + 少量合成用例）。
//
// 覆盖：槽位上限与深夜专属上限、exclusiveKey 去重、遗物合法性接入（Core.check 的合法 / 非法示例、
// 深夜诅咒配对）、appliesTo 分流、叠层输入换算、汇总连乘、推荐填满不越界。
// 数值会随数据集修订变化，这里一律按「数据里的字段」现算期望值，不写绝对快照。
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const Page = require("../renderer/pages/ranker.js");
const Core = require("../renderer/core.js");
const R = Page._internals;

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const resource = (name) => path.join(repoRoot, "windows", "resources", name);
const skills = R.decorateSkills(JSON.parse(readFileSync(resource("skills.json"), "utf8")));
const buffs = JSON.parse(readFileSync(resource("buffs.json"), "utf8"));
const catalog = JSON.parse(readFileSync(resource("affixes.json"), "utf8"));
const index = R.indexBuffs(buffs);
const cfgIndex = R.buildConfigIndex(buffs, index, catalog, Core);
const affixById = new Map(catalog.affixes.map((affix) => [affix.effectId, affix]));
const rules = buffs.slotRules;

function outputFor(kind, id, weaponId, extra) {
  const isSpell = kind !== "skill";
  const weapon = weaponId ? skills._weaponById[weaponId] : null;
  const source = isSpell ? skills._spellById[id] : skills._skillById[id];
  const hits = (isSpell ? source.hits : R.selectHits(source, weapon)).filter((hit) => !hit.noDamage && !hit.noFp);
  const comp = R.composition(hits, weapon, isSpell);
  return R.makeOutput(Object.assign({
    mode: kind, meansId: id, weapon, hand: 1, shares: comp.shares, contexts: {}
  }, extra || {}), buffs);
}

const corpse = outputFor("skill", 1177, 9040000);          // 尸横遍野 + 尸山血海（刀）
const lion = outputFor("skill", 100, 3180000);              // 狮子斩 + 大剑
const comet = outputFor("sorcery", 4021, null);             // 帚星
const lightning = outputFor("incantation", 5040, null);     // 死亡雷击

function withAffixes(list, runMode) {
  let config = R.emptyConfig();
  config.runMode = runMode || "normal";
  list.forEach((id) => { config = R.stepWeaponAffix(cfgIndex, config, id, 1); });
  return config;
}

function customCard(affixIds, curseIds) {
  const card = R.emptyRelicCard();
  card.type = "custom";
  card.affixIds = [affixIds[0] ?? null, affixIds[1] ?? null, affixIds[2] ?? null];
  card.curseIds = [(curseIds || [])[0] ?? null, (curseIds || [])[1] ?? null, (curseIds || [])[2] ?? null];
  return card;
}

function close(actual, expected, message) {
  assert.ok(Math.abs(actual - expected) <= 1e-9, message + "（期望 " + expected + "，实际 " + actual + "）");
}

// ------------------------------------------------------------------ 武器词条槽位

test("常规：武器词条总数不超过 slotRules.weaponAffix.maxAffixesNormal，满了步进就停", () => {
  const normalIds = cfgIndex.weaponAffixes.filter((affix) => R.weaponAffixAvailable(affix, "normal")).map((affix) => affix.id);
  assert.ok(normalIds.length > rules.weaponAffix.maxAffixesNormal);
  let config = R.emptyConfig();
  normalIds.forEach((id) => { config = R.stepWeaponAffix(cfgIndex, config, id, 1); });
  const usage = R.weaponAffixUsage(cfgIndex, config);
  assert.equal(usage.used, rules.weaponAffix.maxAffixesNormal);
  assert.equal(usage.cap, rules.weaponAffix.maxAffixesNormal);
  const blocked = R.canAddWeaponAffix(cfgIndex, config, normalIds[normalIds.length - 1]);
  assert.equal(blocked.ok, false);
  assert.equal(blocked.reason, R.TEXT.waCapReached);
  // 同一条词条也能叠数量（只是同键只计一份），减到 0 就从配置里移除。
  let one = R.stepWeaponAffix(cfgIndex, R.emptyConfig(), normalIds[0], 1);
  one = R.stepWeaponAffix(cfgIndex, one, normalIds[0], 1);
  assert.equal(one.weaponAffixes[0].count, 2);
  one = R.stepWeaponAffix(cfgIndex, R.stepWeaponAffix(cfgIndex, one, normalIds[0], -1), normalIds[0], -1);
  assert.equal(one.weaponAffixes.length, 0);
});

test("常规：深夜专属词条不可用；深夜：总数 ≤ maxAffixesDeep，深夜专属正面词条 ≤ maxDeepOnlyAffixes", () => {
  const deepOnly = cfgIndex.weaponAffixes.filter((affix) => affix.deepOnlyPositive);
  assert.ok(deepOnly.length > 0);
  deepOnly.forEach((affix) => {
    assert.equal(R.weaponAffixAvailable(affix, "normal"), false, affix.id + " 常规模式不该出现");
    assert.equal(R.weaponAffixAvailable(affix, "deep"), true);
  });
  const normalBlocked = R.canAddWeaponAffix(cfgIndex, R.emptyConfig(), deepOnly[0].id);
  assert.equal(normalBlocked.ok, false);
  assert.equal(normalBlocked.reason, R.TEXT.waNotInMode);

  let config = R.emptyConfig();
  config.runMode = "deep";
  for (let round = 0; round < 3; round += 1) {
    deepOnly.forEach((affix) => { config = R.stepWeaponAffix(cfgIndex, config, affix.id, 1); });
  }
  const usage = R.weaponAffixUsage(cfgIndex, config);
  assert.equal(usage.deepOnlyUsed, rules.weaponAffix.maxDeepOnlyAffixes, "深夜专属按 weaponAffixDeepOnlyPositive 计数、到上限为止");
  assert.equal(usage.deepOnlyCap, rules.weaponAffix.maxDeepOnlyAffixes);
  assert.equal(R.canAddWeaponAffix(cfgIndex, config, deepOnly[0].id).reason, R.TEXT.waDeepOnlyCapReached);
  // 深夜专属满了仍可加普通词条，直到总上限。
  cfgIndex.weaponAffixes.filter((affix) => !affix.deepOnlyPositive).forEach((affix) => {
    config = R.stepWeaponAffix(cfgIndex, config, affix.id, 1);
  });
  const full = R.weaponAffixUsage(cfgIndex, config);
  assert.equal(full.used, rules.weaponAffix.maxAffixesDeep);
  assert.ok(full.deepOnlyUsed <= full.deepOnlyCap);
});

test("诅咒不进正面词条栏，也不计入深夜专属上限（deepOnlyCapCountsCurses=false）", () => {
  assert.equal(rules.weaponAffix.deepOnlyCapCountsCurses, false);
  const curses = buffs.weaponAffixes.filter((affix) => (affix.roles || []).indexOf("curse") !== -1);
  assert.ok(curses.length > 0);
  curses.forEach((affix) => assert.equal(cfgIndex.weaponAffixById[affix.attachEffectId], undefined));
});

test("深夜切回常规：去掉深夜专属，再从最后加入的开始削到常规上限", () => {
  let config = R.emptyConfig();
  config.runMode = "deep";
  const deepOnly = cfgIndex.weaponAffixes.filter((affix) => affix.deepOnlyPositive).slice(0, 2);
  const normal = cfgIndex.weaponAffixes.filter((affix) => R.weaponAffixAvailable(affix, "normal")).slice(0, 9);
  deepOnly.concat(normal).forEach((affix) => { config = R.stepWeaponAffix(cfgIndex, config, affix.id, 1); });
  assert.equal(R.weaponAffixUsage(cfgIndex, config).used, 11);
  const back = R.applyRunMode(cfgIndex, config, "normal");
  const usage = R.weaponAffixUsage(cfgIndex, back);
  assert.equal(back.runMode, "normal");
  assert.equal(usage.used, rules.weaponAffix.maxAffixesNormal);
  assert.equal(usage.deepOnlyUsed, 0);
  assert.deepEqual(back.weaponAffixes.map((one) => one.id), normal.slice(0, usage.cap).map((affix) => affix.id), "保留先加入的");
  assert.equal(R.weaponAffixUsage(cfgIndex, config).used, 11, "不改原配置");
});

test("武器类别过滤：默认按当前武器的 wepType（常规看 normalWepTypes、深夜看 deepWepTypes），已选的始终显示", () => {
  const katana = corpse.weapon.wepType;
  const rows = R.weaponAffixRows(cfgIndex, corpse, R.emptyConfig(), katana);
  assert.ok(rows.length > 0);
  rows.forEach((row) => assert.ok(row.affix.normalWepTypes.indexOf(katana) !== -1, row.affix.id + " 不能出现在刀上"));
  const all = R.weaponAffixRows(cfgIndex, corpse, R.emptyConfig(), null);
  assert.ok(all.length >= rows.length);
  const foreign = cfgIndex.weaponAffixes.find((affix) => R.weaponAffixAvailable(affix, "normal") &&
    affix.normalWepTypes.indexOf(katana) === -1);
  assert.ok(foreign, "应当有刀上出不来的词条");
  const picked = R.weaponAffixRows(cfgIndex, corpse, withAffixes([foreign.id]), katana);
  assert.ok(picked.some((row) => row.affix.id === foreign.id && row.count === 1), "已选的不被类别过滤藏起来");
  // 行按有效倍率降序。
  rows.forEach((row, i) => { if (i) assert.ok(rows[i - 1].score >= row.score); });
});

test("武器类别过滤：按 normalWepTypes / deepWepTypes 过滤与按 scope.rollableWeaponTypes 过滤结果一致", () => {
  // 任务口径写的是 scope.rollableWeaponTypes（常规 ∪ 深夜）；页面按模式分开取，是为了常规模式不出现
  // 只在深夜才能出的类别。对栏里列出的每条词条，两种口径的类别集合必须相同，数据一变这里就会红。
  const byId = {};
  buffs.buffs.forEach((buff) => { byId[buff.spEffectId] = buff; });
  cfgIndex.weaponAffixes.forEach((affix) => {
    const rollable = new Set();
    affix.entries.forEach((entry) => ((byId[entry.id].scope || {}).rollableWeaponTypes || []).forEach((type) => rollable.add(type)));
    const union = new Set(affix.normalWepTypes.concat(affix.deepWepTypes));
    assert.deepEqual([...rollable].sort((a, b) => a - b), [...union].sort((a, b) => a - b), affix.id + " 的可出现类别");
    if (R.weaponAffixAvailable(affix, "normal")) {
      assert.deepEqual(affix.normalWepTypes.slice().sort((a, b) => a - b), [...union].sort((a, b) => a - b),
        affix.id + " 常规可出的词条，常规与深夜的类别应当相同");
    }
  });
});

// ------------------------------------------------------------------ exclusiveKey 去重

test("同一词条放两份：互斥键相同只计一份，汇总给出提示", () => {
  const skillAttack = cfgIndex.weaponAffixById[8350002];
  assert.ok(skillAttack, "提升战技攻击力（档位3）");
  const single = R.evaluateConfig(cfgIndex, corpse, withAffixes([8350002]), Core);
  const twice = R.evaluateConfig(cfgIndex, corpse, withAffixes([8350002, 8350002]), Core);
  close(twice.total.multiplier, single.total.multiplier, "两份与一份总倍率相同");
  assert.equal(twice.items.filter((item) => item.state === "duplicate").length, 1);
  assert.ok(twice.warnings.some((warning) => warning.kind === "duplicate" && warning.text.indexOf(skillAttack.entries[0].key) !== -1));
  assert.equal(R.weaponAffixUsage(cfgIndex, withAffixes([8350002, 8350002])).used, 2, "多份照样占槽位");
});

test("不同档位（档位1/2/3）是不同互斥键：各自计入相乘，并标注「参数推断，未实测」", () => {
  const result = R.evaluateConfig(cfgIndex, corpse, withAffixes([8350000, 8350001, 8350002]), Core);
  assert.equal(result.counted.length, 3);
  const product = result.counted.reduce((acc, item) => acc * item.multiplier, 1);
  close(result.total.multiplier, product, "都是全属性同倍率时总倍率等于三条连乘");
  assert.ok(result.warnings.some((warning) => warning.kind === "tiers" && warning.text.indexOf("未实测") !== -1));
});

test("跨栏同键：遗物与武器词条共用一个互斥键时只留倍率高的那份", () => {
  // 累积阶梯的各档（米莉森的义手、带翼剑徽章、连续攻击遗物…）共用 sp120。
  const config = R.emptyConfig();
  config.accessories = [1250, 2080];
  const result = R.evaluateConfig(cfgIndex, corpse, config, Core);
  const counted = result.counted.filter((item) => item.entry.key === "sp120");
  assert.equal(counted.length, 1, "两个护符的累积阶梯同键，只计一份");
  const dup = result.items.filter((item) => item.entry.key === "sp120" && item.state === "duplicate");
  assert.equal(dup.length, 1);
  assert.ok(counted[0].multiplier >= dup[0].multiplier);
});

// ------------------------------------------------------------------ 遗物合法性

test("自组普通遗物：一组合法示例走 Core.check（currentNormal）", () => {
  const card = customCard([7001402, 7260400, 7120100]);
  const check = R.checkCustomRelic(card, "normal", cfgIndex.catalog, Core);
  const direct = Core.check(Core.canonicalOrder([7001402, 7260400, 7120100].map((id) => affixById.get(id))), "currentNormal");
  assert.equal(direct.status, "valid");
  assert.equal(check.status, "valid");
  assert.equal(check.message, direct.message, "文案沿用 Core.check");
  assert.equal(check.issues.length, 0);
});

test("自组普通遗物：一组非法示例（同一互斥池）沿用 Core.check 的问题文案，整件不计入", () => {
  const card = customCard([7001400, 7001600]);
  const check = R.checkCustomRelic(card, "normal", cfgIndex.catalog, Core);
  assert.equal(check.status, "invalid");
  const conflict = check.issues.find((issue) => issue.kind === "conflict");
  assert.ok(conflict, "应当报互斥");
  assert.equal(conflict.title, "同一互斥池");
  assert.ok(conflict.detail.indexOf("提升物理攻击力") !== -1 && conflict.detail.indexOf("不能同时出现") !== -1);
  const config = R.emptyConfig();
  config.relics[0] = card;
  const result = R.evaluateConfig(cfgIndex, corpse, config, Core);
  const relicItems = result.items.filter((item) => item.column === "relic");
  assert.ok(relicItems.length > 0);
  relicItems.forEach((item) => assert.equal(item.state, "relicInvalid"));
  assert.equal(result.byColumn.relic.count, 0);
});

test("自组遗物：不足三条时用占位词条补足预检；词条重复与不在出货池同样按 Core 报错", () => {
  const partial = R.checkCustomRelic(customCard([7001402]), "normal", cfgIndex.catalog, Core);
  assert.equal(partial.status, "partial");
  assert.ok(partial.message.indexOf("1") !== -1);
  const dup = R.checkCustomRelic(customCard([7001402, 7001402]), "normal", cfgIndex.catalog, Core);
  assert.equal(dup.status, "invalid");
  assert.ok(dup.issues.some((issue) => issue.kind === "duplicate" && issue.title === "词条重复"));
  const fixedOnly = R.checkCustomRelic(customCard([7006700]), "normal", cfgIndex.catalog, Core);
  assert.equal(fixedOnly.status, "invalid", "只出现在固定遗物上的词条不能自组");
  assert.ok(fixedOnly.issues.some((issue) => issue.kind === "unavailable"));
  assert.ok(fixedOnly.issues.every((issue) => (issue.effectIds || []).every((id) => id > 0)), "占位词条不出现在问题的词条 ID 里");
  const unknown = R.checkCustomRelic(customCard([123456789]), "normal", cfgIndex.catalog, Core);
  assert.equal(unknown.status, "invalid");
  assert.equal(unknown.issues[0].title, R.TEXT.relicUnknownEffectTitle);
  assert.equal(R.checkCustomRelic(R.emptyRelicCard(), "normal", cfgIndex.catalog, Core).status, "empty");
});

test("自组深夜遗物：requiresCurse 的词条必须配诅咒；诅咒不计增伤但要占位", () => {
  const needsCurse = cfgIndex.relicCandidates.deep.find((candidate) => candidate.affix.requiresCurse);
  const free = cfgIndex.relicCandidates.deep.find((candidate) => !candidate.affix.requiresCurse &&
    candidate.affix.compatibilityId !== needsCurse.affix.compatibilityId);
  assert.ok(needsCurse && free);
  const missing = R.checkCustomRelic(customCard([needsCurse.id]), "deep", cfgIndex.catalog, Core);
  assert.equal(missing.status, "invalid");
  const issue = missing.issues.find((one) => one.kind === "curseMissing");
  assert.equal(issue.title, "需诅咒的词条缺少负面词条");
  assert.equal(issue.detail, "第 1 行的正面词条需要配对负面词条：" + needsCurse.affix.name);

  const assigned = R.autoAssignCurses(customCard([needsCurse.id, free.id]), "deep", cfgIndex.catalog, Core);
  assert.ok(assigned.curseIds[0] != null, "自动配上第一条合法诅咒");
  assert.equal(assigned.curseIds[1], null, "不需诅咒的那行不配");
  const ok = R.checkCustomRelic(assigned, "deep", cfgIndex.catalog, Core);
  assert.notEqual(ok.status, "invalid");
  // Core 的「深夜模式仅作预检，仍需校验负面词条配对」在本页已经做完配对后不再照抄，换成「诅咒配对已校验」。
  assert.equal(ok.warnings.some((warning) => warning.kind === "cursePairing"), false);
  const pairing = ok.warnings.find((warning) => warning.kind === "cursePairingChecked");
  assert.ok(pairing && pairing.title === R.TEXT.relicCursePairingTitle);
  assert.ok(pairing.detail.indexOf(String(cfgIndex.catalog.cursePoolId)) !== -1);
  assert.equal(missing.warnings.some((warning) => warning.kind === "cursePairing" || warning.kind === "cursePairingChecked"), false,
    "配对没过时既不照抄预检提示，也不说已校验");

  const extra = R.checkCustomRelic(customCard([free.id], [assigned.curseIds[0]]), "deep", cfgIndex.catalog, Core);
  assert.ok(extra.issues.some((one) => one.kind === "curseUnexpected" && one.title === "多余的负面词条"));
  const notCurse = R.checkCustomRelic(customCard([needsCurse.id], [free.id]), "deep", cfgIndex.catalog, Core);
  assert.ok(notCurse.issues.some((one) => one.kind === "curseMismatch"), "正面词条当诅咒用要报「不在诅咒池」");

  // 诅咒本身不计增伤：配置里只算正面词条的条目。
  const config = R.emptyConfig();
  config.runMode = "deep";
  config.relics[3] = assigned;
  const result = R.evaluateConfig(cfgIndex, lightning, config, Core);
  const relicIds = new Set(result.items.filter((item) => item.column === "relic").map((item) => item.entry.id));
  const curseAffix = affixById.get(assigned.curseIds[0]);
  (cfgIndex.relicAffixEntries.get(curseAffix.effectId) || []).forEach((entry) => {
    assert.equal(relicIds.has(entry.id), false, "诅咒的效果不进增伤");
  });
});

test("深夜遗物格只在深夜模式计入；普通格用普通口径、深夜格用深夜口径", () => {
  const config = R.emptyConfig();
  config.relics[3] = customCard([7001402]);
  const normal = R.evaluateConfig(cfgIndex, corpse, config, Core);
  assert.equal(normal.caps.relics, rules.modes.normal.relicSlots);
  assert.equal(normal.items.filter((item) => item.column === "relic").length, 0, "常规模式没有第 4 格");
  config.runMode = "deep";
  const deep = R.evaluateConfig(cfgIndex, corpse, config, Core);
  assert.equal(deep.caps.relics, rules.modes.deep.relicSlots);
  assert.equal(R.relicKindForCard(deep.caps, 3), "deep");
  assert.equal(R.relicKindForCard(deep.caps, 2), "normal");
  assert.ok(deep.relicChecks[3].status !== "empty");
});

test("固定遗物：整件的词条按 spEffectIds 计入；条件型默认未确认，勾选「条件成立」后计入", () => {
  const relic = cfgIndex.fixedRelics.find((one) => one.key === "2070");
  assert.ok(relic, "安定者的遗志（提升近战攻击力 + 提升战技攻击力）");
  const config = R.emptyConfig();
  config.relics[0] = { type: "fixed", key: "2070", affixIds: [null, null, null], curseIds: [null, null, null] };
  const result = R.evaluateConfig(cfgIndex, corpse, config, Core);
  const ids = result.counted.filter((item) => item.column === "relic").map((item) => item.entry.id).sort();
  assert.deepEqual(ids, relic.entries.filter((entry) => entry.countsAsDamage).map((entry) => entry.id).sort());

  const conditionalRelic = cfgIndex.fixedRelics.find((one) => one.entries.some((entry) =>
    entry.countsAsDamage && entry.activation !== "passive" && !entry.stackInput &&
    entry.appliesTo && entry.appliesTo.skill === "yes"));
  assert.ok(conditionalRelic);
  const entry = conditionalRelic.entries.find((one) => one.countsAsDamage && one.activation !== "passive" &&
    !one.stackInput && one.appliesTo.skill === "yes");
  const cfg2 = R.emptyConfig();
  cfg2.relics[0] = { type: "fixed", key: conditionalRelic.key, affixIds: [null, null, null], curseIds: [null, null, null] };
  const before = R.evaluateConfig(cfgIndex, corpse, cfg2, Core).items.find((item) => item.entry.id === entry.id);
  assert.equal(before.state, "pending");
  cfg2.ticks[entry.id] = true;
  const after = R.evaluateConfig(cfgIndex, corpse, cfg2, Core).items.find((item) => item.entry.id === entry.id);
  assert.ok(after.state === "counted" || after.state === "duplicate");
});

// ------------------------------------------------------------------ appliesTo 分流

test("appliesTo 分流：魔法 / 祷告排除「提升战技攻击力」类（112），战技照样吃", () => {
  [8350000, 8350001, 8350002, 7006700, 312300].forEach((id) => {
    const entry = index.byId[id];
    assert.equal(R.appliesVerdict(entry, comet).state, "no", id + " 对魔法不生效");
    assert.equal(R.appliesVerdict(entry, lightning).state, "no", id + " 对祷告不生效");
    assert.equal(R.appliesVerdict(entry, corpse).state, "yes", id + " 对尸横遍野（全段带 112）生效");
  });
});

test("appliesTo 分流：数据判 magParamChange=0 的条目对魔法一律不生效，wepParamChange=3 的对战技不生效", () => {
  let magZero = 0;
  index.entries.forEach((entry) => {
    const detail = entry.appliesToDetail.sorcery;
    if (!detail || !/^magParamChange=0/.test(detail.reason || "")) return;
    magZero += 1;
    assert.equal(R.appliesVerdict(entry, comet).state, "no", entry.id + " magParamChange=0 却对魔法生效");
  });
  assert.ok(magZero > 0);
  const sorceryBoost = index.byId[8330000];   // 强化魔法（武器词条）
  assert.equal(R.appliesVerdict(sorceryBoost, corpse).state, "no");
  assert.equal(R.appliesVerdict(sorceryBoost, comet).state, "yes");
});

test("appliesTo 分流：战技的子类别限定按 attackIndex 对所选战技判定（咆哮类没有 112 段就不吃）", () => {
  const roarEntry = Object.keys(buffs.attackIndex.skills).find((id) => {
    const sets = buffs.attackIndex.skills[id].subCategorySets;
    return sets.every((set) => set.subs.indexOf(112) === -1 && set.subs.indexOf(111) === -1);
  });
  assert.ok(roarEntry, "应当有不带 112 的战技（野蛮咆哮等）");
  const roar = R.makeOutput({ mode: "skill", meansId: Number(roarEntry), weapon: null, hand: 1,
    shares: corpse.shares, contexts: {} }, buffs);
  assert.equal(R.appliesVerdict(index.byId[8350000], roar).state, "no");
  const partialId = Object.keys(buffs.attackIndex.skills).find((id) => {
    const sets = buffs.attackIndex.skills[id].subCategorySets;
    return sets.some((set) => set.subs.indexOf(112) !== -1) && sets.some((set) => set.subs.indexOf(112) === -1 && set.subs.indexOf(111) === -1);
  });
  assert.ok(partialId, "应当有部分段带 112 的战技");
  const partial = R.appliesVerdict(index.byId[8350000], R.makeOutput({ mode: "skill", meansId: Number(partialId),
    weapon: null, hand: 1, shares: corpse.shares, contexts: {} }, buffs));
  assert.equal(partial.state, "yes");
  assert.ok(partial.weight > 0 && partial.weight < 1, "部分段命中按段数加权");
});

test("appliesTo 分流：持武器的手、出手武器类别、攻击情境各走各的判定", () => {
  const rightOnly = index.byId[8980002];       // 提升魔力属性攻击力（右手武器・武器固有）
  assert.equal(R.appliesVerdict(rightOnly, corpse).state, "yes");
  assert.equal(R.appliesVerdict(rightOnly, outputFor("skill", 1177, 9040000, { hand: 2 })).state, "no");
  const daggerOnly = index.byId[8160000];      // 提升短剑的攻击力
  assert.equal(R.appliesVerdict(daggerOnly, corpse).state, "no", "刀不是短剑");
  const daggerSkill = skills.skills.find((skill) => (skill.weaponIds || []).some((id) =>
    skills._weaponById[id] && skills._weaponById[id].wepType === 1 && typeof skills._weaponById[id].skillVariant === "number" &&
    R.selectHits(skill, skills._weaponById[id]).some((hit) => !hit.noDamage)));
  const daggerWeapon = daggerSkill.weaponIds.map((id) => skills._weaponById[id]).find((weapon) => weapon && weapon.wepType === 1 && typeof weapon.skillVariant === "number");
  assert.equal(R.appliesVerdict(daggerOnly, outputFor("skill", daggerSkill.id, daggerWeapon.id)).state, "yes");
  const counter = index.byId[320600];          // 矛护符：强化突刺反击
  assert.equal(R.appliesVerdict(counter, corpse).state, "context");
  assert.equal(R.appliesVerdict(counter, outputFor("skill", 1177, 9040000, { contexts: { thrustingCounter: true } })).state, "yes");
});

test("配置里所有计入的条目：appliesTo 对当前输出类别不是 no", () => {
  [corpse, lion, comet, lightning].forEach((output) => {
    ["normal", "deep"].forEach((runMode) => {
      const base = R.emptyConfig();
      base.runMode = runMode;
      const filled = R.recommendFill(cfgIndex, output, base, Core, R.outputWepType(output)).config;
      R.evaluateConfig(cfgIndex, output, filled, Core).counted.forEach((item) => {
        assert.notEqual(item.entry.appliesTo[output.mode], "no", item.entry.id + " 对 " + output.mode + " 不生效却计入了");
      });
    });
  });
});

// ------------------------------------------------------------------ 叠层输入

test("叠层：封印监牢（ladder）按层数取 tierMultipliers，赐福王的余威（copies）按份数取乘方", () => {
  const evergaol = index.byId[7069001];
  const grace = index.byId[8970000];
  const config = R.emptyConfig();
  config.others[8970000] = true;
  config.stacks[8970000] = 4;
  const result = R.evaluateConfig(cfgIndex, corpse, config, Core);
  const graceItem = result.items.find((item) => item.entry.id === 8970000);
  assert.equal(graceItem.state, "counted", "填了层数就等于条件成立");
  close(graceItem.table.fire, Math.pow(grace.stackInput.perStackMultiplier, 4), "4 份");

  const env = { plan: index.plan, out: corpse, config: R.emptyConfig(), ladders: cfgIndex.ladders };
  env.config.stacks[7069001] = 5;
  const ladderItem = R.evaluateEntry(evergaol, env, { explicit: false });
  close(ladderItem.table.slash, evergaol.stackInput.tierMultipliers[4], "第 5 层");
  env.config.stacks[7069001] = 0;
  assert.equal(R.evaluateEntry(evergaol, env, { explicit: true }).state, "zeroStacks");
});

test("叠层：不同存档阶梯（sp204 不同优先度）可同时计入并相乘，汇总给出未实测提示", () => {
  const relicWith = (spId) => cfgIndex.relicCandidates.normal.find((candidate) =>
    candidate.entries.some((entry) => entry.id === spId));
  const evergaol = relicWith(7069001);
  const invader = relicWith(7069201);
  assert.ok(evergaol && invader, "两条阶梯都能自组进普通遗物");
  const config = R.emptyConfig();
  config.relics[0] = customCard([evergaol.id]);
  config.relics[1] = customCard([invader.id]);
  const result = R.evaluateConfig(cfgIndex, corpse, config, Core);
  const counted = result.counted.filter((item) => /^sp204@p/.test(item.entry.key));
  assert.equal(counted.length, 2, "exclusiveKey 不同，两条都计入");
  assert.ok(result.warnings.some((warning) => warning.kind === "ladder204"));
});

// ------------------------------------------------------------------ 汇总连乘

test("汇总：总倍率 = Σ 占比 × 各类型上全部计入条目的倍率连乘；各栏小计只取本栏", () => {
  const config = R.recommendFill(cfgIndex, lion, R.emptyConfig(), Core, lion.weapon.wepType).config;
  config.others[3558] = true;
  const result = R.evaluateConfig(cfgIndex, lion, config, Core);
  const perType = {};
  R.TYPE_KEYS.forEach((type) => { perType[type] = 1; });
  result.counted.forEach((item) => R.TYPE_KEYS.forEach((type) => { perType[type] *= item.table[type]; }));
  const expected = R.TYPE_KEYS.reduce((sum, type) => sum + lion.shares[type] * perType[type], 0);
  close(result.total.multiplier, expected, "总倍率");
  R.COLUMN_ORDER.forEach((column) => {
    const own = {};
    R.TYPE_KEYS.forEach((type) => { own[type] = 1; });
    const items = result.counted.filter((item) => item.column === column);
    items.forEach((item) => R.TYPE_KEYS.forEach((type) => { own[type] *= item.table[type]; }));
    close(result.byColumn[column].multiplier, R.TYPE_KEYS.reduce((sum, type) => sum + lion.shares[type] * own[type], 0), column + " 小计");
    assert.equal(result.byColumn[column].count, items.length);
  });
  assert.ok(result.total.multiplier > 1);
});

test("汇总：纯物理倍率对纯魔力法术等于 ×1；攻击力加算只展示、不进连乘", () => {
  const config = R.emptyConfig();
  config.relics[0] = customCard([7001402]);
  const result = R.evaluateConfig(cfgIndex, comet, config, Core);
  close(result.total.multiplier, 1, "物理 +6% 对帚星（纯魔力）没有收益");
  const flatOnly = cfgIndex.relicCandidates.normal.find((candidate) => candidate.entries.every((entry) => !entry.hasMultiplier && entry.hasFlat));
  if (flatOnly) {
    const cfg = R.emptyConfig();
    cfg.relics[0] = customCard([flatOnly.id]);
    cfg.ticks = {};
    const flat = R.evaluateConfig(cfgIndex, corpse, cfg, Core);
    close(flat.total.multiplier, 1, "只有加算的条目不改变总倍率");
  }
});

test("汇总：没有构成时算不出倍率，推荐填满什么都不做", () => {
  const empty = R.makeOutput({ mode: "skill", meansId: 1177, weapon: corpse.weapon, hand: 1, shares: null, contexts: {} }, buffs);
  const result = R.evaluateConfig(cfgIndex, empty, withAffixes([8350002]), Core);
  assert.equal(result.total.multiplier, null);
  const fill = R.recommendFill(cfgIndex, empty, R.emptyConfig(), Core, null);
  assert.equal(fill.added.length, 0);
});

// ------------------------------------------------------------------ 推荐填满

test("推荐填满：不越界（武器词条总数 / 深夜专属 / 遗物格 / 护符格），自组遗物全部合法或预检通过", () => {
  [corpse, lion, comet, lightning].forEach((output) => {
    ["normal", "deep"].forEach((runMode) => {
      [R.outputWepType(output), null].forEach((filterType) => {
        const base = R.emptyConfig();
        base.runMode = runMode;
        const fill = R.recommendFill(cfgIndex, output, base, Core, filterType);
        const result = R.evaluateConfig(cfgIndex, output, fill.config, Core);
        const label = output.mode + "/" + output.meansId + "/" + runMode + "/" + filterType;
        const wa = result.slots.weaponAffix;
        assert.ok(wa.used <= wa.cap, label + " 武器词条越界");
        assert.ok(wa.deepOnlyUsed <= wa.deepOnlyCap, label + " 深夜专属越界");
        assert.ok(result.slots.relic.used <= result.slots.relic.cap, label + " 遗物越界");
        assert.ok(result.slots.accessory.used <= result.slots.accessory.cap, label + " 护符越界");
        result.relicChecks.forEach((check, i) => {
          assert.notEqual(check.status, "invalid", label + " 第 " + (i + 1) + " 格遗物不合法：" + JSON.stringify(check.issues));
        });
        const keys = result.counted.map((item) => item.entry.key);
        assert.equal(new Set(keys).size, keys.length, label + " 同一互斥键出现了两次");
        assert.equal(result.items.filter((item) => item.state === "duplicate").length, 0, label + " 推荐不该挑出重复的键");
        if (filterType != null) {
          fill.config.weaponAffixes.forEach((one) => {
            assert.ok(R.weaponAffixMatchesType(cfgIndex.weaponAffixById[one.id], runMode, filterType), label + " 越过了类别过滤");
          });
        }
        assert.ok(fill.added.length > 0, label + " 应当填进东西");
        assert.ok(result.total.multiplier >= 1, label);
      });
    });
  });
});

test("推荐填满：只挑被动、自动判定生效、无需确认、不需要层数的条目；只填空槽、重复点击不再加东西", () => {
  const fill = R.recommendFill(cfgIndex, corpse, R.emptyConfig(), Core, corpse.weapon.wepType);
  const result = R.evaluateConfig(cfgIndex, corpse, fill.config, Core);
  result.counted.forEach((item) => {
    assert.equal(item.entry.activation, "passive", item.entry.id + " 不是被动");
    assert.equal(item.needs.length, 0, item.entry.id + " 需要确认");
    assert.equal(item.entry.stackInput, null);
  });
  const again = R.recommendFill(cfgIndex, corpse, fill.config, Core, corpse.weapon.wepType);
  assert.equal(again.added.length, 0, "已经填满，再点不该有变化");
  assert.deepEqual(again.config, fill.config);

  // 已选的不动：先放一件固定遗物与一个护符，再填。
  const seeded = R.emptyConfig();
  seeded.relics[1] = { type: "fixed", key: "2070", affixIds: [null, null, null], curseIds: [null, null, null] };
  seeded.accessories[0] = 2020;
  const kept = R.recommendFill(cfgIndex, corpse, seeded, Core, corpse.weapon.wepType).config;
  assert.equal(kept.relics[1].key, "2070");
  assert.equal(kept.accessories[0], 2020);
  assert.ok(kept.relics[0].type !== "empty" || kept.relics[2].type !== "empty");
});

test("推荐填满：同一件固定遗物不会放进两格，同一护符不会装两个", () => {
  [corpse, lion].forEach((output) => {
    const config = R.recommendFill(cfgIndex, output, R.emptyConfig(), Core, null).config;
    const fixedKeys = config.relics.filter((card) => card.type === "fixed").map((card) => card.key);
    assert.equal(new Set(fixedKeys).size, fixedKeys.length);
    const talismans = config.accessories.filter((id) => id != null);
    assert.equal(new Set(talismans).size, talismans.length);
  });
});

// ------------------------------------------------------------------ 其它栏

test("当前武器的固有效果自动列入（可排除）但不算亲手放入：条件型默认未确认，换一把武器就没有", () => {
  const innateEntry = index.entries.find((entry) => entry.innate && entry.countsAsDamage &&
    (entry.innate.weaponIds || []).length && entry.appliesTo.skill !== "no");
  assert.ok(innateEntry);
  const weaponId = innateEntry.innate.weaponIds[0];
  const weapon = skills._weaponById[weaponId];
  assert.ok(weapon && typeof weapon.skillVariant === "number");
  const skill = skills._skillById[weapon.swordArtsParamId];
  const output = outputFor("skill", skill.id, weapon.id);
  const auto = R.currentInnateEntries(cfgIndex, output);
  assert.ok(auto.indexOf(innateEntry) !== -1);
  const result = R.evaluateConfig(cfgIndex, output, R.emptyConfig(), Core);
  const item = result.items.find((one) => one.entry.id === innateEntry.id);
  assert.ok(item && item.auto && item.explicit === false, "当前武器固有：自动列入，但不算用户亲手放入");
  if (innateEntry.activation !== "passive") {
    assert.equal(item.state, "pending", "条件型固有效果默认不计入（notes.ranking ③）");
    const ticked = R.emptyConfig();
    ticked.ticks[innateEntry.id] = true;
    const after = R.evaluateConfig(cfgIndex, output, ticked, Core).items.find((one) => one.entry.id === innateEntry.id);
    assert.equal(after.state, "counted", "勾选「条件成立」后计入");
  }
  const off = R.emptyConfig();
  off.innateOff[innateEntry.id] = true;
  assert.equal(R.evaluateConfig(cfgIndex, output, off, Core).items.some((one) => one.entry.id === innateEntry.id), false);
  assert.equal(R.currentInnateEntries(cfgIndex, corpse).indexOf(innateEntry), -1);
  assert.deepEqual(R.currentInnateEntries(cfgIndex, comet), [], "法术没有武器");
});

// ------------------------------------------------------------------ 复核回归：多档词条 / 减益 / 固有效果

const mohg = (() => {
  const skill = skills.skills.find((one) => one.nameZh === "授血仪式");
  const weapon = skills.weapons.find((one) => one.nameZh === "蒙格温圣矛");
  assert.ok(skill && weapon, "授血仪式 + 蒙格温圣矛");
  return outputFor("skill", skill.id, weapon.id);
})();

test("回归：蒙格温圣矛的条件型固有效果不会在空配置里自动计入（空配置 ×1），勾选后才计入", () => {
  const empty = R.evaluateConfig(cfgIndex, mohg, R.emptyConfig(), Core);
  close(empty.total.multiplier, 1, "空配置不该有增伤");
  const bleed = empty.items.find((item) => item.entry.id === 8981903);
  assert.ok(bleed && bleed.auto, "周围陷入出血时提升攻击力：当前武器固有，自动列入");
  assert.equal(bleed.state, "pending");
  const ticked = R.emptyConfig();
  ticked.ticks[8981903] = true;
  const on = R.evaluateConfig(cfgIndex, mohg, ticked, Core);
  const item = on.items.find((one) => one.entry.id === 8981903);
  assert.equal(item.state, "counted");
  close(on.total.multiplier, item.multiplier, "勾选后总倍率等于这一条");
  // 其它栏的这一行：状态按「未亲手放入」显示（条件未确认），分数仍是确认后能拿到的。
  const row = R.otherRowsFor(cfgIndex, mohg, R.emptyConfig(), "weaponInnate").find((one) => one.key === 8981903);
  assert.ok(row && row.auto && row.selected);
  assert.equal(row.state, "pending");
  close(row.score, item.multiplier, "行分数＝确认后的倍率");
  // 叠层类固有效果（玛雷家的庇佑 / 复仇的庇佑）自动列入时默认 0 层。
  [8988200, 8998000].forEach((id) => {
    const entry = index.byId[id];
    assert.ok(entry.stackInput && entry.innate);
    assert.equal(R.stacksFor(entry, R.emptyConfig(), false), 0);
  });
  const stackWeapon = skills._weaponById[index.byId[8988200].innate.weaponIds[0]];
  if (stackWeapon && typeof stackWeapon.skillVariant === "number" && skills._skillById[stackWeapon.swordArtsParamId]) {
    const output = outputFor("skill", stackWeapon.swordArtsParamId, stackWeapon.id);
    const stackItem = R.evaluateConfig(cfgIndex, output, R.emptyConfig(), Core).items.find((one) => one.entry.id === 8988200);
    assert.ok(stackItem && stackItem.state !== "counted", "叠层固有效果默认 0 层、不计入");
  }
});

test("回归：一件自组遗物只带「附加异常状态出血」(7120600)，总倍率不因它下降（×0.85⁴ 不再出现）", () => {
  const ticked = R.emptyConfig();
  ticked.ticks[8981903] = true;
  const base = R.evaluateConfig(cfgIndex, mohg, ticked, Core).total.multiplier;
  [7120400, 7120500, 7120600].forEach((affixId) => {
    const config = R.cloneConfig(ticked);
    config.relics[0] = customCard([affixId]);
    const result = R.evaluateConfig(cfgIndex, mohg, config, Core);
    assert.notEqual(result.relicChecks[0].status, "invalid");
    assert.ok(result.total.multiplier >= 0.85, affixId + " 让总倍率掉到 " + result.total.multiplier);
    close(result.total.multiplier, base, affixId + " 的 ×0.85 是减益（direction=decrease），不进增伤");
    const own = result.items.filter((item) => item.column === "relic" && item.entry.countsAsDamage);
    assert.equal(own.filter((item) => item.state === "variantOff").length, 3, "四档只留一档");
    const chosen = own.filter((item) => item.state !== "variantOff");
    assert.equal(chosen.length, 1);
    assert.equal(chosen[0].state, "no");
    assert.equal(chosen[0].reasons[0], R.TEXT.reasonDecrease);
    assert.equal(result.warnings.some((warning) => warning.kind === "tiers"), false, "不再提示「不同档位同时计入」");
  });
  // 自组下拉里这条词条也不再显示 ×0.522。
  const row = R.relicAffixRows(cfgIndex, mohg, ticked, "normal").find((one) => one.id === 7120600);
  assert.ok(row);
  close(row.score, 1, "下拉里的分数");
  assert.equal(row.state, "no");
});

test("回归：「附加魔力属性攻击力」四档只算选中的一档，加算不再四档相加", () => {
  const members = index.variants["affix#7120000"];
  const config = R.emptyConfig();
  config.relics[0] = customCard([7120000]);
  const result = R.evaluateConfig(cfgIndex, mohg, config, Core);
  const own = result.items.filter((item) => item.column === "relic" && item.entry.variantGroup === "affix#7120000");
  assert.equal(own.length, 4);
  const counted = own.filter((item) => item.state === "counted");
  assert.equal(counted.length, 1);
  assert.equal(counted[0].entry.id, members[0].id, "默认第 1 档");
  close(result.total.flat, counted[0].flat, "汇总的加算只有一档");
  close(result.total.multiplier, 1, "加算不进连乘");
  config.variants["affix#7120000"] = members[3].id;
  const fourth = R.evaluateConfig(cfgIndex, mohg, config, Core);
  assert.deepEqual(fourth.counted.filter((item) => item.column === "relic").map((item) => item.entry.id), [members[3].id]);
  // 同一词条放在两件遗物上：键已合并，只计一份。
  const twice = R.cloneConfig(config);
  twice.relics[1] = customCard([7120000]);
  const both = R.evaluateConfig(cfgIndex, mohg, twice, Core);
  assert.equal(both.counted.filter((item) => item.entry.key === "affix#7120000").length, 1);
  // 固定遗物整件带进来的多档同样只留一档（且条件型默认未确认）。
  const water = cfgIndex.fixedRelics.find((relic) => relic.entries.some((entry) => entry.id === 7120001));
  assert.ok(water, "细腻的水滴情景带 7120001–04");
  const fixed = R.emptyConfig();
  fixed.relics[0] = { type: "fixed", key: water.key, affixIds: [null, null, null], curseIds: [null, null, null] };
  const fixedResult = R.evaluateConfig(cfgIndex, mohg, fixed, Core);
  const fixedOwn = fixedResult.items.filter((item) => item.entry.variantGroup === "affix#7120000");
  assert.equal(fixedOwn.filter((item) => item.state !== "variantOff").length, 1);
});

test("回归：深夜遗物「【无赖】技艺命中敌人时，能降低对方的攻击力」(6500400 → 7500401) 不再按 ×0.87 计入", () => {
  const config = R.emptyConfig();
  config.runMode = "deep";
  config.relics[3] = R.autoAssignCurses(customCard([6500400]), "deep", cfgIndex.catalog, Core);
  const result = R.evaluateConfig(cfgIndex, corpse, config, Core);
  assert.notEqual(result.relicChecks[3].status, "invalid");
  const item = result.items.find((one) => one.entry.id === 7500401);
  assert.ok(item);
  assert.equal(item.state, "no");
  assert.equal(item.reasons[0], R.TEXT.reasonDecrease);
  close(result.total.multiplier, 1);
  const row = R.relicAffixRows(cfgIndex, corpse, config, "deep").find((one) => one.id === 6500400);
  assert.ok(!row || row.state === "no", "自组下拉里显示为不生效");
});

test("其它栏：勾选即视为条件成立；累积阶梯一行、只算选中的那层", () => {
  const config = R.emptyConfig();
  config.others[3558] = true;
  const result = R.evaluateConfig(cfgIndex, corpse, config, Core);
  const ladder = result.items.filter((item) => item.entry.ladderGroup === 3558);
  assert.ok(ladder.length >= 2);
  assert.equal(ladder.filter((item) => item.state === "counted").length, 1);
  assert.equal(ladder.filter((item) => item.state === "tierOff").length, ladder.length - 1);
  const rows = R.otherRowsFor(cfgIndex, corpse, config, "consumable");
  const row = rows.find((one) => one.key === 3558);
  assert.equal(row.selected, true);
  rows.forEach((one, i) => { if (i) assert.ok(rows[i - 1].score >= one.score); });
});

test("护符与遗物候选行：按有效倍率降序，状态取「最接近生效」的那一条", () => {
  const talismans = R.talismanRows(cfgIndex, comet, R.emptyConfig());
  talismans.forEach((row, i) => { if (i) assert.ok(talismans[i - 1].score >= row.score); });
  const sorceryTalisman = talismans.find((row) => row.id === 3000);   // 魔法师球护符
  assert.ok(sorceryTalisman && sorceryTalisman.state === "counted" && sorceryTalisman.score > 1);
  const fixed = R.fixedRelicRows(cfgIndex, corpse, R.emptyConfig(), "normal");
  assert.equal(fixed.length, cfgIndex.fixedRelics.filter((relic) => !relic.isDeepRelic).length);
  // score 按「随整件带入」口径（条件型未确认），potential 按全部确认；减益（direction=decrease）两种口径
  // 都不计入，所以 potential ≥ score。
  fixed.forEach((row) => assert.ok(row.score > 0 && row.potential >= row.score - 1e-12, row.key + " 确认条件后不该更低"));
  const withPending = fixed.find((row) => row.relic.entries.some((entry) => entry.countsAsDamage &&
    entry.activation !== "passive" && !entry.stackInput && entry.appliesTo.skill === "yes"));
  assert.ok(withPending && withPending.potential !== withPending.score, "有条件型效果的固定遗物，两种口径应当不同");
  const relicRows = R.relicAffixRows(cfgIndex, lightning, R.emptyConfig(), "deep");
  assert.ok(relicRows.length > 0);
});

test("遗物格：切成「固定遗物／自组」但还没选东西的格不算占用，推荐填满也会填它", () => {
  const config = R.emptyConfig();
  config.relics[0] = { type: "fixed", key: null, affixIds: [null, null, null], curseIds: [null, null, null] };
  config.relics[1] = customCard([]);
  assert.equal(R.relicCardFilled(config.relics[0]), false);
  assert.equal(R.relicCardFilled(config.relics[1]), false);
  assert.equal(R.relicCardFilled(customCard([7001402])), true);
  assert.equal(R.evaluateConfig(cfgIndex, corpse, config, Core).slots.relic.used, 0);
  const filled = R.recommendFill(cfgIndex, corpse, config, Core, corpse.weapon.wepType).config;
  assert.ok(R.relicCardFilled(filled.relics[0]) && R.relicCardFilled(filled.relics[1]));
});
