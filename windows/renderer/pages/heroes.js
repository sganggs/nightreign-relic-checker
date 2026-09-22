// 角色属性页。页面模块契约见 renderer/pages/README.md。
// 本文件由「角色属性」功能开发者独占：只改这里与 pages/heroes.css。
//
// 数据：ctx.getGameData("heroes") → resources/heroes.json（schemaVersion 1）。
// 数值口径（务必与数据集自带的 interpolation / caveats 一致，页面不另立说法）：
//   · heroes[].levels[1..15]：参数表只有 1 / 2 / 12 / 15 四行锚点，其余等级是相邻锚点之间
//     线性插值后 floor；该规则已用两个 wiki 的整表逐格实测（interpolation.baseVerified）。
//   · 派生值各自只吃一项属性、不吃等级：血量←生命力（CalcCorrectGraph 100）、
//     专注值←集中力（101）、精力←耐力（104）、负重上限←耐力（220）。属性一旦被转职遗物
//     或利普拉的交易改动，派生值必须用 growthGraphs 重算，不能沿用 levels[].derived。
//   · 转职遗物（statModifiers）只有 L1 / L12 两个锚点：2–11 级是推算（levels[].inferred），
//     13–15 级沿用 L12；锚点与「沿用」已由 15 级实测确认，只有 2–11 级仍未实测。
//   · 利普拉的交易（libraRespecs）走 heroStatusId「整套替换」，转职遗物走 heroStatusModifier
//     「在当前表上加减」，字段不同所以可叠加 —— 这是按参数结构推断的，未在游戏里实测。
//   · 负重上限是《艾尔登法环》继承下来的遗留列：本作装备没有重量，界面也没有负重条，
//     页面照常展示但必须标出「未实测的遗留值」。
(function (root) {
  "use strict";

  var PAGE_KEY = "heroes";
  var DATA_NAME = "heroes";

  // ---------------------------------------------------------------- 常量表

  var MAX_LEVEL = 15;
  var MIN_LEVEL = 1;
  var MIN_STAT = 1; // 属性被转职遗物减到 0 或负数时钳到 1（并在界面上注明）

  // 数据集缺 statNames 时的兜底顺序与中文名（正常情况下一律读数据集）。
  var ATTRIBUTE_FALLBACK = [
    { key: "vigor", zh: "生命力", en: "Vigor" },
    { key: "mind", zh: "集中力", en: "Mind" },
    { key: "endurance", zh: "耐力", en: "Endurance" },
    { key: "strength", zh: "力气", en: "Strength" },
    { key: "dexterity", zh: "灵巧", en: "Dexterity" },
    { key: "intelligence", zh: "智力", en: "Intelligence" },
    { key: "faith", zh: "信仰", en: "Faith" },
    { key: "arcane", zh: "感应", en: "Arcane" }
  ];

  var DERIVED_FALLBACK = [
    { key: "hp", zh: "血量", en: "HP", fromStat: "vigor", graphId: 100, integer: true },
    { key: "fp", zh: "专注值", en: "FP", fromStat: "mind", graphId: 101, integer: true },
    { key: "stamina", zh: "精力", en: "Stamina", fromStat: "endurance", graphId: 104, integer: true },
    { key: "equipLoad", zh: "负重上限", en: "Equip Load", fromStat: "endurance", graphId: 220, integer: false }
  ];

  // 遗物颜色 → pill 配色，与 lookup.js 的 COLOR_PILLS 同一套。
  var RELIC_COLOR_PILLS = ["red", "blue", "amber", "green", "gray"];

  var VIEWS = [
    { key: "detail", label: "角色属性" },
    { key: "compare", label: "同级对比" }
  ];

  // 转职遗物在某一级的数值来源，三种口径三种说法（两端逐字一致）。
  var LEVEL_NOTES = {
    anchor: { label: "遗物锚点", kind: "green" },
    inferred: { label: "推算", kind: "amber" },
    carried: { label: "沿用 12 级锚点", kind: "blue" }
  };

  var EQUIP_LOAD_HINT = "本作装备没有重量，负重上限是《艾尔登法环》继承下来的遗留列，未经实测";
  var LIBRA_HINT = "利普拉的交易把整套基础属性表替换掉；能否与转职遗物叠加是按参数字段结构推断的，未实测";

  // -------------------------------------------------------------- 纯计算层
  // 以下函数不碰 DOM，windows/tests/heroes.test.mjs 直接 require 本文件测试。

  function isObject(value) {
    return Boolean(value) && typeof value === "object";
  }

  function toFiniteNumber(value, fallback) {
    var num = Number(value);
    return isFinite(num) ? num : fallback;
  }

  // 浮点噪声归一：CalcCorrectGraph 的分段斜率都是有理数，真值离整数至少 0.01，
  // 先抹掉 1e-9 以下的尾巴再 floor，结果与整数精确运算逐格一致。
  function normalize(value) {
    return Math.round(value * 1e9) / 1e9;
  }

  function attributeDefs(data) {
    var names = isObject(data) && isObject(data.statNames) ? data.statNames : null;
    var list = names && Array.isArray(names.attributes) ? names.attributes : null;
    if (!list || !list.length) return ATTRIBUTE_FALLBACK.slice();
    var byKey = {};
    list.forEach(function (item) {
      if (isObject(item) && item.key) byKey[item.key] = item;
    });
    var order = names && Array.isArray(names.attributeOrder) && names.attributeOrder.length
      ? names.attributeOrder
      : list.map(function (item) { return item && item.key; });
    return order.filter(function (key) { return Boolean(byKey[key]); }).map(function (key) {
      var item = byKey[key];
      return { key: key, zh: item.zh || key, en: item.en || "" };
    });
  }

  function derivedDefs(data) {
    var names = isObject(data) && isObject(data.statNames) ? data.statNames : null;
    var list = names && Array.isArray(names.derived) ? names.derived : null;
    if (!list || !list.length) return DERIVED_FALLBACK.slice();
    var byKey = {};
    list.forEach(function (item) {
      if (isObject(item) && item.key) byKey[item.key] = item;
    });
    var order = names && Array.isArray(names.derivedOrder) && names.derivedOrder.length
      ? names.derivedOrder
      : list.map(function (item) { return item && item.key; });
    return order.filter(function (key) { return Boolean(byKey[key]); }).map(function (key) {
      var item = byKey[key];
      return {
        key: key,
        zh: item.zh || key,
        en: item.en || "",
        fromStat: item.fromStat || "",
        graphId: item.graphId,
        integer: item.integer !== false
      };
    });
  }

  // CalcCorrectGraph：分段插值。adjPt > 0 时 ratio ** adjPt[下段下标]，
  // < 0 时 1 - (1 - ratio) ** -adjPt；本数据集只有负重上限（220）不是直线。
  function evalGrowthGraph(graph, value) {
    if (!isObject(graph)) return null;
    var xs = graph.stageMaxVal;
    var ys = graph.stageMaxGrowVal;
    var adj = Array.isArray(graph.adjPt) ? graph.adjPt : [];
    if (!Array.isArray(xs) || !Array.isArray(ys) || xs.length < 2 || ys.length < xs.length) return null;
    var val = Number(value);
    if (!isFinite(val)) return null;
    if (val <= xs[0]) return ys[0];
    if (val >= xs[xs.length - 1]) return ys[ys.length - 1];
    var index = 0;
    for (var i = 0; i < xs.length - 1; i += 1) {
      if (val >= xs[i] && val <= xs[i + 1]) { index = i; break; }
    }
    var span = xs[index + 1] - xs[index];
    var ratio = span === 0 ? 0 : (val - xs[index]) / span;
    var exponent = toFiniteNumber(adj[index], 1);
    var growth;
    if (exponent > 0) growth = Math.pow(ratio, exponent);
    else if (exponent < 0) growth = 1 - Math.pow(1 - ratio, -exponent);
    else growth = ratio;
    return ys[index] + (ys[index + 1] - ys[index]) * growth;
  }

  // 派生值重算：血量 / 专注值 / 精力向下取整，负重上限保留 1 位小数。
  function deriveStats(data, stats) {
    var graphs = isObject(data) && isObject(data.growthGraphs) ? data.growthGraphs : {};
    var out = {};
    derivedDefs(data).forEach(function (def) {
      var graph = graphs[String(def.graphId)];
      var raw = evalGrowthGraph(graph, stats ? stats[def.fromStat] : null);
      if (raw === null) { out[def.key] = null; return; }
      out[def.key] = def.integer ? Math.floor(normalize(raw)) : Math.round(raw * 10) / 10;
    });
    return out;
  }

  function heroList(data) {
    return isObject(data) && Array.isArray(data.heroes) ? data.heroes : [];
  }

  function findHero(data, heroKey) {
    var list = heroList(data);
    for (var i = 0; i < list.length; i += 1) {
      if (list[i] && list[i].key === heroKey) return list[i];
    }
    return null;
  }

  function libraList(data) {
    return isObject(data) && Array.isArray(data.libraRespecs) ? data.libraRespecs : [];
  }

  function findLibra(data, libraKey) {
    if (!libraKey) return null;
    var list = libraList(data);
    for (var i = 0; i < list.length; i += 1) {
      if (list[i] && list[i].key === libraKey) return list[i];
    }
    return null;
  }

  function modifiersForHero(data, heroKey) {
    if (!isObject(data) || !Array.isArray(data.statModifiers)) return [];
    return data.statModifiers.filter(function (mod) {
      return isObject(mod) && mod.heroKey === heroKey;
    });
  }

  function selectedModifiers(data, heroKey, ids) {
    var wanted = {};
    (Array.isArray(ids) ? ids : []).forEach(function (id) { wanted[String(id)] = true; });
    return modifiersForHero(data, heroKey).filter(function (mod) {
      return wanted[String(mod.affixId)] === true;
    });
  }

  function clampLevel(level) {
    var num = Math.round(toFiniteNumber(level, MAX_LEVEL));
    if (num < MIN_LEVEL) return MIN_LEVEL;
    if (num > MAX_LEVEL) return MAX_LEVEL;
    return num;
  }

  function levelRow(levels, level) {
    if (!Array.isArray(levels)) return null;
    for (var i = 0; i < levels.length; i += 1) {
      if (levels[i] && Number(levels[i].level) === Number(level)) return levels[i];
    }
    return null;
  }

  function pickStats(stats, defs) {
    var out = {};
    defs.forEach(function (def) {
      out[def.key] = toFiniteNumber(stats ? stats[def.key] : null, 0);
    });
    return out;
  }

  // 转职遗物在某一级的数值来源：1 / 12 是参数锚点，2–11 推算，13–15 沿用 L12。
  function modifierLevelNote(level) {
    var lv = clampLevel(level);
    if (lv === 1 || lv === 12) return { kind: "anchor", label: LEVEL_NOTES.anchor.label };
    if (lv < 12) return { kind: "inferred", label: LEVEL_NOTES.inferred.label };
    return { kind: "carried", label: LEVEL_NOTES.carried.label };
  }

  // 叠加增减量并钳位：结果小于 1 的属性一律钳到 1，钳位前的原值记在 clamped 里。
  function applyDeltas(baseStats, sum, defs) {
    var stats = {};
    var clamped = {};
    defs.forEach(function (def) {
      var raw = toFiniteNumber(baseStats[def.key], 0) + toFiniteNumber(sum[def.key], 0);
      if (raw < MIN_STAT) {
        clamped[def.key] = raw;
        raw = MIN_STAT;
      }
      stats[def.key] = raw;
    });
    return { stats: stats, clamped: clamped };
  }

  // 页面的单一真相：给定角色 / 等级 / 利普拉交易 / 勾选的转职遗物，算出这一级要显示的一切。
  function computeLevel(data, options) {
    var opts = isObject(options) ? options : {};
    var defs = attributeDefs(data);
    var level = clampLevel(opts.level);
    var libra = findLibra(data, opts.libraKey);
    var hero = findHero(data, opts.heroKey);
    if (!hero) return null;
    var source = libra || hero;
    var row = levelRow(source.levels, level);
    if (!row) return null;

    var baseStats = pickStats(row.stats, defs);
    var result = {
      level: level,
      heroKey: hero.key,
      libraKey: libra ? libra.key : "",
      isAnchor: Boolean(row.isAnchor),
      base: { stats: baseStats, derived: deriveStats(data, baseStats) },
      modifiers: [],
      deltas: {},
      clamped: {},
      modified: null,
      note: null,
      inferred: false
    };

    var mods = selectedModifiers(data, opts.heroKey, opts.modifierIds);
    if (!mods.length) return result;

    var sum = {};
    mods.forEach(function (mod) {
      var modRow = levelRow(mod.levels, level);
      var delta = isObject(modRow) && isObject(modRow.delta) ? modRow.delta : {};
      Object.keys(delta).forEach(function (key) {
        sum[key] = toFiniteNumber(sum[key], 0) + toFiniteNumber(delta[key], 0);
      });
      if (modRow && modRow.inferred) result.inferred = true;
      result.modifiers.push({
        affixId: mod.affixId,
        nameZh: mod.nameZh || "",
        delta: delta,
        deltaFloorAlt: isObject(modRow) && isObject(modRow.deltaFloorAlt) ? modRow.deltaFloorAlt : null,
        isAnchor: Boolean(modRow && modRow.isAnchor),
        inferred: Boolean(modRow && modRow.inferred)
      });
    });

    var applied = applyDeltas(baseStats, sum, defs);
    result.deltas = sum;
    result.clamped = applied.clamped;
    result.modified = { stats: applied.stats, derived: deriveStats(data, applied.stats) };
    result.note = modifierLevelNote(level);
    return result;
  }

  // 全部等级表：1–15 级各算一行。
  function computeAllLevels(data, options) {
    var opts = isObject(options) ? options : {};
    var rows = [];
    for (var level = MIN_LEVEL; level <= MAX_LEVEL; level += 1) {
      var row = computeLevel(data, {
        heroKey: opts.heroKey,
        level: level,
        libraKey: opts.libraKey,
        modifierIds: opts.modifierIds
      });
      if (row) rows.push(row);
    }
    return rows;
  }

  // 同级对比只看各角色的基础表：利普拉的交易 5 套表不分角色，叠上去 10 行会一模一样；
  // 转职遗物是逐角色的两条，混进来也没有可比性。口径写在表格说明里。
  function compareRows(data, level) {
    var defs = attributeDefs(data);
    var lv = clampLevel(level);
    return heroList(data).map(function (hero, index) {
      var row = levelRow(hero.levels, lv);
      var stats = pickStats(row ? row.stats : null, defs);
      return {
        heroKey: hero.key,
        nameZh: hero.nameZh || hero.key,
        nameEn: hero.nameEn || "",
        order: toFiniteNumber(hero.id, index),
        level: lv,
        isAnchor: Boolean(row && row.isAnchor),
        stats: stats,
        // 派生值一律现算：对比表和详情页走同一条 growthGraphs 路径，两处不可能对不上。
        derived: deriveStats(data, stats)
      };
    });
  }

  function compareValue(row, key) {
    if (!row) return null;
    if (key === "hero") return row.order;
    if (row.stats && typeof row.stats[key] === "number") return row.stats[key];
    if (row.derived && typeof row.derived[key] === "number") return row.derived[key];
    return null;
  }

  // 点列头排序：同值按角色原顺序兜底，永远返回新数组（不动入参）。
  function sortCompareRows(rows, key, dir) {
    var list = Array.isArray(rows) ? rows.slice() : [];
    var sign = dir === "asc" ? 1 : -1;
    list.sort(function (a, b) {
      var left = compareValue(a, key);
      var right = compareValue(b, key);
      if (left === null && right === null) return a.order - b.order;
      if (left === null) return 1;
      if (right === null) return -1;
      if (left === right) return a.order - b.order;
      return left < right ? -sign : sign;
    });
    return list;
  }

  function fmtStat(value) {
    if (value === null || value === undefined || !isFinite(Number(value))) return "—";
    return String(Math.round(Number(value)));
  }

  function fmtDerived(def, value) {
    if (value === null || value === undefined || !isFinite(Number(value))) return "—";
    if (def && def.integer === false) return Number(value).toFixed(1);
    return String(Math.round(Number(value)));
  }

  function fmtSigned(value) {
    var num = toFiniteNumber(value, 0);
    if (num > 0) return "+" + num;
    return String(num);
  }

  function deltaClass(value) {
    var num = toFiniteNumber(value, 0);
    if (num > 0) return "heroes-delta--up";
    if (num < 0) return "heroes-delta--down";
    return "heroes-delta--flat";
  }

  // 「生命力 -5、集中力 +10」：增减量摘要，按属性顺序排。
  function deltaSummary(delta, defs) {
    var list = Array.isArray(defs) ? defs : ATTRIBUTE_FALLBACK;
    return list.filter(function (def) {
      return isObject(delta) && toFiniteNumber(delta[def.key], 0) !== 0;
    }).map(function (def) {
      return def.zh + " " + fmtSigned(delta[def.key]);
    }).join("、");
  }

  function crossCheckFor(data, heroKey) {
    if (!isObject(data) || !Array.isArray(data.crossChecks)) return null;
    for (var i = 0; i < data.crossChecks.length; i += 1) {
      var item = data.crossChecks[i];
      if (isObject(item) && item.heroKey === heroKey && toFiniteNumber(item.mismatchCount, 0) > 0) return item;
    }
    return null;
  }

  function hasHeroData(data) {
    return isObject(data) && heroList(data).length > 0 && isObject(data.growthGraphs);
  }

  // ------------------------------------------------------------------ 状态

  var dom = null;
  var ctxRef = null;

  var state = {
    loaded: false,
    data: null,
    view: "detail",
    heroKey: "",
    level: MAX_LEVEL,
    allLevels: false,
    libraKey: "",
    modifierIds: [],
    sortKey: "hero",
    sortDir: "asc"
  };

  // ------------------------------------------------------------ 渲染小工具

  function helpers() {
    return ctxRef && ctxRef.helpers ? ctxRef.helpers : null;
  }

  function esc(value) {
    var h = helpers();
    if (h && typeof h.escapeHtml === "function") return h.escapeHtml(value);
    return String(value === null || value === undefined ? "" : value)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function pill(text, kind) {
    var h = helpers();
    if (h && typeof h.pill === "function") return h.pill(text, kind);
    return "<span class='pill pill--" + (kind || "purple") + "'>" + esc(text) + "</span>";
  }

  function titleBlock() {
    return "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>角色属性</h1><p>《黑夜君临》各夜行者逐等级属性，以及装备转职遗物后的属性</p></div>" +
      "</header>";
  }

  // ------------------------------------------------------------ 模板：外壳

  function viewControl() {
    return VIEWS.map(function (view) {
      var active = view.key === state.view;
      return "<button type='button' class='segment-button" + (active ? " is-active" : "") + "'" +
        " data-heroes-view='" + view.key + "' data-testid='heroes-view-" + view.key + "'" +
        " role='radio' aria-checked='" + active + "'>" + esc(view.label) + "</button>";
    }).join("");
  }

  function levelControl() {
    var out = "";
    for (var level = MIN_LEVEL; level <= MAX_LEVEL; level += 1) {
      var active = level === state.level;
      out += "<button type='button' class='segment-button" + (active ? " is-active" : "") + "'" +
        " data-heroes-level='" + level + "' data-testid='heroes-level-" + level + "'" +
        " role='radio' aria-checked='" + active + "'>" + level + "</button>";
    }
    return out;
  }

  function libraControl(data) {
    var options = "<option value=''>无（角色原表）</option>";
    libraList(data).forEach(function (deal) {
      var label = (deal.dealLineZh || deal.nameZh || deal.key) +
        (deal.statNameZh ? "（" + deal.statNameZh + "）" : "");
      options += "<option value='" + esc(deal.key) + "'" +
        (deal.key === state.libraKey ? " selected" : "") + ">" + esc(label) + "</option>";
    });
    return "<label class='select-field heroes-libra-field'><span class='sr-only'>利普拉的交易</span>" +
      "<select data-heroes-libra data-testid='heroes-libra'>" + options + "</select></label>";
  }

  function heroPicker(data) {
    var buttons = heroList(data).map(function (hero) {
      var active = hero.key === state.heroKey;
      var label = (hero.nameZh || hero.key) + (hero.nameEn ? " " + hero.nameEn : "");
      return "<button type='button' class='heroes-hero" + (active ? " is-active" : "") + "'" +
        " data-heroes-hero='" + esc(hero.key) + "' data-testid='heroes-hero-" + esc(hero.key) + "'" +
        " aria-pressed='" + active + "' aria-label='" + esc(label) + "'>" +
        "<span class='heroes-hero-zh'>" + esc(hero.nameZh || hero.key) + "</span>" +
        "<span class='heroes-hero-en'>" + esc(hero.nameEn || "") + "</span>" +
        "</button>";
    }).join("");
    return "<section class='card heroes-picker' data-testid='heroes-picker'>" +
      "<div class='heroes-picker-grid'>" + buttons + "</div></section>";
  }

  function shell(data) {
    return "" +
      "<div class='page-content heroes-content'>" +
      titleBlock() +
      "<section class='card heroes-toolbar' data-testid='heroes-toolbar'>" +
      "<div class='heroes-toolbar-row'>" +
      "<div class='heroes-control'><span class='heroes-control-label'>视图</span>" +
      "<div class='segmented-control heroes-view' role='radiogroup' aria-label='视图' " +
      "data-testid='heroes-view'>" + viewControl() + "</div></div>" +
      "<div class='heroes-control heroes-control--grow'><span class='heroes-control-label'>等级</span>" +
      "<div class='segmented-control heroes-levels' role='radiogroup' aria-label='等级' " +
      "data-testid='heroes-level'>" + levelControl() + "</div></div>" +
      "<div class='heroes-control'><span class='heroes-control-label'>表格</span>" +
      "<label class='switch-control heroes-all-switch'>" +
      "<input type='checkbox' data-heroes-all data-testid='heroes-all'" +
      (state.allLevels ? " checked" : "") + ">" +
      "<span class='switch-track'></span><span>全部等级</span></label></div>" +
      "</div>" +
      "<div class='heroes-toolbar-row heroes-toolbar-row--libra'>" +
      "<div class='heroes-control heroes-control--libra'><span class='heroes-control-label'>利普拉的交易</span>" +
      libraControl(data) + "</div>" +
      "<p class='heroes-libra-hint' data-testid='heroes-libra-hint'></p>" +
      "</div>" +
      "</section>" +
      heroPicker(data) +
      "<div class='heroes-body' data-testid='heroes-body'></div>" +
      "<div data-testid='heroes-footer'></div>" +
      "</div>";
  }

  function unavailableShell(message) {
    return "" +
      "<div class='page-content heroes-content'>" +
      titleBlock() +
      "<article class='card page-placeholder-card' data-testid='heroes-card'>" +
      "<div class='section-heading'><div class='section-icon'>◈</div>" +
      "<div><h2>数据未内置</h2><p>" + esc(message) + "</p></div></div>" +
      "<div class='page-status-row'>" + pill("数据未内置", "amber") +
      "<span>缺少 resources/" + DATA_NAME + ".json</span></div>" +
      "<p class='data-hint'>源文件生成后运行仓库根的 scripts/sync-data.sh 同步到 windows/resources/ " +
      "与 macOS 的 Resources/，无需改代码。</p>" +
      "</article></div>";
  }

  // ------------------------------------------------------- 模板：单等级视图

  function statCard(label, baseText, modifiedText, delta, clampedFrom, hint) {
    var changed = modifiedText !== null && modifiedText !== baseText;
    var body;
    if (!changed) {
      // 没勾转职遗物、或这一项没被改动：只显示一个数字，不摆「46 → 46」这种废话。
      body = "<strong class='heroes-stat-value'>" +
        esc(modifiedText === null ? baseText : modifiedText) + "</strong>";
    } else {
      body = "<span class='heroes-stat-base'>" + esc(baseText) + "</span>" +
        "<span class='heroes-stat-arrow' aria-hidden='true'>→</span>" +
        "<strong class='heroes-stat-value'>" + esc(modifiedText) + "</strong>";
    }
    var deltaHtml = "";
    if (delta !== null && delta !== undefined && toFiniteNumber(delta, 0) !== 0) {
      deltaHtml = "<span class='heroes-stat-delta " + deltaClass(delta) + "'>" +
        esc(fmtSigned(delta)) + "</span>";
    }
    var notes = "";
    if (clampedFrom !== null && clampedFrom !== undefined) {
      notes += "<span class='heroes-stat-note heroes-stat-note--clamp'>" +
        esc("原为 " + clampedFrom + "，已钳到最低 " + MIN_STAT) + "</span>";
    }
    if (hint) notes += "<span class='heroes-stat-note'>" + esc(hint) + "</span>";
    return "<div class='heroes-stat" + (changed ? " is-changed" : "") + "'>" +
      "<span class='heroes-stat-label'>" + esc(label) + "</span>" +
      "<div class='heroes-stat-main'>" + body + deltaHtml + "</div>" +
      notes + "</div>";
  }

  function singleLevelHtml(data, computed) {
    var attrs = attributeDefs(data);
    var derived = derivedDefs(data);
    var hasMods = Boolean(computed.modified);
    var attrCards = attrs.map(function (def) {
      var base = computed.base.stats[def.key];
      var after = hasMods ? computed.modified.stats[def.key] : null;
      var clamp = Object.prototype.hasOwnProperty.call(computed.clamped, def.key)
        ? computed.clamped[def.key] : null;
      return statCard(
        def.zh,
        fmtStat(base),
        after === null ? null : fmtStat(after),
        hasMods ? computed.deltas[def.key] : null,
        clamp,
        ""
      );
    }).join("");

    var derivedCards = derived.map(function (def) {
      var base = computed.base.derived[def.key];
      var after = hasMods ? computed.modified.derived[def.key] : null;
      var delta = null;
      if (hasMods && typeof base === "number" && typeof after === "number") {
        delta = Math.round((after - base) * 10) / 10;
      }
      return statCard(
        def.zh,
        fmtDerived(def, base),
        after === null || after === undefined ? null : fmtDerived(def, after),
        delta,
        null,
        def.key === "equipLoad" ? EQUIP_LOAD_HINT : ""
      );
    }).join("");

    return "<div class='heroes-stat-grid' data-testid='heroes-stat-grid'>" + attrCards + "</div>" +
      "<h3 class='heroes-subhead'>派生值（按 CalcCorrectGraph 重算）</h3>" +
      "<div class='heroes-stat-grid heroes-stat-grid--derived' data-testid='heroes-derived-grid'>" +
      derivedCards + "</div>";
  }

  // ------------------------------------------------------- 模板：全部等级表

  function allLevelsHtml(data, rows) {
    var attrs = attributeDefs(data);
    var derived = derivedDefs(data);
    var hasMods = rows.length > 0 && Boolean(rows[0].modified);

    var head = "<tr><th scope='col'>等级</th>" +
      attrs.map(function (def) { return "<th scope='col'>" + esc(def.zh) + "</th>"; }).join("") +
      derived.map(function (def) { return "<th scope='col'>" + esc(def.zh) + "</th>"; }).join("") +
      "<th scope='col'>数值来源</th></tr>";

    var body = rows.map(function (row) {
      var classes = [];
      if (row.isAnchor) classes.push("is-anchor");
      if (row.level === state.level) classes.push("is-current");
      var cells = attrs.map(function (def) {
        var value = row.modified ? row.modified.stats[def.key] : row.base.stats[def.key];
        var delta = row.modified ? toFiniteNumber(row.deltas[def.key], 0) : 0;
        var clamped = Object.prototype.hasOwnProperty.call(row.clamped, def.key);
        return "<td class='heroes-cell" + (clamped ? " is-clamped" : "") + "'>" +
          "<span class='heroes-cell-value'>" + esc(fmtStat(value)) + "</span>" +
          (delta !== 0
            ? "<span class='heroes-cell-delta " + deltaClass(delta) + "'>" + esc(fmtSigned(delta)) + "</span>"
            : "") +
          (clamped ? "<span class='heroes-cell-clamp' title='钳到最低 1'>钳</span>" : "") +
          "</td>";
      }).join("");
      var derivedCells = derived.map(function (def) {
        var base = row.base.derived[def.key];
        var value = row.modified ? row.modified.derived[def.key] : base;
        var delta = null;
        if (row.modified && typeof base === "number" && typeof value === "number") {
          delta = Math.round((value - base) * 10) / 10;
        }
        return "<td class='heroes-cell'>" +
          "<span class='heroes-cell-value'>" + esc(fmtDerived(def, value)) + "</span>" +
          (delta !== null && delta !== 0
            ? "<span class='heroes-cell-delta " + deltaClass(delta) + "'>" + esc(fmtSigned(delta)) + "</span>"
            : "") +
          "</td>";
      }).join("");
      // 两个标记不是一回事：前者说基础表这一级是不是参数原值，后者说转职遗物的增减量从哪来。
      var notes = row.isAnchor ? pill("基础锚点", "purple") : pill("基础插值", "gray");
      if (hasMods && row.note) {
        notes += pill(row.note.label, LEVEL_NOTES[row.note.kind].kind);
      }
      return "<tr" + (classes.length ? " class='" + classes.join(" ") + "'" : "") + ">" +
        "<th scope='row'>" + row.level + "</th>" + cells + derivedCells +
        "<td class='heroes-cell heroes-cell--notes'>" + notes + "</td></tr>";
    }).join("");

    return "<div class='table-wrap heroes-table-wrap'>" +
      "<table class='heroes-table heroes-level-table' data-testid='heroes-level-table'>" +
      "<thead>" + head + "</thead><tbody>" + body + "</tbody></table></div>" +
      "<p class='heroes-table-caption'>" +
      esc("加粗行是参数表里的锚点（1 / 2 / 12 / 15 级），其余等级按相邻锚点线性插值后向下取整。") +
      "</p>";
  }

  // --------------------------------------------------------- 模板：转职遗物

  function relicItemsHtml(mod) {
    var items = Array.isArray(mod.relicItems) ? mod.relicItems : [];
    if (!items.length) return "<span class='heroes-mod-relic'>遗物：数据未内置</span>";
    return "<span class='heroes-mod-relic'>遗物：" + items.map(function (item) {
      return esc(item.nameZh || item.nameEn || "未知遗物") +
        pill(item.colorZh || "未知", RELIC_COLOR_PILLS[toFiniteNumber(item.color, 4)] || "gray");
    }).join("、") + "</span>";
  }

  function modifiersHtml(data, computed) {
    var attrs = attributeDefs(data);
    var mods = modifiersForHero(data, state.heroKey);
    if (!mods.length) {
      return "<section class='card heroes-card' data-testid='heroes-mods'>" +
        "<div class='section-heading'><div class='section-icon'>◇</div>" +
        "<div><h2>转职遗物</h2><p>数据未内置</p></div></div></section>";
    }
    var note = modifierLevelNote(state.level);
    var rows = mods.map(function (mod) {
      var checked = state.modifierIds.indexOf(String(mod.affixId)) !== -1;
      var modRow = levelRow(mod.levels, state.level);
      var delta = isObject(modRow) && isObject(modRow.delta) ? modRow.delta : {};
      var alt = isObject(modRow) && isObject(modRow.deltaFloorAlt) ? modRow.deltaFloorAlt : null;
      var summary = deltaSummary(delta, attrs) || "本级无增减";
      return "<label class='heroes-mod" + (checked ? " is-checked" : "") + "'" +
        " data-testid='heroes-mod-" + esc(mod.affixId) + "'>" +
        "<input type='checkbox' data-heroes-mod='" + esc(mod.affixId) + "'" +
        (checked ? " checked" : "") + ">" +
        "<span class='heroes-mod-box' aria-hidden='true'>✓</span>" +
        "<span class='heroes-mod-copy'>" +
        "<span class='heroes-mod-name'>" + esc(mod.nameZh || mod.nameEn || "未命名词条") +
        (mod.dlcOnly ? pill("仅 DLC 池可掉", "blue") : "") + "</span>" +
        "<span class='heroes-mod-meta'>" + relicItemsHtml(mod) + "</span>" +
        "<span class='heroes-mod-delta'>" + esc(state.level + " 级增减：" + summary) +
        pill(note.label, LEVEL_NOTES[note.kind].kind) + "</span>" +
        (alt
          ? "<span class='heroes-mod-alt'>" +
            esc("若按 floor 取整则为：" + deltaSummary(alt, attrs)) + "</span>"
          : "") +
        "</span></label>";
    }).join("");

    var clampedKeys = computed ? Object.keys(computed.clamped) : [];
    var clampNote = "";
    if (clampedKeys.length) {
      var names = clampedKeys.map(function (key) {
        for (var i = 0; i < attrs.length; i += 1) {
          if (attrs[i].key === key) return attrs[i].zh;
        }
        return key;
      }).join("、");
      clampNote = "<p class='heroes-clamp-note' data-testid='heroes-clamp-note'>" +
        pill("已钳位", "red") + esc(names + " 叠加后不足 1，已钳到最低 " + MIN_STAT + "（游戏里属性不会低于 1）") +
        "</p>";
    }

    return "<section class='card heroes-card' data-testid='heroes-mods'>" +
      "<div class='section-heading'><div class='section-icon'>◇</div>" +
      "<div><h2>转职遗物</h2><p>两条词条可同时勾选，效果相加；派生值按 growthGraphs 重算</p></div></div>" +
      "<div class='heroes-mod-list'>" + rows + "</div>" + clampNote +
      "<p class='data-hint'>" +
      esc("锚点只有 1 级与 12 级：2–11 级是线性插值后向零取整的推算值，13–15 级沿用 12 级锚点" +
        "（沿用这一条已由多组 15 级实测确认）。") + "</p>" +
      "</section>";
  }

  // --------------------------------------------------------- 模板：同级对比

  function compareHtml(data) {
    var attrs = attributeDefs(data);
    var derived = derivedDefs(data);
    var rows = sortCompareRows(compareRows(data, state.level), state.sortKey, state.sortDir);
    if (!rows.length) {
      return "<section class='card heroes-card'><div class='empty-state'>" +
        "<div class='empty-icon'>☷</div><h3>数据未内置</h3><p>没有可对比的角色</p></div></section>";
    }

    function headCell(key, label, align) {
      var active = state.sortKey === key;
      var arrow = active ? (state.sortDir === "asc" ? " ↑" : " ↓") : "";
      var aria = active ? (state.sortDir === "asc" ? "ascending" : "descending") : "none";
      return "<th scope='col' aria-sort='" + aria + "'" +
        (align ? " class='heroes-th--num'" : "") + ">" +
        "<button type='button' class='heroes-sort" + (active ? " is-active" : "") + "'" +
        " data-heroes-sort='" + esc(key) + "' data-testid='heroes-sort-" + esc(key) + "'>" +
        esc(label) + "<span class='heroes-sort-arrow'>" + esc(arrow) + "</span></button></th>";
    }

    var head = "<tr>" + headCell("hero", "角色", false) +
      attrs.map(function (def) { return headCell(def.key, def.zh, true); }).join("") +
      derived.map(function (def) { return headCell(def.key, def.zh, true); }).join("") +
      "</tr>";

    var body = rows.map(function (row) {
      var cells = attrs.map(function (def) {
        return "<td class='heroes-cell'>" + esc(fmtStat(row.stats[def.key])) + "</td>";
      }).join("");
      var derivedCells = derived.map(function (def) {
        return "<td class='heroes-cell'>" + esc(fmtDerived(def, row.derived[def.key])) + "</td>";
      }).join("");
      return "<tr" + (row.heroKey === state.heroKey ? " class='is-current'" : "") + ">" +
        "<th scope='row' class='heroes-compare-name'>" +
        "<span class='heroes-hero-zh'>" + esc(row.nameZh) + "</span>" +
        "<span class='heroes-hero-en'>" + esc(row.nameEn) + "</span></th>" +
        cells + derivedCells + "</tr>";
    }).join("");

    return "<section class='card heroes-card' data-testid='heroes-compare'>" +
      "<div class='section-heading'><div class='section-icon'>◫</div>" +
      "<div><h2>同级对比（" + state.level + " 级）</h2>" +
      "<p>10 个夜行者在同一等级下的属性与派生值，点列头排序</p></div></div>" +
      "<div class='table-wrap heroes-table-wrap'>" +
      "<table class='heroes-table heroes-compare-table' data-testid='heroes-compare-table'>" +
      "<thead>" + head + "</thead><tbody>" + body + "</tbody></table></div>" +
      "<p class='heroes-table-caption'>" +
      esc("对比表只用各角色的基础表：利普拉的交易 5 套表不分角色（叠上去 10 行会一模一样），" +
        "转职遗物是逐角色的两条，都不进对比。") + "</p>" +
      "</section>";
  }

  // ------------------------------------------------------------- 模板：底部

  var INTERPOLATION_LABELS = {
    baseAnchorLevels: "基础表锚点等级",
    modifierAnchorLevels: "转职遗物锚点等级",
    maxLevel: "最高等级",
    baseRule: "基础属性插值规则",
    baseRounding: "基础属性取整",
    baseVerified: "基础表已实测",
    baseVerification: "基础表实测说明",
    derivedRule: "派生值算法",
    modifierRule: "转职遗物插值规则",
    modifierRounding: "转职遗物取整",
    modifierVerified: "转职遗物（保守合取）",
    modifierVerifiedNote: "关于 modifierVerified",
    modifierAnchorVerified: "转职遗物锚点已实测",
    modifierAnchorVerification: "锚点实测说明",
    modifierMidLevelsVerified: "转职遗物 2–11 级已实测",
    modifierInference: "转职遗物推断范围",
    libraRule: "利普拉的交易规则"
  };

  var INTERPOLATION_ORDER = [
    "baseAnchorLevels", "baseRule", "baseRounding", "baseVerified", "baseVerification",
    "derivedRule",
    "modifierAnchorLevels", "modifierRule", "modifierRounding",
    "modifierAnchorVerified", "modifierAnchorVerification",
    "modifierMidLevelsVerified", "modifierInference",
    "modifierVerified", "modifierVerifiedNote",
    "libraRule", "maxLevel"
  ];

  function interpolationValue(value) {
    if (typeof value === "boolean") return value ? "是" : "否";
    if (Array.isArray(value)) return value.join(" / ");
    return String(value === null || value === undefined ? "—" : value);
  }

  function interpolationHtml(data) {
    var info = isObject(data) && isObject(data.interpolation) ? data.interpolation : null;
    if (!info) return "";
    var keys = INTERPOLATION_ORDER.filter(function (key) {
      return Object.prototype.hasOwnProperty.call(info, key);
    });
    Object.keys(info).forEach(function (key) {
      if (keys.indexOf(key) === -1) keys.push(key);
    });
    var rows = keys.map(function (key) {
      return "<div class='heroes-meta-row'><dt>" + esc(INTERPOLATION_LABELS[key] || key) + "</dt>" +
        "<dd>" + esc(interpolationValue(info[key])) + "</dd></div>";
    }).join("");
    return "<details class='card heroes-details' data-testid='heroes-interpolation'>" +
      "<summary><span class='heroes-summary-title'>插值与取整说明</span>" +
      pill(keys.length + " 条", "purple") + "</summary>" +
      "<div class='heroes-details-body'><dl class='heroes-meta'>" + rows + "</dl></div></details>";
  }

  function caveatsHtml(data) {
    var list = isObject(data) && Array.isArray(data.caveats) ? data.caveats : [];
    if (!list.length) return "";
    return "<details class='card heroes-details' data-testid='heroes-caveats'>" +
      "<summary><span class='heroes-summary-title'>数据说明与已知取舍</span>" +
      pill(list.length + " 条", "amber") + "</summary>" +
      "<div class='heroes-details-body'><ul class='heroes-caveat-list'>" +
      list.map(function (line) {
        return "<li>" + esc(line) + "</li>";
      }).join("") + "</ul></div></details>";
  }

  function versionHtml(data) {
    var counts = isObject(data) && isObject(data.counts) ? data.counts : {};
    var sources = isObject(data) && Array.isArray(data.sources) ? data.sources : [];
    var rows = [
      { label: "游戏版本", value: data.gameVersion || "未知" },
      { label: "数据版本", value: data.dataVersion || "未知" },
      { label: "生成时间", value: data.generatedAt || "未知" },
      { label: "结构版本", value: "schemaVersion " + interpolationValue(data.schemaVersion) },
      {
        label: "内容",
        value: interpolationValue(counts.heroes) + " 个角色 × " +
          interpolationValue(counts.levelsPerHero) + " 级 · " +
          interpolationValue(counts.statModifiers) + " 条转职遗物 · " +
          interpolationValue(counts.libraRespecs) + " 套利普拉交易"
      }
    ].map(function (row) {
      return "<div class='heroes-meta-row'><dt>" + esc(row.label) + "</dt>" +
        "<dd>" + esc(row.value) + "</dd></div>";
    }).join("");

    var sourceList = sources.map(function (item) {
      return "<li><strong>" + esc(item.name || "未命名来源") + "</strong>" +
        (item.revision ? "<span>" + esc(item.revision) + "</span>" : "") +
        (item.note ? "<p>" + esc(item.note) + "</p>" : "") + "</li>";
    }).join("");

    return "<details class='card heroes-details' data-testid='heroes-version'>" +
      "<summary><span class='heroes-summary-title'>数据版本与来源</span>" +
      pill(data.gameVersion || "未知版本", "green") + "</summary>" +
      "<div class='heroes-details-body'><dl class='heroes-meta'>" + rows + "</dl>" +
      (sourceList ? "<ul class='heroes-source-list'>" + sourceList + "</ul>" : "") +
      "</div></details>";
  }

  function footerHtml(data) {
    return "<div class='heroes-footer'>" +
      interpolationHtml(data) + caveatsHtml(data) + versionHtml(data) + "</div>";
  }

  // -------------------------------------------------------------- 渲染主体

  function statusRow(data, computed) {
    var hero = findHero(data, state.heroKey);
    var libra = findLibra(data, state.libraKey);
    var parts = [];
    parts.push(pill((hero ? hero.nameZh : "未知角色") + " · " + state.level + " 级", "purple"));
    if (computed && computed.isAnchor) parts.push(pill("基础锚点等级", "green"));
    else parts.push(pill("基础插值等级", "gray"));
    if (libra) parts.push(pill("利普拉：" + (libra.statNameZh || libra.nameZh), "amber"));
    if (computed && computed.modified) {
      parts.push(pill("转职遗物 " + computed.modifiers.length + " 条", "blue"));
      if (computed.note) parts.push(pill(computed.note.label, LEVEL_NOTES[computed.note.kind].kind));
    }
    var cross = crossCheckFor(data, state.heroKey);
    var note = "";
    if (cross) {
      note = "<span class='heroes-cross-note'>" +
        esc("与外部 wiki 有 " + cross.mismatchCount + " 格差异，本页以参数为准：" + (cross.note || "")) +
        "</span>";
    }
    return "<div class='page-status-row heroes-status' data-testid='heroes-status'>" +
      parts.join("") + note + "</div>";
  }

  function detailHtml(data) {
    var computed = computeLevel(data, {
      heroKey: state.heroKey,
      level: state.level,
      libraKey: state.libraKey,
      modifierIds: state.modifierIds
    });
    if (!computed) {
      return "<section class='card heroes-card'><div class='empty-state'>" +
        "<div class='empty-icon'>☷</div><h3>数据未内置</h3><p>这个角色没有可用的等级数据</p>" +
        "</div></section>";
    }
    var hero = findHero(data, state.heroKey);
    var libra = findLibra(data, state.libraKey);
    var heading = "<div class='section-heading'><div class='section-icon'>◆</div>" +
      "<div><h2>" + esc(hero ? hero.nameZh : "角色") + "　" +
      esc(state.allLevels ? "1–15 级属性表" : state.level + " 级属性") + "</h2>" +
      // 参数里 5 笔交易共用一个文本 ID，nameZh 是脚本拼的「效果名（属性名）」，
      // 游戏里真正能看到的逐笔文案是 dealLineZh（对话选项），两个都给出来。
      "<p>" + esc(libra
        ? "基础表已整套换成「" + (libra.nameZh || libra.key) + "」" +
          (libra.dealLineZh ? "，对话选项：" + libra.dealLineZh : "")
        : "数值来自 HeroStatusParam，中间等级为锚点间线性插值") + "</p></div></div>";

    var body = state.allLevels
      ? allLevelsHtml(data, computeAllLevels(data, {
        heroKey: state.heroKey,
        libraKey: state.libraKey,
        modifierIds: state.modifierIds
      }))
      : singleLevelHtml(data, computed);

    return "<section class='card heroes-card' data-testid='heroes-detail'>" +
      heading + statusRow(data, computed) + body + "</section>" +
      modifiersHtml(data, computed);
  }

  function renderBody() {
    if (!dom || !state.data) return;
    var body = dom.querySelector("[data-testid='heroes-body']");
    if (!body) return;
    body.innerHTML = state.view === "compare" ? compareHtml(state.data) : detailHtml(state.data);
    var hint = dom.querySelector("[data-testid='heroes-libra-hint']");
    if (hint) {
      var libra = findLibra(state.data, state.libraKey);
      hint.innerHTML = libra
        ? pill("整套替换", "amber") + esc(LIBRA_HINT)
        : esc("选中后基础表整套换成对应的替换表，转职遗物仍可叠加。");
    }
  }

  function syncControls() {
    if (!dom) return;
    var views = dom.querySelectorAll("[data-heroes-view]");
    for (var i = 0; i < views.length; i += 1) {
      var activeView = views[i].getAttribute("data-heroes-view") === state.view;
      views[i].classList.toggle("is-active", activeView);
      views[i].setAttribute("aria-checked", String(activeView));
    }
    var levels = dom.querySelectorAll("[data-heroes-level]");
    for (var j = 0; j < levels.length; j += 1) {
      var activeLevel = Number(levels[j].getAttribute("data-heroes-level")) === state.level;
      levels[j].classList.toggle("is-active", activeLevel);
      levels[j].setAttribute("aria-checked", String(activeLevel));
    }
    var heroes = dom.querySelectorAll("[data-heroes-hero]");
    for (var k = 0; k < heroes.length; k += 1) {
      var activeHero = heroes[k].getAttribute("data-heroes-hero") === state.heroKey;
      heroes[k].classList.toggle("is-active", activeHero);
      heroes[k].setAttribute("aria-pressed", String(activeHero));
    }
    var allSwitch = dom.querySelector("[data-heroes-all]");
    if (allSwitch) {
      allSwitch.checked = state.allLevels;
      allSwitch.disabled = state.view === "compare";
      var wrap = allSwitch.closest(".switch-control");
      if (wrap) wrap.classList.toggle("is-disabled", state.view === "compare");
    }
  }

  function setHero(key) {
    if (state.heroKey === key) return;
    state.heroKey = key;
    state.modifierIds = []; // 转职遗物是逐角色的两条，换角色必须清空勾选
  }

  function bindEvents() {
    if (!dom) return;

    dom.addEventListener("click", function (event) {
      var viewButton = event.target.closest("[data-heroes-view]");
      if (viewButton) {
        state.view = viewButton.getAttribute("data-heroes-view");
        syncControls();
        renderBody();
        return;
      }
      var levelButton = event.target.closest("[data-heroes-level]");
      if (levelButton) {
        state.level = clampLevel(levelButton.getAttribute("data-heroes-level"));
        syncControls();
        renderBody();
        return;
      }
      var heroButton = event.target.closest("[data-heroes-hero]");
      if (heroButton) {
        setHero(heroButton.getAttribute("data-heroes-hero"));
        syncControls();
        renderBody();
        return;
      }
      var sortButton = event.target.closest("[data-heroes-sort]");
      if (sortButton) {
        var key = sortButton.getAttribute("data-heroes-sort");
        if (state.sortKey === key) {
          state.sortDir = state.sortDir === "asc" ? "desc" : "asc";
        } else {
          state.sortKey = key;
          state.sortDir = key === "hero" ? "asc" : "desc";
        }
        renderBody();
      }
    });

    dom.addEventListener("change", function (event) {
      var target = event.target;
      if (!target) return;
      if (target.hasAttribute && target.hasAttribute("data-heroes-all")) {
        state.allLevels = Boolean(target.checked);
        renderBody();
        return;
      }
      if (target.hasAttribute && target.hasAttribute("data-heroes-libra")) {
        state.libraKey = target.value || "";
        renderBody();
        return;
      }
      if (target.hasAttribute && target.hasAttribute("data-heroes-mod")) {
        var id = target.getAttribute("data-heroes-mod");
        var index = state.modifierIds.indexOf(id);
        if (target.checked && index === -1) state.modifierIds.push(id);
        if (!target.checked && index !== -1) state.modifierIds.splice(index, 1);
        renderBody();
      }
    });
  }

  function renderData(data) {
    if (!dom) return;
    state.data = data;
    var heroes = heroList(data);
    if (!findHero(data, state.heroKey)) {
      state.heroKey = heroes.length ? heroes[0].key : "";
      state.modifierIds = [];
    }
    dom.innerHTML = shell(data);
    bindEvents();
    syncControls();
    renderBody();
    var footer = dom.querySelector("[data-testid='heroes-footer']");
    if (footer) footer.innerHTML = footerHtml(data);
  }

  function load(ctx) {
    ctxRef = ctx;
    if (!dom) return;
    ctx.getGameData(DATA_NAME).then(function (data) {
      if (!dom) return;
      if (!hasHeroData(data)) {
        state.loaded = false;
        dom.innerHTML = unavailableShell("尚未提供角色属性数据文件，页面无法显示数值。");
        return;
      }
      state.loaded = true;
      renderData(data);
    });
  }

  var api = {
    init: function (mount, ctx) {
      dom = mount;
      ctxRef = ctx;
      mount.innerHTML = "<div class='page-content heroes-content'>" +
        "<p class='heroes-loading' data-testid='heroes-loading'>正在载入角色属性数据…</p></div>";
      load(ctx);
    },
    refresh: function (ctx) {
      ctxRef = ctx;
      if (!dom) return;
      if (!state.loaded) load(ctx);
    },
    // 纯计算部分，供 windows/tests/heroes.test.mjs 直接测试。
    _internals: {
      MAX_LEVEL: MAX_LEVEL,
      MIN_STAT: MIN_STAT,
      LEVEL_NOTES: LEVEL_NOTES,
      attributeDefs: attributeDefs,
      derivedDefs: derivedDefs,
      evalGrowthGraph: evalGrowthGraph,
      deriveStats: deriveStats,
      heroList: heroList,
      findHero: findHero,
      libraList: libraList,
      findLibra: findLibra,
      modifiersForHero: modifiersForHero,
      selectedModifiers: selectedModifiers,
      clampLevel: clampLevel,
      levelRow: levelRow,
      pickStats: pickStats,
      modifierLevelNote: modifierLevelNote,
      applyDeltas: applyDeltas,
      computeLevel: computeLevel,
      computeAllLevels: computeAllLevels,
      compareRows: compareRows,
      compareValue: compareValue,
      sortCompareRows: sortCompareRows,
      deltaSummary: deltaSummary,
      crossCheckFor: crossCheckFor,
      hasHeroData: hasHeroData,
      fmtStat: fmtStat,
      fmtDerived: fmtDerived,
      fmtSigned: fmtSigned,
      deltaClass: deltaClass
    }
  };

  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  if (root && root.document) {
    root.NightreignPages = root.NightreignPages || {};
    root.NightreignPages[PAGE_KEY] = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this);
