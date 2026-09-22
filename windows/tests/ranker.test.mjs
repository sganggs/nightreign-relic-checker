// 增伤排名页（renderer/pages/ranker.js）纯计算层测试。
//
// 口径以两份数据集自带的说明为准：
//   · skills：usage.选段（必读）／近战武器段／法术 · 子弹段／削韧／伤害类型（斩 / 打 / 突）
//   · buffs：notes.ranking、notes.howToUseRates、stackingRules、rateFields[].countsAsDamage
//
// 数据集仍在做取值层面的修复，所以这里一律写**结构性断言**
// （某个字段存在、某个占比大于 0、某个排序关系成立），不断言具体数值。
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const Page = require("../renderer/pages/ranker.js");
const R = Page._internals;

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const resource = (name) => path.join(repoRoot, "windows", "resources", name);
const skills = R.decorateSkills(JSON.parse(readFileSync(resource("skills.json"), "utf8")));
const buffs = JSON.parse(readFileSync(resource("buffs.json"), "utf8"));

const plan = R.rateFieldPlan(buffs);
const index = R.indexBuffs(buffs);
const skillOptions = { mode: "skill", hand: 1, includeAlly: false, includeConditional: false };

// 一把「物理 + 属性都有基础攻击力」的武器，用来验证构成会同时出现两种伤害类型。
function firstMixedWeapon() {
  return skills.weapons.find((weapon) => {
    const base = weapon.attackBase || {};
    const elemental = ["magic", "fire", "lightning", "holy"].some((key) => Number(base[key]) > 0);
    return Number(base.physical) > 0 && elemental && typeof weapon.skillVariant === "number";
  });
}

function skillOf(weapon) {
  return skills.skills.find((skill) => (skill.weaponIds || []).indexOf(weapon.id) !== -1);
}

test("模块注册：导出 init / refresh，不依赖 window", () => {
  assert.equal(typeof Page.init, "function");
  assert.equal(typeof Page.refresh, "function");
  assert.equal(typeof globalThis.NightreignPages, "undefined", "node 下不应尝试注册页面");
});

