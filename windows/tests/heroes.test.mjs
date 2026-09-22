// 角色属性页（renderer/pages/heroes.js）纯计算层测试。
// 口径以 data/nightreign-heroes-v1.03.5.json 自带的 interpolation / caveats 为准：
//   · 派生值 = CalcCorrectGraph 分段线性插值，血量←生命力(100) / 专注值←集中力(101) /
//     精力←耐力(104) / 负重上限←耐力(220)；前三项向下取整，负重保留 1 位小数。
//     页面自己的插值实现必须与数据集 levels[].derived 逐格一致 —— 这是本文件的主检查项。
//   · 转职遗物只有 L1 / L12 两个锚点，2–11 级推算、13–15 级沿用 L12。
//   · 属性被减到小于 1 时钳到 1（游戏里属性不会低于 1），派生值按钳位后的属性算。
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const Page = require("../renderer/pages/heroes.js");
const H = Page._internals;

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const data = JSON.parse(readFileSync(path.join(repoRoot, "windows", "resources", "heroes.json"), "utf8"));

const ATTR_KEYS = data.statNames.attributeOrder;
const DERIVED_KEYS = data.statNames.derivedOrder;
const LEVELS = [];
for (let level = 1; level <= 15; level += 1) LEVELS.push(level);

function modsOf(heroKey) {
  return data.statModifiers.filter((mod) => mod.heroKey === heroKey);
}

function levelOf(levels, level) {
  return levels.find((row) => row.level === level);
}

test("模块注册：导出 init / refresh，不依赖 window", () => {
  assert.equal(typeof Page.init, "function");
  assert.equal(typeof Page.refresh, "function");
  assert.equal(typeof globalThis.NightreignPages, "undefined", "node 下不应尝试注册页面");
});

test("数据集本身是 schema 1，10 个角色 × 15 级，20 条转职遗物、5 套利普拉交易", () => {
  assert.equal(data.schemaVersion, 1);
  assert.equal(data.heroes.length, 10);
  assert.equal(data.statModifiers.length, 20);
  assert.equal(data.libraRespecs.length, 5);
  data.heroes.forEach((hero) => {
    assert.equal(hero.levels.length, 15, hero.key + " 应有 1–15 级");
    assert.deepEqual(hero.levels.map((row) => row.level), LEVELS);
  });
  assert.ok(Array.isArray(data.caveats) && data.caveats.length > 0, "页面底部要展示 caveats");
  assert.ok(data.interpolation && typeof data.interpolation.baseRule === "string");
});

test("属性 / 派生值的中文名与顺序一律读数据集 statNames", () => {
  const attrs = H.attributeDefs(data);
  assert.deepEqual(attrs.map((def) => def.key), ATTR_KEYS);
  assert.deepEqual(attrs.map((def) => def.zh), ["生命力", "集中力", "耐力", "力气", "灵巧", "智力", "信仰", "感应"]);
  const derived = H.derivedDefs(data);
  assert.deepEqual(derived.map((def) => def.key), DERIVED_KEYS);
  assert.deepEqual(derived.map((def) => def.zh), ["血量", "专注值", "精力", "负重上限"]);
  // 负重上限是唯一的非整数列，格式化时保留 1 位小数。
  assert.equal(derived.find((def) => def.key === "equipLoad").integer, false);
  assert.equal(derived.find((def) => def.key === "hp").integer, true);
});

test("派生值重算：每个角色每一级都必须等于数据集的 levels[].derived", () => {
  let checked = 0;
  data.heroes.forEach((hero) => {
    hero.levels.forEach((row) => {
      const got = H.deriveStats(data, row.stats);
      assert.deepEqual(
        got,
        {
          hp: row.derived.hp,
          fp: row.derived.fp,
          stamina: row.derived.stamina,
          equipLoad: row.derived.equipLoad
        },
        hero.key + " " + row.level + " 级派生值与数据集不一致"
      );
      checked += DERIVED_KEYS.length;
    });
  });
  assert.equal(checked, 10 * 15 * 4, "应逐格核对 600 个派生值");
});

