// 增伤排名页的**双端对照用例**：macOS 端由同事并行实现同一套「自己组配置」算法，
// 两端用同一组输入、同一套断言口径。
//
// 每一端都在自己这一侧用一份**独立重算的参考实现**校对「同一算法的中间量」——构成占比、
// 「全部增益一览」前 10 名的有效倍率、整套配置的总倍率与计入条目集合（参考实现不复用被测代码的任何分支）。
// 两边都绿，两端算出来的数就必然对得上；数值会随数据集修订变化，所以一律**不写绝对快照**。
//
// 固定的三组配置对照输入（任务清单）：
//   ① 尸横遍野 + 尸山血海，常规模式：按推荐填满后的总倍率与计入条目集合；
//   ② 死亡雷击，深夜模式：按推荐填满后的总倍率与计入条目集合；
//   ③ 狮子斩 + 大剑：2 件固定遗物（安定者的遗志、辽阔的幽静情景）＋ 1 件自组遗物。
//
// 需要人工对拍时：
//   NR_RANKER_DUMP=1 node --test windows/tests/ranker_crosscheck.test.mjs
// 会打出 CASE / CONFIG 两种行（同一格式），与 macOS 端逐行比即可。
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

// 构成用例（与旧版对照用例同一组输入）。
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
const FIELDS = {};
(buffs.rateFields || []).forEach((field) => { FIELDS[field.key] = field; });

function countsAsDamage(buff) {
  return Object.keys(buff.rates || {}).some((key) => {
    const field = FIELDS[key];
    return field && field.countsAsDamage === true && buff.rates[key] !== field.default;
  });
}

// 同一遗物词条下的多档（affixVariant）参考分组，独立重写：数据有 affixVariant 就按它；没有时按
// 「同一 relicAffixes[0].attachEffectId、行名去掉 ' - Potency N' 后相同、倍率字段集合相同、各自一个
// exclusiveKey、至少两条」分组。每组默认只算第 1 档（数据给的 variant=1，推断时取 ID 最小的），
// 互斥键合并为 affix#<词条 ID>。返回 spEffectId → { group, first }。
function referenceVariants() {
  const out = {};
  const withData = buffs.buffs.filter((buff) => buff.affixVariant);
  if (withData.length) {
    const firsts = {};
    withData.forEach((buff) => {
      const key = buff.affixVariant.key || "affix#" + buff.affixVariant.attachEffectId;
      if (buff.affixVariant.variant === 1) firsts[key] = buff.spEffectId;
    });
    withData.forEach((buff) => {
      const key = buff.affixVariant.key || "affix#" + buff.affixVariant.attachEffectId;
      out[buff.spEffectId] = { group: key, first: firsts[key] };
    });
    return out;
  }
  const buckets = new Map();
  buffs.buffs.forEach((buff) => {
    if (!countsAsDamage(buff) || buff.stackInput || buff.accumulatorLadder || buff.accumulatorStages || buff.selfAllyPair) return;
    const links = buff.relicAffixes || [];
    if (links.length !== 1) return;
    const name = String(buff.paramName || "").replace(/\s*-\s*Potency\s*\d+\s*$/i, "");
    const bucket = links[0].attachEffectId + "|" + name + "|" + Object.keys(buff.rates || {}).sort().join(",");
    if (!buckets.has(bucket)) buckets.set(bucket, []);
    buckets.get(bucket).push(buff);
  });
  buckets.forEach((members) => {
    if (members.length < 2) return;
    if (new Set(members.map((buff) => buff.stacking.exclusiveKey)).size !== members.length) return;
    const group = "affix#" + members[0].relicAffixes[0].attachEffectId;
    const first = Math.min(...members.map((buff) => buff.spEffectId));
    members.forEach((buff) => { out[buff.spEffectId] = { group, first }; });
  });
  return out;
}
const VARIANTS = referenceVariants();