test("两份数据集都带着页面真正依赖的结构（schemaVersion 只卡下限，新版本不得弄红）", () => {
  // skills 第三轮不动，仍是 2；buffs 会升到 4（只增字段），所以这里只能卡下限。
  assert.equal(skills.schemaVersion, 2);
  assert.ok(buffs.schemaVersion >= 3, "buffs schemaVersion 应当 ≥ 3（v4 只增字段，向后兼容）");
  assert.ok(skills.usage && skills.usage["选段（必读）"], "选段规则必须来自数据集");
  assert.ok(skills.usage["本数据集的边界"], "页面要引用『绝对伤害不在范围内』这段");
  assert.ok(Array.isArray(skills.caveats) && skills.caveats.length > 0);
  assert.ok(buffs.notes && buffs.notes.ranking, "底部折叠要展示 notes.ranking 原文");
  assert.ok(buffs.notes.howToUseRates && buffs.notes.activation);
  assert.ok(buffs.stackingRules && buffs.stackingRules.zh, "底部折叠要展示 stackingRules 原文");
  // 页面真正读的那些键必须在：倍率字段表、来源枚举、子类别枚举、每条 buff 的 scope/stacking。
  assert.ok(Array.isArray(buffs.rateFields) && buffs.rateFields.length > 0);
  assert.ok(buffs.enums && buffs.enums.sourceKind && buffs.enums.atkSubCategory);
  assert.ok(Array.isArray(buffs.enums.spCategoryBehavior));
  buffs.buffs.forEach((buff) => {
    assert.equal(typeof buff.spEffectId, "number");
    assert.ok(buff.scope && typeof buff.scope === "object", buff.spEffectId + " 缺 scope");
    assert.ok(buff.stacking && typeof buff.stacking.group === "string", buff.spEffectId + " 缺 stacking.group");
    assert.ok(typeof buff.activation === "string" && typeof buff.target === "string");
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

test("selectHits：一律走 weapons[].skillVariant → variants[i].atkIds，不取并集", () => {
  const multi = skills.skills.find((skill) => Array.isArray(skill.variants) && skill.variants.length > 1);
  assert.ok(multi, "数据集里应当有多套动作的战技");
  const seen = new Set();
  multi.variants.forEach((variant, position) => {
    const weapon = skills._weaponById[variant.weaponIds[0]];
    assert.equal(weapon.skillVariant, position, "variant 的下标必须就是武器的 skillVariant");
    const hits = R.selectHits(multi, weapon);
    assert.equal(hits.length, variant.atkIds.length);
    hits.forEach((hit) => assert.ok(variant.atkIds.indexOf(hit.atkId) !== -1));
    assert.ok(hits.length < multi.hits.length || multi.variants.length === 1, "取并集会把段数撑到全表");
    hits.forEach((hit) => seen.add(hit.atkId));
  });
  assert.ok(seen.size <= multi.hits.length);
});

test("selectVariant / selectHits：武器没有 skillVariant 就是打不出段", () => {
  const skill = skills.skills.find((one) => Array.isArray(one.variants) && one.variants.length);
  assert.equal(R.selectVariant(skill, {}), null);
  assert.deepEqual(R.selectHits(skill, {}), []);
  assert.deepEqual(R.selectHits({ hits: [] }, {}), []);
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
});

test("hitOverridesFor：「全选」只勾当前 FP 侧，FP 段与无FP 段不会同时计入", () => {
  const hits = [
    { atkId: 1 },
    { atkId: 2, noFp: true },
    { atkId: 3, noDamage: true }
  ];
  const all = R.hitOverridesFor(hits, "all", false);
  assert.equal(all[1], true);
  assert.equal(all[2], false, "无FP 版与 FP 版互为替代，一起勾会把同一击算两遍");
  assert.equal(3 in all, false, "noDamage 段不参与");

  const allNoFp = R.hitOverridesFor(hits, "all", true);
  assert.equal(allNoFp[1], false);
  assert.equal(allNoFp[2], true);

  assert.deepEqual(R.hitOverridesFor(hits, "none", false), { 1: false, 2: false });
  assert.deepEqual(R.hitOverridesFor(hits, "reset", false), {}, "恢复默认＝清空 override");

  // 真实数据：全选之后相对值合计不会翻倍（= 与默认勾选一致）。
  const weapon = skills.weapons.find((one) => typeof one.skillVariant === "number" &&
    skills.skills.some((skill) => (skill.weaponIds || []).indexOf(one.id) !== -1 &&
      R.selectHits(skill, one).some((hit) => hit.noFp)));
  assert.ok(weapon, "数据集里应当有带无FP 版本的战技");
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

test("削韧 / 耐力：poise + 武器基础 × mv / 100", () => {
  const weapon = { poiseDamageBase: 10, staminaBase: 40 };
  assert.equal(R.hitPoise({ poise: 5, poiseMv: 200 }, weapon), 25);
  assert.equal(R.hitStamina({ stamina: 2, staminaMv: 50 }, weapon), 22);
  assert.equal(R.hitPoise({}, weapon), 0);
});

// ------------------------------------------------------------------ 作用范围

test("scopeVerdict：战技命中按战技攻击子类别（112）匹配", () => {
  const skillScoped = R.scopeInfo({ scope: { subCategories: [R.SKILL_SUB_CATEGORY, 111] } });
  assert.equal(R.scopeVerdict(skillScoped, skillOptions).ok, true);

  const jumpOnly = R.scopeInfo({ scope: { subCategories: [102] } });
  assert.equal(R.scopeVerdict(jumpOnly, skillOptions).ok, false);

  const unscoped = R.scopeInfo({ scope: {} });
  assert.equal(R.scopeVerdict(unscoped, skillOptions).ok, true);
});

test("scopeVerdict：武器槽默认右手，左手条目不计入", () => {
  const left = R.scopeInfo({ scope: { weaponSlot: 2 } });
  assert.equal(R.scopeVerdict(left, skillOptions).ok, false);
  assert.equal(R.scopeVerdict(left, { mode: "skill", hand: 2 }).ok, true);

  const right = R.scopeInfo({ scope: { weaponSlot: 1 } });
  assert.equal(R.scopeVerdict(right, skillOptions).ok, true);
  assert.equal(R.scopeVerdict(right, { mode: "skill", hand: 2 }).ok, false);
});

test("scopeVerdict：只作用于法术的条目不计入战技，反之亦然", () => {
  const sorceryOnly = R.scopeInfo({
    scope: { weaponSlot: 3, affectsSorcery: true, affectsIncantation: false, affectsShaman: false }
  });
  assert.equal(sorceryOnly.spellOnly, true);
  assert.equal(R.scopeVerdict(sorceryOnly, skillOptions).ok, false);
  assert.equal(R.scopeVerdict(sorceryOnly, { mode: "sorcery", hand: 1 }).ok, true);
  assert.equal(R.scopeVerdict(sorceryOnly, { mode: "incantation", hand: 1 }).ok, false);

  // 纯武器 buff（一个法术标记都没点）对魔法／祷告不生效。
  const weaponOnly = R.scopeInfo({ scope: {} });
  assert.equal(R.scopeVerdict(weaponOnly, { mode: "sorcery", hand: 1 }).ok, false);
});

test("scopeVerdict：只点亮 affectsThrow 的条目＝致命一击／投掷，不进通用排名", () => {
  const throwOnly = R.scopeInfo({ scope: { affectsThrow: true } });
  assert.equal(throwOnly.throwOnly, true);
  assert.equal(R.scopeVerdict(throwOnly, skillOptions).ok, false);
  assert.equal(R.scopeVerdict(throwOnly, { mode: "incantation", hand: 1 }).ok, false);

  // 数据集里确实存在这种签名（否则这条判定就该删掉）。
  const real = index.entries.filter((entry) => entry.scope.throwOnly && entry.hasMultiplier);
  assert.ok(real.length > 0, "数据集里应当有只点 affectsThrow 的倍率条目");
  real.forEach((entry) => {
    assert.equal(R.scopeVerdict(entry.scope, skillOptions).ok, false);
  });
});

test("scopeVerdict：只标 130（近战武器攻击）而没有 112 的条目在战技模式下判为作用域不符", () => {
  const melee = R.scopeInfo({ scope: { subCategories: [R.MELEE_SUB_CATEGORY] } });
  assert.equal(melee.meleeOnly, true);
  const verdict = R.scopeVerdict(melee, skillOptions);
  assert.equal(verdict.ok, false);
  assert.ok(verdict.reason.indexOf("130") !== -1, "排除原因要点明是哪一条判定，供底部说明分项展示");

  // 同时标了 112 的就照常放行。
  const both = R.scopeInfo({ scope: { subCategories: [R.MELEE_SUB_CATEGORY, R.SKILL_SUB_CATEGORY] } });
  assert.equal(both.meleeOnly, false);
  assert.equal(R.scopeVerdict(both, skillOptions).ok, true);
});

test("scope.attackContexts：默认不计入，勾选该情境后才参与（v3 数据里没有这个键 = no-op）", () => {
  // notes.ranking（v4）第④步：attackContexts 非空＝只在列出的攻击情境下吃得到。
  const gated = R.scopeInfo({ scope: { attackContexts: ["thrustingCounter", "guardCounter"] } });
  assert.deepEqual(gated.attackContexts, ["thrustingCounter", "guardCounter"]);

  const off = R.scopeVerdict(gated, skillOptions);
  assert.equal(off.ok, false, "默认不得乘进通用排名");
  assert.equal(off.context, true, "要能和普通的『作用域不符』区分开，UI 才能提示『勾选情境后计入』");

  const on = R.scopeVerdict(gated, { mode: "skill", hand: 1, contexts: { guardCounter: true } });
  assert.equal(on.ok, true, "勾选了其中一个情境就应当参与乘算");

  const other = R.scopeVerdict(gated, { mode: "skill", hand: 1, contexts: { jumpAttack: true } });
  assert.equal(other.ok, false, "勾了别的情境不算");

  // attackContexts 存在时以它为准，不再用 affectsThrow 推断（否则会被 throwOnly 先拦掉）。
  const throwWithContext = R.scopeInfo({ scope: { affectsThrow: true, attackContexts: ["criticalHit"] } });
  assert.equal(throwWithContext.throwOnly, false);
  assert.equal(R.scopeVerdict(throwWithContext, { mode: "skill", hand: 1, contexts: { criticalHit: true } }).ok, true);

  // 缺失 attackContexts（当前 v3 数据）时一切照旧：判定与排名不受影响。
  const plain = R.scopeInfo({ scope: {} });
  assert.deepEqual(plain.attackContexts, []);
  assert.equal(R.scopeVerdict(plain, skillOptions).ok, true);
});

test("rankEntries：受攻击情境限制的条目单独计数，作用域排除按原因分项", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);

  // 给一条合成条目挂上情境限制，确认它默认不进榜、勾选情境后进榜。
  const gated = R.indexBuff({
    spEffectId: -99,
    rates: { physicsAttackRate: 1.5 },
    target: "self",
    activation: "passive",
    direction: "increase",
    stacking: { group: "sp0#-99", spCategory: 0, spCategoryBehavior: "none", stateInfo: 0 },
    scope: { attackContexts: ["jumpAttack"] }
  }, plan);
  const entries = index.entries.concat([gated]);

  const base = R.rankEntries(entries, comp.shares, skillOptions);
  assert.ok(base.excluded.context >= 1, "情境限制要单独计数，不混进『作用域不符』");
  assert.equal(base.rows.some((row) => row.id === -99), false);

  const picked = R.rankEntries(entries, comp.shares,
    { mode: "skill", hand: 1, includeAlly: false, includeConditional: false, contexts: { jumpAttack: true } });
  assert.equal(picked.rows.some((row) => row.id === -99), true, "勾选情境后应当参与排名");

  // 作用域排除给出按原因的分项，总数对得上。
  const reasons = base.excluded.scopeReasons;
  assert.ok(Object.keys(reasons).length > 0);
  const summed = Object.keys(reasons).reduce((total, key) => total + reasons[key], 0);
  assert.equal(summed, base.excluded.scope + base.excluded.context);
});

test("availableContexts：中文名一律取 enums.attackContext，没有这个键时返回空表", () => {
  assert.deepEqual(R.availableContexts({}, []), []);
  assert.deepEqual(R.availableContexts(buffs, index.entries), index.contexts);
  index.contexts.forEach((item) => {
    assert.ok(item.zh && item.count > 0);
    assert.ok(buffs.enums.attackContext && buffs.enums.attackContext[item.key],
      item.key + " 必须能在 enums.attackContext 里查到中文名");
  });

  const fake = {
    enums: { attackContext: { jumpAttack: { zh: "跳跃攻击", en: "Jump Attack" } } }
  };
  const entries = [
    R.indexBuff({ spEffectId: 1, rates: { fireAttackRate: 1.1 }, scope: { attackContexts: ["jumpAttack"] } }, plan),
    R.indexBuff({ spEffectId: 2, rates: { fireAttackRate: 1.2 }, scope: { attackContexts: ["jumpAttack", "zzz"] } }, plan),
    R.indexBuff({ spEffectId: 3, rates: { saAttackPowerRate: 2 }, scope: { attackContexts: ["zzz"] } }, plan)
  ];
  const listed = R.availableContexts(fake, entries);
  assert.deepEqual(listed.map((item) => item.key), ["jumpAttack", "zzz"], "按命中数降序");
  assert.equal(listed[0].zh, "跳跃攻击");
  assert.equal(listed[0].count, 2);
  assert.equal(listed[1].count, 1, "不带伤害倍率的条目不计数");
});

test("scope.subCategories 的取值都能在 enums.atkSubCategory 里查到中文名", () => {
  let checked = 0;
  buffs.buffs.forEach((buff) => {
    ((buff.scope || {}).subCategories || []).forEach((value) => {
      assert.ok(buffs.enums.atkSubCategory[String(value)], "子类别 " + value + " 没有中文名");
      checked += 1;
    });
  });
  assert.ok(checked > 0);
});

// ------------------------------------------------------------------ 有效倍率

test("effectiveFor：Σ 占比 × 该类型的倍率连乘", () => {
  const entry = R.indexBuff({ spEffectId: -7, rates: { physicsAttackRate: 1.5, fireAttackRate: 1.1 } }, plan);
  const pure = R.effectiveFor(entry, Object.assign(R.TYPE_KEYS.reduce((acc, key) => {
    acc[key] = 0;
    return acc;
  }, {}), { slash: 1 }));
  assert.ok(Math.abs(pure.multiplier - 1.5) < 1e-9);

  const half = R.effectiveFor(entry, Object.assign(R.TYPE_KEYS.reduce((acc, key) => {
    acc[key] = 0;
    return acc;
  }, {}), { slash: 0.5, fire: 0.5 }));
  assert.ok(Math.abs(half.multiplier - (0.5 * 1.5 + 0.5 * 1.1)) < 1e-9);
  assert.ok(half.multiplier < pure.multiplier, "属性占比越高，纯物理倍率的收益越低");

  // 没勾任何段时不给倍率。
  const none = R.effectiveFor(entry, R.TYPE_KEYS.reduce((acc, key) => { acc[key] = 0; return acc; }, {}));
  assert.equal(none.multiplier, 1);
  assert.equal(none.useful, false);
});

test("effectiveFor：只带点数加算的条目倍率仍是 1，但按占比加权后算有收益", () => {
  const entry = R.indexBuff({ spEffectId: -8, rates: { fireAttackPower: 40 } }, plan);
  const shares = R.TYPE_KEYS.reduce((acc, key) => { acc[key] = 0; return acc; }, {});
  shares.fire = 0.5;
  shares.slash = 0.5;
  const effective = R.effectiveFor(entry, shares);
  assert.equal(effective.multiplier, 1);
  assert.ok(Math.abs(effective.flat - 20) < 1e-9);
  assert.equal(effective.useful, true);
});

// ------------------------------------------------------------------ 排名

test("rankEntries：默认只留 self + increase/mixed + passive + 作用域匹配", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);
  const ranked = R.rankEntries(index.entries, comp.shares, skillOptions);

  assert.ok(ranked.rows.length > 0);
  ranked.rows.forEach((row) => {
    assert.equal(row.entry.target, "self");
    assert.equal(row.entry.activation, "passive");
    assert.notEqual(row.entry.direction, "decrease");
    assert.equal(R.scopeVerdict(row.entry.scope, skillOptions).ok, true);
  });
  for (let i = 1; i < ranked.rows.length; i += 1) {
    assert.ok(ranked.rows[i - 1].multiplier >= ranked.rows[i].multiplier, "必须按有效倍率降序");
  }
  assert.ok(ranked.excluded.scope > 0 || ranked.excluded.activation > 0);
});

test("rankEntries：打开条件型 / 队友开关后条目只增不减", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);

  const base = R.rankEntries(index.entries, comp.shares, skillOptions);
  const withConditional = R.rankEntries(index.entries, comp.shares,
    { mode: "skill", hand: 1, includeAlly: false, includeConditional: true });
  const withAlly = R.rankEntries(index.entries, comp.shares,
    { mode: "skill", hand: 1, includeAlly: true, includeConditional: true });

  assert.ok(withConditional.rows.length > base.rows.length, "条件型条目应当能被纳入");
  assert.ok(withAlly.rows.length >= withConditional.rows.length);
  assert.ok(withConditional.rows.some((row) => row.conditional === true));
  assert.ok(withAlly.rows.some((row) => row.entry.target === "ally"));
});

