(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.RelicCore = factory();
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function makeMode(key, title, shortTitle, detail, slotPoolPatterns) {
    var frozenPatterns = slotPoolPatterns.map(function (pattern) {
      return Object.freeze(pattern.slice());
    });
    var slotPoolIds = [];
    frozenPatterns.forEach(function (pattern) {
      pattern.forEach(function (poolId) {
        if (!slotPoolIds.includes(poolId)) {
          slotPoolIds.push(poolId);
        }
      });
    });

    return Object.freeze({
      key: key,
      title: title,
      shortTitle: shortTitle,
      detail: detail,
      slotPoolPatterns: Object.freeze(frozenPatterns),
      slotPoolIds: Object.freeze(slotPoolIds),
    });
  }

  var MODES = Object.freeze({
    currentNormal: makeMode(
      "currentNormal",
      "普通 1.03",
      "1.03",
      "严格检查 1.03 / DLC 后普通大遗物的非零权重词条池。",
      [[310, 210, 110]]
    ),
    legacyNormal: makeMode(
      "legacyNormal",
      "普通旧池",
      "旧池",
      "严格检查 1.02 及更早的普通大遗物词条池。",
      [[300, 200, 100]]
    ),
    deepPositive: makeMode(
      "deepPositive",
      "深夜正面",
      "深夜",
      "按真实七种三槽模板预检深夜正面词条、互斥与顺序；不替代具体遗物 ID 与负面词条配对校验。",
      [
        [2000000, 2000000, 2000000],
        [2000000, 2000000, 2100000],
        [2000000, 2100000, 2100000],
        [2100000, 2100000, 2100000],
        [2000000, 2000000, 2200000],
        [2000000, 2200000, 2200000],
        [2200000, 2200000, 2200000],
      ]
    ),
    compatibilityOnly: makeMode(
      "compatibilityOnly",
      "顺序/互斥",
      "通用",
      "只检查词条是否重复、互斥，以及保存顺序；适合固定遗物或来源不明的组合。",
      []
    ),
  });

  function resolveMode(modeOrKey) {
    if (typeof modeOrKey === "string" && MODES[modeOrKey]) {
      return MODES[modeOrKey];
    }

    if (modeOrKey && typeof modeOrKey === "object") {
      if (modeOrKey.key && MODES[modeOrKey.key]) {
        return MODES[modeOrKey.key];
      }
    }

    throw new Error("未知校验模式：" + String(modeOrKey));
  }

  function foldForSearch(value) {
    var folded = String(value == null ? "" : value);

    if (typeof folded.normalize === "function") {
      folded = folded.normalize("NFKD");
    }

    return folded
      .replace(/\p{M}/gu, "")
      .replace(/ /g, "")
      .replace(/，/g, ",")
      .replace(/＋/g, "+")
      .toLowerCase();
  }

  function searchableText(affix) {
    var aliases = Array.isArray(affix && affix.aliases) ? affix.aliases : [];
    return foldForSearch([
      affix && affix.name,
      affix && affix.category,
      affix && affix.effectId,
    ].concat(aliases).join(" "));
  }

  function intersects(left, right) {
    var values = new Set(right);
    return left.some(function (value) {
      return values.has(value);
    });
  }

  function isEligible(affix, modeOrKey) {
    var mode = resolveMode(modeOrKey);
    if (mode === MODES.compatibilityOnly) {
      return !affix.isCurse;
    }

    return !affix.isCurse && intersects(affix.poolIds || [], mode.slotPoolIds);
  }

  function canonicalOrder(affixes) {
    return affixes.slice().sort(function (left, right) {
      if (left.sortId === right.sortId) {
        return left.effectId - right.effectId;
      }
      return left.sortId - right.sortId;
    });
  }

  function hasPoolAssignment(affixes, slotPools) {
    if (affixes.length !== slotPools.length) {
      return false;
    }
    if (slotPools.length === 0) {
      return true;
    }

    var used = new Array(affixes.length).fill(false);

    function assign(slotIndex) {
      if (slotIndex === slotPools.length) {
        return true;
      }

      for (var affixIndex = 0; affixIndex < affixes.length; affixIndex += 1) {
        if (
          !used[affixIndex] &&
          (affixes[affixIndex].poolIds || []).includes(slotPools[slotIndex])
        ) {
          used[affixIndex] = true;
          if (assign(slotIndex + 1)) {
            return true;
          }
          used[affixIndex] = false;
        }
      }

      return false;
    }

    return assign(0);
  }

  function hasPoolPatternAssignment(affixes, slotPoolPatterns) {
    return slotPoolPatterns.some(function (slotPools) {
      return hasPoolAssignment(affixes, slotPools);
    });
  }

  function groupBy(values, keyForValue) {
    var groups = new Map();
    values.forEach(function (value) {
      var key = keyForValue(value);
      if (!groups.has(key)) {
        groups.set(key, []);
      }
      groups.get(key).push(value);
    });
    return Array.from(groups.values());
  }

  function makeIssue(kind, title, detail, affixes) {
    return {
      kind: kind,
      title: title,
      detail: detail,
      effectIds: affixes.map(function (affix) {
        return affix.effectId;
      }),
    };
  }

  function check(affixes, modeOrKey) {
    var mode = resolveMode(modeOrKey);
    if (!Array.isArray(affixes) || affixes.length !== 3) {
      return {
        status: "incomplete",
        message: "请选择三个词条",
        orderedAffixes: [],
        issues: [],
        warnings: [],
      };
    }

    var issues = [];
    var warnings = [];

    groupBy(affixes, function (affix) {
      return affix.effectId;
    })
      .filter(function (group) {
        return group.length > 1;
      })
      .forEach(function (group) {
        issues.push(makeIssue(
          "duplicate",
          "词条重复",
          "同一个效果不能在一件遗物上出现两次：" + group[0].name,
          group
        ));
      });

    groupBy(affixes.filter(function (affix) {
      return affix.compatibilityId !== -1;
    }), function (affix) {
      return affix.compatibilityId;
    })
      .filter(function (group) {
        return group.length > 1;
      })
      .forEach(function (group) {
        issues.push(makeIssue(
          "conflict",
          "同一互斥池",
          group.map(function (affix) { return affix.name; }).join("、") + " 不能同时出现",
          group
        ));
      });

    if (
      mode !== MODES.compatibilityOnly &&
      !hasPoolPatternAssignment(affixes, mode.slotPoolPatterns)
    ) {
      var unavailable = affixes.filter(function (affix) {
        return !intersects(affix.poolIds || [], mode.slotPoolIds);
      });
      var isPatternMismatch = unavailable.length === 0;
      var affected = isPatternMismatch ? affixes : unavailable;
      issues.push(makeIssue(
        "unavailable",
        isPatternMismatch ? "不符合当前槽池模板" : "不在当前出货池",
        affected.map(function (affix) { return affix.name; }).join("、") +
          (isPatternMismatch
            ? " 无法分配到任一合法三词条槽模板"
            : " 不在当前校验模式的候选词条池"),
        affected
      ));
    }

    if (mode === MODES.deepPositive) {
      var curseBound = affixes.filter(function (affix) {
        return affix.requiresCurse;
      });
      var aOnlyCount = curseBound.length;
      var warningDetail = "A-only（仅 A 池）词条：" + aOnlyCount + " 条";
      if (aOnlyCount > 0) {
        warningDetail += "，至少需要 " + aOnlyCount + " 条对应负面词条";
      }
      warningDetail += "；当前仅预检三条正面效果，完整深夜遗物仍需结合具体遗物 ID，校验全部负面词条及其正负配对";
      warnings.push(makeIssue(
        "cursePairing",
        "深夜模式仅作预检",
        warningDetail,
        curseBound
      ));
    }

    var ordered = canonicalOrder(affixes);
    if (issues.length > 0) {
      return {
        status: "invalid",
        message: "该三词条组合不合法",
        orderedAffixes: ordered,
        issues: issues,
        warnings: warnings,
      };
    }

    var isOrdered = ordered.every(function (affix, index) {
      return affix.effectId === affixes[index].effectId;
    });
    if (!isOrdered) {
      return {
        status: "wrongOrder",
        message: "组合本身可成立，但词条顺序错误",
        orderedAffixes: ordered,
        issues: [],
        warnings: warnings,
      };
    }

    return {
      status: "valid",
      message: mode === MODES.deepPositive
        ? "正面词条预检通过；不等同于完整深夜遗物合法"
        : "该三词条组合合法，顺序正确",
      orderedAffixes: ordered,
      issues: [],
      warnings: warnings,
    };
  }

  function shuffled(values) {
    var result = values.slice();
    for (var index = result.length - 1; index > 0; index -= 1) {
      var other = Math.floor(Math.random() * (index + 1));
      var value = result[index];
      result[index] = result[other];
      result[other] = value;
    }
    return result;
  }

  function randomCombination(catalogOrAffixes, modeOrKey) {
    var catalog = Array.isArray(catalogOrAffixes)
      ? catalogOrAffixes
      : catalogOrAffixes && catalogOrAffixes.affixes;
    if (!Array.isArray(catalog)) {
      return null;
    }

    var candidates = catalog.filter(function (affix) {
      return isEligible(affix, modeOrKey);
    });
    if (candidates.length < 3) {
      return null;
    }

    for (var attempt = 0; attempt < 6000; attempt += 1) {
      var sample = shuffled(candidates).slice(0, 3);
      var ordered = canonicalOrder(sample);
      if (check(ordered, modeOrKey).status === "valid") {
        return ordered;
      }
    }
    return null;
  }

  function validateCatalog(catalog) {
    if (!catalog || typeof catalog !== "object" || !Array.isArray(catalog.affixes)) {
      throw new Error("无法读取词条库文件");
    }
    if (catalog.schemaVersion !== 1) {
      throw new Error("不支持的词条库版本：" + catalog.schemaVersion);
    }

    var counts = new Map();
    catalog.affixes.forEach(function (affix) {
      counts.set(affix.effectId, (counts.get(affix.effectId) || 0) + 1);
    });
    var duplicates = Array.from(counts.entries())
      .filter(function (entry) { return entry[1] > 1; })
      .map(function (entry) { return entry[0]; })
      .sort(function (left, right) { return left - right; });
    if (duplicates.length > 0) {
      throw new Error("词条库包含重复 ID：" + duplicates.join(", "));
    }

    var positiveCount = catalog.affixes.filter(function (affix) {
      return !affix.isCurse;
    }).length;
    if (positiveCount < 3) {
      throw new Error("词条库中的有效正面词条不足三个");
    }

    var sourceIsValid = function (source) {
      return source &&
        typeof source === "object" &&
        !Array.isArray(source) &&
        typeof source.name === "string" &&
        typeof source.url === "string" &&
        typeof source.revision === "string" &&
        typeof source.license === "string";
    };
    var affixIsValid = function (affix) {
      return affix &&
        typeof affix === "object" &&
        !Array.isArray(affix) &&
        Number.isSafeInteger(affix.effectId) &&
        typeof affix.name === "string" &&
        Array.isArray(affix.aliases) &&
        affix.aliases.every(function (alias) { return typeof alias === "string"; }) &&
        typeof affix.category === "string" &&
        typeof affix.explanation === "string" &&
        typeof affix.superposability === "string" &&
        Number.isSafeInteger(affix.compatibilityId) &&
        Number.isSafeInteger(affix.sortId) &&
        Array.isArray(affix.poolIds) &&
        affix.poolIds.every(Number.isSafeInteger) &&
        typeof affix.isCurse === "boolean" &&
        typeof affix.requiresCurse === "boolean" &&
        (affix.popularity == null || Number.isSafeInteger(affix.popularity)) &&
        typeof affix.source === "string";
    };
    var catalogIsStructurallyValid =
      typeof catalog.gameVersion === "string" &&
      typeof catalog.dataVersion === "string" &&
      typeof catalog.generatedAt === "string" &&
      Array.isArray(catalog.sources) &&
      catalog.sources.every(sourceIsValid) &&
      catalog.affixes.every(affixIsValid);

    if (!catalogIsStructurallyValid) {
      throw new Error("无法读取词条库文件");
    }

    return catalog;
  }

  // ---- 存档检查：遗物审计（契约 §3/§4，与 macOS 端 RelicAudit 严格同步） ----

  var RELIC_COLOR_LABELS = Object.freeze(["红", "蓝", "黄", "绿", "白"]);
  var DEEP_SLOT_POOL_IDS = Object.freeze([2000000, 2100000, 2200000]);
  var SLOT_PERMUTATIONS = Object.freeze([
    [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0],
  ]);
  var PAIR_ISSUE_ORDER = Object.freeze([
    "effectUnexpected", "effectMissing", "slotMismatch",
    "curseUnexpected", "curseMissing", "curseMismatch",
  ]);
  var DEEP_CURSE_POOL_ID = 3000000;
  var EMPTY_POOL = new Set();

  function normalizeEffectId(value) {
    return value == null || value === 0 || value === -1 || value === 0xFFFFFFFF ? -1 : value;
  }

  function normalizeTriple(values) {
    var result = [-1, -1, -1];
    for (var index = 0; index < 3; index += 1) {
      result[index] = normalizeEffectId(Array.isArray(values) ? values[index] : -1);
    }
    return result;
  }

  function buildRelicIndex(catalog, relicData) {
    if (!relicData || typeof relicData !== "object" || !Array.isArray(relicData.relics)) {
      throw new Error("无法读取遗物数据文件");
    }
    if (relicData.relicsSchemaVersion !== 1) {
      throw new Error("不支持的遗物数据版本：" + relicData.relicsSchemaVersion);
    }

    var affixIndex = new Map();
    var affixes = catalog && Array.isArray(catalog.affixes) ? catalog.affixes : [];
    affixes.forEach(function (affix) { affixIndex.set(affix.effectId, affix); });
    (Array.isArray(relicData.extraAffixes) ? relicData.extraAffixes : []).forEach(function (extra) {
      if (affixIndex.has(extra.effectId)) return;
      affixIndex.set(extra.effectId, {
        effectId: extra.effectId,
        name: extra.name,
        sortId: extra.sortId,
        compatibilityId: extra.compatibilityId,
        isCurse: false,
        requiresCurse: false,
        poolIds: [],
      });
    });

    // 防御：槽池模板缺失/畸形时归一为无槽（-1），避免坏数据让整次扫描抛异常
    function normalizeSlotTriple(values) {
      var result = [-1, -1, -1];
      for (var index = 0; index < 3; index += 1) {
        var value = Array.isArray(values) ? values[index] : -1;
        result[index] = typeof value === "number" && isFinite(value) ? value : -1;
      }
      return result;
    }
    var relicsById = new Map();
    relicData.relics.forEach(function (relic) {
      if (!relic || typeof relic.id !== "number") return;
      relicsById.set(relic.id, {
        id: relic.id,
        name: typeof relic.name === "string" ? relic.name : "",
        color: relic.color,
        deep: relic.deep === true,
        slots: normalizeSlotTriple(relic.slots),
        curseSlots: normalizeSlotTriple(relic.curseSlots),
      });
    });

    var poolSets = new Map();
    Object.keys(relicData.pools || {}).forEach(function (key) {
      poolSets.set(Number(key), new Set(relicData.pools[key]));
    });

    var deepPoolUnion = new Set();
    DEEP_SLOT_POOL_IDS.forEach(function (poolId) {
      (poolSets.get(poolId) || EMPTY_POOL).forEach(function (effectId) { deepPoolUnion.add(effectId); });
    });

    return Object.freeze({
      relicsById: relicsById,
      poolSets: poolSets,
      deepPoolUnion: deepPoolUnion,
      affixIndex: affixIndex,
      relicData: relicData,
    });
  }

  function auditIssue(kind, title, detail, effectIds) {
    return { kind: kind, title: title, detail: detail, effectIds: effectIds.slice() };
  }

  function describeAffix(ctx, effectId) {
    var affix = ctx.affixIndex.get(effectId);
    return affix && affix.name ? affix.name : "词条 #" + effectId;
  }

  function rollablePool(ctx, poolId) {
    return ctx.poolSets.get(poolId) || EMPTY_POOL;
  }

  // 非深夜遗物：对 (effect, curse) 三对做 6 种排列，返回问题最少的排列
  // （并列取列表序靠前者）。深夜遗物不走此路径（见 auditDeepRelic）。
  function evaluatePairing(ctx, meta, effects, curses) {
    var best = null;
    SLOT_PERMUTATIONS.forEach(function (permutation) {
      var problems = [];
      for (var pair = 0; pair < 3; pair += 1) {
        var slot = permutation[pair];
        var slotPool = meta.slots[slot];
        var cursePool = meta.curseSlots[slot];
        var effect = effects[pair];
        var curse = curses[pair];
        if (slotPool === -1 && effect !== -1) {
          problems.push({ kind: "effectUnexpected", pair: pair, effectId: effect });
        }
        if (slotPool !== -1 && effect === -1) {
          problems.push({ kind: "effectMissing", pair: pair, effectId: -1 });
        }
        if (slotPool !== -1 && effect !== -1 && !rollablePool(ctx, slotPool).has(effect)) {
          problems.push({ kind: "slotMismatch", pair: pair, effectId: effect });
        }
        if (cursePool === -1 && curse !== -1) {
          problems.push({ kind: "curseUnexpected", pair: pair, effectId: curse });
        }
        if (cursePool !== -1 && curse === -1) {
          problems.push({ kind: "curseMissing", pair: pair, effectId: effect });
        }
        if (cursePool !== -1 && curse !== -1 && !rollablePool(ctx, cursePool).has(curse)) {
          problems.push({ kind: "curseMismatch", pair: pair, effectId: curse });
        }
      }
      if (best === null || problems.length < best.length) {
        best = problems;
      }
    });
    return { passed: best.length === 0, problems: best };
  }

  // 深夜遗物：按行配对模型。真实存档实证（759 件深夜遗物零违反）：
  // 第 i 行正面词条为「需诅咒」词条 ⇔ 第 i 行携带负面词条；正面词条属于
  // 深夜 A/B/C 池并集；词条数等于该遗物的槽数。参数表中深夜遗物行的
  // 槽池排列（如 1.03 深夜遗物普遍记录为 CCC 且无诅咒槽）与游戏实际
  // 生成不符，不能作为校验依据。
  function auditDeepRelic(ctx, meta, effects, curses, issues) {
    var slotCount = meta.slots.filter(function (pool) { return pool !== -1; }).length;
    var effectCount = effects.filter(function (effectId) { return effectId !== -1; }).length;
    if (effectCount < slotCount) {
      issues.push(auditIssue("effectMissing", "正面词条数量不足",
        "该遗物应有 " + slotCount + " 条正面词条，实有 " + effectCount + " 条", []));
    } else if (effectCount > slotCount) {
      issues.push(auditIssue("effectUnexpected", "正面词条数量超出",
        "该遗物应有 " + slotCount + " 条正面词条，实有 " + effectCount + " 条", []));
    }
    var row;
    for (row = 0; row < 3; row += 1) {
      var effectId = effects[row];
      if (effectId !== -1 && !ctx.deepPoolUnion.has(effectId)) {
        issues.push(auditIssue("slotMismatch", "正面词条不在深夜词条池",
          "第 " + (row + 1) + " 行的正面词条不在深夜词条池中：" + describeAffix(ctx, effectId), [effectId]));
      }
    }
    for (row = 0; row < 3; row += 1) {
      var effect = effects[row];
      var curse = curses[row];
      var affix = effect === -1 ? null : ctx.affixIndex.get(effect);
      var needsCurse = Boolean(affix && affix.requiresCurse);
      if (needsCurse && curse === -1) {
        issues.push(auditIssue("curseMissing", "需诅咒的词条缺少负面词条",
          "第 " + (row + 1) + " 行的正面词条需要配对负面词条：" + describeAffix(ctx, effect), [effect]));
      } else if (!needsCurse && curse !== -1) {
        issues.push(auditIssue("curseUnexpected", "多余的负面词条",
          "第 " + (row + 1) + " 行的正面词条不需要负面词条，却携带负面词条：" + describeAffix(ctx, curse), [curse]));
      }
    }
    for (row = 0; row < 3; row += 1) {
      var curseId = curses[row];
      if (curseId !== -1 && !rollablePool(ctx, DEEP_CURSE_POOL_ID).has(curseId)) {
        issues.push(auditIssue("curseMismatch", "负面词条不在诅咒池",
          "第 " + (row + 1) + " 行的负面词条不在诅咒池：" + describeAffix(ctx, curseId), [curseId]));
      }
    }
  }

  function pairIssue(ctx, problem) {
    var line = problem.pair + 1;
    var ids = problem.effectId === -1 ? [] : [problem.effectId];
    switch (problem.kind) {
      case "effectUnexpected":
        return auditIssue("effectUnexpected", "多余的正面词条",
          "第 " + line + " 行的正面词条超出该遗物的词条槽：" + describeAffix(ctx, problem.effectId), ids);
      case "effectMissing":
        return auditIssue("effectMissing", "正面词条缺失",
          "第 " + line + " 行缺少正面词条，该遗物的词条槽不允许为空", ids);
      case "slotMismatch":
        return auditIssue("slotMismatch", "正面词条不在对应槽池",
          "第 " + line + " 行的正面词条不在对应槽的可掉落池：" + describeAffix(ctx, problem.effectId), ids);
      case "curseUnexpected":
        return auditIssue("curseUnexpected", "多余的负面词条",
          "第 " + line + " 行不应携带负面词条：" + describeAffix(ctx, problem.effectId), ids);
      case "curseMissing":
        return auditIssue("curseMissing", "需诅咒的词条缺少负面词条",
          "第 " + line + " 行的诅咒槽不允许为空" +
          (problem.effectId === -1 ? "" : "：" + describeAffix(ctx, problem.effectId)), ids);
      default:
        return auditIssue("curseMismatch", "负面词条不在诅咒池",
          "第 " + line + " 行的负面词条不在诅咒池：" + describeAffix(ctx, problem.effectId), ids);
    }
  }

  // 契约 §4：单件遗物审计。输入 {itemId, effects[3], curses[3]}（-1 为空），输出 status/issues/warnings/orderedEffects
  function auditRelic(relic, ctx) {
    var issues = [];
    var warnings = [];
    var orderedEffects = null;
    var itemId = relic && Number.isSafeInteger(relic.itemId) ? relic.itemId : -1;
    var effects = normalizeTriple(relic && relic.effects);
    var curses = normalizeTriple(relic && relic.curses);

    function finish() {
      return {
        status: issues.length > 0 ? "invalid" : "valid",
        issues: issues,
        warnings: warnings,
        orderedEffects: orderedEffects,
      };
    }

    // §4.1 未知遗物 ID：无法继续，跳过 2-8
    var meta = ctx.relicsById.get(itemId);
    if (!meta) {
      issues.push(auditIssue("unknownItem", "未知遗物 ID",
        "遗物 ID " + itemId + " 不在内置遗物表中，无法核对词条槽", []));
      return finish();
    }

    // §4.2 / §4.3 ID 区段检查（命中后继续评估）
    if (itemId >= 20000 && itemId <= 30035) {
      issues.push(auditIssue("illegalRange", "处于作弊器常用 ID 区段",
        "遗物 ID " + itemId + " 落在 20000-30035 区段，正常游戏不会产出", []));
    }
    if (itemId < 100 || itemId > 2013322) {
      issues.push(auditIssue("outOfRange", "超出合法遗物 ID 范围",
        "遗物 ID " + itemId + " 超出 100-2013322 的合法区间", []));
    }

    // §4.4 未知词条 ID：加入后跳过 5-8
    var unknownIds = [];
    effects.concat(curses).forEach(function (effectId) {
      if (effectId !== -1 && !ctx.affixIndex.has(effectId) && unknownIds.indexOf(effectId) === -1) {
        unknownIds.push(effectId);
      }
    });
    if (unknownIds.length > 0) {
      issues.push(auditIssue("unknownEffect", "存在未知词条 ID",
        "以下词条 ID 不在词条索引中：" + unknownIds.join("、"), unknownIds));
      return finish();
    }

    var presentIds = effects.concat(curses).filter(function (effectId) { return effectId !== -1; });

    // §4.5 词条重复
    var idCounts = new Map();
    presentIds.forEach(function (effectId) { idCounts.set(effectId, (idCounts.get(effectId) || 0) + 1); });
    var duplicated = [];
    idCounts.forEach(function (count, effectId) { if (count > 1) duplicated.push(effectId); });
    if (duplicated.length > 0) {
      issues.push(auditIssue("duplicate", "词条重复",
        "同一词条在一件遗物上重复出现：" + duplicated.map(function (effectId) {
          return describeAffix(ctx, effectId);
        }).join("、"), duplicated));
    }

    // §4.6 互斥词条（compatibilityId == -1 豁免）
    var compatibilityGroups = new Map();
    presentIds.forEach(function (effectId) {
      var affix = ctx.affixIndex.get(effectId);
      if (affix.compatibilityId === -1) return;
      if (!compatibilityGroups.has(affix.compatibilityId)) {
        compatibilityGroups.set(affix.compatibilityId, []);
      }
      compatibilityGroups.get(affix.compatibilityId).push(effectId);
    });
    // 与 Swift 端一致：按出现顺序去重列出冲突词条
    var conflictGroupIds = new Set();
    compatibilityGroups.forEach(function (effectIds, groupId) {
      if (effectIds.length > 1) conflictGroupIds.add(groupId);
    });
    var conflicting = [];
    var seenConflicting = new Set();
    presentIds.forEach(function (effectId) {
      var affix = ctx.affixIndex.get(effectId);
      if (affix.compatibilityId === -1 || !conflictGroupIds.has(affix.compatibilityId)) return;
      if (seenConflicting.has(effectId)) return;
      seenConflicting.add(effectId);
      conflicting.push(effectId);
    });
    if (conflicting.length > 0) {
      issues.push(auditIssue("conflict", "互斥词条同时出现",
        "同一互斥池的词条不能同时出现：" + conflicting.map(function (effectId) {
          return describeAffix(ctx, effectId);
        }).join("、"), conflicting));
    }

    // 槽池与诅咒配对：深夜遗物按行配对；非深夜遗物（含唯一遗物——其槽池
    // 为单词条固定池，参数表经真实存档交叉验证是准确的）按参数行模板做
    // 排列匹配，不符即非法。
    if (meta.deep) {
      auditDeepRelic(ctx, meta, effects, curses, issues);
    } else {
      var pairing = evaluatePairing(ctx, meta, effects, curses);
      if (!pairing.passed) {
        pairing.problems.slice().sort(function (left, right) {
          var kindDelta = PAIR_ISSUE_ORDER.indexOf(left.kind) - PAIR_ISSUE_ORDER.indexOf(right.kind);
          return kindDelta !== 0 ? kindDelta : left.pair - right.pair;
        }).forEach(function (problem) {
          issues.push(pairIssue(ctx, problem));
        });
      }
    }

    // §4.10 保存顺序（仅当 issues 为空时评估）
    if (issues.length === 0) {
      var canonical = canonicalOrder(effects.filter(function (effectId) { return effectId !== -1; })
        .map(function (effectId) { return ctx.affixIndex.get(effectId); }))
        .map(function (affix) { return affix.effectId; });
      while (canonical.length < 3) canonical.push(-1);
      var misordered = effects.some(function (effectId, index) { return effectId !== canonical[index]; });
      if (misordered) {
        orderedEffects = canonical;
        issues.push(auditIssue("wrongOrder", "保存顺序错误",
          "词条应按 (sortId, effectId) 升序保存、空槽排最后",
          effects.filter(function (effectId) { return effectId !== -1; })));
      }
    }

    return finish();
  }

  function isUniqueRelicId(itemId) {
    return (itemId >= 1000 && itemId <= 2100) || (itemId >= 10000 && itemId <= 19999);
  }

  // 契约 §4 整体检查：同角色内唯一遗物重复持有；除第 1 件 status 为 valid 者外逐件追加 issue（原地修改）
  function applyUniqueDuplicates(audits, relics) {
    var groups = new Map();
    relics.forEach(function (relic, index) {
      var itemId = relic && relic.itemId;
      if (!Number.isSafeInteger(itemId) || !isUniqueRelicId(itemId)) return;
      if (!groups.has(itemId)) groups.set(itemId, []);
      groups.get(itemId).push(index);
    });
    groups.forEach(function (indexes, itemId) {
      if (indexes.length < 2) return;
      var kept = -1;
      indexes.some(function (index) {
        if (audits[index].status === "valid") {
          kept = index;
          return true;
        }
        return false;
      });
      indexes.forEach(function (index) {
        if (index === kept) return;
        audits[index].issues.push(auditIssue("uniqueDuplicate", "唯一遗物重复持有",
          "同一角色持有多件唯一遗物 #" + itemId + "，正常游戏至多一件", []));
        audits[index].status = "invalid";
      });
    });
    return audits;
  }

  // 契约 §3：遗物种类标签（按优先级）
  function relicKindLabel(itemId, meta) {
    if (meta && meta.deep === true) return "深夜遗物";
    if (isUniqueRelicId(itemId)) return "唯一遗物";
    if (itemId >= 100 && itemId <= 199) return "商店遗物（旧版）";
    if (itemId >= 200 && itemId <= 299) return "商店遗物";
    if (itemId >= 1000000 && itemId <= 1009999) return "对局奖励";
    return "遗物";
  }

  // 契约 §3：颜色标签（0红 1蓝 2黄 3绿 4白）
  function relicColorLabel(color) {
    return RELIC_COLOR_LABELS[color] || "未知";
  }

  return Object.freeze({
    MODES: MODES,
    foldForSearch: foldForSearch,
    searchableText: searchableText,
    isEligible: isEligible,
    canonicalOrder: canonicalOrder,
    hasPoolAssignment: hasPoolAssignment,
    hasPoolPatternAssignment: hasPoolPatternAssignment,
    check: check,
    randomCombination: randomCombination,
    validateCatalog: validateCatalog,
    buildRelicIndex: buildRelicIndex,
    auditRelic: auditRelic,
    applyUniqueDuplicates: applyUniqueDuplicates,
    relicKindLabel: relicKindLabel,
    relicColorLabel: relicColorLabel,
  });
});
