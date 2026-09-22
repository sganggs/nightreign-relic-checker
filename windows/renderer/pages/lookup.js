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
  var DEEP_CURSE_POOL_ID = 3000000;
  var COLOR_PILLS = ["red", "blue", "amber", "green", "gray"];
  var SLOT_LABELS = ["第 1 槽", "第 2 槽", "第 3 槽"];

  // 与 core.js auditRelic（契约 §4.2 / §4.3）完全一致的 ID 规则。
  var RELIC_ID_MIN = 100;
  var RELIC_ID_MAX = 2013322;
  var CHEAT_ID_MIN = 20000;
  var CHEAT_ID_MAX = 30035;

  // 槽位池的中文短名。普通大遗物的槽位池按「孔数」分层：
  // 1 孔 = [100]，2 孔 = [200, 100]，3 孔 = [300, 200, 100]（1.03 之后同构为 110/210/310）。
  // 注意层号不是槽序号 —— 3 孔遗物 slots 数组是 [300, 200, 100]，第 1 个槽位用的是
  // 3 孔层池，所以标签只能写「N 孔层」，写「第 N 槽」会和槽序号自相矛盾。
  // 三层是嵌套关系（1 孔层 ⊆ 2 孔层 ⊆ 3 孔层）。与 macOS 端 affixPoolLabel 同表。
  var POOL_LABELS = {
    100: "旧池 · 1 孔层",
    200: "旧池 · 2 孔层",
    300: "旧池 · 3 孔层",
    110: "1.03 · 1 孔层",
    210: "1.03 · 2 孔层",
    310: "1.03 · 3 孔层",
    2000000: "深夜 A 池",
    2100000: "深夜 B 池",
    2200000: "深夜 C 池",
    3000000: "深夜诅咒池"
  };

  // 与 macOS 端 affixPoolDetail 同表。
  var POOL_DETAILS = {
    2000000: "强力正面词条：同一行必定配一条深夜诅咒",
    2100000: "普通正面词条：同一行不带诅咒",
    2200000: "普通正面词条：同一行不带诅咒",
    3000000: "深夜遗物负面词条的唯一来源"
  };

  // ==================================================================
  // 纯逻辑（不依赖 DOM，node 下可单独测试）
  // ==================================================================

  function poolLabel(poolId) {
    return Object.prototype.hasOwnProperty.call(POOL_LABELS, poolId) ? POOL_LABELS[poolId] : "池 " + poolId;
  }

  function poolDetail(poolId) {
    return Object.prototype.hasOwnProperty.call(POOL_DETAILS, poolId) ? POOL_DETAILS[poolId] : "";
  }

  // 池标签是不是「池 <id>」这种兜底写法。是的话就别在旁边再打一遍「池 <id>」，
  // 物品表里有 588 个没有中文短名的槽位池，原来的写法会把同一串打两次。
  // 与 macOS 端 RelicSlotRow 的 `affixPoolLabel(id) != "池 \(id)"` 同一条判断。
  function poolLabelIsFallback(poolId) {
    return !Object.prototype.hasOwnProperty.call(POOL_LABELS, poolId);
  }

  // 结果被截断时的「共 N 件 / 已显示 M 件」。控件两端可以不同
  // （这边翻页、macOS 就地展开全部），但这句话必须逐字相同，
  // 否则同一份数据在两端读起来像两个结论。macOS 端 affixLookupHitCountText。
  function hitCountText(total, shown) {
    var visible = Math.max(0, Math.min(shown, total));
    if (visible >= total) return "共 " + total + " 件 · 已显示全部 " + total + " 件";
    return "共 " + total + " 件 · 已显示 " + visible + " 件（另有 " + (total - visible) + " 件未列出）";
  }

  // 深夜遗物一栏的结论文案（两端逐字一致；macOS 端 affixLookupDeepNote）。
  // 分支顺序固定：负面词条 → A 池（需诅咒）→ B/C 池 → 不在任何深夜池。
  // 诅咒词条本身不会 requiresCurse，所以先判 isCurse 不会吃掉 A 池那一支。
  function deepNoteText(deep) {
    var cursePoolId = deep && deep.cursePoolId !== undefined ? deep.cursePoolId : DEEP_CURSE_POOL_ID;
    var curseCount = deep && Array.isArray(deep.curses) ? deep.curses.length : 0;
    if (deep && deep.isCurse) {
      return "负面词条：只出现在深夜遗物带诅咒的那一行，与同一行的 A 池正面词条配对；" +
        "诅咒池（" + cursePoolId + "）共 " + curseCount + " 条。";
    }
    if (deep && deep.requiresCurse) {
      return "A 池词条：出货时这一行必定同时带一条深夜诅咒（诅咒池 " + cursePoolId +
        "，共 " + curseCount + " 条）。存档里这条词条没配诅咒即为改动。";
    }
    if (deep && deep.inAny) {
      return "B / C 池词条：深夜遗物可出，所在行不带诅咒。";
    }
    return "这条词条不在任何深夜词条池里，深夜遗物不会出它。";
  }

  // 互斥组里出现「不会出现在遗物上」的词条时的说明（两端逐字一致；
  // macOS 端 affixLookupUnreachableConflictNote）。
  var UNREACHABLE_CONFLICT_NOTE =
    "这条词条不会出现在任何遗物的槽位池里，不参与互斥判定：" +
    "互斥只约束「能同时出现在一件遗物上」的词条。";

  // compatibilityId = -1（参数表里就没给互斥池）时的说明（两端逐字一致；
  // macOS 端 affixLookupNoConflictGroupNote）。
  var NO_CONFLICT_GROUP_NOTE = "该词条没有互斥组，可与任意其他词条同时出现（仍不能与自身重复）。";

  // 互斥池里只有它自己时的说明（两端逐字一致；macOS 端 affixLookupLoneConflictNote）。
  function loneConflictNote(compatibilityId) {
    return "互斥池 " + compatibilityId + " 内只有这一条词条，没有互斥对象。";
  }

  // 互斥组一栏走哪一支：两端必须是同一条链（文案见上面几串，控件各自套）。
  //   1. unreachable：进不了任何槽位池 → UNREACHABLE_CONFLICT_NOTE
  //   2. noGroup：    compatibilityId = -1 → NO_CONFLICT_GROUP_NOTE
  //   3. peers：      有互斥对象 → 互斥组列表
  //   4. lone：       互斥池里只有自己 → loneConflictNote
  // 前两支的顺序不能反：仓库真实数据里有 148 条「不可达且 compatibilityId = -1」
  // 的效果（effectId 11001 / 12000 / 12001 / 12003 等），先判 -1 的那一端会说它
  //「可与任意其他词条同时出现」，先判不可达的那一端会说它「不参与互斥判定」，
  // 正好是相反的口径。两端都把不可达排在前面——它是更强的结论
  //（这条词条根本不会出现在遗物上，谈不上能不能和别的词条同时出现）。
  function conflictBranch(affix, reachable, peerCount) {
    if (!reachable) return "unreachable";
    if (!affix || affix.compatibilityId === -1 || affix.compatibilityId == null) return "noGroup";
    return peerCount > 0 ? "peers" : "lone";
  }

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

  function poolSizeIn(base, poolId) {
    var members = base.poolSets.get(poolId);
    return members ? members.size : 0;
  }

  function poolSize(index, poolId) {
    return poolSizeIn(index.base, poolId);
  }

  // 「正常游玩拿不到」的原因；空串表示正常可获得。判定口径与 core.js auditRelic
  // 的 illegalRange / outOfRange 两条规则一致（macOS 端 RelicLookupEntry.isObtainable
  // 同款）：作弊器区段的 72 件遗物槽位池全是空池，当成正常遗物列出来会让人
  // 以为某条词条「有遗物能出」。另外再挡掉参数表里的无名内部行与空池脏数据。
  function unobtainableReasonFor(base, meta) {
    if (meta.id >= CHEAT_ID_MIN && meta.id <= CHEAT_ID_MAX) return "作弊器常用 ID 区段（20000–30035）";
    if (meta.id < RELIC_ID_MIN || meta.id > RELIC_ID_MAX) return "超出合法 ID 区间（100–2013322）";
    if (!meta.name) return "参数表内部条目（没有官方名称）";
    var live = meta.slots.some(function (poolId) {
      return poolId !== -1 && poolSizeIn(base, poolId) > 0;
    });
    return live ? "" : "槽位池在数据集中是空池";
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
      var reason = unobtainableReasonFor(base, meta);
      return {
        id: meta.id,
        meta: meta,
        name: relicDisplayName(meta),
        named: Boolean(meta.name),
        kindLabel: kindLabel,
        colorLabel: Core.relicColorLabel(meta.color),
        unique: isUniqueRelicId(Core, meta.id),
        obtainable: reason === "",
        unobtainableReason: reason,
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
      obtainableCount: relicRows.filter(function (row) { return row.obtainable; }).length,
      poolRelicCount: new Map(),
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

  // 遗物搜索：名称 / ID / 种类。默认只给正常可获得的遗物（与 macOS 端
  // searchRelics(onlyObtainable:) 同口径）。
  function searchRelics(Core, index, query, options) {
    var settings = options || {};
    var limit = settings.limit || SEARCH_LIMIT;
    var includeUnobtainable = settings.includeUnobtainable === true;
    var onlyDeep = settings.onlyDeep === true;
    var needle = Core.foldForSearch(query || "");

    var matched = index.relicRows.filter(function (row) {
      if (!includeUnobtainable && !row.obtainable) return false;
      if (onlyDeep && !row.meta.deep) return false;
      return !needle || row.searchText.indexOf(needle) !== -1;
    });

    return {
      rows: matched.slice(0, limit),
      total: matched.length,
      truncated: matched.length > limit
    };
  }

  // 同 compatibilityId 的其他词条（同组不能同时出现）；compatibilityId 为 -1 时无互斥组。
  //
  // 口径与 core.js auditRelic §4.6 一致：参与互斥判定的是「能出现在遗物上的词条」，
  // 即词条库词条 ∪ 被某个槽位池引用的 extraAffixes。物品表里另有一千多条从不进
  // 任何槽位池的效果（庇佑等），它们共用参数表的默认 compatibilityId 100，
  // 列进来会把最大互斥组从 102 条撑到 1128 条，且没有任何遗物能同时带上它们。
  // index 为 null（遗物物品表不可用）时退回词条库内的同组词条。
  //
  // 互斥组必须是对称的：A 在 B 的组里 ⇔ B 在 A 的组里。所以「能不能出现在
  // 遗物上」这道关，查询方自己也要过一遍——否则一条永远进不了任何槽位池的
  // 词条会反查出整整一组互斥对象，而那一组里每一条都不认它。
  function appearsOnRelic(index, effectId) {
    if (!index) return true;
    return index.catalogIds.has(effectId) || index.effectPools.has(effectId);
  }

  function compatibilityPeers(Core, index, affix, catalog) {
    if (!affix || affix.compatibilityId === -1 || affix.compatibilityId == null) return [];
    if (!appearsOnRelic(index, affix.effectId)) return [];
    if (!index) {
      var affixes = catalog && Array.isArray(catalog.affixes) ? catalog.affixes : [];
      return sortAffixes(Core, affixes.filter(function (other) {
        return other.compatibilityId === affix.compatibilityId && other.effectId !== affix.effectId;
      }));
    }
    var peers = [];
    index.base.affixIndex.forEach(function (entry, effectId) {
      if (effectId === affix.effectId) return;
      if (entry.compatibilityId !== affix.compatibilityId) return;
      if (!appearsOnRelic(index, effectId)) return;
      peers.push(entry);
    });
    return sortAffixes(Core, peers);
  }

  // a) 普通随机遗物：按各校验口径的候选池判断能否掉落、落在哪几个池里。
  // 「顺序/互斥」口径不限定池（slotPoolPatterns 为空），不算掉落来源，故排除。
  //
  // 只报「池」不报「第几槽」：普通大遗物的池按孔数分层，3 孔遗物的 slots 是
  // [300, 200, 100]，把模板下标当槽序号打出来会和遗物详情里的「第 N 槽」自相矛盾；
  // 深夜口径更有 7 种模板。与 macOS 端 LookupModeHit 一样只列 mode.slotPoolIds。
  function modeSources(Core, index, effectId) {
    return Object.keys(Core.MODES).map(function (key) {
      var mode = Core.MODES[key];
      if (!mode.slotPoolPatterns.length) return null;

      var pools = mode.slotPoolIds.slice().sort(function (left, right) {
        return left - right;
      }).map(function (poolId) {
        return {
          poolId: poolId,
          label: poolLabel(poolId),
          detail: poolDetail(poolId),
          size: poolSize(index, poolId),
          relicCount: relicCountForPool(index, poolId),
          member: poolHas(index, poolId, effectId)
        };
      });

      return {
        key: key,
        title: mode.title,
        shortTitle: mode.shortTitle,
        detail: mode.detail,
        available: pools.some(function (entry) { return entry.member; }),
        pools: pools
      };
    }).filter(Boolean);
  }

  // 某个池被多少件「正常可获得」的遗物引用（正面槽 + 诅咒槽，按遗物去重）。
  function relicCountForPool(index, poolId) {
    if (index.poolRelicCount.has(poolId)) return index.poolRelicCount.get(poolId);
    var seen = new Set();
    (index.poolSlots.get(poolId) || []).forEach(function (ref) {
      var row = index.relicRowsById.get(ref.relicId);
      if (row && row.obtainable) seen.add(ref.relicId);
    });
    index.poolRelicCount.set(poolId, seen.size);
    return seen.size;
  }

  // b) 深夜遗物：A/B/C 三池归属；A 池词条需要在同一行搭配诅咒池里的负面词条。
  //
  // 口径与 core.js auditDeepRelic / RelicAudit 一致：A 池词条与诅咒按存档里的
  // effects[i] / curses[i] 位置配对（「这一行的正面词条需诅咒 ⇔ 这一行带负面词条」），
  // 槽位模板只保证「A 槽数 = 诅咒槽数」，不能反过来断言某一槽必定是 A 池。
  function deepSources(Core, index, effectId) {
    var affix = affixOf(index, effectId);
    var pools = DEEP_POOL_IDS.map(function (poolId) {
      return {
        poolId: poolId,
        label: poolLabel(poolId),
        detail: poolDetail(poolId),
        size: poolSize(index, poolId),
        relicCount: relicCountForPool(index, poolId),
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
      cursePool: {
        poolId: DEEP_CURSE_POOL_ID,
        label: poolLabel(DEEP_CURSE_POOL_ID),
        detail: poolDetail(DEEP_CURSE_POOL_ID),
        size: poolSize(index, DEEP_CURSE_POOL_ID),
        relicCount: relicCountForPool(index, DEEP_CURSE_POOL_ID),
        member: poolHas(index, DEEP_CURSE_POOL_ID, effectId)
      },
      curses: curses
    };
  }

  // c) 遍历遗物表：列出所有 slots / curseSlots 指向的池子里包含该词条的遗物。
  // 池子只有一个成员即「固定词条」，否则是「随机池可出」。结果按 effectId 缓存。
  //
  // 正常游玩拿不到的条目（作弊器区段 / 超范围 / 无名参数行 / 空池）一律不列出，
  // 只计入 hidden；与 macOS 端 AffixLookupReport.hiddenRelicCount 同口径。
  // 命中记录按「遗物 + 正面槽/诅咒槽」聚合，只报命中的池、不报槽序号
  // （槽序号对普通遗物与孔数层池对不上号，对深夜遗物与游戏实际生成不符）。
  function relicSourcesFor(index, effectId) {
    if (index.sourceCache.has(effectId)) return index.sourceCache.get(effectId);

    var byKey = new Map();
    (index.effectPools.get(effectId) || []).forEach(function (poolId) {
      var size = poolSize(index, poolId);
      (index.poolSlots.get(poolId) || []).forEach(function (ref) {
        var key = ref.relicId + ":" + ref.kind;
        var row = byKey.get(key);
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
            obtainable: base.obtainable,
            role: ref.kind,
            fixed: false,
            poolIds: []
          };
          byKey.set(key, row);
        }
        if (row.poolIds.indexOf(poolId) === -1) row.poolIds.push(poolId);
        if (size === 1) row.fixed = true;
      });
    });

    var fixed = [];
    var random = [];
    var hidden = 0;
    byKey.forEach(function (row) {
      if (!row.obtainable) { hidden += 1; return; }
      row.poolIds.sort(function (left, right) { return left - right; });
      (row.fixed ? fixed : random).push(row);
    });
    var byId = function (left, right) { return left.id - right.id; };
    fixed.sort(byId);
    random.sort(byId);

    var result = Object.freeze({
      fixed: fixed,
      random: random,
      total: fixed.length + random.length,
      hidden: hidden
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

    function describeSlot(slot) {
      var poolId = meta.slots[slot];
      var cursePoolId = meta.curseSlots[slot];
      var base = {
        slot: slot,
        poolId: poolId,
        label: poolId === -1 ? "" : poolLabel(poolId),
        cursePoolId: cursePoolId,
        curseSize: cursePoolId === -1 ? 0 : poolSize(index, cursePoolId)
      };
      if (poolId === -1) {
        base.empty = true;
        base.size = 0;
        base.fixed = false;
        base.preview = [];
        base.more = 0;
        return base;
      }
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
      base.empty = names.length === 0;
      base.size = names.length;
      base.fixed = names.length === 1;
      base.preview = names.slice(0, limit);
      base.more = Math.max(0, names.length - limit);
      return base;
    }

    var slots = [0, 1, 2].map(describeSlot);

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

    // 深夜遗物：按池 id 归并展示，不给槽序号。参数表里深夜遗物的行排列与游戏
    // 实际生成不符（例如 2013212「辽阔的光耀暗淡情景」记录为 CCC 且无诅咒槽），
    // 存档里的正面词条又按 (sortId, effectId) 升序保存，两者没有对应关系；
    // 一旦打出「第 N 槽」，用户就会拿存档第 N 行去对，结论必然是错的。
    // 与 macOS 端 RelicLookupDetailPane.deepPoolGroups 同款。
    var poolGroups = null;
    if (meta.deep) {
      var groupById = new Map();
      slots.forEach(function (entry) {
        if (entry.poolId === -1) return;
        var group = groupById.get(entry.poolId);
        if (!group) {
          group = { poolId: entry.poolId, count: 0, slot: entry };
          groupById.set(entry.poolId, group);
        }
        group.count += 1;
      });
      poolGroups = Array.from(groupById.keys()).sort(function (left, right) {
        return left - right;
      }).map(function (poolId) { return groupById.get(poolId); });
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
      obtainable: base.obtainable,
      unobtainableReason: base.unobtainableReason,
      slotCount: slots.filter(function (entry) { return entry.poolId !== -1; }).length,
      curseSlotCount: slots.filter(function (entry) { return entry.cursePoolId !== -1; }).length,
      slots: slots,
      poolGroups: poolGroups,
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
    poolLabel: poolLabel,
    poolDetail: poolDetail,
    poolLabelIsFallback: poolLabelIsFallback,
    appearsOnRelic: appearsOnRelic,
    hitCountText: hitCountText,
    deepNoteText: deepNoteText,
    conflictBranch: conflictBranch,
    loneConflictNote: loneConflictNote,
    UNREACHABLE_CONFLICT_NOTE: UNREACHABLE_CONFLICT_NOTE,
    NO_CONFLICT_GROUP_NOTE: NO_CONFLICT_GROUP_NOTE,
    ROW_LIMIT: ROW_LIMIT,
    SEARCH_LIMIT: SEARCH_LIMIT,
    SLOT_PREVIEW: SLOT_PREVIEW,
    PEER_PREVIEW: PEER_PREVIEW,
    CHEAT_ID_MIN: CHEAT_ID_MIN,
    CHEAT_ID_MAX: CHEAT_ID_MAX,
    RELIC_ID_MIN: RELIC_ID_MIN,
    RELIC_ID_MAX: RELIC_ID_MAX
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
      relicOnlyDeep: false
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
        "<div><h2>遗物搜索</h2><p>按遗物名或 ID 查看每个槽位的词条池；唯一遗物还会给出官方固定词条</p></div></div>" +
        "<div class='lookup-filter-row'>" +
        "<label class='search-field lookup-search'><span aria-hidden='true'>⌕</span>" +
        "<input type='search' autocomplete='off' placeholder='搜索遗物名称、ID 或种类' data-testid='lookup-relic-search'></label>" +
        "<label class='switch-control'><input type='checkbox' data-lookup-toggle='relicOnlyDeep' data-testid='lookup-relic-only-deep'>" +
        "<span class='switch-track'></span><span>只看深夜遗物</span></label>" +
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
        parts.push(pill("可查遗物 " + index.obtainableCount + " 件 · 池 " + index.base.poolSets.size + " 个", "purple"));
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
      var index = lookupIndex();
      var peers = compatibilityPeers(context.Core, index, affix, context.catalog);

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

      var peerEntry = function (peer) {
        return index
          ? affixEntry(index, peer.effectId)
          : { effectId: peer.effectId, name: peer.name || ("词条 #" + peer.effectId), inCatalog: true };
      };
      var extraPeerCount = index
        ? peers.filter(function (peer) { return !isCatalogAffix(index, peer.effectId); }).length
        : 0;
      var peersHtml;
      var branch = conflictBranch(affix, appearsOnRelic(index, affix.effectId), peers.length);
      if (branch === "unreachable") {
        // 互斥组是对称的：这条词条进不了任何槽位池，也就不进任何互斥组。
        // 两端都把原因写出来，而不是一侧显示整组、另一侧连提都不提。
        peersHtml = "<p class='lookup-note' data-testid='lookup-peers-unreachable'>" +
          esc(UNREACHABLE_CONFLICT_NOTE) + "</p>";
      } else if (branch === "noGroup") {
        peersHtml = "<p class='lookup-note' data-testid='lookup-peers-no-group'>" +
          esc(NO_CONFLICT_GROUP_NOTE) + "</p>";
      } else if (branch === "peers") {
        peersHtml = "<p class='lookup-note'>同一互斥池（" + affix.compatibilityId + "）内的词条不能同时出现在一件遗物上，共 " +
          (peers.length + 1) + " 条" +
          (extraPeerCount > 0 ? "（其中 " + extraPeerCount + " 条只见于遗物参数表）" : "") +
          "：</p><div class='lookup-chiplist lookup-chiplist--scroll' data-testid='lookup-peers'>" +
          peersShown.map(function (peer) {
            return affixChip(peerEntry(peer));
          }).join("") + "</div>" + peersToggle +
          (extraPeerCount > 0 ? extraAffixNote(peersShown.map(peerEntry)) : "");
      } else {
        peersHtml = "<p class='lookup-note' data-testid='lookup-peers-lone'>" +
          esc(loneConflictNote(affix.compatibilityId)) + "</p>";
      }

      // 深夜结论只在下面「能在哪出」卡片的「深夜遗物」一栏说一次（那里还带着
      // A/B/C 三池与诅咒池的命中情况）。这里原来也有一块「深夜相关」，
      // 两端文案统一之后就成了同一屏里一字不差地说两遍，与 macOS 的单张
      // deepCard 也对不上，所以撤掉。

      node.innerHTML = "<article class='card lookup-card' data-testid='lookup-detail-card'>" +
        "<div class='section-heading'><div class='section-icon section-icon--green'>◈</div>" +
        "<div><h2>" + esc(affix.name) + "</h2><p>" + esc(affix.explanation || "数据集未提供该词条的说明") + "</p></div></div>" +
        "<div class='lookup-taglist'>" + tags + "</div>" +
        "<dl class='data-lines lookup-lines'>" + lines + "</dl>" +
        "<div class='lookup-block'><h3>互斥组</h3>" + peersHtml + "</div>" +
        "</article>";
    }

    // 槽位池只按「池」展示，不打槽序号：普通大遗物按孔数分层取池，
    // 3 孔遗物的 slots 是 [300, 200, 100]，模板下标不是槽序号。
    // 池标签 + 池的补充说明（深夜 A/B/C 池的出货规则）+ 规模。
    // 说明此前只算不画：深夜三池在 macOS 上各有一行小字，这边什么都没有，
    // 同一个池在两端读起来像两回事。与 macOS 端 LookupPoolRow 同一套三段。
    //
    // meta 一律写「池 <id> · N 条 · M 件遗物」，与 macOS 端 LookupPoolRow 逐字一致。
    // 上一轮在这里也套了兜底判断，于是没有中文短名的池在 Windows 只写
    //「N 条 · M 件遗物」、macOS 仍写「池 <id> · …」，同一行在两端又不一样了。
    //「兜底标签旁边不再重复打一遍 id」那条判断只用在 slotBlock 的那枚 pill 上
    //（macOS 的 RelicSlotRow 早有同样判断，那一处两端本来就一致）。
    function poolChips(pools) {
      return pools.map(function (pool) {
        var meta = "池 " + pool.poolId + " · " + pool.size + " 条 · " + pool.relicCount + " 件遗物";
        return "<span class='lookup-slot-chip" + (pool.member ? " is-on" : "") + "'>" +
          esc(pool.label) +
          (pool.detail ? "<span class='lookup-slot-chip-detail'>" + esc(pool.detail) + "</span>" : "") +
          "<span>" + esc(meta) + "</span></span>";
      }).join("");
    }

    function relicWhereLabel(row) {
      return (row.role === "curse" ? "诅咒槽" : "正面槽") + "（" +
        row.poolIds.map(function (poolId) { return poolLabel(poolId); }).join(" / ") + "）";
    }

    function relicSourceRow(row) {
      return "<tr data-testid='lookup-source-row'>" +
        "<td><button type='button' class='lookup-linkish' data-relic-id='" + row.id + "'>" + esc(row.name) + "</button></td>" +
        "<td class='lookup-num'>" + row.id + "</td>" +
        "<td>" + esc(row.kindLabel) + "</td>" +
        "<td>" + pill(row.colorLabel, COLOR_PILLS[row.color] || "gray") + "</td>" +
        "<td class='lookup-where'>" + esc(relicWhereLabel(row)) + "</td>" +
        "</tr>";
    }

    function relicTable(rows, testId) {
      if (!rows.length) return "";
      return "<div class='table-wrap lookup-table-wrap'><table class='library-table lookup-table' data-testid='" + testId + "'>" +
        "<thead><tr><th>遗物</th><th class='lookup-num'>ID</th><th>种类</th><th>颜色</th><th>命中的池</th></tr></thead>" +
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

      // a) 普通随机遗物：逐口径说明（只报池，不报槽序号）
      var modeRows = modes.map(function (entry) {
        return "<tr data-testid='lookup-mode-row' data-mode='" + entry.key + "'>" +
          "<td><strong>" + esc(entry.title) + "</strong><p class='lookup-sub'>" + esc(entry.detail) + "</p></td>" +
          "<td>" + (entry.available ? pill("可掉落", "green") : pill("不掉落", "gray")) + "</td>" +
          "<td class='lookup-slotcell'>" + poolChips(entry.pools) + "</td>" +
          "</tr>";
      }).join("");
      var tierNote = "<p class='lookup-note lookup-note--muted' data-testid='lookup-tier-note'>" +
        "普通大遗物按孔数分层取池：1 孔取 1 孔层池，2 孔取 2 孔层 + 1 孔层，3 孔取 3 / 2 / 1 孔层。" +
        "三层是嵌套关系（大池包含小池），层号指的是孔数，不是槽位的先后顺序。</p>";

      // b) 深夜遗物：口径与 core.js auditDeepRelic 一致 —— 按行配对，不按槽序号
      var deepBody = "<div class='lookup-chipbar'>" +
        poolChips(deep.pools.concat([deep.cursePool])) + "</div>" +
        "<p class='lookup-note' data-testid='lookup-deep-note-text'>" + esc(deepNoteText(deep)) + "</p>";
      if (!deep.isCurse && deep.requiresCurse) {
        deepBody += "<div class='lookup-chiplist' data-testid='lookup-curses'>" +
          deep.curses.map(function (curse) {
            return affixChip(affixEntry(index, curse.effectId));
          }).join("") + "</div>";
      }

      // c) 固定 / 唯一遗物与随机池出处。
      // 不会正常获得的条目（作弊器区段 / 超范围 / 无名参数行 / 空池）已在
      // relicSourcesFor 里剔除，这里只需把条数说清楚。
      var fixedRows = sources.fixed;
      var allRandomRows = sources.random;
      var randomRows = state.onlyFixed ? [] : allRandomRows;
      var paged = paginate(randomRows, state.sourcePage, ROW_LIMIT);
      state.sourcePage = paged.page;

      var relicBody = "<div class='lookup-filter-row lookup-filter-row--tight'>" +
        "<label class='switch-control'><input type='checkbox' data-lookup-toggle='onlyFixed'" + (state.onlyFixed ? " checked" : "") +
        " data-testid='lookup-only-fixed'><span class='switch-track'></span><span>只看固定词条</span></label>" +
        // 「只看固定词条」开着时随机池表格整块不渲染，计数行要说明它是被折叠而不是漏渲染
        "<span class='lookup-count' data-testid='lookup-source-count'>固定 " + fixedRows.length + " 件 · 随机池 " +
        allRandomRows.length + " 件" + (state.onlyFixed ? "（已折叠）" : "") + "</span>" +
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
          // 「共 N 件 · 已显示 M 件」与 macOS 端逐字相同；控件不同（那边是
          // 「展开全部」，这边翻页）没关系，计数口径必须一样。
          //
          // 传的是 paged.to（已显示到第几件）而不是本页行数：macOS 的
          // affixLookupHitCountText(total:shown:) 是「前 M 件 / 共 N 件」的累计口径。
          // 按本页行数写，第 2 页会再写一遍「已显示 200 件（另有 232 件未列出）」，
          // 末页更会和紧挨着的副标题「第 401–432 件（第 3 / 3 页）」直接打架。
          var countLine = "<span data-testid='lookup-hit-count'>" +
            esc(hitCountText(paged.total, paged.to)) + "</span>";
          if (paged.pageCount > 1) {
            relicBody += "<div class='lookup-pager' data-testid='lookup-pager'>" +
              "<button type='button' class='button button--secondary' data-lookup-page='prev'" +
              (paged.page === 0 ? " disabled" : "") + ">上一页</button>" +
              countLine +
              "<span class='lookup-sub'>第 " + paged.from + "–" + paged.to + " 件（第 " +
              (paged.page + 1) + " / " + paged.pageCount + " 页）</span>" +
              "<button type='button' class='button button--secondary' data-lookup-page='next'" +
              (paged.page >= paged.pageCount - 1 ? " disabled" : "") + ">下一页</button>" +
              "</div>";
          } else {
            relicBody += "<div class='lookup-pager'>" + countLine + "</div>";
          }
        }
      }

      // 与 macOS 端 hiddenRelicCount 的提示同文案：说清楚被挡掉的是哪几类条目
      if (sources.hidden > 0) {
        relicBody += "<p class='lookup-note lookup-note--muted' data-testid='lookup-source-hidden'>" +
          "另有 " + sources.hidden + " 条不会正常获得的物品表条目未列出：" +
          "超出合法 ID 区间 / 没有名称的参数行（调试、未启用条目），以及 20000–30035 作弊器区段的遗物。</p>";
      }

      node.innerHTML = "<article class='card lookup-card' data-testid='lookup-sources-card'>" +
        "<div class='section-heading'><div class='section-icon'>⌖</div>" +
        "<div><h2>能在哪出</h2><p>按出货口径、深夜池与具体遗物三层展开</p></div></div>" +

        "<div class='lookup-block'><h3>普通随机遗物</h3>" +
        "<div class='table-wrap lookup-table-wrap'><table class='library-table lookup-table' data-testid='lookup-mode-table'>" +
        "<thead><tr><th>校验口径</th><th>能否掉落</th><th>候选池</th></tr></thead><tbody>" + modeRows +
        "</tbody></table></div>" + tierNote + "</div>" +

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
        onlyDeep: state.relicOnlyDeep
      });
      if (!found.rows.length) {
        node.innerHTML = "<div class='empty-state lookup-empty' data-testid='lookup-relic-empty'><div class='empty-icon'>⌕</div>" +
          "<h3>没有匹配遗物</h3><p>请更换关键词；正常游玩拿不到的参数表条目（作弊器区段等）本页不收录</p></div>";
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

    // 一个槽位（或深夜遗物的一组同池槽位）的词条池。
    // title 由调用方给：普通遗物用「第 N 槽」，深夜遗物用「本件 N 条」——
    // 参数表的深夜行序对不上游戏实际生成，不能打出槽序号。
    function slotBlock(entry, title) {
      if (entry.poolId === -1) {
        return "<div class='lookup-slotbox is-muted'><div class='lookup-slotbox-head'><strong>" + esc(title) + "</strong>" +
          pill("没有这个槽", "gray") + "</div></div>";
      }
      // 具名池（深夜 A/B/C 等）的标签里没有 id，这里补上；兜底标签本身就是
      // 「池 xxx」，再打一枚就成了「池 501100000 池 501100000」。
      // 与 macOS 端 RelicSlotRow 的同一条判断。
      var head = "<div class='lookup-slotbox-head'><strong>" + esc(title) + "</strong>" +
        pill(entry.label, "purple") +
        (poolLabelIsFallback(entry.poolId) ? "" : pill("池 " + entry.poolId, "gray")) +
        pill(entry.fixed ? "固定 1 条" : "随机 " + entry.size + " 条", entry.fixed ? "green" : "blue") +
        (entry.cursePoolId !== -1 ? pill("配诅咒 · " + entry.curseSize + " 条", "amber") : "") +
        "</div>";
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
            "<h3>先选一件遗物</h3><p>选中后显示每个槽位池的成员数与词条；深夜遗物按池展示，不给槽位顺序</p></div></article>"
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
      var slotItems = summary.slots.reduce(function (all, entry) {
        return all.concat(entry.preview || []);
      }, summary.fixedEffects || []);

      // 深夜遗物只给池构成、不给槽位顺序（口径与 macOS 端 deepPoolGroups 一致）
      var slotsBlock;
      if (summary.deep) {
        slotsBlock = "<div class='lookup-block'><h3>槽位池</h3><div class='lookup-slotgrid' data-testid='lookup-deep-groups'>" +
          summary.poolGroups.map(function (group) {
            return slotBlock(group.slot, "本件 " + group.count + " 条");
          }).join("") + "</div>" +
          "<p class='lookup-note lookup-note--muted' data-testid='lookup-deep-note'>" +
          "深夜遗物只给池构成、不给槽位顺序：参数表里深夜遗物的行排列与游戏实际生成不符" +
          "（例如 2013212「辽阔的光耀暗淡情景」记录为 CCC 且没有诅咒槽），" +
          "存档里的正面词条又是按保存顺序（sortId 升序）排的，两者没有对应关系。" +
          "某件深夜遗物是否合法，请以「存档检查」页的按行配对判定为准。</p></div>";
      } else {
        slotsBlock = "<div class='lookup-block'><h3>正面词条槽</h3><div class='lookup-slotgrid'>" +
          summary.slots.map(function (entry) {
            return slotBlock(entry, SLOT_LABELS[entry.slot]);
          }).join("") + "</div></div>";
      }

      node.innerHTML = "<article class='card lookup-card' data-testid='lookup-relic-card'>" +
        "<div class='section-heading'><div class='section-icon section-icon--green'>▤</div>" +
        "<div><h2>" + esc(summary.name) + "</h2><p>" +
        (summary.deep
          ? "深夜遗物的正面词条按池配对：A 池词条必定同时带一条深夜诅咒"
          : "每个槽位从自己的池里抽一条正面词条") +
        "</p></div></div>" +
        "<div class='lookup-taglist'>" + tags + "</div>" +
        fixedBlock +
        slotsBlock +
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
        "<li>普通大遗物的池按<strong>孔数</strong>分层（1 孔层 ⊆ 2 孔层 ⊆ 3 孔层），层号不是槽序号：" +
        "3 孔遗物的槽位池依次是 3 / 2 / 1 孔层，所以本页的池标签一律写「N 孔层」。</li>" +
        "<li>深夜遗物在参数表里记录的槽池排列与游戏实际生成不符，不能作为深夜校验依据" +
        "（例如遗物 2013212「辽阔的光耀暗淡情景」记录为 CCC 且没有诅咒槽）；" +
        "本页按 core.js 的 A/B/C 池并集与「同一行的正面词条需诅咒 ⇔ 这一行带负面词条」口径说明，" +
        "槽位模板只保证「A 槽数 = 诅咒槽数」。</li>" +
        "<li>正常游玩拿不到的物品表条目一律不列出：20000–30035 作弊器区段（" +
        "与「存档检查」的 illegalRange 判定同口径，这 72 件的槽位池是空池）、" +
        "超出 100–2013322 的参数行，以及没有官方名称的内部条目（多为词条道具本体）。</li>" +
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
        // 「只看深夜遗物」开着时跳到普通遗物，得先把筛选放开
        if (row && !row.meta.deep && state.relicOnlyDeep) {
          state.relicOnlyDeep = false;
          var toggle = dom.querySelector("[data-testid='lookup-relic-only-deep']");
          if (toggle) toggle.checked = false;
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
        if (name === "relicOnlyDeep") {
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
