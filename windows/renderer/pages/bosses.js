// 首领数据页。页面模块契约见 renderer/pages/README.md。
// 本文件由「首领数据」功能开发者独占：只改这里与 pages/bosses.css。
//
// 数据：ctx.getGameData("bosses") → resources/bosses.json（bossesSchemaVersion 2）。
// 数值口径（务必与数据集说明一致）：
//   · hp 已经含常驻缩放（= hpBase × hpMultiplier），多人血量 = hp × scaling.<duo|trio>.hp
//   · 有效韧性 = poise / (poiseTakenBase × scaling.<tier>.poiseTaken)
//   · 削韧恢复 = poiseRecover × poiseRecoverMultiplier × scaling.<tier>.poiseRecover
//   · 异常发动伤害 = ailmentDamageRateBase × scaling.<tier>.ailmentDamageRate
//   · buildupRate 是 Boss 承受的异常累积量倍率（越小越难打出异常），resist 是累积阈值
//   · nightBosses 的主键是 id；永夜之王等变体用 variantKey / variantNameZh
(function (root) {
  "use strict";

  var PAGE_KEY = "bosses";
  var DATA_NAME = "bosses";

  // ---------------------------------------------------------------- 常量表

  var DAMAGE_TYPES = [
    { key: "standard", zh: "标准" },
    { key: "slash", zh: "斩击" },
    { key: "strike", zh: "打击" },
    { key: "pierce", zh: "突刺" },
    { key: "magic", zh: "魔力" },
    { key: "fire", zh: "火" },
    { key: "lightning", zh: "雷" },
    { key: "holy", zh: "圣" }
  ];

  var AILMENTS = [
    { key: "poison", zh: "中毒" },
    { key: "rot", zh: "猩红腐败" },
    { key: "bleed", zh: "出血" },
    { key: "frost", zh: "冻伤" },
    { key: "sleep", zh: "睡眠" },
    { key: "madness", zh: "发狂" },
    { key: "death", zh: "死亡" }
  ];

  var GROUP_LABELS = {
    "Field Boss Threat": "野外首领威胁档",
    "Night Boss Threat": "守夜首领威胁档",
    "Final Boss Threat": "最终首领威胁档"
  };

  // 分组名两端一致（macOS 端 BossCard.Group.title）：顶部筛选、卡头徽标都用它。
  // 行内的威胁档位徽标另用短名「守夜 / 野外」，与 macOS 的 threatTitle 对应。
  var GROUP_TITLES = {
    nightlords: "夜王",
    night: "守夜首领",
    field: "野外首领"
  };

  var TABS = [
    { key: "nightlords", label: GROUP_TITLES.nightlords },
    { key: "night", label: GROUP_TITLES.night },
    { key: "field", label: GROUP_TITLES.field }
  ];

  var PARTY_OPTIONS = [
    { value: 1, label: "1 人" },
    { value: 2, label: "2 人" },
    { value: 3, label: "3 人" }
  ];

  var VARIANT_PILL = {
    everdark: { text: "永夜之王", kind: "purple" },
    standardBearers: { text: "救世旗手", kind: "blue" },
    unknown: { text: "未知变体", kind: "gray" }
  };

  // -------------------------------------------------------------- 纯计算层
  // 以下函数不碰 DOM，windows/tests/bosses.test.mjs 直接 require 本文件测试。

  function tierKey(party) {
    if (party === 2) return "duo";
    if (party === 3) return "trio";
    return null;
  }

  // 深夜模式下换用 deepOfNight 里的同一组数值；没有深夜专属缩放时回落到常规值。
  function numbersFor(entry, deep) {
    var deepNums = deep && entry && entry.deepOfNight ? entry.deepOfNight : null;
    var source = deepNums || entry || {};
    return {
      isDeep: Boolean(deepNums),
      hp: Number(source.hp) || 0,
      hpMultiplier: Number(source.hpMultiplier) || 1,
      poiseTakenBase: Number(source.poiseTakenBase) || 1,
      poiseRecoverMultiplier: Number(source.poiseRecoverMultiplier) || 1,
      ailmentDamageRateBase: Number(source.ailmentDamageRateBase) || 0,
      permScalingIds: Array.isArray(source.permScalingIds) ? source.permScalingIds : []
    };
  }

  function scalingFor(entry, party) {
    var key = tierKey(party);
    if (!key) return null;
    var scaling = entry && entry.scaling;
    return scaling && scaling[key] ? scaling[key] : null;
  }

  // 一条 fight / variant 在给定人数、深夜开关下的最终数值。
  function computeStats(entry, party, deep) {
    var nums = numbersFor(entry, deep);
    var tier = scalingFor(entry, party);
    var hpMul = tier ? Number(tier.hp) || 1 : 1;
    var poiseTakenMul = tier ? Number(tier.poiseTaken) || 1 : 1;
    var poiseRecoverMul = tier ? Number(tier.poiseRecover) || 1 : 1;
    var buildupMul = tier ? Number(tier.buildupRate) || 1 : 1;
    var ailmentMul = tier ? Number(tier.ailmentDamageRate) || 1 : 1;
    var poiseTakenTotal = nums.poiseTakenBase * poiseTakenMul;
    var poise = Number(entry && entry.poise);
    // poise < 0（数据集 caveat 3：一般是子弹/投射物实体）= 不吃削韧；
    // poise === 0 是另一回事（该实体没有削韧槽），不能和 -1 一起显示成「有效韧性 0」。
    var poiseKind = !isFinite(poise) || poise < 0 ? "none" : (poise === 0 ? "zero" : "value");
    var noPoise = poiseKind !== "value";
    return {
      isDeep: nums.isDeep,
      tier: tier,
      tierKey: tierKey(party),
      hp: Math.round(nums.hp * hpMul),
      hpSingle: nums.hp,
      hpBase: Number(entry && entry.hpBase) || 0,
      hpMultiplier: nums.hpMultiplier,
      poise: noPoise ? null : poise,
      poiseKind: poiseKind,
      poiseTakenTotal: poiseTakenTotal,
      effectivePoise: noPoise || !poiseTakenTotal ? null : poise / poiseTakenTotal,
      poiseRecover: (Number(entry && entry.poiseRecover) || 0) * nums.poiseRecoverMultiplier * poiseRecoverMul,
      ailmentDamageRate: nums.ailmentDamageRateBase * ailmentMul,
      buildupRate: buildupMul,
      poisonRate: tier ? Number(tier.poisonRate) || 1 : 1,
      permScalingIds: nums.permScalingIds
    };
  }

  // 承伤倍率：> 1 多吃伤害（弱点），< 1 抗性，= 1 正常。
  function rateClass(rate) {
    var value = Number(rate);
    if (!isFinite(value) || value === 1) return "flat";
    return value > 1 ? "up" : "down";
  }

  function rateNote(rate) {
    var kind = rateClass(rate);
    if (kind === "up") return "弱点";
    if (kind === "down") return "抗性";
    return "";
  }

  function isImmune(value) {
    return Number(value) >= 999;
  }

  // 名字缺失（english-only / chrid-fallback）时的显示口径。
  function displayName(boss) {
    var zh = boss && boss.nameZh ? String(boss.nameZh) : "";
    var en = boss && boss.nameEn ? String(boss.nameEn) : "";
    var source = boss && boss.nameSource ? String(boss.nameSource) : "";
    if (zh) {
      return {
        primary: zh,
        secondary: en && en !== zh ? en : "",
        fallback: source === "chrid-fallback",
        inferred: Boolean(boss && boss.nameInferred)
      };
    }
    return {
      primary: en || "未知敌人",
      secondary: "",
      fallback: true,
      inferred: Boolean(boss && boss.nameInferred)
    };
  }

  function nameBadge(info, nameSource) {
    if (info.fallback) {
      if (nameSource === "english-only") return { text: "仅英文名", kind: "gray" };
      return { text: "无游戏内名称", kind: "gray" };
    }
    if (nameSource === "manual") return { text: "名称手工补录", kind: "gray" };
    if (info.inferred) return { text: "名称按 ID 推断", kind: "gray" };
    return null;
  }

  function entryLabel(entry, index) {
    var label = entry && entry.labelZh ? String(entry.labelZh) : "";
    if (label) return label;
    if (entry && entry.labelEn) return String(entry.labelEn);
    return "变体 " + (index + 1);
  }

  // 某个分组下参与「代表行」评选的候选行。两步过滤，任一步没有候选就原样放行：
  //   1. 守夜 / 野外分组先按 threat 过滤——同一组首领可能两种档位都有（数据里 6 组），
  //      在「野外」分组下就该看野外那几行，而不是血量更高的守夜行；
  //   2. 再收敛到 isMain（夜王的主战行**不唯一**，多阶段 / 多体有 2～5 条）。
  function candidateEntries(entries, group) {
    var pool = Array.isArray(entries) ? entries.filter(Boolean) : [];
    if (group === "night" || group === "field") {
      var byThreat = pool.filter(function (entry) { return entry.threat === group; });
      if (byThreat.length) pool = byThreat;
    }
    var mains = pool.filter(function (entry) { return entry.isMain; });
    return mains.length ? mains : pool;
  }

  // 候选行里血量最高的一条（同血量取 npcId 较小者）。排序用 1 人基准血量，
  // 与当前人数 / 深夜开关无关，保证头条行不会跟着设置跳。
  function representativeEntry(entries, group) {
    var pool = candidateEntries(entries, group);
    var best = null;
    pool.forEach(function (entry) {
      if (!best) { best = entry; return; }
      var hp = Number(entry.hp) || 0;
      var bestHp = Number(best.hp) || 0;
      if (hp !== bestHp) {
        if (hp > bestHp) best = entry;
        return;
      }
      if ((Number(entry.npcId) || 0) < (Number(best.npcId) || 0)) best = entry;
    });
    return best;
  }

  // 不区分分组的代表行（夜王卡片用；守夜 / 野外请用 representativeEntry 带上分组）。
  function mainEntry(entries) {
    return representativeEntry(entries, null);
  }

  function mainRows(entries) {
    return (Array.isArray(entries) ? entries : []).filter(function (entry) {
      return entry && entry.isMain;
    });
  }

  function joinSearch(parts) {
    return parts.filter(function (part) {
      return part !== null && part !== undefined && part !== "";
    }).join("\n");
  }

  // 可按行号搜索的数字串（npcId / chrId / NpcName ID）。纯数字查询走前缀匹配，
  // 所以这些值不能混进全文搜索串——否则「1」「50」会命中全表。
  function numberKeys(values) {
    var out = [];
    values.forEach(function (value) {
      if (value === null || value === undefined || value === "") return;
      var text = String(value);
      if (out.indexOf(text) === -1) out.push(text);
    });
    return out;
  }

  function entryNumbers(entries) {
    var out = [];
    (Array.isArray(entries) ? entries : []).forEach(function (entry) {
      if (!entry) return;
      var ids = Array.isArray(entry.npcIds) && entry.npcIds.length ? entry.npcIds : [entry.npcId];
      ids.forEach(function (id) { out.push(id); });
    });
    return out;
  }

  function defaultFold(value) {
    return String(value == null ? "" : value).toLowerCase();
  }

  // 一个 Boss 可能同时属于守夜与野外（数据里 tiers = ["field","night"] 的有 6 组，
  // 而 tier 只保留一个），所以分组一律按 tiers 判定，卡片允许同时出现在两个分组里。
  function bossGroups(boss) {
    var raw = boss && Array.isArray(boss.tiers) && boss.tiers.length
      ? boss.tiers
      : [boss && boss.tier];
    var out = [];
    raw.forEach(function (tier) {
      var key = tier === "night" ? "night" : (tier === "field" ? "field" : null);
      if (key && out.indexOf(key) === -1) out.push(key);
    });
    if (!out.length) out.push(boss && boss.tier === "night" ? "night" : "field");
    // 主分组沿用 tier，方便卡头徽标与默认排序。
    var primary = boss && boss.tier === "night" ? "night" : "field";
    if (out.indexOf(primary) > 0) {
      out.splice(out.indexOf(primary), 1);
      out.unshift(primary);
    }
    return out;
  }

  // 整张卡片的深夜覆盖情况：all = 每条数值行都有深夜专属缩放，some = 部分行有，none = 都没有。
  // 只看代表行会把「格诺斯塔·永夜之王」这类首条 isMain 无深夜值、其余行有的卡片判错。
  function deepCoverage(item) {
    var entries = item && Array.isArray(item.entries) ? item.entries : [];
    if (!entries.length) return "none";
    var hit = 0;
    entries.forEach(function (entry) { if (entry && entry.deepOfNight) hit += 1; });
    if (!hit) return "none";
    return hit === entries.length ? "all" : "some";
  }

  // 把数据集拍平成页面用的卡片列表；fold 用 ctx.helpers.foldForSearch（测试里传 Core.foldForSearch）。
  function buildItems(data, fold) {
    var folder = typeof fold === "function" ? fold : defaultFold;
    var items = [];
    if (!data || typeof data !== "object") return items;

    (Array.isArray(data.nightlords) ? data.nightlords : []).forEach(function (lord) {
      var entries = Array.isArray(lord.fights) ? lord.fights : [];
      var variant = VARIANT_PILL[lord.variantKey] || null;
      items.push({
        uid: "nl:" + String(lord.menuId),
        kind: "nightlord",
        group: "nightlords",
        groups: ["nightlords"],
        name: lord.nameZh || lord.nameEn || "未知夜王",
        nameEn: lord.nameEn || "",
        expedition: lord.expeditionZh || lord.expeditionEn || "",
        variantName: lord.variantNameZh || "",
        variantPill: lord.variantKey && lord.variantKey !== "normal" ? variant : null,
        nameBadge: null,
        weakness: Array.isArray(lord.weakness) ? lord.weakness : [],
        description: lord.descriptionZh || "",
        entries: entries,
        main: mainEntry(entries),
        idText: "菜单行 " + String(lord.menuId),
        // 搜索串的组成两端必须一致：中英文名 + 远征名 + 变体名 + 官方弱点 + 每行标签。
        // 分组名、nameSource / threat / variantKey 这类内部枚举值都不进搜索串。
        search: folder(joinSearch([
          lord.nameZh, lord.nameEn, lord.expeditionZh, lord.expeditionEn,
          lord.variantNameZh, lord.variantNameEn
        ].concat((Array.isArray(lord.weakness) ? lord.weakness : []).map(function (weak) {
          return joinSearch([weak.zh, weak.en]);
        })).concat(entries.map(function (fight) { return joinSearch([fight.labelZh, fight.labelEn]); })))),
        numbers: numberKeys(entryNumbers(entries))
      });
    });

    (Array.isArray(data.nightBosses) ? data.nightBosses : []).forEach(function (boss) {
      var entries = Array.isArray(boss.variants) ? boss.variants : [];
      var info = displayName(boss);
      var groups = bossGroups(boss);
      items.push({
        uid: "nb:" + String(boss.id),
        kind: "boss",
        group: groups[0],
        groups: groups,
        name: info.primary,
        nameEn: info.secondary,
        expedition: "",
        variantName: "",
        variantPill: null,
        nameBadge: nameBadge(info, boss.nameSource),
        // weakness 只存在于 NightBossMenuParam（数据集 caveat 8），守夜 / 野外 Boss 根本没有这个字段。
        // 这里必须是 null（= 没有官方标注）而不是 []（= 官方标注为空），否则页面会凭空给出否定结论。
        weakness: null,
        description: "",
        entries: entries,
        // 卡片自身主分组下的代表行；渲染时按当前分组重新取（见 representativeEntry）。
        main: representativeEntry(entries, groups[0]),
        idText: "chr " + (Array.isArray(boss.chrIds) ? boss.chrIds.join(" / ") : "?"),
        // nameSource 是内部枚举（npcname / manual / chrid-fallback…），不进全文搜索串；
        // chrId / npcId 这类行号进 numbers，按前缀匹配。
        search: folder(joinSearch([
          boss.nameZh, boss.nameEn
        ].concat(entries.map(function (variant) { return joinSearch([variant.labelZh, variant.labelEn]); })))),
        numbers: numberKeys(
          entryNumbers(entries)
            .concat(Array.isArray(boss.chrIds) ? boss.chrIds : [])
            .concat(boss.npcNameId === null || boss.npcNameId === undefined ? [] : [boss.npcNameId])
        )
      });
    });

    return items;
  }

  function itemInGroup(item, group) {
    if (!item) return false;
    if (Array.isArray(item.groups)) return item.groups.indexOf(group) !== -1;
    return item.group === group;
  }

  // 纯数字按行号前缀匹配：npcId / chrId 是 4～9 位数，contains 会让「1」「50」命中全表。
  function itemMatches(item, needle) {
    if (!needle) return true;
    if (/^\d+$/.test(needle)) {
      return (item.numbers || []).some(function (text) { return text.indexOf(needle) === 0; });
    }
    return item.search.indexOf(needle) !== -1;
  }

  function filterItems(items, group, query, fold) {
    var folder = typeof fold === "function" ? fold : defaultFold;
    var needle = folder(String(query == null ? "" : query).trim());
    return items.filter(function (item) {
      if (group && !itemInGroup(item, group)) return false;
      return itemMatches(item, needle);
    });
  }

  // 数据集里是否存在深夜专属数值；没有的话顶部「深夜」开关禁用。
  function hasDeepData(data) {
    if (!data) return false;
    var found = false;
    var scan = function (entries) {
      (entries || []).forEach(function (entry) { if (entry && entry.deepOfNight) found = true; });
    };
    (Array.isArray(data.nightlords) ? data.nightlords : []).forEach(function (lord) { scan(lord.fights); });
    (Array.isArray(data.nightBosses) ? data.nightBosses : []).forEach(function (boss) { scan(boss.variants); });
    return found;
  }

  // ------------------------------------------------------------ 数字格式化

  function round(value, digits) {
    var factor = Math.pow(10, digits);
    return Math.round(Number(value) * factor) / factor;
  }

  function fmtInt(value) {
    var number = Math.round(Number(value) || 0);
    return String(number).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }

  function fmtNumber(value, digits) {
    if (value === null || value === undefined || !isFinite(Number(value))) return "—";
    var rounded = round(value, digits === undefined ? 2 : digits);
    return String(rounded);
  }

  function fmtMul(value) {
    if (value === null || value === undefined || !isFinite(Number(value))) return "—";
    return "×" + fmtNumber(value, 3);
  }

  // kind 来自 computeStats().poiseKind：none = poise < 0，zero = poise === 0。
  function fmtPoise(value, kind) {
    if (value === null || value === undefined) return kind === "zero" ? "无削韧槽" : "不吃削韧";
    return fmtNumber(value, 1);
  }

  // ------------------------------------------------------------ 页面状态

  var state = {
    party: 1,
    group: "nightlords",
    query: "",
    deep: false,
    data: null,
    items: [],
    hasDeep: false,
    expanded: {},
    loaded: false
  };

  var dom = null;
  var ctxRef = null;

  function helpers() {
    return ctxRef && ctxRef.helpers ? ctxRef.helpers : null;
  }

  function esc(value) {
    var h = helpers();
    if (h && typeof h.escapeHtml === "function") return h.escapeHtml(value);
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (char) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[char];
    });
  }

  function pill(text, kind) {
    var h = helpers();
    if (h && typeof h.pill === "function") return h.pill(text, kind);
    return "<span class='pill pill--" + (kind || "purple") + "'>" + esc(text) + "</span>";
  }

  function fold(value) {
    var h = helpers();
    if (h && typeof h.foldForSearch === "function") return h.foldForSearch(value);
    return defaultFold(value);
  }

  // ------------------------------------------------------------ 模板：外壳

  function partyControl() {
    return PARTY_OPTIONS.map(function (option) {
      var active = option.value === state.party;
      return "<button type='button' class='segment-button" + (active ? " is-active" : "") + "'" +
        " data-bosses-party='" + option.value + "' data-testid='bosses-party-" + option.value + "'" +
        " role='radio' aria-checked='" + active + "'>" + esc(option.label) + "</button>";
    }).join("");
  }

  function groupControl() {
    return TABS.map(function (tab) {
      var active = tab.key === state.group;
      return "<button type='button' class='segment-button" + (active ? " is-active" : "") + "'" +
        " data-bosses-group='" + tab.key + "' data-testid='bosses-group-" + tab.key + "'" +
        " role='radio' aria-checked='" + active + "'>" + esc(tab.label) + "</button>";
    }).join("");
  }

  function shell() {
    return "" +
      "<div class='page-content bosses-content'>" +
      "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>首领数据</h1><p>《黑夜君临》首领的血量、承伤倍率、韧性与人数缩放</p></div>" +
      "</header>" +
      "<section class='card bosses-toolbar' data-testid='bosses-toolbar'>" +
      "<div class='bosses-toolbar-row'>" +
      "<div class='bosses-control'><span class='bosses-control-label'>人数</span>" +
      "<div class='segmented-control bosses-party' role='radiogroup' aria-label='队伍人数' data-testid='bosses-party'>" +
      partyControl() + "</div></div>" +
      "<div class='bosses-control bosses-control--grow'><span class='bosses-control-label'>搜索</span>" +
      "<label class='search-field'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='搜索首领名、远征名、变体标签，或输入 npcId / chrId 前缀' autocomplete='off' data-testid='bosses-search'></label></div>" +
      "<div class='bosses-control'><span class='bosses-control-label'>深夜</span>" +
      "<label class='switch-control bosses-deep'><input type='checkbox' data-testid='bosses-deep'>" +
      "<span class='switch-track'></span><span data-testid='bosses-deep-label'>深夜数值</span></label></div>" +
      "</div>" +
      "<div class='bosses-toolbar-row bosses-toolbar-row--tabs'>" +
      "<div class='segmented-control bosses-group' role='radiogroup' aria-label='首领分组' data-testid='bosses-group'>" +
      groupControl() + "</div>" +
      "<span class='bosses-count' data-testid='bosses-count'>—</span>" +
      "</div>" +
      "</section>" +
      "<div class='bosses-list' data-testid='bosses-list'></div>" +
      "<div class='empty-state bosses-empty' data-testid='bosses-empty' hidden>" +
      "<div class='empty-icon'>☷</div><h3>没有匹配的首领</h3><p>请调整搜索词或切换分组</p></div>" +
      "<div data-testid='bosses-footer'></div>" +
      "</div>";
  }

  function unavailableShell(message) {
    return "" +
      "<div class='page-content bosses-content'>" +
      "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>首领数据</h1><p>《黑夜君临》首领的血量、承伤倍率、韧性与人数缩放</p></div>" +
      "</header>" +
      "<article class='card page-placeholder-card' data-testid='bosses-card'>" +
      "<div class='section-heading'><div class='section-icon'>✸</div>" +
      "<div><h2>数据未内置</h2><p>" + esc(message) + "</p></div></div>" +
      "<div class='page-status-row'>" + pill("数据未内置", "amber") +
      "<span>缺少 resources/" + DATA_NAME + ".json</span></div>" +
      "<p class='data-hint'>源文件生成后运行仓库根的 scripts/sync-data.sh 同步到 windows/resources/ 与 macOS 的 Resources/，无需改代码。</p>" +
      "</article></div>";
  }

  // ------------------------------------------------------------ 模板：卡片

  // 代表行里承伤倍率 > 1 的属性（页面自己按 damageRates 算出来的，不是官方标注）。
  function topDamageTypes(entry, limit) {
    if (!entry || !entry.damageRates) return [];
    return DAMAGE_TYPES.map(function (type) {
      return { zh: type.zh, rate: Number(entry.damageRates[type.key]) };
    }).filter(function (row) {
      return isFinite(row.rate) && row.rate > 1;
    }).sort(function (a, b) {
      return b.rate - a.rate;
    }).slice(0, limit || 3);
  }

  // weakness（NightBossMenuParam 的菜单弱点图标）只有夜王有。守夜 / 野外 Boss 的数据里
  // 根本没有这个字段，所以不能显示「官方标注：无弱点」——那是把「数据里没有」说成「官方说没有」。
  function weaknessRow(item, entry) {
    if (item.kind === "nightlord") {
      var list = Array.isArray(item.weakness) ? item.weakness : [];
      if (!list.length) return "<span class='bosses-none'>官方标注：无弱点</span>";
      return "<span class='bosses-weak-label'>官方弱点</span>" + list.map(function (weak) {
        return pill(weak.zh || weak.en || String(weak.code), "amber");
      }).join("");
    }
    var hot = topDamageTypes(entry, 3);
    if (!hot.length) {
      return "<span class='bosses-none'>本作只给夜王官方弱点标注；展开看承伤倍率</span>";
    }
    return "<span class='bosses-weak-label'>代表行承伤偏高</span>" + hot.map(function (row) {
      return pill(row.zh + " " + fmtMul(row.rate), "amber");
    }).join("");
  }

  function statCell(label, value, hint) {
    return "<div class='bosses-stat'><span class='bosses-stat-label'>" + esc(label) + "</span>" +
      "<strong class='bosses-stat-value'>" + esc(value) + "</strong>" +
      (hint ? "<span class='bosses-stat-hint'>" + esc(hint) + "</span>" : "") + "</div>";
  }

  function partyLabel() {
    return state.party + " 人";
  }

  function cardHeadBadges(item) {
    var badges = [];
    if (item.kind === "nightlord") {
      badges.push(pill("夜王", "purple"));
      if (item.variantPill) badges.push(pill(item.variantPill.text, item.variantPill.kind));
    } else {
      // tiers 里同时含 field 与 night 的 Boss 两枚徽标都画，和分组切换里两边都能搜到对应。
      (Array.isArray(item.groups) && item.groups.length ? item.groups : [item.group]).forEach(function (group) {
        badges.push(pill(GROUP_TITLES[group] || group, group === "night" ? "blue" : "green"));
      });
    }
    if (item.nameBadge) badges.push(pill(item.nameBadge.text, item.nameBadge.kind));
    if (state.deep) {
      // 只给真有深夜专属数值的卡片挂徽标：大多数卡片深夜与常规相同，
      // 逐张挂灰徽标纯属噪音，还会把名称徽标挤到第二行。整体数量写在顶部计数里。
      var coverage = deepCoverage(item);
      if (coverage === "all") badges.push(pill("深夜数值", "amber"));
      else if (coverage === "some") badges.push(pill("部分行有深夜数值", "amber"));
    }
    return badges.join("");
  }

  function cardSubtitle(item) {
    var parts = [];
    if (item.nameEn) parts.push(item.nameEn);
    if (item.expedition) parts.push("远征：" + item.expedition);
    if (item.variantName) parts.push(item.variantName);
    if (!parts.length) parts.push(item.idText);
    return parts.join(" · ");
  }

  // 卡面这三格只是「代表行」的数值。同一张卡常有 5 组差距很大的数值（古龙 2,672～6,167），
  // 不写清楚取自哪一行会被当成算错；而且两种情况必须分别说明：
  //   · 夜王的 isMain 不唯一（多阶段 / 多体有 2～5 条），并列列出全部主战血量；
  //   · 守夜 / 野外的候选行随分组切换（同一组首领可能两种档位都有）。
  function summaryCaption(item, entry) {
    if (!entry) return "";
    var pool = candidateEntries(item.entries, state.group);
    // 只有「代表行本身有歧义」的卡片才铺开列全部候选行，别把普通卡片的摘要撑成两行：
    //   · 夜王有多条 isMain（哪条才是「这只夜王的血量」说不清）；
    //   · 同时属于守夜与野外的组（同一张卡在两个分组下给的是不同的行）。
    var ambiguous = item.kind === "nightlord"
      ? mainRows(item.entries).length > 1
      : (Array.isArray(item.groups) ? item.groups.length : 1) > 1;
    if (ambiguous && pool.length > 1) {
      var list = pool.map(function (row) {
        return entryLabel(row, item.entries.indexOf(row)) + " " +
          fmtInt(computeStats(row, state.party, state.deep).hp);
      }).join(" · ");
      var lead = item.kind === "nightlord"
        ? pool.length + " 条主战行，上方取血量最高的一条："
        : "该分组 " + pool.length + " 条数值行，上方取血量最高的一条：";
      return "<div class='bosses-stat-caption bosses-stat-caption--warn'>" + esc(lead + list) + "</div>";
    }
    if (item.entries.length < 2) return "";
    var label = entryLabel(entry, item.entries.indexOf(entry));
    return "<div class='bosses-stat-caption'>代表行：" + esc(label) +
      "<span>共 " + item.entries.length + " 组，展开看全部</span></div>";
  }

  // 夜王的主战行不止一条时要标明头条取的是最高那条，别让用户以为「这只夜王就这点血」。
  function hpMetricTitle(item) {
    if (item.kind !== "nightlord") return "血量";
    return mainRows(item.entries).length > 1 ? "主战血量 · 最高" : "主战血量";
  }

  // 深夜开着、但代表行没有深夜专属缩放时（卡头徽标写「部分行有深夜数值」的那几张），
  // 要在血量下面直说这一行回落到了常规值，否则摘要与徽标看着像在互相打架。
  function summaryHpHint(stats) {
    if (state.deep) {
      if (!stats.isDeep) return "该行深夜同常规";
      return state.party === 1 ? "深夜数值" : "深夜 1 人 " + fmtInt(stats.hpSingle);
    }
    return state.party === 1 ? "含常驻缩放" : "1 人 " + fmtInt(stats.hpSingle);
  }

  function cardSummary(item, entry) {
    if (!entry) return "<p class='bosses-none'>该首领没有可用的数值行。</p>";
    var stats = computeStats(entry, state.party, state.deep);
    return summaryCaption(item, entry) + "<div class='bosses-stat-row'>" +
      statCell(hpMetricTitle(item) + "（" + partyLabel() + "）", fmtInt(stats.hp), summaryHpHint(stats)) +
      statCell("有效韧性", fmtPoise(stats.effectivePoise, stats.poiseKind), stats.effectivePoise === null ? "" : "韧性槽 " + fmtNumber(stats.poise, 0)) +
      statCell("削韧恢复", fmtNumber(stats.poiseRecover, 3), "每秒") +
      "</div>";
  }

  function rateTable(entry) {
    var head = DAMAGE_TYPES.map(function (type) {
      return "<th scope='col'>" + esc(type.zh) + "</th>";
    }).join("");
    var body = DAMAGE_TYPES.map(function (type) {
      var rate = entry.damageRates ? entry.damageRates[type.key] : 1;
      var note = rateNote(rate);
      return "<td class='bosses-rate bosses-rate--" + rateClass(rate) + "'>" +
        "<strong>" + esc(fmtNumber(rate, 2)) + "</strong>" +
        (note ? "<span>" + esc(note) + "</span>" : "") + "</td>";
    }).join("");
    return "<table class='bosses-mini-table'><thead><tr>" + head + "</tr></thead>" +
      "<tbody><tr>" + body + "</tr></tbody></table>";
  }

  function resistTable(entry) {
    var head = AILMENTS.map(function (item) {
      return "<th scope='col'>" + esc(item.zh) + "</th>";
    }).join("");
    var body = AILMENTS.map(function (item) {
      var value = entry.resist ? entry.resist[item.key] : null;
      if (value === null || value === undefined) return "<td class='bosses-resist'>—</td>";
      if (isImmune(value)) return "<td class='bosses-resist bosses-resist--immune'><strong>免疫</strong></td>";
      return "<td class='bosses-resist'><strong>" + esc(fmtInt(value)) + "</strong></td>";
    }).join("");
    return "<table class='bosses-mini-table'><thead><tr>" + head + "</tr></thead>" +
      "<tbody><tr>" + body + "</tr></tbody></table>";
  }

  function scalingTable(entry) {
    var scaling = entry.scaling || {};
    var rows = [
      { key: "duo", label: "2 人" },
      { key: "trio", label: "3 人" }
    ].map(function (row) {
      var tier = scaling[row.key];
      var active = tierKey(state.party) === row.key;
      if (!tier) {
        return "<tr" + (active ? " class='is-active'" : "") + "><th scope='row'>" + esc(row.label) +
          "</th><td colspan='5' class='bosses-none'>无缩放数据</td></tr>";
      }
      return "<tr" + (active ? " class='is-active'" : "") + ">" +
        "<th scope='row'>" + esc(row.label) + "</th>" +
        "<td>" + esc(fmtMul(tier.hp)) + "</td>" +
        "<td>" + esc(fmtMul(tier.poiseTaken)) + "</td>" +
        "<td>" + esc(fmtMul(tier.poiseRecover)) + "</td>" +
        "<td>" + esc(fmtMul(tier.buildupRate)) + "</td>" +
        "<td>" + esc(fmtMul(tier.ailmentDamageRate)) + "</td>" +
        "</tr>";
    }).join("");
    return "<table class='bosses-mini-table bosses-scaling-table'>" +
      "<thead><tr><th scope='col'>人数</th><th scope='col'>血量</th><th scope='col'>承受削韧</th>" +
      "<th scope='col'>削韧恢复</th><th scope='col'>异常累积</th><th scope='col'>异常发动伤害</th></tr></thead>" +
      "<tbody>" + rows + "</tbody></table>";
  }

  function permScalingLine(stats) {
    var table = state.data && state.data.permanentScaling ? state.data.permanentScaling : null;
    if (!table || !stats.permScalingIds.length) return "";
    var chips = stats.permScalingIds.map(function (id) {
      var effect = table[String(id)];
      if (!effect) return "<span class='bosses-chip'>常驻 " + esc(id) + "</span>";
      var factors = [];
      if (Number(effect.hp) !== 1) factors.push("血量 " + fmtMul(effect.hp));
      if (Number(effect.poiseTaken) !== 1) factors.push("承受削韧 " + fmtMul(effect.poiseTaken));
      if (Number(effect.poiseRecover) !== 1) factors.push("削韧恢复 " + fmtMul(effect.poiseRecover));
      if (Number(effect.ailmentDamageRate) !== 1) factors.push("异常伤害 " + fmtMul(effect.ailmentDamageRate));
      var text = (effect.nameZh || effect.nameEn || ("常驻 " + id)) + (factors.length ? "（" + factors.join(" · ") + "）" : "");
      return "<span class='bosses-chip'>" + esc(text) + "</span>";
    }).join("");
    return "<div class='bosses-chips'><span class='bosses-sub'>常驻缩放</span>" + chips + "</div>";
  }

  // 深夜提示随开关反向：关着时告诉用户「可以切」，开着时给出常规值作对照，
  // 不要在已经显示深夜血量的行上再重复播报一遍同一个数字。
  // 三条文案与 macOS 端 BossFightRowView.scalingSection 完全一致。
  function deepNote(entry) {
    if (!entry) return "";
    if (entry.deepOfNight) {
      if (state.deep) {
        return "<p class='bosses-note'>当前为深夜数值；常规数值：血量 " +
          esc(fmtInt(entry.hp)) + "（1 人）。</p>";
      }
      return "<p class='bosses-note'>该行有深夜专属缩放：血量 " + esc(fmtInt(entry.deepOfNight.hp)) +
        "（1 人），可用顶部「深夜」开关切换。</p>";
    }
    if (state.deep) {
      return "<p class='bosses-note bosses-note--muted'>该行没有深夜专属缩放，深夜数值与常规相同。</p>";
    }
    return "";
  }

  function entryBlock(item, entry, index) {
    var stats = computeStats(entry, state.party, state.deep);
    var tiers = state.data && state.data.scalingTiers ? state.data.scalingTiers : null;
    var tierMeta = tiers && entry.scalingId !== null && entry.scalingId !== undefined ? tiers[String(entry.scalingId)] : null;
    var groupName = tierMeta && tierMeta.group ? (GROUP_LABELS[tierMeta.group] || tierMeta.group) : "";
    var badges = [];
    if (entry.isMain) badges.push(pill("主战", "green"));
    if (item.kind === "boss" && entry.threat) {
      badges.push(pill(entry.threat === "night" ? "守夜" : "野外", entry.threat === "night" ? "blue" : "green"));
    }
    if (entry.labelUncertain) badges.push(pill("标签存疑", "gray"));
    if (stats.isDeep) badges.push(pill("深夜", "amber"));

    var npcIds = Array.isArray(entry.npcIds) ? entry.npcIds : [];
    var idText = "npcId " + String(entry.npcId) + (npcIds.length > 1 ? "（合并 " + npcIds.length + " 行）" : "");

    return "<section class='bosses-entry'>" +
      "<header class='bosses-entry-head'>" +
      "<strong>" + esc(entryLabel(entry, index)) + "</strong>" +
      "<span class='bosses-entry-badges'>" + badges.join("") + "</span>" +
      "<span class='bosses-entry-id'>" + esc(idText) + "</span>" +
      "</header>" +
      "<div class='bosses-stat-row bosses-stat-row--compact'>" +
      statCell("血量（" + partyLabel() + "）", fmtInt(stats.hp), "参数原值 " + fmtInt(stats.hpBase) + " × " + fmtNumber(stats.hpMultiplier, 3)) +
      statCell("有效韧性", fmtPoise(stats.effectivePoise, stats.poiseKind), stats.effectivePoise === null ? "" : "承受削韧 " + fmtMul(stats.poiseTakenTotal)) +
      statCell("削韧恢复", fmtNumber(stats.poiseRecover, 3), "每秒") +
      statCell("异常累积", fmtMul(stats.buildupRate), "Boss 承受量") +
      statCell("异常发动伤害", fmtMul(stats.ailmentDamageRate), "中毒/腐败 " + fmtMul(stats.poisonRate)) +
      "</div>" +
      "<div class='bosses-sub'>承伤倍率（&gt;1 多吃伤害，&lt;1 抗性）</div>" + rateTable(entry) +
      "<div class='bosses-sub'>异常抗性（累积阈值，越大越难触发）</div>" + resistTable(entry) +
      "<div class='bosses-sub'>多人缩放" + (entry.scalingId !== null && entry.scalingId !== undefined
        ? "（档位 " + esc(entry.scalingId) + (groupName ? " · " + esc(groupName) : "") + "）" : "") + "</div>" +
      scalingTable(entry) +
      permScalingLine(stats) +
      deepNote(entry) +
      "</section>";
  }

  function cardBody(item) {
    if (!item.entries.length) return "<p class='bosses-none'>没有可用的数值行。</p>";
    var head = "";
    if (item.description) {
      head = "<p class='bosses-desc'>" + esc(item.description) + "</p>";
    }
    return head + item.entries.map(function (entry, index) {
      return entryBlock(item, entry, index);
    }).join("");
  }

  function cardInner(item) {
    var expanded = Boolean(state.expanded[item.uid]);
    // 折叠态的代表行跟着当前分组走：同一张卡可能同时出现在「守夜」与「野外」里，
    // 野外分组下就该看野外那几行，而不是恒取 variants[0]（常常是血量更高的守夜行）。
    var entry = representativeEntry(item.entries, state.group);
    return "" +
      "<button type='button' class='bosses-card-head' data-bosses-toggle='" + esc(item.uid) + "' aria-expanded='" + expanded + "'>" +
      "<span class='bosses-card-title'>" +
      "<strong>" + esc(item.name) + "</strong>" +
      "<span class='bosses-card-sub'>" + esc(cardSubtitle(item)) + "</span>" +
      "</span>" +
      "<span class='bosses-card-badges'>" + cardHeadBadges(item) + "</span>" +
      "<span class='bosses-chevron' aria-hidden='true'>" + (expanded ? "▴" : "▾") + "</span>" +
      "</button>" +
      "<div class='bosses-weakness'>" + weaknessRow(item, entry) +
      "<span class='bosses-entry-count'>" + esc(item.entries.length + " 组数值") + "</span></div>" +
      cardSummary(item, entry) +
      (expanded ? "<div class='bosses-card-body'>" + cardBody(item) + "</div>" : "");
  }

  function cardHtml(item) {
    var expanded = Boolean(state.expanded[item.uid]);
    return "<article class='card bosses-card" + (expanded ? " is-expanded" : "") + "'" +
      " data-bosses-card='" + esc(item.uid) + "'>" + cardInner(item) + "</article>";
  }

  // ------------------------------------------------------------ 模板：底部

  function caveatsBlock(data) {
    var list = Array.isArray(data.caveats) ? data.caveats : [];
    if (!list.length) return "";
    return "<details class='card bosses-details' data-testid='bosses-caveats'>" +
      "<summary><span class='bosses-summary-title'>数据说明与已知取舍</span>" +
      pill(list.length + " 条", "amber") + "</summary>" +
      "<div class='bosses-details-body'>" +
      "<p class='bosses-note'>本页数值直接读取游戏参数表，不是官方公布数据，也不是实测结论；标注与实际手感可能有出入。</p>" +
      "<ul class='bosses-caveat-list'>" + list.map(function (text) {
        return "<li>" + esc(text) + "</li>";
      }).join("") + "</ul></div></details>";
  }

  function scalingTiersBlock(data) {
    var tiers = data.scalingTiers && typeof data.scalingTiers === "object" ? data.scalingTiers : null;
    if (!tiers) return "";
    var keys = Object.keys(tiers).sort(function (a, b) { return Number(a) - Number(b); });
    var rows = keys.map(function (key) {
      var tier = tiers[key];
      var groupName = tier.group ? (GROUP_LABELS[tier.group] || tier.group) : "其它档位";
      return ["duo", "trio"].map(function (which, index) {
        var value = tier[which];
        var label = which === "duo" ? "2 人" : "3 人";
        var first = index === 0
          ? "<th scope='row' rowspan='2'>" + esc(key) + "<span>" + esc(groupName) + "</span></th>"
          : "";
        if (!value) {
          return "<tr>" + first + "<td>" + esc(label) + "</td><td colspan='5' class='bosses-none'>无数据</td></tr>";
        }
        return "<tr>" + first + "<td>" + esc(label) + "</td>" +
          "<td>" + esc(fmtMul(value.hp)) + "</td>" +
          "<td>" + esc(fmtMul(value.poiseTaken)) + "</td>" +
          "<td>" + esc(fmtMul(value.poiseRecover)) + "</td>" +
          "<td>" + esc(fmtMul(value.buildupRate)) + "</td>" +
          "<td>" + esc(fmtMul(value.ailmentDamageRate)) + "</td></tr>";
      }).join("");
    }).join("");

    return "<details class='card bosses-details' data-testid='bosses-tiers'>" +
      "<summary><span class='bosses-summary-title'>人数缩放档位说明</span>" +
      pill(keys.length + " 档", "purple") + "</summary>" +
      "<div class='bosses-details-body'>" +
      "<ul class='bosses-legend'>" +
      "<li><b>血量</b>：多人时 Boss 血量乘这个倍率，页面顶部切人数后所有血量都按它换算。</li>" +
      "<li><b>承受削韧</b>：Boss 实际吃到的削韧比例。2 人 ×0.55 表示同样的削韧只吃 55%，等价于有效韧性变成约 1.8 倍。</li>" +
      "<li><b>削韧恢复</b>：削韧槽恢复速度倍率，与承受削韧同值。</li>" +
      "<li><b>异常累积</b>：Boss 承受的异常累积量倍率，越小越难打出异常；<b>不是</b>阈值下调，多人并不会更容易上异常。</li>" +
      "<li><b>异常发动伤害</b>：异常触发那一下的伤害倍率（出血/冻伤/睡眠/发狂同值）；中毒与腐败单独由 poisonRate 控制，目前恒为 ×1。</li>" +
      "</ul>" +
      "<div class='table-wrap bosses-table-wrap'><table class='bosses-mini-table bosses-tier-table'>" +
      "<thead><tr><th scope='col'>档位</th><th scope='col'>人数</th><th scope='col'>血量</th>" +
      "<th scope='col'>承受削韧</th><th scope='col'>削韧恢复</th><th scope='col'>异常累积</th>" +
      "<th scope='col'>异常发动伤害</th></tr></thead><tbody>" + rows + "</tbody></table></div>" +
      "</div></details>";
  }

  function versionBlock(data) {
    var counts = {
      lords: Array.isArray(data.nightlords) ? data.nightlords.length : 0,
      night: 0,
      field: 0,
      both: 0,
      rows: 0
    };
    (Array.isArray(data.nightBosses) ? data.nightBosses : []).forEach(function (boss) {
      var groups = bossGroups(boss);
      if (groups.indexOf("night") !== -1) counts.night += 1;
      if (groups.indexOf("field") !== -1) counts.field += 1;
      if (groups.length > 1) counts.both += 1;
      counts.rows += Array.isArray(boss.variants) ? boss.variants.length : 0;
    });
    (Array.isArray(data.nightlords) ? data.nightlords : []).forEach(function (lord) {
      counts.rows += Array.isArray(lord.fights) ? lord.fights.length : 0;
    });

    var sources = (Array.isArray(data.sources) ? data.sources : []).map(function (source) {
      return "<li><strong>" + esc(source.name) + "</strong>" +
        (source.revision ? "<span>" + esc(source.revision) + "</span>" : "") +
        (source.usage ? "<span>" + esc(source.usage) + "</span>" : "") + "</li>";
    }).join("");

    return "<details class='card bosses-details' data-testid='bosses-version'>" +
      "<summary><span class='bosses-summary-title'>数据版本与来源</span>" +
      pill(data.gameVersion || "未知版本", "green") + "</summary>" +
      "<div class='bosses-details-body'>" +
      "<dl class='bosses-meta'>" +
      "<div><dt>游戏版本</dt><dd>" + esc(data.gameVersion || "—") + "</dd></div>" +
      "<div><dt>数据版本</dt><dd>" + esc(data.dataVersion || "—") + "</dd></div>" +
      "<div><dt>生成时间</dt><dd>" + esc(data.generatedAt || "—") + "</dd></div>" +
      "<div><dt>数据集结构版本</dt><dd>bossesSchemaVersion " + esc(data.bossesSchemaVersion || "—") + "</dd></div>" +
      "<div><dt>收录</dt><dd>夜王 " + counts.lords + " · 守夜 " + counts.night +
      " · 野外 " + counts.field + (counts.both ? "（含 " + counts.both + " 组两边都出现）" : "") +
      " · 数值行 " + counts.rows + "</dd></div>" +
      "</dl>" +
      (sources ? "<div class='bosses-sub'>来源</div><ul class='bosses-source-list'>" + sources + "</ul>" : "") +
      "</div></details>";
  }

  function footerHtml(data) {
    return caveatsBlock(data) + scalingTiersBlock(data) + versionBlock(data);
  }

  // ------------------------------------------------------------ 渲染与事件

  function renderList() {
    if (!dom) return;
    var list = dom.querySelector("[data-testid='bosses-list']");
    var empty = dom.querySelector("[data-testid='bosses-empty']");
    var count = dom.querySelector("[data-testid='bosses-count']");
    if (!list) return;
    var visible = filterItems(state.items, state.group, state.query, fold);
    list.innerHTML = visible.map(cardHtml).join("");
    if (empty) empty.hidden = visible.length > 0;
    if (count) {
      var total = state.items.filter(function (item) { return itemInGroup(item, state.group); }).length;
      var deepText = "";
      if (state.deep) {
        var withDeep = visible.filter(function (item) { return deepCoverage(item) !== "none"; }).length;
        deepText = " · 深夜（其中 " + withDeep + " 个有深夜专属数值）";
      }
      count.textContent = "显示 " + visible.length + " / " + total + " 个首领 · " + partyLabel() + deepText;
    }
  }

  function renderControls() {
    if (!dom) return;
    dom.querySelectorAll("[data-bosses-party]").forEach(function (button) {
      var active = Number(button.dataset.bossesParty) === state.party;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-checked", String(active));
    });
    dom.querySelectorAll("[data-bosses-group]").forEach(function (button) {
      var active = button.dataset.bossesGroup === state.group;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-checked", String(active));
    });
  }

  function renderCard(uid) {
    if (!dom) return;
    // uid 里可能带单引号（如 "nb:The Duke's Dear Freja@7800"），不走选择器拼接。
    var node = null;
    var nodes = dom.querySelectorAll("[data-bosses-card]");
    for (var n = 0; n < nodes.length; n += 1) {
      if (nodes[n].getAttribute("data-bosses-card") === uid) { node = nodes[n]; break; }
    }
    if (!node) return;
    var item = null;
    for (var i = 0; i < state.items.length; i += 1) {
      if (state.items[i].uid === uid) { item = state.items[i]; break; }
    }
    if (!item) return;
    // innerHTML 会连刚被点击的那个 .bosses-card-head 一起销毁，焦点会掉回 body；
    // 重绘后按属性值找回新按钮再 focus()，Tab + Enter 浏览才不用从页首重来。
    var doc = node.ownerDocument || (dom && dom.ownerDocument);
    var hadFocus = Boolean(doc && doc.activeElement && node.contains(doc.activeElement));
    node.classList.toggle("is-expanded", Boolean(state.expanded[uid]));
    node.innerHTML = cardInner(item);
    if (!hadFocus) return;
    var heads = node.querySelectorAll("[data-bosses-toggle]");
    for (var h = 0; h < heads.length; h += 1) {
      if (heads[h].getAttribute("data-bosses-toggle") === uid) { heads[h].focus(); break; }
    }
  }

  function bindEvents() {
    if (!dom) return;

    dom.addEventListener("click", function (event) {
      var partyButton = event.target.closest("[data-bosses-party]");
      if (partyButton) {
        state.party = Number(partyButton.dataset.bossesParty) || 1;
        renderControls();
        renderList();
        return;
      }
      var groupButton = event.target.closest("[data-bosses-group]");
      if (groupButton) {
        state.group = groupButton.dataset.bossesGroup;
        renderControls();
        renderList();
        return;
      }
      var toggle = event.target.closest("[data-bosses-toggle]");
      if (toggle) {
        var uid = toggle.dataset.bossesToggle;
        if (state.expanded[uid]) delete state.expanded[uid];
        else state.expanded[uid] = true;
        renderCard(uid);
      }
    });

    var search = dom.querySelector("[data-testid='bosses-search']");
    if (search) {
      search.addEventListener("input", function (event) {
        state.query = event.target.value || "";
        renderList();
      });
    }

    var deep = dom.querySelector("[data-testid='bosses-deep']");
    if (deep) {
      deep.addEventListener("change", function (event) {
        state.deep = Boolean(event.target.checked);
        renderList();
      });
    }
  }

  function applyDeepAvailability() {
    if (!dom) return;
    var deep = dom.querySelector("[data-testid='bosses-deep']");
    var label = dom.querySelector("[data-testid='bosses-deep-label']");
    if (!deep) return;
    deep.disabled = !state.hasDeep;
    if (!state.hasDeep) {
      deep.checked = false;
      state.deep = false;
      if (label) label.textContent = "深夜数值（本数据集无）";
      var control = deep.closest(".switch-control");
      if (control) control.classList.add("is-disabled");
    }
  }

  function renderData(data) {
    if (!dom) return;
    state.data = data;
    state.items = buildItems(data, fold);
    state.hasDeep = hasDeepData(data);
    dom.innerHTML = shell();
    bindEvents();
    var search = dom.querySelector("[data-testid='bosses-search']");
    if (search && state.query) search.value = state.query;
    applyDeepAvailability();
    renderControls();
    renderList();
    var footer = dom.querySelector("[data-testid='bosses-footer']");
    if (footer) footer.innerHTML = footerHtml(data);
  }

  function load(ctx) {
    ctxRef = ctx;
    if (!dom) return;
    ctx.getGameData(DATA_NAME).then(function (data) {
      if (!dom) return;
      if (!data || typeof data !== "object") {
        state.loaded = false;
        dom.innerHTML = unavailableShell("尚未提供首领数据文件，页面无法显示数值。");
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
      mount.innerHTML = "<div class='page-content bosses-content'><p class='bosses-loading' " +
        "data-testid='bosses-loading'>正在载入首领数据…</p></div>";
      load(ctx);
    },
    refresh: function (ctx) {
      ctxRef = ctx;
      if (!dom) return;
      if (!state.loaded) load(ctx);
    },
    // 纯计算部分，供 windows/tests/bosses.test.mjs 直接测试。
    _internals: {
      tierKey: tierKey,
      numbersFor: numbersFor,
      scalingFor: scalingFor,
      computeStats: computeStats,
      rateClass: rateClass,
      rateNote: rateNote,
      isImmune: isImmune,
      displayName: displayName,
      nameBadge: nameBadge,
      entryLabel: entryLabel,
      mainEntry: mainEntry,
      mainRows: mainRows,
      candidateEntries: candidateEntries,
      representativeEntry: representativeEntry,
      itemMatches: itemMatches,
      bossGroups: bossGroups,
      deepCoverage: deepCoverage,
      itemInGroup: itemInGroup,
      topDamageTypes: topDamageTypes,
      buildItems: buildItems,
      filterItems: filterItems,
      hasDeepData: hasDeepData,
      fmtInt: fmtInt,
      fmtNumber: fmtNumber,
      fmtMul: fmtMul,
      fmtPoise: fmtPoise,
      DAMAGE_TYPES: DAMAGE_TYPES,
      AILMENTS: AILMENTS,
      GROUP_LABELS: GROUP_LABELS,
      GROUP_TITLES: GROUP_TITLES
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