test("rankEntries：法术按魔法／祷告匹配，换一边结果就不一样", () => {
  const spell = skills.spells.find((one) => one.kind === "sorcery" && (one.hits || []).length > 0);
  const comp = R.composition(spell.hits, null, true);
  const asSorcery = R.rankEntries(index.entries, comp.shares, { mode: "sorcery", hand: 1, includeAlly: false, includeConditional: false });
  const asIncantation = R.rankEntries(index.entries, comp.shares, { mode: "incantation", hand: 1, includeAlly: false, includeConditional: false });
  const ids = (result) => result.rows.map((row) => row.id).sort().join(",");
  assert.ok(asSorcery.rows.length > 0);
  assert.notEqual(ids(asSorcery), ids(asIncantation), "魔法与祷告的可用条目不该完全相同");
});

// ------------------------------------------------------------------ 叠加与组合

test("stackingGroupKey：一律用数据集算好的 stacking.group，stateInfo 不参与分组", () => {
  // stackingRules 第 3 条：stateInfo「并不是互斥分组」，只是「值得怀疑」。
  assert.equal(
    R.stackingGroupKey({ stacking: { spCategoryBehavior: "stackSelf", stateInfo: 367, group: "sp10#1" } }),
    "sp10#1"
  );
  assert.equal(
    R.stackingGroupKey({ stacking: { spCategoryBehavior: "none", stateInfo: 0, group: "sp0#1" } }),
    "sp0#1"
  );
  assert.equal(
    R.stackingGroupKey({ stacking: { spCategoryBehavior: "removePrevious", stateInfo: 9, group: "sp151" } }),
    "sp151"
  );
  // 交叉参考键单独给出，只对本身不互斥的 none / stackSelf 有意义。
  assert.equal(
    R.stateGroupKey({ stacking: { spCategoryBehavior: "stackSelf", stateInfo: 367, group: "sp10#1" } }),
    "state#367"
  );
  assert.equal(R.stateGroupKey({ stacking: { spCategoryBehavior: "stackSelf", stateInfo: 0 } }), null);
  assert.equal(R.stateGroupKey({ stacking: { spCategoryBehavior: "removePrevious", stateInfo: 9 } }), null);
});

