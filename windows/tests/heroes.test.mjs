// 角色属性页（renderer/pages/heroes.js）纯计算层测试。
// 口径以 data/nightreign-heroes-v1.03.5.json 自带的 interpolation / caveats 为准：
//   · 派生值 = CalcCorrectGraph 分段线性插值，血量←生命力(100) / 专注值←集中力(101) /
//     精力←耐力(104) / 负重上限←耐力(220)；前三项向下取整，负重保留 1 位小数。
//     页面自己的插值实现必须与数据集 levels[].derived 逐格一致 —— 这是本文件的主检查项。
//   · 转职遗物只有 L1 / L12 两个锚点，2–11 级推算、13–15 级沿用 L12 —— 锚点等级读数据集
//     的 interpolation.modifierAnchorLevels，页面不写死。
//   · 属性被减到小于 1 时钳到 1（游戏里属性不会低于 1），派生值按钳位后的属性算。
//
// 本文件最后一段是「双端对照基线」：6 组真实数据（5 组单角色快照 + 1 组同级对比排序）
// 与一整份共用文案，macOS 端 RelicCoreChecks/HeroStatsChecks.swift 的
// checkHeroCrossEndFixtures / checkHeroCrossEndCopy 跑的是同一张表、同一批期望值。
// 改这里请连同那边一起改，否则两端会各自红一片 —— 这正是它们存在的意义。
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
    assert.equal(computed.note.label, "词条锚点");
    assert.equal(computed.note.source, "anchor");
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
      assert.equal(H.modifierLevelNote(data, level).label, "词条沿用 12 级锚点");
      assert.equal(H.modifierLevelNote(data, level).source, "carried");
    });
  });
});

test("2–11 级是推算：数据集标了 inferred，页面给「词条推算」标记", () => {
  [2, 3, 4, 5, 6, 7, 8, 9, 10, 11].forEach((level) => {
    assert.equal(H.modifierLevelNote(data, level).label, "词条推算");
    assert.equal(H.modifierLevelNote(data, level).source, "inferred");
  });
  [1, 12].forEach((level) => {
    assert.equal(H.modifierLevelNote(data, level).label, "词条锚点");
    assert.equal(H.modifierLevelNote(data, level).source, "anchor");
  });
  data.statModifiers.forEach((mod) => {
    mod.levels.forEach((row) => {
      const isAnchorLevel = row.level === 1 || row.level === 12;
      assert.equal(row.isAnchor, isAnchorLevel);
      assert.equal(row.inferred, !isAnchorLevel);
    });
  });
});

