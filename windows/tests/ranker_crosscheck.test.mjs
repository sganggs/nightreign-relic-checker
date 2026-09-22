// 增伤排名页的**双端对照用例**：与 macOS 端
// macos/Sources/RelicCoreChecks/BuffRankerChecks.swift 的 checkCrossPlatformCases
// 用的是同一组输入、同一套断言口径。
//
// 两端各自把「同一算法的中间量」断言成一致——构成占比、前 10 名及其有效倍率、推荐组合总倍率
// 都在各自这一侧用一份**独立重算的参考实现**校对（参考实现不复用被测代码的任何分支）。
// 只要两边都绿，两端算出来的数就必然对得上；数值本身会随数据集修订变化，
// 所以这里一律**不写绝对快照**，只写结构性与相对断言。
//
// 需要人工对拍时：
//   NR_RANKER_DUMP=1 node --test windows/tests/ranker_crosscheck.test.mjs
//   NR_RANKER_DUMP=1 swift run RelicCoreChecks   （在 macos/ 下）
// 两边都会打出同一格式的 CASE 行，逐行比即可。
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
const index = R.indexBuffs(buffs);

// 与 macOS 端 crossCases 一一对应。
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
  physicsAttackRate: R.TYPES_BY_ELEMENT.physical,
  physicsAttackPowerRate: R.TYPES_BY_ELEMENT.physical,
  magicAttackRate: ["magic"], magicAttackPowerRate: ["magic"],
  fireAttackRate: ["fire"], fireAttackPowerRate: ["fire"],
  thunderAttackRate: ["lightning"], thunderAttackPowerRate: ["lightning"],
  darkAttackRate: ["holy"], darkAttackPowerRate: ["holy"],
  slashAttackRate: ["slash"], slashAttackPowerRate: ["slash"],
  blowAttackRate: ["blow"], blowAttackPowerRate: ["blow"],
  thrustAttackRate: ["thrust"], thrustAttackPowerRate: ["thrust"],
  neutralAttackRate: ["neutral"], neutralAttackPowerRate: ["neutral"]
};

// 有效倍率：直接从这条 buff 的 rates + rateFields 重算。
function referenceMultiplier(buff, shares) {
  const fields = {};
  (buffs.rateFields || []).forEach((field) => { fields[field.key] = field; });
  const perChannel = {};
  TYPE_KEYS.forEach((key) => { perChannel[key] = 1; });
  Object.keys(buff.rates || {}).forEach((key) => {
    const field = fields[key];
    const value = buff.rates[key];
    if (!field || field.countsAsDamage !== true || field.valueKind !== "multiplier") return;
    if (typeof value !== "number" || !isFinite(value) || value <= 0 || value === field.default) return;
    (FIELD_CHANNELS[key] || []).forEach((channel) => { perChannel[channel] *= value; });
  });
  return TYPE_KEYS.reduce((sum, key) => sum + shares[key] * perChannel[key], 0);
}

// ---- 跑一个用例 --------------------------------------------------------

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
  const options = {
    mode: def.kind, hand: 1, includeAlly: false, includeConditional: false,
    includeAttributeScoped: false, ladderTop: false, contexts: {}
  };
  const result = R.rankEntries(index.entries, comp.shares, options);
  const combo = R.recommendCombo(result.rows, true, false);
  return { def, weapon, hits, selected, comp, result, combo, isSpell };
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

