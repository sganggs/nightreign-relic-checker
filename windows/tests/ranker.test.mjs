// 增伤排名页（renderer/pages/ranker.js）纯计算层单元测试。
//
// 口径以数据集自带的说明为准：
//   · skills（schemaVersion 3）：usage.选段（必读）／战技来源（v3）／命中段已按 TAE 核实（v3）／近战武器段／
//     法术 · 子弹段／削韧／伤害类型（斩 / 打 / 突），fieldNotes.noFp / fpBoth / notInvoked / selfOrAllyOnly
//   · buffs（schemaVersion 6）：notes.ranking、notes.appliesTo、stackingRules、slotRules、
//     rateFields[].countsAsDamage、stackInput、accumulatorLadder、stacking.exclusiveKey
//
// 数据集仍在做取值层面的修复，所以这里一律写**结构性断言**
// （某个字段存在、某个占比大于 0、某个排序关系成立），不断言会随数据变化的具体数值；
// 合成用例（自己拼的 buff）才断言精确数值。整套配置的用例见 ranker_config.test.mjs，
// 双端对照用例见 ranker_crosscheck.test.mjs。
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

const plan = R.rateFieldPlan(buffs);
const index = R.indexBuffs(buffs);
const cfgIndex = R.buildConfigIndex(buffs, index, catalog, Core);

// 一把「物理 + 属性都有基础攻击力」的武器，用来验证构成会同时出现两种伤害类型。
function firstMixedWeapon() {
  return skills.weapons.find((weapon) => {
    const base = weapon.attackBase || {};
    const elemental = ["magic", "fire", "lightning", "holy"].some((key) => Number(base[key]) > 0);
    return Number(base.physical) > 0 && elemental && typeof weapon.skillVariant === "number";
  });
}

// 武器自己的固定战技（v3 的 weaponIds 含局内战技池，「第一个引用它的战技」不再是它自带的那个）。
function skillOf(weapon) {
  return skills._skillById[weapon.swordArtsParamId] || null;
}

function shares(map) {
  const out = {};
  R.TYPE_KEYS.forEach((key) => { out[key] = map[key] || 0; });
  return out;
}

// 合成一条 buff（默认：物理 ×1.2、对三类输出都 yes、被动、按 ID 互斥）。
function synth(id, extra) {
  return R.indexBuff(Object.assign({
    spEffectId: id,
    rates: { physicsAttackRate: 1.2 },
    target: "self",
    activation: "passive",
    direction: "increase",
    appliesTo: { skill: "yes", sorcery: "yes", incantation: "yes" },
    stacking: { spCategory: 10, spCategoryBehavior: "stackSelf", exclusiveKey: "sp10#" + id }
  }, extra || {}), plan);
}

function out(options, data) {
  return R.makeOutput(Object.assign({
    mode: "skill", meansId: null, weapon: null, hand: 1,
    shares: shares({ slash: 1 }), contexts: {}
  }, options || {}), data || buffs);
}

function env(output, config) {
  return { plan, out: output, config: config || R.emptyConfig(), ladders: cfgIndex.ladders };
}

test("模块注册：导出 init / refresh，不依赖 window", () => {
  assert.equal(typeof Page.init, "function");
  assert.equal(typeof Page.refresh, "function");
  assert.equal(typeof globalThis.NightreignPages, "undefined", "node 下不应尝试注册页面");
});

test("两份数据集都带着页面真正依赖的结构（skills 需要 v3 的 skillVariants / weaponSources，buffs 需要 v6 的 appliesTo / slotRules / exclusiveKey）", () => {
  assert.equal(skills.schemaVersion, 3);
  assert.equal(R.SKILLS_SCHEMA_MIN, 3);
  assert.ok(buffs.schemaVersion >= 6, "配置组装依赖 schemaVersion 6 的字段");
  assert.ok(skills.usage && skills.usage["选段（必读）"], "选段规则必须来自数据集");
  assert.ok(skills.usage["本数据集的边界"], "页面要引用『绝对伤害不在范围内』这段");
  assert.ok(skills.usage["战技来源（v3）"], "武器来源（固定 / 局内战技池）的读法来自数据集");
  assert.ok(skills.usage[R.TAE_USAGE_KEY], "底部要引用「命中段已按 TAE 核实（v3）」这段");
  assert.equal(skills.counts.taeVerified, true, "本版本的 variants 已按 TAE 核实");
  assert.ok(skills.swordArtsPools && typeof skills.swordArtsPools === "object");
  skills.weapons.forEach((weapon) => {
    assert.ok(Array.isArray(weapon.skillIds), weapon.id + " 缺 skillIds");
    // skillVariants 缺失 = 这把武器能带的战技都没有命中段（fieldNotes.省略即默认值）。
    assert.ok(weapon.skillVariants === undefined || typeof weapon.skillVariants === "object", weapon.id + " 的 skillVariants");
  });
  skills.skills.forEach((skill) => {
    assert.deepEqual((skill.weaponSources || []).map((one) => one.id), skill.weaponIds || [],
      skill.id + " 的 weaponSources 与 weaponIds 一一对应");
  });
  assert.ok(buffs.notes && buffs.notes.ranking && buffs.notes.appliesTo && buffs.notes.userQuestions);
  assert.ok(buffs.stackingRules && buffs.stackingRules.zh);
  assert.ok(buffs.slotRules && buffs.slotRules.modes && buffs.slotRules.weaponAffix && buffs.slotRules.relic);
  assert.ok(Array.isArray(buffs.weaponAffixes) && buffs.weaponAffixes.length > 0);
  assert.ok(Array.isArray(buffs.fixedRelics) && buffs.fixedRelics.length > 0);
  assert.ok(buffs.attackIndex && buffs.attackIndex.skills && buffs.attackIndex.spells);
  assert.ok(buffs.enums && buffs.enums.sourceSlot && buffs.enums.wepType && buffs.enums.attackContext);
  buffs.buffs.forEach((buff) => {
    assert.equal(typeof buff.spEffectId, "number");
    assert.ok(buff.appliesTo && typeof buff.appliesTo === "object", buff.spEffectId + " 缺 appliesTo");
    R.OUTPUT_CLASSES.forEach((cls) => {
      assert.ok(["yes", "no", "conditional"].indexOf(buff.appliesTo[cls]) !== -1, buff.spEffectId + " 的 appliesTo." + cls);
    });
    assert.ok(buff.stacking && typeof buff.stacking.exclusiveKey === "string", buff.spEffectId + " 缺 exclusiveKey");
    assert.ok(typeof buff.sourceSlot === "string", buff.spEffectId + " 缺 sourceSlot");
  });
});

// ------------------------------------------------------------------ 倍率字段

test("parseRateFieldKey：认得出伤害层、攻击力层与点数加算", () => {
  assert.deepEqual(R.parseRateFieldKey("physicsAttackRate").layer, "damage");
  assert.deepEqual(R.parseRateFieldKey("physicsAttackPowerRate").layer, "attackPower");
  assert.deepEqual(R.parseRateFieldKey("physicsAttackPower").layer, "flat");
  assert.deepEqual(R.parseRateFieldKey("physicsAttackRate").types, R.TYPES_BY_ELEMENT.physical);
  assert.deepEqual(R.parseRateFieldKey("slashAttackRate").types, ["slash"]);
  assert.deepEqual(R.parseRateFieldKey("darkAttackRate").types, ["holy"], "dark 槽位在本作＝圣");
  assert.deepEqual(R.parseRateFieldKey("thunderAttackPowerRate").types, ["lightning"]);
  assert.equal(R.parseRateFieldKey("saAttackPowerRate"), null, "削韧不在伤害轴上");
  assert.equal(R.parseRateFieldKey("bowDistRate"), null);
});

test("rateFieldPlan：countsAsDamage 的字段一个都不能漏解析", () => {
  assert.equal(plan.unmapped.length, 0, "countsAsDamage 字段出现了页面解析不了的 key：" + plan.unmapped.join(", "));
  assert.ok(plan.multiplier.length > 0 && plan.flat.length > 0);
  const counted = buffs.rateFields.filter((field) => field.countsAsDamage === true);
  assert.equal(plan.multiplier.length + plan.flat.length, counted.length);
  plan.skipped.forEach((key) => {
    assert.notEqual(plan.byKey[key].countsAsDamage, true, key + " 被跳过了但它 countsAsDamage");
  });
});

test("rateFieldPlan：conditionalDamage（特攻 / 致命一击 / 远程衰减）不进乘积", () => {
  const conditional = buffs.rateFields.filter((field) => field.conditionalDamage === true);
  assert.ok(conditional.length > 0, "数据集应当标出 conditionalDamage 字段");
  conditional.forEach((field) => {
    assert.ok(
      !plan.multiplier.some((entry) => entry.key === field.key),
      field.key + " 是 conditionalDamage，不得无条件相乘"
    );
  });
});

test("indexBuff：物理倍率铺到全部物理子类型，属性倍率只落在自己那一格", () => {
  const physOnly = R.indexBuff({ spEffectId: -1, rates: { physicsAttackRate: 1.2 } }, plan);
  R.TYPES_BY_ELEMENT.physical.forEach((type) => {
    assert.ok(physOnly.multiplier[type] > 1, type + " 应当吃到物理倍率");
  });
  ["magic", "fire", "lightning", "holy"].forEach((type) => {
    assert.equal(physOnly.multiplier[type], 1, type + " 不应当吃到物理倍率");
  });

  const fireOnly = R.indexBuff({ spEffectId: -2, rates: { fireAttackRate: 1.5 } }, plan);
  assert.equal(fireOnly.multiplier.fire, 1.5);
  assert.equal(fireOnly.multiplier.slash, 1);

  // 斩击倍率与物理倍率同时生效、相乘（stackingRules 第 5 条）。
  const both = R.indexBuff({ spEffectId: -3, rates: { physicsAttackRate: 2, slashAttackRate: 3 } }, plan);
  assert.equal(both.multiplier.slash, 6);
  assert.equal(both.multiplier.blow, 2);

  // 攻击力倍率与最终伤害倍率是两层，两层相乘。
  const twoLayers = R.indexBuff({ spEffectId: -4, rates: { fireAttackRate: 2, fireAttackPowerRate: 3 } }, plan);
  assert.equal(twoLayers.multiplier.fire, 6);

  // 点数加算不折成倍率，单独进 flat 表。
  const flatOnly = R.indexBuff({ spEffectId: -5, rates: { fireAttackPower: 35 } }, plan);
  assert.equal(flatOnly.multiplier.fire, 1);
  assert.equal(flatOnly.flat.fire, 35);
  assert.equal(flatOnly.hasFlat, true);
  assert.equal(flatOnly.hasMultiplier, false);
});

test("indexBuff：削韧 / 异常 / special / flag 字段一律不进伤害表", () => {
  const noise = R.indexBuff({
    spEffectId: -6,
    rates: {
      saAttackPowerRate: 2, bloodAttackPower: 50,
      restageAttackRate: 0.6, isUseAtkParamAtkPowerCorrect: 1
    }
  }, plan);
  assert.equal(noise.countsAsDamage, false, "这些字段不改变血量伤害");
  assert.equal(noise.otherRateKeys.length, 4, "但要能提示『另有不计入伤害的字段』");
});

// ------------------------------------------------------------------ 选段

test("selectHits：一律走 weapons[].skillVariants[战技 ID] → variants[i].atkIds，不取并集", () => {
  const multi = skills.skills.find((skill) => Array.isArray(skill.variants) && skill.variants.length > 1);
  assert.ok(multi, "数据集里应当有多套动作的战技");
  const seen = new Set();
  multi.variants.forEach((variant, position) => {
    const weapon = skills._weaponById[variant.weaponIds[0]];
    assert.equal(weapon.skillVariants[String(multi.id)], position, "variant 的下标必须就是武器的 skillVariants[战技 ID]");
    assert.equal(R.variantIndexFor(multi, weapon), position);
    const hits = R.selectHits(multi, weapon);
    assert.equal(hits.length, variant.atkIds.length);
    hits.forEach((hit) => assert.ok(variant.atkIds.indexOf(hit.atkId) !== -1));
    assert.ok(hits.length < multi.hits.length || multi.variants.length === 1, "取并集会把段数撑到全表");
    hits.forEach((hit) => seen.add(hit.atkId));
  });
  assert.ok(seen.size <= multi.hits.length);

  // 全量：每个 (战技, 武器) 对（固定与局内战技池）都由 skillVariants 指到含这把武器的那一套。
  let pairs = 0;
  skills.skills.forEach((skill) => {
    if (!(skill.variants || []).length) return;
    (skill.weaponIds || []).forEach((id) => {
      const weapon = skills._weaponById[id];
      const position = R.variantIndexFor(skill, weapon);
      assert.ok(position >= 0, skill.id + " × " + id + " 找不到动作套");
      assert.equal(position, weapon.skillVariants[String(skill.id)]);
      assert.ok(skill.variants[position].weaponIds.indexOf(id) !== -1, skill.id + " × " + id + " 指错了套");
      assert.deepEqual(R.selectHits(skill, weapon).map((hit) => hit.atkId).sort(),
        skill.hits.filter((hit) => skill.variants[position].atkIds.indexOf(hit.atkId) !== -1).map((hit) => hit.atkId).sort());
      if (weapon.swordArtsParamId === skill.id) assert.equal(weapon.skillVariant, position, "固定战技的旧 skillVariant 与 skillVariants 一致");
      pairs += 1;
    });
  });
  assert.ok(pairs > 6000, "局内战技池的武器也要逐对验到（本版本 6567 对）");
});

