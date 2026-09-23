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

  assert.ok(pairs > 8000, "对照样本太少说明遍历写错了（本版本 8540 对）");
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
  // ① 段名（hits[].labelZh，本版本 162 段）。
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
  assert.deepEqual(
    listed.map((item) => item.key), ["jumpAttack", "zzz"],
    "按 ATTACK_CONTEXT_ORDER 的固定顺序排，枚举表里没有的键排最后"
  );
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

// ------------------------------------------------ v4 / v5 字段与两端共用口径

test("scopeVerdict：武器槽 0 / 3 不限，4（踢击）一律判为作用域不符", () => {
  const unlimited = R.scopeInfo({ scope: {} });
  assert.equal(unlimited.slot, 0);
  assert.equal(R.scopeVerdict(unlimited, skillOptions).ok, true);

  const onSelf = R.scopeInfo({ scope: { weaponSlot: 3 } });
  assert.equal(R.scopeVerdict(onSelf, skillOptions).ok, true);
  assert.equal(R.scopeVerdict(onSelf, { mode: "skill", hand: 2 }).ok, true);

  const kick = R.scopeInfo({ scope: { weaponSlot: 4 } });
  assert.equal(R.scopeVerdict(kick, skillOptions).ok, false, "踢击槽与武器／法术命中无关");
  assert.equal(R.scopeVerdict(kick, { mode: "skill", hand: 2 }).ok, false);
});

test("scopeVerdict：法术也按当前手判定 scope.weaponSlot（施法器同样占左右手）", () => {
  const leftHandSorcery = R.scopeInfo({ scope: { weaponSlot: 2, affectsSorcery: true } });
  assert.equal(R.scopeVerdict(leftHandSorcery, { mode: "sorcery", hand: 1 }).ok, false);
  assert.equal(R.scopeVerdict(leftHandSorcery, { mode: "sorcery", hand: 2 }).ok, true);
});

test("scope.spAttribute：默认不计入，打开开关后才进榜", () => {
  const scoped = R.scopeInfo({ scope: { spAttribute: 11 } });
  assert.equal(scoped.attributeScoped, true);
  const blocked = R.scopeVerdict(scoped, skillOptions);
  assert.equal(blocked.ok, false);
  assert.equal(blocked.attribute, true, "要和普通的作用域不符区分开，UI 才能提示『打开开关后计入』");
  assert.equal(
    R.scopeVerdict(scoped, { mode: "skill", hand: 1, includeAttributeScoped: true }).ok,
    true
  );

  // 数据集里确实有一批（油脂类全在这），否则这条判定就该删掉。
  const real = index.entries.filter((entry) => entry.scope.attributeScoped && entry.countsAsDamage);
  assert.ok(real.length > 0, "数据集里应当有 spAttribute 限定且带伤害字段的条目");
});

test("rankEntries：属性限定的条目单独计数，打开开关后条目只增不减", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);

  const base = R.rankEntries(index.entries, comp.shares, skillOptions);
  assert.ok(base.excluded.attribute > 0, "应当有条目因为属性限定被拦下");
  base.rows.forEach((row) => {
    assert.equal(row.entry.scope.attributeScoped, false, "默认榜单里不该有属性限定的条目");
  });

  const opened = R.rankEntries(index.entries, comp.shares, {
    mode: "skill", hand: 1, includeAttributeScoped: true
  });
  assert.ok(opened.rows.length >= base.rows.length, "打开开关后条目不应变少");
  assert.equal(opened.excluded.attribute, 0);
});

test("stackLadder：解出总层数与满层倍率，同一阶梯共用一个叠加组键", () => {
  const ladders = index.entries.filter((entry) => entry.ladder);
  assert.ok(ladders.length > 0, "数据集里应当有 stackLadder 条目");
  assert.equal(
    ladders.length,
    (buffs.buffs || []).filter((buff) => buff.stackLadder).length,
    "每条带 stackLadder 的 buff 都该解出来"
  );

  ladders.forEach((entry) => {
    assert.ok(entry.ladder.tiers > 1, "叠层阶梯至少两层");
    assert.ok(entry.ladder.key.indexOf("ladder#") === 0);
    assert.ok(
      entry.ladder.tierSpEffectIds.indexOf(entry.id) !== -1,
      "阶梯键要把自己也算进去（tierSpEffectIds 是第 2 层起）"
    );
    assert.equal(
      entry.ladder.tierSpEffectIds.length,
      entry.ladder.tiers,
      "并上自己之后应当正好是总层数"
    );
    // 满层数值必须 ≥ 第 1 层。
    R.TYPE_KEYS.forEach((type) => {
      assert.ok(entry.ladder.multiplier[type] >= entry.multiplier[type] - 1e-9);
    });
    assert.equal(R.stackKeyFor(entry), entry.ladder.key, "叠层条目的组键必须是阶梯键");
  });

  const plain = index.entries.find((entry) => !entry.ladder);
  assert.equal(R.stackKeyFor(plain), plain.group, "非叠层条目仍用 stacking.group");
});

