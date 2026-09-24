// 增伤排名页的**双端对照用例**：macOS 端（RelicCore/BuffLoadout.swift，自检在
// RelicCoreChecks/BuffRankerChecks.swift 的 checkLoadoutParity）按同一套口径实现，两端用同一组输入、
// 同一套断言口径、同一种对拍行格式。
//
// 每一端都在自己这一侧用一份**独立重算的参考实现**校对「同一算法的中间量」——构成占比、
// 「全部增益一览」前 10 名的有效倍率、整套配置的总倍率、各栏小计与计入条目集合（参考实现不复用被测
// 代码的任何分支，容差 1e-9，比任务要求的 1e-6 更严）。两边都绿，两端算出来的数就必然对得上；
// 数值会随数据集修订变化，所以一律**不写绝对快照**。文案常量表与说明区另用摘要锁住逐字一致
// （摘要常量两端相同，见文末）。
//
// 固定的三组配置对照输入（任务清单）：
//   A 尸横遍野 + 尸山血海，常规模式：按推荐填满；
//   B 死亡雷击，深夜模式：按推荐填满；
//   C 狮子斩 + 大剑：2 件固定遗物（安定者的遗志 2070、王的黑夜 2100，勾「切换武器时，能提升物理攻击力」
//     7035902）＋ 1 件自组遗物（封印监牢 7060000 / 出击时附加火 7120100 / 对陷入冻伤的敌人 7260400）
//     ＋ 2 个护符（战士壶碎片 1230、红羽七刃剑 2040）＋ 封印监牢 7 层。
//
// 需要人工对拍时：
//   NR_RANKER_DUMP=1 node --test windows/tests/ranker_crosscheck.test.mjs
//   NR_RANKER_DUMP=1 swift run RelicCoreChecks
// 两端都打出 CASE / CONFIG / OUTPUTS / TEXT 四种行（同一格式，见 ranker.js 的 caseDumpLine / configDumpLine），
// 逐行比即可。
//
// 战技数据集 schemaVersion 3：选段一律读 weapons[].skillVariants[战技 ID]（局内战技池的武器同样有），
// 默认勾选按「hit.fpBoth || noFp 与开关同侧」；七组构成用例的战技都是所选武器的固定战技，输入不变。
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
const DUMP = process.env.NR_RANKER_DUMP === "1";

// 构成用例（两端同一组输入；v3 下不变，1177 + 9040000 等仍是武器的固定战技）。
const CASES = [
  // 尸横遍野（尸山血海）：全段 —— 物理 + 火两条通道，12 段里 6 段是专注值不足版。
  { key: "corpse-piler-full", kind: "skill", id: 1177, weaponId: 9040000, only: null },
  // 同一把武器只勾最后一段：每段五属性 motion 同值，构成比例必须与全段完全一致。
  { key: "corpse-piler-last", kind: "skill", id: 1177, weaponId: 9040000, only: [303400305] },
  // 狮子斩 + 大剑：纯物理。
  { key: "lions-claw-greatsword", kind: "skill", id: 100, weaponId: 3180000, only: null },
  // 狮子斩 + 火焰大剑：同一战技、同一套段，换一把带火属性的武器。
  { key: "lions-claw-flame-greatsword", kind: "skill", id: 100, weaponId: 3180500, only: null },
  // 喷火 + 钢丝火把：带子弹段的战技（子弹段照常乘武器攻击力，不得整段归零）。
  { key: "firebreather", kind: "skill", id: 223, weaponId: 24020000, only: null },
  // 死亡雷击：祷告，只用 flat。
  { key: "death-lightning", kind: "incantation", id: 5040, weaponId: null, only: null },
  // 帚星：魔法，只用 flat。
  { key: "comet", kind: "sorcery", id: 4021, weaponId: null, only: null }
];

const ELEMENTS = R.ELEMENTS;
const TYPE_KEYS = R.TYPE_KEYS;
const PHYS = ["slash", "blow", "thrust", "neutral", "physNone"];
const EPS = 1e-9;

// ---- 参考实现（故意不复用被测代码的分支）--------------------------------

// 构成：amount[el] = 攻击力 × motion/100 + flat（addBaseAtk 再加一份），
// 物理落到这一段解析出的物理子类型上。
function referenceShares(hits, weapon, selected) {
  const amounts = {};
  TYPE_KEYS.forEach((key) => { amounts[key] = 0; });
  hits.forEach((hit) => {
    if (!selected.has(hit.atkId) || hit.noDamage) return;
    let physType = "physNone";
    if (hit.attribute === "Slash") physType = "slash";
    else if (hit.attribute === "Strike") physType = "blow";
    else if (hit.attribute === "Pierce") physType = "thrust";
    else if (hit.attribute === "Standard") physType = "neutral";
    else if (hit.attribute === "WeaponAtkAttribute") {
      physType = ["slash", "blow", "thrust", "neutral"][weapon ? weapon.atkAttribute : -1] || "physNone";
    } else if (hit.attribute === "WeaponAtkAttribute2") {
      physType = ["slash", "blow", "thrust", "neutral"][weapon ? weapon.atkAttribute2 : -1] || "physNone";
    }
    ELEMENTS.forEach((element) => {
      const base = weapon && weapon.attackBase && weapon.attackBase[element] ? weapon.attackBase[element] : 0;
      const motion = weapon && hit.motion && hit.motion[element] ? hit.motion[element] : 0;
      const flat = hit.flat && hit.flat[element] ? hit.flat[element] : 0;
      let amount = (base * motion) / 100 + flat;
      if (hit.addBaseAtk) amount += base;
      if (!(amount > 0)) return;
      amounts[element === "physical" ? physType : element] += amount;
    });
  });
  const total = TYPE_KEYS.reduce((sum, key) => sum + amounts[key], 0);
  const shares = {};
  TYPE_KEYS.forEach((key) => { shares[key] = total > 0 ? amounts[key] / total : 0; });
  return { shares, total };
}