test("selectHits：局内战技池抽到的战技不能套用武器固定战技的 skillVariant", () => {
  // 1080000 蝎尾针：固定战技 109 连击（skillVariant=1），局内还能抽到 103 回旋斩（skillVariants["103"]=0）。
  // 旧写法拿 skillVariant 去套 103，会选到别的武器类别的那一套动作。
  const weapon = skills._weaponById[1080000];
  const pool = skills._skillById[103];
  assert.ok(weapon && pool);
  assert.notEqual(weapon.swordArtsParamId, 103);
  assert.equal(typeof weapon.skillVariant, "number");
  const own = weapon.skillVariants["103"];
  assert.equal(typeof own, "number");
  assert.notEqual(own, weapon.skillVariant, "这个例子要能区分两种写法");
  assert.equal(R.variantIndexFor(pool, weapon), own);
  assert.deepEqual(R.selectHits(pool, weapon).map((hit) => hit.atkId), pool.hits
    .filter((hit) => pool.variants[own].atkIds.indexOf(hit.atkId) !== -1).map((hit) => hit.atkId));

  // 回退规则：缺 skillVariants 条目时才用 skillVariant，而且只对武器的固定战技（swordArtsParamId）。
  const skill = { id: 7, hits: [{ atkId: 1 }, { atkId: 2 }], variants: [{ atkIds: [1], weaponIds: [9] }, { atkIds: [2], weaponIds: [9] }] };
  assert.equal(R.variantIndexFor(skill, { id: 9, skillVariants: { 7: 1 }, skillVariant: 0, swordArtsParamId: 7 }), 1, "skillVariants 优先");
  assert.equal(R.variantIndexFor(skill, { id: 9, skillVariants: {}, skillVariant: 1, swordArtsParamId: 7 }), 1, "缺条目时回退固定战技的 skillVariant");
  assert.equal(R.variantIndexFor(skill, { id: 9, skillVariant: 1, swordArtsParamId: 7 }), 1, "旧数据没有 skillVariants 也回退");
  assert.equal(R.variantIndexFor(skill, { id: 9, skillVariants: {}, skillVariant: 1, swordArtsParamId: 8 }), -1,
    "skillVariant 只指固定战技，不能拿去套别的战技");
  assert.deepEqual(R.selectHits(skill, { id: 9, skillVariants: {}, skillVariant: 1, swordArtsParamId: 8 }), []);
});

test("selectVariant / selectHits：武器的 skillVariants 里没有这个战技就是打不出段", () => {
  const skill = skills.skills.find((one) => Array.isArray(one.variants) && one.variants.length);
  assert.equal(R.selectVariant(skill, {}), null);
  assert.deepEqual(R.selectHits(skill, {}), []);
  assert.deepEqual(R.selectHits(skill, null), []);
  assert.deepEqual(R.selectHits({ hits: [] }, {}), []);
  const outOfRange = {};
  outOfRange[String(skill.id)] = skill.variants.length;
  assert.equal(R.selectVariant(skill, { skillVariants: outOfRange }), null, "越界的下标同样打不出段");
});

test("selectHits：没有 variants 时退回 ctx 单选（武器名 → 类别 → ctx 缺失）", () => {
  const skill = {
    hits: [
      { atkId: 1, ctx: "Dagger" },
      { atkId: 2, ctx: "Reduvia" },
      { atkId: 3 }
    ]
  };
  assert.deepEqual(
    R.selectHits(skill, { nameEn: "Reduvia", wepTypeEn: "Dagger" }).map((hit) => hit.atkId),
    [2],
    "武器名优先"
  );
  assert.deepEqual(
    R.selectHits(skill, { nameEn: "Misericorde", wepTypeEn: "Dagger" }).map((hit) => hit.atkId),
    [1],
    "退到武器类别"
  );
  assert.deepEqual(
    R.selectHits(skill, { nameEn: "X", wepTypeEn: "Y" }).map((hit) => hit.atkId),
    [3],
    "最后才用 ctx 缺失的那组"
  );

  // 回退路径直接读 hits[]：TAE 判为打不出的段（notInvoked）与不带伤害的段（noDamage）一律剔掉。
  const tae = {
    hits: [
      { atkId: 11, ctx: "Dagger", notInvoked: true, notInvokedReason: "gated" },
      { atkId: 12, ctx: "Dagger", noDamage: true },
      { atkId: 13, ctx: "Dagger" },
      { atkId: 14, notInvoked: true },
      { atkId: 15 }
    ]
  };
  assert.deepEqual(R.selectHits(tae, { nameEn: "Misericorde", wepTypeEn: "Dagger" }).map((hit) => hit.atkId), [13]);
  assert.deepEqual(R.selectHits(tae, { nameEn: "X", wepTypeEn: "Y" }).map((hit) => hit.atkId), [15]);
  const onlyDead = { hits: [{ atkId: 21, ctx: "Dagger", notInvoked: true }, { atkId: 22 }] };
  assert.deepEqual(R.selectHits(onlyDead, { wepTypeEn: "Dagger" }).map((hit) => hit.atkId), [22],
    "剔掉 notInvoked 之后这一类没有段，才往下退");
  assert.deepEqual(R.invokedHits(tae.hits).map((hit) => hit.atkId), [12, 13, 15]);
});

test("hitOverridesFor：「全选」只勾当前这一侧，正常版与专注值不足版不会同时计入", () => {
  const hits = [
    { atkId: 1 },
    { atkId: 2, noFp: true },
    { atkId: 3, noDamage: true }
  ];
  const all = R.hitOverridesFor(hits, "all", false);
  assert.equal(all[1], true);
  assert.equal(all[2], false, "专注值不足版与正常版互为替代，一起勾会把同一击算两遍");
  assert.equal(3 in all, false, "noDamage 段不参与");

  const allNoFp = R.hitOverridesFor(hits, "all", true);
  assert.equal(allNoFp[1], false);
  assert.equal(allNoFp[2], true);

  assert.deepEqual(R.hitOverridesFor(hits, "none", false), { 1: false, 2: false });
  assert.deepEqual(R.hitOverridesFor(hits, "reset", false), {}, "恢复默认＝清空 override");

  // fpBoth：两侧动画都会打出的段，开关在哪一侧都勾上（取段规则 hit.fpBoth || noFp 同侧）。
  const shared = hits.concat([{ atkId: 4, fpBoth: true }]);
  assert.equal(R.hitOverridesFor(shared, "all", false)[4], true);
  assert.equal(R.hitOverridesFor(shared, "all", true)[4], true, "专注值不足侧也要计入 fpBoth 段");
  assert.equal(R.hitOnSide({ fpBoth: true }, true), true);
  assert.equal(R.hitOnSide({ fpBoth: true }, false), true);
  assert.equal(R.hitOnSide({ noFp: true }, false), false);
  assert.equal(R.hitOnSide({}, true), false);

  // 真实数据：全选之后相对值合计不会翻倍（= 与默认勾选一致）。
  const weapon = skills.weapons.find((one) => typeof one.skillVariant === "number" &&
    skills.skills.some((skill) => (skill.weaponIds || []).indexOf(one.id) !== -1 &&
      R.selectHits(skill, one).some((hit) => hit.noFp)));
  assert.ok(weapon, "数据集里应当有带专注值不足版本的战技");
  const skill = skills.skills.find((one) => (one.weaponIds || []).indexOf(weapon.id) !== -1 &&
    R.selectHits(one, weapon).some((hit) => hit.noFp));
  const picked = R.selectHits(skill, weapon);
  const overrides = R.hitOverridesFor(picked, "all", false);
  const chosen = picked.filter((hit) => overrides[hit.atkId] === true);
  const fallback = picked.filter((hit) => !hit.noDamage && !hit.noFp);
  assert.deepEqual(chosen.map((hit) => hit.atkId), fallback.map((hit) => hit.atkId));
  assert.equal(
    R.composition(chosen, weapon, false).total,
    R.composition(fallback, weapon, false).total
  );
});

// ------------------------------------------------------------------ 伤害类型

test("physicalTypeForHit：253 / 252 回查武器的 atkAttribute / atkAttribute2", () => {
  const weapon = { atkAttribute: 2, atkAttribute2: 1 };
  assert.equal(R.physicalTypeForHit({ attribute: "WeaponAtkAttribute" }, weapon), "thrust");
  assert.equal(R.physicalTypeForHit({ attribute: "WeaponAtkAttribute2" }, weapon), "blow");
  assert.equal(R.physicalTypeForHit({ attribute: "Slash" }, weapon), "slash");
  assert.equal(R.physicalTypeForHit({ attribute: "Standard" }, weapon), "neutral");
  assert.equal(R.physicalTypeForHit({ attribute: "None" }, weapon), "physNone");
  assert.equal(R.physicalTypeForHit({ attribute: "WeaponAtkAttribute" }, {}), "physNone");
});

test("数据集里确实有大量走 Weapon* 间接引用的段（页面必须走这一步）", () => {
  let indirect = 0;
  skills.skills.forEach((skill) => {
    (skill.hits || []).forEach((hit) => {
      if (hit.attribute === "WeaponAtkAttribute" || hit.attribute === "WeaponAtkAttribute2") indirect += 1;
    });
  });
  assert.ok(indirect > 0, "有 Weapon* 段就必须回查 weapons[].atkAttribute");
  assert.ok(skills.weapons.every((weapon) => typeof weapon.atkAttribute === "number"));
  assert.ok(skills.weapons.every((weapon) => typeof weapon.atkAttribute2 === "number"));
});

// ------------------------------------------------------------------ 伤害构成

test("usesMotion：只有法术段忽略动作值，战技的子弹段照常乘武器攻击力", () => {
  assert.equal(R.usesMotion({}, false), true);
  assert.equal(R.usesMotion({}, true), false, "法术段不得把 motion 乘到施法器攻击力上");
  // usage「法术 / 子弹段」的结论是「motion 只在施法器该属性 attackBase 非 0 时才有意义」，
  // 战技的子弹段挂的是真武器，motion 是真实动作值，不能一并忽略。
  assert.equal(R.usesMotion({ isBullet: true }, false), true);
  assert.equal(R.usesMotion({ isBullet: true }, true), false);
});

test("hitContribution：武器段 = 攻击力 × motion/100 + flat，addBaseAtk 再加一份", () => {
  const weapon = { attackBase: { physical: 100, fire: 50 } };
  const hit = { attribute: "Slash", motion: { physical: 200, fire: 100 }, flat: { fire: 7 } };
  const plain = R.hitContribution(hit, weapon, false);
  assert.equal(plain.slash, 200);
  assert.equal(plain.fire, 57);

  const withBase = R.hitContribution(Object.assign({ addBaseAtk: true }, hit), weapon, false);
  assert.equal(withBase.slash, 300);

  // 子弹段走同一条路：motion 与 addBaseAtk 都算。
  const bullet = R.hitContribution(Object.assign({ isBullet: true, addBaseAtk: true }, hit), weapon, false);
  assert.equal(bullet.slash, 300);
  assert.equal(bullet.fire, 107);

  // 同一段当成法术段来算：motion 被忽略，只剩 flat。
  const asSpell = R.hitContribution(hit, weapon, true);
  assert.equal(asSpell.slash, 0);
  assert.equal(asSpell.fire, 7);

  // noDamage 段（只挂 spEffect）完全不计入。
  assert.equal(R.hitContribution(Object.assign({ noDamage: true }, hit), weapon, false).slash, 0);
});

test("hitChipPlan：分段芯片只留对当前武器真正有贡献的属性", () => {
  const weapon = { attackBase: { physical: 100, fire: 50 }, atkAttribute: 0, atkAttribute2: 0 };
  // 参数表里五属性同值，但武器只有物理与火 → 魔力／雷／圣三项乘出来恒为 0。
  const hit = {
    attribute: "Slash",
    motion: { physical: 99, magic: 99, fire: 99, lightning: 99, holy: 99 }
  };
  const plan = R.hitChipPlan(hit, weapon, false);
  assert.deepEqual(plan.chips.map((chip) => chip.type), ["slash", "fire"]);
  assert.equal(plan.hidden, 3, "被隐藏的三项要数出来，行末才补得上那句小字");

  // flat 会让一个 attackBase 为 0 的属性重新有贡献。
  const withFlat = R.hitChipPlan(Object.assign({ flat: { holy: 20 } }, hit), weapon, false);
  assert.deepEqual(withFlat.chips.map((chip) => chip.type), ["slash", "fire", "holy"]);
  assert.equal(withFlat.hidden, 2);

  // 顺序固定为 物理子类型 → 魔力 → 火 → 雷 → 圣（与 macOS 端 SkillDamageChannel 一致）。
  const full = { attackBase: { physical: 10, magic: 10, fire: 10, lightning: 10, holy: 10 } };
  assert.deepEqual(
    R.hitChipPlan(hit, Object.assign({ atkAttribute: 0, atkAttribute2: 0 }, full), false)
      .chips.map((chip) => chip.type),
    ["slash", "magic", "fire", "lightning", "holy"]
  );

  // 法术段只用 flat：motion 一项都不显示，也不算「被隐藏」（缺席的原因不是武器为 0）。
  const spellHit = { attribute: "None", motion: { physical: 100, magic: 100, fire: 100 }, flat: { magic: 152 } };
  const spellPlan = R.hitChipPlan(spellHit, null, true);
  assert.deepEqual(spellPlan.chips.map((chip) => chip.type), ["magic"]);
  assert.equal(spellPlan.hidden, 0);

  // 全部属性都无贡献 → 没有芯片，渲染侧退回「无伤害数值」。
  const dead = R.hitChipPlan({ attribute: "Slash", motion: { magic: 99 } }, weapon, false);
  assert.equal(dead.chips.length, 0);

  // noDamage 段整段短路：不出芯片，也不数 hidden（与 macOS 端 segment() 的
  // `for element in ... where !hit.noDamage` 同一口径）。
  const noDamage = R.hitChipPlan(Object.assign({ noDamage: true }, hit), weapon, false);
  assert.deepEqual(noDamage, { chips: [], hidden: 0 });
});