test("effectiveFor：「按满层计算」改用 topRates，默认口径不受影响", () => {
  const entry = index.entries.find((one) => one.ladder);
  const shares = {};
  R.TYPE_KEYS.forEach((key) => { shares[key] = 0; });
  shares.slash = 1;

  const first = R.effectiveFor(entry, shares, false);
  const top = R.effectiveFor(entry, shares, true);
  assert.ok(top.multiplier > first.multiplier, "满层数值应当高于第 1 层");
  assert.ok(Math.abs(first.multiplier - entry.multiplier.slash) < 1e-9);
  assert.ok(Math.abs(top.multiplier - entry.ladder.multiplier.slash) < 1e-9);

  // 非叠层条目不受开关影响。
  const plain = index.entries.find((one) => !one.ladder && one.hasMultiplier);
  assert.equal(
    R.effectiveFor(plain, shares, true).multiplier,
    R.effectiveFor(plain, shares, false).multiplier
  );
});

test("rankEntries：ladderTop 开关只改叠层条目的倍率", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);
  const options = { mode: "skill", hand: 1, includeConditional: true };
  const base = R.rankEntries(index.entries, comp.shares, options);
  const top = R.rankEntries(index.entries, comp.shares, Object.assign({ ladderTop: true }, options));

  const baseById = {};
  base.rows.forEach((row) => { baseById[row.id] = row; });
  let changed = 0;
  top.rows.forEach((row) => {
    const before = baseById[row.id];
    if (!before) return;
    if (row.entry.ladder) {
      if (row.multiplier > before.multiplier + 1e-9) changed += 1;
    } else {
      assert.ok(Math.abs(row.multiplier - before.multiplier) < 1e-9, "非叠层条目不该被开关影响");
    }
  });
  assert.ok(changed > 0, "打开后至少有一条叠层条目的倍率变高");

  // 无论开关怎么拨，同一阶梯都只按一层进组合。
  base.rows.concat(top.rows).forEach((row) => {
    if (!row.entry.ladder) return;
    assert.equal(R.stackKeyFor(row.entry), row.entry.ladder.key);
  });
});