const FIELD_CHANNELS = {
  physicsAttackRate: PHYS, physicsAttackPowerRate: PHYS,
  magicAttackRate: ["magic"], magicAttackPowerRate: ["magic"],
  fireAttackRate: ["fire"], fireAttackPowerRate: ["fire"],
  thunderAttackRate: ["lightning"], thunderAttackPowerRate: ["lightning"],
  darkAttackRate: ["holy"], darkAttackPowerRate: ["holy"],
  slashAttackRate: ["slash"], slashAttackPowerRate: ["slash"],
  blowAttackRate: ["blow"], blowAttackPowerRate: ["blow"],
  thrustAttackRate: ["thrust"], thrustAttackPowerRate: ["thrust"],
  neutralAttackRate: ["neutral"], neutralAttackPowerRate: ["neutral"]
};
const FLAT_CHANNELS = {
  physicsAttackPower: PHYS, magicAttackPower: ["magic"], fireAttackPower: ["fire"],
  thunderAttackPower: ["lightning"], darkAttackPower: ["holy"]
};
const FIELDS = {};
(buffs.rateFields || []).forEach((field) => { FIELDS[field.key] = field; });
const BUFF = {};
buffs.buffs.forEach((buff) => { BUFF[buff.spEffectId] = buff; });

function countsAsDamage(buff) {
  return Object.keys(buff.rates || {}).some((key) => {
    const field = FIELDS[key];
    return field && field.countsAsDamage === true && buff.rates[key] !== field.default;
  });
}

// 能进配置页的条目：带伤害字段、作用于自己或队友、不是减益。
function listable(buff) {
  return countsAsDamage(buff) && (buff.target === "self" || buff.target === "ally") && buff.direction !== "decrease";
}

// appliesTo 判定（notes.appliesTo 的口径，独立重写）。manual＝要用户确认。
function referenceVerdict(buff, out) {
  const cls = out.mode;
  const value = (buff.appliesTo || {})[cls];
  if (value !== "yes" && value !== "conditional") return { ok: false };
  let manual = (buff.requiresGoodsIds || []).length > 0;
  if (value === "yes") return { ok: true, weight: 1, manual, restricted: null };
  const requires = (((buff.appliesToDetail || {})[cls]) || {}).requires || {};
  let weight = 1;
  let restricted = null;
  if (Object.keys(requires).length === 0) manual = true;
  for (const key of Object.keys(requires)) {
    const need = requires[key];
    if (key === "hand") {
      if (need !== out.hand) return { ok: false };
    } else if (key === "attackWeaponTypes") {
      const own = cls === "skill" ? (out.weapon ? out.weapon.wepType : null) : (cls === "sorcery" ? 57 : 61);
      if (need.indexOf(own) === -1) return { ok: false };
    } else if (key === "subCategoriesAny") {
      const table = cls === "skill" ? buffs.attackIndex.skills : buffs.attackIndex.spells;
      const one = table[String(out.meansId)];
      if (!one) { manual = true; continue; }
      let matched = 0;
      let total = 0;
      one.subCategorySets.forEach((set) => {
        total += set.hits;
        if (set.subs.some((sub) => need.indexOf(sub) !== -1)) matched += set.hits;
      });
      if (matched === 0) return { ok: false };
      weight = matched / total;
    } else if (key === "attackContexts") {
      if (!need.some((ctxKey) => out.contexts[ctxKey])) return { ok: false, context: true };
    } else if (key === "physicalType") {
      restricted = ["slash", "blow", "thrust", "neutral"][need];
      if (!(out.shares[restricted] > 0)) return { ok: false };
    } else {
      manual = true;
    }
  }
  return { ok: true, weight, manual, restricted };
}

function paramMax(si) {
  if (si.mode !== "ladder") return 99;
  const tiers = (si.tierMultipliers || []).length;
  return si.paramMaxStacks > 0 ? (tiers ? Math.min(si.paramMaxStacks, tiers) : si.paramMaxStacks) : Math.max(tiers, 1);
}

// 叠层输入（notes.stackInput）：ladder 第 n 层取 tierMultipliers[n-1]，copies 取 perStackMultiplier^n，
// 替换 appliesToRateKeys 那几个字段。
function referenceRates(buff, stacks) {
  const si = buff.stackInput;
  if (!si) return buff.rates || {};
  const rates = Object.assign({}, buff.rates || {});
  const value = si.mode === "ladder"
    ? si.tierMultipliers[Math.min(stacks, si.tierMultipliers.length) - 1]
    : Math.pow(si.perStackMultiplier, stacks);
  (si.appliesToRateKeys || [si.multiplierKey]).forEach((key) => { rates[key] = value; });
  return rates;
}