// ---- 断言 --------------------------------------------------------------

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
    assert.ok(run.comp.total > 0, "相对伤害总量应为正");
  });

  test("对照用例 " + def.key + "：前 10 名与有效倍率", () => {
    const top = run.result.rows.slice(0, 10);
    assert.equal(top.length, Math.min(10, run.result.rows.length), "前 10 名应取满");
    top.forEach((row, i) => {
      if (i === 0) return;
      assert.ok(top[i - 1].multiplier >= row.multiplier, "前 10 名必须按有效倍率降序");
    });
    top.forEach((row) => {
      const buff = buffById[row.id];
      assert.ok(buff, "榜上出现了数据集里没有的 #" + row.id);
      close(
        row.multiplier,
        referenceMultiplier(buff, run.comp.shares),
        "#" + row.id + " 的有效倍率应等于 Σ 占比 × 适用倍率连乘"
      );
    });
  });

  test("对照用例 " + def.key + "：推荐组合", () => {
    const combo = run.combo;
    close(
      combo.product,
      combo.picks.reduce((product, pick) => product * pick.row.multiplier, 1),
      "组合总倍率应是入选条目的连乘"
    );
    const groups = combo.picks.map((pick) => pick.row.entry.group);
    assert.equal(new Set(groups).size, groups.length, "每个叠加组只应出现一次");
    combo.picks.forEach((pick) => {
      assert.ok(pick.row.multiplier > 1, "推荐组合只应含真正增伤的条目");
    });
    const best = run.result.rows.length ? run.result.rows[0].multiplier : 1;
    assert.ok(combo.product >= best - 1e-6, "组合总倍率不应低于榜首单条");
    // 「组数」与 macOS 端 BuffStackPlan.groupCount 同一定义＝取用条目数。
    assert.equal(combo.groups, combo.picks.length, "组数必须等于取用条目数");
  });

  test("对照用例 " + def.key + "：排除条数按原因分类（与 macOS 端同一计数点）", () => {
    const excluded = run.result.excluded;
    // 属性限定只统计「其余各关都过、单单被 spAttribute 拦下」的那些。
    assert.ok(excluded.attribute > 0, "应有被属性／异常限定拦下的条目");
    const reasonTotal = Object.keys(excluded.scopeReasons)
      .filter((key) => key !== "只在特定攻击情境成立")
      .reduce((total, key) => total + excluded.scopeReasons[key], 0);
    assert.equal(reasonTotal, excluded.scope, "分项条数之和应等于『作用域不符』总数");
    assert.equal(
      excluded.scopeReasons["只在特定攻击情境成立"] || 0, excluded.context,
      "情境闸门在分项里的条数应等于『受攻击情境限制』的条数"
    );
    assert.ok(
      !("限定属性／异常攻击" in excluded.scopeReasons),
      "属性限定不该同时记进作用域分项（否则两端计数点又错位了）"
    );
  });
});

// ---- 跨用例关系 --------------------------------------------------------

test("对照：构成相同的两次选段，排名与组合必须逐项相同", () => {
  const full = results["corpse-piler-full"];
  const last = results["corpse-piler-last"];
  assert.ok(full.selected.length > last.selected.length, "全段应比只勾一段多");
  // 尸横遍野每段的五属性 motion 同值 → 只勾一段与全勾的占比完全一样。
  TYPE_KEYS.forEach((key) => {
    close(full.comp.shares[key], last.comp.shares[key], key + " 占比应一致");
  });
  assert.deepEqual(
    full.result.rows.slice(0, 10).map((row) => row.id),
    last.result.rows.slice(0, 10).map((row) => row.id),
    "构成相同 → 前 10 名必须完全相同"
  );
  full.result.rows.slice(0, 10).forEach((row, i) => {
    close(row.multiplier, last.result.rows[i].multiplier, "第 " + (i + 1) + " 名倍率应一致");
  });
  close(full.combo.product, last.combo.product, "构成相同 → 推荐组合总倍率必须完全相同");
});

test("对照：同一战技换一把带火属性的武器，火占比与榜单随之变化", () => {
  const plain = results["lions-claw-greatsword"];
  const flame = results["lions-claw-flame-greatsword"];
  close(plain.comp.shares.fire, 0, "普通大剑的火占比应为 0");
  assert.ok(flame.comp.shares.fire > 0, "火焰大剑的火占比应大于 0");
  assert.deepEqual(
    plain.selected.map((hit) => hit.atkId),
    flame.selected.map((hit) => hit.atkId),
    "同一战技同一套段，换武器不该改变选段"
  );
  const fireOnly = flame.result.rows.filter((row) => {
    const table = row.entry.multiplier;
    return table.fire > 1 && TYPE_KEYS.every((key) => key === "fire" || Math.abs(table[key] - 1) < 1e-9);
  });
  assert.ok(fireOnly.length > 0, "火焰大剑下应能进来只加火的条目");
  const plainIds = new Set(plain.result.rows.map((row) => row.id));
  fireOnly.forEach((row) => {
    assert.ok(!plainIds.has(row.id), "只加火的条目不该出现在纯物理构成的榜上（#" + row.id + "）");
  });
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
  assert.ok(run.hits.some((hit) => hit.noDamage === true), "喷火里应有 noDamage 段（耐力消耗）");
  assert.ok(
    run.selected.every((hit) => hit.noDamage !== true),
    "noDamage 段不该进构成"
  );
});