test("selfInflictedStatus：解出 v5 的自伤标记，且它们一条都不进伤害乘积", () => {
  const flagged = index.entries.filter((entry) => entry.selfInflictedStatus);
  const raw = (buffs.buffs || []).filter((buff) => buff.selfInflictedStatus === true);
  assert.equal(flagged.length, raw.length, "带 selfInflictedStatus 的条目都该解出来");
  if (buffs.counts && typeof buffs.counts.buffsWithSelfInflictedStatus === "number") {
    assert.equal(flagged.length, buffs.counts.buffsWithSelfInflictedStatus);
  }
  assert.ok(flagged.length > 0, "v5 数据里应当有自伤型异常累积行");

  flagged.forEach((entry) => {
    assert.equal(entry.buff.target, "self", "自伤标记只会出现在 target=self 上");
    assert.equal(entry.hasMultiplier, false, "自伤行不该有伤害倍率");
    assert.equal(entry.hasFlat, false, "自伤行的加算是 status 组，不进攻击力加算");
    assert.equal(entry.countsAsDamage, false, "伤害榜一个数都不该被它们影响");
    entry.otherRateKeys.forEach((key) => {
      const field = index.plan.byKey[key];
      if (field && field.group === "status") {
        assert.equal(field.countsAsDamage, false);
      }
    });
  });
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

test("prefersRow：applyHighest 组按 categoryPriority 取数值小的那一份", () => {
  const strong = {
    id: 1, multiplier: 1.5,
    entry: { buff: { stacking: { spCategoryBehavior: "applyHighest", categoryPriority: 9 } } }
  };
  const prior = {
    id: 2, multiplier: 1.2,
    entry: { buff: { stacking: { spCategoryBehavior: "applyHighest", categoryPriority: 1 } } }
  };
  assert.equal(R.prefersRow(prior, strong), true, "stackingRules 第 4 条：数值小的优先");
  assert.equal(R.prefersRow(strong, prior), false);

  // 不是 applyHighest 的组照旧按倍率高的留下。
  const plainStrong = {
    id: 3, multiplier: 1.5, entry: { buff: { stacking: { spCategoryBehavior: "none", categoryPriority: 9 } } }
  };
  const plainWeak = {
    id: 4, multiplier: 1.2, entry: { buff: { stacking: { spCategoryBehavior: "none", categoryPriority: 1 } } }
  };
  assert.equal(R.prefersRow(plainStrong, plainWeak), true);
  assert.equal(R.prefersRow(plainWeak, plainStrong), false);

  // 倍率与优先度都一样时按 spEffectId 稳定取小的，保证两端结果可重复。
  const a = { id: 5, multiplier: 1.3, entry: { buff: { stacking: { spCategoryBehavior: "none" } } } };
  const b = { id: 6, multiplier: 1.3, entry: { buff: { stacking: { spCategoryBehavior: "none" } } } };
  assert.equal(R.prefersRow(a, b), true);
  assert.equal(R.prefersRow(b, a), false);
});

test("recommendCombo：同一叠层阶梯的两层永远只留一条", () => {
  const ladder = { tiers: 10, saved: true, tierSpEffectIds: [101, 102], key: "ladder#101", multiplier: {} };
  const shared = { group: "sp204", family: "[Relic] Ladder", ladder: ladder, buff: { stacking: {} } };
  const rows = [
    { id: 101, multiplier: 1.05, flat: 0, entry: Object.assign({}, shared) },
    { id: 102, multiplier: 1.63, flat: 0, entry: Object.assign({}, shared) },
    { id: 200, multiplier: 1.10, flat: 0, entry: { group: "sp10#200", family: "[Relic] Other", buff: { stacking: {} } } }
  ];
  const combo = R.recommendCombo(rows, false, false);
  assert.equal(combo.picks.length, 2, "阶梯的两层必须并成一组");
  assert.ok(Math.abs(combo.product - 1.63 * 1.1) < 1e-9, "阶梯组内取更高的那一层");
});

test("推荐组合不受搜索框与来源类型筛选影响（两端同一口径）", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);
  const ranked = R.rankEntries(index.entries, comp.shares, skillOptions);

  const all = R.recommendCombo(ranked.rows, true, false);
  // 模拟「只看遗物词条」这一类视图筛选：组合仍按全部命中条目算。
  const filtered = ranked.rows.filter((row) => row.entry.kinds.indexOf("relicAffix") !== -1);
  assert.ok(filtered.length > 0 && filtered.length < ranked.rows.length, "筛选应当真的筛掉了一些");
  const still = R.recommendCombo(ranked.rows, true, false);
  assert.ok(Math.abs(all.product - still.product) < 1e-12, "视图筛选不参与组合计算");
});

test("默认排名口径：direction 只取 increase / mixed", () => {
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);
  const ranked = R.rankEntries(index.entries, comp.shares, skillOptions);
  ranked.rows.forEach((row) => {
    assert.ok(
      row.entry.direction === "increase" || row.entry.direction === "mixed",
      "#" + row.id + " 的 direction=" + row.entry.direction + " 不该进榜"
    );
  });
  const odd = R.candidateFilter(
    { target: "self", direction: "unknown", countsAsDamage: true, activation: "passive", scope: R.scopeInfo({}) },
    skillOptions
  );
  assert.equal(odd.ok, false);
  assert.equal(odd.reason, "direction");
});

test("数据版本：本页按 buffs schemaVersion 5 的字段口径实现", () => {
  assert.ok(buffs.schemaVersion >= 5, "当前数据集应当是 schemaVersion ≥ 5");
  assert.ok(buffs.notes.stackLadder, "v5 起 notes.stackLadder 必须在（底部原文要展示它）");
  assert.ok(buffs.notes.attackContext, "v4 起 notes.attackContext 必须在");
  assert.equal(typeof buffs.counts.buffsWithSelfInflictedStatus, "number");
  assert.equal(typeof buffs.counts.stateInfoLabels, "number");
  assert.equal(
    Object.keys(buffs.enums.stateInfo || {}).length,
    buffs.counts.stateInfoLabels,
    "enums.stateInfo 的条数应与 counts.stateInfoLabels 对得上"
  );
  // 43 条 target 改判 enemy 的累积行：一条都不该进伤害榜。
  const enemyStatus = (buffs.buffs || []).filter((buff) => buff.target === "enemy");
  assert.ok(enemyStatus.length > 0);
  enemyStatus.forEach((buff) => {
    const entry = index.entries.find((one) => one.id === buff.spEffectId);
    assert.equal(
      R.candidateFilter(entry, skillOptions).reason,
      "target",
      "#" + buff.spEffectId + " 是挂在敌人身上的，必须按 target 拦下"
    );
  });
});