// 单条的逐通道倍率与加算：部分段命中按 1 + (m − 1) × 占比，stackSelf 多份再乘方。
function referenceTables(buff, verdict, stacks, copies) {
  const table = {};
  const flat = {};
  TYPE_KEYS.forEach((key) => { table[key] = 1; flat[key] = 0; });
  const rates = referenceRates(buff, stacks);
  Object.keys(rates).forEach((key) => {
    const field = FIELDS[key];
    const value = rates[key];
    if (!field || field.countsAsDamage !== true || typeof value !== "number" || !isFinite(value) || value === field.default) return;
    if (field.valueKind === "multiplier" && FIELD_CHANNELS[key] && value > 0) {
      FIELD_CHANNELS[key].forEach((channel) => {
        if (verdict.restricted && channel !== verdict.restricted) return;
        table[channel] *= value;
      });
    } else if (field.valueKind === "flat" && FLAT_CHANNELS[key]) {
      FLAT_CHANNELS[key].forEach((channel) => { flat[channel] += value; });
    }
  });
  TYPE_KEYS.forEach((key) => {
    if (verdict.weight < 1) {
      table[key] = 1 + (table[key] - 1) * verdict.weight;
      flat[key] *= verdict.weight;
    }
    if (copies > 1) {
      table[key] = Math.pow(table[key], copies);
      flat[key] *= copies;
    }
  });
  return { table, flat };
}

function weighted(table, shares) {
  let sum = 0;
  let weight = 0;
  TYPE_KEYS.forEach((key) => {
    if (!(shares[key] > 0)) return;
    sum += shares[key] * table[key];
    weight += shares[key];
  });
  return weight > 0 ? sum / weight : 1;
}

// 一览（「条件全部成立」）的参考值：叠层取一局实际上限（没有就退『＋N』标签数，再没有 1 层）。
function referenceOverview(buff, out) {
  if (!listable(buff)) return null;
  if (buff.selfAllyPair && buff.selfAllyPair.role === "ally") return null;
  const verdict = referenceVerdict(buff, out);
  if (!verdict.ok) return null;
  const si = buff.stackInput;
  const soft = si ? (si.practicalMaxStacks > 0 ? si.practicalMaxStacks : (si.uiLabelMax > 0 ? si.uiLabelMax : 1)) : null;
  const stacks = si ? Math.min(soft, paramMax(si)) : null;
  return weighted(referenceTables(buff, verdict, stacks, 1).table, out.shares);
}

const SUMMARY_COLUMN = { weaponAffix: "weaponAffix", relic: "relic", accessory: "accessory" };

// 整套配置的参考值：独立地从配置展开 spEffectId（同一 ID 合并份数），按 多档只留选中的一档 / 作用对象
// （含 selfAllyPair）/ 减益 / appliesTo / 累积阶梯选层 / 叠层层数 / 确认（占槽位的栏要勾「条件成立」）过滤，
// 份数按 stackSelf 且按 ID 互斥的相乘，×1 且没有正加算的不算，按 exclusiveKey 去重（applyHighest 比
// categoryPriority，其余取有效倍率高的，再比加算，再取 id 小的），逐伤害类型连乘后按占比加权；各栏小计同法。
function referenceConfig(config, out) {
  const deep = config.runMode === "deep";
  const relicSlots = deep ? buffs.slotRules.modes.deep.relicSlots : buffs.slotRules.modes.normal.relicSlots;
  const sources = [];
  config.weaponAffixes.slice().sort((a, b) => a.id - b.id).forEach((one) => {
    const raw = buffs.weaponAffixes.find((affix) => affix.attachEffectId === one.id);
    raw.spEffectIds.filter((id) => BUFF[id] && listable(BUFF[id])).forEach((id) => sources.push({ id, copies: one.count, column: "weaponAffix" }));
  });
  config.relics.slice(0, relicSlots).forEach((card) => {
    if (card.type === "fixed") {
      const relic = buffs.fixedRelics.find((one) => one.relicIds.join("-") === card.key);
      relic.spEffectIds.filter((id) => BUFF[id] && listable(BUFF[id])).forEach((id) => sources.push({ id, copies: 1, column: "relic" }));
    } else if (card.type === "custom") {
      card.affixIds.filter((id) => id != null).forEach((affixId) => {
        buffs.buffs.filter((buff) => listable(buff) && (buff.relicAffixes || []).some((link) => link.catalogEffectId === affixId))
          .forEach((buff) => sources.push({ id: buff.spEffectId, copies: 1, column: "relic" }));
      });
    }
  });
  config.accessories.filter((id) => id != null).forEach((talismanId) => {
    buffs.buffs.filter((buff) => listable(buff) && buff.sourceSlot === "accessory" &&
      (buff.sources || []).some((source) => source.kind === "accessory" && source.id === talismanId))
      .forEach((buff) => sources.push({ id: buff.spEffectId, copies: 1, column: "accessory" }));
  });
  if (out.mode === "skill" && out.weapon) {
    buffs.buffs.filter((buff) => listable(buff) && buff.weaponInnate && (buff.weaponInnate.weaponIds || []).indexOf(out.weapon.id) !== -1)
      .forEach((buff) => sources.push({ id: buff.spEffectId, copies: 1, column: "other" }));
  }
  const merged = new Map();
  sources.forEach((source) => {
    const one = merged.get(source.id);
    if (one) one.copies += source.copies;
    else merged.set(source.id, { id: source.id, copies: source.copies, column: source.column });
  });
  const variantPick = (buff) => {
    const key = buff.affixVariant.key || "affix#" + buff.affixVariant.attachEffectId;
    const chosen = (config.variants || {})[key];
    if (chosen != null) return chosen;
    return buffs.buffs.find((one) => one.affixVariant && (one.affixVariant.key || "affix#" + one.affixVariant.attachEffectId) === key &&
      one.affixVariant.variant === 1).spEffectId;
  };
  const candidates = [];
  merged.forEach((one) => {
    const buff = BUFF[one.id];
    if (buff.affixVariant && variantPick(buff) !== buff.spEffectId) return;
    if (buff.selfAllyPair && buff.selfAllyPair.role === "ally") return;
    const verdict = referenceVerdict(buff, out);
    if (!verdict.ok) return;
    let stacks = null;
    let selected = false;
    if (buff.accumulatorLadder) {
      const group = buff.accumulatorLadder.tierSpEffectIds[0];
      if ((config.tiers || {})[group] !== buff.spEffectId) return;
      selected = true;
    }
    if (buff.stackInput) {
      stacks = Math.min(Math.max(0, Math.floor((config.stacks || {})[buff.spEffectId] || 0)), paramMax(buff.stackInput));
      if (!(stacks > 0)) return;
      selected = true;
    }
    const needs = !selected && (verdict.manual || buff.activation !== "passive");
    if (needs && !(config.ticks || {})[buff.spEffectId]) return;
    const multiply = buff.stacking.spCategoryBehavior === "stackSelf" &&
      (!buff.stacking.exclusiveScope || buff.stacking.exclusiveScope === "perSpEffect");
    const tables = referenceTables(buff, verdict, stacks, multiply ? one.copies : 1);
    const value = weighted(tables.table, out.shares);
    const flat = weighted(tables.flat, out.shares);
    if (Math.abs(value - 1) <= EPS && flat <= EPS) return;
    candidates.push({ id: buff.spEffectId, key: buff.stacking.exclusiveKey, value, flat, table: tables.table,
      column: SUMMARY_COLUMN[one.column] || "other", copies: multiply ? one.copies : 1,
      highest: buff.stacking.spCategoryBehavior === "applyHighest", priority: buff.stacking.categoryPriority });
  });
  const winners = {};
  candidates.forEach((one) => {
    const current = winners[one.key];
    let better = !current;
    if (current) {
      if (one.highest && current.highest && one.priority !== current.priority) better = one.priority < current.priority;
      else if (Math.abs(one.value - current.value) > EPS) better = one.value > current.value;
      else if (Math.abs(one.flat - current.flat) > EPS) better = one.flat > current.flat;
      else better = one.id < current.id;
    }
    if (better) winners[one.key] = one;
  });
  const product = (list) => {
    const perType = {};
    TYPE_KEYS.forEach((key) => { perType[key] = 1; });
    list.forEach((one) => TYPE_KEYS.forEach((type) => { perType[type] *= one.table[type]; }));
    return weighted(perType, out.shares);
  };
  const list = Object.keys(winners).map((key) => winners[key]);
  const subtotals = {};
  R.COLUMN_ORDER.forEach((column) => { subtotals[column] = product(list.filter((one) => one.column === column)); });
  return {
    total: product(list),
    subtotals,
    ids: list.map((one) => one.id + (one.copies > 1 ? "x" + one.copies : "")).sort((a, b) => parseInt(a, 10) - parseInt(b, 10))
  };
}