test("派生值重算：利普拉 5 套替换表同样逐格一致", () => {
  let checked = 0;
  data.libraRespecs.forEach((deal) => {
    assert.equal(deal.levels.length, 15);
    deal.levels.forEach((row) => {
      assert.deepEqual(H.deriveStats(data, row.stats), {
        hp: row.derived.hp,
        fp: row.derived.fp,
        stamina: row.derived.stamina,
        equipLoad: row.derived.equipLoad
      }, "利普拉（" + deal.key + "）" + row.level + " 级派生值与数据集不一致");
      checked += DERIVED_KEYS.length;
    });
  });
  assert.equal(checked, 5 * 15 * 4);
});

test("派生值只吃对应的那一项属性：改别的属性不动它", () => {
  const base = { vigor: 20, mind: 10, endurance: 12, strength: 30, dexterity: 30, intelligence: 5, faith: 5, arcane: 5 };
  const before = H.deriveStats(data, base);
  const after = H.deriveStats(data, Object.assign({}, base, { strength: 60, dexterity: 60, arcane: 40 }));
  assert.deepEqual(after, before);
  // 生命力 +1 只动血量（100 的斜率恒为 20：血量 = 20 × 生命力 + 80）
  const moreVigor = H.deriveStats(data, Object.assign({}, base, { vigor: 21 }));
  assert.equal(moreVigor.hp, before.hp + 20);
  assert.equal(moreVigor.fp, before.fp);
  assert.equal(moreVigor.stamina, before.stamina);
});

test("growthGraphs 的分段公式：端点钳位 + 数据集自述的三条直线", () => {
  const hp = data.growthGraphs["100"];
  assert.equal(H.evalGrowthGraph(hp, 1), 100);
  assert.equal(H.evalGrowthGraph(hp, 0), 100, "低于最低锚点钳到端点");
  assert.equal(H.evalGrowthGraph(hp, 99), 2060);
  assert.equal(H.evalGrowthGraph(hp, 150), 2060, "高于最高锚点钳到端点");
  for (let stat = 1; stat <= 99; stat += 1) {
    assert.equal(Math.floor(H.evalGrowthGraph(hp, stat)), 20 * stat + 80, "血量 = 20 × 生命力 + 80");
    assert.equal(Math.floor(H.evalGrowthGraph(data.growthGraphs["101"], stat)), 5 * stat + 45, "专注值 = 5 × 集中力 + 45");
    if (stat <= 75) {
      assert.equal(Math.floor(H.evalGrowthGraph(data.growthGraphs["104"], stat)), 2 * stat + 48, "精力 = 2 × 耐力 + 48");
    }
  }
  assert.equal(H.evalGrowthGraph(null, 10), null);
  assert.equal(H.evalGrowthGraph(hp, "x"), null);
});

test("转职遗物 12 级锚点：叠加结果 = 基础 stats + delta，派生值按叠加后的属性重算", () => {
  let checked = 0;
  data.statModifiers.forEach((mod) => {
    const hero = data.heroes.find((item) => item.key === mod.heroKey);
    const baseRow = levelOf(hero.levels, 12);
    const modRow = levelOf(mod.levels, 12);
    assert.equal(modRow.isAnchor, true, "12 级必须是转职遗物的参数锚点");
    const computed = H.computeLevel(data, {
      heroKey: mod.heroKey,
      level: 12,
      modifierIds: [mod.affixId]
    });
    assert.ok(computed.modified, "勾了词条就该有修改后的结果");
    ATTR_KEYS.forEach((key) => {
      const expected = baseRow.stats[key] + (modRow.delta[key] || 0);
      assert.equal(computed.modified.stats[key], expected,
        mod.nameZh + " 的 " + key + " 应为 " + expected);
      checked += 1;
    });
    assert.deepEqual(computed.base.stats, H.pickStats(baseRow.stats, H.attributeDefs(data)));
    assert.deepEqual(computed.base.derived, {
      hp: baseRow.derived.hp,
      fp: baseRow.derived.fp,
      stamina: baseRow.derived.stamina,
      equipLoad: baseRow.derived.equipLoad
    });
    assert.deepEqual(computed.modified.derived, H.deriveStats(data, computed.modified.stats));
    assert.equal(computed.note.label, "遗物锚点");
  });
  assert.equal(checked, 20 * 8);
});

