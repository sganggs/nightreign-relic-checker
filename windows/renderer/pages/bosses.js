// 首领数据页。页面模块契约见 renderer/pages/README.md。
// 本文件由「首领数据」功能开发者独占：只改这里与 pages/bosses.css。
//
// 数据：ctx.getGameData("bosses") → resources/bosses.json（bossesSchemaVersion 3）。
// 数值口径（务必与数据集说明一致）：
//   · hp 已经含常驻缩放（= hpBase × hpMultiplier），多人血量 = hp × scaling.<duo|trio>.hp
//   · 深夜深度 N 的血量直接用 depthStats[N].hp（已含常驻缩放 × 深夜修正 × 深度倍率），
//     再乘人数缩放；有效韧性的分母换成 depthStats[N].poiseTakenBase
//   · 有效韧性 = poise / (poiseTakenBase × scaling.<tier>.poiseTaken)
//   · 削韧恢复 = poiseRecover × poiseRecoverMultiplier × scaling.<tier>.poiseRecover
//   · 异常发动伤害 = ailmentDamageRateBase × scaling.<tier>.ailmentDamageRate
//   · 敌人攻击力 = attackRateBase × scaling.<tier>.attackRate（深夜取 depthStats[N].attackRateBase）
//   · 变异个体（游戏内正式叫法，社区俗称「红化」）的倍率 spCategory = 203，与常驻(0)/深度(0)/
//     人数(140) 分类都不同 → 不互相覆盖，是在其它缩放**之上再乘一层**（按参数结构推断）
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

  // 数据里还有 group = null 的档位（98810 / 98815 / 98818 / 98822）：它们与
  // 三个威胁档一样要有名字，否则展开态的「多人缩放」只写个档位号，
  // 和底部档位表里的「其它档位」对不上。与 macOS 端
  // BossScalingGroup.title(for:) 同一条规则（含空串也算缺失）。
  var TIER_GROUP_FALLBACK = "其它档位";

  // 行没有 scalingId 时展开态「多人缩放明细」的档位说明。
  // 与 macOS 端 BossRowText.scalingCaption 的同一支逐字一致：此前 Windows 给空串，
  // 整段说明直接不出现，两端一个有话一个空白。
  var TIER_NO_SCALING = "无缩放档位";

  // 行内徽标 / 卡头计数的统一文案，两端逐字相同（macOS 端 BossFightRowView
  // 与 BossCardView 用同样的几串）。
  var BADGE_LABEL_UNCERTAIN = "标签为社区推测";
  var BADGE_MUTATION = "变异个体";
  var BADGE_HIDDEN = "隐藏实体";

  // 深夜 / 深度 / 变异个体的中文一律用游戏内文本（CL_MenuText 131150 / 131011 /
  // 338806），数据集里放在 deepOfNightText。取不到时才用这里的兜底串。
  var DEEP_TEXT_FALLBACK = {
    deepOfNight: "深夜",
    depth: "深度",
    mutation: "变异个体"
  };

  // 深度只有 1–5 五档（ChaosMatchingRankControlParam 就 5 行）。
  var DEPTHS = [1, 2, 3, 4, 5];

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

  // 名称来源徽标：前四档沿用上一版的文案，schemaVersion 3 新增的 community /
  // community-npcname 合并成「社区资料」（名字或身份来自社区 roster，不是游戏文本）。
  // 表里没有的取值（npcname / npcname-alias / npcparam-nameid…）说明名字直接来自
  // 游戏文本，不挂徽标。
  var NAME_SOURCE_BADGES = {
    "english-only": "仅英文名",
    "chrid-fallback": "无游戏内名称",
    "manual": "名称手工补录",
    "community": "社区资料",
    "community-npcname": "社区资料"
  };

  var BADGE_NAME_INFERRED = "名称按 ID 推断";
  var BADGE_NAME_APPROX = "近似匹配";
  var BADGE_NAME_FALLBACK = "参考译名 · 非本作游戏文本";

  // -------------------------------------------------------------- 纯计算层
  // 以下函数不碰 DOM，windows/tests/bosses.test.mjs 直接 require 本文件测试。

  function tierKey(party) {
    if (party === 2) return "duo";
    if (party === 3) return "trio";
    return null;
  }

  // 顶部「模式」下拉的取值：0 = 常规，1–5 = 深夜的对应深度。
  // 其它一切（null / true / "3" / 9）都归一化，避免 depthStats["true"] 这种取法。
  function depthValue(value) {
    // 布尔要先排掉：Number(true) === 1 会让旧的「深夜」开关静悄悄变成「深度 1」。
    if (value === true || value === false) return 0;
    var number = Math.floor(Number(value));
    if (!isFinite(number) || number < 1) return 0;
    return number > 5 ? 5 : number;
  }

  // 档位分组的中文名。group 缺失（数据里的 4 个 group = null 档位）时写
  // 「其它档位」——展开态的「多人缩放」标题与底部档位表用同一个名字，
  // 与 macOS 端 BossScalingGroup.title(for:) 逐字一致。
  function tierGroupLabel(group) {
    if (!group) return TIER_GROUP_FALLBACK;
    return GROUP_LABELS[group] || String(group);
  }

  // 展开态「多人缩放」标题里的档位说明。三支与 macOS 端
  // BossRowText.scalingCaption(scalingID:groupTitle:) 逐字一致：
  //   没有 scalingId → 「无缩放档位」（此前 Windows 给空串，整段不出现）；
  //   查不到档位     → 「档位 #<id>」；
  //   查得到         → 「档位 #<id> · <分组名>」。
  // id 前面的「#」跟 macOS 走：macOS 底部档位表也写 #<id>，本页底部档位表
  // 同步改成 #<id>，两端内部与相互都自洽。
  function scalingCaption(entry, tiers) {
    var id = entry && entry.scalingId;
    if (id === null || id === undefined) return TIER_NO_SCALING;
    var meta = tiers ? tiers[String(id)] : null;
    if (!meta) return "档位 #" + id;
    return "档位 #" + id + " · " + tierGroupLabel(meta.group);
  }

  // 卡头右侧的数值行计数。两端同一串（macOS 端 BossCardView 的同一行）。
  function rowCountText(count) {
    return count + " 条数值行";
  }

  // 深夜模式的显示名，全部取游戏文本：「深夜 · 深度 3」。
  function deepText(data, key) {
    var table = data && data.deepOfNightText ? data.deepOfNightText : null;
    var item = table ? table[key] : null;
    var zh = item && item.zh ? String(item.zh) : "";
    return zh || DEEP_TEXT_FALLBACK[key] || "";
  }

  function depthLabel(data, depth) {
    if (!depth) return "常规";
    return deepText(data, "deepOfNight") + " · " + deepText(data, "depth") + " " + depth;
  }

  // 一条数值行的徽标文案（不含 DOM）：顺序即渲染顺序。
  function entryBadgeTexts(item, entry, stats) {
    var out = [];
    if (entry && entry.isMain) out.push("主战");
    if (item && item.kind === "boss" && entry && entry.threat) {
      out.push(entry.threat === "night" ? "守夜" : "野外");
    }
    if (entry && entry.labelUncertain) out.push(BADGE_LABEL_UNCERTAIN);
    // 只在这一行真的换了深度数值时挂徽标：没有 depthStats 的行在深度模式下显示的
    // 仍是常规值，挂「深夜 N」会骗人（展开区另写「该行无深夜数值」）。
    if (stats && stats.depth && stats.hasDepth) out.push("深夜 " + stats.depth);
    if (stats && stats.hasMutation) out.push(BADGE_MUTATION);
    return out;
  }

  // 数值字段的取值：只有「缺字段 / 不是有限数」才回落到默认值。
  // 不能写成 `Number(x) || fallback`——那会把数据里真实的 0 也改写成 1，
  // 于是「承受削韧倍率 = 0」这种异常在 Windows 端永远出不来，
  // 而 macOS 端（Codable 的 default: 只在缺字段时生效）照原样显示，两端就对不上了。
  // 还要先排掉 null / undefined / 空串：Number(null) === 0、Number("") === 0 都是
  // 有限数，会被当成「数据里真实的 0」；而 macOS 的 bossDouble 走
  // decodeIfPresent，JSON null 与空串都解不出来，落到 default。不先排掉这三种，
  // 「只在缺字段时回落」这条口径落到 Windows 就会在 null 这一格反过来与 macOS 不一致。
  function numberOr(value, fallback) {
    if (value === null || value === undefined || value === "") return fallback;
    var number = Number(value);
    return isFinite(number) ? number : fallback;
  }

  // 深度 N 的那一行 depthStats；depth = 0（常规）或该行没有深夜数值时为 null。
  function depthStatsFor(entry, depth) {
    var level = depthValue(depth);
    if (!level) return null;
    var table = entry && entry.depthStats;
    if (!table || typeof table !== "object") return null;
    return table[String(level)] || null;
  }

  // 深度模式下换用 depthStats[N] 的那一组数值。
  // depthStats 只给 hp / hpMultiplier / poiseTakenBase / attackRateBase（已含
  // 常驻缩放 × 深夜修正 × 深度倍率），削韧恢复与异常发动伤害没有深度专属字段，
  // 仍从 deepOfNight（深夜修正，非 null 时）取，没有就用常规值。
  function numbersFor(entry, depth) {
    var level = depthValue(depth);
    var depthRow = depthStatsFor(entry, level);
    var deepNums = level && entry && entry.deepOfNight ? entry.deepOfNight : null;
    var soft = deepNums || entry || {};
    var hard = depthRow || soft;
    return {
      depth: level,
      // 本行在当前模式下是否真的换了数值：深度模式且查得到 depthStats。
      hasDepth: Boolean(depthRow),
      // 该行有没有「深夜专属修正」（2287 条件效果），与深度无关。
      isDeep: Boolean(entry && entry.deepOfNight),
      hp: numberOr(hard.hp, 0),
      hpMultiplier: numberOr(hard.hpMultiplier, 1),
      poiseTakenBase: numberOr(hard.poiseTakenBase, 1),
      attackRateBase: numberOr(hard.attackRateBase, numberOr(entry && entry.attackRateBase, 1)),
      poiseRecoverMultiplier: numberOr(soft.poiseRecoverMultiplier, 1),
      ailmentDamageRateBase: numberOr(soft.ailmentDamageRateBase, 0),
      permScalingIds: Array.isArray(soft.permScalingIds) ? soft.permScalingIds : [],
      depthSpEffectId: depthRow && depthRow.depthSpEffectId !== undefined ? depthRow.depthSpEffectId : null
    };
  }

  function scalingFor(entry, party) {
    var key = tierKey(party);
    if (!key) return null;
    var scaling = entry && entry.scaling;
    return scaling && scaling[key] ? scaling[key] : null;
  }

  // 某个变异档位（mutations[id]）。id 为空 / 查不到时返回 null，页面按「无」处理。
  function mutationFor(data, id) {
    if (id === null || id === undefined || id === "") return null;
    var table = data && data.mutations && typeof data.mutations === "object" ? data.mutations : null;
    if (!table) return null;
    return table[String(id)] || null;
  }

  // 一条 fight / variant 在给定人数、深度、变异档位下的最终数值。
  // 四层缩放互不覆盖，一律连乘：常驻(已在 hp 里) × 深度 × 人数 × 变异。
  function computeStats(entry, party, depth, mutation) {
    var nums = numbersFor(entry, depth);
    var tier = scalingFor(entry, party);
    var hpMul = tier ? numberOr(tier.hp, 1) : 1;
    var poiseTakenMul = tier ? numberOr(tier.poiseTaken, 1) : 1;
    var poiseRecoverMul = tier ? numberOr(tier.poiseRecover, 1) : 1;
    var buildupMul = tier ? numberOr(tier.buildupRate, 1) : 1;
    var ailmentMul = tier ? numberOr(tier.ailmentDamageRate, 1) : 1;
    // 人数缩放的攻击力倍率：只有 7744 / 7753 / 7754 / 7758 四档不是 1
    //（双人 ×1.1、三人 ×1.2，见 notes.multiplayerScalingAudit）。
    var attackMul = tier ? numberOr(tier.attackRate, 1) : 1;
    var mut = mutation && typeof mutation === "object" ? mutation : null;
    var mutHp = mut ? numberOr(mut.hp, 1) : 1;
    var mutAttack = mut ? numberOr(mut.attackRate, 1) : 1;
    var mutRune = mut ? numberOr(mut.runeRate, 1) : 1;
    var poiseTakenTotal = nums.poiseTakenBase * poiseTakenMul;
    var poise = Number(entry && entry.poise);
    // poise < 0（数据集 caveat 3：一般是子弹/投射物实体）= 不吃削韧；
    // poise === 0 是另一回事（该实体没有削韧槽），不能和 -1 一起显示成「有效韧性 0」。
    var poiseKind = !isFinite(poise) || poise < 0 ? "none" : (poise === 0 ? "zero" : "value");
    var noPoise = poiseKind !== "value";
    // 分母必须是正的有限数，否则算不出有效韧性（口径与 macOS 端
    // BossFight.effectivePoise(for:depth:) 的 `factor > 0, factor.isFinite` 一致）。
    var poiseTakenOk = isFinite(poiseTakenTotal) && poiseTakenTotal > 0;
    return {
      depth: nums.depth,
      hasDepth: nums.hasDepth,
      isDeep: nums.isDeep,
      tier: tier,
      tierKey: tierKey(party),
      hp: Math.round(nums.hp * hpMul * mutHp),
      hpSingle: Math.round(nums.hp * mutHp),
      hpBase: Number(entry && entry.hpBase) || 0,
      hpMultiplier: nums.hpMultiplier,
      poise: noPoise ? null : poise,
      // 原始 superArmorDurability：poiseCaption 的 none / zero 两支要把它写出来。
      // 缺字段 / 非数字时取 -1，与 macOS 端 `bossDouble(.poise, default: -1)` 同一个回落值。
      poiseRaw: isFinite(poise) ? poise : -1,
      poiseKind: poiseKind,
      poiseTakenTotal: poiseTakenTotal,
      poiseTakenOk: poiseTakenOk,
      effectivePoise: noPoise || !poiseTakenOk ? null : poise / poiseTakenTotal,
      poiseRecover: numberOr(entry && entry.poiseRecover, 0) * nums.poiseRecoverMultiplier * poiseRecoverMul,
      ailmentDamageRate: nums.ailmentDamageRateBase * ailmentMul,
      buildupRate: buildupMul,
      poisonRate: tier ? numberOr(tier.poisonRate, 1) : 1,
      attackRate: nums.attackRateBase * attackMul * mutAttack,
      attackRateBase: nums.attackRateBase,
      partyAttackRate: attackMul,
      hasMutation: Boolean(mut),
      mutationHp: mutHp,
      mutationAttack: mutAttack,
      runeRate: mutRune,
      permScalingIds: nums.permScalingIds,
      depthSpEffectId: nums.depthSpEffectId
    };
  }

  // 展开态「深夜各深度」小表的五行：血量 / 攻击倍率 / 承受削韧，都按当前人数
  //（与当前选中的变异档位）换算。没有 depthStats 的行返回 null，页面写
  //「该行无深夜数值」。
  function depthRows(entry, party, mutation) {
    if (!entry || !entry.depthStats || typeof entry.depthStats !== "object") return null;
    var rows = [];
    DEPTHS.forEach(function (depth) {
      if (!entry.depthStats[String(depth)]) return;
      var stats = computeStats(entry, party, depth, mutation);
      rows.push({
        depth: depth,
        hp: stats.hp,
        attackRate: stats.attackRate,
        poiseTaken: stats.poiseTakenTotal
      });
    });
    return rows.length ? rows : null;
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

  // 字符串化：null / undefined 一律给空串。名字相关字段在数据里可能缺，
  // 页面又要拿它们判空，不能让 "undefined" 渲染出去。
  // 叫 asText 而不是 text：本文件里好几处把局部变量 / 参数命名成 text，重名会踩坑。
  function asText(value) {
    return value === null || value === undefined ? "" : String(value);
  }

  // 名字的显示口径（schemaVersion 3）：
  //   nameZh 非空            → 主标题 nameZh，副标题 nameEn；
  //   nameZh 空、有 nameEn   → 主标题 nameEn，副标题 nameZhFallback（旧手工译名）；
  //   只剩 nameZhFallback    → 主标题就用它；
  //   三者都没有             → 才轮到「未知敌人 cXXXX」。
  // 关键点：「未知敌人」不再由页面顶掉英文名。数据里 chrid-fallback 的两组本来就把
  // 「未知敌人 c7931」写在 nameZh 里，走第一支；页面只在真的一个名字都没有时自己拼。
  function displayName(boss) {
    var zh = asText(boss && boss.nameZh);
    var en = asText(boss && boss.nameEn);
    var fallback = asText(boss && boss.nameZhFallback);
    var chrIds = boss && Array.isArray(boss.chrIds) ? boss.chrIds : [];
    var source = asText(boss && boss.nameSource);
    var info = {
      primary: "",
      secondary: "",
      // usesFallback：副标题（或主标题）用的是 nameZhFallback，要挂「参考译名」徽标。
      usesFallback: false,
      // fallbackName：无论有没有用上，都保留原串给搜索索引与展开区说明。
      fallbackName: fallback,
      // gameTextName：名字直接来自本作游戏文本（nameZh 非空且不是 chrid 兜底）。
      gameTextName: Boolean(zh) && source !== "chrid-fallback",
      approx: Boolean(boss && boss.nameApprox),
      inferred: Boolean(boss && boss.nameInferred),
      unknown: false
    };
    if (zh) {
      info.primary = zh;
      info.secondary = en && en !== zh ? en : "";
      return info;
    }
    if (en) {
      info.primary = en;
      info.secondary = fallback;
      info.usesFallback = Boolean(fallback);
      return info;
    }
    if (fallback) {
      info.primary = fallback;
      info.usesFallback = true;
      return info;
    }
    info.primary = chrIds.length ? "未知敌人 c" + chrIds[0] : "未知敌人";
    info.unknown = true;
    return info;
  }

  // 名字相关徽标（顺序即渲染顺序）。全部灰色：它们说明「这名字的可信度」，
  // 不是首领属性，不能和分组 / 变体徽标抢颜色。
  function nameBadges(info, boss) {
    var out = [];
    var source = asText(boss && boss.nameSource);
    var sourceText = NAME_SOURCE_BADGES[source];
    if (sourceText) out.push({ text: sourceText, kind: "gray" });
    else if (info.inferred) out.push({ text: BADGE_NAME_INFERRED, kind: "gray" });
    if (info.approx) out.push({ text: BADGE_NAME_APPROX, kind: "gray" });
    if (info.usesFallback) out.push({ text: BADGE_NAME_FALLBACK, kind: "gray" });
    return out;
  }

  function entryLabel(entry, index) {
    var label = entry && entry.labelZh ? String(entry.labelZh) : "";
    if (label) return label;
    if (entry && entry.labelEn) return String(entry.labelEn);
    return "变体 " + (index + 1);
  }

  // 某个分组下参与「代表行」评选的候选行。三步过滤，任一步没有候选就原样放行：
  //   1. 守夜 / 野外分组先按 threat 过滤——同一组首领可能两种档位都有（数据里 6 组），
  //      在「野外」分组下就该看野外那几行，而不是血量更高的守夜行；
  //   2. 再收敛到 isMain（夜王的主战行**不唯一**，多阶段 / 多体有 2～5 条）；
  //   3. 最后排除 noReward = true 的行（整组都 noReward 就不排除）。
  //
  // 第 3 步的位置是两端约定好的：**必须在 isMain 之后**。夜王的主战行几乎都是
  // noReward = true（奖励挂在远征结算上，不在 NpcParam 的 getSoul/掉落表里），
  // 把这一步提到 isMain 之前会把整组主战行踢掉——玛利斯的代表行会从 12,687 掉到
  // 3,045、格拉狄乌斯会从 npcId 75000020 变成 75000000。放在 isMain 之后，18 位
  // 夜王的代表行一条不变，只修掉真正抢位的模板/无奖励行：恶兆妖鬼的「教程」行
  //（21300520，hp 9920）→ 21300030、神皮使徒守夜的「基准」行（35600900）→
  // 35600110、火焰战车的「血条实体」（44600015，hp 8009）→ 44600010 等 16 组。
  function candidateEntries(entries, group) {
    var pool = Array.isArray(entries) ? entries.filter(Boolean) : [];
    if (group === "night" || group === "field") {
      var byThreat = pool.filter(function (entry) { return entry.threat === group; });
      if (byThreat.length) pool = byThreat;
    }
    var mains = pool.filter(function (entry) { return entry.isMain; });
    if (mains.length) pool = mains;
    var rewarding = pool.filter(function (entry) { return !entry.noReward; });
    return rewarding.length ? rewarding : pool;
  }

  // 候选行里血量最高的一条（同血量取 npcId 较小者）。排序用 1 人常规血量，
  // 与当前人数 / 深度 / 变异设置无关，保证头条行不会跟着设置跳。
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

  // 整张卡片的「深夜专属修正」覆盖情况：all = 每条数值行都有 deepOfNight，
  // some = 部分行有，none = 都没有。深度倍率（depthStats）几乎每行都有，
  // 所以这里说的是 2287 条件效果那一层，展开区的说明按它写。
  function deepCoverage(item) {
    var entries = item && Array.isArray(item.entries) ? item.entries : [];
    if (!entries.length) return "none";
    var hit = 0;
    entries.forEach(function (entry) { if (entry && entry.deepOfNight) hit += 1; });
    if (!hit) return "none";
    return hit === entries.length ? "all" : "some";
  }

  // 整张卡片有没有深度数值（depthStats）。一条都没有的卡在深度模式下
  // 要直说「该行无深夜数值」，不能默默显示常规值。
  function depthCoverage(item) {
    var entries = item && Array.isArray(item.entries) ? item.entries : [];
    if (!entries.length) return "none";
    var hit = 0;
    entries.forEach(function (entry) { if (entry && entry.depthStats) hit += 1; });
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
        nameBadges: [],
        nameNote: "",
        nameEvidence: null,
        nameFallback: "",
        nameFallbackNote: "",
        nameSourceUrl: "",
        hidden: false,
        noReward: false,
        depthChanceWeights: lord.depthChanceWeights && typeof lord.depthChanceWeights === "object"
          ? lord.depthChanceWeights
          : null,
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
        nameBadges: nameBadges(info, boss),
        nameNote: asText(boss.nameNote),
        nameEvidence: boss.nameEvidence && typeof boss.nameEvidence === "object" ? boss.nameEvidence : null,
        nameFallback: info.fallbackName,
        nameFallbackNote: asText(boss.nameZhFallbackNote),
        nameSourceUrl: asText(boss.nameSourceUrl),
        // hidden：整组不掉奖励且（不吃削韧 ∪ 名字连社区都认不出 ∪ 社区标为杂兵）的
        // 召唤物 / 投射物实体。默认不显示，由工具条的「显示隐藏实体」开关放出来。
        hidden: Boolean(boss.hidden),
        // noReward 只作展开区小字，不影响显示：Storm King / 蚯蚓脸这类也不掉奖励，
        // 但它们是玩家真会遇到的首领。
        noReward: Boolean(boss.noReward),
        depthChanceWeights: null,
        // weakness 只存在于 NightBossMenuParam（数据集 caveat 8），守夜 / 野外 Boss 根本没有这个字段。
        // 这里必须是 null（= 没有官方标注）而不是 []（= 官方标注为空），否则页面会凭空给出否定结论。
        weakness: null,
        description: "",
        entries: entries,
        // 卡片自身主分组下的代表行；渲染时按当前分组重新取（见 representativeEntry）。
        main: representativeEntry(entries, groups[0]),
        idText: "chr " + (Array.isArray(boss.chrIds) ? boss.chrIds.join(" / ") : "?"),
        // nameSource 是内部枚举（npcname / community / chrid-fallback…），不进全文搜索串；
        // chrId / npcId 这类行号进 numbers，按前缀匹配。
        // nameZhFallback 必须进搜索串：schemaVersion 3 把「大型黄金河马」这类旧译名
        // 移出了 nameZh，不收进索引的话用户搜「河马」就再也搜不到这张卡。
        search: folder(joinSearch([
          boss.nameZh, boss.nameEn, boss.nameZhFallback
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

  // showHidden 缺省为 false：hidden = true 的组（召唤物 / 投射物等非首领实体）默认不出现。
  function filterItems(items, group, query, fold, showHidden) {
    var folder = typeof fold === "function" ? fold : defaultFold;
    var needle = folder(String(query == null ? "" : query).trim());
    return items.filter(function (item) {
      if (!showHidden && item.hidden) return false;
      if (group && !itemInGroup(item, group)) return false;
      return itemMatches(item, needle);
    });
  }

  // 数据集里是否存在深度数值；没有的话顶部「模式」下拉只留「常规」。
  function hasDepthData(data) {
    if (!data) return false;
    var found = false;
    var scan = function (entries) {
      (entries || []).forEach(function (entry) { if (entry && entry.depthStats) found = true; });
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

  // digits 默认 3（缩放档位表里的 ×0.55 / ×1.428 需要三位）；
  // 「代表行承伤偏高」的徽标固定两位，与 macOS 端
  // BossFormat.multiplier(_:digits: 2) 一致。
  function fmtMul(value, digits) {
    if (value === null || value === undefined || !isFinite(Number(value))) return "—";
    return "×" + fmtNumber(value, digits === undefined ? 3 : digits);
  }

  // 人数缩放明细表里的「攻击力」列：绝大多数档位是 1，写「不变」比写「×1」
  // 更直接地回答用户的问题「多人是不是只是血更厚」。
  function fmtAttackRate(value) {
    // 与 fmtMul 同一条缺值口径：null / undefined / 空串都是「没有这个数」，
    // 不能走 Number(null) === 0 那条路写成「×0」。
    if (value === null || value === undefined || value === "") return "—";
    var number = Number(value);
    if (!isFinite(number)) return "—";
    return number === 1 ? "不变" : fmtMul(number, 3);
  }

  // kind 来自 computeStats().poiseKind，与 macOS 端 BossPoiseKind.placeholder 同表：
  //   none = poise < 0（不吃削韧）、zero = poise === 0（没有削韧槽）、
  //   value = poise > 0 但承受削韧倍率为 0 / 非有限（数据异常）——此时不能写
  //   「不吃削韧」，那是另一回事，两端一律给占位符「—」，原因写在下面的小字里。
  function fmtPoise(value, kind) {
    if (value === null || value === undefined) {
      if (kind === "zero") return "无削韧槽";
      if (kind === "value") return "—";
      return "不吃削韧";
    }
    return fmtNumber(value, 1);
  }

  // 展开态「有效韧性」下面的小字，四支全部与 macOS 端
  // BossRowText.poiseCaption(poise:poiseTakenTotal:kind:hasEffectivePoise:) 逐字一致：
  //   能算出有效韧性 → 「韧性 120 ÷ 承受削韧 0.55」；
  //   poise < 0       → 「superArmorDurability = -1」；
  //   poise = 0       → 「superArmorDurability = 0，该实体没有削韧槽」；
  //   倍率异常        → 「承受削韧倍率异常（N）」。
  function poiseCaption(stats) {
    if (stats.effectivePoise !== null) {
      return "韧性 " + fmtNumber(stats.poiseRaw, 0) + " ÷ 承受削韧 " + fmtNumber(stats.poiseTakenTotal, 3);
    }
    if (stats.poiseKind === "zero") return "superArmorDurability = 0，该实体没有削韧槽";
    if (stats.poiseKind === "none") return "superArmorDurability = " + fmtNumber(stats.poiseRaw, 0);
    return "承受削韧倍率异常（" + fmtNumber(stats.poiseTakenTotal, 3) + "）";
  }

  // 变异档位下拉的一行文案：三个倍率都写出来，用户不用去底部对表。
  function mutationOptionLabel(id, mutation) {
    if (!mutation) return "档位 " + id;
    return "血量 " + fmtMul(mutation.hp, 3) + " · 攻击 " + fmtMul(mutation.attackRate, 3) +
      " · 卢恩 " + fmtMul(mutation.runeRate, 3) + "（档位 " + id + "）";
  }

  // ------------------------------------------------------------ 页面状态

  var state = {
    party: 1,
    group: "nightlords",
    query: "",
    // 0 = 常规，1–5 = 深夜的深度。原来的布尔开关已经换成这个下拉。
    depth: 0,
    showHidden: false,
    // 每条数值行各自选中的变异档位：key = "<卡片 uid>#<npcId>"，value = 档位 id 字符串。
    mutation: {},
    data: null,
    items: [],
    hasDepth: false,
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

  function entryKey(item, entry) {
    return item.uid + "#" + String(entry && entry.npcId);
  }

  function selectedMutation(item, entry) {
    var id = state.mutation[entryKey(item, entry)];
    return mutationFor(state.data, id);
  }

  function statsFor(item, entry) {
    return computeStats(entry, state.party, state.depth, selectedMutation(item, entry));
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

  // 「常规 / 深夜·深度 1…5」六选一。深度差别大（最终 Boss 档深度 5 的伤害是深度 1
  // 的 2.27 倍），布尔开关表达不了，所以换成下拉。
  function depthControl() {
    var options = ["<option value='0'" + (state.depth === 0 ? " selected" : "") + ">常规</option>"];
    if (state.hasDepth) {
      DEPTHS.forEach(function (depth) {
        options.push("<option value='" + depth + "'" + (state.depth === depth ? " selected" : "") + ">" +
          esc(depthLabel(state.data, depth)) + "</option>");
      });
    }
    return "<label class='select-field bosses-mode'><span class='sr-only'>深夜模式</span>" +
      "<select data-bosses-depth data-testid='bosses-depth'" + (state.hasDepth ? "" : " disabled") + ">" +
      options.join("") + "</select></label>";
  }

  // 顶部说明一律用游戏内文本（CL_MenuText）。「变异个体」是红化敌人的官方简中叫法，
  // 这里连同 textId 一起写出来，免得用户以为是页面自造词。
  function depthIntro() {
    var data = state.data;
    if (!data || !data.deepOfNightText) return "";
    var table = data.deepOfNightText;
    var desc = table.description && table.description.zh ? String(table.description.zh) : "";
    var lead = state.depth
      ? depthLabel(data, state.depth) + "：当前所有数值已按该深度换算。"
      : "常规模式。切到「" + deepText(data, "deepOfNight") + "」可看各" + deepText(data, "depth") + "的数值。";
    var mutation = "红化敌人在游戏内的正式名称是「" + BADGE_MUTATION + "」（CL_MenuText " +
      (table.mutation && table.mutation.textId ? table.mutation.textId : "338806") + "）。";
    return "<p class='bosses-deep-intro' data-testid='bosses-deep-intro'>" +
      "<strong>" + esc(lead) + "</strong>" + (desc ? "<span>" + esc(desc) + "</span>" : "") +
      "<span>" + esc(mutation) + "</span></p>";
  }

  function shell() {
    return "" +
      "<div class='page-content bosses-content'>" +
      "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>首领数据</h1><p>《黑夜君临》首领的血量、承伤倍率、韧性、深夜深度与人数缩放</p></div>" +
      "</header>" +
      "<section class='card bosses-toolbar' data-testid='bosses-toolbar'>" +
      "<div class='bosses-toolbar-row'>" +
      "<div class='bosses-control'><span class='bosses-control-label'>人数</span>" +
      "<div class='segmented-control bosses-party' role='radiogroup' aria-label='队伍人数' data-testid='bosses-party'>" +
      partyControl() + "</div></div>" +
      "<div class='bosses-control bosses-control--grow'><span class='bosses-control-label'>搜索</span>" +
      "<label class='search-field'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='搜索首领名、参考译名、远征名、变体标签，或输入 npcId / chrId 前缀' autocomplete='off' data-testid='bosses-search'></label></div>" +
      "<div class='bosses-control'><span class='bosses-control-label'>模式</span>" +
      depthControl() + "</div>" +
      "<div class='bosses-control'><span class='bosses-control-label'>隐藏实体</span>" +
      "<label class='switch-control bosses-hidden-switch' title='召唤物 / 投射物等非首领实体：整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出名字 / 被社区标为杂兵。默认不显示。'>" +
      "<input type='checkbox' data-testid='bosses-hidden'>" +
      "<span class='switch-track'></span><span>显示隐藏实体</span></label></div>" +
      "</div>" +
      "<div class='bosses-toolbar-row bosses-toolbar-row--tabs'>" +
      "<div class='segmented-control bosses-group' role='radiogroup' aria-label='首领分组' data-testid='bosses-group'>" +
      groupControl() + "</div>" +
      "<span class='bosses-count' data-testid='bosses-count'>—</span>" +
      "</div>" +
      "<div data-testid='bosses-intro'>" + depthIntro() + "</div>" +
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
      "<div><h1>首领数据</h1><p>《黑夜君临》首领的血量、承伤倍率、韧性、深夜深度与人数缩放</p></div>" +
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
      // 两位小数：与 macOS 端 weaknessNote 的 BossFormat.multiplier(_, digits: 2) 一致。
      return pill(row.zh + " " + fmtMul(row.rate, 2), "amber");
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
    (item.nameBadges || []).forEach(function (badge) {
      badges.push(pill(badge.text, badge.kind));
    });
    if (item.hidden) badges.push(pill(BADGE_HIDDEN, "gray"));
    if (state.depth) {
      // 深度模式下只给真有 depthStats 的卡片挂徽标；一条都没有的卡另在展开区写明。
      var coverage = depthCoverage(item);
      if (coverage === "all") badges.push(pill(deepText(state.data, "depth") + " " + state.depth, "amber"));
      else if (coverage === "some") badges.push(pill("部分行有深夜数值", "amber"));
      // 另有一层「深夜专属修正」（2287 条件效果，22 张卡有）：它把永夜之王 / DLC 的
      // 常驻加成在深夜里压回去，数值已经含在 depthStats 里，但值得标出来。
      // 只看代表行会把格诺斯塔·永夜之王这类首条无深夜修正、其余行有的卡片判错，所以扫全卡。
      var deep = deepCoverage(item);
      if (deep === "all") badges.push(pill("含深夜专属修正", "amber"));
      else if (deep === "some") badges.push(pill("部分行有深夜专属修正", "amber"));
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
          fmtInt(computeStats(row, state.party, state.depth, null).hp);
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

  // 深度模式下代表行没有 depthStats 时要直说这一行回落到了常规值，
  // 否则摘要与卡头徽标看着像在互相打架。
  function summaryHpHint(stats) {
    if (state.depth) {
      if (!stats.hasDepth) return "该行无深夜数值";
      return state.party === 1 ? "含深度倍率" : "深度 1 人 " + fmtInt(stats.hpSingle);
    }
    return state.party === 1 ? "含常驻缩放" : "1 人 " + fmtInt(stats.hpSingle);
  }

  // 多人时敌人攻击力也会上浮的四个档位（7744 / 7753 / 7754 / 7758），
  // 在血量旁边直接标出来——「多人只是血更厚」这个常见误解正是这里错的。
  function partyAttackNote(stats) {
    if (!stats.tier || !(stats.partyAttackRate > 1)) return "";
    return "<div class='bosses-stat-caption bosses-stat-caption--warn'>" +
      esc("多人攻击 " + fmtMul(stats.partyAttackRate, 3) + "：该档位在 " + partyLabel() +
        "时敌人攻击力也会上浮，不只是血条变长。") + "</div>";
  }

  function cardSummary(item, entry) {
    if (!entry) return "<p class='bosses-none'>该首领没有可用的数值行。</p>";
    var stats = computeStats(entry, state.party, state.depth, null);
    return summaryCaption(item, entry) + partyAttackNote(stats) + "<div class='bosses-stat-row'>" +
      statCell(hpMetricTitle(item) + "（" + partyLabel() + "）", fmtInt(stats.hp), summaryHpHint(stats)) +
      statCell("有效韧性", fmtPoise(stats.effectivePoise, stats.poiseKind), stats.effectivePoise === null ? "" : "韧性槽 " + fmtNumber(stats.poise, 0)) +
      statCell("攻击力倍率", fmtMul(stats.attackRate, 3),
        stats.depth && stats.hasDepth ? "深度 " + stats.depth : "常驻") +
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
          "</th><td colspan='6' class='bosses-none'>无缩放数据</td></tr>";
      }
      return "<tr" + (active ? " class='is-active'" : "") + ">" +
        "<th scope='row'>" + esc(row.label) + "</th>" +
        "<td>" + esc(fmtMul(tier.hp)) + "</td>" +
        "<td>" + esc(fmtAttackRate(tier.attackRate)) + "</td>" +
        "<td>" + esc(fmtMul(tier.poiseTaken)) + "</td>" +
        "<td>" + esc(fmtMul(tier.poiseRecover)) + "</td>" +
        "<td>" + esc(fmtMul(tier.buildupRate)) + "</td>" +
        "<td>" + esc(fmtMul(tier.ailmentDamageRate)) + "</td>" +
        "</tr>";
    }).join("");
    return "<table class='bosses-mini-table bosses-scaling-table'>" +
      "<thead><tr><th scope='col'>人数</th><th scope='col'>血量</th><th scope='col'>攻击力</th>" +
      "<th scope='col'>承受削韧</th><th scope='col'>削韧恢复</th><th scope='col'>异常累积</th>" +
      "<th scope='col'>异常发动伤害</th></tr></thead>" +
      "<tbody>" + rows + "</tbody></table>";
  }

  // 「深夜各深度」小表：深度 1–5 的血量 / 攻击倍率 / 承受削韧，全部按当前人数
  //（与本行选中的变异档位）换算，行内高亮当前深度。
  function depthTable(item, entry) {
    var rows = depthRows(entry, state.party, selectedMutation(item, entry));
    if (!rows) {
      return "<p class='bosses-note bosses-note--muted'>该行无深夜数值（数据里没有 depthStats）。</p>";
    }
    var body = rows.map(function (row) {
      var active = row.depth === state.depth;
      return "<tr" + (active ? " class='is-active'" : "") + ">" +
        "<th scope='row'>" + esc(deepText(state.data, "depth") + " " + row.depth) + "</th>" +
        "<td>" + esc(fmtInt(row.hp)) + "</td>" +
        "<td>" + esc(fmtMul(row.attackRate, 3)) + "</td>" +
        "<td>" + esc(fmtMul(row.poiseTaken, 3)) + "</td></tr>";
    }).join("");
    return "<table class='bosses-mini-table bosses-depth-table'>" +
      "<thead><tr><th scope='col'>" + esc(deepText(state.data, "depth")) + "</th>" +
      "<th scope='col'>血量（" + esc(partyLabel()) + "）</th>" +
      "<th scope='col'>攻击倍率</th><th scope='col'>承受削韧</th></tr></thead>" +
      "<tbody>" + body + "</tbody></table>";
  }

  // 「变异个体」块：先列出这一行可能变异成的档位，再给一个「按变异个体计算」下拉。
  // 倍率 spCategory = 203，与常驻 / 深度 / 人数都不同分类，按参数结构推断是再乘一层。
  function mutationBlock(item, entry) {
    var pool = Array.isArray(entry.mutationPool) ? entry.mutationPool : [];
    if (!pool.length) return "";
    var key = entryKey(item, entry);
    var current = state.mutation[key] || "";
    var chips = pool.map(function (id) {
      var mutation = mutationFor(state.data, id);
      if (!mutation) return "<span class='bosses-chip'>" + esc("档位 " + id) + "</span>";
      return "<span class='bosses-chip'>" + esc(mutationOptionLabel(id, mutation)) + "</span>";
    }).join("");
    var options = ["<option value=''" + (current ? "" : " selected") + ">无</option>"].concat(
      pool.map(function (id) {
        var value = String(id);
        return "<option value='" + esc(value) + "'" + (current === value ? " selected" : "") + ">" +
          esc(mutationOptionLabel(id, mutationFor(state.data, id))) + "</option>";
      })
    ).join("");
    return "<div class='bosses-sub'>" + esc(BADGE_MUTATION) + "（可能的变异档位）</div>" +
      "<div class='bosses-chips'>" + chips + "</div>" +
      "<label class='select-field bosses-mutation-field'>" +
      "<span class='sr-only'>按变异个体计算</span>" +
      "<select data-bosses-mutation='" + esc(key) + "' data-testid='bosses-mutation'>" + options + "</select></label>" +
      "<p class='bosses-note bosses-note--muted'>选中档位后，本行上面的数值会在当前基础上再乘一层" +
      "（血量 / 攻击力 / 卢恩）。变异倍率的 spCategory = 203，与常驻(0)、深度(0)、人数(140) 都不同分类，" +
      "不互相覆盖——「再乘一层」是按参数结构推断的，游戏里没有公开说明。</p>";
  }

  function permScalingLine(stats) {
    var table = state.data && state.data.permanentScaling ? state.data.permanentScaling : null;
    if (!table || !stats.permScalingIds.length) return "";
    var chips = stats.permScalingIds.map(function (id) {
      var effect = table[String(id)];
      if (!effect) return "<span class='bosses-chip'>常驻 " + esc(id) + "</span>";
      var factors = [];
      if (Number(effect.hp) !== 1) factors.push("血量 " + fmtMul(effect.hp));
      if (Number(effect.attackRate) !== 1 && effect.attackRate !== undefined) {
        factors.push("攻击 " + fmtMul(effect.attackRate));
      }
      if (Number(effect.poiseTaken) !== 1) factors.push("承受削韧 " + fmtMul(effect.poiseTaken));
      if (Number(effect.poiseRecover) !== 1) factors.push("削韧恢复 " + fmtMul(effect.poiseRecover));
      if (Number(effect.ailmentDamageRate) !== 1) factors.push("异常伤害 " + fmtMul(effect.ailmentDamageRate));
      var text = (effect.nameZh || effect.nameEn || ("常驻 " + id)) + (factors.length ? "（" + factors.join(" · ") + "）" : "");
      return "<span class='bosses-chip'>" + esc(text) + "</span>";
    }).join("");
    return "<div class='bosses-chips'><span class='bosses-sub'>常驻缩放</span>" + chips + "</div>";
  }

  // 行内的补充说明：深夜专属修正、无奖励行。两条都是「为什么这一行的数字长这样」。
  function entryNotes(entry, stats) {
    var out = [];
    if (entry.deepOfNight) {
      out.push("该行另有「深夜专属修正」（2287 条件效果），上表各深度的数值已经把它算进去；" +
        "常规血量 " + fmtInt(entry.hp) + "（1 人）。");
    }
    if (stats.depth && stats.hasDepth && stats.depthSpEffectId) {
      out.push("深度 " + stats.depth + " 用的是 SpEffect " + stats.depthSpEffectId + "。");
    }
    if (entry.noReward) {
      out.push("该行不掉任何奖励（getSoul / chaosMatchingRewardLotId / itemLotId_enemy 全为 0 或 -1），" +
        "通常是模板行、血条实体或演出行；选代表行时会排在同分组的实战行之后。");
    }
    if (!out.length) return "";
    return out.map(function (note) {
      return "<p class='bosses-note bosses-note--muted'>" + esc(note) + "</p>";
    }).join("");
  }

  function entryBlock(item, entry, index) {
    var stats = statsFor(item, entry);
    var tiers = state.data && state.data.scalingTiers ? state.data.scalingTiers : null;
    var caption = scalingCaption(entry, tiers);
    var badges = entryBadgeTexts(item, entry, stats).map(function (text) {
      if (text === "主战") return pill(text, "green");
      if (text === "守夜") return pill(text, "blue");
      if (text === "野外") return pill(text, "green");
      if (text === BADGE_MUTATION) return pill(text, "red");
      return pill(text, "amber");
    });

    var npcIds = Array.isArray(entry.npcIds) ? entry.npcIds : [];
    var idText = "npcId " + String(entry.npcId) + (npcIds.length > 1 ? "（合并 " + npcIds.length + " 行）" : "");

    return "<section class='bosses-entry'>" +
      "<header class='bosses-entry-head'>" +
      "<strong>" + esc(entryLabel(entry, index)) + "</strong>" +
      "<span class='bosses-entry-badges'>" + badges.join("") + "</span>" +
      "<span class='bosses-entry-id'>" + esc(idText) + "</span>" +
      "</header>" +
      "<div class='bosses-stat-row bosses-stat-row--compact'>" +
      statCell("血量（" + partyLabel() + "）", fmtInt(stats.hp),
        stats.depth && stats.hasDepth
          ? "深度 " + stats.depth + " · 1 人 " + fmtInt(stats.hpSingle)
          : "参数原值 " + fmtInt(stats.hpBase) + " × " + fmtNumber(stats.hpMultiplier, 3)) +
      statCell("有效韧性", fmtPoise(stats.effectivePoise, stats.poiseKind), poiseCaption(stats)) +
      statCell("攻击力倍率", fmtMul(stats.attackRate, 3),
        stats.partyAttackRate > 1 ? "含多人 " + fmtMul(stats.partyAttackRate, 3) : "对玩家伤害倍率") +
      statCell("削韧恢复", fmtNumber(stats.poiseRecover, 3), "每秒") +
      statCell("异常累积", fmtMul(stats.buildupRate), "Boss 承受量") +
      statCell("异常发动伤害", fmtMul(stats.ailmentDamageRate), "中毒/腐败 " + fmtMul(stats.poisonRate)) +
      (stats.hasMutation ? statCell("卢恩倍率", fmtMul(stats.runeRate, 3), BADGE_MUTATION) : "") +
      "</div>" +
      "<div class='bosses-sub'>承伤倍率（&gt;1 多吃伤害，&lt;1 抗性）</div>" + rateTable(entry) +
      "<div class='bosses-sub'>异常抗性（累积阈值，越大越难触发）</div>" + resistTable(entry) +
      "<div class='bosses-sub'>" + esc(deepText(state.data, "deepOfNight") + "各" + deepText(state.data, "depth")) +
      "（按 " + esc(partyLabel()) + "换算）</div>" +
      depthTable(item, entry) +
      mutationBlock(item, entry) +
      "<div class='bosses-sub'>多人缩放" + (caption ? "（" + esc(caption) + "）" : "") + "</div>" +
      scalingTable(entry) +
      permScalingLine(stats) +
      entryNotes(entry, stats) +
      "</section>";
  }

  // 卡片级的名字说明：近似匹配的依据、参考译名的来龙去脉、隐藏实体的判据。
  function nameNoteBlock(item) {
    var parts = [];
    if (item.nameNote) parts.push(item.nameNote);
    if (item.nameEvidence && item.nameEvidence.id) {
      var ev = item.nameEvidence;
      parts.push("游戏文本依据：" + (ev.fmg || "FMG") + " " + ev.id +
        "「" + (ev.en || "") + " / " + (ev.zh || "") + "」。");
    }
    if (item.nameFallback) {
      parts.push(item.nameFallbackNote ||
        ("「" + item.nameFallback + "」不是本作的游戏内文本，是按《艾尔登法环》官方简中补的参考译名。"));
    }
    if (item.nameSourceUrl) parts.push("社区来源：" + item.nameSourceUrl);
    if (item.hidden) {
      parts.push("本组默认隐藏：整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出名字 / 被社区标为杂兵，" +
        "判定为召唤物、投射物等非首领实体。");
    }
    if (!parts.length) return "";
    return "<div class='bosses-name-note' data-testid='bosses-name-note'>" +
      "<div class='bosses-sub'>名称与收录说明</div>" +
      parts.map(function (note) {
        return "<p class='bosses-note'>" + esc(note) + "</p>";
      }).join("") + "</div>";
  }

  // 夜王各深度的出现权重（NightBossMenuParam.depth1..5ChanceWeight）。
  // 权重 0 要说清是「该深度不会出现」——永夜之王与救世旗手在深度 1 根本刷不出来。
  function depthChanceBlock(item) {
    var weights = item.depthChanceWeights;
    if (!weights) return "";
    var cells = DEPTHS.map(function (depth) {
      var value = Number(weights[String(depth)]);
      var zero = !isFinite(value) || value === 0;
      return "<td" + (zero ? " class='bosses-zero'" : "") + ">" +
        esc(zero ? "该深度不会出现" : fmtInt(value)) + "</td>";
    }).join("");
    var head = DEPTHS.map(function (depth) {
      return "<th scope='col'>" + esc(deepText(state.data, "depth") + " " + depth) + "</th>";
    }).join("");
    return "<div class='bosses-sub'>各" + esc(deepText(state.data, "depth")) + "出现权重</div>" +
      "<table class='bosses-mini-table bosses-chance-table'><thead><tr>" + head + "</tr></thead>" +
      "<tbody><tr>" + cells + "</tr></tbody></table>" +
      "<p class='bosses-note bosses-note--muted'>权重来自 NightBossMenuParam.depth1..5ChanceWeight，是同一深度内各夜王之间的相对权重，不是百分比。" +
      "守夜 / 野外首领没有按深度的出现权重参数，数据集里也没有。</p>";
  }

  function cardBody(item) {
    if (!item.entries.length) return "<p class='bosses-none'>没有可用的数值行。</p>";
    var head = "";
    if (item.description) {
      head = "<p class='bosses-desc'>" + esc(item.description) + "</p>";
    }
    return head + nameNoteBlock(item) + depthChanceBlock(item) + item.entries.map(function (entry, index) {
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
      "<span class='bosses-entry-count'>" + esc(rowCountText(item.entries.length)) + "</span></div>" +
      cardSummary(item, entry) +
      (expanded ? "<div class='bosses-card-body'>" + cardBody(item) + "</div>" : "");
  }

  function cardHtml(item) {
    var expanded = Boolean(state.expanded[item.uid]);
    return "<article class='card bosses-card" + (expanded ? " is-expanded" : "") +
      (item.hidden ? " is-hidden-entity" : "") + "'" +
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
      var groupName = tierGroupLabel(tier.group);
      return ["duo", "trio"].map(function (which, index) {
        var value = tier[which];
        var label = which === "duo" ? "2 人" : "3 人";
        var first = index === 0
          ? "<th scope='row' rowspan='2'>#" + esc(key) + "<span>" + esc(groupName) + "</span></th>"
          : "";
        if (!value) {
          return "<tr>" + first + "<td>" + esc(label) + "</td><td colspan='6' class='bosses-none'>无数据</td></tr>";
        }
        return "<tr>" + first + "<td>" + esc(label) + "</td>" +
          "<td>" + esc(fmtMul(value.hp)) + "</td>" +
          "<td>" + esc(fmtAttackRate(value.attackRate)) + "</td>" +
          "<td>" + esc(fmtMul(value.poiseTaken)) + "</td>" +
          "<td>" + esc(fmtMul(value.poiseRecover)) + "</td>" +
          "<td>" + esc(fmtMul(value.buildupRate)) + "</td>" +
          "<td>" + esc(fmtMul(value.ailmentDamageRate)) + "</td></tr>";
      }).join("");
    }).join("");

    var audit = Array.isArray(data.notes && data.notes.multiplayerScalingAudit)
      ? data.notes.multiplayerScalingAudit
      : [];

    return "<details class='card bosses-details' data-testid='bosses-tiers'>" +
      "<summary><span class='bosses-summary-title'>人数缩放档位说明</span>" +
      pill(keys.length + " 档", "purple") + "</summary>" +
      "<div class='bosses-details-body'>" +
      "<p class='bosses-note bosses-note--lead'>多人<strong>不是</strong>简单乘倍：血量按档位从 ×1 到 ×3 不等" +
      "（最终 Boss ×2 / ×3，野外常见档 7740 只有 ×1.1 / ×1.2，突袭档 98810 / 98815 完全不加血）；" +
      "7744 / 7753 / 7754 / 7758 四档还会让敌人<strong>攻击力上浮</strong> ×1.1 / ×1.2；" +
      "防御、卢恩与掉落、异常阈值三类字段人数缩放一律不碰，变的只是异常累积量与发动伤害倍率（都往下走）。</p>" +
      "<ul class='bosses-legend'>" +
      "<li><b>血量</b>：多人时 Boss 血量乘这个倍率，页面顶部切人数后所有血量都按它换算。</li>" +
      "<li><b>攻击力</b>：敌人对玩家的伤害倍率（五属性同值）。绝大多数档位「不变」，只有上面四档是 ×1.1 / ×1.2。</li>" +
      "<li><b>承受削韧</b>：Boss 实际吃到的削韧比例。2 人 ×0.55 表示同样的削韧只吃 55%，等价于有效韧性变成约 1.8 倍。</li>" +
      "<li><b>削韧恢复</b>：削韧槽恢复速度倍率，与承受削韧同值。</li>" +
      "<li><b>异常累积</b>：Boss 承受的异常累积量倍率，越小越难打出异常；<b>不是</b>阈值下调，多人并不会更容易上异常。</li>" +
      "<li><b>异常发动伤害</b>：异常触发那一下的伤害倍率（出血/冻伤/睡眠/发狂同值）；中毒与腐败单独由 poisonRate 控制，目前恒为 ×1。</li>" +
      "</ul>" +
      "<div class='table-wrap bosses-table-wrap'><table class='bosses-mini-table bosses-tier-table'>" +
      "<thead><tr><th scope='col'>档位</th><th scope='col'>人数</th><th scope='col'>血量</th>" +
      "<th scope='col'>攻击力</th><th scope='col'>承受削韧</th><th scope='col'>削韧恢复</th>" +
      "<th scope='col'>异常累积</th><th scope='col'>异常发动伤害</th></tr></thead><tbody>" + rows + "</tbody></table></div>" +
      (audit.length
        ? "<div class='bosses-sub'>核实结论（notes.multiplayerScalingAudit）</div>" +
          "<ul class='bosses-caveat-list'>" + audit.map(function (line) {
            return "<li>" + esc(line) + "</li>";
          }).join("") + "</ul>"
        : "") +
      "</div></details>";
  }

  // 深夜各深度的全局控制值（ChaosMatchingRankControlParam）。
  // 这张表里**没有**任何血量 / 攻击倍率，那些在每行的 depthStats 里。
  function depthOverviewBlock(data) {
    var depths = data.deepOfNightDepths && typeof data.deepOfNightDepths === "object"
      ? data.deepOfNightDepths
      : null;
    if (!depths) return "";
    var keys = Object.keys(depths).sort(function (a, b) { return Number(a) - Number(b); });
    if (!keys.length) return "";
    var rows = keys.map(function (key) {
      var row = depths[key] || {};
      var challenge = row.mapChallengeWeight || {};
      var cataclysm = row.cataclysmWeight || {};
      return "<tr><th scope='row'>" + esc(row.labelZh || (deepText(data, "depth") + " " + key)) + "</th>" +
        "<td>" + esc(fmtNumber(row.cursedUncommonRate, 0)) + " / " + esc(fmtNumber(row.cursedRareRate, 0)) + "</td>" +
        "<td>" + esc(fmtNumber(challenge.map, 0) + " / " + fmtNumber(challenge.nightlord, 0) + " / " + fmtNumber(challenge.none, 0)) + "</td>" +
        "<td>" + esc(fmtNumber(cataclysm["0"], 0) + " / " + fmtNumber(cataclysm["1"], 0) + " / " + fmtNumber(cataclysm["2"], 0)) + "</td></tr>";
    }).join("");
    var desc = data.deepOfNightText && data.deepOfNightText.description
      ? String(data.deepOfNightText.description.zh || "")
      : "";
    return "<details class='card bosses-details' data-testid='bosses-depths'>" +
      "<summary><span class='bosses-summary-title'>" + esc(deepText(data, "deepOfNight") + "各" + deepText(data, "depth") + "概览") +
      "</span>" + pill(keys.length + " 档", "blue") + "</summary>" +
      "<div class='bosses-details-body'>" +
      (desc ? "<p class='bosses-desc'>" + esc(desc) + "</p>" : "") +
      "<p class='bosses-note bosses-note--lead'>这张表来自 ChaosMatchingRankControlParam，只管全局控制，<strong>不含任何血量 / 攻击倍率</strong>——" +
      "各深度的数值倍率在每条数值行的「" + esc(deepText(data, "deepOfNight") + "各" + deepText(data, "depth")) + "」小表里。" +
      "最终首领档深度 1→5 血量 ×1.3→×1.718、攻击 ×1.3→×2.947，攻击力涨得远比血量快。</p>" +
      "<table class='bosses-mini-table bosses-depth-overview'>" +
      "<thead><tr><th scope='col'>" + esc(deepText(data, "depth")) + "</th>" +
      "<th scope='col'>诅咒遗物率（不常见 / 稀有）</th>" +
      "<th scope='col'>地图挑战权重（地图 / 夜王 / 无）</th>" +
      "<th scope='col'>天变数量权重（0 / 1 / 2）</th></tr></thead>" +
      "<tbody>" + rows + "</tbody></table></div></details>";
  }

  // 「变异个体出现只数」：ChaosMatchingMutationCategoryParam 给的是**只数**，
  // 不是百分比概率，这一点最容易误读，所以写在标题下面第一行。
  function mutationCategoryBlock(data) {
    var list = Array.isArray(data.mutationCategories) ? data.mutationCategories : [];
    if (!list.length) return "";
    var rows = list.map(function (row) {
      var counts = row.mutatedCount || {};
      return "<tr><td>" + esc(row.mapZh || row.mapEn || row.mapId) + "</td>" +
        "<td>" + esc(row.categoryZh || row.categoryEn || row.categoryId) + "</td>" +
        DEPTHS.map(function (depth) {
          var value = Number(counts[String(depth)]);
          var zero = !isFinite(value) || value === 0;
          return "<td" + (zero ? " class='bosses-zero'" : "") + ">" + esc(zero ? "0" : String(value)) + "</td>";
        }).join("") + "</tr>";
    }).join("");
    var mutations = data.mutations && typeof data.mutations === "object" ? data.mutations : {};
    var mutationKeys = Object.keys(mutations).sort(function (a, b) { return Number(a) - Number(b); });
    var mutationRows = mutationKeys.map(function (key) {
      var mutation = mutations[key];
      return "<tr><th scope='row'>" + esc(key) + "</th>" +
        "<td>" + esc(fmtMul(mutation.hp, 3)) + "</td>" +
        "<td>" + esc(fmtMul(mutation.attackRate, 3)) + "</td>" +
        "<td>" + esc(fmtMul(mutation.runeRate, 3)) + "</td>" +
        "<td>" + esc(mutation.statNameEn || "—") + "</td></tr>";
    }).join("");
    return "<details class='card bosses-details' data-testid='bosses-mutations'>" +
      "<summary><span class='bosses-summary-title'>" + esc(BADGE_MUTATION) + "出现只数</span>" +
      pill(list.length + " 行", "red") + "</summary>" +
      "<div class='bosses-details-body'>" +
      "<p class='bosses-note bosses-note--lead'>表里的数字是「该地图、该深度下这一类敌人有<strong>几只</strong>会变异」，" +
      "<strong>不是百分比概率</strong>——这点最容易读错。野外首领与封印监牢首领深度 1 全是 0，也就是深度 1 遇不到变异的野外/监牢首领。</p>" +
      "<div class='table-wrap bosses-table-wrap'><table class='bosses-mini-table bosses-mutation-table'>" +
      "<thead><tr><th scope='col'>地图</th><th scope='col'>敌人类别</th>" +
      DEPTHS.map(function (depth) {
        return "<th scope='col'>" + esc(deepText(data, "depth") + " " + depth) + "</th>";
      }).join("") + "</tr></thead><tbody>" + rows + "</tbody></table></div>" +
      (mutationRows
        ? "<div class='bosses-sub'>变异档位倍率（SpEffectSetParam → 数值档位）</div>" +
          "<table class='bosses-mini-table bosses-mutation-tier-table'>" +
          "<thead><tr><th scope='col'>档位</th><th scope='col'>血量</th><th scope='col'>攻击</th>" +
          "<th scope='col'>卢恩</th><th scope='col'>Paramdex 行名</th></tr></thead>" +
          "<tbody>" + mutationRows + "</tbody></table>"
        : "") +
      "<p class='bosses-note bosses-note--muted'>哪些敌人能变异 = NpcParam.chaosMatchingSpEffectSetParamId != -1 的行" +
      "（数据集里 mutationPool 非空的即是）。按刷新点组织的 ChaosMatchingMutationEnemyTableParam 没法直接对到某一行 NpcParam，未收录。</p>" +
      "</div></details>";
  }

  function versionBlock(data) {
    var counts = {
      lords: Array.isArray(data.nightlords) ? data.nightlords.length : 0,
      night: 0,
      field: 0,
      both: 0,
      hidden: 0,
      rows: 0
    };
    (Array.isArray(data.nightBosses) ? data.nightBosses : []).forEach(function (boss) {
      var groups = bossGroups(boss);
      if (groups.indexOf("night") !== -1) counts.night += 1;
      if (groups.indexOf("field") !== -1) counts.field += 1;
      if (groups.length > 1) counts.both += 1;
      if (boss.hidden) counts.hidden += 1;
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
      (counts.hidden ? " · 隐藏实体 " + counts.hidden : "") +
      " · 数值行 " + counts.rows + "</dd></div>" +
      "</dl>" +
      (sources ? "<div class='bosses-sub'>来源</div><ul class='bosses-source-list'>" + sources + "</ul>" : "") +
      "</div></details>";
  }

  function footerHtml(data) {
    return caveatsBlock(data) + scalingTiersBlock(data) + depthOverviewBlock(data) +
      mutationCategoryBlock(data) + versionBlock(data);
  }

  // ------------------------------------------------------------ 渲染与事件

  function renderList() {
    if (!dom) return;
    var list = dom.querySelector("[data-testid='bosses-list']");
    var empty = dom.querySelector("[data-testid='bosses-empty']");
    var count = dom.querySelector("[data-testid='bosses-count']");
    var intro = dom.querySelector("[data-testid='bosses-intro']");
    if (intro) intro.innerHTML = depthIntro();
    if (!list) return;
    var visible = filterItems(state.items, state.group, state.query, fold, state.showHidden);
    list.innerHTML = visible.map(cardHtml).join("");
    if (empty) empty.hidden = visible.length > 0;
    if (count) {
      var inGroup = state.items.filter(function (item) { return itemInGroup(item, state.group); });
      var total = inGroup.filter(function (item) { return state.showHidden || !item.hidden; }).length;
      var hiddenCount = inGroup.filter(function (item) { return item.hidden; }).length;
      var depthText = state.depth ? " · " + depthLabel(state.data, state.depth) : "";
      var hiddenText = "";
      if (hiddenCount) {
        hiddenText = state.showHidden
          ? " · 含隐藏实体 " + hiddenCount + " 个"
          : " · 已隐藏 " + hiddenCount + " 个非首领实体";
      }
      count.textContent = "显示 " + visible.length + " / " + total + " 个首领 · " +
        partyLabel() + depthText + hiddenText;
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

  function findCard(uid) {
    // uid 里可能带单引号（如 "nb:The Duke's Dear Freja@7800"），不走选择器拼接。
    var nodes = dom.querySelectorAll("[data-bosses-card]");
    for (var n = 0; n < nodes.length; n += 1) {
      if (nodes[n].getAttribute("data-bosses-card") === uid) return nodes[n];
    }
    return null;
  }

  function renderCard(uid, focusSelector, focusValue) {
    if (!dom) return;
    var node = findCard(uid);
    if (!node) return;
    var item = null;
    for (var i = 0; i < state.items.length; i += 1) {
      if (state.items[i].uid === uid) { item = state.items[i]; break; }
    }
    if (!item) return;
    // innerHTML 会连刚被点击的那个控件一起销毁，焦点会掉回 body；
    // 重绘后按属性值找回新控件再 focus()，Tab + Enter 浏览才不用从页首重来。
    var doc = node.ownerDocument || (dom && dom.ownerDocument);
    var hadFocus = Boolean(doc && doc.activeElement && node.contains(doc.activeElement));
    node.classList.toggle("is-expanded", Boolean(state.expanded[uid]));
    node.innerHTML = cardInner(item);
    if (!hadFocus) return;
    var attribute = focusSelector || "data-bosses-toggle";
    var value = focusValue === undefined ? uid : focusValue;
    var targets = node.querySelectorAll("[" + attribute + "]");
    for (var h = 0; h < targets.length; h += 1) {
      if (targets[h].getAttribute(attribute) === value) { targets[h].focus(); break; }
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

    dom.addEventListener("change", function (event) {
      var mutation = event.target.closest("[data-bosses-mutation]");
      if (mutation) {
        var key = mutation.getAttribute("data-bosses-mutation");
        var value = mutation.value || "";
        if (value) state.mutation[key] = value;
        else delete state.mutation[key];
        // key = "<uid>#<npcId>"，uid 自己不含 "#"，按最后一个 "#" 切回卡片 uid。
        renderCard(key.slice(0, key.lastIndexOf("#")), "data-bosses-mutation", key);
        return;
      }
      var depth = event.target.closest("[data-bosses-depth]");
      if (depth) {
        state.depth = depthValue(depth.value);
        renderList();
        return;
      }
      var hidden = event.target.closest("[data-testid='bosses-hidden']");
      if (hidden) {
        state.showHidden = Boolean(hidden.checked);
        renderList();
      }
    });

    var search = dom.querySelector("[data-testid='bosses-search']");
    if (search) {
      search.addEventListener("input", function (event) {
        state.query = event.target.value || "";
        renderList();
      });
    }
  }

  function applyDepthAvailability() {
    if (!dom) return;
    var select = dom.querySelector("[data-testid='bosses-depth']");
    if (!select) return;
    if (!state.hasDepth) {
      state.depth = 0;
      select.disabled = true;
      var control = select.closest(".select-field");
      if (control) control.classList.add("is-disabled");
    }
  }

  function renderData(data) {
    if (!dom) return;
    state.data = data;
    state.items = buildItems(data, fold);
    state.hasDepth = hasDepthData(data);
    if (!state.hasDepth) state.depth = 0;
    state.mutation = {};
    dom.innerHTML = shell();
    bindEvents();
    var search = dom.querySelector("[data-testid='bosses-search']");
    if (search && state.query) search.value = state.query;
    var hidden = dom.querySelector("[data-testid='bosses-hidden']");
    if (hidden) hidden.checked = state.showHidden;
    applyDepthAvailability();
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
      depthValue: depthValue,
      numberOr: numberOr,
      numbersFor: numbersFor,
      depthStatsFor: depthStatsFor,
      depthRows: depthRows,
      scalingFor: scalingFor,
      mutationFor: mutationFor,
      computeStats: computeStats,
      rateClass: rateClass,
      rateNote: rateNote,
      isImmune: isImmune,
      displayName: displayName,
      nameBadges: nameBadges,
      entryLabel: entryLabel,
      mainEntry: mainEntry,
      mainRows: mainRows,
      candidateEntries: candidateEntries,
      representativeEntry: representativeEntry,
      itemMatches: itemMatches,
      bossGroups: bossGroups,
      deepCoverage: deepCoverage,
      depthCoverage: depthCoverage,
      itemInGroup: itemInGroup,
      topDamageTypes: topDamageTypes,
      buildItems: buildItems,
      filterItems: filterItems,
      hasDepthData: hasDepthData,
      deepText: deepText,
      depthLabel: depthLabel,
      fmtInt: fmtInt,
      fmtNumber: fmtNumber,
      fmtMul: fmtMul,
      fmtAttackRate: fmtAttackRate,
      fmtPoise: fmtPoise,
      poiseCaption: poiseCaption,
      mutationOptionLabel: mutationOptionLabel,
      tierGroupLabel: tierGroupLabel,
      scalingCaption: scalingCaption,
      rowCountText: rowCountText,
      entryBadgeTexts: entryBadgeTexts,
      DAMAGE_TYPES: DAMAGE_TYPES,
      AILMENTS: AILMENTS,
      DEPTHS: DEPTHS,
      GROUP_LABELS: GROUP_LABELS,
      GROUP_TITLES: GROUP_TITLES,
      NAME_SOURCE_BADGES: NAME_SOURCE_BADGES
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
