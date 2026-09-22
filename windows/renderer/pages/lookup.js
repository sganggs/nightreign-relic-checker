// 词条反查页。页面模块契约见 renderer/pages/README.md。
// 本文件由「词条反查」功能开发者独占：只改这里与 pages/lookup.css。
// 只使用现有数据：ctx.catalog（词条库）与遗物物品表（ctx.relicData，
// 用户没进过存档页时为 null，本页自行通过 window.nightreign.loadRelicData() 桥载入并缓存）。
//
// 文件同时是 node 可 require 的纯逻辑模块（供 tests/lookup_index.test.mjs 使用）：
// 顶层不碰 document / window，渲染代码全部在 install(root) 之后才执行。
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else if (root) {
    api.install(root);
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  var PAGE_KEY = "lookup";
  var ROW_LIMIT = 200;      // 遗物出处表每页最多 200 行
  var SEARCH_LIMIT = 200;   // 搜索结果最多 200 行
  var SLOT_PREVIEW = 10;    // 「按遗物查」每个槽位预览的词条数
  var PEER_PREVIEW = 24;    // 互斥组最多直接列出的词条数

  var DEEP_POOL_IDS = [2000000, 2100000, 2200000];
  var DEEP_POOL_LABELS = { 2000000: "A 池", 2100000: "B 池", 2200000: "C 池" };
  var DEEP_CURSE_POOL_ID = 3000000;
  var COLOR_PILLS = ["red", "blue", "amber", "green", "gray"];
  var SLOT_LABELS = ["第 1 槽", "第 2 槽", "第 3 槽"];

  // ==================================================================
  // 纯逻辑（不依赖 DOM，node 下可单独测试）
  // ==================================================================

  // core.js 目前没有导出 isUniqueRelicId，这里保留同口径的本地实现做兜底。
  function localIsUniqueRelicId(itemId) {
    return (itemId >= 1000 && itemId <= 2100) || (itemId >= 10000 && itemId <= 19999);
  }

  function isUniqueRelicId(Core, itemId) {
    var fromCore = Core && Core.isUniqueRelicId;
    return typeof fromCore === "function" ? fromCore(itemId) : localIsUniqueRelicId(itemId);
  }

  function relicDisplayName(meta) {
    if (!meta) return "未知遗物";
    return meta.name || "未命名遗物 #" + meta.id;
  }

  function poolSize(index, poolId) {
    var members = index.base.poolSets.get(poolId);
    return members ? members.size : 0;
  }

  function poolHas(index, poolId, effectId) {
    var members = index.base.poolSets.get(poolId);
    return Boolean(members && members.has(effectId));
  }

  function affixOf(index, effectId) {
    return index.base.affixIndex.get(effectId) || null;
  }

  function affixName(index, effectId) {
    var affix = affixOf(index, effectId);
    return affix && affix.name ? affix.name : "词条 #" + effectId;
  }

  // Core.buildRelicIndex 会把 relics.json 的 extraAffixes（角色专属词条等）也并进
  // affixIndex，所以池成员里有一部分 effectId 词条库（catalog.affixes）里没有。
  // 这些词条查不到分类 / 说明 / 互斥组，不能作为「按词条查」的跳转目标。
  function isCatalogAffix(index, effectId) {
    return Boolean(index && index.catalogIds && index.catalogIds.has(effectId));
  }

  function affixEntry(index, effectId) {
    return {
      effectId: effectId,
      name: affixName(index, effectId),
      inCatalog: isCatalogAffix(index, effectId)
    };
  }

  function sortAffixes(Core, affixes) {
    return Core.canonicalOrder(affixes.filter(Boolean));
  }

  // 词条 → 池 → 遗物的反向索引，一次性建立并缓存（约 1.3 万条池成员关系）。
  // relicData 缺失 / 版本不符时 Core.buildRelicIndex 会抛错，由调用方降级处理。
  function buildLookupIndex(Core, catalog, relicData) {
    var base = Core.buildRelicIndex(catalog, relicData);

    var poolSlots = new Map();   // poolId → [{ relicId, slot, kind }]
    var effectPools = new Map(); // effectId → [poolId]
    var relics = [];

    function addSlot(poolId, relicId, slot, kind) {
      if (poolId === -1) return;
      var list = poolSlots.get(poolId);
      if (!list) { list = []; poolSlots.set(poolId, list); }
      list.push({ relicId: relicId, slot: slot, kind: kind });
    }

    base.relicsById.forEach(function (meta) {
      relics.push(meta);
      for (var slot = 0; slot < 3; slot += 1) {
        addSlot(meta.slots[slot], meta.id, slot, "slot");
        addSlot(meta.curseSlots[slot], meta.id, slot, "curse");
      }
    });
    relics.sort(function (left, right) { return left.id - right.id; });

    base.poolSets.forEach(function (members, poolId) {
      members.forEach(function (effectId) {
        var list = effectPools.get(effectId);
        if (!list) { list = []; effectPools.set(effectId, list); }
        list.push(poolId);
      });
    });

    var relicRows = relics.map(function (meta) {
      var kindLabel = Core.relicKindLabel(meta.id, meta);
      return {
        id: meta.id,
        meta: meta,
        name: relicDisplayName(meta),
        named: Boolean(meta.name),
        kindLabel: kindLabel,
        colorLabel: Core.relicColorLabel(meta.color),
        unique: isUniqueRelicId(Core, meta.id),
        searchText: Core.foldForSearch([meta.name, meta.id, kindLabel].join(" "))
      };
    });

    var relicRowsById = new Map();
    relicRows.forEach(function (row) { relicRowsById.set(row.id, row); });

    // 词条库自己的 effectId 集合：用来区分「池成员里来自 extraAffixes 的词条」。
    var catalogIds = new Set();
    (catalog && Array.isArray(catalog.affixes) ? catalog.affixes : []).forEach(function (affix) {
      catalogIds.add(affix.effectId);
    });

    return Object.freeze({
      base: base,
      poolSlots: poolSlots,
      effectPools: effectPools,
      relicRows: relicRows,
      relicRowsById: relicRowsById,
      catalogIds: catalogIds,
      sourceCache: new Map()
    });
  }

  // 词条搜索：名称 / 别名 / 分类 / effectId（foldForSearch 归一化）。
  function searchAffixes(Core, catalog, query, options) {
    var settings = options || {};
    var limit = settings.limit || SEARCH_LIMIT;
    var includeCurse = settings.includeCurse !== false;
    var affixes = catalog && Array.isArray(catalog.affixes) ? catalog.affixes : [];
    var needle = Core.foldForSearch(query || "");

    var matched = affixes.filter(function (affix) {
      if (!includeCurse && affix.isCurse) return false;
      return !needle || Core.searchableText(affix).indexOf(needle) !== -1;
    }).sort(function (left, right) {
      return left.sortId - right.sortId || left.effectId - right.effectId;
    });

    return {
      rows: matched.slice(0, limit),
      total: matched.length,
      truncated: matched.length > limit
    };
  }

  // 遗物搜索：名称 / ID / 种类。
  function searchRelics(Core, index, query, options) {
    var settings = options || {};
    var limit = settings.limit || SEARCH_LIMIT;
    var includeUnnamed = settings.includeUnnamed === true;
    var needle = Core.foldForSearch(query || "");

    var matched = index.relicRows.filter(function (row) {
      if (!includeUnnamed && !row.named) return false;
      return !needle || row.searchText.indexOf(needle) !== -1;
    });

    return {
      rows: matched.slice(0, limit),
      total: matched.length,
      truncated: matched.length > limit
    };
  }

  // 同 compatibilityId 的其他词条（同组不能同时出现）；compatibilityId 为 -1 时无互斥组。
  function compatibilityPeers(Core, catalog, affix) {
    if (!affix || affix.compatibilityId === -1 || affix.compatibilityId == null) return [];
    var affixes = catalog && Array.isArray(catalog.affixes) ? catalog.affixes : [];
    return sortAffixes(Core, affixes.filter(function (other) {
      return other.compatibilityId === affix.compatibilityId && other.effectId !== affix.effectId;
    }));
  }

  // a) 普通随机遗物：按各校验口径的槽位池模式判断能否掉落、落在哪几个槽的池子里。
  // 「顺序/互斥」口径不限定池（slotPoolPatterns 为空），不算掉落来源，故排除。
  function modeSources(Core, index, effectId) {
    return Object.keys(Core.MODES).map(function (key) {
      var mode = Core.MODES[key];
      if (!mode.slotPoolPatterns.length) return null;

      var seen = Object.create(null);
      var slots = [];
      mode.slotPoolPatterns.forEach(function (pattern) {
        pattern.forEach(function (poolId, slot) {
          var cacheKey = slot + ":" + poolId;
          if (seen[cacheKey]) return;
          seen[cacheKey] = true;
          slots.push({
            slot: slot,
            poolId: poolId,
            size: poolSize(index, poolId),
            member: poolHas(index, poolId, effectId)
          });
        });
      });
      slots.sort(function (left, right) { return left.slot - right.slot || left.poolId - right.poolId; });

      var pools = mode.slotPoolIds.map(function (poolId) {
        return {
          poolId: poolId,
          label: DEEP_POOL_LABELS[poolId] || ("池 " + poolId),
          size: poolSize(index, poolId),
          member: poolHas(index, poolId, effectId)
        };
      });

      return {
        key: key,
        title: mode.title,
        shortTitle: mode.shortTitle,
        detail: mode.detail,
        multiPattern: mode.slotPoolPatterns.length > 1,
        available: slots.some(function (entry) { return entry.member; }),
        slots: slots,
        pools: pools
      };
    }).filter(Boolean);
  }

  // b) 深夜遗物：A/B/C 三池归属；A 池词条需要在同一行搭配诅咒池里的负面词条。
  function deepSources(Core, index, effectId) {
    var affix = affixOf(index, effectId);
    var pools = DEEP_POOL_IDS.map(function (poolId) {
      return {
        poolId: poolId,
        label: DEEP_POOL_LABELS[poolId],
        size: poolSize(index, poolId),
        member: poolHas(index, poolId, effectId)
      };
    });
    var curseMembers = index.base.poolSets.get(DEEP_CURSE_POOL_ID);
    var curses = sortAffixes(Core, Array.from(curseMembers || []).map(function (id) {
      return affixOf(index, id);
    }));

    return {
      pools: pools,
      inAny: pools.some(function (entry) { return entry.member; }),
      requiresCurse: Boolean(affix && affix.requiresCurse),
      isCurse: Boolean(affix && affix.isCurse),
      cursePoolId: DEEP_CURSE_POOL_ID,
      curses: curses
    };
  }

  // c) 遍历遗物表：列出所有 slots / curseSlots 指向的池子里包含该词条的遗物。
  // 池子只有一个成员即「固定词条」，否则是「随机池可出」。结果按 effectId 缓存。
  function relicSourcesFor(index, effectId) {
    if (index.sourceCache.has(effectId)) return index.sourceCache.get(effectId);

    var byRelic = new Map();
    (index.effectPools.get(effectId) || []).forEach(function (poolId) {
      var size = poolSize(index, poolId);
      (index.poolSlots.get(poolId) || []).forEach(function (ref) {
        var row = byRelic.get(ref.relicId);
        if (!row) {
          var base = index.relicRowsById.get(ref.relicId);
          if (!base) return;
          row = {
            id: base.id,
            name: base.name,
            named: base.named,
            kindLabel: base.kindLabel,
            colorLabel: base.colorLabel,
            color: base.meta.color,
            deep: base.meta.deep,
            unique: base.unique,
            fixed: false,
            entries: []
          };
          byRelic.set(ref.relicId, row);
        }
        row.entries.push({ slot: ref.slot, kind: ref.kind, poolId: poolId, poolSize: size });
        if (size === 1) row.fixed = true;
      });
    });

    var fixed = [];
    var random = [];
    byRelic.forEach(function (row) {
      row.entries.sort(function (left, right) {
        if (left.kind !== right.kind) return left.kind === "slot" ? -1 : 1;
        return left.slot - right.slot;
      });
      (row.fixed ? fixed : random).push(row);
    });
    var byId = function (left, right) { return left.id - right.id; };
    fixed.sort(byId);
    random.sort(byId);

    var result = Object.freeze({
      fixed: fixed,
      random: random,
      total: fixed.length + random.length,
      namedTotal: fixed.concat(random).filter(function (row) { return row.named; }).length
    });
    index.sourceCache.set(effectId, result);
    return result;
  }

  // 3) 按遗物查：三个正面槽（及诅咒槽）各自池子的成员数与前若干个词条名。
  function relicSlotSummary(Core, index, relicId, previewCount) {
    var base = index.relicRowsById.get(relicId);
    if (!base) return null;
    var limit = previewCount || SLOT_PREVIEW;
    var meta = base.meta;

    function describeSlot(poolId, slot, kind) {
      if (poolId === -1) return { slot: slot, kind: kind, poolId: -1, empty: true, size: 0, preview: [], more: 0 };
      var members = Array.from(index.base.poolSets.get(poolId) || []);
      var ordered = sortAffixes(Core, members.map(function (id) { return affixOf(index, id); }));
      var names = ordered.map(function (affix) {
        return affixEntry(index, affix.effectId);
      });
      // 池成员里有 affixIndex 查不到的 ID 时补一条占位，保证成员数与池一致
      if (names.length < members.length) {
        members.forEach(function (id) {
          if (!affixOf(index, id)) names.push(affixEntry(index, id));
        });
      }
      return {
        slot: slot,
        kind: kind,
        poolId: poolId,
        empty: names.length === 0,
        size: names.length,
        fixed: names.length === 1,
        preview: names.slice(0, limit),
        more: Math.max(0, names.length - limit)
      };
    }

    var slots = [0, 1, 2].map(function (slot) { return describeSlot(meta.slots[slot], slot, "slot"); });
    var curseSlots = [0, 1, 2].map(function (slot) { return describeSlot(meta.curseSlots[slot], slot, "curse"); });

    // 唯一 / 固定遗物：词条完全确定时给出固定词条，口径与 core.js 的
    // officialFixedEffects 完全一致 —— 每个「已声明」的槽（poolId !== -1）都必须
    // 存在、池里恰好一个成员，且该成员能在 affixIndex 里查到；否则返回 null。
    // （只看 describeSlot 的 size 会把「空池」和「查不到的占位成员」误判成固定。）
    var fixedEffects = null;
    var fixedIds = [];
    var fixedOk = true;
    for (var probe = 0; probe < 3 && fixedOk; probe += 1) {
      var probePool = meta.slots[probe];
      if (probePool === -1) continue;
      var probeMembers = index.base.poolSets.get(probePool);
      if (!probeMembers || probeMembers.size !== 1) { fixedOk = false; break; }
      fixedIds.push(probeMembers.values().next().value);
    }
    if (fixedOk && fixedIds.length > 0) {
      var fixedAffixes = fixedIds.map(function (effectId) { return affixOf(index, effectId); });
      if (!fixedAffixes.some(function (affix) { return !affix; })) {
        fixedEffects = sortAffixes(Core, fixedAffixes).map(function (affix) {
          return affixEntry(index, affix.effectId);
        });
      }
    }

    return {
      id: base.id,
      name: base.name,
      named: base.named,
      kindLabel: base.kindLabel,
      colorLabel: base.colorLabel,
      color: meta.color,
      deep: meta.deep,
      unique: base.unique,
      slotCount: slots.filter(function (entry) { return entry.poolId !== -1; }).length,
      curseSlotCount: curseSlots.filter(function (entry) { return entry.poolId !== -1; }).length,
      slots: slots,
      curseSlots: curseSlots,
      fixedEffects: fixedEffects
    };
  }

  // 大列表分页：页码越界时夹到合法范围。
  function paginate(rows, page, limit) {
    var size = limit || ROW_LIMIT;
    var pageCount = Math.max(1, Math.ceil(rows.length / size));
    var current = Math.min(Math.max(0, page || 0), pageCount - 1);
    return {
      rows: rows.slice(current * size, current * size + size),
      page: current,
      pageCount: pageCount,
      total: rows.length,
      from: rows.length ? current * size + 1 : 0,
      to: Math.min(rows.length, current * size + size)
    };
  }

  // 数据集自带的 caveats / 已知限制（当前两份数据集没有该字段时返回空数组）。
  function datasetCaveats(dataset) {
    if (!dataset || typeof dataset !== "object") return [];
    var raw = dataset.caveats;
    if (!raw) return [];
    if (typeof raw === "string") return [raw];
    if (!Array.isArray(raw)) return [];
    return raw.map(function (item) {
      if (typeof item === "string") return item;
      if (item && typeof item === "object") return String(item.text || item.note || item.detail || "");
      return String(item);
    }).filter(Boolean);
  }

  var logic = {
    buildLookupIndex: buildLookupIndex,
    searchAffixes: searchAffixes,
    searchRelics: searchRelics,
    compatibilityPeers: compatibilityPeers,
    modeSources: modeSources,
    deepSources: deepSources,
    relicSourcesFor: relicSourcesFor,
    relicSlotSummary: relicSlotSummary,
    paginate: paginate,
    datasetCaveats: datasetCaveats,
    relicDisplayName: relicDisplayName,
    isCatalogAffix: isCatalogAffix,
    isUniqueRelicId: localIsUniqueRelicId,
    ROW_LIMIT: ROW_LIMIT,
    SEARCH_LIMIT: SEARCH_LIMIT,
    SLOT_PREVIEW: SLOT_PREVIEW
  };

  // ==================================================================
  // 渲染层（只在浏览器 / WebView2 里执行）
  // ==================================================================

  function install(root) {
    var dom = null;
    var context = null;

    var state = {
      tab: "affix",
      affixQuery: "",
      effectId: null,
      relicQuery: "",
      relicId: null,
      peersExpanded: false,
      sourcePage: 0,
      onlyFixed: false,
      hideUnnamed: true,
      relicShowUnnamed: false
    };

    var relicData = null;        // 本页自行载入并缓存的遗物物品表
    var relicDataError = "";
    var relicDataPromise = null;
    var indexCache = { catalog: null, relicData: null, value: null, error: "" };

    function esc(value) { return context.helpers.escapeHtml(value); }
    function pill(text, color) { return context.helpers.pill(text, color); }

    // ---- 数据 ----

    // ctx.relicData 只有进过存档页才有值；否则走 Go 壳的 loadRelicData 桥，
    // 浏览器预览模式下回退到 fetch("../resources/relics.json")（与 app.js 一致）。
    function ensureRelicData() {
      if (context && context.relicData) {
        relicData = context.relicData;
        return Promise.resolve(relicData);
      }
      if (relicData) return Promise.resolve(relicData);
      if (!relicDataPromise) {
        relicDataPromise = Promise.resolve().then(function () {
          var bridge = root.nightreign;
          if (bridge && typeof bridge.loadRelicData === "function") return bridge.loadRelicData();
          return root.fetch("../resources/relics.json").then(function (response) {
            if (!response.ok) throw new Error("无法载入内置遗物数据");
            return response.json();
          });
        }).then(function (data) {
          // 等待期间 app.js 可能已经把自己的实例交给了本页（refresh 里换过来）。
          // 这时直接沿用 ctx 的那一份，别再把模块变量指回本页的副本，
          // 否则两份 relics.json 会长期共存在内存里。
          if (context && context.relicData) return context.relicData;
          relicData = data;
          relicDataError = "";
          return data;
        }).catch(function (error) {
          relicDataPromise = null;
          relicDataError = error && error.message ? error.message : String(error);
          throw error;
        });
      }
      return relicDataPromise;
    }

    function currentRelicData() {
      return (context && context.relicData) || relicData;
    }

    function lookupIndex() {
      var catalog = context && context.catalog;
      var data = currentRelicData();
      if (!catalog || !data) return null;
      if (indexCache.catalog === catalog && indexCache.relicData === data) {
        return indexCache.value;
      }
      indexCache = { catalog: catalog, relicData: data, value: null, error: "" };
      try {
        indexCache.value = buildLookupIndex(context.Core, catalog, data);
        relicDataError = "";
      } catch (error) {
        indexCache.error = error && error.message ? error.message : String(error);
        relicDataError = indexCache.error;
      }
      return indexCache.value;
    }

    function selectedAffix() {
      var catalog = context && context.catalog;
      if (!catalog || state.effectId == null) return null;
      var found = null;
      catalog.affixes.some(function (affix) {
        if (affix.effectId === state.effectId) { found = affix; return true; }
        return false;
      });
      return found;
    }

    // 池成员里有一部分词条只存在于 relics.json 的 extraAffixes（角色专属词条等），
    // 词条库里查不到 —— 这些 chip 渲染成不可点的静态标签，点了也不会跳转、
    // 更不会覆盖用户已经输入的词条搜索词。
    function affixChip(item, prefix) {
      var label = (prefix || "") + esc(item.name) + "<span>" + item.effectId + "</span>";
      if (item.inCatalog !== false) {
        return "<button type='button' class='lookup-chip' data-effect-id='" + item.effectId + "'>" + label + "</button>";
      }
      return "<span class='lookup-chip lookup-chip--static' data-testid='lookup-chip-static'" +
        " title='该词条来自遗物参数表（extraAffixes），词条库中没有对应条目'>" + label +
        "<em>参数表</em></span>";
    }

    function extraAffixNote(items) {
      var hasExtra = items.some(function (item) { return item.inCatalog === false; });
      return hasExtra
        ? "<p class='lookup-note lookup-note--muted' data-testid='lookup-extra-note'>" +
          "带「参数表」标记的词条来自遗物参数表（extraAffixes，多为角色专属词条），" +
          "词条库中没有对应条目，无法在「按词条查」里展开。</p>"
        : "";
    }

    // ---- 模板 ----

    function shell() {
      return "" +
        "<div class='page-content lookup-content'>" +
        "<header class='title-block page-title'>" +
        "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
        "<div><h1>词条反查</h1><p>由词条查能出它的遗物与出货池，也可反过来按遗物查三个槽位的词条池</p></div>" +
        "</header>" +

        "<div class='lookup-toolbar'>" +
        "<div class='segmented-control lookup-tabs' role='radiogroup' aria-label='反查方式' data-testid='lookup-tabs'>" +
        "<button type='button' class='segment-button' role='radio' data-lookup-tab='affix' data-testid='lookup-tab-affix'>按词条查</button>" +
        "<button type='button' class='segment-button' role='radio' data-lookup-tab='relic' data-testid='lookup-tab-relic'>按遗物查</button>" +
        "</div>" +
        "<div class='lookup-status' data-testid='lookup-data-status'></div>" +
        "</div>" +

        "<section class='lookup-panel' data-lookup-panel='affix'>" +
        "<article class='card lookup-card'>" +
        "<div class='section-heading'><div class='section-icon'>⌕</div>" +
        "<div><h2>词条搜索</h2><p>支持名称、别名、分类与 effectId</p></div></div>" +
        "<label class='search-field lookup-search'><span aria-hidden='true'>⌕</span>" +
        "<input type='search' autocomplete='off' placeholder='搜索词条名称、别名、分类或 effectId' data-testid='lookup-affix-search'></label>" +
        "<div class='lookup-list' data-testid='lookup-affix-results'></div>" +
        "</article>" +
        "<div data-testid='lookup-affix-detail'></div>" +
        "<div data-testid='lookup-affix-sources'></div>" +
        "</section>" +

        "<section class='lookup-panel' data-lookup-panel='relic' hidden>" +
        "<article class='card lookup-card'>" +
        "<div class='section-heading'><div class='section-icon'>▤</div>" +
        "<div><h2>遗物搜索</h2><p>按遗物名或 ID 查看三个槽位（及诅咒槽）各自的词条池</p></div></div>" +
        "<div class='lookup-filter-row'>" +
        "<label class='search-field lookup-search'><span aria-hidden='true'>⌕</span>" +
        "<input type='search' autocomplete='off' placeholder='搜索遗物名称、ID 或种类' data-testid='lookup-relic-search'></label>" +
        "<label class='switch-control'><input type='checkbox' data-lookup-toggle='relicShowUnnamed' data-testid='lookup-relic-unnamed'>" +
        "<span class='switch-track'></span><span>显示无名称条目</span></label>" +
        "</div>" +
        "<div class='lookup-list' data-testid='lookup-relic-results'></div>" +
        "</article>" +
        "<div data-testid='lookup-relic-detail'></div>" +
        "</section>" +

        "<details class='card lookup-caveats' data-testid='lookup-caveats'>" +
        "<summary>数据口径与已知限制</summary>" +
        "<div class='lookup-caveats-body' data-testid='lookup-caveats-body'></div>" +
        "</details>" +
        "</div>";
    }

    // ---- 渲染：状态条 ----

    function renderStatus() {
      var node = dom.querySelector("[data-testid='lookup-data-status']");
      if (!node) return;
      var parts = [];
      var catalog = context.catalog;
      if (catalog && catalog.affixes) {
        parts.push(pill("词条库 " + catalog.affixes.length + " 条", "green"));
      } else {
        parts.push(pill("词条库未就绪", "amber"));
      }
      var index = lookupIndex();
      if (index) {
        parts.push(pill("遗物 " + index.relicRows.length + " 件 · 池 " + index.base.poolSets.size + " 个", "purple"));
      } else if (relicDataError) {
        parts.push(pill("遗物物品表不可用", "red"));
      } else if (currentRelicData()) {
        parts.push(pill("遗物物品表已载入", "purple"));
      } else {
        parts.push(pill("正在载入遗物物品表…", "gray"));
      }
      node.innerHTML = parts.join("");
    }

    // ---- 渲染：按词条查 ----

    function affixRowHtml(affix) {
      var tags = pill(affix.category || "未分类", "purple") +
        (affix.isCurse ? pill("负面词条", "red") : "") +
        (affix.requiresCurse ? pill("需诅咒", "amber") : "");
      return "<button type='button' class='lookup-row" + (affix.effectId === state.effectId ? " is-active" : "") +
        "' data-effect-id='" + affix.effectId + "' data-testid='lookup-affix-row'>" +
        "<span class='lookup-row-ids'><strong>" + affix.effectId + "</strong><span>" + affix.sortId + "</span></span>" +
        "<span class='lookup-row-copy'><span class='lookup-row-name'><strong>" + esc(affix.name) + "</strong>" + tags + "</span>" +
        (affix.explanation ? "<p>" + esc(affix.explanation) + "</p>" : "") + "</span></button>";
    }

    function renderAffixResults() {
      var node = dom.querySelector("[data-testid='lookup-affix-results']");
      if (!node) return;
      var catalog = context.catalog;
      if (!catalog || !catalog.affixes) {
        node.innerHTML = "<div class='empty-state lookup-empty'><div class='empty-icon'>☷</div><h3>词条库未就绪</h3><p>请先在「数据设置」里恢复内置词条库</p></div>";
        return;
      }
      var found = searchAffixes(context.Core, catalog, state.affixQuery, { limit: SEARCH_LIMIT });
      if (!found.rows.length) {
        node.innerHTML = "<div class='empty-state lookup-empty' data-testid='lookup-affix-empty'><div class='empty-icon'>⌕</div><h3>没有匹配词条</h3><p>请更换关键词</p></div>";
        return;
      }
      node.innerHTML = "<div class='lookup-list-meta' data-testid='lookup-affix-count'>" +
        "匹配 " + found.total + " 条" + (found.truncated ? "，仅显示前 " + found.rows.length + " 条" : "") +
        "</div>" + found.rows.map(affixRowHtml).join("");
    }

    function renderAffixDetail() {
      var node = dom.querySelector("[data-testid='lookup-affix-detail']");
      if (!node) return;
      var affix = selectedAffix();
      if (!affix) {
        node.innerHTML = "<article class='card lookup-card lookup-hint'><div class='empty-state lookup-empty'>" +
          "<div class='empty-icon'>⌖</div><h3>先选一条词条</h3><p>选中后显示分类、说明、互斥组与全部出处</p></div></article>";
        return;
      }
      var peers = compatibilityPeers(context.Core, context.catalog, affix);
      var index = lookupIndex();

      var tags = pill(affix.category || "未分类", "purple") +
        pill(affix.superposability || "叠加性未知", affix.superposability === "可叠加" ? "green" : "gray") +
        (affix.isCurse ? pill("负面词条", "red") : "") +
        (affix.requiresCurse ? pill("需搭配诅咒", "amber") : "");

      var lines = "" +
        "<div><dt>effectId</dt><dd>" + affix.effectId + "</dd></div>" +
        "<div><dt>排序键 sortId</dt><dd>" + affix.sortId + "</dd></div>" +
        "<div><dt>分类</dt><dd>" + esc(affix.category || "未分类") + "</dd></div>" +
        "<div><dt>可叠加性</dt><dd>" + esc(affix.superposability || "未知") + "</dd></div>" +
        "<div><dt>互斥池 ID</dt><dd>" + affix.compatibilityId +
        (affix.compatibilityId === -1 ? "（无互斥组）" : "") + "</dd></div>";

      // 互斥组最大的有 102 条：默认只列前 PEER_PREVIEW 条，其余由本页的
      //「展开全部」按钮就地展开（词条库页没有按 compatibilityId 过滤的能力，
      // 不能把用户指过去）。
      var peersShown = state.peersExpanded ? peers : peers.slice(0, PEER_PREVIEW);
      var peersToggle = peers.length > PEER_PREVIEW
        ? "<div class='lookup-peers-actions'><button type='button' class='button button--secondary lookup-peers-toggle'" +
          " data-lookup-peers-toggle='1' data-testid='lookup-peers-toggle'>" +
          (state.peersExpanded ? "收起（只看前 " + PEER_PREVIEW + " 条）" : "展开全部 " + peers.length + " 条") +
          "</button><span class='lookup-sub'>" +
          (state.peersExpanded ? "已列出全部 " + peers.length + " 条互斥词条" : "还有 " + (peers.length - PEER_PREVIEW) + " 条未列出") +
          "</span></div>"
        : "";

      var peersHtml = affix.compatibilityId === -1
        ? "<p class='lookup-note'>该词条没有互斥组，可与任意其他词条同时出现（仍不能与自身重复）。</p>"
        : (peers.length
          ? "<p class='lookup-note'>同一互斥池（" + affix.compatibilityId + "）内的词条不能同时出现在一件遗物上，共 " +
            (peers.length + 1) + " 条：</p><div class='lookup-chiplist lookup-chiplist--scroll' data-testid='lookup-peers'>" +
            peersShown.map(function (peer) {
              return "<button type='button' class='lookup-chip' data-effect-id='" + peer.effectId + "'>" +
                esc(peer.name) + "<span>" + peer.effectId + "</span></button>";
            }).join("") + "</div>" + peersToggle
          : "<p class='lookup-note'>互斥池 " + affix.compatibilityId + " 内只有这一条词条，没有互斥对象。</p>");

      var deepNote = "";
      if (index) {
        var deep = deepSources(context.Core, index, affix.effectId);
        if (deep.isCurse) {
          deepNote = "<p class='lookup-note'>这是诅咒池（" + deep.cursePoolId + "）里的负面词条，只会出现在深夜遗物的诅咒槽，" +
            "与同一行需诅咒的正面词条配对。</p>";
        } else if (deep.requiresCurse) {
          deepNote = "<p class='lookup-note'>深夜专属：该词条属于深夜 A 池，出现时同一行必须携带一条诅咒池的负面词条。</p>";
        } else if (deep.inAny) {
          deepNote = "<p class='lookup-note'>该词条可出现在深夜遗物上，且不需要搭配负面词条。</p>";
        } else {
          deepNote = "<p class='lookup-note'>该词条不在深夜 A/B/C 池中，不会出现在深夜遗物上。</p>";
        }
      }

      node.innerHTML = "<article class='card lookup-card' data-testid='lookup-detail-card'>" +
        "<div class='section-heading'><div class='section-icon section-icon--green'>◈</div>" +
        "<div><h2>" + esc(affix.name) + "</h2><p>" + esc(affix.explanation || "数据集未提供该词条的说明") + "</p></div></div>" +
        "<div class='lookup-taglist'>" + tags + "</div>" +
        "<dl class='data-lines lookup-lines'>" + lines + "</dl>" +
        "<div class='lookup-block'><h3>互斥组</h3>" + peersHtml + "</div>" +
        (deepNote ? "<div class='lookup-block'><h3>深夜相关</h3>" + deepNote + "</div>" : "") +
        "</article>";
    }

    function slotChips(entry) {
      return entry.slots.map(function (slot) {
        return "<span class='lookup-slot-chip" + (slot.member ? " is-on" : "") + "'>" +
          SLOT_LABELS[slot.slot] + "<span>池 " + slot.poolId + " · " + slot.size + " 条</span></span>";
      }).join("");
    }

    function poolChips(entry) {
      return entry.pools.map(function (pool) {
        return "<span class='lookup-slot-chip" + (pool.member ? " is-on" : "") + "'>" +
          esc(pool.label) + "<span>池 " + pool.poolId + " · " + pool.size + " 条</span></span>";
      }).join("");
    }

    function relicEntryLabel(entry) {
      var where = entry.kind === "curse" ? "诅咒槽 " + (entry.slot + 1) : SLOT_LABELS[entry.slot];
      return where + "（池 " + entry.poolId + " · " + entry.poolSize + " 条）";
    }

    function relicSourceRow(row) {
      return "<tr data-testid='lookup-source-row'>" +
        "<td><button type='button' class='lookup-linkish' data-relic-id='" + row.id + "'>" + esc(row.name) + "</button></td>" +
        "<td class='lookup-num'>" + row.id + "</td>" +
        "<td>" + esc(row.kindLabel) + "</td>" +
        "<td>" + pill(row.colorLabel, COLOR_PILLS[row.color] || "gray") + "</td>" +
        "<td class='lookup-where'>" + row.entries.map(relicEntryLabel).map(esc).join("、") + "</td>" +
        "</tr>";
    }

    function relicTable(rows, testId) {
      if (!rows.length) return "";
      return "<div class='table-wrap lookup-table-wrap'><table class='library-table lookup-table' data-testid='" + testId + "'>" +
        "<thead><tr><th>遗物</th><th class='lookup-num'>ID</th><th>种类</th><th>颜色</th><th>出现位置</th></tr></thead>" +
        "<tbody>" + rows.map(relicSourceRow).join("") + "</tbody></table></div>";
    }

    function renderAffixSources() {
      var node = dom.querySelector("[data-testid='lookup-affix-sources']");
      if (!node) return;
      var affix = selectedAffix();
      if (!affix) { node.innerHTML = ""; return; }

      var index = lookupIndex();
      if (!index) {
        node.innerHTML = "<article class='card lookup-card' data-testid='lookup-sources-card'>" +
          "<div class='section-heading'><div class='section-icon section-icon--red'>!</div>" +
          "<div><h2>能在哪出</h2><p>遗物物品表不可用，本页只能显示词条说明部分</p></div></div>" +
          "<div class='issue-row issue-row--warning' data-testid='lookup-relicdata-missing'><span class='issue-symbol'>△</span>" +
          "<div><strong>遗物物品表不可用</strong><p>" +
          esc(relicDataError ? "载入失败：" + relicDataError : "正在载入 relics.json，请稍候…") +
          "</p></div></div></article>";
        return;
      }

      var modes = modeSources(context.Core, index, affix.effectId);
      var deep = deepSources(context.Core, index, affix.effectId);
      var sources = relicSourcesFor(index, affix.effectId);

      // a) 普通随机遗物：逐口径说明
      var modeRows = modes.map(function (entry) {
        return "<tr data-testid='lookup-mode-row' data-mode='" + entry.key + "'>" +
          "<td><strong>" + esc(entry.title) + "</strong><p class='lookup-sub'>" + esc(entry.detail) + "</p></td>" +
          "<td>" + (entry.available ? pill("可掉落", "green") : pill("不掉落", "gray")) + "</td>" +
          "<td class='lookup-slotcell'>" + (entry.multiPattern ? poolChips(entry) : slotChips(entry)) + "</td>" +
          "</tr>";
      }).join("");

      // b) 深夜遗物
      var deepBody = "<div class='lookup-chipbar'>" + deep.pools.map(function (pool) {
        return "<span class='lookup-slot-chip" + (pool.member ? " is-on" : "") + "'>深夜 " + esc(pool.label) +
          "<span>池 " + pool.poolId + " · " + pool.size + " 条</span></span>";
      }).join("") + "</div>";
      if (deep.isCurse) {
        deepBody += "<p class='lookup-note'>诅咒池（" + deep.cursePoolId + "）共 " + deep.curses.length +
          " 条负面词条，只出现在深夜遗物的诅咒槽（curseSlots）。</p>";
      } else if (!deep.inAny) {
        deepBody += "<p class='lookup-note'>不在深夜 A/B/C 三池内，深夜遗物不会出这条词条。</p>";
      } else if (deep.requiresCurse) {
        deepBody += "<p class='lookup-note'>属于 A 池：出现时同一行必须配一条诅咒池（" + deep.cursePoolId +
          "）的负面词条，因此只会出现在带诅咒槽的深夜遗物上。诅咒池共 " + deep.curses.length + " 条：</p>" +
          "<div class='lookup-chiplist' data-testid='lookup-curses'>" + deep.curses.map(function (curse) {
            return affixChip({
              effectId: curse.effectId,
              name: curse.name || ("词条 #" + curse.effectId),
              inCatalog: isCatalogAffix(index, curse.effectId)
            });
          }).join("") + "</div>";
      } else {
        deepBody += "<p class='lookup-note'>属于 B / C 池：深夜遗物可出，且不需要搭配负面词条。</p>";
      }

      // c) 固定 / 唯一遗物与随机池出处
      var visible = function (row) { return !state.hideUnnamed || row.named; };
      var fixedRows = sources.fixed.filter(visible);
      var allRandomRows = sources.random.filter(visible);
      var randomRows = state.onlyFixed ? [] : allRandomRows;
      var paged = paginate(randomRows, state.sourcePage, ROW_LIMIT);
      state.sourcePage = paged.page;
      var hidden = sources.total - (fixedRows.length + allRandomRows.length);

      var relicBody = "<div class='lookup-filter-row lookup-filter-row--tight'>" +
        "<label class='switch-control'><input type='checkbox' data-lookup-toggle='onlyFixed'" + (state.onlyFixed ? " checked" : "") +
        " data-testid='lookup-only-fixed'><span class='switch-track'></span><span>只看固定词条</span></label>" +
        "<label class='switch-control'><input type='checkbox' data-lookup-toggle='hideUnnamed'" + (state.hideUnnamed ? " checked" : "") +
        " data-testid='lookup-hide-unnamed'><span class='switch-track'></span><span>隐藏无名称条目</span></label>" +
        // 「只看固定词条」开着时随机池表格整块不渲染，计数行要说明它是被折叠而不是漏渲染
        "<span class='lookup-count' data-testid='lookup-source-count'>固定 " + fixedRows.length + " 件 · 随机池 " +
        allRandomRows.length + " 件" + (state.onlyFixed ? "（已折叠）" : "") +
        (hidden > 0 ? " · 已隐藏 " + hidden + " 件无名称条目" : "") + "</span>" +
        "</div>";

      relicBody += "<h4 class='lookup-subhead'>固定词条（池内只有这一条）</h4>";
      relicBody += fixedRows.length
        ? relicTable(fixedRows, "lookup-fixed-table")
        : "<p class='lookup-note'>没有遗物把这条词条作为固定词条。</p>";

      if (!state.onlyFixed) {
        relicBody += "<h4 class='lookup-subhead'>随机池可出（该槽位还会出其他词条）</h4>";
        if (!randomRows.length) {
          relicBody += "<p class='lookup-note'>没有随机池会出这条词条。</p>";
        } else {
          relicBody += relicTable(paged.rows, "lookup-random-table");
          if (paged.pageCount > 1) {
            relicBody += "<div class='lookup-pager' data-testid='lookup-pager'>" +
              "<button type='button' class='button button--secondary' data-lookup-page='prev'" +
              (paged.page === 0 ? " disabled" : "") + ">上一页</button>" +
              "<span>第 " + paged.from + "–" + paged.to + " 件 / 共 " + paged.total + " 件（第 " +
              (paged.page + 1) + " / " + paged.pageCount + " 页）</span>" +
              "<button type='button' class='button button--secondary' data-lookup-page='next'" +
              (paged.page >= paged.pageCount - 1 ? " disabled" : "") + ">下一页</button>" +
              "</div>";
          } else {
            relicBody += "<div class='lookup-pager'><span>共 " + paged.total + " 件</span></div>";
          }
        }
      }

      node.innerHTML = "<article class='card lookup-card' data-testid='lookup-sources-card'>" +
        "<div class='section-heading'><div class='section-icon'>⌖</div>" +
        "<div><h2>能在哪出</h2><p>按出货口径、深夜池与具体遗物三层展开</p></div></div>" +

        "<div class='lookup-block'><h3>普通随机遗物</h3>" +
        "<div class='table-wrap lookup-table-wrap'><table class='library-table lookup-table' data-testid='lookup-mode-table'>" +
        "<thead><tr><th>校验口径</th><th>能否掉落</th><th>槽位 / 池</th></tr></thead><tbody>" + modeRows +
        "</tbody></table></div></div>" +

        "<div class='lookup-block'><h3>深夜遗物</h3>" + deepBody + "</div>" +

        "<div class='lookup-block'><h3>具体遗物出处</h3>" + relicBody + "</div>" +
        "</article>";
    }

    // ---- 渲染：按遗物查 ----

    function renderRelicResults() {
      var node = dom.querySelector("[data-testid='lookup-relic-results']");
      if (!node) return;
      var index = lookupIndex();
      if (!index) {
        node.innerHTML = "<div class='issue-row issue-row--warning' data-testid='lookup-relic-missing'><span class='issue-symbol'>△</span>" +
          "<div><strong>遗物物品表不可用</strong><p>" +
          esc(relicDataError ? "载入失败：" + relicDataError : "正在载入 relics.json，请稍候…") + "</p></div></div>";
        return;
      }
      var found = searchRelics(context.Core, index, state.relicQuery, {
        limit: SEARCH_LIMIT,
        includeUnnamed: state.relicShowUnnamed
      });
      if (!found.rows.length) {
        node.innerHTML = "<div class='empty-state lookup-empty' data-testid='lookup-relic-empty'><div class='empty-icon'>⌕</div>" +
          "<h3>没有匹配遗物</h3><p>请更换关键词，或勾选「显示无名称条目」</p></div>";
        return;
      }
      node.innerHTML = "<div class='lookup-list-meta' data-testid='lookup-relic-count'>匹配 " + found.total + " 件" +
        (found.truncated ? "，仅显示前 " + found.rows.length + " 件" : "") + "</div>" +
        found.rows.map(function (row) {
          return "<button type='button' class='lookup-row" + (row.id === state.relicId ? " is-active" : "") +
            "' data-relic-id='" + row.id + "' data-testid='lookup-relic-row'>" +
            "<span class='lookup-row-ids'><strong>" + row.id + "</strong></span>" +
            "<span class='lookup-row-copy'><span class='lookup-row-name'><strong>" + esc(row.name) + "</strong>" +
            pill(row.kindLabel, row.meta.deep ? "amber" : "purple") +
            pill(row.colorLabel, COLOR_PILLS[row.meta.color] || "gray") + "</span></span></button>";
        }).join("");
    }

    function slotBlock(entry) {
      var title = entry.kind === "curse" ? "诅咒槽 " + (entry.slot + 1) : SLOT_LABELS[entry.slot];
      if (entry.poolId === -1) {
        return "<div class='lookup-slotbox is-muted'><div class='lookup-slotbox-head'><strong>" + title + "</strong>" +
          pill("没有这个槽", "gray") + "</div></div>";
      }
      var head = "<div class='lookup-slotbox-head'><strong>" + title + "</strong>" +
        pill("池 " + entry.poolId, "purple") +
        pill(entry.fixed ? "固定词条" : entry.size + " 条可出", entry.fixed ? "green" : "blue") + "</div>";
      if (entry.empty) {
        return "<div class='lookup-slotbox'>" + head + "<p class='lookup-note'>该池在数据集中没有成员（空池），这个槽位不会出词条。</p></div>";
      }
      var chips = entry.preview.map(function (item) { return affixChip(item); }).join("");
      var more = entry.more > 0 ? "<span class='lookup-more'>…还有 " + entry.more + " 条</span>" : "";
      return "<div class='lookup-slotbox'>" + head + "<div class='lookup-chiplist'>" + chips + more + "</div></div>";
    }

    function renderRelicDetail() {
      var node = dom.querySelector("[data-testid='lookup-relic-detail']");
      if (!node) return;
      var index = lookupIndex();
      if (!index || state.relicId == null) {
        node.innerHTML = index
          ? "<article class='card lookup-card lookup-hint'><div class='empty-state lookup-empty'><div class='empty-icon'>▤</div>" +
            "<h3>先选一件遗物</h3><p>选中后显示三个槽位（及诅咒槽）各自池子的成员数与词条</p></div></article>"
          : "";
        return;
      }
      var summary = relicSlotSummary(context.Core, index, state.relicId, SLOT_PREVIEW);
      if (!summary) { node.innerHTML = ""; return; }

      // Core.relicKindLabel 在非深夜的唯一 ID 区间上本来就返回「唯一遗物」，
      // 只有种类标签另有说法（例如以后出现深夜的唯一遗物）时才补这个 pill，避免并排重复。
      var tags = pill(summary.kindLabel, summary.deep ? "amber" : "purple") +
        pill(summary.colorLabel, COLOR_PILLS[summary.color] || "gray") +
        pill("ID " + summary.id, "gray") +
        (summary.unique && summary.kindLabel !== "唯一遗物" ? pill("唯一遗物", "green") : "") +
        pill("词条槽 " + summary.slotCount + (summary.curseSlotCount ? " · 诅咒槽 " + summary.curseSlotCount : ""), "blue");

      var fixedBlock = "";
      if (summary.fixedEffects) {
        fixedBlock = "<div class='lookup-block'><h3>固定词条</h3>" +
          "<p class='lookup-note'>各槽池都只有一个成员，这件遗物的词条完全确定（按 sortId → effectId 升序）：</p>" +
          "<div class='lookup-chiplist' data-testid='lookup-relic-fixed'>" + summary.fixedEffects.map(function (item, order) {
            return affixChip(item, (order + 1) + ". ");
          }).join("") + "</div></div>";
      }

      // 「参数表」说明整张卡片只出一次，放在最后统一覆盖固定词条与各槽位预览
      var slotItems = summary.slots.concat(summary.curseSlots).reduce(function (all, entry) {
        return all.concat(entry.preview || []);
      }, summary.fixedEffects || []);
      var curseBlocks = summary.curseSlots.filter(function (entry) { return entry.poolId !== -1; });

      node.innerHTML = "<article class='card lookup-card' data-testid='lookup-relic-card'>" +
        "<div class='section-heading'><div class='section-icon section-icon--green'>▤</div>" +
        "<div><h2>" + esc(summary.name) + "</h2><p>" +
        (summary.deep ? "深夜遗物：正面词条来自深夜 A/B/C 池，需诅咒的词条同一行配负面词条" : "槽位池决定这件遗物能出哪些词条") +
        "</p></div></div>" +
        "<div class='lookup-taglist'>" + tags + "</div>" +
        fixedBlock +
        "<div class='lookup-block'><h3>正面词条槽</h3><div class='lookup-slotgrid'>" +
        summary.slots.map(slotBlock).join("") + "</div></div>" +
        (curseBlocks.length
          ? "<div class='lookup-block'><h3>诅咒槽</h3><div class='lookup-slotgrid'>" +
            curseBlocks.map(slotBlock).join("") + "</div></div>"
          : "") +
        extraAffixNote(slotItems) +
        "</article>";
    }

    // ---- 渲染：底部数据说明 ----

    function renderCaveats() {
      var node = dom.querySelector("[data-testid='lookup-caveats-body']");
      if (!node) return;
      var catalog = context.catalog;
      var data = currentRelicData();
      var notes = datasetCaveats(catalog).concat(datasetCaveats(data));

      var seenSource = Object.create(null);
      var sources = []
        .concat((catalog && catalog.sources) || [])
        .concat((data && data.sources) || [])
        .filter(function (source) {
          // 两份数据集共用同一批来源（名称写法略有差异），按 URL 去重后再列
          var key = String(source.url || source.name);
          if (seenSource[key]) return false;
          seenSource[key] = true;
          return true;
        })
        .map(function (source) {
          return "<li><strong>" + esc(source.name) + "</strong>" +
            (source.revision ? "<span> · " + esc(String(source.revision).slice(0, 12)) + "</span>" : "") +
            (source.license ? "<span> · " + esc(source.license) + "</span>" : "") +
            (source.url ? "<p class='lookup-sub'>" + esc(source.url) + "</p>" : "") + "</li>";
        }).join("");

      node.innerHTML =
        "<ul class='lookup-notelist'>" +
        "<li>池归属来自游戏参数表（EquipParamAntique / AttachEffectTableParam）重建的非零权重池，" +
        "<strong>不是实测掉率</strong>，同一池内各词条的权重差异本页不体现。</li>" +
        "<li>「普通旧池」对应 1.02 及更早版本，只用于核对老存档；当前版本请看「普通 1.03」。</li>" +
        "<li>深夜遗物在参数表里记录的槽池排列与游戏实际生成不符，不能作为深夜校验依据" +
        "（例如遗物 2013212「辽阔的光耀暗淡情景」记录为 CCC 且没有诅咒槽）；" +
        "本页按 core.js 的 A/B/C 池并集与「需诅咒 ⇔ 同行带负面词条」口径说明。</li>" +
        "<li>无名称的遗物条目是参数表里的内部项（多为词条道具本体），默认隐藏。</li>" +
        (notes.length ? notes.map(function (item) { return "<li>" + esc(item) + "</li>"; }).join("") : "") +
        "</ul>" +
        (sources ? "<h4 class='lookup-subhead'>数据来源</h4><ul class='lookup-notelist lookup-sources'>" + sources + "</ul>" : "");
    }

    // ---- 整页渲染与事件 ----

    function renderTabs() {
      var buttons = dom.querySelectorAll("[data-lookup-tab]");
      Array.prototype.forEach.call(buttons, function (button) {
        var active = button.dataset.lookupTab === state.tab;
        button.classList.toggle("is-active", active);
        button.setAttribute("aria-checked", active ? "true" : "false");
      });
      Array.prototype.forEach.call(dom.querySelectorAll("[data-lookup-panel]"), function (panel) {
        panel.hidden = panel.dataset.lookupPanel !== state.tab;
      });
    }

    function renderAll() {
      renderTabs();
      renderStatus();
      renderAffixResults();
      renderAffixDetail();
      renderAffixSources();
      renderRelicResults();
      renderRelicDetail();
      renderCaveats();
    }

    function selectAffix(effectId) {
      // 保险：只存在于 extraAffixes 的词条在词条库里查不到，跳过去只会得到空详情，
      // 还会把用户的搜索词冲掉。这类 chip 本来就渲染成非按钮，这里再兜一道底。
      var index = lookupIndex();
      if (index && !isCatalogAffix(index, effectId)) return;
      state.effectId = effectId;
      state.sourcePage = 0;
      state.peersExpanded = false;
      state.tab = "affix";
      // 从互斥组 / 诅咒池 /「按遗物查」跳过来时，结果列表里可能没有这条词条，用 ID 带出来
      if (!dom.querySelector("[data-testid='lookup-affix-results'] [data-effect-id='" + effectId + "']")) {
        state.affixQuery = String(effectId);
        var input = dom.querySelector("[data-testid='lookup-affix-search']");
        if (input) input.value = state.affixQuery;
      }
      renderTabs();
      renderAffixResults();
      renderAffixDetail();
      renderAffixSources();
    }

    function selectRelic(relicId) {
      state.relicId = relicId;
      state.tab = "relic";
      // 与 selectAffix 同理：从出处表跳过来时遗物列表里可能没有这一行
      //（默认 ID 升序只显示前 200 件），用 ID 带出来，选中行才有高亮。
      if (!dom.querySelector("[data-testid='lookup-relic-results'] [data-relic-id='" + relicId + "']")) {
        var index = lookupIndex();
        var row = index && index.relicRowsById.get(relicId);
        if (row && !row.named && !state.relicShowUnnamed) {
          state.relicShowUnnamed = true;
          var toggle = dom.querySelector("[data-testid='lookup-relic-unnamed']");
          if (toggle) toggle.checked = true;
        }
        state.relicQuery = String(relicId);
        var input = dom.querySelector("[data-testid='lookup-relic-search']");
        if (input) input.value = state.relicQuery;
      }
      renderTabs();
      renderRelicResults();
      renderRelicDetail();
    }

    // CSP 禁止内联脚本，事件一律在 mount 上做委托。
    function bindEvents() {
      dom.addEventListener("click", function (event) {
        if (!event.target || typeof event.target.closest !== "function") return;
        var tabButton = event.target.closest("[data-lookup-tab]");
        if (tabButton) {
          state.tab = tabButton.dataset.lookupTab;
          renderTabs();
          return;
        }
        var peersToggle = event.target.closest("[data-lookup-peers-toggle]");
        if (peersToggle) {
          state.peersExpanded = !state.peersExpanded;
          renderAffixDetail();
          // 重渲染换掉了按钮节点，把焦点还给新的那一个
          var toggleAgain = dom.querySelector("[data-testid='lookup-peers-toggle']");
          if (toggleAgain) toggleAgain.focus();
          return;
        }
        var pager = event.target.closest("[data-lookup-page]");
        if (pager) {
          var direction = pager.dataset.lookupPage;
          state.sourcePage += direction === "next" ? 1 : -1;
          if (state.sourcePage < 0) state.sourcePage = 0;
          renderAffixSources();
          // 与开关一样：重渲染会换掉按钮节点，把焦点还回去，键盘翻页才能连续。
          // 翻到首 / 末页时同名按钮会变成 disabled，改聚焦另一个。
          var again = dom.querySelector("[data-lookup-page='" + direction + "']");
          if (!again || again.disabled) {
            again = dom.querySelector("[data-lookup-page='" + (direction === "next" ? "prev" : "next") + "']");
          }
          if (again && !again.disabled) again.focus();
          return;
        }
        var affixNode = event.target.closest("[data-effect-id]");
        if (affixNode) {
          selectAffix(Number(affixNode.dataset.effectId));
          return;
        }
        var relicNode = event.target.closest("[data-relic-id]");
        if (relicNode) {
          selectRelic(Number(relicNode.dataset.relicId));
        }
      });

      dom.addEventListener("input", function (event) {
        var target = event.target;
        if (!target || typeof target.getAttribute !== "function") return;
        var testId = target.getAttribute("data-testid");
        if (testId === "lookup-affix-search") {
          state.affixQuery = target.value;
          renderAffixResults();
        } else if (testId === "lookup-relic-search") {
          state.relicQuery = target.value;
          renderRelicResults();
        }
      });

      dom.addEventListener("change", function (event) {
        if (!event.target || typeof event.target.closest !== "function") return;
        var toggle = event.target.closest("[data-lookup-toggle]");
        if (!toggle) return;
        var name = toggle.dataset.lookupToggle;
        state[name] = toggle.checked;
        if (name === "relicShowUnnamed") {
          renderRelicResults();
        } else {
          state.sourcePage = 0;
          renderAffixSources();
        }
        // 重渲染会换掉节点，把焦点还给同一个开关，键盘操作才能连续
        var again = dom.querySelector("[data-lookup-toggle='" + name + "']");
        if (again && again !== toggle) again.focus();
      });
    }

    function refresh(ctx) {
      if (!dom) return;
      context = ctx;
      // app.js 载入过遗物物品表后（用户进了存档页）改用它的实例，释放本页自己的副本
      if (ctx.relicData && relicData !== ctx.relicData) {
        relicData = ctx.relicData;
        relicDataPromise = null;
      }
      renderAll();
      if (!currentRelicData()) {
        ensureRelicData().then(function () {
          renderAll();
        }).catch(function () {
          renderAll();
        });
      }
    }

    root.NightreignPages = root.NightreignPages || {};
    root.NightreignPages[PAGE_KEY] = {
      // 首次切换到本页时调用一次；mount 是 [data-mount="lookup"] 元素。
      init: function (mount, ctx) {
        dom = mount;
        context = ctx;
        mount.innerHTML = shell();
        bindEvents();
        refresh(ctx);
      },
      // 词条库 / 存档数据变化后调用。
      refresh: refresh
    };
  }

  logic.install = install;
  return logic;
});