// ============================================================ 两端口径对齐
// 下面这一组断言全部是为了**钉住两端同一套口径**：目标白名单、计数点、chip 顺序、
// 徽标与说明文案、可检索字段、组合的组数定义。macOS 端
// macos/Sources/RelicCoreChecks/BuffRankerChecks.swift 的 checkTwoSidedParity
// 有逐条对应的同名断言。

test("两端对齐：target 用白名单（self 恒取 / ally 看开关 / 其余一律排除）", () => {
  // 与 macOS 端 `["self","ally","summon","enemy"].contains($0.target)` 那条取值词表对应：
  // 数据集当前只有这四种，但页面的判定必须是白名单——黑名单会在数据集加新取值时静默放行。
  const known = ["self", "ally", "summon", "enemy"];
  buffs.buffs.forEach((buff) => {
    assert.ok(known.indexOf(buff.target) !== -1, "#" + buff.spEffectId + " 的 target 取值超出词表：" + buff.target);
  });

  const make = (target) => ({
    target: target, direction: "increase", countsAsDamage: true,
    activation: "passive", scope: R.scopeInfo({})
  });
  assert.equal(R.candidateFilter(make("self"), skillOptions).ok, true);
  assert.equal(R.candidateFilter(make("ally"), skillOptions).reason, "ally");
  assert.equal(
    R.candidateFilter(make("ally"), { mode: "skill", hand: 1, includeAlly: true }).ok, true
  );
  ["summon", "enemy", "party", "", "unknown-future-value"].forEach((target) => {
    assert.equal(
      R.candidateFilter(make(target), skillOptions).reason, "target",
      "target=" + target + " 不在白名单里，必须排除"
    );
  });
});

test("两端对齐：scope.atkAttribute 只作用于一个物理攻击类型（数据集 0 例，用合成用例覆盖）", () => {
  // macOS 端 makeProfile 会把倍率限制到 SkillDamageChannel.physical(code:) 那一个通道，
  // scopeVerdict 在当前构成该通道占比为 0 时返回「限定物理攻击类型」。两端必须同口径。
  const dataHas = buffs.buffs.some((buff) => typeof (buff.scope || {}).atkAttribute === "number");
  assert.equal(dataHas, false, "本版本数据集还没有 atkAttribute；出现后请把这条改成真实用例");

  const info = R.scopeInfo({ scope: { atkAttribute: 0 } });   // 0 = 斩击
  assert.equal(info.atkAttribute, 0);
  assert.equal(info.restrictedType, "slash");

  // 倍率只落在斩击那一格：physicsAttackRate 本来覆盖全部物理子类型。
  const restricted = R.indexBuff({ spEffectId: -601, rates: { physicsAttackRate: 1.5 }, scope: { atkAttribute: 0 } }, plan);
  assert.equal(restricted.multiplier.slash, 1.5);
  ["blow", "thrust", "neutral", "physNone"].forEach((type) => {
    assert.equal(restricted.multiplier[type], 1, type + " 不该吃到只限定斩击的倍率");
  });
  const unrestricted = R.indexBuff({ spEffectId: -602, rates: { physicsAttackRate: 1.5 } }, plan);
  R.TYPES_BY_ELEMENT.physical.forEach((type) => {
    assert.equal(unrestricted.multiplier[type], 1.5, "没有 atkAttribute 时物理各子类型都吃");
  });

  // 当前构成里这个通道占比为 0 → 作用域不符；有占比 → 照常计入；没有构成时不判。
  const zero = R.TYPE_KEYS.reduce((acc, key) => { acc[key] = 0; return acc; }, {});
  const thrustOnly = Object.assign({}, zero, { thrust: 1 });
  const slashOnly = Object.assign({}, zero, { slash: 1 });
  assert.equal(R.scopeVerdict(info, { mode: "skill", hand: 1, shares: slashOnly }).ok, true);
  const missed = R.scopeVerdict(info, { mode: "skill", hand: 1, shares: thrustOnly });
  assert.equal(missed.ok, false);
  assert.equal(missed.reason, "限定物理攻击类型");
  assert.equal(R.scopeVerdict(info, skillOptions).ok, true, "一段都没勾时不判这一关");

  // 叠层阶梯的满层数值同样受限制。
  const ladder = R.indexBuff({
    spEffectId: -603,
    rates: { physicsAttackRate: 1.2 },
    scope: { atkAttribute: 1 },   // 1 = 打击
    stackLadder: { tiers: 3, tierSpEffectIds: [-604], topRates: { physicsAttackRate: 2 }, saved: true }
  }, plan);
  assert.equal(ladder.ladder.multiplier.blow, 2);
  assert.equal(ladder.ladder.multiplier.slash, 1);
});