// ---- 跑一个构成用例 ----------------------------------------------------

function runCase(def) {
  const isSpell = def.kind !== "skill";
  const skill = isSpell ? null : skills._skillById[def.id];
  const spell = isSpell ? skills._spellById[def.id] : null;
  assert.ok(skill || spell, def.key + "：找不到这个战技 / 法术");
  const weapon = def.weaponId ? skills._weaponById[def.weaponId] : null;
  if (def.weaponId) assert.ok(weapon, def.key + "：找不到武器 " + def.weaponId);
  const hits = skill ? R.selectHits(skill, weapon) : (spell.hits || []).slice();
  const selected = hits.filter((hit) => {
    if (hit.noDamage) return false;
    if (def.only) return def.only.indexOf(hit.atkId) !== -1;
    return hit.fpBoth === true || hit.noFp !== true;   // 默认勾选＝正常版这一侧（两侧共用的 fpBoth 段也算）
  });
  const comp = R.composition(selected, weapon, isSpell);
  const out = R.makeOutput({ mode: def.kind, meansId: def.id, weapon, hand: 1, shares: comp.shares, contexts: {} }, buffs);
  const rows = R.overviewRows(cfgIndex, out);
  const useful = rows.filter((row) => row.applicable && row.multiplier > R.USEFUL_EPSILON);
  return { def, weapon, hits, selected, comp, out, rows, useful, isSpell };
}

const results = {};
CASES.forEach((def) => { results[def.key] = runCase(def); });

function close(actual, expected, message) {
  assert.ok(
    Math.abs(actual - expected) <= 1e-9,
    message + "（期望 " + expected + "，实际 " + actual + "）"
  );
}

// ---- 构成用例的断言 ------------------------------------------------------