test("hitChipPlan：只靠 addBaseAtk 出伤害的属性也要出芯片", () => {
  // 113 主教冲锋 + 23000600 雷电主教大火槌的 #30000831 就是这个形状：数据里只有
  // flat.fire = 55，标准（段自己声明 attribute=Standard）与雷两条通道全部来自
  // addBaseAtk（额外一份武器该属性攻击力）。
  // 漏掉它们，芯片行会把一段 219 的伤害显示成「火 固定 55」。
  const weapon = { attackBase: { physical: 82, lightning: 82 }, atkAttribute: 1, atkAttribute2: 1 };
  const hit = { attribute: "Standard", addBaseAtk: true, flat: { fire: 55 } };
  const plan = R.hitChipPlan(hit, weapon, false);
  assert.deepEqual(plan.chips.map((chip) => chip.type), ["neutral", "fire", "lightning"]);
  assert.equal(plan.hidden, 0, "这几项不是「武器为 0」，不该触发行末那句小字");

  const physical = plan.chips[0];
  assert.equal(physical.motion, null, "数据里没写 motion → null，展示侧不出这一格");
  assert.equal(physical.flat, null);
  assert.equal(physical.baseAttack, 82, "「+基础攻击力」这一格的来源");

  // 可见芯片之和 == 这一段的真实总量（219 = 打击 82 + 雷 82 + 火 55）。
  const contribution = R.hitContribution(hit, weapon, false);
  const visible = plan.chips.reduce((sum, chip) => sum + contribution[chip.type], 0);
  const total = R.TYPE_KEYS.reduce((sum, key) => sum + contribution[key], 0);
  assert.equal(total, 219);
  assert.equal(visible, total);

  // 整段只靠 addBaseAtk：照样出芯片，不能退回「无伤害数值」。
  const onlyBase = R.hitChipPlan({ attribute: "Standard", addBaseAtk: true }, weapon, false);
  assert.deepEqual(onlyBase.chips.map((chip) => chip.type), ["neutral", "lightning"]);

  // addBaseAtk 碰上 attackBase 为 0 的属性不算一条通道（macOS 端的 `base > 0` 同理）。
  assert.deepEqual(
    R.hitChipPlan({ attribute: "Standard", addBaseAtk: true }, { attackBase: {} }, false).chips,
    []
  );
});

test("真实数据：可见芯片的相对值之和恒等于该段总量（隐藏只发生在展示层）", () => {
  // 这条是「芯片＝真正有贡献的属性」这个承诺的全量版本，对所有可达的（段 × 武器）
  // 与全部法术段逐对验；macOS 端 checkSegmentChips 有同一条断言，两端一起钉住。
  let pairs = 0;
  let withHidden = 0;
  let onlyBaseAtk = 0;
  const check = (hit, weapon, isSpell, where) => {
    pairs += 1;
    const plan = R.hitChipPlan(hit, weapon, isSpell);
    const contribution = R.hitContribution(hit, weapon, isSpell);
    const total = R.TYPE_KEYS.reduce((sum, key) => sum + contribution[key], 0);
    const visible = plan.chips.reduce((sum, chip) => sum + contribution[chip.type], 0);
    assert.equal(visible, total, where + "：可见芯片之和应当等于整段总量");
    assert.equal(
      plan.chips.length === 0, !(total > 0),
      where + "：有伤害就必须至少有一个芯片，没伤害才退回「无伤害数值」"
    );
    if (plan.hidden > 0) withHidden += 1;
    if (plan.chips.some((chip) => chip.motion === null && chip.flat === null)) onlyBaseAtk += 1;
  };

  for (const skill of skills.skills) {
    for (const weapon of R.weaponsForSkill(skills, skill)) {
      for (const hit of R.selectHits(skill, weapon)) check(hit, weapon, false, "段 " + hit.atkId);
    }
  }
  for (const spell of skills.spells) {
    for (const hit of spell.hits || []) check(hit, null, true, "法术段 " + hit.atkId);
  }

  assert.ok(pairs > 30000, "对照样本太少说明遍历写错了（本版本含局内战技池的武器，35564 对）");
  assert.ok(withHidden > 0, "真实数据里应当有「其余属性该武器为 0」的段，否则这一关是空跑");
  assert.ok(onlyBaseAtk > 0, "真实数据里应当有只靠 addBaseAtk 出伤害的通道，否则这一关是空跑");
});

test("真实数据：尸横遍野 + 尸山血海 每段只剩「斩击 + 火」两个属性芯片", () => {
  const weapon = skills._weaponById[9040000];
  const skill = skills.skills.find((one) => one.id === 1177);
  assert.ok(weapon && skill, "对照用例的武器 9040000 / 战技 1177 必须在数据集里");
  const base = weapon.attackBase || {};
  assert.ok(Number(base.physical) > 0 && Number(base.fire) > 0);
  ["magic", "lightning", "holy"].forEach((key) => {
    assert.ok(!(Number(base[key]) > 0), key + " 的基础攻击力应当是 0");
  });

  const hits = R.selectHits(skill, weapon);
  assert.ok(hits.length > 0);
  hits.forEach((hit) => {
    const plan = R.hitChipPlan(hit, weapon, false);
    assert.deepEqual(
      plan.chips.map((chip) => chip.type),
      ["slash", "fire"],
      "段 " + hit.atkId + " 只应显示斩击与火"
    );
    assert.equal(plan.hidden, 3, "段 " + hit.atkId + " 有三项被隐藏");
  });
});

test("真实数据：某个法术段只显示带 flat 的那些属性", () => {
  const spell = skills.spells.find((one) => one.id === 4021);
  assert.ok(spell, "帚星（4021）必须在数据集里");
  const hit = (spell.hits || []).find((one) => !one.noDamage &&
    one.flat && Object.keys(one.flat).length > 0);
  assert.ok(hit, "帚星应当有带 flat 的命中段");
  const plan = R.hitChipPlan(hit, null, true);
  assert.ok(plan.chips.length > 0);
  assert.equal(plan.hidden, 0, "法术段不用 motion，缺席的属性不算「武器为 0」");
  const flatKeys = Object.keys(hit.flat).filter((key) => Number(hit.flat[key]) > 0);
  assert.equal(plan.chips.length, flatKeys.length, "芯片数应当等于 flat > 0 的属性数");
  plan.chips.forEach((chip) => {
    assert.ok(chip.flat > 0, "法术段的每个芯片都来自 flat");
    assert.equal(chip.motion, null, "法术段不显示动作值（没声明就是 null，不是 0）");
    assert.equal(chip.baseAttack, null, "法术段没有武器，addBaseAtk 也无从加起");
  });
});

test("zhFpText：展示层把数据集原文里的 FP 一律换成中文说法", () => {
  // ① 段名（hits[].labelZh，本版本 375 段；v3 按 TAE 补标的无 FP 段也以「无FP版」开头）。
  assert.equal(R.zhFpText("无FP版 L2 第1段-第1击"), "专注值不足版 L2 第1段-第1击");
  assert.equal(R.zhFpText("无 FP 版 R2"), "专注值不足版 R2");
  assert.equal(R.zhFpText("L2 第3段"), "L2 第3段", "不含 FP 的标签原样返回");
  assert.equal(R.zhFpText(undefined), "", "缺标签时返回空串，交给后面的兜底");
  // 全角空格也要吃下——两端同一套正则，数据集换写法时不能只有一端替换掉。
  assert.equal(R.zhFpText("无　FP版 R2"), "专注值不足版 R2");

  // ② 底部「数据说明」里的 caveats 原文。
  assert.equal(
    R.zhFpText("12 段（6 段带 FP + 6 段 No FP）就是全部"),
    "12 段（6 段正常版 + 6 段专注值不足版）就是全部"
  );
  const caveats = skills.caveats || [];
  assert.ok(caveats.some((text) => text.indexOf("FP") !== -1), "数据集原文里确实还有 FP");
  caveats.forEach((text) => {
    assert.equal(R.zhFpText(text).indexOf("FP"), -1, "页面上不该再出现英文 FP");
  });
  // 数据集本身不动：noFp 字段与 labelZh 原文都还在。
  const skill = skills.skills.find((one) => one.id === 1177);
  const raw = (skill.hits || []).filter((hit) => hit.noFp === true);
  assert.ok(raw.length > 0);
  assert.ok(raw.every((hit) => (hit.labelZh || "").indexOf("无FP版") === 0), "数据集原文保持不变");
});

test("真实数据：可达的子弹段能算出构成（只有 motion 的子弹段不得被整段归零）", () => {
  // 取一个「可达 + 子弹 + 带 motion + 武器该属性 attackBase > 0」的战技 / 武器组合，
  // 它的构成必须算得出来；把子弹段忽略 motion 会让这类组合彻底变成死路。
  let sample = null;
  for (const skill of skills.skills) {
    if (!Array.isArray(skill.hits) || !skill.hits.length) continue;
    for (const weaponId of skill.weaponIds || []) {
      const weapon = skills._weaponById[weaponId];
      if (!weapon) continue;
      const hits = R.selectHits(skill, weapon);
      const bullets = hits.filter((hit) => hit.isBullet && !hit.noDamage && hit.motion &&
        Object.keys(hit.motion).some((el) => Number(hit.motion[el]) > 0 &&
          Number((weapon.attackBase || {})[el]) > 0));
      if (bullets.length) { sample = { skill, weapon, hits, bullets }; break; }
    }
    if (sample) break;
  }
  assert.ok(sample, "数据集里应当有可达的、带 motion 的战技子弹段");

  const onlyBullets = R.composition(sample.bullets, sample.weapon, false);
  assert.equal(onlyBullets.hasDamage, true, "子弹段自己就应当算得出非 0 相对值");

  const all = R.composition(sample.hits.filter((hit) => !hit.noFp), sample.weapon, false);
  assert.equal(all.hasDamage, true);

  // 全表：可达的子弹段里有相当一部分只有 motion 没有 flat，忽略 motion 会把它们算成 0。
  let motionOnly = 0;
  skills.skills.forEach((skill) => {
    const seen = new Set();
    (skill.weaponIds || []).forEach((weaponId) => {
      const weapon = skills._weaponById[weaponId];
      if (!weapon) return;
      R.selectHits(skill, weapon).forEach((hit) => {
        if (!hit.isBullet || seen.has(hit.atkId)) return;
        seen.add(hit.atkId);
        const hasMotion = hit.motion && Object.keys(hit.motion).length > 0;
        const hasFlat = hit.flat && Object.keys(hit.flat).length > 0;
        if (hasMotion && !hasFlat) motionOnly += 1;
      });
    });
  });
  assert.ok(motionOnly > 0, "可达的子弹段里应当有『只有 motion 没有 flat』的，正是被归零的那一批");
});

test("真实数据：每个进入列表的战技 / 法术都至少有一种选法算得出构成", () => {
  const items = R.buildMeansItems(skills);
  items.forEach((item) => {
    if (item.kind === "skill") {
      assert.equal(R.skillHasDamage(skills, skills._skillById[item.id]), true,
        item.nameZh + " 进了列表却算不出构成");
      return;
    }
    const spell = skills._spellById[item.id];
    assert.equal(R.hasAnyDamage(spell.hits, null, true), true, item.nameZh + " 进了列表却算不出构成");
  });
});

test("composition：占比之和为 1，noDamage 段不参与", () => {
  const weapon = { attackBase: { physical: 100, fire: 100 }, atkAttribute: 0 };
  const comp = R.composition([
    { attribute: "WeaponAtkAttribute", motion: { physical: 100 } },
    { attribute: "None", motion: { fire: 100 } },
    { attribute: "Slash", motion: { physical: 999 }, noDamage: true }
  ], weapon, false);
  assert.equal(comp.hasDamage, true);
  const sum = R.TYPE_KEYS.reduce((total, key) => total + comp.shares[key], 0);
  assert.ok(Math.abs(sum - 1) < 1e-9);
  assert.equal(comp.shares.slash, 0.5);
  assert.equal(comp.shares.fire, 0.5);

  const empty = R.composition([], weapon, false);
  assert.equal(empty.hasDamage, false);
  assert.equal(empty.total, 0);
});

test("真实数据：物理 + 属性武器的战技构成里两边占比都大于 0", () => {
  const weapon = firstMixedWeapon();
  assert.ok(weapon, "数据集里应当有同时带物理与属性攻击力的武器");
  const skill = skillOf(weapon);
  assert.ok(skill, "这把武器应当能找到它的战技");
  const hits = R.selectHits(skill, weapon).filter((hit) => !hit.noFp);
  assert.ok(hits.length > 0);
  const comp = R.composition(hits, weapon, false);
  assert.equal(comp.hasDamage, true);
  const physical = R.TYPES_BY_ELEMENT.physical.reduce((sum, key) => sum + comp.shares[key], 0);
  const elemental = ["magic", "fire", "lightning", "holy"].reduce((sum, key) => sum + comp.shares[key], 0);
  assert.ok(physical > 0, "物理占比应当大于 0");
  assert.ok(elemental > 0, "属性占比应当大于 0");
});