// appliesTo 判定（notes.appliesTo 的口径，独立重写）。
function referenceVerdict(buff, out) {
  const cls = out.mode;
  const value = (buff.appliesTo || {})[cls];
  if (value === "yes") return { ok: true, weight: 1, manual: false, restricted: null };
  if (value !== "conditional") return { ok: false };
  const requires = (((buff.appliesToDetail || {})[cls]) || {}).requires || {};
  let weight = 1;
  let manual = Object.keys(requires).length === 0;
  let restricted = null;
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

function referenceTable(buff, verdict, stacks) {
  const perChannel = {};
  TYPE_KEYS.forEach((key) => { perChannel[key] = 1; });
  const rates = referenceRates(buff, stacks);
  Object.keys(rates).forEach((key) => {
    const field = FIELDS[key];
    const value = rates[key];
    if (!field || field.countsAsDamage !== true || field.valueKind !== "multiplier") return;
    if (typeof value !== "number" || !isFinite(value) || value <= 0 || value === field.default) return;
    (FIELD_CHANNELS[key] || []).forEach((channel) => {
      if (verdict.restricted && channel !== verdict.restricted) return;
      perChannel[channel] *= value;
    });
  });
  if (verdict.weight < 1) {
    TYPE_KEYS.forEach((key) => { perChannel[key] = 1 + (perChannel[key] - 1) * verdict.weight; });
  }
  return perChannel;
}

function weighted(table, shares) {
  return TYPE_KEYS.reduce((sum, key) => sum + shares[key] * table[key], 0);
}

// 一条 buff 在「亲手放入」口径下对当前输出的有效倍率（一览的参考值）。
// 叠层类亲手放入时默认一局实际能达到的层数（没有就 1 层）。
function referenceMultiplier(buff, out) {
  if (buff.direction === "decrease") return null;
  const verdict = referenceVerdict(buff, out);
  if (!verdict.ok) return null;
  const stacks = buff.stackInput ? (buff.stackInput.practicalMaxStacks || 1) : null;
  return weighted(referenceTable(buff, verdict, stacks), out.shares);
}

// 整套配置的参考总倍率：独立地从配置展开 spEffectId，按 多档只留第 1 档 / target / direction（减益不计）/
// appliesTo / activation 过滤，按 exclusiveKey 去重（同键取有效倍率高的，再相同取 id 小的），
// 逐伤害类型连乘后按占比加权。当前武器固有自动列入但不算亲手放入（条件型默认未确认）。
function referenceConfig(config, out) {
  const deep = config.runMode === "deep";
  const relicSlots = deep ? buffs.slotRules.modes.deep.relicSlots : buffs.slotRules.modes.normal.relicSlots;
  const byId = {};
  buffs.buffs.forEach((buff) => { byId[buff.spEffectId] = buff; });
  const sources = [];
  config.weaponAffixes.forEach((one) => {
    const raw = buffs.weaponAffixes.find((affix) => affix.attachEffectId === one.id);
    for (let copy = 0; copy < one.count; copy += 1) {
      raw.spEffectIds.forEach((id) => sources.push({ id, explicit: true }));
    }
  });
  config.relics.slice(0, relicSlots).forEach((card) => {
    if (card.type === "fixed") {
      const relic = buffs.fixedRelics.find((one) => one.relicIds.join("-") === card.key);
      relic.spEffectIds.forEach((id) => sources.push({ id, explicit: false }));
    } else if (card.type === "custom") {
      card.affixIds.filter((id) => id != null).forEach((affixId) => {
        buffs.buffs.filter((buff) => (buff.relicAffixes || []).some((link) => link.catalogEffectId === affixId))
          .forEach((buff) => sources.push({ id: buff.spEffectId, explicit: true }));
      });
    }
  });
  config.accessories.filter((id) => id != null).forEach((talismanId) => {
    buffs.buffs.filter((buff) => (buff.sourceSlots || []).indexOf("accessory") !== -1 &&
      (buff.sources || []).some((source) => source.kind === "accessory" && source.id === talismanId))
      .forEach((buff) => sources.push({ id: buff.spEffectId, explicit: true }));
  });
  if (out.mode === "skill" && out.weapon) {
    buffs.buffs.filter((buff) => buff.weaponInnate && (buff.weaponInnate.weaponIds || []).indexOf(out.weapon.id) !== -1)
      .forEach((buff) => sources.push({ id: buff.spEffectId, explicit: false }));
  }
  const winners = {};
  sources.forEach((source) => {
    const buff = byId[source.id];
    if (!buff || !countsAsDamage(buff)) return;
    const variant = VARIANTS[buff.spEffectId];
    if (variant && variant.first !== buff.spEffectId) return;
    if (buff.target !== "self" || buff.direction === "decrease") return;
    assert.ok(!buff.stackInput && !buff.accumulatorLadder, "参考实现不处理叠层；对照用例里不该出现 " + buff.spEffectId);
    const verdict = referenceVerdict(buff, out);
    if (!verdict.ok) return;
    const needsConfirm = verdict.manual || buff.activation !== "passive";
    if (needsConfirm && !source.explicit) return;
    const table = referenceTable(buff, verdict);
    const value = weighted(table, out.shares);
    const key = variant ? variant.group : buff.stacking.exclusiveKey;
    const current = winners[key];
    if (!current || value > current.value || (value === current.value && buff.spEffectId < current.id)) {
      winners[key] = { id: buff.spEffectId, value, table };
    }
  });
  const perType = {};
  TYPE_KEYS.forEach((key) => { perType[key] = 1; });
  Object.keys(winners).forEach((key) => TYPE_KEYS.forEach((type) => { perType[type] *= winners[key].table[type]; }));
  return {
    total: weighted(perType, out.shares),
    ids: Object.keys(winners).map((key) => winners[key].id).sort((a, b) => a - b)
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
    return Boolean(hit.noFp) === false;   // 默认勾选＝正常版这一侧
  });
  const comp = R.composition(selected, weapon, isSpell);
  const out = R.makeOutput({ mode: def.kind, meansId: def.id, weapon, hand: 1, shares: comp.shares, contexts: {} }, buffs);
  const rows = R.overviewRows(cfgIndex, out, R.emptyConfig());
  const counted = rows.filter((row) => row.state === "counted" && row.multiplier > R.USEFUL_EPSILON);
  return { def, weapon, hits, selected, comp, out, rows, counted, isSpell };
}