test("stateInfo 交叉参考默认关闭：同一 stateInfo 下挂着互不相干的效果，不能当成一个叠加组", () => {
  // 数据实测：至少有一个 stateInfo 值下面挂着一堆 paramName 完全不同的条目
  // （护符、遗物、武器被动各一套），按它合并会把本可共存的组合砍掉。
  const byState = new Map();
  index.entries.forEach((entry) => {
    if (!entry.state) return;
    if (!byState.has(entry.state)) byState.set(entry.state, []);
    byState.get(entry.state).push(entry);
  });
  const mixed = [...byState.values()].filter((list) => {
    const families = new Set(list.map((entry) => entry.family));
    return list.length > 2 && families.size === list.length;
  });
  assert.ok(mixed.length > 0, "应当存在『同 stateInfo 但互不同族』的成组条目");

  // 这些条目必须落在各自独立的叠加组里（默认口径）。
  const sample = mixed[0];
  const rows = sample.map((entry) => ({ id: entry.id, multiplier: 1.1, flat: 0, entry }));
  const relaxed = R.bucketRows(rows, false, false);
  assert.equal(Object.keys(relaxed).length, rows.length, "默认口径下不该按 stateInfo 并成一组");
  // 打开交叉参考开关才合并，用户可以随时退回。
  const strict = R.bucketRows(rows, false, true);
  assert.equal(Object.keys(strict).length, 1, "打开开关后按 stateInfo 合并成一组");
  assert.ok(R.recommendCombo(rows, false, true).product <= R.recommendCombo(rows, false, false).product);
});