test("锚点等级读数据集而不是写死 1/12：换一组锚点，标记跟着走", () => {
  assert.deepEqual(H.modifierAnchorLevels(data), [1, 12]);
  assert.deepEqual(H.baseAnchorLevels(data), [1, 2, 12, 15]);
  assert.equal(H.maxLevelOf(data), 15);
  // 直接喂一组别的锚点：文案里的等级必须跟着数据走
  assert.equal(H.COPY.modifierSource(9, [1, 8]).label, "词条沿用 8 级锚点");
  assert.equal(H.COPY.modifierSource(8, [1, 8]).label, "词条锚点");
  assert.equal(H.COPY.modifierSource(5, [1, 8]).label, "词条推算");
  // 数据集没给锚点信息时什么都不标（不瞎标「推算」）
  assert.equal(H.COPY.modifierSource(3, []), null);
  assert.equal(H.modifierLevelNote({ heroes: [] }, 3), null);
  // 说明文字里的等级同样取自数据集
  assert.equal(
    H.modifierRuleHint(data),
    "锚点只有 1 / 12 级：中间等级是线性插值后向零取整的推算值，12 级之后沿用 12 级锚点" +
      "（沿用这一条已由多组 15 级实测确认）。"
  );
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
  const top = H.maxLevelOf(data);
  assert.equal(H.clampLevel(0, top), 1);
  assert.equal(H.clampLevel(99, top), 15);
  assert.equal(H.clampLevel("7", top), 7);
  assert.equal(H.clampLevel(undefined, top), 15);
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

// ---------------------------------------------------------------------------
// 双端对照基线：6 组真实数据，两端逐格钉死同一批数字与同一批文案。
//
// macOS 端 RelicCoreChecks/HeroStatsChecks.swift 的 checkHeroCrossEndFixtures 用
// 同一张表跑同一批断言（同样的角色 / 等级 / 词条 / 利普拉，同样的期望值）。
// 任何一端的纯逻辑漂了，两端的用例会各自红 —— 这就是「双端一致」的可执行定义。
// 每一组既钉死绝对值（属性 / 派生值 / 钳位 / 文案），也断言相对关系
// （最终值 = max(1, 基础 + 增减量)、派生值可由最终属性复算）。
const FIXTURES = [
  {
    name: "追踪者 15 级：两条词条全勾",
    heroKey: "wylder",
    level: 15,
    modifierIds: [6640000, 6640100],
    libraKey: "",
    isAnchor: true,
    baseStats: [52, 19, 27, 50, 40, 15, 15, 10],
    baseDerived: { hp: 1120, fp: 140, stamina: 102, equipLoad: 74.1 },
    delta: { vigor: -5, mind: 10, strength: -7, dexterity: -5, intelligence: 15, faith: 15 },
    // cardDelta = 卡片 / 表格里显示的那个数（生效值 = 最终 − 基础）。没钳位时与 delta 相同。
    cardDelta: { vigor: -5, mind: 10, strength: -7, dexterity: -5, intelligence: 15, faith: 15 },
    finalStats: [47, 29, 27, 43, 35, 30, 30, 10],
    finalDerived: { hp: 1020, fp: 190, stamina: 102, equipLoad: 74.1 },
    clamped: {},
    noteLabel: "词条沿用 12 级锚点",
    noteSource: "carried"
  },
  {
    name: "铁之眼 15 级：利普拉（力气）+ 降灵巧词条（会钳位）",
    heroKey: "ironeye",
    level: 15,
    modifierIds: [6642000],
    libraKey: "strength",
    isAnchor: true,
    baseStats: [47, 6, 23, 73, 9, 3, 3, 3],
    baseDerived: { hp: 1020, fp: 75, stamina: 94, equipLoad: 68.8 },
    delta: { dexterity: -9, arcane: 15 },
    // 灵巧被钳到 1：词条请求 -9，真正生效的只有 -8 —— 卡片上的大数字写 -8，
    // 请求值 -9 只出现在小字里（clampRequestedText）。macOS 端钉的是同一组数。
    cardDelta: { dexterity: -8, arcane: 15 },
    clampRequestedText: "词条请求 -9，已钳到最低 1",
    finalStats: [47, 6, 23, 73, 1, 3, 3, 18],
    finalDerived: { hp: 1020, fp: 75, stamina: 94, equipLoad: 68.8 },
    clamped: { dexterity: 0 },
    clampSummary: "灵巧 叠加后不足 1，已钳到最低 1（游戏里属性不会低于 1）",
    noteLabel: "词条沿用 12 级锚点",
    noteSource: "carried"
  },
  {
    name: "学者 5 级：第 2 条词条（有 deltaFloorAlt）",
    heroKey: "scholar",
    level: 5,
    modifierIds: [6647300],
    libraKey: "",
    isAnchor: false,
    baseStats: [20, 9, 10, 5, 7, 12, 6, 50],
    baseDerived: { hp: 480, fp: 90, stamina: 68, equipLoad: 48.2 },
    delta: { endurance: 2, dexterity: 18, intelligence: -2, arcane: -10 },
    cardDelta: { endurance: 2, dexterity: 18, intelligence: -2, arcane: -10 },
    finalStats: [20, 9, 12, 5, 25, 10, 6, 40],
    finalDerived: { hp: 480, fp: 90, stamina: 72, equipLoad: 51.4 },
    clamped: {},
    floorAlt: { intelligence: -3, arcane: -11 },
    floorAltText: "若按 floor 取整，负向项改为：智力 -3、感应 -11（其余项不变）",
    noteLabel: "词条推算",
    noteSource: "inferred"
  },
  {
    name: "女爵 12 级：不勾词条",
    heroKey: "duchess",
    level: 12,
    modifierIds: [],
    libraKey: "",
    isAnchor: true,
    baseStats: [35, 24, 14, 9, 38, 36, 24, 11],
    baseDerived: { hp: 780, fp: 165, stamina: 76, equipLoad: 54.5 },
    delta: {},
    finalStats: null,
    finalDerived: null,
    clamped: {}
  },
  {
    name: "送葬者 1 级：不勾词条",
    heroKey: "undertaker",
    level: 1,
    modifierIds: [],
    libraKey: "",
    isAnchor: true,
    baseStats: [7, 4, 3, 5, 2, 2, 5, 10],
    baseDerived: { hp: 220, fp: 65, stamina: 54, equipLoad: 45 },
    delta: {},
    finalStats: null,
    finalDerived: null,
    clamped: {}
  }
];

test("双端对照基线：5 组单角色快照逐格钉死（属性 / 派生值 / 钳位 / 标记）", () => {
  const defs = H.attributeDefs(data);
  FIXTURES.forEach((fixture) => {
    const computed = H.computeLevel(data, {
      heroKey: fixture.heroKey,
      level: fixture.level,
      libraKey: fixture.libraKey,
      modifierIds: fixture.modifierIds
    });
    assert.ok(computed, fixture.name + "：应能算出快照");
    assert.equal(computed.isAnchor, fixture.isAnchor, fixture.name + "：基础表锚点标记");
    assert.deepEqual(
      ATTR_KEYS.map((key) => computed.base.stats[key]),
      fixture.baseStats,
      fixture.name + "：基础属性"
    );
    assert.deepEqual(computed.base.derived, fixture.baseDerived, fixture.name + "：基础派生值");

    if (fixture.finalStats === null) {
      assert.equal(computed.modified, null, fixture.name + "：没勾词条就不该有修改后的表");
      assert.equal(computed.note, null, fixture.name + "：没勾词条就不该有来源标记");
      assert.deepEqual(computed.deltas, {}, fixture.name + "：没勾词条就没有增减量");
      assert.deepEqual(computed.clamped, {}, fixture.name + "：没勾词条不会钳位");
      return;
    }

    // 增减量：只列出非 0 项，与数据集逐项相加的结果一致（这是词条**请求**的量）
    ATTR_KEYS.forEach((key) => {
      assert.equal(computed.deltas[key] || 0, fixture.delta[key] || 0, fixture.name + "：" + key + " 增减量（请求值）");
    });
    // 卡片 / 表格上真正显示的那个数是**生效值**（最终 − 基础）：钳位时它比请求值小。
    // macOS 端 HeroStatsSnapshot.effectiveDelta 钉的是同一张 cardDelta 表。
    ATTR_KEYS.forEach((key) => {
      assert.equal(
        H.effectiveDelta(computed, key) || 0,
        fixture.cardDelta[key] || 0,
        fixture.name + "：" + key + " 卡片上显示的增减量（生效值）"
      );
    });
    assert.deepEqual(
      ATTR_KEYS.map((key) => computed.modified.stats[key]),
      fixture.finalStats,
      fixture.name + "：最终属性"
    );
    assert.deepEqual(computed.modified.derived, fixture.finalDerived, fixture.name + "：最终派生值");
    assert.deepEqual(computed.clamped, fixture.clamped, fixture.name + "：钳位记录（含钳位前原值）");
    assert.equal(computed.note.label, fixture.noteLabel, fixture.name + "：增减量来源文案");
    assert.equal(computed.note.source, fixture.noteSource, fixture.name + "：增减量来源分类");

    // 相对断言①：最终值恒等于 max(1, 基础 + 增减量)
    ATTR_KEYS.forEach((key) => {
      const raw = computed.base.stats[key] + (computed.deltas[key] || 0);
      assert.equal(computed.modified.stats[key], Math.max(H.MIN_STAT, raw), fixture.name + "：" + key + " 钳位口径");
      assert.equal(
        Object.prototype.hasOwnProperty.call(computed.clamped, key),
        raw < H.MIN_STAT,
        fixture.name + "：" + key + " 是否记为钳位"
      );
      if (raw < H.MIN_STAT) assert.equal(computed.clamped[key], raw, fixture.name + "：" + key + " 钳位前原值");
    });
    // 相对断言②：派生值一律由最终属性复算，而不是拿未钳位的属性算
    assert.deepEqual(
      computed.modified.derived,
      H.deriveStats(data, computed.modified.stats),
      fixture.name + "：派生值应按钳位后的属性重算"
    );

    if (fixture.clampSummary) {
      assert.equal(
        H.COPY.clampSummary(H.clampedNames(computed.clamped, defs)),
        fixture.clampSummary,
        fixture.name + "：钳位汇总文案"
      );
    }
    if (fixture.clampRequestedText) {
      // 卡片小字：请求值只出现在这里，大数字写的是生效值
      const clampedKeys = Object.keys(computed.clamped);
      assert.equal(clampedKeys.length, 1, fixture.name + "：本组只应有一项被钳");
      assert.equal(
        H.COPY.clampRequestedNote(computed.deltas[clampedKeys[0]]),
        fixture.clampRequestedText,
        fixture.name + "：钳位小字应写词条请求值"
      );
      assert.notEqual(
        H.effectiveDelta(computed, clampedKeys[0]),
        computed.deltas[clampedKeys[0]],
        fixture.name + "：被钳的那一项，生效值与请求值本来就不该相等"
      );
    }
    if (fixture.floorAlt) {
      const mod = data.statModifiers.find((item) => item.affixId === fixture.modifierIds[0]);
      const modRow = levelOf(mod.levels, fixture.level);
      assert.deepEqual(modRow.deltaFloorAlt, fixture.floorAlt, fixture.name + "：deltaFloorAlt");
      assert.equal(
        H.COPY.floorAlt(H.deltaSummary(modRow.deltaFloorAlt, defs)),
        fixture.floorAltText,
        fixture.name + "：deltaFloorAlt 文案"
      );
      // deltaFloorAlt 恒为负向项、且恰好比 trunc 少 1（floor 与 trunc 只在负数上差 1）
      Object.keys(modRow.deltaFloorAlt).forEach((key) => {
        assert.ok(modRow.deltaFloorAlt[key] < 0, "deltaFloorAlt 只会出现在负向项上");
        assert.equal(modRow.deltaFloorAlt[key], modRow.delta[key] - 1);
      });
    }
  });
});

test("双端对照基线⑥：同级对比 10 级按血量降序，前三名与兜底顺序钉死", () => {
  const rows = H.compareRows(data, 10);
  assert.equal(rows.length, 10);
  const sorted = H.sortCompareRows(rows, "hp", "desc");
  assert.deepEqual(sorted.slice(0, 3).map((row) => row.nameZh), ["守护者", "无赖", "追踪者"]);
  assert.deepEqual(sorted.slice(0, 3).map((row) => row.derived.hp), [1020, 940, 880]);
  assert.deepEqual(sorted.slice(0, 3).map((row) => row.stats.vigor), [47, 43, 40]);
  // 相对断言：降序单调不增，且血量恒等于 20 × 生命力 + 80（CalcCorrectGraph 100 的斜率）
  for (let i = 1; i < sorted.length; i += 1) {
    assert.ok(sorted[i - 1].derived.hp >= sorted[i].derived.hp, "血量降序应单调不增");
  }
  sorted.forEach((row) => assert.equal(row.derived.hp, 20 * row.stats.vigor + 80));
  // 平手退回数据集顺序：两个方向上平手的几行相对次序都不翻面（不是严格反序）
  const flat = rows.map((row) => Object.assign({}, row, {
    stats: Object.assign({}, row.stats, { arcane: 7 })
  }));
  const asc = H.sortCompareRows(flat, "arcane", "asc").map((row) => row.order);
  const desc = H.sortCompareRows(flat, "arcane", "desc").map((row) => row.order);
  assert.deepEqual(asc, desc, "全平手时升降序都按数据集顺序");
  assert.deepEqual(asc, flat.map((row) => row.order).slice().sort((a, b) => a - b));
});

test("双端共用文案 COPY：逐字钉死（macOS 端 HeroStatsCopy 有同一份）", () => {
  assert.equal(H.COPY.missing, "—");
  assert.equal(H.COPY.emptyData, "数据未内置");
  assert.equal(H.COPY.viewSingle, "单角色");
  assert.equal(H.COPY.viewCompare, "同级对比");

  assert.equal(H.COPY.baseLevelBadge(15, true), "15 级是参数锚点");
  assert.equal(H.COPY.baseLevelBadge(7, false), "7 级为插值推算");
  assert.equal(H.COPY.baseAnchorTag, "参数锚点");
  assert.equal(H.COPY.baseInterpolatedTag, "插值推算");
  assert.equal(
    H.COPY.allLevelsCaption([1, 2, 12, 15]),
    "加粗行是参数表里的锚点（1 / 2 / 12 / 15 级），其余等级按相邻锚点线性插值后向下取整。"
  );

  assert.equal(H.COPY.modifierCountBadge(2), "转职遗物 2 条");
  assert.equal(
    H.COPY.modifierSubtitle,
    "勾选后在基础属性上加减（可同时勾选，效果相加）；派生值按 CalcCorrectGraph 重算"
  );
  assert.equal(H.COPY.dlcOnlyTag, "仅 DLC 池可掉");
  assert.equal(H.COPY.noDeltaAtLevel, "本级无增减");
  assert.equal(H.COPY.noModifierData, "数据未内置该角色的转职遗物词条");
  assert.equal(
    H.COPY.floorAlt("智力 -3、感应 -11"),
    "若按 floor 取整，负向项改为：智力 -3、感应 -11（其余项不变）"
  );

  assert.equal(H.COPY.clampCellTag, "钳");
  assert.equal(H.COPY.clampRowTag, "已钳位");
  assert.equal(H.COPY.clampedFromNote(0), "原为 0，已钳到最低 1");
  assert.equal(H.COPY.clampedFromNote(-3), "原为 -3，已钳到最低 1");
  assert.equal(H.COPY.clampRequestedNote(-9), "词条请求 -9，已钳到最低 1");
  assert.equal(H.COPY.clampRequestedNote(-13), "词条请求 -13，已钳到最低 1");
  assert.equal(
    H.COPY.clampSummary(["生命力", "集中力"]),
    "生命力、集中力 叠加后不足 1，已钳到最低 1（游戏里属性不会低于 1）"
  );
  assert.equal(
    H.COPY.clampSummaryByLevel([{ level: 13, names: ["灵巧"] }, { level: 15, names: ["灵巧", "感应"] }], 15),
    "1–15 级里有 2 级叠加后不足 1：13 级 灵巧；15 级 灵巧、感应；已钳到最低 1（游戏里属性不会低于 1）"
  );
  assert.equal(H.COPY.clampSummaryByLevel([], 15), "");

  assert.equal(H.COPY.libraSwapTag, "整套替换");
  assert.equal(
    H.COPY.libraHint,
    "利普拉的交易把整套基础属性表替换掉；能否与转职遗物叠加是按参数字段结构推断的，未实测"
  );
  assert.equal(H.COPY.libraEmptyHint, "选中后基础表整套换成对应的替换表，转职遗物仍可叠加。");
  assert.equal(H.COPY.libraBadge("力气"), "利普拉：力气");
  assert.equal(
    H.COPY.libraCrossCheckNote,
    "已做利普拉的交易，基础表整套替换，与外部 wiki 的角色原表差异不再适用"
  );
  assert.equal(H.COPY.crossCheckNote(14, "补丁 1.02.2"), "与外部 wiki 有 14 格差异，本页以参数为准：补丁 1.02.2");
  assert.equal(H.COPY.crossCheckNote(14, ""), "与外部 wiki 有 14 格差异，本页以参数为准");

  assert.equal(H.COPY.legacyMark, "*");
  assert.equal(H.COPY.legacyHeader("负重上限"), "负重上限 *");
  assert.equal(H.COPY.equipLoadHint, "本作装备没有重量，负重上限是《艾尔登法环》继承下来的遗留列，未经实测");
  assert.equal(
    H.COPY.equipLoadFootnote,
    "* 负重上限是《艾尔登法环》继承下来的遗留列：本作装备没有重量、界面也没有负重条，未经实测，仅供参考。"
  );

  assert.equal(
    H.COPY.compareCaption,
    "对比表只用各角色的基础表：利普拉的交易不分角色（叠上去每行都一样），转职遗物是逐角色的词条，都不进对比。"
  );

  // 折叠区标题里的 N 两端必须是同一个数：两端渲染的都是 interpolationNotes 那 10 条
  // （macOS 端 HeroInterpolation.notes 同序同文），不再是一端数字段、一端数条目。
  assert.equal(H.COPY.interpolationTitle(10), "插值与验证口径（10 条）");
  assert.equal(H.COPY.interpolationTitle(H.interpolationNotes(data).length), "插值与验证口径（10 条）");
  assert.equal(H.COPY.caveatsTitle(13), "已知取舍（13 条）");
  assert.equal(H.COPY.sourcesTitle(10), "数据出处（10 条）与外部对照");
  assert.deepEqual(H.COPY.versionLabels, ["游戏版本", "数据版本", "生成时间", "数据集结构版本", "收录"]);
  assert.equal(H.COPY.contentSummary(10, 15, 20, 5), "10 位夜行者 × 15 级 · 20 条转职遗物词条 · 5 笔利普拉交易");
});

test("数据版本块：5 行标签与「收录」口径按数据集实算", () => {
  const rows = H.versionRows(data);
  assert.deepEqual(rows.map((row) => row.label), H.COPY.versionLabels);
  assert.equal(rows[0].value, data.gameVersion);
  assert.equal(rows[1].value, data.dataVersion);
  assert.equal(rows[3].value, "schemaVersion 1");
  assert.equal(rows[4].value, "10 位夜行者 × 15 级 · 20 条转职遗物词条 · 5 笔利普拉交易");
  // 缺字段时给破折号，不要写「未知」/ 0
  const bare = H.versionRows({ heroes: [], statModifiers: [], libraRespecs: [] });
  assert.equal(bare[0].value, "—");
  assert.equal(bare[2].value, "—");
});

test("负重上限是遗留列：两张表的列头都带 * 注记，且只有它带", () => {
  const derived = H.derivedDefs(data);
  const equip = derived.find((def) => def.key === "equipLoad");
  const hp = derived.find((def) => def.key === "hp");
  assert.equal(equip.inGameLabel, false, "负重上限没有游戏内 UI 标签");
  assert.equal(hp.inGameLabel, true);
  assert.equal(H.derivedHeader(equip), "负重上限 *");
  assert.equal(H.derivedHeader(hp), "血量");
  assert.equal(H.hasLegacyDerived(derived), true);
  assert.equal(H.hasLegacyDerived(derived.filter((def) => def.inGameLabel !== false)), false);
  assert.deepEqual(
    derived.filter((def) => def.inGameLabel === false).map((def) => def.key),
    ["equipLoad"],
    "遗留列当前只有负重上限一项"
  );
});

test("选了利普拉后不再报该角色与 wiki 的差异，改写成一句说明", () => {
  const duchess = H.crossCheckFor(data, "duchess");
  assert.ok(duchess && duchess.mismatchCount === 14);
  // 没选利普拉：照常报差异
  assert.equal(
    H.COPY.crossCheckNote(duchess.mismatchCount, duchess.note),
    "与外部 wiki 有 14 格差异，本页以参数为准：" + duchess.note
  );
  // 选了利普拉：基础表已整套换掉，角色原表的差异不再适用
  assert.ok(H.COPY.libraCrossCheckNote.indexOf("整套替换") !== -1);
  const swapped = H.computeLevel(data, { heroKey: "duchess", level: 12, libraKey: "strength" });
  const plain = H.computeLevel(data, { heroKey: "duchess", level: 12 });
  assert.notDeepEqual(swapped.base.stats, plain.base.stats, "换了表才谈得上「差异不再适用」");
});

test("全部等级视图的钳位汇总按行聚合：15 行里哪几级被钳都列出来", () => {
  const defs = H.attributeDefs(data);
  const rows = H.computeAllLevels(data, {
    heroKey: "ironeye",
    libraKey: "strength",
    modifierIds: [6642000]
  });
  assert.equal(rows.length, 15);
  const clamped = H.clampedByLevel(rows, defs);
  assert.ok(clamped.length > 1, "这一组合应有多级触发钳位（否则「按行聚合」没意义）");
  // 聚合结果与逐行的 clamped 逐项对得上
  const expected = rows
    .filter((row) => Object.keys(row.clamped).length)
    .map((row) => ({ level: row.level, names: H.clampedNames(row.clamped, defs) }));
  assert.deepEqual(clamped, expected);
  clamped.forEach((entry) => {
    assert.ok(entry.names.length > 0);
    entry.names.forEach((name) => assert.ok(defs.some((def) => def.zh === name)));
  });
  const summary = H.COPY.clampSummaryByLevel(clamped, H.maxLevelOf(data));
  assert.ok(summary.startsWith("1–15 级里有 " + clamped.length + " 级叠加后不足 1："));
  clamped.forEach((entry) => assert.ok(summary.indexOf(entry.level + " 级 " + entry.names.join("、")) !== -1));
  // 不勾词条时没有任何钳位
  assert.deepEqual(H.clampedByLevel(H.computeAllLevels(data, { heroKey: "ironeye" }), defs), []);
});

test("派生值取整：整数段走精确整数除法，与 normalize + floor 逐格一致", () => {
  const hp = data.growthGraphs["100"];
  const fp = data.growthGraphs["101"];
  const stamina = data.growthGraphs["104"];
  const equip = data.growthGraphs["220"];
  for (let stat = 1; stat <= 99; stat += 1) {
    [hp, fp, stamina].forEach((graph) => {
      assert.equal(
        H.evalGrowthGraphInteger(graph, stat),
        Math.floor(Math.round(H.evalGrowthGraph(graph, stat) * 1e9) / 1e9),
        "整数求值应与 normalize + floor 逐格一致"
      );
    });
  }
  // 负重上限带指数，退回浮点 + 1 位小数（远离零）
  assert.equal(H.roundOneDigit(74.149999), 74.1);
  assert.equal(H.roundOneDigit(74.15), 74.2);
  assert.equal(H.roundOneDigit(-74.15), -74.2, "四舍五入应远离零（与 Swift 的 .rounded() 同口径）");
  assert.equal(H.deriveStats(data, { endurance: 27 }).equipLoad, H.roundOneDigit(H.evalGrowthGraph(equip, 27)));
});

test("数据缺失降级：缺 growthGraph / 缺来源属性给破折号，不退回 0", () => {
  const derived = H.derivedDefs(data);
  const hp = derived.find((def) => def.key === "hp");
  // 缺来源属性
  const partial = H.deriveStats(data, { vigor: 20 });
  assert.equal(partial.hp, 480);
  assert.equal(partial.fp, null, "缺集中力时专注值应为 null");
  assert.equal(H.fmtDerived(hp, partial.fp), "—");
  // 缺 growthGraphs 整份
  const noGraphs = H.deriveStats({ statNames: data.statNames, growthGraphs: {} }, { vigor: 20, mind: 10 });
  assert.deepEqual(noGraphs, { hp: null, fp: null, stamina: null, equipLoad: null });
  // 0 是真实数值，照常显示
  assert.equal(H.fmtDerived(hp, 0), "0");
  assert.equal(H.fmtStat(0), "0");
  assert.equal(H.fmtStat(null), "—");
});

test("同级对比：某一级缺行的角色整行丢掉，而不是摆一行 0", () => {
  const shrunk = {
    statNames: data.statNames,
    growthGraphs: data.growthGraphs,
    interpolation: data.interpolation,
    heroes: [
      data.heroes[0],
      Object.assign({}, data.heroes[1], {
        levels: data.heroes[1].levels.filter((row) => row.level !== 10)
      })
    ]
  };
  const rows = H.compareRows(shrunk, 10);
  assert.equal(rows.length, 1, "缺 10 级的角色应从对比表消失");
  assert.equal(rows[0].heroKey, data.heroes[0].key);
  assert.equal(H.compareRows(shrunk, 9).length, 2, "有数据的等级仍是两行");
  // 真实数据集每一级都齐，10 行不变
  for (let level = 1; level <= 15; level += 1) {
    assert.equal(H.compareRows(data, level).length, 10);
  }
});

// ---------------------------------------------------------------------------
// 本轮补的四条「两端曾经各写各的」的用例。每一条都有 macOS 端的对称断言
// （RelicCoreChecks/HeroStatsChecks.swift），改一端没跟上另一端就红。

test("卡片上的增减量是生效值：钳位时大数字写 -8、小字写「词条请求 -9」", () => {
  // 复核者点名的那一组：铁之眼 15 级 + 利普拉（力气）+「提升感应，但降低灵巧」。
  // 之前 Windows 卡片写 -9（请求值）、macOS 写 -8（生效值），同一输入两端两个数。
  [
    { affixId: 6642000, requested: -9 },
    { affixId: 6642100, requested: -13 }
  ].forEach((sample) => {
    const computed = H.computeLevel(data, {
      heroKey: "ironeye",
      level: 15,
      libraKey: "strength",
      modifierIds: [sample.affixId]
    });
    assert.equal(computed.base.stats.dexterity, 9);
    assert.equal(computed.deltas.dexterity, sample.requested, "请求值仍保留在 deltas 里");
    assert.equal(computed.modified.stats.dexterity, 1, "钳到最低 1");
    assert.equal(H.effectiveDelta(computed, "dexterity"), -8, "卡片上显示的一律是生效值");
    assert.equal(
      H.COPY.clampRequestedNote(computed.deltas.dexterity),
      "词条请求 " + sample.requested + "，已钳到最低 1"
    );
  });
  // 没钳位时生效值与请求值相同（绝大多数格子走的是这条）
  const plain = H.computeLevel(data, { heroKey: "wylder", level: 15, modifierIds: [6640000] });
  ATTR_KEYS.forEach((key) => {
    assert.equal(H.effectiveDelta(plain, key), plain.deltas[key] || 0);
  });
  // 没勾词条 / 缺基础值时没有可显示的增减量
  assert.equal(H.effectiveDelta(H.computeLevel(data, { heroKey: "wylder", level: 15 }), "vigor"), null);
  assert.equal(H.effectiveDelta(null, "vigor"), null);
});

test("「插值与验证口径」：两端渲染同一组 10 条说明，标题里的 N 就是这 10", () => {
  const notes = H.interpolationNotes(data);
  assert.equal(notes.length, 10, "真实数据集拼出 10 条说明（macOS 端 notes.count 同样是 10）");
  assert.deepEqual(notes.map((note) => note.title), [
    "参数锚点", "基础属性插值", "基础表验证", "派生值换算", "转职遗物插值",
    "转职遗物锚点验证", "转职遗物中间等级", "取整方向", "兼容字段说明", "利普拉的交易"
  ]);
  assert.deepEqual(H.COPY.interpolationNoteTitles, notes.map((note) => note.title));
  // 锚点一条由数据集的两组锚点拼出来，不写死 1/2/12/15 与 1/12
  assert.equal(
    notes[0].text,
    "基础属性表只有 1 / 2 / 12 / 15 级是参数原值，转职遗物只有 1 / 12 级是参数原值。"
  );
  assert.equal(
    H.COPY.interpolationAnchorNote([1, 8], [1, 6]),
    "基础属性表只有 1 / 8 级是参数原值，转职遗物只有 1 / 6 级是参数原值。"
  );
  // 正文直接取数据集那一段（不改写）
  assert.equal(notes[1].text, data.interpolation.baseRule);
  assert.equal(notes[2].text, data.interpolation.baseVerification);
  assert.equal(notes[9].text, data.interpolation.libraRule);
  // 取整方向：floor / trunc 都写出来，并点名 deltaFloorAlt
  assert.ok(notes[7].text.indexOf("基础属性表按向下取整（floor）") === 0);
  assert.ok(notes[7].text.indexOf("转职遗物增减量按向零取整（trunc）") !== -1);
  assert.ok(notes[7].text.indexOf("两种取整只在负的增减量上差 1；") !== -1);
  assert.ok(notes[7].text.indexOf("deltaFloorAlt") !== -1);
  assert.equal(H.COPY.roundingTerm("floor"), "向下取整（floor）");
  assert.equal(H.COPY.roundingTerm("round"), "四舍五入（round）");
  assert.equal(H.COPY.roundingTerm("别的"), "别的");
  // 两个取整字段都缺时整条说明不出现（不硬造）
  assert.equal(H.COPY.interpolationRoundingNote("", ""), "");
  assert.equal(
    H.interpolationNotes({ interpolation: { baseRule: "x" } }).map((note) => note.title).join(),
    "基础属性插值"
  );
  assert.deepEqual(H.interpolationNotes({}), []);
  assert.deepEqual(H.interpolationNotes(null), []);
});

test("最大等级读数据集：maxLevel = 20 时行数 / 选择器 / 钳位汇总一起变", () => {
  function heroWithLevels(hero, top) {
    const levels = [];
    for (let level = 1; level <= top; level += 1) {
      const source = hero.levels[Math.min(level, hero.levels.length) - 1];
      levels.push(Object.assign({}, source, { level, isAnchor: level === 1 || level === top }));
    }
    return Object.assign({}, hero, { levels });
  }
  const big = {
    statNames: data.statNames,
    growthGraphs: data.growthGraphs,
    interpolation: Object.assign({}, data.interpolation, { maxLevel: 20 }),
    heroes: data.heroes.slice(0, 2).map((hero) => heroWithLevels(hero, 20)),
    statModifiers: data.statModifiers.filter((mod) => mod.heroKey === data.heroes[0].key),
    libraRespecs: []
  };
  assert.equal(H.maxLevelOf(big), 20);
  assert.equal(H.levelRange(big).length, 20);
  assert.equal(H.levelRange(big)[19], 20);
  assert.equal(H.clampLevel(99, H.maxLevelOf(big)), 20, "钳位上限跟着数据集走");
  assert.equal(H.computeAllLevels(big, { heroKey: big.heroes[0].key }).length, 20, "表体也应有 20 行");
  assert.equal(H.computeLevel(big, { heroKey: big.heroes[0].key, level: 20 }).level, 20);
  // 等级选择器同样到 20（页面上那排按钮就是这个串）
  const control = H.levelControl(big);
  assert.ok(control.indexOf("data-heroes-level='20'") !== -1, "选择器应有 20 级按钮");
  assert.equal(control.match(/data-heroes-level='/g).length, 20);
  assert.equal(H.levelControl(data).match(/data-heroes-level='/g).length, 15);
  // 汇总文案里的范围同样是 1–20
  assert.equal(
    H.COPY.clampSummaryByLevel([{ level: 20, names: ["灵巧"] }], H.maxLevelOf(big)),
    "1–20 级里有 1 级叠加后不足 1：20 级 灵巧；已钳到最低 1（游戏里属性不会低于 1）"
  );
  // 缺 interpolation.maxLevel 时退回各角色 levels 的最大值（macOS 端同一条兜底）
  const noDeclared = Object.assign({}, big, { interpolation: { baseAnchorLevels: [1] } });
  assert.equal(H.maxLevelOf(noDeclared), 20);
  assert.equal(H.maxLevelOf({ heroes: [{ key: "x", levels: [{ level: 1 }, { level: 7 }] }] }), 7);
  // 连角色表都没有时才退回常量
  assert.equal(H.maxLevelOf({}), H.FALLBACK_MAX_LEVEL);
  assert.equal(H.FALLBACK_MAX_LEVEL, 15);
});

test("词条来源三档三色：source → pill 配色两端钉同一张表", () => {
  assert.deepEqual(H.SOURCE_PILL, { anchor: "green", inferred: "amber", carried: "blue" });
  // 沿用锚点必须与锚点**不同色**，否则页面上 1/12 级与 13–15 级长得一模一样
  assert.notEqual(H.SOURCE_PILL.carried, H.SOURCE_PILL.anchor);
  assert.equal(H.SOURCE_PILL[H.modifierLevelNote(data, 1).source], "green");
  assert.equal(H.SOURCE_PILL[H.modifierLevelNote(data, 6).source], "amber");
  assert.equal(H.SOURCE_PILL[H.modifierLevelNote(data, 15).source], "blue");
});

test("属性缺失同样给破折号：pickStats 不再把缺项写成 0", () => {
  const defs = H.attributeDefs(data);
  const picked = H.pickStats({ vigor: 20, mind: null, endurance: "" }, defs);
  assert.equal(picked.vigor, 20);
  assert.equal(picked.mind, null, "写着 null 的属性不是 0");
  assert.equal(picked.endurance, null);
  assert.equal(picked.arcane, null, "整项缺失也是 null");
  assert.equal(H.fmtStat(picked.mind), "—");
  assert.equal(H.fmtStat(0), "0", "0 是真实数值，照常显示");

  // 缺属性的角色：单等级视图 / 全部等级表 / 对比表三处都给破折号，且不编最终值
  const hero = data.heroes[0];
  const holed = {
    statNames: data.statNames,
    growthGraphs: data.growthGraphs,
    interpolation: data.interpolation,
    statModifiers: data.statModifiers.filter((mod) => mod.heroKey === hero.key),
    heroes: [Object.assign({}, hero, {
      levels: hero.levels.map((row) => {
        const stats = Object.assign({}, row.stats);
        delete stats.arcane;
        return Object.assign({}, row, { stats });
      })
    })]
  };
  const mod = holed.statModifiers[0];
  const computed = H.computeLevel(holed, { heroKey: hero.key, level: 12, modifierIds: [mod.affixId] });
  assert.equal(computed.base.stats.arcane, null);
  assert.equal(computed.modified.stats.arcane, null, "没有基础值就不编一个最终值");
  assert.equal(H.effectiveDelta(computed, "arcane"), null);
  assert.equal(Object.prototype.hasOwnProperty.call(computed.clamped, "arcane"), false, "缺项不记钳位");
  assert.equal(H.fmtStat(computed.modified.stats.arcane), "—");
  const rows = H.computeAllLevels(holed, { heroKey: hero.key, modifierIds: [mod.affixId] });
  assert.equal(rows.length, 15);
  rows.forEach((row) => assert.equal(H.fmtStat(row.base.stats.arcane), "—"));
  assert.equal(H.fmtStat(H.compareRows(holed, 12)[0].stats.arcane), "—");
  // 其余 7 项照常有数
  assert.equal(computed.base.stats.vigor, levelOf(hero.levels, 12).stats.vigor);
});

test("growthGraph 可用性两端同一条：三个数组必须等长", () => {
  const hp = data.growthGraphs["100"];
  assert.equal(H.isUsableGraph(hp), true);
  assert.equal(H.isUsableGraph(null), false);
  assert.equal(H.isUsableGraph({ stageMaxVal: [1], stageMaxGrowVal: [1], adjPt: [1] }), false, "至少两段");
  assert.equal(
    H.isUsableGraph({ stageMaxVal: [1, 10], stageMaxGrowVal: [1, 10, 20], adjPt: [1, 1] }),
    false,
    "ys 比 xs 长也算不可用（之前 Windows 照算不误，macOS 给破折号）"
  );
  const shortAdj = { stageMaxVal: [1, 10], stageMaxGrowVal: [0, 90], adjPt: [1] };
  assert.equal(H.isUsableGraph(shortAdj), false, "adjPt 残缺同样不可用");
  assert.equal(H.evalGrowthGraph(shortAdj, 5), null, "不可用图表一律给 null → 页面破折号");
  assert.equal(H.evalGrowthGraphInteger(shortAdj, 5), null);
  const noAdj = { stageMaxVal: [1, 10], stageMaxGrowVal: [0, 90] };
  assert.equal(H.isUsableGraph(noAdj), false, "整个 adjPt 缺失也不可用");
  assert.deepEqual(
    H.deriveStats({ statNames: data.statNames, growthGraphs: { 100: shortAdj } }, { vigor: 20, mind: 10 }),
    { hp: null, fp: null, stamina: null, equipLoad: null },
    "图表不可用时派生值一律 null（破折号），不编数字"
  );
});