test("转职遗物 1 级锚点同样成立，且 anchors[] 与 levels[] 对得上", () => {
  data.statModifiers.forEach((mod) => {
    const anchor1 = mod.anchors.find((row) => row.level === 1);
    const anchor12 = mod.anchors.find((row) => row.level === 12);
    assert.deepEqual(levelOf(mod.levels, 1).delta, anchor1.delta);
    assert.deepEqual(levelOf(mod.levels, 12).delta, anchor12.delta);
    const hero = data.heroes.find((item) => item.key === mod.heroKey);
    const baseRow = levelOf(hero.levels, 1);
    const computed = H.computeLevel(data, { heroKey: mod.heroKey, level: 1, modifierIds: [mod.affixId] });
    ATTR_KEYS.forEach((key) => {
      const raw = baseRow.stats[key] + (anchor1.delta[key] || 0);
      assert.equal(computed.modified.stats[key], Math.max(1, raw));
    });
  });
});

test("13–15 级沿用 12 级锚点：delta 逐项相同，且带「沿用 12 级锚点」标记", () => {
  data.statModifiers.forEach((mod) => {
    const at12 = levelOf(mod.levels, 12).delta;
    [13, 14, 15].forEach((level) => {
      const row = levelOf(mod.levels, level);
      assert.deepEqual(row.delta, at12, mod.nameZh + " " + level + " 级应沿用 12 级 delta");
      assert.equal(row.isAnchor, false);
      assert.equal(row.inferred, true);
      assert.equal(H.modifierLevelNote(level).label, "沿用 12 级锚点");
      assert.equal(H.modifierLevelNote(level).kind, "carried");
    });
  });
});

test("2–11 级是推算：数据集标了 inferred，页面给「推算」标记", () => {
  [2, 3, 4, 5, 6, 7, 8, 9, 10, 11].forEach((level) => {
    assert.equal(H.modifierLevelNote(level).label, "推算");
    assert.equal(H.modifierLevelNote(level).kind, "inferred");
  });
  [1, 12].forEach((level) => {
    assert.equal(H.modifierLevelNote(level).label, "遗物锚点");
    assert.equal(H.modifierLevelNote(level).kind, "anchor");
  });
  data.statModifiers.forEach((mod) => {
    mod.levels.forEach((row) => {
      const isAnchorLevel = row.level === 1 || row.level === 12;
      assert.equal(row.isAnchor, isAnchorLevel);
      assert.equal(row.inferred, !isAnchorLevel);
    });
  });
});

test("两条词条可同时勾选：增减量相加，派生值按合计后的属性重算", () => {
  data.heroes.forEach((hero) => {
    const mods = modsOf(hero.key);
    assert.equal(mods.length, 2, hero.key + " 应恰好有 2 条转职遗物词条");
    const level = 12;
    const baseRow = levelOf(hero.levels, level);
    const computed = H.computeLevel(data, {
      heroKey: hero.key,
      level,
      modifierIds: mods.map((mod) => mod.affixId)
    });
    assert.equal(computed.modifiers.length, 2);
    ATTR_KEYS.forEach((key) => {
      const sum = mods.reduce((acc, mod) => acc + (levelOf(mod.levels, level).delta[key] || 0), 0);
      assert.equal(computed.deltas[key] || 0, sum);
      assert.equal(computed.modified.stats[key], Math.max(1, baseRow.stats[key] + sum));
    });
    assert.deepEqual(computed.modified.derived, H.deriveStats(data, computed.modified.stats));
  });
});