test("真实数据：法术的构成只由固定值决定，不会凭空多出物理", () => {
  const spell = skills.spells.find((one) => (one.hits || []).some((hit) => hit.flat && hit.flat.magic > 0));
  assert.ok(spell, "数据集里应当有带魔力固定伤害的法术");
  const comp = R.composition(spell.hits, null, true);
  assert.ok(comp.shares.magic > 0);
  const physical = R.TYPES_BY_ELEMENT.physical.reduce((sum, key) => sum + comp.shares[key], 0);
  assert.equal(physical, 0, "辉石杖的 attackBase 只有 physical，乘上去会凭空造出物理伤害");
});

test("削韧 / 削精力：poise + 武器基础 × mv / 100", () => {
  const weapon = { poiseDamageBase: 10, staminaBase: 40 };
  assert.equal(R.hitPoise({ poise: 5, poiseMv: 200 }, weapon), 25);
  assert.equal(R.hitStamina({ stamina: 2, staminaMv: 50 }, weapon), 22);
  assert.equal(R.hitPoise({}, weapon), 0);
});

test("multiplierMap：只收 countsAsDamage 的乘数字段，非默认值才乘", () => {
  const plan = index.plan;
  const table = R.multiplierMap({
    physicsAttackRate: 1.1,
    magicAttackRate: 1,            // 等于默认值 → 不乘
    saAttackPowerRate: 2,          // 削韧 → 不乘
    bloodAttackPower: 30,          // 异常累积 → 不乘
    weakDmgRateB: 10,              // 特攻（conditionalDamage）→ 不乘
    restageAttackRate: 0.6         // special → 不乘
  }, plan, null);
  R.TYPES_BY_ELEMENT.physical.forEach((type) => {
    assert.ok(Math.abs(table[type] - 1.1) < 1e-9, type + " 应当吃到物理倍率");
  });
  assert.equal(table.magic, 1);
  assert.equal(table.fire, 1);
  assert.equal(table.holy, 1);

  const used = [];
  R.multiplierMap({ fireAttackRate: 1.25, physicsAttackRate: 0 }, plan, used);
  assert.deepEqual(used.map((field) => field.key), ["fireAttackRate"], "0 不是合法乘数，必须跳过");
});

// ------------------------------------------------------------------ 输出手段列表与显示名

test("buildMeansItems / filterMeans：中英文都能搜到，且只收算得出构成的条目", () => {
  const items = R.buildMeansItems(skills);
  assert.ok(items.length > 0);
  assert.ok(items.some((item) => item.kind === "skill"));
  assert.ok(items.some((item) => item.kind === "sorcery"));
  assert.ok(items.some((item) => item.kind === "incantation"));

  // 收录口径：有命中段 + （战技）至少一把武器（固定或局内战技池）+ 至少能算出一段非 0 相对值。
  // 算不出构成的条目选中后只会停在「当前没有勾选任何带伤害的段」，是死路。
  const skillIds = new Set(items.filter((item) => item.kind === "skill").map((item) => item.id));
  skills.skills.forEach((skill) => {
    const usable = (skill.hits || []).length > 0 && (skill.weaponIds || []).length > 0 &&
      R.skillHasDamage(skills, skill);
    assert.equal(skillIds.has(skill.id), usable, skill.id + " 的收录判定不对");
  });
  // v3 把局内战技池算进 weaponIds 后，没有武器的只剩占位条目（1 无战技、9999 ？？？），它们也没有命中段；
  // 「有段但没有武器」这条排除规则仍然保留，用合成数据钉住。
  const weaponless = skills.skills.filter((skill) => !(skill.weaponIds || []).length);
  assert.deepEqual(weaponless.map((skill) => skill.id), [1, 9999], "没有武器的只剩两个占位条目");
  weaponless.forEach((skill) => assert.equal((skill.hits || []).length, 0, skill.id + " 是占位条目，不该有命中段"));
  const orphanHit = { atkId: 1, attribute: "Slash", motion: { physical: 100 } };
  const synthetic = R.decorateSkills({
    weapons: [{ id: 5, attackBase: { physical: 100 }, atkAttribute: 0, atkAttribute2: 0, skillVariants: { 71: 0 } }],
    skills: [
      { id: 70, nameZh: "有段无武器", hits: [orphanHit], variants: [{ atkIds: [1], weaponIds: [] }], weaponIds: [] },
      { id: 71, nameZh: "有段有武器", hits: [orphanHit], variants: [{ atkIds: [1], weaponIds: [5] }], weaponIds: [5] }
    ],
    spells: []
  });
  assert.deepEqual(R.buildMeansItems(synthetic).map((item) => item.id), [71], "有段但没有武器的战技选不出武器，不进列表");
  assert.deepEqual(R.meansWithoutDamage(synthetic), { skills: 0, spells: 0 }, "没有武器的不算「算不出构成」");

  // 只在局内战技池里出现的战技（v2 里一把武器都没有）现在能选：风暴刃 210、狩猎巨人 116。
  [210, 116].forEach((id) => {
    const skill = skills._skillById[id];
    assert.ok((skill.weaponSources || []).every((one) => one.fixed !== true && one.pool.length > 0), id + " 只来自战技池");
    assert.ok(skillIds.has(id), id + " 应当进输出手段列表");
  });

  // 法术同一条口径：有段但一个固定值都没有的（恢复／庇佑类）不得进列表。
  const spellIds = new Set(items.filter((item) => item.kind !== "skill").map((item) => item.id));
  const deadSpells = skills.spells.filter((spell) =>
    (spell.hits || []).length > 0 && !R.hasAnyDamage(spell.hits, null, true));
  assert.ok(deadSpells.length > 0, "数据集里应当确实存在『有段但算不出伤害』的法术");
  deadSpells.forEach((spell) => {
    assert.equal(spellIds.has(spell.id), false, (spell.nameZh || spell.id) + " 选中后构成恒为 0，不该进列表");
  });

  const sample = items.find((item) => item.kind === "skill" && item.nameZh && item.nameEn);
  assert.ok(filterMeansHas(items, sample.nameZh, "skill", sample.id));
  assert.ok(filterMeansHas(items, sample.nameEn.toUpperCase(), "skill", sample.id), "英文搜索要忽略大小写");
  assert.equal(R.filterMeans(items, "", "spell").every((item) => item.kind !== "skill"), true);
  assert.equal(R.filterMeans(items, "", "skill").every((item) => item.kind === "skill"), true);
});

function filterMeansHas(items, query, kind, id) {
  return R.filterMeans(items, query, kind).some((item) => item.id === id);
}

test("groupWeapons：按武器类别中文名分组，组内保持原顺序", () => {
  const multi = skills.skills.find((skill) => (skill.weaponIds || []).length > 5);
  const weapons = R.weaponsForSkill(skills, multi);
  assert.equal(weapons.length, multi.weaponIds.length);
  const groups = R.groupWeapons(weapons);
  assert.ok(groups.length > 0);
  const flat = groups.reduce((total, group) => total + group.weapons.length, 0);
  assert.equal(flat, weapons.length);
  groups.forEach((group) => {
    group.weapons.forEach((weapon) => {
      assert.equal(weapon.wepTypeZh || weapon.wepTypeEn || "未分类", group.label);
    });
  });
});

// ------------------------------------------------------------------ v3：局内战技池、TAE 核实、fpBoth

// 按「使用专注值不足版本」开关取一侧的带伤害段（页面默认勾选的口径：hit.fpBoth || noFp 与开关同侧）。
function sideHits(skill, weapon, noFp) {
  return R.selectHits(skill, weapon).filter((hit) => !hit.noDamage && R.hitOnSide(hit, noFp));
}

test("v3：风暴刃 210 能选到武器，专注值正常侧 3 段＋1 段子弹、不足侧 3 段，两侧不相加", () => {
  const skill = skills._skillById[210];
  const weapons = R.weaponsForSkill(skills, skill);
  assert.equal(weapons.length, skill.weaponIds.length);
  assert.ok(weapons.length > 0, "局内战技池的武器要选得到");
  weapons.forEach((weapon) => {
    assert.equal(R.weaponSourceOf(skill, weapon), "pool");
    const fp = sideHits(skill, weapon, false);
    const noFp = sideHits(skill, weapon, true);
    assert.equal(fp.filter((hit) => !hit.isBullet).length, 3, weapon.id + " 正常侧应是 3 段近战");
    assert.equal(fp.filter((hit) => hit.isBullet).length, 1, weapon.id + " 正常侧另有 1 段飞刃子弹");
    assert.equal(noFp.length, 3, weapon.id + " 专注值不足侧 3 段");
    assert.ok(noFp.every((hit) => hit.noFp === true && !hit.isBullet));
    const fpIds = new Set(fp.map((hit) => hit.atkId));
    assert.ok(noFp.every((hit) => !fpIds.has(hit.atkId)), "两侧互为替代，不共段");
  });
  // 411–413 是 TAE 补标的无 FP 段：行名没写 No FP，labelZh 补了「无FP版」。
  [300000411, 300000412, 300000413].forEach((id) => {
    const hit = skill.hits.find((one) => one.atkId === id);
    assert.equal(hit.noFp, true);
    assert.equal(hit.noFpSource, "tae");
    assert.equal(hit.labelZh.indexOf("无FP版"), 0);
  });
  const weapon = weapons[0];
  assert.equal(R.composition(sideHits(skill, weapon, false), weapon, false).hasDamage, true);
  assert.equal(R.composition(sideHits(skill, weapon, true), weapon, false).hasDamage, true);
});

test("v3：狩猎巨人 116 专注值正常 / 不足两侧各 1 段", () => {
  const skill = skills._skillById[116];
  const weapons = R.weaponsForSkill(skills, skill);
  assert.ok(weapons.length > 0);
  weapons.forEach((weapon) => {
    assert.equal(R.weaponSourceOf(skill, weapon), "pool");
    assert.deepEqual(sideHits(skill, weapon, false).map((hit) => hit.atkId), [301700910], String(weapon.id));
    assert.deepEqual(sideHits(skill, weapon, true).map((hit) => hit.atkId), [301700915], String(weapon.id));
  });
});

test("v3：狩猎大蛇 1188 只剩两段近战 L2（各带专注值不足版），光之束等 notInvoked 段不进选段", () => {
  const skill = skills._skillById[1188];
  const weapon = skills._weaponById[17030000];
  assert.equal(R.weaponSourceOf(skill, weapon), "fixed");
  const hits = R.selectHits(skill, weapon);
  assert.deepEqual(hits.map((hit) => hit.atkId).sort(), [301703950, 301703951, 301703970, 301703971]);
  assert.deepEqual(sideHits(skill, weapon, false).map((hit) => hit.atkId), [301703950, 301703951]);
  assert.deepEqual(sideHits(skill, weapon, true).map((hit) => hit.atkId), [301703970, 301703971]);
  const dead = skill.hits.filter((hit) => hit.notInvoked === true);
  assert.ok(dead.some((hit) => hit.atkId === 301703900) && dead.some((hit) => hit.atkId === 301703901),
    "光之束两段留在 hits[] 里并标 notInvoked");
  dead.forEach((hit) => assert.equal(hits.indexOf(hit), -1, hit.atkId + " 不该进选段"));
});

test("v3：notInvoked 段在任何武器上都不进选段；selfOrAllyOnly 段恒带 noDamage、不进构成", () => {
  let notInvoked = 0;
  let selfOrAlly = 0;
  skills.skills.forEach((skill) => {
    notInvoked += skill.hits.filter((hit) => hit.notInvoked === true).length;
    R.weaponsForSkill(skills, skill).forEach((weapon) => {
      R.selectHits(skill, weapon).forEach((hit) => {
        assert.notEqual(hit.notInvoked, true, skill.id + " × " + weapon.id + " 选进了 " + hit.atkId);
      });
    });
    skill.hits.filter((hit) => hit.selfOrAllyOnly === true).forEach((hit) => {
      selfOrAlly += 1;
      assert.equal(hit.noDamage, true, hit.atkId + " 只打自己 / 队友，必须带 noDamage");
      const one = R.hitContribution(hit, { attackBase: { physical: 100, magic: 100, fire: 100, lightning: 100, holy: 100 } }, false);
      assert.ok(R.TYPE_KEYS.every((key) => one[key] === 0));
      assert.equal(hit.atkId in R.hitOverridesFor([hit], "all", false), false, "全选也不勾");
    });
  });
  assert.equal(notInvoked, skills.counts.hitsNotInvoked, "notInvoked 段数与数据集 counts 一致");
  assert.ok(notInvoked > 0 && selfOrAlly > 0);
});