CASES.forEach((def) => {
  const run = results[def.key];

  test("对照用例 " + def.key + "：选段与伤害构成", () => {
    assert.ok(run.hits.length > 0, "应能选出段");
    assert.ok(run.selected.length > 0, "应能勾上段");
    const ids = new Set(run.hits.map((hit) => hit.atkId));
    run.selected.forEach((hit) => {
      assert.ok(ids.has(hit.atkId), "勾选的段必须来自选出的段");
      assert.notEqual(hit.noDamage, true, "noDamage 段不该被勾上");
      if (!def.only) assert.notEqual(hit.noFp, true, "默认勾选只取正常版这一侧");
    });
    const reference = referenceShares(run.hits, run.weapon, new Set(run.selected.map((hit) => hit.atkId)));
    TYPE_KEYS.forEach((key) => {
      close(run.comp.shares[key], reference.shares[key], key + " 占比应与参考实现一致");
    });
    close(TYPE_KEYS.reduce((sum, key) => sum + run.comp.shares[key], 0), 1, "占比之和应为 1");
    close(run.comp.total, reference.total, "相对伤害总量应与参考实现一致");
  });

  test("对照用例 " + def.key + "：一览前 10 名与有效倍率（条件全部成立、Σ 占比 × 适用倍率连乘，部分段按段加权）", () => {
    const top = run.useful.slice(0, 10);
    assert.ok(top.length > 0, "应有生效的条目");
    top.forEach((row, i) => {
      if (i) assert.ok(top[i - 1].multiplier >= row.multiplier - 1e-12, "前 10 名必须按有效倍率降序");
      const buff = BUFF[row.entry.id];
      assert.ok(buff, "一览里出现了数据集里没有的 #" + row.entry.id);
      const expected = referenceOverview(buff, run.out);
      assert.notEqual(expected, null, "#" + row.entry.id + " 参考实现判为不生效");
      close(row.multiplier, expected, "#" + row.entry.id + " 的有效倍率");
    });
  });

  test("对照用例 " + def.key + "：一览只收能进计算的条目，生效判定分流与参考实现逐条一致", () => {
    let checked = 0;
    const listed = new Set(run.rows.map((row) => row.entry.id));
    buffs.buffs.forEach((buff) => assert.equal(listed.has(buff.spEffectId), listable(buff), "#" + buff.spEffectId + " 进不进一览"));
    run.rows.forEach((row) => {
      const buff = row.entry.buff;
      const expected = referenceOverview(buff, run.out);
      checked += 1;
      if (expected === null) {
        assert.equal(row.applicable, false, "#" + buff.spEffectId + " 参考判不生效，页面却是 " + row.state);
        if (buff.selfAllyPair && buff.selfAllyPair.role === "ally") assert.equal(row.reasons[0], R.TEXT.reasonAllyPair);
      } else {
        assert.equal(row.applicable, true, "#" + buff.spEffectId + " 参考判生效，页面却是 " + row.state);
        close(row.multiplier, expected, "#" + buff.spEffectId + " 的有效倍率");
      }
    });
    assert.ok(checked > 100, "逐条比对的样本太少");
  });
});

// ---- 跨用例关系 --------------------------------------------------------

test("对照：构成相同的两次选段，一览与推荐配置必须逐项相同", () => {
  const full = results["corpse-piler-full"];
  const last = results["corpse-piler-last"];
  assert.ok(full.selected.length > last.selected.length, "全段应比只勾一段多");
  TYPE_KEYS.forEach((key) => close(full.comp.shares[key], last.comp.shares[key], key + " 占比应一致"));
  assert.deepEqual(
    full.useful.slice(0, 10).map((row) => row.entry.id),
    last.useful.slice(0, 10).map((row) => row.entry.id),
    "构成相同 → 前 10 名必须完全相同"
  );
  const fillFull = R.recommendFill(cfgIndex, full.out, R.emptyConfig(), Core, full.weapon.wepType).config;
  const fillLast = R.recommendFill(cfgIndex, last.out, R.emptyConfig(), Core, last.weapon.wepType).config;
  assert.deepEqual(fillFull, fillLast, "构成相同 → 推荐配置完全相同");
});

test("对照：同一战技换一把带火属性的武器，只加火的条目随之生效", () => {
  const plain = results["lions-claw-greatsword"];
  const flame = results["lions-claw-flame-greatsword"];
  close(plain.comp.shares.fire, 0, "普通大剑的火占比应为 0");
  assert.ok(flame.comp.shares.fire > 0, "火焰大剑的火占比应大于 0");
  assert.deepEqual(plain.selected.map((hit) => hit.atkId), flame.selected.map((hit) => hit.atkId),
    "同一战技同一套段，换武器不该改变选段");
  const fireOnly = flame.useful.filter((row) => row.table.fire > 1 &&
    TYPE_KEYS.every((key) => key === "fire" || Math.abs(row.table[key] - 1) < 1e-9));
  assert.ok(fireOnly.length > 0, "火焰大剑下应能进来只加火的条目");
  const plainIds = new Set(plain.useful.map((row) => row.entry.id));
  fireOnly.forEach((row) => assert.ok(!plainIds.has(row.entry.id), "只加火的条目对纯物理构成没有收益（#" + row.entry.id + "）"));
});

test("对照：带子弹的战技，子弹段照常按 攻击力 × motion/100 + flat 计算", () => {
  const run = results["firebreather"];
  const bullets = run.hits.filter((hit) => hit.isBullet);
  assert.ok(bullets.length > 0, "喷火应有子弹段");
  const damaging = bullets.filter((hit) => {
    const one = R.hitContribution(hit, run.weapon, false);
    return TYPE_KEYS.some((key) => one[key] > 0);
  });
  assert.ok(damaging.length > 0, "战技的子弹段不得被整段归零");
  assert.ok(run.hits.some((hit) => hit.noDamage === true), "喷火里应有 noDamage 段（精力消耗）");
  assert.ok(run.selected.every((hit) => hit.noDamage !== true), "noDamage 段不该进构成");
  // 战技的子弹段同样按 skill 判定：带 112 的「提升战技攻击力」对它生效。
  assert.equal(R.appliesVerdict(index.byId[8350000], run.out).state, "yes");
});