test("每条 buff 的 spCategoryBehavior 都能在 enums 里查到标签", () => {
  const codes = new Set(buffs.enums.spCategoryBehavior.map((row) => row.code));
  buffs.buffs.forEach((buff) => {
    assert.ok(codes.has(buff.stacking.spCategoryBehavior), buff.spEffectId + " 的叠加行为查不到标签");
  });
});

test("familyKey：档位后缀归一到同一族", () => {
  const potency1 = R.familyKey({ spEffectId: 1, paramName: "[Weapon] Improved Skill Attack Power - Potency 1" });
  const potency3 = R.familyKey({ spEffectId: 2, paramName: "[Weapon] Improved Skill Attack Power - Potency 3" });
  assert.equal(potency1, potency3);
  assert.equal(
    R.familyKey({ spEffectId: 3, paramName: "[Relic] Physical Attack Up +4" }),
    R.familyKey({ spEffectId: 4, paramName: "[Relic] Physical Attack Up" })
  );
  assert.equal(
    R.familyKey({ spEffectId: 5, paramName: "[Item - Level 3] Exalted Flesh" }),
    R.familyKey({ spEffectId: 6, paramName: "[Item] Exalted Flesh" })
  );
  assert.notEqual(
    R.familyKey({ spEffectId: 7, paramName: "[Talisman] Improved Skill Attack Power" }),
    potency1,
    "护符与武器被动是两件东西，不该并成一族"
  );
  assert.equal(R.familyKey({ spEffectId: 8, paramName: null }), "id#8");
});