test("钳位：叠加后小于 1 的属性钳到 1，钳位前的原值记在 clamped 里", () => {
  const defs = H.attributeDefs(data);
  const base = { vigor: 10, mind: 2, endurance: 10, strength: 10, dexterity: 1, intelligence: 10, faith: 10, arcane: 10 };
  const applied = H.applyDeltas(base, { mind: -5, dexterity: -1, vigor: -9 }, defs);
  assert.equal(applied.stats.mind, 1, "2 − 5 = −3 → 钳到 1");
  assert.equal(applied.stats.dexterity, 1, "1 − 1 = 0 → 钳到 1");
  assert.equal(applied.stats.vigor, 1, "10 − 9 = 1 → 正好 1，不算钳位");
  assert.equal(applied.clamped.mind, -3);
  assert.equal(applied.clamped.dexterity, 0);
  assert.equal(Object.prototype.hasOwnProperty.call(applied.clamped, "vigor"), false);
  // 钳位后的派生值按 1 算，不是按负数算
  assert.equal(H.deriveStats(data, applied.stats).fp, H.deriveStats(data, { mind: 1 }).fp);
});

test("钳位在真实组合里会发生：利普拉（力气）+ 铁之眼的降灵巧词条", () => {
  const mod = data.statModifiers.find(
    (item) => item.heroKey === "ironeye" && (item.delta || levelOf(item.levels, 12).delta).dexterity < 0
  );
  assert.ok(mod, "铁之眼应有降灵巧的词条");
  const libra = data.libraRespecs.find((deal) => deal.key === "strength");
  const level = 12;
  const computed = H.computeLevel(data, {
    heroKey: "ironeye",
    level,
    libraKey: "strength",
    modifierIds: [mod.affixId]
  });
  const baseRow = levelOf(libra.levels, level);
  assert.deepEqual(computed.base.stats, H.pickStats(baseRow.stats, H.attributeDefs(data)),
    "选了利普拉交易后基础表应整套换成 libraRespecs 的表");
  const raw = baseRow.stats.dexterity + levelOf(mod.levels, level).delta.dexterity;
  assert.ok(raw < 1, "这一组合叠加后确实会小于 1（否则本用例失去意义）");
  assert.equal(computed.modified.stats.dexterity, 1);
  assert.equal(computed.clamped.dexterity, raw);
  assert.deepEqual(computed.modified.derived, H.deriveStats(data, computed.modified.stats));
});

test("利普拉的交易是整套替换：基础表换成 libraRespecs，且与角色原表不同", () => {
  const defs = H.attributeDefs(data);
  data.libraRespecs.forEach((deal) => {
    const computed = H.computeLevel(data, { heroKey: "wylder", level: 15, libraKey: deal.key });
    assert.equal(computed.libraKey, deal.key);
    assert.deepEqual(computed.base.stats, H.pickStats(levelOf(deal.levels, 15).stats, defs));
    assert.deepEqual(computed.base.derived, H.deriveStats(data, computed.base.stats));
    assert.equal(computed.modified, null, "没勾词条时不产生修改后的表");
  });
  const plain = H.computeLevel(data, { heroKey: "wylder", level: 15 });
  const swapped = H.computeLevel(data, { heroKey: "wylder", level: 15, libraKey: "faith" });
  assert.notDeepEqual(plain.base.stats, swapped.base.stats);
  // 5 套表不分角色：换角色不改变替换后的结果
  const other = H.computeLevel(data, { heroKey: "recluse", level: 15, libraKey: "faith" });
  assert.deepEqual(other.base.stats, swapped.base.stats);
});

test("全部等级表：15 行，锚点标记与数据集 isAnchor 一致，每行派生值可复算", () => {
  const rows = H.computeAllLevels(data, { heroKey: "guardian", modifierIds: [] });
  assert.equal(rows.length, 15);
  const hero = data.heroes.find((item) => item.key === "guardian");
  rows.forEach((row, index) => {
    const source = hero.levels[index];
    assert.equal(row.level, source.level);
    assert.equal(row.isAnchor, source.isAnchor);
    assert.deepEqual(row.base.derived, {
      hp: source.derived.hp,
      fp: source.derived.fp,
      stamina: source.derived.stamina,
      equipLoad: source.derived.equipLoad
    });
  });
  assert.deepEqual(rows.filter((row) => row.isAnchor).map((row) => row.level), [1, 2, 12, 15],
    "基础表的参数锚点是 1 / 2 / 12 / 15 级");
});