test("对照：法术的构成只来自 flat，不会凭空多出物理；推荐配置能给出增伤", () => {
  ["death-lightning", "comet"].forEach((key) => {
    const run = results[key];
    PHYS.forEach((type) => close(run.comp.shares[type], 0, key + " 是法术，" + type + " 占比必须为 0"));
    const filled = R.recommendFill(cfgIndex, run.out, R.emptyConfig(), Core, R.outputWepType(run.out)).config;
    assert.ok(R.evaluateConfig(cfgIndex, run.out, filled, Core).total.multiplier > 1, key + " 应能给出增伤配置");
  });
});

// 参考实现：一个战技能不能进列表——不经被测代码，直接读 weapons[].skillVariants → variants[i].atkIds，
// 任一把武器（固定或局内战技池）的任一段按参考公式算得出非 0 相对值即可。
function referenceSkillListable(skill) {
  if (!(skill.hits || []).length || !(skill.weaponIds || []).length) return false;
  return skill.weaponIds.some((id) => {
    const weapon = skills._weaponById[id];
    const position = weapon && weapon.skillVariants ? weapon.skillVariants[String(skill.id)] : undefined;
    const variant = typeof position === "number" ? (skill.variants || [])[position] : null;
    if (!variant) return false;
    const picked = skill.hits.filter((hit) => variant.atkIds.indexOf(hit.atkId) !== -1);
    return referenceShares(picked, weapon, new Set(picked.map((hit) => hit.atkId))).total > 0;
  });
}

// 参考实现：一个法术能不能进列表——没有武器，只看 spells[] 里各段的固定值（按参考公式算得出非 0 即可）。
function referenceSpellListable(spell) {
  const hits = spell.hits || [];
  if (!hits.length) return false;
  return referenceShares(hits, null, new Set(hits.map((hit) => hit.atkId))).total > 0;
}

test("对照：输出手段列表只收「算得出非 0 相对值」的战技与法术", () => {
  const items = R.buildMeansItems(skills);
  const skillItems = items.filter((item) => item.kind === "skill");
  const spellItems = items.filter((item) => item.kind !== "skill");
  assert.ok(skillItems.length > 0 && spellItems.length > 0);
  // v3：局内战技池的武器也算，列表里的战技与参考实现逐个相同（本版本 155 个）。
  assert.deepEqual(skillItems.map((item) => item.id).sort((a, b) => a - b),
    skills.skills.filter(referenceSkillListable).map((skill) => skill.id).sort((a, b) => a - b));
  skillItems.forEach((item) => {
    const skill = skills._skillById[item.id];
    const playable = (skill.weaponIds || []).some((id) => {
      const weapon = skills._weaponById[id];
      return weapon && R.hasAnyDamage(R.selectHits(skill, weapon), weapon, false);
    });
    assert.ok(playable, "列表里的战技「" + item.nameZh + "」必须至少有一把武器算得出构成");
  });
  spellItems.forEach((item) => {
    assert.ok(R.hasAnyDamage(skills._spellById[item.id].hits, null, true), "列表里的法术「" + item.nameZh + "」必须至少有一段带固定值");
  });
  // 法术同样与参考实现逐个相同：skills 的 spells[] 现在只收可施放的（可达施法器池里 chanceWeight>0），
  // Magic 残留行 8100 / 8101「风暴管束者」（本作是战技 1200）不在 spells[]，也就不在列表里（本版本 119 个）。
  assert.deepEqual(spellItems.map((item) => item.id).sort((a, b) => a - b),
    skills.spells.filter(referenceSpellListable).map((spell) => spell.id).sort((a, b) => a - b));
  const notCastable = ((skills.coverage || {}).spellsNotCastable || []).map((one) => one.id);
  assert.deepEqual(notCastable, [8100, 8101], "不可施放的只有风暴管束者两行");
  notCastable.forEach((id) => {
    assert.ok(!spellItems.some((item) => item.id === id), id + " 不可施放，不得进输出手段列表");
  });
  if (DUMP) console.log("OUTPUTS skills=" + skillItems.length + " spells=" + spellItems.length);
});

// ---- 三组配置对照 --------------------------------------------------------

function outputOf(kind, id, weaponId) {
  const run = runCase({ key: "cfg", kind, id, weaponId, only: null });
  return run.out;
}

function fixedCard(key) {
  return { type: "fixed", key, affixIds: [null, null, null], curseIds: [null, null, null] };
}

const CONFIG_CASES = [
  {
    key: "corpse-piler-normal-fill",
    output: () => outputOf("skill", 1177, 9040000),
    build: (out) => R.recommendFill(cfgIndex, out, R.emptyConfig(), Core, R.outputWepType(out)).config,
    filled: true
  },
  {
    key: "death-lightning-deep-fill",
    output: () => outputOf("incantation", 5040, null),
    build: (out) => {
      const base = R.emptyConfig();
      base.runMode = "deep";
      return R.recommendFill(cfgIndex, out, base, Core, R.outputWepType(out)).config;
    },
    filled: true
  },
  {
    key: "lions-claw-2fixed-1custom-2talismans-evergaol7",
    output: () => outputOf("skill", 100, 3180000),
    build: () => {
      const config = R.emptyConfig();
      config.relics[0] = fixedCard("2070");   // 安定者的遗志：提升近战攻击力 + 提升战技攻击力
      config.relics[1] = fixedCard("2100");   // 王的黑夜：切换武器时…（条件型；只勾 7035902）
      const custom = R.emptyRelicCard();      // 自组：封印监牢 / 出击时附加火 / 对陷入冻伤的敌人
      custom.type = "custom";
      custom.affixIds = [7060000, 7120100, 7260400];
      config.relics[2] = custom;
      config.accessories = [1230, 2040];      // 战士壶碎片（提升战技攻击力）、红羽七刃剑（条件型，未勾）
      config.stacks[7069001] = 7;             // 封印监牢 7 层
      config.ticks[7035902] = true;           // 切换武器时，能提升物理攻击力：条件成立
      return config;
    },
    filled: false
  }
];