test("recommendCombo：同组只取一条，连乘等于取出条目的乘积", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);
  const ranked = R.rankEntries(index.entries, comp.shares, skillOptions);

  const merged = R.recommendCombo(ranked.rows, true);
  const raw = R.recommendCombo(ranked.rows, false);

  assert.ok(merged.picks.length > 0);
  assert.ok(merged.picks.length <= raw.picks.length, "合并同族后组数只会更少");
  assert.ok(merged.product <= raw.product + 1e-9);

  const product = merged.picks.reduce((total, pick) => total * pick.row.multiplier, 1);
  assert.ok(Math.abs(product - merged.product) < 1e-9);

  const groups = merged.picks.map((pick) => pick.row.entry.group);
  assert.equal(new Set(groups).size, groups.length, "同一个叠加组不该出现两条");
  merged.picks.forEach((pick) => assert.ok(pick.row.multiplier > 1));
});

test("bucketRows：同一个 stacking 组的条目一定落在同一个桶里", () => {
  const rows = [
    { id: 1, multiplier: 1.2, flat: 0, entry: { group: "sp151", family: "[Item] A", buff: { stacking: {} } } },
    { id: 2, multiplier: 1.1, flat: 0, entry: { group: "sp151", family: "[Item] B", buff: { stacking: {} } } },
    { id: 3, multiplier: 1.3, flat: 0, entry: { group: "sp10#3", family: "[Weapon] C", buff: { stacking: {} } } },
    { id: 4, multiplier: 1.4, flat: 0, entry: { group: "sp10#4", family: "[Weapon] C", buff: { stacking: {} } } }
  ];
  const separate = R.bucketRows(rows, false);
  assert.equal(Object.keys(separate).length, 3);
  const merged = R.bucketRows(rows, true);
  assert.equal(Object.keys(merged).length, 2, "同族的 sp10#3 / sp10#4 应当并成一桶");

  const combo = R.recommendCombo(rows, true);
  assert.equal(combo.picks.length, 2);
  assert.ok(Math.abs(combo.product - 1.2 * 1.4) < 1e-9, "每桶取最高");
});