test("computeLevel 的兜底：未知角色返回 null，等级越界钳进 1–15", () => {
  assert.equal(H.computeLevel(data, { heroKey: "不存在", level: 15 }), null);
  assert.equal(H.computeLevel(null, { heroKey: "wylder", level: 15 }), null);
  assert.equal(H.clampLevel(0), 1);
  assert.equal(H.clampLevel(99), 15);
  assert.equal(H.clampLevel("7"), 7);
  assert.equal(H.clampLevel(undefined), 15);
  assert.equal(H.computeLevel(data, { heroKey: "wylder", level: 99 }).level, 15);
  // 勾了别的角色的词条不会生效
  const foreign = modsOf("recluse")[0].affixId;
  const computed = H.computeLevel(data, { heroKey: "wylder", level: 12, modifierIds: [foreign] });
  assert.equal(computed.modified, null);
});

test("同级对比：10 行，数值等于各角色本级基础表（不含利普拉与转职遗物）", () => {
  const rows = H.compareRows(data, 15);
  assert.equal(rows.length, 10);
  rows.forEach((row) => {
    const hero = data.heroes.find((item) => item.key === row.heroKey);
    const source = levelOf(hero.levels, 15);
    ATTR_KEYS.forEach((key) => assert.equal(row.stats[key], source.stats[key]));
    DERIVED_KEYS.forEach((key) => assert.equal(row.derived[key], source.derived[key]));
    assert.equal(row.nameZh, hero.nameZh);
    assert.equal(row.nameEn, hero.nameEn);
  });
  assert.deepEqual(H.compareRows(data, 1).map((row) => row.level), new Array(10).fill(1));
});

test("同级对比排序：点列头升降序切换，不修改入参，同值按角色原顺序兜底", () => {
  const rows = H.compareRows(data, 15);
  const snapshot = rows.map((row) => row.heroKey);

  const desc = H.sortCompareRows(rows, "vigor", "desc");
  for (let i = 1; i < desc.length; i += 1) {
    assert.ok(desc[i - 1].stats.vigor >= desc[i].stats.vigor, "降序应单调不增");
  }
  const asc = H.sortCompareRows(rows, "vigor", "asc");
  assert.deepEqual(asc.map((row) => row.stats.vigor).slice().sort((a, b) => a - b), asc.map((row) => row.stats.vigor));
  assert.equal(desc[0].stats.vigor, Math.max(...rows.map((row) => row.stats.vigor)));

  // 派生值列也能排（血量随生命力单调，两列顺序应一致）
  const byHp = H.sortCompareRows(rows, "hp", "desc").map((row) => row.heroKey);
  assert.deepEqual(byHp, desc.map((row) => row.heroKey));

  // 角色列 = 数据集原顺序
  assert.deepEqual(H.sortCompareRows(rows, "hero", "asc").map((row) => row.heroKey),
    data.heroes.map((hero) => hero.key));

  assert.deepEqual(rows.map((row) => row.heroKey), snapshot, "排序不得修改入参数组");
  assert.equal(H.compareValue(rows[0], "不存在的列"), null);
});

test("同值时按角色原顺序兜底，排序结果稳定", () => {
  const rows = H.compareRows(data, 1);
  const flat = rows.map((row) => Object.assign({}, row, { stats: Object.assign({}, row.stats, { arcane: 10 }) }));
  const sorted = H.sortCompareRows(flat, "arcane", "desc");
  assert.deepEqual(sorted.map((row) => row.order), flat.map((row) => row.order).slice().sort((a, b) => a - b));
});