test("对照：法术的构成只来自 flat，不会凭空多出物理", () => {
  ["death-lightning", "comet"].forEach((key) => {
    const run = results[key];
    R.TYPES_BY_ELEMENT.physical.forEach((type) => {
      close(run.comp.shares[type], 0, key + " 是法术，" + type + " 占比必须为 0");
    });
    assert.ok(run.combo.product > 1, key + " 应能给出理论叠加组合");
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
      if (!weapon) return false;
      return R.hasAnyDamage(R.selectHits(skill, weapon), weapon, false);
    });
    assert.ok(playable, "列表里的战技「" + item.nameZh + "」必须至少有一把武器算得出构成");
  });
  spellItems.forEach((item) => {
    const spell = skills._spellById[item.id];
    assert.ok(
      R.hasAnyDamage(spell.hits, null, true),
      "列表里的法术「" + item.nameZh + "」必须至少有一段带固定值"
    );
  });

  // 反面：确实有一批被挡在外面，否则这条口径是空跑。
  const droppedSkills = (skills.skills || []).filter((skill) => {
    if (!Array.isArray(skill.hits) || !skill.hits.length) return false;
    if (!Array.isArray(skill.weaponIds) || !skill.weaponIds.length) return false;
    return !R.skillHasDamage(skills, skill);
  });
  const droppedSpells = (skills.spells || []).filter((spell) => {
    return Array.isArray(spell.hits) && spell.hits.length && !R.hasAnyDamage(spell.hits, null, true);
  });
  assert.ok(droppedSkills.length > 0, "应当有算不出伤害的战技被挡在列表外");
  assert.ok(droppedSpells.length > 0, "应当有算不出伤害的法术被挡在列表外");

  if (process.env.NR_RANKER_DUMP === "1") {
    console.log("OUTPUTS skills=" + skillItems.length + " spells=" + spellItems.length);
  }
});

test("对照：七组用例覆盖了战技全段 / 单段 / 多武器 / 子弹 / 魔法 / 祷告", () => {
  assert.equal(CASES.length, 7);
  const kinds = new Set(CASES.map((def) => def.kind));
  assert.ok(kinds.has("skill") && kinds.has("sorcery") && kinds.has("incantation"));
  // 每组都要真的算出东西来，否则这份对照就是空跑。
  CASES.forEach((def) => {
    const run = results[def.key];
    assert.ok(run.result.rows.length > 0, def.key + " 应有命中条目");
    assert.ok(run.combo.picks.length > 0, def.key + " 应有推荐组合");
  });

  if (process.env.NR_RANKER_DUMP === "1") {
    CASES.forEach((def) => {
      const run = results[def.key];
      const shares = TYPE_KEYS.map((key) => run.comp.shares[key].toFixed(9)).join(",");
      const top = run.result.rows.slice(0, 10)
        .map((row) => row.id + ":" + row.multiplier.toFixed(9)).join(",");
      const excluded = run.result.excluded;
      const reasons = Object.keys(excluded.scopeReasons).sort((a, b) => {
        const diff = excluded.scopeReasons[b] - excluded.scopeReasons[a];
        return diff !== 0 ? diff : (a < b ? -1 : (a > b ? 1 : 0));
      }).map((key) => key + ":" + excluded.scopeReasons[key]).join("|");
      console.log(
        "CASE " + def.key +
        " selected=" + run.selected.map((hit) => hit.atkId).join(",") +
        " shares=" + shares +
        " rows=" + run.result.rows.length +
        " top10=" + top +
        " combo=" + run.combo.product.toFixed(9) +
        " picks=" + run.combo.picks.length +
        " groups=" + run.combo.groups +
        " excluded=" + excluded.context + "/" + excluded.attribute + "/" + excluded.scope +
        " reasons=" + reasons
      );
    });
  }
});