test("v3：fpBoth 段两侧都计——专注值不足侧不会丢掉两侧共用的段", () => {
  let fpBoth = 0;
  skills.skills.forEach((skill) => skill.hits.forEach((hit) => {
    if (hit.fpBoth !== true) return;
    fpBoth += 1;
    assert.notEqual(hit.noFp, true, hit.atkId + "：fpBoth 与 noFp 互斥");
  }));
  assert.equal(fpBoth, skills.counts.hitsFpBoth);

  // 1024 唤矛仪式：全部带伤害的段都是两侧共用的子弹。旧写法（noFp 与开关同侧）在专注值不足侧一段都取不到。
  const ritual = skills._skillById[1024];
  const spear = skills._weaponById[ritual.weaponIds[0]];
  const fp = sideHits(ritual, spear, false);
  const noFp = sideHits(ritual, spear, true);
  assert.ok(fp.length > 0 && fp.every((hit) => hit.fpBoth === true));
  assert.deepEqual(noFp.map((hit) => hit.atkId), fp.map((hit) => hit.atkId), "两侧取到同一批段");
  assert.equal(R.composition(noFp, spear, false).hasDamage, true, "专注值不足侧也算得出构成");
  const old = R.selectHits(ritual, spear).filter((hit) => !hit.noDamage && Boolean(hit.noFp) === true);
  assert.equal(old.length, 0, "旧写法在这里会丢段，这个例子才有意义");

  // 218 伟哉卡利亚：300200872 两侧共用，另外各有自己一侧的段。
  const glintblade = skills._skillById[218];
  const weapon = R.weaponsForSkill(skills, glintblade)[0];
  const fpIds = sideHits(glintblade, weapon, false).map((hit) => hit.atkId);
  const noFpIds = sideHits(glintblade, weapon, true).map((hit) => hit.atkId);
  assert.ok(fpIds.indexOf(300200872) !== -1 && noFpIds.indexOf(300200872) !== -1);
  assert.ok(fpIds.length > 1 && noFpIds.length > 1);
  assert.equal(R.hitOverridesFor(R.selectHits(glintblade, weapon), "all", true)[300200872], true);
});

test("v3：武器选择器——固定战技的武器排前、其余按 id，每把武器标「固定战技 / 局内可抽到」（两者都成立只标固定）", () => {
  const lion = skills._skillById[100];
  const weapons = R.weaponsForSkill(skills, lion);
  const sources = weapons.map((weapon) => R.weaponSourceOf(lion, weapon));
  const firstPool = sources.indexOf("pool");
  assert.ok(firstPool > 0, "狮子斩既有固定武器也有局内战技池的武器");
  assert.ok(sources.slice(0, firstPool).every((one) => one === "fixed"));
  assert.ok(sources.slice(firstPool).every((one) => one === "pool"));
  const ascending = (list) => list.every((weapon, i) => i === 0 || list[i - 1].id < weapon.id);
  assert.ok(ascending(weapons.slice(0, firstPool)) && ascending(weapons.slice(firstPool)));
  weapons.slice(0, firstPool).forEach((weapon) => assert.equal(weapon.swordArtsParamId, 100));
  assert.equal(firstPool, lion.weaponSources.filter((one) => one.fixed === true).length);
  // 默认武器（列表第一把）是固定武器，分组后第一组的第一把就是它。
  assert.equal(R.groupWeapons(weapons)[0].weapons[0].id, weapons[0].id);

  // 同一把武器两者都成立（大蛇狩猎矛：固定 1188，局内战技池也抽得到 1188）→ 只标固定。
  const serpent = skills._skillById[1188];
  const entry = serpent.weaponSources.find((one) => one.id === 17030000);
  assert.ok(entry.fixed === true && entry.pool.length > 0);
  assert.equal(R.weaponSourceMap(serpent)[17030000], "fixed");
  const label = R.weaponOptionLabel(skills._weaponById[17030000], "fixed");
  assert.ok(label.indexOf(R.TEXT.weaponSource.fixed) !== -1 && label.indexOf(R.TEXT.weaponSource.pool) === -1);
  const poolLabel = R.weaponOptionLabel(weapons[firstPool], "pool");
  assert.ok(poolLabel.indexOf(R.TEXT.weaponSource.pool) !== -1 && poolLabel.indexOf(R.TEXT.weaponSource.fixed) === -1);

  // 全表：标记与 weaponSources 一致，固定标记恰好是 swordArtsParamId 指向这个战技的武器。
  skills.skills.forEach((skill) => {
    const map = R.weaponSourceMap(skill);
    (skill.weaponSources || []).forEach((one) => {
      const weapon = skills._weaponById[one.id];
      assert.equal(map[one.id], one.fixed === true ? "fixed" : "pool");
      assert.equal(map[one.id] === "fixed", weapon.swordArtsParamId === skill.id);
    });
  });
  // 旧数据没有 weaponSources：按 swordArtsParamId 判固定，判不出的不标。
  assert.equal(R.weaponSourceOf({ id: 5 }, { id: 1, swordArtsParamId: 5 }), "fixed");
  assert.equal(R.weaponSourceOf({ id: 5 }, { id: 1, swordArtsParamId: 6 }), null);

  // 四条新文案（三端同名同值）。
  assert.deepEqual(R.TEXT.weaponSource, {
    fixed: "固定战技",
    pool: "局内可抽到",
    poolHint: "局内掉落的这把武器有机会抽到这个战技（按战技池权重）",
    note: "武器列表含固定带这个战技的武器与局内战技池能抽到它的武器；动作套按这一把武器实解。"
  });
});

test("v3：skills schemaVersion < 3 要提示结果不可信", () => {
  assert.equal(R.skillsSchemaWarning(skills), "");
  assert.equal(R.skillsSchemaWarning({ schemaVersion: 4 }), "");
  const old = R.skillsSchemaWarning({ schemaVersion: 2 });
  assert.ok(old.indexOf("schemaVersion 2") !== -1 && old.indexOf("结果不可信") !== -1);
  assert.ok(R.skillsSchemaWarning({}).indexOf("结果不可信") !== -1, "缺版本号同样提示");
  assert.ok(R.skillsSchemaWarning(null).indexOf("结果不可信") !== -1);
});

test("列表一律显示 displayNameZh（notes.displayName：nameZh 重名极多）", () => {
  const withDisplay = buffs.buffs.find((buff) => buff.displayNameZh);
  assert.equal(R.buffDisplayName(withDisplay), withDisplay.displayNameZh);
  const names = index.entries.map((entry) => entry.name);
  assert.equal(new Set(names).size, names.length, "displayNameZh 在全表唯一，列表不该出现重名");
});

test("格式化：倍率 / 百分比 / 持续时间", () => {
  assert.equal(R.fmtMultiplier(1.25), "×1.250");
  assert.equal(R.fmtGain(1.25), "+25.0%");
  assert.equal(R.fmtPercent(0.5), "50.0%");
  assert.equal(R.fmtDuration(-1), "永久");
  assert.equal(R.fmtDuration(30), "30 秒");
  assert.equal(R.fmtNumber(46.0, 1), "46");
});

// ------------------------------------------------------------------ 性能

// ------------------------------------------------------------------ v6 索引字段

test("indexBuff：带出 v6 的来源槽位 / appliesTo / 互斥键 / 叠层输入 / 累积阶梯", () => {
  const byId = index.byId;
  const skillAttack = byId[8350000];
  assert.equal(skillAttack.slot, "weaponAffix");
  assert.equal(skillAttack.key, "sp10#8350000");
  assert.equal(skillAttack.appliesTo.skill, "conditional");
  const evergaol = byId[7069001];
  assert.ok(evergaol.stackInput && evergaol.stackInput.mode === "ladder");
  const grace = byId[8970000];
  assert.ok(grace.stackInput && grace.stackInput.mode === "copies");
  assert.equal(grace.slot, "runStack");
  const prosthesis = byId[312506];
  assert.ok(prosthesis.accLadder, "米莉森的义手是累积阶梯");
  assert.equal(prosthesis.ladderGroup, 312505, "阶梯组 id 取第 1 档");
  assert.equal(prosthesis.ladderTier, 2);
  assert.equal(index.entries.length, buffs.buffs.length, "索引应当覆盖全表");
  index.entries.forEach((entry) => {
    assert.equal(entry.key, entry.buff.stacking.exclusiveKey, entry.id + " 的互斥键必须原样取 exclusiveKey");
    const listable = entry.countsAsDamage && (entry.target === "self" || entry.target === "ally") && entry.direction !== "decrease";
    assert.equal(entry.listable, listable, entry.id + " 能不能进配置页：带伤害字段、作用于自己或队友、不是减益");
  });
  // selfAllyPair：Self／Allies 两行成对，role 与 target 一致。
  assert.equal(byId[1876].pairRole, "self");
  assert.equal(byId[1877].pairRole, "ally");
  assert.equal(byId[1877].target, "ally");
  assert.deepEqual(byId[7050301].goodsIds, [1210], "requiresGoodsIds 原样带出");
});

// ------------------------------------------------------------------ 多档词条（affixVariant）

test("多档词条：一律读数据的 affixVariant，恰好是 schema 复核三轮列出的 7 组 × 4 档（不按 compatibilityId 或行名猜）", () => {
  const tagged = buffs.buffs.filter((buff) => buff.affixVariant);
  assert.equal(tagged.length, 28, "数据给了 28 条 affixVariant");
  const groups = index.variants;
  const expected = [7120000, 7120100, 7120200, 7120300, 7120400, 7120500, 7120600];
  assert.deepEqual(Object.keys(groups).sort(), expected.map((id) => "affix#" + id).sort());
  expected.forEach((attachId) => {
    const members = groups["affix#" + attachId];
    assert.deepEqual(members.map((entry) => entry.id), [1, 2, 3, 4].map((n) => attachId + n), attachId + " 的四档");
    members.forEach((entry, i) => {
      assert.equal(entry.variantTier, i + 1);
      assert.equal(entry.variantGroup, entry.buff.affixVariant.key);
      assert.equal(entry.key, "affix#" + attachId, "互斥键原样取数据的 exclusiveKey");
      assert.equal(entry.variantMembers, members);
    });
  });
  // 状态负载行（7120405 等）不是档位，不进组。
  assert.equal(index.byId[7120405].variantGroup, null);
  // 累积阶梯、叠层、连续三阶段（8885220–22 各自一个键、同时存在）都不是多档词条。
  [7037604, 7069001, 8885220, 8885221].forEach((id) => assert.equal(index.byId[id].variantGroup, null, id + " 不是多档词条"));
  // 同一 compatibilityId 的不同词条（7 条「出击时的武器，附加…」同为 200）不会被并成一组。
  assert.equal(Object.keys(groups).length, 7);
});

test("多档词条：同一组只算选中的那一档（默认第 1 档），config.variants 可以改选", () => {
  const members = index.variants["affix#7120000"];
  const config = R.emptyConfig();
  const mixed = out({ shares: shares({ slash: 0.5, magic: 0.5 }) });
  const first = members.map((entry) => R.evaluateEntry(entry, env(mixed, config), { column: "other", autoConfirm: true }));
  assert.equal(first[0].state === "variantOff", false, "第 1 档是选中的那一档");
  assert.deepEqual(first.slice(1).map((item) => item.state), ["variantOff", "variantOff", "variantOff"]);
  assert.ok(first[1].reasons[0].indexOf("第 1 档") !== -1 && first[1].reasons[0].indexOf("affixVariant") !== -1);
  config.variants["affix#7120000"] = members[2].id;
  const third = members.map((entry) => R.evaluateEntry(entry, env(mixed, config), { column: "other", autoConfirm: true }).state);
  assert.deepEqual(third.map((state) => state === "variantOff"), [true, true, false, true]);
  assert.equal(R.selectedVariant(members[0], config).tier, 3);
  assert.equal(R.selectedVariant(members[0], R.emptyConfig()).tiers, 4);
  assert.ok(R.TEXT.variantNoMapping.indexOf("映射") !== -1, "选档控件写明参数里查不到武器类别 → 档位的映射");
});

test("多档词条：数据没标 affixVariant 的一律不成组（结构再像也不推断）", () => {
  const base = { target: "self", activation: "passive", direction: "increase",
    appliesTo: { skill: "yes", sorcery: "yes", incantation: "yes" } };
  const data = {
    rateFields: buffs.rateFields,
    buffs: [
      Object.assign({ spEffectId: 11, paramName: "[Relic] A - Potency 1", rates: { physicsAttackRate: 1.1 },
        relicAffixes: [{ attachEffectId: 10 }], stacking: { exclusiveKey: "affix#10" },
        affixVariant: { key: "affix#10", attachEffectId: 10, variant: 1, variants: 2 } }, base),
      Object.assign({ spEffectId: 12, paramName: "[Relic] A - Potency 2", rates: { physicsAttackRate: 1.2 },
        relicAffixes: [{ attachEffectId: 10 }], stacking: { exclusiveKey: "affix#10" },
        affixVariant: { key: "affix#10", attachEffectId: 10, variant: 2, variants: 2 } }, base),
      Object.assign({ spEffectId: 21, paramName: "[Relic] B - Potency 1", rates: { physicsAttackRate: 1.1 },
        relicAffixes: [{ attachEffectId: 20, compatibilityId: 5 }], stacking: { exclusiveKey: "sp10#21" } }, base),
      Object.assign({ spEffectId: 22, paramName: "[Relic] B - Potency 2", rates: { physicsAttackRate: 1.2 },
        relicAffixes: [{ attachEffectId: 20, compatibilityId: 5 }], stacking: { exclusiveKey: "sp10#22" } }, base)
    ]
  };
  const own = R.indexBuffs(data);
  assert.deepEqual(Object.keys(own.variants), ["affix#10"]);
  assert.equal(own.byId[12].variantTier, 2);
  assert.equal(own.byId[21].variantGroup, null);
  assert.equal(own.byId[21].key, "sp10#21");
  const bare = R.indexBuffs({ rateFields: buffs.rateFields, buffs: data.buffs.slice(2) });
  assert.deepEqual(Object.keys(bare.variants), [], "没有 affixVariant 就没有多档组");
  assert.equal(bare.byId[22].key, "sp10#22");
});

// ------------------------------------------------------------------ 减益（notes.ranking ②）