test("两端对齐：推荐组合的「组数」＝取用条目数，纯加算行不占掉一个叠加组", () => {
  const shares = R.TYPE_KEYS.reduce((acc, key) => { acc[key] = 0; return acc; }, {});
  shares.slash = 1;
  // 同一个叠加组里放两条：一条纯加算（倍率恒为 1、categoryPriority 更小），一条真增伤。
  const group = { group: "sp1234", spCategory: 1234, spCategoryBehavior: "applyHighest", stateInfo: 0 };
  const flatOnly = R.indexBuff({
    spEffectId: 1, rates: { physicsAttackPower: 40 }, target: "self", activation: "passive",
    direction: "increase", stacking: Object.assign({ categoryPriority: 0 }, group)
  }, plan);
  const real = R.indexBuff({
    spEffectId: 2, rates: { physicsAttackRate: 1.3 }, target: "self", activation: "passive",
    direction: "increase", stacking: Object.assign({ categoryPriority: 9 }, group)
  }, plan);
  const ranked = R.rankEntries([flatOnly, real], shares, skillOptions);
  assert.equal(ranked.rows.length, 2, "两条都该进榜（纯加算行按 flat > 0 也算有用）");

  const combo = R.recommendCombo(ranked.rows, true, false);
  assert.equal(combo.picks.length, 1, "同组只取一条");
  assert.equal(combo.groups, combo.picks.length, "「组数」必须等于取用条目数（与 macOS 端 groupCount 同一定义）");
  assert.equal(combo.picks[0].row.id, 2, "纯加算行不得凭更小的 categoryPriority 赢下整组后被丢弃");
  assert.ok(Math.abs(combo.product - 1.3) < 1e-12);

  // 真实数据上：组数恒等于取用条目数，且入选条目一定真增伤。
  const weapon = firstMixedWeapon();
  const skill = skillOf(weapon);
  const comp = R.composition(R.selectHits(skill, weapon).filter((hit) => !hit.noFp), weapon, false);
  const realRanked = R.rankEntries(index.entries, comp.shares, skillOptions);
  const realCombo = R.recommendCombo(realRanked.rows, true, false);
  assert.equal(realCombo.groups, realCombo.picks.length);
  realCombo.picks.forEach((pick) => assert.ok(pick.row.multiplier > 1));
  // 并列倍率按 spEffectId 升序（与 macOS 端 stackPlan 的 picks 排序一致）。
  for (let i = 1; i < realCombo.picks.length; i += 1) {
    const prev = realCombo.picks[i - 1];
    const cur = realCombo.picks[i];
    if (prev.row.multiplier === cur.row.multiplier) {
      assert.ok(prev.row.id < cur.row.id, "并列时应按 spEffectId 升序");
    }
  }
});

test("两端对齐：攻击情境 chip 按固定顺序，且只统计带伤害倍率字段的条目", () => {
  const keys = index.contexts.map((item) => item.key);
  const expected = keys.slice().sort((a, b) => {
    let left = R.ATTACK_CONTEXT_ORDER.indexOf(a);
    let right = R.ATTACK_CONTEXT_ORDER.indexOf(b);
    if (left < 0) left = R.ATTACK_CONTEXT_ORDER.length;
    if (right < 0) right = R.ATTACK_CONTEXT_ORDER.length;
    return left !== right ? left - right : (a < b ? -1 : (a > b ? 1 : 0));
  });
  assert.deepEqual(keys, expected, "chip 顺序不得随数据计数重排");
  index.contexts.forEach((item) => {
    const counted = index.entries.filter((entry) => {
      return entry.countsAsDamage && entry.scope.attackContexts.indexOf(item.key) !== -1;
    }).length;
    assert.equal(item.count, counted, item.key + " 的计数应只含带伤害倍率字段的条目");
    // 数据集自带的 counts.buffsByAttackContext 统计的是**全部**条目，chip 只会更少。
    assert.ok(item.count <= (buffs.counts.buffsByAttackContext || {})[item.key]);
  });
});