// ------------------------------------------------------------------ 列表与格式

test("buildMeansItems / filterMeans：中英文都能搜到，且只收算得出构成的条目", () => {
  const items = R.buildMeansItems(skills);
  assert.ok(items.length > 0);
  assert.ok(items.some((item) => item.kind === "skill"));
  assert.ok(items.some((item) => item.kind === "sorcery"));
  assert.ok(items.some((item) => item.kind === "incantation"));

  // 收录口径：有命中段 + （战技）至少一把武器引用 + 至少能算出一段非 0 相对值。
  // 算不出构成的条目选中后只会停在「当前没有勾选任何带伤害的段」，是死路。
  const skillIds = new Set(items.filter((item) => item.kind === "skill").map((item) => item.id));
  skills.skills.forEach((skill) => {
    const usable = (skill.hits || []).length > 0 && (skill.weaponIds || []).length > 0 &&
      R.skillHasDamage(skills, skill);
    assert.equal(skillIds.has(skill.id), usable, skill.id + " 的收录判定不对");
  });
  assert.ok(
    skills.skills.some((skill) => (skill.hits || []).length > 0 && !(skill.weaponIds || []).length),
    "数据集里应当确实存在『有段但没有武器引用』的战技"
  );

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

test("sourceKindsOf / 徽标：数据集里出现的来源类型都有中文名", () => {
  const known = new Set(R.SOURCE_KINDS.map((kind) => kind.key));
  Object.keys(buffs.enums.sourceKind).forEach((kind) => {
    assert.ok(known.has(kind), "来源类型 " + kind + " 在页面上没有徽标");
    assert.ok(R.sourceKindLabel(kind) !== kind, kind + " 没有中文名");
  });
  assert.deepEqual(R.sourceKindsOf({ sources: [] }), ["other"]);
  assert.deepEqual(R.sourceKindsOf({ sources: [{ kind: "goods" }, { kind: "goods" }] }), ["goods"]);
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

test("性能：索引只建一次，选段变化时的重算是纯加权（全表远低于 50ms）", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const hits = R.selectHits(skill, weapon);
  const started = Date.now();
  for (let i = 0; i < 20; i += 1) {
    const comp = R.composition(hits.slice(0, (i % hits.length) + 1), weapon, false);
    R.rankEntries(index.entries, comp.shares, skillOptions);
  }
  const elapsed = Date.now() - started;
  assert.ok(elapsed < 50 * 20, "20 次全表重算用了 " + elapsed + "ms，太慢了");
  assert.equal(index.entries.length, buffs.buffs.length, "索引应当覆盖全表");
});