test("evaluateEntry：direction=decrease 一律不计入（notes.ranking 第②步），mixed 照常计入", () => {
  const debuff = synth(-40, { rates: { physicsAttackRate: 0.87 }, direction: "decrease" });
  const item = R.evaluateEntry(debuff, env(out()), { column: "other", autoConfirm: true });
  assert.equal(item.state, "no");
  assert.equal(item.reasons[0], R.TEXT.reasonDecrease);
  assert.equal(debuff.listable, false, "减益不进配置页各栏");
  const mixed = synth(-41, { rates: { physicsAttackPower: 30, magicAttackPower: 33 }, direction: "mixed" });
  assert.equal(R.evaluateEntry(mixed, env(out()), { column: "other", autoConfirm: true }).state, "counted");
  // 真实数据：【无赖】技艺命中敌人时降低对方攻击力（7500401），target=self、appliesTo.skill=yes，但它是减益。
  const raider = index.byId[7500401];
  assert.equal(raider.direction, "decrease");
  assert.equal(raider.appliesTo.skill, "yes");
  assert.equal(R.evaluateEntry(raider, env(out()), { column: "other", autoConfirm: true }).state, "no");
  index.entries.forEach((entry) => {
    if (entry.direction !== "decrease") return;
    const state = R.evaluateEntry(entry, env(out()), { column: "other", autoConfirm: true }).state;
    assert.notEqual(state, "counted", entry.id + " 是减益，不能计入");
    assert.notEqual(state, "pending", entry.id + " 是减益，不该等用户确认");
  });
});

// ------------------------------------------------------------------ 加算的符号

test("fmtFlat / hasFlat：攻击力加算按数值带符号，不会出现「+-」", () => {
  assert.equal(R.fmtFlat(-76.86486), "-76.9");
  assert.equal(R.fmtFlat(12.34), "+12.3");
  assert.equal(R.fmtFlat(-0.04), "0");
  assert.equal(R.fmtFlat(66, 0), "+66");
  assert.equal(R.hasFlat(-12.8), true);
  assert.equal(R.hasFlat(0.01), false);
  assert.equal(R.hasFlat(0), false);
});

test("exclusiveKeyOf：exclusiveKey 缺失时退回 stacking.group，再退回 sp<cat>#<id>", () => {
  assert.equal(R.exclusiveKeyOf({ spEffectId: 5, stacking: { exclusiveKey: "sp204@p11", group: "sp204" } }), "sp204@p11");
  assert.equal(R.exclusiveKeyOf({ spEffectId: 5, stacking: { group: "sp160" } }), "sp160");
  assert.equal(R.exclusiveKeyOf({ spEffectId: 5, stacking: { spCategory: 20 } }), "sp20#5");
});

test("characterKey / characterLabel：按 Paramdex 行名方括号分组，中文名与 heroes 数据集一致", () => {
  assert.equal(R.characterKey({ paramName: "[Skill - Revenant] Spirit Stat Change - Level 2" }), "Revenant");
  assert.equal(R.characterKey({ paramName: "[Ultimate - Executor] Beast Depth 1" }), "Executor");
  assert.equal(R.characterKey({ paramName: "Magic Cocktail" }), "");
  assert.equal(R.characterLabel("Revenant"), "复仇者");
  assert.equal(R.characterLabel(""), "其他角色");
  const heroes = JSON.parse(readFileSync(resource("heroes.json"), "utf8"));
  (heroes.heroes || []).forEach((hero) => {
    assert.equal(R.CHARACTER_NAMES[hero.nameEn], hero.nameZh, hero.nameEn + " 的中文名应与 heroes 数据集一致");
  });
});

test("outputWepType：战技取所选武器的类别，魔法＝手杖，祷告＝圣印记", () => {
  const weapon = skills._weaponById[9040000];
  assert.equal(R.outputWepType(out({ mode: "skill", weapon })), weapon.wepType);
  assert.equal(R.outputWepType(out({ mode: "skill", weapon: null })), null);
  assert.equal(R.outputWepType(out({ mode: "sorcery" })), R.CASTER_WEP_TYPE.sorcery);
  assert.equal(R.outputWepType(out({ mode: "incantation" })), R.CASTER_WEP_TYPE.incantation);
  assert.equal(buffs.enums.wepType[String(R.CASTER_WEP_TYPE.sorcery)].zh, "手杖");
  assert.equal(buffs.enums.wepType[String(R.CASTER_WEP_TYPE.incantation)].zh, "圣印记");
});

// ------------------------------------------------------------------ appliesTo 判定

test("appliesVerdict：yes 直接生效，no 带上数据给的 reason", () => {
  const yes = synth(-1);
  assert.equal(R.appliesVerdict(yes, out()).state, "yes");
  const no = synth(-2, {
    appliesTo: { skill: "no", sorcery: "yes", incantation: "yes" },
    appliesToDetail: { skill: { reason: "wepParamChange=3（自身）：不作用于武器攻击" } }
  });
  const verdict = R.appliesVerdict(no, out());
  assert.equal(verdict.state, "no");
  assert.deepEqual(verdict.reasons, ["wepParamChange=3（自身）：不作用于武器攻击"]);
  assert.equal(R.appliesVerdict(no, out({ mode: "sorcery" })).state, "yes", "换输出类别就换 appliesTo 的键");
  const missing = synth(-3, { appliesTo: null });
  assert.equal(R.appliesVerdict(missing, out()).state, "no", "没有 appliesTo 的数据按不生效处理");
});

test("appliesVerdict：requires.hand 按当前手自动判定", () => {
  const right = synth(-4, {
    appliesTo: { skill: "conditional" },
    appliesToDetail: { skill: { reason: "wepParamChange=1", requires: { hand: 1 } } }
  });
  assert.equal(R.appliesVerdict(right, out({ hand: 1 })).state, "yes");
  const left = R.appliesVerdict(right, out({ hand: 2 }));
  assert.equal(left.state, "no");
  assert.ok(left.reasons[0].indexOf("右手") !== -1 && left.reasons[0].indexOf("左手") !== -1);
});

test("appliesVerdict：requires.attackWeaponTypes 按当前武器（法术按施法器）自动判定", () => {
  const dagger = synth(-5, {
    appliesTo: { skill: "conditional", sorcery: "conditional" },
    appliesToDetail: {
      skill: { reason: "triggerOnWepType=1", requires: { attackWeaponTypes: [1] } },
      sorcery: { reason: "triggerOnWepType=57", requires: { attackWeaponTypes: [57] } }
    }
  });
  assert.equal(R.appliesVerdict(dagger, out({ weapon: { wepType: 1 } })).state, "yes");
  const katana = R.appliesVerdict(dagger, out({ weapon: { wepType: 13 } }));
  assert.equal(katana.state, "no");
  assert.ok(katana.reasons[0].indexOf("短剑") !== -1 && katana.reasons[0].indexOf("刀") !== -1, "类别名取 enums.wepType");
  assert.equal(R.appliesVerdict(dagger, out({ weapon: null })).state, "no", "没有武器就对不上出手武器类别");
  assert.equal(R.appliesVerdict(dagger, out({ mode: "sorcery" })).state, "yes", "魔法由手杖施放");
});

test("appliesVerdict：requires.physicalType 只落在对应物理通道，构成里没有这一类就不生效", () => {
  const pierce = synth(-6, {
    appliesTo: { skill: "conditional" },
    appliesToDetail: { skill: { reason: "atkAttribute=2", requires: { physicalType: 2 } } }
  });
  const mixed = out({ shares: shares({ slash: 0.5, thrust: 0.5 }) });
  const verdict = R.appliesVerdict(pierce, mixed);
  assert.equal(verdict.state, "yes");
  assert.equal(verdict.restrictedType, "thrust");
  const tables = R.entryTables(pierce, plan, verdict.restrictedType, verdict.weight, null);
  assert.equal(tables.table.thrust, 1.2);
  assert.equal(tables.table.slash, 1, "只乘对应的那一格");
  assert.equal(R.appliesVerdict(pierce, out({ shares: shares({ slash: 1 }) })).state, "no");
});

test("appliesVerdict：requires.subCategoriesAny 用 attackIndex 逐段判定（全中 / 全不中 / 部分按段加权）", () => {
  const data = {
    enums: buffs.enums,
    attackIndex: {
      skills: {
        1: { subCategorySets: [{ subs: [112, 130], hits: 4 }] },
        2: { subCategorySets: [{ subs: [106, 130], hits: 3 }] },
        3: { subCategorySets: [{ subs: [112], hits: 1 }, { subs: [130], hits: 3 }] }
      },
      spells: {}
    }
  };
  const skillAttack = synth(-7, {
    appliesTo: { skill: "conditional" },
    appliesToDetail: { skill: { reason: "子类别限定 [112]", requires: { subCategoriesAny: [111, 112] } } }
  });
  assert.equal(R.appliesVerdict(skillAttack, out({ meansId: 1 }, data)).state, "yes");
  const none = R.appliesVerdict(skillAttack, out({ meansId: 2 }, data));
  assert.equal(none.state, "no");
  assert.ok(none.reasons[0].indexOf("112") !== -1);
  const partial = R.appliesVerdict(skillAttack, out({ meansId: 3 }, data));
  assert.equal(partial.state, "yes");
  assert.equal(partial.weight, 0.25, "4 段里 1 段带 112");
  assert.ok(partial.notes[0].indexOf("1/4") !== -1);
  const weighted = R.entryTables(skillAttack, plan, null, partial.weight, null);
  assert.ok(Math.abs(weighted.table.slash - (1 + 0.2 * 0.25)) < 1e-12, "按段加权：1 + (m − 1) × 命中段占比");
  const unknown = R.appliesVerdict(skillAttack, out({ meansId: 99 }, data));
  assert.equal(unknown.state, "pending", "attackIndex 里查不到就要用户确认");
});

test("appliesVerdict：requires.attackContexts 只认攻击情境勾选；附魔武器限定等要用户确认", () => {
  const counter = synth(-8, {
    appliesTo: { skill: "conditional" },
    appliesToDetail: { skill: { reason: "stateInfo=197", requires: { attackContexts: ["thrustingCounter"] } } }
  });
  const unchecked = R.appliesVerdict(counter, out());
  assert.equal(unchecked.state, "context");
  assert.ok(unchecked.reasons[0].indexOf("突刺反击") !== -1, "情境中文名取 enums.attackContext");
  assert.equal(R.appliesVerdict(counter, out({ contexts: { thrustingCounter: true } })).state, "yes");

  const imbued = synth(-9, {
    appliesTo: { skill: "conditional" },
    appliesToDetail: { skill: { reason: "spAttribute=10", requires: { imbuedWeaponOnly: true } } }
  });
  const pending = R.appliesVerdict(imbued, out());
  assert.equal(pending.state, "pending");
  assert.equal(pending.needs[0], R.TEXT.requireImbued);

  const bare = synth(-10, { appliesTo: { skill: "conditional" }, appliesToDetail: { skill: { reason: "看战技" } } });
  assert.equal(R.appliesVerdict(bare, out()).state, "pending", "conditional 却没有机读条件 → 要确认");
  const odd = synth(-11, {
    appliesTo: { skill: "conditional" },
    appliesToDetail: { skill: { reason: "x", requires: { someNewKey: 1 } } }
  });
  assert.equal(R.appliesVerdict(odd, out()).state, "pending", "数据新增的 requires 键不能被静默放行");
});

// ------------------------------------------------------------------ 叠层

test("stackedRates：ladder 取 tierMultipliers[n−1]（超出按最后一层），copies 取 perStackMultiplier^n", () => {
  const evergaol = index.byId[7069001];
  const si = evergaol.stackInput;
  assert.ok(Array.isArray(si.tierMultipliers) && si.tierMultipliers.length > 1);
  const seven = R.stackedRates(evergaol, 7);
  si.appliesToRateKeys.forEach((key) => assert.equal(seven[key], si.tierMultipliers[6]));
  const over = R.stackedRates(evergaol, 99);
  assert.equal(over[si.multiplierKey], si.tierMultipliers[si.tierMultipliers.length - 1]);
  assert.equal(R.stackedRates(evergaol, 0), null, "0 层 = 不计入");
  assert.equal(R.stackedRates(evergaol, 1)[si.multiplierKey], si.tierMultipliers[0]);

  const grace = index.byId[8970000];
  const three = R.stackedRates(grace, 3);
  assert.ok(Math.abs(three[grace.stackInput.multiplierKey] - Math.pow(grace.stackInput.perStackMultiplier, 3)) < 1e-12);
  assert.equal(grace.rates[grace.stackInput.multiplierKey], grace.stackInput.perStackMultiplier, "原 rates 不被改写");
});

test("stacksFor / stackWarnings：层数缺省 0（填层数才算确认），勾选不占槽位的行时预填一局实际上限；超出上限给提示", () => {
  const evergaol = index.byId[7069001];
  const invader = index.byId[7069201];
  const grace = index.byId[8970000];
  assert.equal(R.stacksFor(evergaol, R.emptyConfig()), 0, "没填过层数就是 0");
  assert.equal(R.defaultStacks(evergaol), evergaol.stackInput.practicalMaxStacks, "预填一局实际上限");
  assert.equal(R.defaultStacks(grace), 1, "参数表无上限、也没有实测上限的预填 1 份");
  const config = R.emptyConfig();
  config.stacks[invader.id] = 3.7;
  assert.equal(R.stacksFor(invader, config), 3, "层数取整");
  assert.equal(R.stackWarnings(evergaol, 7, 7).length, 0);
  assert.ok(R.stackWarnings(evergaol, 8, 8)[0].indexOf("7") !== -1, "超过一局实际上限要提示");
  assert.equal(R.stackWarnings(evergaol, 12, R.stackParamMax(evergaol)).length, 2, "超过参数表层数再多一条（按参数表上限计算）");
  assert.ok(R.stackWarnings(grace, 11, 11)[0].indexOf("10") !== -1, "copies 超过游戏文本备好的＋N 标签要提示");
  assert.equal(R.stackParamMax(evergaol), evergaol.stackInput.paramMaxStacks);
  assert.equal(R.stackParamMax(grace), R.COPIES_CEILING, "份数型参数表无上限，页面按 99 截断误输入");
  assert.equal(R.setStacks(R.emptyConfig(), evergaol, 99).stacks[evergaol.id], R.stackParamMax(evergaol));
  assert.equal(R.setStacks(R.emptyConfig(), evergaol, -3).stacks[evergaol.id], 0);
});