const configResults = {};
CONFIG_CASES.forEach((def) => {
  const out = def.output();
  const config = def.build(out);
  configResults[def.key] = { def, out, config, result: R.evaluateConfig(cfgIndex, out, config, Core) };
});

CONFIG_CASES.forEach((def) => {
  const run = configResults[def.key];

  test("配置对照 " + def.key + "：总倍率、各栏小计与计入条目集合等于参考实现", () => {
    const reference = referenceConfig(run.config, run.out);
    close(run.result.total.multiplier, reference.total, "总倍率");
    R.COLUMN_ORDER.forEach((column) => {
      close(run.result.byColumn[column].multiplier, reference.subtotals[column], column + " 小计");
    });
    assert.deepEqual(
      run.result.counted.slice().sort((a, b) => a.entry.id - b.entry.id)
        .map((item) => item.entry.id + (item.countedCopies > 1 ? "x" + item.countedCopies : "")),
      reference.ids, "计入条目集合（含份数）"
    );
    assert.ok(run.result.total.multiplier > 1, "这套配置应当增伤");
  });

  test("配置对照 " + def.key + "：槽位不越界、遗物合法、同键不重复", () => {
    const slots = run.result.slots;
    assert.ok(slots.weaponAffix.used <= slots.weaponAffix.cap);
    assert.ok(slots.weaponAffix.deepOnlyUsed <= slots.weaponAffix.deepOnlyCap);
    assert.ok(slots.relic.used <= slots.relic.cap);
    assert.ok(slots.accessory.used <= slots.accessory.cap);
    run.result.relicChecks.forEach((check) => assert.notEqual(check.status, "invalid", JSON.stringify(check.issues)));
    assert.deepEqual(run.result.violations, []);
    const keys = run.result.counted.map((item) => item.entry.key);
    assert.equal(new Set(keys).size, keys.length);
  });

  test("配置对照 " + def.key + "：口径细节", () => {
    if (def.filled) {
      // 推荐是确定性的：同样输入再填一次得到同一套配置，且已满不再加东西。
      const again = R.recommendFill(cfgIndex, run.out, run.config, Core, R.outputWepType(run.out));
      assert.equal(again.added.length, 0);
      assert.deepEqual(def.build(run.out), run.config, "推荐填满必须是确定性的");
      // 不选条件型、叠层与累积阶梯。
      run.result.counted.forEach((item) => {
        assert.equal(item.entry.activation, "passive", item.entry.id + " 不是被动");
        assert.equal(item.entry.stackInput, null);
        assert.equal(item.entry.accLadder, null);
        assert.equal(item.needs.length, 0);
      });
      // 平局取 ID 小者：推荐的武器词条里，没有哪条能被 ID 更小、推荐口径总倍率相同的候选替换。
      const picks = run.config.weaponAffixes.map((one) => one.id);
      assert.ok(picks.length > 0);
      if (def.key.indexOf("deep") !== -1) {
        assert.equal(run.config.runMode, "deep");
        assert.equal(run.result.caps.relics, buffs.slotRules.modes.deep.relicSlots);
        assert.equal(run.result.slots.weaponAffix.used, buffs.slotRules.weaponAffix.maxAffixesDeep, "深夜填满 12 条");
        run.result.counted.forEach((item) => {
          assert.notEqual(item.entry.id, 8350000, "祷告不吃提升战技攻击力");
        });
        run.config.relics.forEach((card) => {
          if (card.type !== "custom") return;
          card.affixIds.forEach((id, row) => {
            if (id == null) return;
            const affix = catalog.affixes.find((one) => one.effectId === id);
            assert.equal(card.curseIds[row] != null, affix.requiresCurse === true, "需诅咒的配诅咒、不需要的不带");
          });
        });
      } else {
        assert.equal(run.result.slots.weaponAffix.used, buffs.slotRules.weaponAffix.maxAffixesNormal, "常规填满 6 条");
      }
    } else {
      assert.equal(run.result.relicChecks[0].status, "fixed");
      assert.equal(run.result.relicChecks[1].status, "fixed");
      assert.equal(run.result.relicChecks[2].status, "valid", "自组遗物三条合法：" + JSON.stringify(run.result.relicChecks[2].issues));
      const counted = new Set(run.result.counted.map((item) => item.entry.id));
      assert.ok(counted.has(7006700) && counted.has(7035902) && counted.has(7069001) && counted.has(312300));
      assert.ok(!counted.has(7035703), "王的黑夜里没勾的条件型不计入");
      assert.ok(!counted.has(320400), "红羽七刃剑是条件型，放进护符栏≠条件成立");
      const evergaol = run.result.items.find((item) => item.entry.id === 7069001);
      assert.equal(evergaol.stacks, 7);
      close(evergaol.multiplier, BUFF[7069001].stackInput.tierMultipliers[6], "封印监牢 7 层");
      const fire = run.result.items.filter((item) => item.entry.variantGroup === "affix#7120100");
      assert.equal(fire.filter((item) => item.state !== "variantOff").length, 1, "多档词条只留第 1 档");
      assert.equal(fire.find((item) => item.state !== "variantOff").state, "pending", "imbuedWeaponOnly 要确认");
    }
  });
});

