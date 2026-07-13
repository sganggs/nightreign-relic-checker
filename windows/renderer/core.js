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
  });
});