test("累积阶梯：同一组只算选中的那一层；没选层就一层都不算（选层即确认）", () => {
  const config = R.emptyConfig();
  const members = cfgIndex.ladders[312505];
  assert.ok(members && members.length >= 3);
  const top = members[members.length - 1];
  members.forEach((entry) => {
    const item = R.evaluateEntry(entry, env(out(), config), { column: "accessory" });
    assert.equal(item.state, "tierOff", entry.id + " 没选层时不计入");
    assert.equal(item.reasons[0], R.TEXT.reasonTierNone);
  });
  config.tiers[312505] = members[0].id;
  const chosen = R.evaluateEntry(members[0], env(out(), config), { column: "accessory" });
  assert.equal(chosen.state, "counted", "选层即视为条件成立（不用再勾「条件成立」）");
  assert.equal(R.evaluateEntry(top, env(out(), config), { column: "accessory" }).state, "tierOff");
  assert.equal(R.selectedLadderTier(top, config, cfgIndex.ladders).tier, 1);
  assert.equal(R.ladderTopTier(cfgIndex.ladders, 312505).id, top.id);
});

// ------------------------------------------------------------------ 单条评估

test("evaluateEntry：条件型——占槽位的栏放进来≠条件成立，要勾「条件成立」；「其它增益」栏勾选即确认", () => {
  const conditional = synth(-12, { activation: "conditional" });
  const config = R.emptyConfig();
  const slotted = R.evaluateEntry(conditional, env(out(), config), { column: "relic" });
  assert.equal(slotted.state, "pending");
  assert.equal(slotted.needs.length, 1);
  assert.equal(slotted.needs[0], R.TEXT.activationNeed.conditional);
  const slotless = R.evaluateEntry(conditional, env(out(), config), { column: "other", autoConfirm: true });
  assert.equal(slotless.state, "counted");
  assert.equal(slotless.ticked, true);
  config.ticks[-12] = true;
  assert.equal(R.evaluateEntry(conditional, env(out(), config), { column: "weaponAffix" }).state, "counted", "勾了就计入");
  const strict = R.makeEnv(cfgIndex, out(), config, { strict: true });
  assert.equal(R.evaluateEntry(conditional, strict, { column: "other", autoConfirm: true }).state, "pending", "推荐口径不计条件型");
  const assume = R.makeEnv(cfgIndex, out(), R.emptyConfig(), { assumeAll: true });
  assert.equal(R.evaluateEntry(conditional, assume, { column: "relic" }).state, "counted", "「条件全部成立」口径当成立");
  // 「装备三把以上 X」：说明写出数量与类别。
  const equipped = synth(-19, { activation: "conditional", scope: { weaponTypes: { mode: "equippedCount", wepTypes: [1], namesZh: ["短剑"], count: 3 } } });
  assert.equal(R.activationNote(equipped, out()), R.fmt(R.TEXT.activationNeed.equipped, 3, "短剑"));
  // 需同时使用道具（requiresGoodsIds）：要确认。
  const goods = synth(-18, { requiresGoodsIds: [1210] });
  const verdict = R.appliesVerdict(goods, out());
  assert.equal(verdict.state, "pending");
  assert.ok(verdict.needs[0].indexOf("道具") !== -1);
});

test("evaluateEntry：作用对象只留自己与队友；selfAllyPair 的 Allies 那一行不算施放者自己", () => {
  assert.equal(R.evaluateEntry(synth(-13, { target: "ally" }), env(out()), { column: "other", autoConfirm: true }).state, "counted",
    "ally＝自己与／或附近队友（notes.target），照常计入");
  const pairAlly = synth(-27, { target: "ally", selfAllyPair: { role: "ally", counterpartSpEffectId: -28 } });
  const pairItem = R.evaluateEntry(pairAlly, env(out()), { column: "other", autoConfirm: true });
  assert.equal(pairItem.state, "no");
  assert.equal(pairItem.reasons[0], R.TEXT.reasonAllyPair);
  const pairSelf = synth(-28, { selfAllyPair: { role: "self", counterpartSpEffectId: -27 } });
  assert.equal(R.evaluateEntry(pairSelf, env(out()), { column: "other", autoConfirm: true }).state, "counted");
  assert.equal(R.evaluateEntry(synth(-14, { target: "enemy" }), env(out()), { column: "other", autoConfirm: true }).state, "no");
  assert.equal(R.evaluateEntry(synth(-15, { target: "summon" }), env(out()), { column: "other", autoConfirm: true }).state, "no");
  assert.equal(R.evaluateEntry(synth(-16, { rates: { saAttackPowerRate: 2 } }), env(out()), { column: "other" }).state, "noDamage");
  // 真实数据：共享圣律 1877（队友那一行）不计入。
  const holy = out({ mode: "incantation", shares: shares({ holy: 1 }) });
  assert.equal(R.evaluateEntry(index.byId[1877], env(holy), { column: "other", autoConfirm: true }).state, "no");
});

test("evaluateEntry：有效倍率 = Σ 占比 × 倍率表；攻击力倍率层与伤害倍率层相乘；加算只按占比加权", () => {
  const both = synth(-17, { rates: { fireAttackRate: 1.5, fireAttackPowerRate: 1.2, physicsAttackPower: 30 } });
  const half = out({ shares: shares({ slash: 0.5, fire: 0.5 }) });
  const item = R.evaluateEntry(both, env(half), { explicit: true });
  assert.ok(Math.abs(item.table.fire - 1.8) < 1e-12, "两层相乘 1.5 × 1.2");
  assert.equal(item.table.slash, 1);
  assert.ok(Math.abs(item.multiplier - (0.5 * 1 + 0.5 * 1.8)) < 1e-12);
  assert.ok(Math.abs(item.flat - 15) < 1e-12, "物理加算 30 × 物理占比 0.5");
  const none = R.evaluateEntry(both, env(out({ shares: shares({}) })), { explicit: true });
  assert.equal(none.multiplier, null, "没有构成就算不出倍率");
});

// ------------------------------------------------------------------ 去重

test("dedupeItems：同一互斥键只留一份（取倍率高的），不同键都留", () => {
  const e = env(out());
  const small = synth(-20, { rates: { physicsAttackRate: 1.1 }, stacking: { spCategory: 160, spCategoryBehavior: "removePrevious", exclusiveKey: "sp160" } });
  const big = synth(-21, { rates: { physicsAttackRate: 1.3 }, stacking: { spCategory: 160, spCategoryBehavior: "removePrevious", exclusiveKey: "sp160" } });
  const other = synth(-22, { rates: { physicsAttackRate: 1.05 } });
  const items = [small, big, other].map((entry) => R.evaluateEntry(entry, e, { explicit: true, label: "#" + entry.id }));
  const winners = R.dedupeItems(items);
  assert.deepEqual(winners.map((item) => item.entry.id).sort((a, b) => a - b), [-22, -21]);
  assert.equal(items[0].state, "duplicate");
  assert.equal(items[0].dupOf, items[1]);
  assert.ok(items[0].reasons[0].indexOf("sp160") !== -1);
});

test("同一效果多份：stackSelf（spCategory 10）各份相乘并提示「参数推断」，其余只算一份", () => {
  const e = env(out());
  const one = synth(-23);
  const merged = R.mergeSources([
    { entry: one, column: "weaponAffix", copies: 2, label: "武器 A", key: "wa:1" },
    { entry: one, column: "relic", copies: 1, label: "遗物 1", key: "relic:0" }
  ]);
  assert.equal(merged.length, 1, "同一 spEffectId 合并成一条");
  assert.equal(merged[0].copies, 3);
  assert.equal(merged[0].column, "weaponAffix", "栏目取第一个来源");
  const item = R.evaluateEntry(one, e, merged[0]);
  assert.equal(item.state, "counted");
  assert.equal(item.countedCopies, 3);
  assert.ok(Math.abs(item.table.slash - Math.pow(1.2, 3)) < 1e-12, "三份相乘");
  assert.ok(item.notes.some((note) => note.indexOf("stackSelf") !== -1 && note.indexOf("参数推断") !== -1));
  const refresh = synth(-24, { stacking: { spCategory: 20, spCategoryBehavior: "resetOnApply", exclusiveKey: "sp20#-24" } });
  const single = R.evaluateEntry(refresh, e, { column: "relic", copies: 2 });
  assert.equal(single.countedCopies, 1);
  assert.ok(Math.abs(single.table.slash - 1.2) < 1e-12, "非 stackSelf 只算一份");
  assert.ok(single.notes.some((note) => note.indexOf("只算一份") !== -1));
  const warnings = R.configWarnings([item, single], [item, single]);
  assert.ok(warnings.some((w) => w.kind === "copiesStackSelf" && w.text.indexOf("未实测") !== -1));
  assert.ok(warnings.some((w) => w.kind === "copiesSingle"));
});

test("prefersItem：两边都是 applyHighest 时按 categoryPriority 取数值小的，否则比有效倍率", () => {
  const e = env(out());
  const low = synth(-25, { rates: { physicsAttackRate: 1.1 }, stacking: { spCategory: 1001, spCategoryBehavior: "applyHighest", categoryPriority: 1, exclusiveKey: "sp1001" } });
  const high = synth(-26, { rates: { physicsAttackRate: 1.5 }, stacking: { spCategory: 1001, spCategoryBehavior: "applyHighest", categoryPriority: 5, exclusiveKey: "sp1001" } });
  const a = R.evaluateEntry(low, e, { column: "other", autoConfirm: true });
  const b = R.evaluateEntry(high, e, { column: "other", autoConfirm: true });
  assert.equal(R.prefersItem(a, b), true, "priority 1 优先于 5，即使倍率更低");
  assert.equal(R.prefersItem(b, a), false);
  // 被压掉的那一份写明是按 categoryPriority 压掉的，汇总也给出提示。
  const items = [b, a];
  R.dedupeItems(items);
  assert.equal(b.state, "duplicate");
  assert.ok(b.reasons[0].indexOf("categoryPriority") !== -1 && b.reasons[0].indexOf("压掉") !== -1);
  const warnings = R.configWarnings(items, [a]);
  assert.equal(warnings[0].kind, "priority");
  assert.ok(warnings[0].text.indexOf("applyHighest") !== -1);
});

// ------------------------------------------------------------------ 槽位规则

test("slotCaps：常规 / 深夜的武器词条上限、深夜专属上限、遗物与护符格数一律取 slotRules", () => {
  const rules = buffs.slotRules;
  const normal = R.slotCaps(rules, "normal");
  const deep = R.slotCaps(rules, "deep");
  assert.equal(normal.weaponAffix, rules.weaponAffix.maxAffixesNormal);
  assert.equal(deep.weaponAffix, rules.weaponAffix.maxAffixesDeep);
  assert.equal(deep.deepOnly, rules.weaponAffix.maxDeepOnlyAffixes);
  assert.equal(normal.deepOnly, rules.weaponAffix.maxWeapons * rules.modes.normal.deepOnlyAffixesPerWeapon);
  assert.equal(normal.relics, rules.modes.normal.relicSlots);
  assert.equal(deep.relics, rules.modes.deep.relicSlots);
  assert.equal(deep.relicNormal, rules.relic.normal);
  assert.equal(deep.relicDeep, rules.relic.deepExtra);
  assert.equal(normal.accessory, rules.accessory.slots);
  // 数据缺失时有兜底，不抛错。
  const fallback = R.slotCaps(null, "deep");
  assert.ok(fallback.weaponAffix > 0 && fallback.relics > 0 && fallback.accessory > 0);
});

// ------------------------------------------------------------------ 配置索引

test("buildConfigIndex：武器词条按 AttachEffect 列出、不含诅咒；护符按护符分组；其它栏按主槽位分组", () => {
  assert.ok(cfgIndex.weaponAffixes.length > 0);
  cfgIndex.weaponAffixes.forEach((affix) => {
    assert.equal(affix.roles.indexOf("curse"), -1, affix.id + " 是诅咒，不该进正面词条栏");
    assert.ok(affix.entries.some((entry) => entry.countsAsDamage), affix.id + " 没有增伤条目");
    const raw = buffs.weaponAffixes.find((one) => one.attachEffectId === affix.id);
    assert.equal(affix.deepOnlyPositive, raw.deepOnlyPositive === true, affix.id + " 的深夜专属标记");
  });
  const prosthesis = cfgIndex.talismanById[1250];
  assert.ok(prosthesis && prosthesis.entries.length >= 3, "米莉森的义手带一整条累积阶梯");
  R.OTHER_SLOTS.forEach((slot) => {
    (cfgIndex.otherRows[slot] || []).forEach((row) => {
      row.entries.forEach((entry) => {
        assert.equal(entry.slot, slot);
        assert.ok(entry.countsAsDamage);
      });
    });
  });
  const dew = cfgIndex.otherRows.consumable.find((row) => row.ladder && row.key === 3558);
  assert.ok(dew, "连刺破露滴的各层合成一行");
  assert.ok(dew.entries.length >= 2);
});