const results = {};
CASES.forEach((def) => { results[def.key] = runCase(def); });

const buffById = {};
(buffs.buffs || []).forEach((buff) => { buffById[buff.spEffectId] = buff; });

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

  test("对照用例 " + def.key + "：一览前 10 名与有效倍率（Σ 占比 × 适用倍率连乘，部分段按段加权）", () => {
    const top = run.counted.slice(0, 10);
    assert.equal(top.length, Math.min(10, run.counted.length));
    assert.ok(top.length > 0, "应有生效的条目");
    top.forEach((row, i) => {
      if (i) assert.ok(top[i - 1].multiplier >= row.multiplier, "前 10 名必须按有效倍率降序");
      const buff = buffById[row.entry.id];
      assert.ok(buff, "一览里出现了数据集里没有的 #" + row.entry.id);
      const expected = referenceMultiplier(buff, run.out);
      assert.notEqual(expected, null, "#" + row.entry.id + " 参考实现判为不生效");
      close(row.multiplier, expected, "#" + row.entry.id + " 的有效倍率");
    });
  });

  test("对照用例 " + def.key + "：生效判定分流与参考实现逐条一致", () => {
    let checked = 0;
    run.rows.forEach((row) => {
      const buff = row.entry.buff;
      const variant = VARIANTS[buff.spEffectId];
      if (variant && variant.first !== buff.spEffectId) {
        assert.equal(row.state, "variantOff", "#" + buff.spEffectId + " 是多档词条里未选的档");
        return;
      }
      assert.notEqual(row.state, "variantOff", "#" + buff.spEffectId + " 不是多档词条里未选的档");
      if (buff.target !== "self") {
        assert.equal(row.state, "no", "#" + buff.spEffectId + " 不作用于自己");
        return;
      }
      if (buff.direction === "decrease") {
        assert.equal(row.state, "no", "#" + buff.spEffectId + " 是减益（notes.ranking ②）");
        return;
      }
      const verdict = referenceVerdict(buff, run.out);
      checked += 1;
      if (!verdict.ok) {
        assert.ok(row.state === "no" || row.state === "context", "#" + buff.spEffectId + " 参考判不生效，页面却是 " + row.state);
        if (verdict.context) assert.equal(row.state, "context");
      } else {
        assert.ok(row.state !== "no" && row.state !== "context", "#" + buff.spEffectId + " 参考判生效，页面却是 " + row.state);
      }
      if (row.state === "counted") assert.notEqual(buff.appliesTo[def.kind], "no");
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
    full.counted.slice(0, 10).map((row) => row.entry.id),
    last.counted.slice(0, 10).map((row) => row.entry.id),
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
  const fireOnly = flame.counted.filter((row) => row.table.fire > 1 &&
    TYPE_KEYS.every((key) => key === "fire" || Math.abs(row.table[key] - 1) < 1e-9));
  assert.ok(fireOnly.length > 0, "火焰大剑下应能进来只加火的条目");
  const plainIds = new Set(plain.counted.map((row) => row.entry.id));
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

test("对照：输出手段列表只收「算得出非 0 相对值」的战技与法术", () => {
  const items = R.buildMeansItems(skills);
  const skillItems = items.filter((item) => item.kind === "skill");
  const spellItems = items.filter((item) => item.kind !== "skill");
  assert.ok(skillItems.length > 0 && spellItems.length > 0);
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
    key: "lions-claw-2fixed-1custom",
    output: () => outputOf("skill", 100, 3180000),
    build: () => {
      const config = R.emptyConfig();
      config.relics[0] = fixedCard("2070");   // 安定者的遗志：提升近战攻击力 + 提升战技攻击力
      config.relics[1] = fixedCard("1750");   // 辽阔的幽静情景：提升物理攻击力＋２（另有条件型）
      const custom = R.emptyRelicCard();      // 自组：提升物理攻击力＋１ / 对陷入冻伤的敌人 / 出击时的武器附加火属性
      custom.type = "custom";
      custom.affixIds = [7001401, 7260400, 7120100];
      config.relics[2] = custom;
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

  test("配置对照 " + def.key + "：总倍率与计入条目集合等于参考实现", () => {
    const reference = referenceConfig(run.config, run.out);
    close(run.result.total.multiplier, reference.total, "总倍率");
    assert.deepEqual(run.result.counted.map((item) => item.entry.id).sort((a, b) => a - b), reference.ids, "计入条目集合");
    assert.ok(run.result.total.multiplier > 1, "这套配置应当增伤");
  });

  test("配置对照 " + def.key + "：槽位不越界、遗物合法、同键不重复", () => {
    const slots = run.result.slots;
    assert.ok(slots.weaponAffix.used <= slots.weaponAffix.cap);
    assert.ok(slots.weaponAffix.deepOnlyUsed <= slots.weaponAffix.deepOnlyCap);
    assert.ok(slots.relic.used <= slots.relic.cap);
    assert.ok(slots.accessory.used <= slots.accessory.cap);
    run.result.relicChecks.forEach((check) => assert.notEqual(check.status, "invalid", JSON.stringify(check.issues)));
    const keys = run.result.counted.map((item) => item.entry.key);
    assert.equal(new Set(keys).size, keys.length);
  });

  test("配置对照 " + def.key + "：口径细节", () => {
    if (def.filled) {
      // 推荐是确定性的：同样输入再填一次得到同一套配置，且已满不再加东西。
      const again = R.recommendFill(cfgIndex, run.out, run.config, Core, R.outputWepType(run.out));
      assert.equal(again.added.length, 0);
      const fresh = def.build(run.out);
      assert.deepEqual(fresh, run.config, "推荐填满必须是确定性的");
      if (def.key.indexOf("deep") !== -1) {
        assert.equal(run.config.runMode, "deep");
        assert.equal(slotsCap(run.result).relic, buffs.slotRules.modes.deep.relicSlots);
        run.result.counted.forEach((item) => {
          assert.notEqual(item.entry.id, 8350000, "祷告不吃提升战技攻击力");
        });
      } else {
        assert.equal(run.result.slots.weaponAffix.cap, buffs.slotRules.weaponAffix.maxAffixesNormal);
      }
    } else {
      assert.equal(run.result.relicChecks[0].status, "fixed");
      assert.equal(run.result.relicChecks[1].status, "fixed");
      assert.equal(run.result.relicChecks[2].status, "valid", "自组遗物三条合法：" + JSON.stringify(run.result.relicChecks[2].issues));
      const pending = run.result.items.filter((item) => item.column === "relic" && item.state === "pending");
      pending.forEach((item) => assert.equal(item.explicit, false, "只有随固定遗物整件带入的条件型才是未确认"));
      const flatOnly = run.result.items.filter((item) => item.column === "relic" && item.entry.hasFlat && !item.entry.hasMultiplier);
      assert.ok(flatOnly.length > 0, "附加火属性是攻击力加算");
      flatOnly.forEach((item) => R.TYPE_KEYS.forEach((type) => assert.equal(item.table[type], 1, "加算不进连乘")));
    }
  });
});

function slotsCap(result) {
  return { relic: result.slots.relic.cap };
}

test("对照：七组构成用例与三组配置用例都真的算出了东西（并在需要时打出对拍行）", () => {
  assert.equal(CASES.length, 7);
  assert.equal(CONFIG_CASES.length, 3);
  const kinds = new Set(CASES.map((def) => def.kind));
  assert.ok(kinds.has("skill") && kinds.has("sorcery") && kinds.has("incantation"));
  CASES.forEach((def) => assert.ok(results[def.key].counted.length > 0, def.key + " 应有生效条目"));
  // 参考实现的多档分组不能是空转：schema 复核三轮列出的 7 组词条（每组 4 档）都要分出来。
  const variantGroups = new Set(Object.keys(VARIANTS).map((id) => VARIANTS[id].group));
  assert.equal(variantGroups.size, 7);
  assert.equal(Object.keys(VARIANTS).length, 28);

  if (DUMP) {
    CASES.forEach((def) => {
      const run = results[def.key];
      const shares = TYPE_KEYS.map((key) => run.comp.shares[key].toFixed(9)).join(",");
      const top = run.counted.slice(0, 10).map((row) => row.entry.id + ":" + row.multiplier.toFixed(9)).join(",");
      const states = {};
      run.rows.forEach((row) => { states[row.state] = (states[row.state] || 0) + 1; });
      console.log(
        "CASE " + def.key +
        " selected=" + run.selected.map((hit) => hit.atkId).join(",") +
        " shares=" + shares +
        " counted=" + run.counted.length +
        " top10=" + top +
        " states=" + Object.keys(states).sort().map((key) => key + ":" + states[key]).join("|")
      );
    });
    CONFIG_CASES.forEach((def) => {
      const run = configResults[def.key];
      const slots = run.result.slots;
      console.log(
        "CONFIG " + def.key +
        " mode=" + run.config.runMode +
        " total=" + run.result.total.multiplier.toFixed(9) +
        " weaponAffix=" + run.config.weaponAffixes.map((one) => one.id + "x" + one.count).join(",") +
        " relics=" + run.config.relics.slice(0, slots.relic.cap).map((card) => card.type === "fixed" ? "F" + card.key
          : (card.type === "custom" ? "C" + card.affixIds.filter((id) => id != null).join("+") +
            (card.curseIds.some((id) => id != null) ? "/" + card.curseIds.filter((id) => id != null).join("+") : "") : "-")).join(",") +
        " accessories=" + run.config.accessories.map((id) => id == null ? "-" : id).join(",") +
        " counted=" + run.result.counted.map((item) => item.entry.id).sort((a, b) => a - b).join(",") +
        " slots=" + slots.weaponAffix.used + "/" + slots.weaponAffix.cap + ":" + slots.weaponAffix.deepOnlyUsed + "/" +
        slots.weaponAffix.deepOnlyCap + ":" + slots.relic.used + "/" + slots.relic.cap + ":" +
        slots.accessory.used + "/" + slots.accessory.cap
      );
    });
  }
});