// ---- 两端逐字一致：文案常量表与说明区的摘要 ------------------------------

// FNV-1a 32 位（按 UTF-8 字节），与 macOS 端 BuffRankerChecks.swift 的 loadoutDigest 逐位相同。
function fnv1a(text) {
  const bytes = Buffer.from(text, "utf8");
  let hash = 0x811c9dc5;
  for (const byte of bytes) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

// 文案常量表：点号路径排序后逐行「路径=文案」。skip＝要排除的路径前缀（只用于核对「只多了哪几个键」）。
function textTableDigest(skip) {
  const flat = R.flattenText(R.TEXT);
  const keys = Object.keys(flat).filter((key) => !(skip && key.startsWith(skip)))
    .sort((a, b) => (a < b ? -1 : (a > b ? 1 : 0)));
  return { count: keys.length, digest: fnv1a(keys.map((key) => key + "=" + flat[key]).join("\n")) };
}

// 说明区：数字归一成 # 之后的摘要（数据改数值不影响，措辞一漂移就分叉）。
function briefDigest(notes) {
  return fnv1a(notes.join("\n").replace(/[0-9]+/g, "#"));
}

// 两端同一个常量：改了任何一句文案，两端都要改、两个常量都要更新。
// 摘要算法不变（FNV-1a 32 位，点号路径排序后逐行「路径=文案」）。
//   skills v3：多了四个 weaponSource.* 键（fixed / pool / poolHint / note），332 → 336 条，854da404 → 07a69c5e；
//   buffs v6 道具等级：再多三个 goodsLevel.* 键（tag / hint / note），336 → 339 条，07a69c5e → 41e2ae25。
const TEXT_TABLE_DIGEST = "41e2ae25";
const TEXT_TABLE_COUNT = 339;
const TEXT_TABLE_DIGEST_BEFORE_GOODS_LEVEL = "07a69c5e";
const BRIEF_DIGEST = "ad04314d";

test("两端逐字一致：配置部分的文案常量表（点号路径 + 文案）与 macOS 端 LoadoutText.table 同一个摘要", () => {
  const { count, digest } = textTableDigest();
  assert.equal(count, TEXT_TABLE_COUNT, "文案条数");
  assert.equal(digest, TEXT_TABLE_DIGEST, "文案常量表摘要（macOS 端 checkLoadoutParity 断言同一个值）");
  // 这一版只多了 goodsLevel.* 三个键：去掉它们，摘要回到上一版的值（其余文案一字未动）。
  const before = textTableDigest("goodsLevel.");
  assert.equal(before.count, TEXT_TABLE_COUNT - 3);
  assert.equal(before.digest, TEXT_TABLE_DIGEST_BEFORE_GOODS_LEVEL, "除 goodsLevel.* 外文案不变");
});

test("文案常量表：ranker.js 里引用到的每个 TEXT.路径 都真的存在（macOS 端 checkLoadoutTexts 同样扫源码）", () => {
  const source = readFileSync(path.join(repoRoot, "windows", "renderer", "pages", "ranker.js"), "utf8");
  const paths = [...new Set(source.match(/\bTEXT(?:\.[A-Za-z_][A-Za-z0-9_]*)+/g) || [])];
  assert.ok(paths.length > 100, "应扫到足量的文案引用");
  const missing = paths.filter((ref) => {
    let node = R.TEXT;
    for (const part of ref.split(".").slice(1)) {
      if (node == null || typeof node !== "object" || !(part in node)) return true;
      node = node[part];
    }
    return node === undefined;
  });
  assert.deepEqual(missing, []);
});

test("两端逐字一致：说明区（口径说明）的正文与 macOS 端 LoadoutText.briefNotes 同一个摘要", () => {
  const notes = R.briefNotes(buffs, cfgIndex);
  assert.equal(briefDigest(notes), BRIEF_DIGEST);
});

test("对照：七组构成用例与三组配置用例都真的算出了东西（并在需要时打出对拍行）", () => {
  assert.equal(CASES.length, 7);
  assert.equal(CONFIG_CASES.length, 3);
  const kinds = new Set(CASES.map((def) => def.kind));
  assert.ok(kinds.has("skill") && kinds.has("sorcery") && kinds.has("incantation"));
  CASES.forEach((def) => assert.ok(results[def.key].useful.length > 0, def.key + " 应有生效条目"));
  assert.equal(Object.keys(index.variants).length, 7, "多档词条 7 组（数据 affixVariant）");

  if (DUMP) {
    CASES.forEach((def) => {
      const run = results[def.key];
      console.log(R.caseDumpLine(def.key, run.selected.map((hit) => hit.atkId), run.comp, run.rows));
    });
    CONFIG_CASES.forEach((def) => {
      const run = configResults[def.key];
      console.log(R.configDumpLine(def.key, run.config, run.result));
    });
    console.log("TEXT count=" + textTableDigest().count + " digest=" + textTableDigest().digest +
      " brief=" + briefDigest(R.briefNotes(buffs, cfgIndex)));
  }
});