test("buildCatalogIndex：诅咒池从词条库现算（只装诅咒词条的池，当前是 3000000），按 (sortId, effectId) 排序", () => {
  const cat = R.buildCatalogIndex(catalog);
  assert.ok(cat.available);
  assert.equal(cat.cursePoolId, 3000000, "与 core.js 的 DEEP_CURSE_POOL_ID 同值");
  assert.ok(cat.curses.length > 0);
  assert.equal(R.cursePoolOf([
    { isCurse: true, poolIds: [7, 9] }, { isCurse: true, poolIds: [9] }, { isCurse: false, poolIds: [7] }
  ]), 9, "混有正面词条的池不算诅咒池");
  assert.equal(R.cursePoolOf([]), 3000000, "算不出来退回兜底常量");
  cat.curses.forEach((curse, i) => {
    assert.equal(curse.isCurse, true);
    assert.ok(curse.poolIds.indexOf(3000000) !== -1);
    if (i) {
      const prev = cat.curses[i - 1];
      assert.ok(prev.sortId < curse.sortId || (prev.sortId === curse.sortId && prev.effectId < curse.effectId));
    }
  });
  assert.equal(R.buildCatalogIndex(null).available, false, "词条库缺失时降级，不抛错");
  const empty = R.buildConfigIndex(buffs, index, null, Core);
  assert.equal(empty.relicCandidates.normal.length, 0, "没有词条库就不能自组遗物");
});

test("自组遗物候选：只收能增伤、且 Core.isEligible 认可当前模式的词条", () => {
  ["normal", "deep"].forEach((kind) => {
    const modeKey = kind === "deep" ? "deepPositive" : "currentNormal";
    const list = cfgIndex.relicCandidates[kind];
    assert.ok(list.length > 0);
    list.forEach((candidate) => {
      assert.equal(Core.isEligible(candidate.affix, modeKey), true, candidate.id + " 不在 " + modeKey + " 的池里");
      assert.equal(candidate.affix.isCurse, false);
      assert.ok(candidate.entries.some((entry) => entry.countsAsDamage));
    });
  });
});

test("availableContexts：只统计当前输出类别下 requires.attackContexts 里真正要求过的情境，中文名取 enums.attackContext", () => {
  const contexts = R.availableContexts(buffs, index.entries, "skill");
  assert.ok(contexts.length > 0);
  contexts.forEach((one) => {
    assert.equal(one.zh, buffs.enums.attackContext[one.key].zh);
    assert.ok(one.count > 0);
  });
  assert.deepEqual(R.availableContexts(buffs, index.entries, "incantation"), [], "祷告没有要求攻击情境的条目");
  assert.deepEqual(R.availableContexts({}, [], "skill"), []);
});

// ------------------------------------------------------------------ 文案常量表

test("TEXT：文案集中在一张常量表里，fmt 按位置替换", () => {
  function walk(node, pathName) {
    Object.keys(node).forEach((key) => {
      const value = node[key];
      if (value && typeof value === "object") walk(value, pathName + "." + key);
      else assert.ok(typeof value === "string" && value.length > 0, pathName + "." + key + " 应是非空文案");
    });
  }
  walk(R.TEXT, "TEXT");
  assert.equal(R.fmt("第 {0} 行：{1}", 2, "名"), "第 2 行：名");
  assert.equal(R.fmt("{0}{0}", "a"), "aa");
  assert.equal(R.fmt("{1}", "a"), "", "缺的参数替换成空串");
  R.COLUMN_ORDER.forEach((column) => assert.ok(R.TEXT.columns[column]));
  R.OTHER_SLOTS.forEach((slot) => assert.ok(R.TEXT.otherGroups[slot]));
});

test("TEXT：配置部分（计算层、工具条、四栏、汇总、口径说明、一览）不写行内中文文案", () => {
  // 两端逐键对照靠这张表：配置相关的源码段里，带汉字的字符串字面量只能出现在 TEXT 里。
  // 只含标点的连接符（「、」「／」「；」）不算文案。原样保留的输出手段／分段命中／伤害构成不在检查范围。
  const source = readFileSync(path.join(repoRoot, "windows", "renderer", "pages", "ranker.js"), "utf8");
  const lines = source.split("\n");
  const ranges = [
    ["// ---- 倍率字段表", "// ---- 输出手段列表"],
    ["// ---- 说明区（结论简述", "// ---- 格式化"],
    ["// ---- 配置工具条", "// ---- 底部折叠"]
  ];
  const literal = /(["'])((?:(?!\1).)*)\1/g;
  const offenders = [];
  ranges.forEach(([from, to]) => {
    const start = lines.findIndex((line) => line.indexOf(from) !== -1);
    const end = lines.findIndex((line, i) => i > start && line.indexOf(to) !== -1);
    assert.ok(start >= 0 && end > start, "找不到源码段 " + from);
    for (let i = start; i < end; i += 1) {
      const code = lines[i].trim().startsWith("//") ? "" : lines[i].replace(/\s\/\/\s.*$/, "");
      let match;
      literal.lastIndex = 0;
      while ((match = literal.exec(code))) {
        if (/[一-鿿]/.test(match[2])) offenders.push((i + 1) + ": " + match[0]);
      }
    }
  });
  assert.deepEqual(offenders, [], "这些中文文案应当移进 TEXT");
});

test("configWarnings：relicAffixes[].exclusivityId 同组的不同遗物词条同时计入时给出提示", () => {
  const make = (id, attachId) => synth(id, { relicAffixes: [{ attachEffectId: attachId, exclusivityId: 100 }] });
  const e = env(out());
  const a = R.evaluateEntry(make(-50, 900), e, { column: "relic", explicit: true, label: "遗物 1：甲" });
  const b = R.evaluateEntry(make(-51, 901), e, { column: "relic", explicit: true, label: "遗物 2：乙" });
  const warnings = R.configWarnings([a, b], [a, b]);
  const hit = warnings.find((one) => one.kind === "exclusivity");
  assert.ok(hit, "同一 exclusivityId 的两条不同词条要提示");
  assert.ok(hit.text.indexOf("100") !== -1 && hit.text.indexOf("未实测") !== -1);
  const same = R.evaluateEntry(make(-52, 900), e, { column: "relic", explicit: true, label: "遗物 3：甲" });
  assert.equal(R.configWarnings([a, same], [a, same]).some((one) => one.kind === "exclusivity"), false, "同一词条不算");
  assert.equal(R.configWarnings([], []).length, 0);
});

test("briefNotes：说明区条数与叠层数字照数据现算，并点明「参数推断，未实测」", () => {
  const notes = R.briefNotes(buffs, cfgIndex);
  assert.ok(notes.length >= 8);
  const all = notes.join("\n");
  assert.equal(all.indexOf("{"), -1, "格式串都填满了");
  const decreases = index.entries.filter((entry) => entry.countsAsDamage && entry.direction === "decrease").length;
  assert.ok(all.indexOf("direction=decrease 的 " + decreases + " 条") !== -1, "减益条数照数据现算");
  assert.ok(all.indexOf("7 组 28 条") !== -1, "多档词条的组数与条数照索引现算");
  assert.ok(all.indexOf(String(cfgIndex.catalog.cursePoolId)) !== -1, "诅咒池 ID 取词条库现算的值");
  // 「提升战技攻击力」的子类别从数据现算：改数据，说明跟着变。
  assert.deepEqual(R.skillOnlySubCategories(buffs), ["112 战技攻击", "111 蓄力战技攻击"]);
  assert.ok(all.indexOf("子类别 112 战技攻击／111 蓄力战技攻击") !== -1);
  const edited = JSON.parse(JSON.stringify(buffs));
  edited.buffs.forEach((buff) => {
    const requires = buff.appliesToDetail && buff.appliesToDetail.skill && buff.appliesToDetail.skill.requires;
    if (requires && Array.isArray(requires.subCategoriesAny) && requires.subCategoriesAny.indexOf(112) !== -1) {
      requires.subCategoriesAny = [112];
    }
  });
  assert.deepEqual(R.skillOnlySubCategories(edited), ["112 战技攻击"]);
  assert.ok(all.indexOf("未实测") !== -1);
  assert.ok(all.indexOf(String(buffs.slotRules.weaponAffix.maxDeepOnlyAffixes)) !== -1, "深夜专属上限取 slotRules");
  assert.ok(all.indexOf(buffs.slotRules.weaponAffix.duplicateWithinWeapon.status) !== -1, "同一把武器两条正面词条能否重复：照数据写未知");
  index.entries.filter((entry) => entry.stackInput).forEach((entry) => {
    assert.ok(all.indexOf(entry.name) !== -1, entry.name + " 的叠层说明要出现在说明区");
  });
  assert.ok(all.indexOf("赐福") !== -1, "赐福王的余威的层数单位是新发现的赐福");
});

test("slotLabel：槽位中文名优先取 enums.sourceSlot", () => {
  Object.keys(buffs.enums.sourceSlot).forEach((slot) => {
    assert.equal(R.slotLabel(buffs, slot), buffs.enums.sourceSlot[slot].zh);
  });
  assert.equal(R.slotLabel({}, "weaponAffix"), R.TEXT.columns.weaponAffix);
});

test("格式化：没有构成时倍率显示成「—」", () => {
  assert.equal(R.fmtMultiplier(null), "—");
  assert.equal(R.fmtGain(null), "—");
  assert.equal(R.fmtMultiplier(1.2), "×1.200");
});

// ------------------------------------------------------------------ 性能

test("性能：索引只建一次，换构成后整套配置的评估与推荐填满都很快", () => {
  const weapon = skills._weaponById[9040000];
  const skill = skills._skillById[1177];
  const hits = R.selectHits(skill, weapon).filter((hit) => !hit.noDamage && !hit.noFp);
  const started = Date.now();
  let config = R.emptyConfig();
  for (let i = 0; i < 10; i += 1) {
    const comp = R.composition(hits.slice(0, (i % hits.length) + 1), weapon, false);
    const output = R.makeOutput({ mode: "skill", meansId: 1177, weapon, hand: 1, shares: comp.shares, contexts: {} }, buffs);
    config = R.recommendFill(cfgIndex, output, R.emptyConfig(), Core, weapon.wepType).config;
    R.evaluateConfig(cfgIndex, output, config, Core);
  }
  const elapsed = Date.now() - started;
  assert.ok(elapsed < 3000, "10 次「推荐填满 + 评估」用了 " + elapsed + "ms，太慢了");
});

test("strongHtml：数据集原文的 **粗体** 标记转成 <strong>，其余字符转义后原样保留", () => {
  assert.equal(R.strongHtml("因此**绝对伤害无法还原**；支持 (a) 相对比较"),
    "因此<strong>绝对伤害无法还原</strong>；支持 (a) 相对比较");
  assert.equal(R.strongHtml("没有标记 <b>"), "没有标记 &lt;b&gt;");
  assert.equal(R.strongHtml("落单的 ** 不配对"), "落单的 ** 不配对");
  assert.equal(R.strongHtml("**开头**中间**结尾"), "<strong>开头</strong>中间**结尾");
  // 页面里引用「本数据集的边界」时不能把星号原样显示出来（QA 实测发现）。
  const skills = JSON.parse(readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "resources", "skills.json"), "utf8"));
  const html = R.strongHtml(skills.usage["本数据集的边界"]);
  assert.ok(html.includes("<strong>") && !html.includes("**"));
});

test("groupWeapons(weapons, skill) / defaultWeaponFor：三端同一排组规则——含固定武器的组在前、组内武器数降序、类别名升序；默认武器是第一组第一把", () => {
  const withBoth = skills.skills.filter((skill) => (skill.weaponSources || []).some((one) => one.fixed) && (skill.weaponSources || []).some((one) => one.pool && !one.fixed));
  assert.ok(withBoth.length >= 10);
  withBoth.forEach((skill) => {
    const weapons = R.weaponsForSkill(skills, skill);
    const groups = R.groupWeapons(weapons, skill);
    const fixedIds = new Set(skill.weaponSources.filter((one) => one.fixed).map((one) => one.id));
    const hasFixed = groups.map((group) => group.weapons.some((weapon) => fixedIds.has(weapon.id)));
    // 含固定武器的组全部在前
    const firstPoolOnly = hasFixed.indexOf(false);
    assert.ok(firstPoolOnly === -1 || hasFixed.slice(firstPoolOnly).every((flag) => !flag), `${skill.id} 组序`);
    // 同一侧内按武器数降序，数量相同按类别名升序
    for (let i = 1; i < groups.length; i += 1) {
      if (hasFixed[i - 1] !== hasFixed[i]) continue;
      const a = groups[i - 1], b = groups[i];
      assert.ok(a.weapons.length > b.weapons.length || (a.weapons.length === b.weapons.length && a.label < b.label), `${skill.id} ${a.label}/${b.label}`);
    }
    // 默认武器 = 第一组第一把，且是固定武器
    const def = R.defaultWeaponFor(skills, skill);
    assert.equal(def.id, groups[0].weapons[0].id);
    assert.ok(fixedIds.has(def.id));
  });
  // 103 回旋斩：与 macOS / Android 一致，默认武器落在最大的固定组（曲剑）里的最小 id
  const spin = skills.skills.find((skill) => skill.id === 103);
  assert.equal(R.defaultWeaponFor(skills, spin).id, 7000000);
  // 不传 skill 时保持首次出现顺序（旧行为）
  const lion = skills.skills.find((skill) => skill.id === 100);
  const flat = R.weaponsForSkill(skills, lion);
  assert.equal(R.groupWeapons(flat)[0].weapons[0].id, flat[0].id);
});