test("文案：属性名取数据集 zh，增减量摘要按属性顺序且带正负号", () => {
  const defs = H.attributeDefs(data);
  const mod = data.statModifiers.find((item) => item.affixId === 6640000);
  assert.ok(mod, "应能找到【追踪者】提升集中力但降低生命力");
  assert.equal(H.deltaSummary(levelOf(mod.levels, 12).delta, defs), "生命力 -5、集中力 +10");
  assert.equal(H.deltaSummary({}, defs), "");
  assert.equal(H.fmtSigned(3), "+3");
  assert.equal(H.fmtSigned(-3), "-3");
  assert.equal(H.fmtSigned(0), "0");
  assert.equal(H.deltaClass(2), "heroes-delta--up");
  assert.equal(H.deltaClass(-2), "heroes-delta--down");
  assert.equal(H.deltaClass(0), "heroes-delta--flat");
});

test("格式化：血量/专注值/精力是整数，负重上限保留 1 位小数，缺值显示破折号", () => {
  const derived = H.derivedDefs(data);
  const hp = derived.find((def) => def.key === "hp");
  const equip = derived.find((def) => def.key === "equipLoad");
  assert.equal(H.fmtDerived(hp, 1280), "1280");
  assert.equal(H.fmtDerived(equip, 72), "72.0");
  assert.equal(H.fmtDerived(equip, 46.6), "46.6");
  assert.equal(H.fmtDerived(hp, null), "—");
  assert.equal(H.fmtStat(52), "52");
  assert.equal(H.fmtStat(null), "—");
});

test("数据未内置的判定：占位 JSON / 缺 growthGraphs 一律走降级分支", () => {
  assert.equal(H.hasHeroData(data), true);
  assert.equal(H.hasHeroData(null), false);
  assert.equal(H.hasHeroData({ placeholder: true }), false);
  assert.equal(H.hasHeroData({ heroes: [] }), false);
  assert.equal(H.hasHeroData({ heroes: [{ key: "x" }] }), false, "缺 growthGraphs 就没法重算派生值");
});

test("与 wiki 的差异按 crossChecks 提示：女爵有差异、追踪者没有", () => {
  const duchess = H.crossCheckFor(data, "duchess");
  assert.ok(duchess, "女爵的灵巧列与两个 wiki 对不上，页面要提示");
  assert.ok(duchess.mismatchCount > 0);
  assert.equal(duchess.authoritative, "params");
  assert.equal(H.crossCheckFor(data, "wylder"), null);
  assert.equal(H.crossCheckFor(data, "executor"), null);
});

test("转职遗物的遗物出处与池信息完整：每条都有 relicItems 与池号", () => {
  data.statModifiers.forEach((mod) => {
    assert.ok(Array.isArray(mod.relicItems) && mod.relicItems.length > 0, mod.nameZh + " 应有携带它的遗物");
    mod.relicItems.forEach((item) => {
      assert.equal(typeof item.nameZh, "string");
      assert.ok(item.nameZh.length > 0);
      assert.ok(item.color >= 0 && item.color <= 3, "颜色下标应落在 红/蓝/黄/绿 之内");
      assert.equal(typeof item.colorZh, "string");
    });
    assert.ok(Array.isArray(mod.rollablePoolIds));
  });
  const dlcOnly = data.statModifiers.filter((mod) => mod.dlcOnly);
  assert.equal(dlcOnly.length, data.counts.dlcOnlyStatModifiers, "只靠 DLC 权重掉落的词条数应与 counts 对上");
  assert.deepEqual(dlcOnly.map((mod) => mod.heroKey).sort(), ["scholar", "scholar", "undertaker", "undertaker"]);
});

test("selectedModifiers 只认本角色的词条，且按传入的 id 过滤（字符串 / 数字都行）", () => {
  const mods = modsOf("recluse");
  const picked = H.selectedModifiers(data, "recluse", [String(mods[0].affixId)]);
  assert.equal(picked.length, 1);
  assert.equal(picked[0].affixId, mods[0].affixId);
  assert.equal(H.selectedModifiers(data, "recluse", [mods[1].affixId]).length, 1);
  assert.equal(H.selectedModifiers(data, "recluse", []).length, 0);
  assert.equal(H.selectedModifiers(data, "recluse", [modsOf("wylder")[0].affixId]).length, 0);
  assert.equal(H.modifiersForHero(data, "不存在").length, 0);
});