test("两端对齐：「本页自己承担的判定」13 条与 macOS 端逐字同文，且条数照数据现算", () => {
  const notes = R.pageRuleNotes(skills, buffs, index);
  assert.equal(notes.length, 13);
  notes.forEach((text) => assert.ok(text && text.length > 20));

  // 锚点表：macOS 端 BuffRankerChecks 里有一份一模一样的。
  const anchors = [
    "weapons[].skillVariant → skills[].variants[i].atkIds",
    "只有法术段忽略 motion",
    "rateFields[].countsAsDamage 为 true 且 valueKind 为 multiplier",
    "武器槽（scope.weaponSlot）",
    "scope.spAttribute（只对带某种属性／异常的攻击生效",
    "叠层阶梯（stackLadder，本版本",
    "selfInflictedStatus（v5，本版本",
    "本页额外做了三条数据集没有直接字段的判定",
    "叠加分组只用数据集算好的 stacking.group",
    "「推荐组合」用全部命中条目计算",
    "攻击力加算（attackPowerFlat）是点数",
    "输出手段列表只收「至少有一段能算出非 0 相对值」的战技与法术",
    "只在特定攻击情境成立的倍率（scope.attackContexts"
  ];
  anchors.forEach((anchor, i) => {
    assert.ok(notes[i].indexOf(anchor) !== -1, "第 " + (i + 1) + " 条应包含锚点「" + anchor + "」");
  });

  // 条数一律现算：把数字挖掉之后的正文在两端必须逐字节相同（FNV-1a 32 位）。
  // 这个摘要与数据无关（数字全部归一成 #），数据集改数值不会弄红它；
  // 两端任何一句措辞漂移都会立刻分叉。macOS 端断言同一个值。
  const normalized = notes.join("\n").replace(/[0-9]+/g, "#");
  let hash = 0x811c9dc5 >>> 0;
  for (const byte of Buffer.from(normalized, "utf8")) {
    hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
  }
  assert.equal(hash.toString(16).padStart(8, "0"), "333839f9", "两端 13 条说明的正文必须逐字相同");

  // 真的照数据现算，不是写死的数字。
  const attributeScoped = buffs.buffs.filter((buff) => typeof (buff.scope || {}).spAttribute === "number").length;
  const melee = index.entries.filter((entry) => entry.scope.meleeOnly).length;
  const without = R.meansWithoutDamage(skills);
  assert.ok(notes[4].indexOf("本版本 " + attributeScoped + " 条") !== -1);
  assert.ok(notes[7].indexOf("等 " + melee + " 条") !== -1);
  assert.ok(notes[11].indexOf("（" + without.skills + " 条）") !== -1);
  assert.ok(notes[11].indexOf("（" + without.spells + " 条）") !== -1);
  assert.ok(without.skills > 0 && without.spells > 0, "确实有一批输出手段被挡在列表外");
});

test("两端对齐：可检索字段取并集（描述 / 来源类型 / spEffectId 都搜得到）", () => {
  const withDesc = buffs.buffs.find((buff) => (buff.descZh || "").length > 6);
  assert.ok(withDesc, "数据集里应当有带 descZh 的条目");
  const entry = index.entries.find((one) => one.id === withDesc.spEffectId);
  assert.ok(entry.searchText.indexOf(withDesc.descZh.slice(0, 6).toLowerCase()) !== -1, "descZh 里的词应当搜得到");
  assert.ok(entry.searchText.indexOf(String(withDesc.spEffectId)) !== -1, "spEffectId 应当搜得到");
  assert.ok(
    entry.searchText.indexOf(R.sourceKindLabel(entry.kinds[0]).toLowerCase()) !== -1,
    "来源类型的中文标签应当搜得到"
  );

  const many = buffs.buffs.find((buff) => (buff.sources || []).length > 6);
  if (many) {
    const row = index.entries.find((one) => one.id === many.spEffectId);
    const last = many.sources[many.sources.length - 1];
    const name = (last.nameZh || last.nameEn || "").toLowerCase();
    if (name) assert.ok(row.searchText.indexOf(name) !== -1, "来源超过 6 个时后面的也要搜得到");
  }
});
