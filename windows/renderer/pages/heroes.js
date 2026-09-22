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
//     页面照常展示但必须标出「未实测的遗留值」—— 单等级卡片上有小字，两张表的列头
//     带 `*` 注记、表下有脚注（靠 statNames.derived[].inGameLabel 判定，不写死 key）。
//
// 与 macOS 端的一致性（不是口号，是可执行的）：
//   · 下面的 COPY 与 macOS 的 RelicCore/HeroData.swift 里的 HeroStatsCopy 是同一份文案，
//     两端各自的用例（tests/heroes.test.mjs 与 RelicCoreChecks/HeroStatsChecks.swift）
//     把同一批字面量钉死，一端改字另一端没跟上就会各自红。
//   · 锚点等级（基础表 1/2/12/15、转职遗物 1/12）与最大等级一律读数据集的
//     interpolation，两端都不写死；换一组锚点 / 换一个 maxLevel，两端的等级选择器、
//     表格行数、标题与汇总一起跟着变（缺 interpolation.maxLevel 时退回各角色
//     levels 里的最大等级，与 macOS 的 HeroStatsIndex.maxLevel / levelRange 同一条）。
//   · 缺数据一律给破折号，**不要**退回 0：0 是真实数值，破折号才是「没有」。
//     属性与派生值一视同仁（缺哪一项就是哪一项破折号），对比表里某一级缺行的
//     角色整行丢掉，而不是摆一行 0。
//   · 增减量的主数字一律是**生效值**（最终 − 基础）。词条请求 -9 而属性被钳到 1 时，
//     卡片上的大数字写 -8（真正发生的变化），请求值 -9 只出现在小字 / title 里
//     （COPY.clampRequestedNote），两端同一条口径、两端用例各钉一遍。
//   · 「插值与验证口径（N 条）」两端渲染同一组说明、数同一个 N：说明由
//     interpolationNotes(data) 拼（与 macOS HeroInterpolation.notes 同序同文），
//     而不是一端数 interpolation 的字段数、另一端数拼好的条目数。
(function (root) {
  "use strict";

  var PAGE_KEY = "heroes";
  var DATA_NAME = "heroes";

  // ---------------------------------------------------------------- 常量表

  // 最大等级只有在数据集既没给 interpolation.maxLevel、角色表里也一行都没有时
  // 才退回这个常量（与 macOS HeroStatsIndex.maxLevel 的 `?? 15` 同一条兜底）。
  // 页面各处一律走 maxLevelOf(data) / levelRange(data)，**不要**再引用它。
  var FALLBACK_MAX_LEVEL = 15;
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
    { key: "hp", zh: "血量", en: "HP", fromStat: "vigor", graphId: 100, integer: true, inGameLabel: true },
    { key: "fp", zh: "专注值", en: "FP", fromStat: "mind", graphId: 101, integer: true, inGameLabel: true },
    { key: "stamina", zh: "精力", en: "Stamina", fromStat: "endurance", graphId: 104, integer: true, inGameLabel: true },
    { key: "equipLoad", zh: "负重上限", en: "Equip Load", fromStat: "endurance", graphId: 220, integer: false, inGameLabel: false }
  ];

  // 遗物颜色 → pill 配色，与 lookup.js 的 COLOR_PILLS 同一套。
  var RELIC_COLOR_PILLS = ["red", "blue", "amber", "green", "gray"];

  // 转职遗物在某一级的数值来源配色；文案走 COPY.modifierSource（两端同一串）。
  var SOURCE_PILL = { anchor: "green", inferred: "amber", carried: "blue" };

  // ------------------------------------------------------------ 双端共用文案
  // macOS 端 RelicCore/HeroData.swift 里有一份同名同结构的 HeroStatsCopy，
  // 两端的测试 / 自检各自把下面这些字符串钉死 —— 只要一端改字、另一端没跟上，
  // 两边的用例就会各自红一片。改文案时请两端 + 两份用例一起改。
  var COPY = {
    missing: "—",                       // 没有数值时统一破折号，不要退回 0
    emptyData: "数据未内置",

    viewSingle: "单角色",
    viewCompare: "同级对比",

    baseLevelBadge: function (level, isAnchor) {
      return level + (isAnchor ? " 级是参数锚点" : " 级为插值推算");
    },
    baseAnchorTag: "参数锚点",
    baseInterpolatedTag: "插值推算",
    allLevelsCaption: function (anchorLevels) {
      return "加粗行是参数表里的锚点（" + anchorLevels.join(" / ") +
        " 级），其余等级按相邻锚点线性插值后向下取整。";
    },

    modifierCountBadge: function (count) { return "转职遗物 " + count + " 条"; },
    modifierSubtitle: "勾选后在基础属性上加减（可同时勾选，效果相加）；派生值按 CalcCorrectGraph 重算",
    dlcOnlyTag: "仅 DLC 池可掉",
    noDeltaAtLevel: "本级无增减",
    noModifierData: "数据未内置该角色的转职遗物词条",
    // 三种来源三种说法；锚点等级一律读数据集，两端都不写死 1 / 12。
    modifierSource: function (level, anchorLevels) {
      var list = Array.isArray(anchorLevels) ? anchorLevels : [];
      if (!list.length) return null;
      var last = Math.max.apply(null, list);
      if (list.indexOf(level) !== -1) return { source: "anchor", label: "词条锚点" };
      if (level > last) return { source: "carried", label: "词条沿用 " + last + " 级锚点" };
      return { source: "inferred", label: "词条推算" };
    },
    // deltaFloorAlt 只含「换成 floor 取整后结果不同」的项，而这些项恒为负
    // （floor 与 trunc 只在负数上差 1）。文案要写清楚这是负向项的替换，
    // 而不是整条词条只剩这几项。
    floorAlt: function (summary) {
      return "若按 floor 取整，负向项改为：" + summary + "（其余项不变）";
    },

    clampCellTag: "钳",
    clampRowTag: "已钳位",
    clampTail: "已钳到最低 " + MIN_STAT,
    clampFloor: "（游戏里属性不会低于 " + MIN_STAT + "）",
    clampedFromNote: function (raw) { return "原为 " + raw + "，" + COPY.clampTail; },
    // 卡片上的大数字是**生效**增减量（最终 − 基础）；被钳位时请求值与生效值不一样，
    // 请求值只在这句小字 / title 里出现（「词条请求 -9，已钳到最低 1」）。
    clampRequestedNote: function (requested) {
      return "词条请求 " + fmtSigned(requested) + "，" + COPY.clampTail;
    },
    clampSummary: function (names) {
      return names.join("、") + " 叠加后不足 " + MIN_STAT + "，" + COPY.clampTail + COPY.clampFloor;
    },
    // 全部等级视图的钳位汇总：按行聚合（每一级各有哪些属性被钳），
    // 而不是只报当前等级那一行 —— 表里一次能看到 15 行，汇总也要对得上 15 行。
    clampSummaryByLevel: function (rows, maxLevel) {
      if (!rows.length) return "";
      var body = rows.map(function (row) {
        return row.level + " 级 " + row.names.join("、");
      }).join("；");
      return "1–" + maxLevel + " 级里有 " + rows.length + " 级叠加后不足 " + MIN_STAT + "：" +
        body + "；" + COPY.clampTail + COPY.clampFloor;
    },

    libraSwapTag: "整套替换",
    libraHint: "利普拉的交易把整套基础属性表替换掉；能否与转职遗物叠加是按参数字段结构推断的，未实测",
    libraEmptyHint: "选中后基础表整套换成对应的替换表，转职遗物仍可叠加。",
    libraBadge: function (statName) { return "利普拉：" + statName; },

    crossCheckNote: function (count, note) {
      return "与外部 wiki 有 " + count + " 格差异，本页以参数为准" + (note ? "：" + note : "");
    },
    // 做了利普拉的交易之后基础表已经整套换掉，展示的不再是该角色的原表。
    libraCrossCheckNote: "已做利普拉的交易，基础表整套替换，与外部 wiki 的角色原表差异不再适用",

    legacyMark: "*",
    legacyHeader: function (title) { return title + " " + COPY.legacyMark; },
    equipLoadHint: "本作装备没有重量，负重上限是《艾尔登法环》继承下来的遗留列，未经实测",
    equipLoadFootnote: "* 负重上限是《艾尔登法环》继承下来的遗留列：本作装备没有重量、界面也没有负重条，未经实测，仅供参考。",

    compareCaption: "对比表只用各角色的基础表：利普拉的交易不分角色（叠上去每行都一样），" +
      "转职遗物是逐角色的词条，都不进对比。",

    // 「插值与验证口径」折叠区：两端渲染同一组说明（同序、同标题、同正文），
    // 标题里的 N 因此两端必然相同 —— 之前一端数 interpolation 的字段数（17）、
    // 另一端数拼出来的条目数（10），同一份数据在两端写着不同的数字。
    // 顺序与 macOS HeroInterpolation.notes 里 append 的顺序逐条对应。
    interpolationNoteTitles: [
      "参数锚点", "基础属性插值", "基础表验证", "派生值换算", "转职遗物插值",
      "转职遗物锚点验证", "转职遗物中间等级", "取整方向", "兼容字段说明", "利普拉的交易"
    ],
    interpolationAnchorNote: function (baseAnchors, modifierAnchors) {
      return "基础属性表只有 " + baseAnchors.join(" / ") + " 级是参数原值，" +
        "转职遗物只有 " + modifierAnchors.join(" / ") + " 级是参数原值。";
    },
    // baseRounding / modifierRounding 这两条口径页面也要看得见：floor 与 trunc
    // 只在**负**增减量上差 1，正是 caveats 点名的歧义来源，数据集为此对受影响的
    // 等级另给了 deltaFloorAlt。两个字段都缺时整条说明不出现（不硬造）。
    roundingTerm: function (raw) {
      if (raw === "floor") return "向下取整（floor）";
      if (raw === "trunc") return "向零取整（trunc）";
      if (raw === "round") return "四舍五入（round）";
      return raw;
    },
    interpolationRoundingNote: function (baseRounding, modifierRounding) {
      var parts = [];
      if (baseRounding) parts.push("基础属性表按" + COPY.roundingTerm(baseRounding));
      if (modifierRounding) parts.push("转职遗物增减量按" + COPY.roundingTerm(modifierRounding));
      if (!parts.length) return "";
      var note = parts.join("，") + "。";
      if (baseRounding && modifierRounding && baseRounding !== modifierRounding) {
        note += "两种取整只在负的增减量上差 1；";
      }
      note += "换成另一种取整后结果不同的等级，数据集在 statModifiers[].levels[].deltaFloorAlt 里另给了一份备用值，" +
        "本页展示的一律是上面这一种。";
      return note;
    },

    interpolationTitle: function (count) { return "插值与验证口径（" + count + " 条）"; },
    caveatsTitle: function (count) { return "已知取舍（" + count + " 条）"; },
    sourcesTitle: function (count) { return "数据出处（" + count + " 条）与外部对照"; },
    versionLabels: ["游戏版本", "数据版本", "生成时间", "数据集结构版本", "收录"],
    contentSummary: function (heroes, maxLevel, modifiers, libra) {
      return heroes + " 位夜行者 × " + maxLevel + " 级 · " +
        modifiers + " 条转职遗物词条 · " + libra + " 笔利普拉交易";
    }
  };

  var VIEWS = [
    { key: "detail", label: COPY.viewSingle },
    { key: "compare", label: COPY.viewCompare }
  ];

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
        integer: item.integer !== false,
        // 游戏内有对应 UI 标签；负重上限没有（遗留列，列头要带 * 注记）。
        inGameLabel: item.inGameLabel !== false
      };
    });
  }

  // 数据集声明的最大等级；缺 interpolation.maxLevel 时退回各角色 levels 里的最大等级，
  // 再没有才退回常量。与 macOS HeroStatsIndex.maxLevel 同一条（那边是
  // `declared > 0 ? declared : heroes.map(\.maxLevel).max() ?? 15`）。
  // 等级选择器、全部等级表的行数、标题与钳位汇总全部走这里，页面不写死 15。
  function maxLevelOf(data) {
    var info = isObject(data) && isObject(data.interpolation) ? data.interpolation : null;
    var declared = info ? Math.round(toFiniteNumber(info.maxLevel, 0)) : 0;
    if (declared > 0) return declared;
    var fromHeroes = 0;
    heroList(data).forEach(function (hero) {
      (isObject(hero) && Array.isArray(hero.levels) ? hero.levels : []).forEach(function (row) {
        var level = Math.round(toFiniteNumber(row && row.level, 0));
        if (level > fromHeroes) fromHeroes = level;
      });
    });
    return fromHeroes > 0 ? fromHeroes : FALLBACK_MAX_LEVEL;
  }

  // 1 … maxLevelOf(data)：等级选择器与全部等级表共用一条，不可能一个到 15、
  // 另一个到 20（macOS 端 HeroStatsIndex.levelRange 同义）。
  function levelRange(data) {
    var out = [];
    for (var level = MIN_LEVEL; level <= maxLevelOf(data); level += 1) out.push(level);
    return out;
  }

  // 基础表 / 转职遗物的参数锚点等级，一律读数据集，页面不写死 1/2/12/15 与 1/12。
  function anchorLevels(data, key) {
    var info = isObject(data) && isObject(data.interpolation) ? data.interpolation : null;
    var list = info && Array.isArray(info[key]) ? info[key] : [];
    return list.map(function (value) { return Math.round(toFiniteNumber(value, 0)); })
      .filter(function (value) { return value > 0; });
  }

  function modifierAnchorLevels(data) {
    return anchorLevels(data, "modifierAnchorLevels");
  }

  function baseAnchorLevels(data) {
    return anchorLevels(data, "baseAnchorLevels");
  }

  // 派生值列头：遗留列（没有游戏内 UI 标签的那一项）带 * 注记。
  function derivedHeader(def) {
    return def && def.inGameLabel === false ? COPY.legacyHeader(def.zh) : (def ? def.zh : "");
  }

  function hasLegacyDerived(defs) {
    return defs.some(function (def) { return def.inGameLabel === false; });
  }

  // CalcCorrectGraph：分段插值。adjPt > 0 时 ratio ** adjPt[下段下标]，
  // < 0 时 1 - (1 - ratio) ** -adjPt；本数据集只有负重上限（220）不是直线。
  // 「什么算可用的图表」：至少两段，且三个数组等长。三个都要求是为了与 macOS 的
  // HeroGrowthGraph.isUsable 逐条相同 —— 之前 Windows 不看 adjPt（缺项默认成 1），
  // 同一份残缺图表一端算得出数字、另一端给破折号。
  function isUsableGraph(graph) {
    if (!isObject(graph)) return false;
    var xs = graph.stageMaxVal;
    var ys = graph.stageMaxGrowVal;
    var adj = graph.adjPt;
    return Array.isArray(xs) && Array.isArray(ys) && Array.isArray(adj) &&
      xs.length >= 2 && ys.length === xs.length && adj.length === xs.length;
  }

  function evalGrowthGraph(graph, value) {
    if (!isUsableGraph(graph)) return null;
    var xs = graph.stageMaxVal;
    var ys = graph.stageMaxGrowVal;
    var adj = graph.adjPt;
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

  // 向下取整的整数除法（JS 的 / 是浮点，| 0 是向零取整）。
  function floorDivide(numerator, denominator) {
    if (!denominator) return 0;
    return Math.floor(numerator / denominator);
  }

  // 整数求值：血量 / 专注值 / 精力所在的 100 / 101 / 104 三行端点都是整数且 adjPt 全为 1，
  // 这一段用整数精确算 floor，绕开浮点；其余情况退回 normalize + floor（抹掉 1e-9
  // 以下的尾巴再取整，否则 239.999999999 会被取成 239）。macOS 端 integerValue 同一口径。
  function evalGrowthGraphInteger(graph, value) {
    var raw = evalGrowthGraph(graph, value);
    if (raw === null) return null;
    var xs = isObject(graph) ? graph.stageMaxVal : null;
    var ys = isObject(graph) ? graph.stageMaxGrowVal : null;
    var adj = isObject(graph) && Array.isArray(graph.adjPt) ? graph.adjPt : [];
    var val = Number(value);
    if (Array.isArray(xs) && Array.isArray(ys) && val > xs[0] && val < xs[xs.length - 1]) {
      for (var i = 0; i < xs.length - 1; i += 1) {
        if (val < xs[i] || val > xs[i + 1]) continue;
        var x0 = xs[i], x1 = xs[i + 1], y0 = ys[i], y1 = ys[i + 1];
        if (toFiniteNumber(adj[i], 1) === 1 && x1 > x0 &&
          x0 === Math.round(x0) && x1 === Math.round(x1) &&
          y0 === Math.round(y0) && y1 === Math.round(y1) && val === Math.round(val)) {
          return y0 + floorDivide((y1 - y0) * (val - x0), x1 - x0);
        }
        break;
      }
    }
    return Math.floor(normalize(raw));
  }

  // 四舍五入到 1 位小数，且「远离零」（Math.round(-2.45 * 10) 会偏向 +∞，与 Swift 的
  // .rounded() 不同口径）。负重上限恒为正，这里只是把两端的边界行为钉成同一条。
  function roundOneDigit(value) {
    var num = Number(value);
    if (!isFinite(num)) return num;
    var sign = num < 0 ? -1 : 1;
    return sign * Math.round(Math.abs(num) * 10) / 10;
  }

  // 派生值重算：血量 / 专注值 / 精力向下取整，负重上限保留 1 位小数。
  // 缺 growthGraph 或缺来源属性时给 null（页面显示破折号），**不要**退回 0。
  function deriveStats(data, stats) {
    var graphs = isObject(data) && isObject(data.growthGraphs) ? data.growthGraphs : {};
    var out = {};
    derivedDefs(data).forEach(function (def) {
      var graph = graphs[String(def.graphId)];
      var source = stats ? stats[def.fromStat] : null;
      if (!isObject(graph) || source === null || source === undefined || !isFinite(Number(source))) {
        out[def.key] = null;
        return;
      }
      if (def.integer) {
        out[def.key] = evalGrowthGraphInteger(graph, source);
        return;
      }
      var raw = evalGrowthGraph(graph, source);
      out[def.key] = raw === null ? null : roundOneDigit(raw);
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

  // 等级钳位：上限一律由调用方从数据集算好传进来（maxLevelOf(data)），
  // 省略时才退回常量 —— 页面里没有一处省略。
  function clampLevel(level, maxLevel) {
    var top = Math.round(toFiniteNumber(maxLevel, FALLBACK_MAX_LEVEL));
    if (top < MIN_LEVEL) top = MIN_LEVEL;
    var num = Math.round(toFiniteNumber(level, top));
    if (num < MIN_LEVEL) return MIN_LEVEL;
    if (num > top) return top;
    return num;
  }

  function levelRow(levels, level) {
    if (!Array.isArray(levels)) return null;
    for (var i = 0; i < levels.length; i += 1) {
      if (levels[i] && Number(levels[i].level) === Number(level)) return levels[i];
    }
    return null;
  }

  // 取出 8 项属性。缺项给 null（页面显示破折号），**不要**退回 0 ——
  // 0 是真实数值，破折号才是「没有」，派生值早就是这条口径，属性也一样。
  // macOS 端对应的是「字典里干脆没有这个 key」，两端的降级行为因此一致。
  function pickStats(stats, defs) {
    var out = {};
    defs.forEach(function (def) {
      var raw = stats ? stats[def.key] : null;
      var num = Number(raw);
      out[def.key] = (raw === null || raw === undefined || raw === "" || !isFinite(num)) ? null : num;
    });
    return out;
  }

  // 转职遗物在某一级的数值来源：锚点等级取自数据集 interpolation.modifierAnchorLevels
  // （当前是 1 / 12），锚点之间是推算，最后一个锚点之后是沿用。两端同一条判定。
  function modifierLevelNote(data, level) {
    return COPY.modifierSource(clampLevel(level, maxLevelOf(data)), modifierAnchorLevels(data));
  }

  // 叠加增减量并钳位：结果小于 1 的属性一律钳到 1，钳位前的原值记在 clamped 里
  // （按 defs 顺序写入，页面的钳位汇总因此与上面的属性卡片同序）。
  // 基础值缺失（null）的那一项不编数字：最终值同样是 null（页面破折号），
  // 也不记钳位 —— macOS 端 HeroStatsMath.apply 对「base 里没有这个 key」同样跳过。
  function applyDeltas(baseStats, sum, defs) {
    var stats = {};
    var clamped = {};
    defs.forEach(function (def) {
      var base = baseStats ? baseStats[def.key] : null;
      if (base === null || base === undefined || !isFinite(Number(base))) {
        stats[def.key] = null;
        return;
      }
      var raw = Number(base) + toFiniteNumber(sum[def.key], 0);
      if (raw < MIN_STAT) {
        clamped[def.key] = raw;
        raw = MIN_STAT;
      }
      stats[def.key] = raw;
    });
    return { stats: stats, clamped: clamped };
  }

  // 卡片 / 表格里那个大数字旁边的增减量：一律是**生效值**（最终 − 基础）。
  // 被钳位时它与词条请求的增减量不一样（请求 -9、生效 -8），请求值走
  // COPY.clampRequestedNote 的小字。macOS 端 HeroStatsSnapshot.effectiveDelta
  // 是同一条公式，两端的卡片因此不会再一个写 -9、一个写 -8。
  function effectiveDelta(computed, key) {
    if (!computed || !computed.modified) return null;
    var base = computed.base.stats[key];
    var after = computed.modified.stats[key];
    if (base === null || base === undefined || after === null || after === undefined) return null;
    return Number(after) - Number(base);
  }

  // 钳位汇总用的属性中文名（按展示顺序）。
  function clampedNames(clamped, defs) {
    return defs.filter(function (def) {
      return Object.prototype.hasOwnProperty.call(clamped || {}, def.key);
    }).map(function (def) { return def.zh; });
  }

  // 全部等级表的钳位汇总：按行聚合成「等级 → 被钳属性中文名」。
  function clampedByLevel(rows, defs) {
    return (Array.isArray(rows) ? rows : []).filter(function (row) {
      return row && Object.keys(row.clamped || {}).length > 0;
    }).map(function (row) {
      return { level: row.level, names: clampedNames(row.clamped, defs) };
    });
  }

  // 页面的单一真相：给定角色 / 等级 / 利普拉交易 / 勾选的转职遗物，算出这一级要显示的一切。
  function computeLevel(data, options) {
    var opts = isObject(options) ? options : {};
    var defs = attributeDefs(data);
    var level = clampLevel(opts.level, maxLevelOf(data));
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
    result.note = modifierLevelNote(data, level);
    // 与 macOS 端 hasInferredDelta 同口径：只有「锚点之间的推算」才算推算，
    // 最后一个锚点之后是「沿用」，虽然数据集上同样标 inferred。
    result.inferred = Boolean(result.note && result.note.source === "inferred") && result.inferred;
    return result;
  }

  // 全部等级表：1 … maxLevelOf(data) 各算一行（数据集把 maxLevel 改成 20 就是 20 行，
  // 标题 / 选择器 / 钳位汇总同时跟着变）。macOS 端 snapshots() 走 levelRange，同一条。
  function computeAllLevels(data, options) {
    var opts = isObject(options) ? options : {};
    var rows = [];
    levelRange(data).forEach(function (level) {
      var row = computeLevel(data, {
        heroKey: opts.heroKey,
        level: level,
        libraKey: opts.libraKey,
        modifierIds: opts.modifierIds
      });
      if (row) rows.push(row);
    });
    return rows;
  }

  // 同级对比只看各角色的基础表：利普拉的交易 5 套表不分角色，叠上去 10 行会一模一样；
  // 转职遗物是逐角色的两条，混进来也没有可比性。口径写在表格说明里。
  function compareRows(data, level) {
    var defs = attributeDefs(data);
    var lv = clampLevel(level, maxLevelOf(data));
    return heroList(data).map(function (hero, index) {
      // 这一级没有数据的角色整行丢掉，而不是摆一行 0 —— 0 是真实数值，
      // 「没有这一级」应该从表里消失（macOS 端 comparisonRows 同一口径）。
      var row = levelRow(hero.levels, lv);
      if (!row) return null;
      var stats = pickStats(row.stats, defs);
      return {
        heroKey: hero.key,
        nameZh: hero.nameZh || hero.key,
        nameEn: hero.nameEn || "",
        order: toFiniteNumber(hero.id, index),
        level: lv,
        isAnchor: Boolean(row.isAnchor),
        stats: stats,
        // 派生值一律现算：对比表和详情页走同一条 growthGraphs 路径，两处不可能对不上。
        derived: deriveStats(data, stats)
      };
    }).filter(Boolean);
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
    if (value === null || value === undefined || !isFinite(Number(value))) return COPY.missing;
    return String(Math.round(Number(value)));
  }

  function fmtDerived(def, value) {
    if (value === null || value === undefined || !isFinite(Number(value))) return COPY.missing;
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
    // 载入数据后立刻钳进 1 … maxLevelOf(data)（见 renderData），这里只是个初值。
    level: FALLBACK_MAX_LEVEL,
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

  // 等级按钮：1 … maxLevelOf(data)，与全部等级表的行数同一条来源。
  function levelControl(data) {
    return levelRange(data).map(function (level) {
      var active = level === state.level;
      return "<button type='button' class='segment-button" + (active ? " is-active" : "") + "'" +
        " data-heroes-level='" + level + "' data-testid='heroes-level-" + level + "'" +
        " role='radio' aria-checked='" + active + "'>" + level + "</button>";
    }).join("");
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
      "data-testid='heroes-level'>" + levelControl(data) + "</div></div>" +
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

  // delta 是**生效**增减量（最终 − 基础）；clampRequested 不为空时说明这一项被钳过，
  // 词条请求的那个数只出现在下面那行小字里（两端同一条口径，见文件头注释）。
  function statCard(label, baseText, modifiedText, delta, clampRequested, hint) {
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
    if (clampRequested !== null && clampRequested !== undefined) {
      notes += "<span class='heroes-stat-note heroes-stat-note--clamp' title='" +
        esc(COPY.clampRequestedNote(clampRequested)) + "'>" +
        esc(COPY.clampRequestedNote(clampRequested)) + "</span>";
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
      // 被钳位的项：大数字旁边写生效值（-8），小字写词条请求值（-9）。
      var clampRequested = Object.prototype.hasOwnProperty.call(computed.clamped, def.key)
        ? toFiniteNumber(computed.deltas[def.key], 0) : null;
      return statCard(
        def.zh,
        fmtStat(base),
        after === null || after === undefined ? null : fmtStat(after),
        hasMods ? effectiveDelta(computed, def.key) : null,
        clampRequested,
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
        derivedHeader(def),
        fmtDerived(def, base),
        after === null || after === undefined ? null : fmtDerived(def, after),
        delta,
        null,
        def.inGameLabel === false ? COPY.equipLoadHint : "来自" + attributeTitle(attrs, def.fromStat)
      );
    }).join("");

    return "<div class='heroes-stat-grid' data-testid='heroes-stat-grid'>" + attrCards + "</div>" +
      "<h3 class='heroes-subhead'>派生值（按 CalcCorrectGraph 重算）</h3>" +
      "<div class='heroes-stat-grid heroes-stat-grid--derived' data-testid='heroes-derived-grid'>" +
      derivedCards + "</div>" +
      clampSummaryHtml(clampedNames(computed.clamped, attrs));
  }

  // 钳位汇总（单等级视图）：列出被钳的属性，按属性展示顺序。
  function clampSummaryHtml(names) {
    if (!names.length) return "";
    return "<p class='heroes-clamp-note' data-testid='heroes-clamp-note'>" +
      pill(COPY.clampRowTag, "red") + esc(COPY.clampSummary(names)) + "</p>";
  }

  function attributeTitle(defs, key) {
    for (var i = 0; i < defs.length; i += 1) {
      if (defs[i].key === key) return defs[i].zh;
    }
    return key || "";
  }

  // ------------------------------------------------------- 模板：全部等级表

  function allLevelsHtml(data, rows) {
    var attrs = attributeDefs(data);
    var derived = derivedDefs(data);
    var hasMods = rows.length > 0 && Boolean(rows[0].modified);

    // 「负重上限」是遗留列：列头带 * 注记、表下有同一条脚注。单等级卡片上有小字
    // 提示，表格里没有地方写，之前表里的数字看着就像实测值。
    var head = "<tr><th scope='col'>等级</th>" +
      attrs.map(function (def) { return "<th scope='col'>" + esc(def.zh) + "</th>"; }).join("") +
      derived.map(function (def) {
        return "<th scope='col'" + (def.inGameLabel === false ? " title='" + esc(COPY.equipLoadHint) + "'" : "") +
          ">" + esc(derivedHeader(def)) + "</th>";
      }).join("") +
      "<th scope='col'>数值来源</th></tr>";

    var body = rows.map(function (row) {
      var classes = [];
      if (row.isAnchor) classes.push("is-anchor");
      if (row.level === state.level) classes.push("is-current");
      var cells = attrs.map(function (def) {
        var value = row.modified ? row.modified.stats[def.key] : row.base.stats[def.key];
        // 与卡片同一条口径：格子里标的是生效增减量，钳位前的原值走「钳」角标的 title。
        var delta = row.modified ? toFiniteNumber(effectiveDelta(row, def.key), 0) : 0;
        var clamped = Object.prototype.hasOwnProperty.call(row.clamped, def.key);
        return "<td class='heroes-cell" + (clamped ? " is-clamped" : "") + "'>" +
          "<span class='heroes-cell-value'>" + esc(fmtStat(value)) + "</span>" +
          (delta !== 0
            ? "<span class='heroes-cell-delta " + deltaClass(delta) + "'>" + esc(fmtSigned(delta)) + "</span>"
            : "") +
          (clamped
            ? "<span class='heroes-cell-clamp' title='" +
              esc(COPY.clampedFromNote(row.clamped[def.key])) + "'>" + esc(COPY.clampCellTag) + "</span>"
            : "") +
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
      // 三个标记不是一回事：第一个说基础表这一级是不是参数原值，第二个说转职遗物的
      // 增减量从哪来，第三个说这一行有没有属性被钳到下限。
      var notes = row.isAnchor
        ? pill(COPY.baseAnchorTag, "purple")
        : pill(COPY.baseInterpolatedTag, "gray");
      if (hasMods && row.note) {
        notes += pill(row.note.label, SOURCE_PILL[row.note.source] || "gray");
      }
      if (Object.keys(row.clamped || {}).length) notes += pill(COPY.clampRowTag, "red");
      return "<tr" + (classes.length ? " class='" + classes.join(" ") + "'" : "") + ">" +
        "<th scope='row'>" + row.level + "</th>" + cells + derivedCells +
        "<td class='heroes-cell heroes-cell--notes'>" + notes + "</td></tr>";
    }).join("");

    // 钳位汇总按**行**聚合：表里一次看得到 15 行，只报当前那一行会与表里的
    // 「钳」标记对不上。
    var clampedRows = clampedByLevel(rows, attrs);
    var clampNote = clampedRows.length
      ? "<p class='heroes-clamp-note' data-testid='heroes-clamp-note'>" + pill(COPY.clampRowTag, "red") +
        esc(COPY.clampSummaryByLevel(clampedRows, maxLevelOf(data))) + "</p>"
      : "";

    return "<div class='table-wrap heroes-table-wrap'>" +
      "<table class='heroes-table heroes-level-table' data-testid='heroes-level-table'>" +
      "<thead>" + head + "</thead><tbody>" + body + "</tbody></table></div>" +
      clampNote +
      "<p class='heroes-table-caption'>" +
      esc(COPY.allLevelsCaption(baseAnchorLevels(data))) +
      "</p>" +
      (hasLegacyDerived(derived)
        ? "<p class='heroes-table-caption'>" + esc(COPY.equipLoadFootnote) + "</p>"
        : "");
  }

  // --------------------------------------------------------- 模板：转职遗物

  function relicItemsHtml(mod) {
    var items = Array.isArray(mod.relicItems) ? mod.relicItems : [];
    if (!items.length) return "<span class='heroes-mod-relic'>" + esc("遗物：" + COPY.emptyData) + "</span>";
    return "<span class='heroes-mod-relic'>遗物：" + items.map(function (item) {
      return esc(item.nameZh || item.nameEn || "未知遗物") +
        pill(item.colorZh || "未知", RELIC_COLOR_PILLS[toFiniteNumber(item.color, 4)] || "gray");
    }).join("、") + "</span>";
  }

  function modifiersHtml(data) {
    var attrs = attributeDefs(data);
    var mods = modifiersForHero(data, state.heroKey);
    if (!mods.length) {
      return "<section class='card heroes-card' data-testid='heroes-mods'>" +
        "<div class='section-heading'><div class='section-icon'>◇</div>" +
        "<div><h2>转职遗物</h2><p>" + esc(COPY.noModifierData) + "</p></div></div></section>";
    }
    var note = modifierLevelNote(data, state.level);
    var rows = mods.map(function (mod) {
      var checked = state.modifierIds.indexOf(String(mod.affixId)) !== -1;
      var modRow = levelRow(mod.levels, state.level);
      var delta = isObject(modRow) && isObject(modRow.delta) ? modRow.delta : {};
      var alt = isObject(modRow) && isObject(modRow.deltaFloorAlt) ? modRow.deltaFloorAlt : null;
      var summary = deltaSummary(delta, attrs) || COPY.noDeltaAtLevel;
      var altSummary = alt ? deltaSummary(alt, attrs) : "";
      return "<label class='heroes-mod" + (checked ? " is-checked" : "") + "'" +
        " data-testid='heroes-mod-" + esc(mod.affixId) + "'>" +
        "<input type='checkbox' data-heroes-mod='" + esc(mod.affixId) + "'" +
        (checked ? " checked" : "") + ">" +
        "<span class='heroes-mod-box' aria-hidden='true'>✓</span>" +
        "<span class='heroes-mod-copy'>" +
        "<span class='heroes-mod-name'>" + esc(mod.nameZh || mod.nameEn || "未命名词条") +
        (mod.dlcOnly ? pill(COPY.dlcOnlyTag, "blue") : "") + "</span>" +
        "<span class='heroes-mod-meta'>" + relicItemsHtml(mod) + "</span>" +
        "<span class='heroes-mod-delta'>" + esc(state.level + " 级增减：" + summary) +
        (note ? pill(note.label, SOURCE_PILL[note.source] || "gray") : "") + "</span>" +
        (altSummary
          ? "<span class='heroes-mod-alt'>" + esc(COPY.floorAlt(altSummary)) + "</span>"
          : "") +
        "</span></label>";
    }).join("");

    return "<section class='card heroes-card' data-testid='heroes-mods'>" +
      "<div class='section-heading'><div class='section-icon'>◇</div>" +
      "<div><h2>转职遗物</h2><p>" + esc(COPY.modifierSubtitle) + "</p></div></div>" +
      "<div class='heroes-mod-list'>" + rows + "</div>" +
      "<p class='data-hint'>" + esc(modifierRuleHint(data)) + "</p>" +
      "</section>";
  }

  // 「锚点只有 1 / 12 级：…」这句里的等级一律取自数据集锚点表。
  function modifierRuleHint(data) {
    var anchors = modifierAnchorLevels(data);
    if (!anchors.length) return "数据集没有给出转职遗物的参数锚点等级，本页不另立说法。";
    var last = Math.max.apply(null, anchors);
    return "锚点只有 " + anchors.join(" / ") + " 级：中间等级是线性插值后向零取整的推算值，" +
      last + " 级之后沿用 " + last + " 级锚点（沿用这一条已由多组 " + maxLevelOf(data) + " 级实测确认）。";
  }

  // --------------------------------------------------------- 模板：同级对比

  function compareHtml(data) {
    var attrs = attributeDefs(data);
    var derived = derivedDefs(data);
    var rows = sortCompareRows(compareRows(data, state.level), state.sortKey, state.sortDir);
    if (!rows.length) {
      return "<section class='card heroes-card'><div class='empty-state'>" +
        "<div class='empty-icon'>☷</div><h3>" + esc(COPY.emptyData) +
        "</h3><p>没有可对比的角色</p></div></section>";
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

    // 「负重上限」列头同样带 * 注记：两张表都是遗留列，不能只有全部等级表标出来。
    var head = "<tr>" + headCell("hero", "角色", false) +
      attrs.map(function (def) { return headCell(def.key, def.zh, true); }).join("") +
      derived.map(function (def) { return headCell(def.key, derivedHeader(def), true); }).join("") +
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
      "<p>" + rows.length + " 个夜行者在同一等级下的属性与派生值，点列头排序</p></div></div>" +
      "<div class='table-wrap heroes-table-wrap'>" +
      "<table class='heroes-table heroes-compare-table' data-testid='heroes-compare-table'>" +
      "<thead>" + head + "</thead><tbody>" + body + "</tbody></table></div>" +
      "<p class='heroes-table-caption'>" + esc(COPY.compareCaption) + "</p>" +
      (hasLegacyDerived(derived)
        ? "<p class='heroes-table-caption'>" + esc(COPY.equipLoadFootnote) + "</p>"
        : "") +
      "</section>";
  }

  // ------------------------------------------------------------- 模板：底部

  function interpolationValue(value) {
    if (typeof value === "boolean") return value ? "是" : "否";
    if (Array.isArray(value)) return value.join(" / ");
    return String(value === null || value === undefined ? "—" : value);
  }

  // 「插值与验证口径」折叠区要逐条展示的说明。
  //
  // 与 macOS 端 HeroInterpolation.notes **逐条同序同文**：标题取自
  // COPY.interpolationNoteTitles，正文要么直接是数据集的那一段文字，要么由
  // COPY 里的同一个拼装函数生成；正文为空的条目两端一起跳过，所以两端数出来的
  // 条数必然相同（之前一端数字段数 17、另一端数条目数 10，页面上写着两个数字）。
  function interpolationNotes(data) {
    var info = isObject(data) && isObject(data.interpolation) ? data.interpolation : null;
    if (!info) return [];
    var titles = COPY.interpolationNoteTitles;
    var baseAnchors = baseAnchorLevels(data);
    var modAnchors = modifierAnchorLevels(data);
    var candidates = [
      { title: titles[0], text: baseAnchors.length ? COPY.interpolationAnchorNote(baseAnchors, modAnchors) : "" },
      { title: titles[1], text: isObject(info) && info.baseRule ? String(info.baseRule) : "" },
      { title: titles[2], text: info.baseVerification ? String(info.baseVerification) : "" },
      { title: titles[3], text: info.derivedRule ? String(info.derivedRule) : "" },
      { title: titles[4], text: info.modifierRule ? String(info.modifierRule) : "" },
      { title: titles[5], text: info.modifierAnchorVerification ? String(info.modifierAnchorVerification) : "" },
      { title: titles[6], text: info.modifierInference ? String(info.modifierInference) : "" },
      {
        title: titles[7],
        text: COPY.interpolationRoundingNote(
          info.baseRounding ? String(info.baseRounding) : "",
          info.modifierRounding ? String(info.modifierRounding) : ""
        )
      },
      { title: titles[8], text: info.modifierVerifiedNote ? String(info.modifierVerifiedNote) : "" },
      { title: titles[9], text: info.libraRule ? String(info.libraRule) : "" }
    ];
    return candidates.filter(function (note) { return Boolean(note.text); });
  }

  function interpolationHtml(data) {
    var notes = interpolationNotes(data);
    if (!notes.length) return "";
    var rows = notes.map(function (note) {
      return "<div class='heroes-meta-row'><dt>" + esc(note.title) + "</dt>" +
        "<dd>" + esc(note.text) + "</dd></div>";
    }).join("");
    return "<details class='card heroes-details' data-testid='heroes-interpolation'>" +
      "<summary><span class='heroes-summary-title'>" + esc(COPY.interpolationTitle(notes.length)) + "</span>" +
      pill(notes.length + " 条", "purple") + "</summary>" +
      "<div class='heroes-details-body'><dl class='heroes-meta'>" + rows + "</dl></div></details>";
  }

  function caveatsHtml(data) {
    var list = isObject(data) && Array.isArray(data.caveats) ? data.caveats : [];
    if (!list.length) return "";
    return "<details class='card heroes-details' data-testid='heroes-caveats'>" +
      "<summary><span class='heroes-summary-title'>" + esc(COPY.caveatsTitle(list.length)) + "</span>" +
      pill(list.length + " 条", "amber") + "</summary>" +
      "<div class='heroes-details-body'><ul class='heroes-caveat-list'>" +
      list.map(function (line) {
        return "<li>" + esc(line) + "</li>";
      }).join("") + "</ul></div></details>";
  }

  // 数据版本块：5 行标签与取值口径两端逐字一致（COPY.versionLabels / contentSummary）。
  function versionRows(data) {
    var labels = COPY.versionLabels;
    return [
      { label: labels[0], value: data.gameVersion || COPY.missing },
      { label: labels[1], value: data.dataVersion || COPY.missing },
      { label: labels[2], value: data.generatedAt || COPY.missing },
      { label: labels[3], value: "schemaVersion " + interpolationValue(data.schemaVersion) },
      {
        label: labels[4],
        value: COPY.contentSummary(
          heroList(data).length,
          maxLevelOf(data),
          (isObject(data) && Array.isArray(data.statModifiers) ? data.statModifiers : []).length,
          libraList(data).length
        )
      }
    ];
  }

  function versionHtml(data) {
    var sources = isObject(data) && Array.isArray(data.sources) ? data.sources : [];
    var rows = versionRows(data).map(function (row) {
      return "<div class='heroes-meta-row'><dt>" + esc(row.label) + "</dt>" +
        "<dd>" + esc(row.value) + "</dd></div>";
    }).join("");

    var sourceList = sources.map(function (item) {
      return "<li><strong>" + esc(item.name || "未命名来源") + "</strong>" +
        (item.revision ? "<span>" + esc(item.revision) + "</span>" : "") +
        (item.note ? "<p>" + esc(item.note) + "</p>" : "") + "</li>";
    }).join("");

    // 与外部 wiki 的逐格对照结果：底部逐条列出（不分角色，和 macOS 端同一块）。
    var checks = isObject(data) && Array.isArray(data.crossChecks) ? data.crossChecks : [];
    var checkList = checks.map(function (item) {
      return "<li><strong>" + esc((item.heroNameZh || item.heroKey) + " 逐格对照") + "</strong>" +
        "<span>" + esc(item.cellsCompared + " 格，差异 " + item.mismatchCount + " 处") + "</span>" +
        (item.note ? "<p>" + esc(item.note) + "</p>" : "") + "</li>";
    }).join("");

    return "<details class='card heroes-details' data-testid='heroes-version'>" +
      "<summary><span class='heroes-summary-title'>" + esc(COPY.sourcesTitle(sources.length)) + "</span>" +
      pill(data.gameVersion || "未知版本", "green") + "</summary>" +
      "<div class='heroes-details-body'><dl class='heroes-meta'>" + rows + "</dl>" +
      (sourceList ? "<ul class='heroes-source-list'>" + sourceList + "</ul>" : "") +
      (checkList ? "<ul class='heroes-source-list'>" + checkList + "</ul>" : "") +
      "</div></details>";
  }

  function footerHtml(data) {
    return "<div class='heroes-footer'>" +
      interpolationHtml(data) + caveatsHtml(data) + versionHtml(data) + "</div>";
  }

  // -------------------------------------------------------------- 渲染主体

  // 与外部 wiki 的逐格差异提示。
  //
  // 做了利普拉的交易之后基础表已经**整套换掉**，展示的不再是该角色的原表，
  // 再提「本角色与 wiki 差 N 格」会把人带偏 —— 这时改写成一句说明。
  function crossCheckNoteText(data) {
    var cross = crossCheckFor(data, state.heroKey);
    if (!cross) return "";
    if (findLibra(data, state.libraKey)) return COPY.libraCrossCheckNote;
    return COPY.crossCheckNote(cross.mismatchCount, cross.note || "");
  }

  function statusRow(data, computed) {
    var hero = findHero(data, state.heroKey);
    var libra = findLibra(data, state.libraKey);
    var parts = [];
    parts.push(pill((hero ? hero.nameZh : "未知角色") + " · " + state.level + " 级", "purple"));
    parts.push(computed && computed.isAnchor
      ? pill(COPY.baseLevelBadge(state.level, true), "green")
      : pill(COPY.baseLevelBadge(state.level, false), "gray"));
    if (computed && computed.modified) {
      parts.push(pill(COPY.modifierCountBadge(computed.modifiers.length), "blue"));
      if (computed.note) parts.push(pill(computed.note.label, SOURCE_PILL[computed.note.source] || "gray"));
    }
    if (libra) parts.push(pill(COPY.libraBadge(libra.statNameZh || libra.nameZh), "amber"));
    var text = crossCheckNoteText(data);
    var note = text
      ? "<span class='heroes-cross-note' data-testid='heroes-cross-note'>" + esc(text) + "</span>"
      : "";
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
        "<div class='empty-icon'>☷</div><h3>" + esc(COPY.emptyData) +
        "</h3><p>这个角色没有可用的等级数据</p></div></section>";
    }
    var hero = findHero(data, state.heroKey);
    var libra = findLibra(data, state.libraKey);
    var heading = "<div class='section-heading'><div class='section-icon'>◆</div>" +
      "<div><h2>" + esc(hero ? hero.nameZh : "角色") + "　" +
      esc(state.allLevels ? "1–" + maxLevelOf(data) + " 级属性表" : state.level + " 级属性") + "</h2>" +
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
      modifiersHtml(data);
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
        ? pill(COPY.libraSwapTag, "amber") + esc(COPY.libraHint)
        : esc(COPY.libraEmptyHint);
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
        state.level = clampLevel(levelButton.getAttribute("data-heroes-level"), maxLevelOf(state.data));
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
    // 当前等级一律钳进数据集声明的范围：数据集把最大等级改小，选中的 15 级不能留在状态里。
    state.level = clampLevel(state.level, maxLevelOf(data));
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
      FALLBACK_MAX_LEVEL: FALLBACK_MAX_LEVEL,
      MIN_STAT: MIN_STAT,
      COPY: COPY,
      SOURCE_PILL: SOURCE_PILL,
      attributeDefs: attributeDefs,
      derivedDefs: derivedDefs,
      derivedHeader: derivedHeader,
      hasLegacyDerived: hasLegacyDerived,
      maxLevelOf: maxLevelOf,
      levelRange: levelRange,
      levelControl: levelControl,
      interpolationNotes: interpolationNotes,
      baseAnchorLevels: baseAnchorLevels,
      modifierAnchorLevels: modifierAnchorLevels,
      isUsableGraph: isUsableGraph,
      evalGrowthGraph: evalGrowthGraph,
      evalGrowthGraphInteger: evalGrowthGraphInteger,
      roundOneDigit: roundOneDigit,
      deriveStats: deriveStats,
      clampedNames: clampedNames,
      clampedByLevel: clampedByLevel,
      versionRows: versionRows,
      modifierRuleHint: modifierRuleHint,
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
      effectiveDelta: effectiveDelta,
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
