// 首领数据页。页面模块契约见 renderer/pages/README.md。
// 本文件由「首领数据」功能开发者独占：只改这里与 pages/bosses.css。
//
// 数据：ctx.getGameData("bosses") → resources/bosses.json（bossesSchemaVersion 4）。
// 分组（bossesSchemaVersion 4 起）按出场场合 roles，不再看 tier / tiers：
//   tier 取自 multiPlayCorrectionParamId 的档位名，只是缩放档位——铃珠猎人野外版 31000010
//   挂的就是 7753「Night Boss Threat」，按它分组会把一批场景头目错归到守夜首领。
//   默认六组：夜王 / 守夜首领 / 据点首领 / 场景头目 / 封印监牢 / 其它场合；打开「显示隐藏实体」
//   后再多「随从/召唤物」「未放置」两组。规则见 roleGroups()；
//   tier / tiers / 行级 threat 只留在展开区作「威胁档位」小字。
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
//
// 双端对齐（macOS：macos/Sources/RelicCore/BossData.swift）——下面几条规则只有一份正文，
// 改这边必须同时改那边：
//   · 名字四级回退：nameZh → nameZhFallback（标「参考译名 · 非本作游戏文本」）
//     → displayFallbackZh（标「无游戏内名称」）→ nameEn；副标题恒为英文名。
//     搜索索引把 nameZhFallback 与 displayFallbackZh 都收进去。见 displayName()。
//   · 代表行：按当前分组过滤 roles → isMain 收敛 → 排除演出行（isStagingRow）→ 排除 noReward
//     → 血量最高（同血量取 npcId 小者），每一步没有候选就原样放行。见 candidateEntries()。
//   · 分组：规则正文是 macOS 端 BossCard.Group 的文档注释（「两端唯一正式版本」），这边照抄：
//     夜王卡只进「夜王」；守夜 / 野外首领按 roles 多重归属；「随从/召唤物」「未放置」是两个
//     默认隐藏的分组；展开区默认收起只有这两种场合的行（macOS 的 displayRows(includeHidden:)）。
//     见 GROUP_ORDER / ROLE_GROUP / HIDDEN_ROLES / roleGroups() / displayEntries()。
//   · 默认隐藏：hidden 的非首领实体与「全部场合都是未放置 / 随从」的组共用「显示隐藏实体」开关；
//     底部那句交代（hiddenSummaryText / ROLE_TEXT.hiddenSummary）与 macOS 的 hiddenSummary 逐字相同。
//   · 文案：TEXT 对应 macOS 的 BossRowText，ROLE_TEXT 对应 BossRoleText（键集合双向相同、逐字相同）。
//     windows/tests/bosses_parity.test.mjs 直接读仓库内 macos/ 的 Swift 源码逐项比对这两张表，并把
//     RelicCoreChecks 里的对照表（代表行、各分组开关前后的条数、出处摘要、收录统计、底部隐藏说明）
//     拿来跑本页的实现；两端同仓库，这些对照一律不跳过。
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

  // 多人缩放档位组名（macOS 的 BossScalingGroup.title(for:)，两端同一套）。**它们只是
  // multiPlayCorrectionParamId 的档位名，不是出场场合**：场景头目行照样可能挂「守夜首领威胁档」。
  // 名字不改（改就得两端一起改），容易误读的行由 threatRoleMismatch() 补一句 threatTierNote。
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

  // 两端必须逐字相同的文案，一一对应 macOS 端 RelicCore 的 `BossRowText`
  // （见 macos/Sources/RelicCore/BossData.swift）。这里集中成一张表而不是散在
  // 模板字符串里，是因为上一轮就是散着写才跑偏的：同一枚徽标 macOS 写「深夜数值」、
  // Windows 写「深夜 4」，两边的注释却都声称「逐字一致」。
  // windows/tests/bosses.test.mjs 逐条断言本表，macOS 端 checkBossDataParityText()
  // 断言 BossRowText 的同名常量。
  var TEXT = {
    // 行内徽标：Paramdex 名带 "?"，阶段 / 用途属社区推测。
    labelUncertainBadge: "标签为社区推测",
    // 行内 / 卡头徽标：这一行当前显示的是深夜数值（depthStats 口径，与深度几无关）。
    deepRowBadge: "深夜数值",
    deepRowBadgePartial: "部分行有深夜数值",
    // 行内 / 卡头徽标：额外吃一组「深夜专属」的常驻修正（deepOfNight，只有 31 行）。
    deepExclusiveBadge: "深夜专属修正",
    deepExclusiveBadgePartial: "部分行有深夜专属修正",
    // 名字徽标（与 macOS 的 BossNameBadge.text 一一对应）。
    nameFallbackBadge: "参考译名 · 非本作游戏文本",
    nameApproxBadge: "近似匹配",
    nameEnglishOnlyBadge: "仅英文名",
    nameNoGameNameBadge: "无游戏内名称",
    nameManualBadge: "名称手工补录",
    nameInferredBadge: "名称按 ID 推断",
    nameCommunityBadge: "社区资料",
    // 工具条开关。
    hiddenToggleTitle: "显示隐藏实体",
    hiddenToggleHelp: "召唤物 / 投射物等非首领实体",
    // 展开区小字：整组 / 该行不掉任何奖励。
    noRewardGroupNote: "该组不掉任何奖励（getSoul / 掉落表全为 0 或 -1）",
    noRewardRowNote: "该行不掉任何奖励",
    // 该行没有 depthStats 时的深夜小表占位文案。
    noDepthStatsText: "该行无深夜数值",
    // 变异个体块的标题与说明。
    mutationTitle: "变异个体",
    mutationPickerTitle: "按变异个体计算",
    mutationPickerNone: "无",
    mutationStackNote: "变异倍率在其它缩放之上再乘一层，按参数结构推断",
    mutationCountNote: "表里是「有几只被变异」的只数，不是百分比概率",
    // 人数缩放明细里攻击力列的「1 倍」写法。
    attackRateUnchanged: "不变",
    // 夜王各深度出现权重为 0 时的说明。
    depthWeightZero: "该深度不会出现",
    // 底部「人数缩放档位说明」的结论段。
    multiplayerAuditSummary:
      "多人不是简单乘倍：血量按档位从 ×1 到 ×3 不等（最终 Boss 档才是 ×2 / ×3，" +
      "野外常见档 7740 只有 ×1.1 / ×1.2，突袭档 98810 / 98815 完全不加血）；" +
      "7744 / 7753 / 7754 / 7758 四档的敌人攻击力还会上浮 10% / 20%；" +
      "防御、卢恩与掉落、异常触发阈值三项人数缩放一概不碰，" +
      "变的只是异常累积量与发动伤害倍率（都往下走，人越多越难上异常）。"
  };

  // 按出场场合分组（bossesSchemaVersion 4）的文案，一一对应 macOS 端 RelicCore 的
  // `BossRoleText`：字符串常量键名同名、逐字相同；函数与 macOS 的同名静态函数同输出
  //（macOS 的 RelicCoreChecks roleParityStrings 与 windows/tests/bosses_parity.test.mjs
  // 钉的是同一批字面量，后者还直接读 Swift 源码比对）。
  //
  // 上一版把八条自拟的场合文案塞进 TEXT，注释却写着「对应 macOS 的 BossRowText」，
  // macOS 根本没有同名常量——测试只是在自己核对自己；这一版整张换成 macOS 那张表。
  var ROLE_TEXT = {
    // 分组标题。前五个与数据集 roleNames 的中文名一致（夜王分组不叫「夜王战」），
    // 「其它场合」是合并分组的名字，不是某个场合。
    groupNightlord: "夜王",
    groupNight: "守夜首领",
    groupStronghold: "据点首领",
    groupField: "场景头目",
    groupEvergaol: "封印监牢",
    groupOther: "其它场合",
    groupSummon: "随从/召唤物",
    groupUnplaced: "未放置",
    // 展开区小字的前缀：tier / threat 只是多人缩放档位。
    threatTierLabel: "威胁档位",
    // 为什么「威胁档位」和分组对不上（卡片级小字、底部场合说明、多人缩放小标题下的提示共用）。
    threatTierNote: "威胁档位只是多人缩放档位（Field / Night Boss Threat），不代表出场场合；分组按地图放置判定的出场场合",
    // 行 / 组没有 roles（旧版数据集）时的徽标与占位。
    rolesMissing: "出场场合：数据未内置",
    // 某个场合没有出处明细时的占位。
    evidenceMissing: "出处：数据未内置",
    // 展开区每行「出场场合」小节的标题与说明。
    roleSectionTitle: "出场场合",
    roleSectionDetail: "按地图放置与抽选参数判定；分组看这里，不看威胁档位",
    // 出处多于一条时的展开 / 收起按钮。
    evidenceExpand: "展开全部出处",
    evidenceCollapse: "只看每个场合的第一条出处",
    // 底部说明里标在默认隐藏分组后面的注记。
    hiddenGroupMark: "（默认隐藏）",
    // 合并行各原始行场合不同时的小标题。
    rowRolesTitle: "逐行场合",
    // 分组切换的提示。
    groupPickerHelp: "按出场场合分组；一组首领可以同时出现在多个分组里",
    // 「显示隐藏实体」开关的补充说明（开关原有的 help 文案保持不变）。
    hiddenToggleRoleHelp: "也控制「未放置」「随从/召唤物」两个场合（分组与展开区的行）",
    // 底部多重归属说明最多列几个名字，其余写「等」。
    multiGroupNameLimit: 12,
    // roleNames 缺失时的内置中文名（与 v4 数据集 roleNames.*.zh 逐字相同，测试断言）。
    builtinRoleNames: {
      night: "守夜首领",
      prelude: "守夜前哨",
      field: "场景头目",
      stronghold: "据点首领",
      mine: "坑道精英",
      evergaol: "封印监牢",
      tower: "大空洞高塔首领",
      raid: "突袭事件",
      invader: "黑夜入侵者",
      event: "地图事件",
      nightlord: "夜王战",
      summon: "随从/召唤物",
      other: "其他地图",
      unplaced: "未放置"
    },
    // 底部「出场场合说明」折叠块的标题。
    overviewTitle: function (count) {
      return "出场场合说明（" + count + " 种）";
    },
    // 底部 notes.roleAudit.summary 的小标题。
    auditTitle: function (count) {
      return "与威胁档位的对照（数据集 notes.roleAudit，" + count + " 条）";
    },
    // 底部场合说明表里的计数：「40 组」「1 组 · 夜王 6」「夜王 18」。
    // 夜王战只有夜王有（守夜 / 野外首领 0 组），不写成「0 组 · 夜王 18」。
    roleCountText: function (groups, nightlords) {
      var parts = [];
      if (groups > 0 || nightlords === 0) parts.push(groups + " 组");
      if (nightlords > 0) parts.push("夜王 " + nightlords);
      return parts.join(" · ");
    },
    // 卡头计数：显示的行数，另有默认隐藏的行时补一句。
    rowCount: function (visible, hidden) {
      var base = rowCountText(visible);
      return hidden > 0 ? base + "（另 " + hidden + " 条已隐藏）" : base;
    },
    // 「另有 N 条出处」。
    evidenceMore: function (count) {
      return "另有 " + count + " 条出处";
    },
    // 展开区底部：默认藏掉的行数。
    hiddenRows: function (count) {
      return "另有 " + count + " 条「" + ROLE_TEXT.groupUnplaced + "」/「" + ROLE_TEXT.groupSummon +
        "」行已隐藏，打开「" + TEXT.hiddenToggleTitle + "」查看";
    },
    // 「威胁档位 · 守夜首领威胁档 / 野外首领威胁档」。取值 night / field 翻成档位组名
    //（与 tierGroupLabel / macOS 的 BossScalingGroup.title(for:) 同一套），未知取值原样写；
    // 去重保序；一个都没有时写「威胁档位 · 无」。
    threatTierCaption: function (threats) {
      var seen = [];
      var titles = [];
      (Array.isArray(threats) ? threats : []).forEach(function (threat) {
        var key = asText(threat);
        if (!key || seen.indexOf(key) !== -1) return;
        seen.push(key);
        titles.push(THREAT_TIER_GROUPS[key] ? tierGroupLabel(THREAT_TIER_GROUPS[key]) : key);
      });
      return ROLE_TEXT.threatTierLabel + " · " + (titles.length ? titles.join(" / ") : "无");
    },
    // 底部说明：同时出现在多个分组的组数，名字最多列 multiGroupNameLimit 个。
    multiGroupNote: function (count, names) {
      var list = (Array.isArray(names) ? names : []);
      var text = list.slice(0, ROLE_TEXT.multiGroupNameLimit).join("、");
      if (list.length > ROLE_TEXT.multiGroupNameLimit) text += " 等";
      return "有 " + count + " 组首领按出场场合同时属于多个分组（" + text + "），" +
        "它们在各个分组下都会出现：卡头列出全部场合，折叠态代表行跟着当前分组走，" +
        "展开后每行标了自己的场合与出处。";
    },
    // 底部说明：默认不显示的组（「显示隐藏实体」开关管的两类，macOS 的 BossRoleText.hiddenSummary）。
    //   · flagged：hidden = true 的非首领实体（召唤物 / 投射物等）的显示名；
    //   · roleOnly：没被判成非首领实体、但全部场合都是「未放置」「随从/召唤物」的组的显示名。
    // 两类共用一个开关，写在同一句里；两类都没有时返回空串（页面不写这一段）。名字全部列出，不截断。
    hiddenSummary: function (flagged, roleOnly) {
      var hidden = Array.isArray(flagged) ? flagged : [];
      var only = Array.isArray(roleOnly) ? roleOnly : [];
      var parts = [];
      if (hidden.length) {
        parts.push(hidden.length + " 组被判定为非首领实体（" + hidden.join("、") + "），" +
          "判据是整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出 / 社区标为杂兵");
      }
      if (only.length) {
        parts.push(only.length + " 组只出现在「" + ROLE_TEXT.groupUnplaced + "」「" + ROLE_TEXT.groupSummon + "」" +
          "两个场合（" + only.join("、") + "）");
      }
      if (!parts.length) return "";
      return "另有 " + parts.join("；另有 ") + "。它们默认不在列表里，" +
        "展开区里只出现在这两个场合的数值行也默认隐藏；" +
        "需要时打开工具条的「" + TEXT.hiddenToggleTitle + "」，" +
        "分组筛选里会多出「" + ROLE_TEXT.groupSummon + "」「" + ROLE_TEXT.groupUnplaced + "」两项。";
    }
  };

  // 只有 Windows 页面才有的场合文案：卡片级「出场场合」一览（每个场合几行、当前分组对应
  // 哪几行并描边高亮）是这边独有的界面元素，macOS 没有对应控件，所以不进双端对照表；
  // 集中放在这里，免得散在模板字符串里。
  var ROLE_PAGE_TEXT = {
    roleRowsChip: function (title, rows) {
      return title + " · " + rows + " 行";
    },
    currentGroupNote: function (groupTitle, rows) {
      return "当前分组「" + groupTitle + "」对应其中 " + rows + " 条数值行（下方描边高亮），" +
        "折叠态的代表行只从这几行里选。";
    }
  };

  var BADGE_LABEL_UNCERTAIN = TEXT.labelUncertainBadge;
  var BADGE_MUTATION = TEXT.mutationTitle;
  var BADGE_HIDDEN = TEXT.hiddenToggleHelp;

  // 「演出行」：登场动画 / 血条实体 / 教程这类玩家打不到、或者只是挂血条的行。
  // 判据照抄 macOS 端 BossFight.stagingLabelKeywords，扫的是页面上真正写着的那个标签
  //（entryLabel），只用于代表行评选，不影响展开区里的逐行展示。
  var STAGING_LABEL_KEYWORDS = ["登场演出", "血条实体", "教程"];

  // 深夜 / 深度 / 变异个体的中文一律用游戏内文本（CL_MenuText 131150 / 131011 /
  // 338806），数据集里放在 deepOfNightText。取不到时才用这里的兜底串。
  var DEEP_TEXT_FALLBACK = {
    deepOfNight: "深夜",
    depth: "深度",
    mutation: "变异个体"
  };

  // 深度只有 1–5 五档（ChaosMatchingRankControlParam 就 5 行）。
  var DEPTHS = [1, 2, 3, 4, 5];

  // 顶部分组切换。bossesSchemaVersion 4 起按出场场合 roles 分组，不再看 tier / tiers。
  // 键序 = macOS 端 BossCard.Group.allCases（夜王的键沿用 "nightlords"），标题取 ROLE_TEXT。
  // 守夜首领 / 据点首领 / 场景头目 / 封印监牢 / 随从/召唤物 / 未放置 与数据集
  // roleNames.<role>.zh 逐字相同（「场景头目」是游戏文本对 Field Boss 的叫法，TutorialBody 403200）。
  var GROUP_TITLES = {
    nightlords: ROLE_TEXT.groupNightlord,
    night: ROLE_TEXT.groupNight,
    stronghold: ROLE_TEXT.groupStronghold,
    field: ROLE_TEXT.groupField,
    evergaol: ROLE_TEXT.groupEvergaol,
    other: ROLE_TEXT.groupOther,
    summon: ROLE_TEXT.groupSummon,
    unplaced: ROLE_TEXT.groupUnplaced
  };

  var GROUP_ORDER = ["nightlords", "night", "stronghold", "field", "evergaol", "other", "summon", "unplaced"];

  // 默认隐藏的两个分组（macOS 的 Group.isHiddenByDefault）：「显示隐藏实体」打开才出现在分组切换里。
  var HIDDEN_GROUPS = ["summon", "unplaced"];

  var TABS = GROUP_ORDER.map(function (key) {
    return { key: key, label: GROUP_TITLES[key], hiddenByDefault: HIDDEN_GROUPS.indexOf(key) !== -1 };
  });

  // 场合取值的规范顺序 = 数据集 roleNames 的键序（roles 数组就按它排；macOS 的 BossRoleCatalog.order）。
  var ROLE_ORDER = [
    "night", "prelude", "field", "stronghold", "mine", "evergaol", "tower",
    "raid", "invader", "event", "nightlord", "summon", "other", "unplaced"
  ];

  // 合并进「其它场合」分组的已知场合（按规范顺序；macOS 的 BossRoleCatalog.otherGroupRoles）。
  // 高塔 / 突袭 / 入侵 / 事件是任务书点名的四个；守夜前哨、坑道精英、其他地图同样不属于任何
  // 独立分组，一并放进来。守夜前哨不并进守夜首领：它是首领本体登场前的那一波敌人。
  var OTHER_GROUP_ROLES = ["prelude", "mine", "tower", "raid", "invader", "event", "other"];

  // 场合 → 分组（macOS 的 BossCard.Group.forRole）：有独立分组的场合各归各组，其余一律「其它场合」，
  // 表里没有的新取值同样归「其它场合」。nightlord 只对夜王卡有意义：守夜 / 野外首领万一带了
  // nightlord 场合，归「其它场合」（见 roleGroups）。
  var ROLE_GROUP = {
    nightlord: "nightlords",
    night: "night",
    stronghold: "stronghold",
    field: "field",
    evergaol: "evergaol",
    summon: "summon",
    unplaced: "unplaced"
  };
  OTHER_GROUP_ROLES.forEach(function (role) { ROLE_GROUP[role] = "other"; });

  // 默认隐藏的两种场合（沿用「显示隐藏实体」开关；macOS 的 BossRoleCatalog.hiddenRoles）：
  //   · 全部场合都是这两种的组默认不显示，开关打开后出现在「随从/召唤物」「未放置」两个分组里；
  //   · 还有别的场合的组照常出现在别的分组，同时也在这两个分组里（开关打开时）；
  //   · 展开区只有这两种场合的行默认收起，写「另有 N 条…已隐藏」。
  var HIDDEN_ROLES = ["summon", "unplaced"];

  // 威胁档位取值 → 档位分组（组级 tier / tiers、行级 threat 只剩展开区小字用，不再参与分组）。
  var THREAT_TIER_GROUPS = { night: "Night Boss Threat", field: "Field Boss Threat" };

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
  //
  // **这张表只负责「取值 → 文案」的翻译，不是判定逻辑**（判定见 nameBadges）：
  // 上一版直接拿它当判定用，于是 nameSource = community 且 nameZh 为空的三组
  //（古龙桂奥尔 / Storm King / 百足幼虫）只挂了「社区资料」，把用户最关心的
  // 「本作游戏文本里根本没有它的简中名」这条结论从页面上抹掉了；macOS 端
  // BossCard.nameBadges 一直是两层判定，两端就此对不上。
  var NAME_SOURCE_BADGES = {
    "english-only": TEXT.nameEnglishOnlyBadge,
    "chrid-fallback": TEXT.nameNoGameNameBadge,
    "manual": TEXT.nameManualBadge,
    "community": TEXT.nameCommunityBadge,
    "community-npcname": TEXT.nameCommunityBadge
  };

  var BADGE_NAME_INFERRED = TEXT.nameInferredBadge;
  var BADGE_NAME_APPROX = TEXT.nameApproxBadge;
  var BADGE_NAME_FALLBACK = TEXT.nameFallbackBadge;

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
  // 场合徽标另由 entryRoleBadges() 给，排在这一组前面。
  function entryBadgeTexts(item, entry, stats) {
    var out = [];
    // 顺序与 macOS 端 BossFightRowView 的 Pill 顺序一致：主战 →
    // 标签为社区推测 → 深夜数值 → 深夜专属修正 → 变异个体。
    // 原来排第一的威胁档位「守夜 / 野外」（行级 threat）已降成行尾小字「威胁档位 守夜」：
    // 它只是缩放档位，与场合徽标「守夜首领 / 场景头目」挨着画会被读成出场位置。
    if (entry && entry.isMain) out.push("主战");
    if (entry && entry.labelUncertain) out.push(BADGE_LABEL_UNCERTAIN);
    // 只在这一行真的换了深度数值时挂「深夜数值」：没有 depthStats 的行在深度模式下
    // 显示的仍是常规值，挂徽标会骗人（展开区另写「该行无深夜数值」）。
    if (stats && stats.depth && stats.hasDepth) out.push(TEXT.deepRowBadge);
    // 另一枚：这一行还额外吃一组「深夜专属修正」（deepOfNight，394 行里只有 31 行）。
    // 两枚分工与 macOS 端 BossFightRowView 的两枚 Pill 完全一致。
    if (stats && stats.depth && stats.isDeep) out.push(TEXT.deepExclusiveBadge);
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
  // 常驻缩放 × 深夜修正 × 深度倍率），削韧恢复倍率 / 异常发动伤害基准 / 常驻 SpEffect
  // 清单没有深度专属字段，仍从 deepOfNight（深夜修正，非 null 时）取，没有就用常规值。
  //
  // 「请求了深度、但这一行没有 depthStats」时整组回落到常规值（hasDepth = false，
  // 页面写「该行无深夜数值」），与 macOS 端 BossFight.baseline(mode:) 的同一支一致。
  // 上一版这里会退到 deepOfNight 那一组，于是同一条假想行两端能给出不同的血量；
  // v3 数据里 394 行全部带 depthStats，走不到这一支，但口径不能两套。
  function numbersFor(entry, depth) {
    var level = depthValue(depth);
    var depthRow = depthStatsFor(entry, level);
    var deepNums = depthRow && entry && entry.deepOfNight ? entry.deepOfNight : null;
    var soft = deepNums || entry || {};
    var hard = depthRow || entry || {};
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
      // 缺字段时回落到 1（中性倍率），与 macOS 的
      // `bossDouble(.ailmentDamageRateBase, default: 1)` 一致。上一版回落到 0，
      // 会把「数据里没写」显示成「异常发动完全不造成伤害」。
      ailmentDamageRateBase: numberOr(soft.ailmentDamageRateBase, 1),
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

  // 主标题的四级回退（两端唯一正式版本，macOS 端 BossCard.displayName 同一套）：
  //   1. nameZh            —— 本作游戏文本里的简中名，不挂名字徽标；
  //   2. nameZhFallback    —— 《艾尔登法环》官方简中的参考译名，挂「参考译名 · 非本作游戏文本」；
  //   3. displayFallbackZh —— 生成器按 chrId 拼的占位名「未知敌人 cXXXX」，挂「无游戏内名称」；
  //   4. nameEn            —— 只剩英文名时显示英文名。
  // 副标题恒为英文名（主标题已经是英文名时不重复）。
  //
  // 两处必须讲清楚的改动：
  //   · 第 2 级上一版被压在副标题里，14 组让出 nameZh 的首领在列表上全是一串英文。
  //     「参考译名不能冒充游戏里的名字」这条顾虑改由徽标逐条承担。
  //   · 第 3 级是**这一轮修掉的 bug**：数据集第二版把占位名从 nameZh 挪进了新字段
  //     displayFallbackZh，Windows 端没跟着读，于是 c7931 / c7932 两组的卡头从
  //     「未知敌人 c7931」变成了「Unknown Enemy (c7931)」。
  // 四级全空才自己拼 chrId（数据里 nameEn 恒非空，这一支只为不渲染空标题）。
  function displayName(boss) {
    var zh = asText(boss && boss.nameZh);
    var en = asText(boss && boss.nameEn);
    var fallback = asText(boss && boss.nameZhFallback);
    var placeholder = asText(boss && boss.displayFallbackZh);
    var chrIds = boss && Array.isArray(boss.chrIds) ? boss.chrIds : [];
    var source = asText(boss && boss.nameSource);
    var info = {
      primary: "",
      secondary: "",
      // usesFallback：主标题用的是 nameZhFallback，必须挂「参考译名」徽标。
      usesFallback: false,
      // usesPlaceholder：主标题用的是 displayFallbackZh（占位名）。
      usesPlaceholder: false,
      // fallbackName / placeholderName：无论有没有用上，都保留原串给搜索索引与展开区说明。
      fallbackName: fallback,
      placeholderName: placeholder,
      // gameTextName：名字直接来自本作游戏文本（nameZh 非空且不是 chrid 兜底）。
      gameTextName: Boolean(zh) && source !== "chrid-fallback",
      approx: Boolean(boss && boss.nameApprox),
      inferred: Boolean(boss && boss.nameInferred),
      unknown: false
    };
    if (zh) info.primary = zh;
    else if (fallback) { info.primary = fallback; info.usesFallback = true; }
    else if (placeholder) { info.primary = placeholder; info.usesPlaceholder = true; }
    else if (en) info.primary = en;
    else {
      info.primary = chrIds.length ? "未知敌人 c" + chrIds[0] : "未知敌人";
      info.unknown = true;
    }
    info.secondary = en && en !== info.primary ? en : "";
    return info;
  }

  // 名字相关徽标（顺序即渲染顺序，与 macOS 端 BossCard.nameBadges 逐项同序同文案）。
  // 全部灰色：它们说明「这名字的可信度」，不是首领属性，不能和分组 / 变体徽标抢颜色。
  //
  // **四层，不是一条链**——每层回答的问题不同，挤进一条 if-else 就必然丢信息：
  //   1. 名字本身缺不缺：chrid-fallback → 无游戏内名称；nameZh 为空 →
  //      english-only 写「仅英文名」、其余（community 等）写「无游戏内名称」；
  //      再往后才是 manual / inferred。
  //   2. 身份是谁认出来的：nameSource 以 community 打头**且没有游戏文本依据**时
  //      追加「社区资料」。挖石山妖那种 community-npcname + nameEvidence 的组不挂，
  //      否则会和展开区同时显示的「游戏文本依据」自相矛盾。
  //   3. nameApprox → 近似匹配。
  //   4. 主标题取自参考译名 → 参考译名 · 非本作游戏文本。
  function nameBadges(info, boss) {
    var out = [];
    var source = asText(boss && boss.nameSource);
    var zh = asText(boss && boss.nameZh);
    if (source === "chrid-fallback") {
      out.push({ text: TEXT.nameNoGameNameBadge, kind: "gray" });
    } else if (!zh) {
      out.push({
        text: source === "english-only" ? TEXT.nameEnglishOnlyBadge : TEXT.nameNoGameNameBadge,
        kind: "gray"
      });
    } else if (source === "manual") {
      out.push({ text: TEXT.nameManualBadge, kind: "gray" });
    } else if (info.inferred) {
      out.push({ text: BADGE_NAME_INFERRED, kind: "gray" });
    }
    if (source.indexOf("community") === 0 && !(boss && boss.nameEvidence)) {
      out.push({ text: TEXT.nameCommunityBadge, kind: "gray" });
    }
    if (info.approx) out.push({ text: BADGE_NAME_APPROX, kind: "gray" });
    if (info.usesFallback) out.push({ text: BADGE_NAME_FALLBACK, kind: "gray" });
    return out;
  }

  // 一条数值行在页面上写着的标签。四级回退与 macOS 端 BossFight.displayLabel 一致：
  // labelZh → labelEn → paramdexName → 「行 <npcId>」。上一版最后一支写的是
  // 「变体 N」（还带序号，同一行在不同筛选下会换名字），而 isStagingRow 正是照这个
  // 标签判的，两端判据一旦不同，代表行就会分叉。
  function entryLabel(entry) {
    if (!entry) return "行 ?";
    if (entry.labelZh) return String(entry.labelZh);
    if (entry.labelEn) return String(entry.labelEn);
    if (entry.paramdexName) return String(entry.paramdexName);
    return "行 " + String(entry.npcId);
  }

  // 登场演出 / 血条实体 / 教程这类玩家打不到、或只是挂血条的行。
  // 只用于代表行评选，不影响展开区逐行展示（与 macOS 端 BossFight.isStagingRow 同判据）。
  function isStagingRow(entry) {
    var label = entryLabel(entry);
    return STAGING_LABEL_KEYWORDS.some(function (keyword) {
      return label.indexOf(keyword) !== -1;
    });
  }

  // 某个分组下参与「代表行」评选的候选行。四步过滤，**任一步会把候选池清空就跳过
  // 那一步**（跳过是规则的一部分，不是容错）。规则正文见 macOS 端
  // BossCard.rows(in:) 的文档注释，两端必须同序：
  //   1. 按当前分组过滤 roles（bossesSchemaVersion 4 起；此前按 threat）——只留场合落在
  //      该分组里的行（rolesInGroup，macOS 的 BossFight.belongs(to:)）。夜王分组即
  //      nightlord 行，「其它场合」即高塔 / 突袭 / 入侵 / 事件等行，「未放置」分组即未放置行。
  //      同一组首领常常横跨几个场合（铃珠猎人的守夜 / 场景头目 / 据点首领各是一行），在
  //      「场景头目」分组下就该看场景头目那一行，而不是血量更高的守夜行；
  //   2. 再收敛到 isMain（夜王的主战行**不唯一**，多阶段 / 多体有 2～5 条）；
  //   3. 排除登场演出 / 血条实体 / 教程这类演出行（isStagingRow）；
  //   4. 最后排除 noReward = true 的行（整池都 noReward 就不排除）。
  //
  // 第 4 步的位置是两端约定好的：**必须在 isMain 之后**。夜王的主战行几乎都是
  // noReward = true（奖励挂在远征结算上，不在 NpcParam 的 getSoul/掉落表里），
  // 把这一步提到 isMain 之前会把整组主战行踢掉——玛利斯的代表行会从 12,687 掉到
  // 3,045、格拉狄乌斯会从 npcId 75000020 变成 75000000。放在 isMain 之后，18 位
  // 夜王的代表行一条不变，只修掉真正抢位的模板/无奖励行（v3 口径下 16 组）。
  // v4 按场合过滤后，模板行多半是「未放置」、在别的分组里第 1 步就出局了；第 4 步仍起作用的
  // 例子：神皮使徒在「未放置」分组下，不掉奖励的 Paramdex 模板行 35600900（7,347）让给 35600000。
  //
  // 第 3 步：**演出行不一定 noReward**，第 4 步拦不住它们。少了这一步，巨鸦群在
  //「场景头目」下的代表行会是只挂血条的「血条实体」45601020（hp 2117，noReward = false）；
  // 恶兆妖鬼在「其它场合」下会是「教程」行 21300520（hp 9920）。
  function candidateEntries(entries, group) {
    var pool = Array.isArray(entries) ? entries.filter(Boolean) : [];
    if (group && Object.prototype.hasOwnProperty.call(GROUP_TITLES, group)) {
      var byRole = pool.filter(function (entry) {
        return rolesInGroup(entryRoles(entry), group).length > 0;
      });
      if (byRole.length) pool = byRole;
    }
    var mains = pool.filter(function (entry) { return entry.isMain; });
    if (mains.length) pool = mains;
    var playable = pool.filter(function (entry) { return !isStagingRow(entry); });
    if (playable.length) pool = playable;
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

  // 不区分分组的代表行（不按 roles 过滤；按分组取请用 representativeEntry 带上分组）。
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

  // ------------------------------------------------------------ 出场场合（roles）
  // bossesSchemaVersion 4：每个 fight / variant 有 roles（逐行场合的并集）、rowRoles
  //（逐原始行）、roleEvidence（逐场合证据）；组 / 夜王有 roles（各行并集）与 roleVariants。
  // 规则与 macOS 端 RelicCore 的 BossRoleCatalog / BossCard.Group / BossCard 同名成员一一对应。

  function roleIndex(role) {
    var index = ROLE_ORDER.indexOf(role);
    return index === -1 ? ROLE_ORDER.length : index;
  }

  // 规范化一份 roles（macOS 的 BossRoleCatalog.normalized）：只留非空字符串、去重，
  // 已知场合按 ROLE_ORDER 排，表外的新取值按键名排在已知场合之后。
  function normalizeRoles(list) {
    var seen = [];
    (Array.isArray(list) ? list : []).forEach(function (role) {
      if (typeof role !== "string" || !role || seen.indexOf(role) !== -1) return;
      seen.push(role);
    });
    return seen.sort(function (a, b) {
      var left = roleIndex(a);
      var right = roleIndex(b);
      if (left !== right) return left - right;
      return a < b ? -1 : (a > b ? 1 : 0);
    });
  }

  function entryRoles(entry) {
    return normalizeRoles(entry && entry.roles);
  }

  // 组 / 夜王的场合：优先读组级 roles（数据里恒为各行 roles 的并集），缺了才自己并。
  function unionRoles(owner, entries) {
    var declared = normalizeRoles(owner && owner.roles);
    if (declared.length) return declared;
    var all = [];
    (Array.isArray(entries) ? entries : []).forEach(function (entry) {
      entryRoles(entry).forEach(function (role) { all.push(role); });
    });
    return normalizeRoles(all);
  }

  function isHiddenRole(role) {
    return HIDDEN_ROLES.indexOf(role) !== -1;
  }

  function isHiddenGroup(group) {
    return HIDDEN_GROUPS.indexOf(group) !== -1;
  }

  // 场合 → 分组（macOS 的 BossCard.Group.forRole）。
  function roleGroup(role) {
    return Object.prototype.hasOwnProperty.call(ROLE_GROUP, role) ? ROLE_GROUP[role] : "other";
  }

  // 一组场合里落在某个分组的那几个（macOS 的 Group.contains(role:)）。
  function rolesInGroup(roles, group) {
    return normalizeRoles(roles).filter(function (role) {
      return roleGroup(role) === group;
    });
  }

  // 只出现在默认隐藏场合（「未放置」「随从/召唤物」）的场合表。没有场合数据的不算——
  // 缺数据不能被当成「未放置」藏起来（macOS 的 BossFight / BossCard.isHiddenByDefault）。
  function onlyHiddenRoles(roles) {
    var list = normalizeRoles(roles);
    return list.length > 0 && list.every(isHiddenRole);
  }

  // 卡片属于哪些分组（按 GROUP_ORDER 排）。规则正文是 macOS 端 BossCard.Group 的文档注释
  //（BossDataIndex.groups(forRoles:)），这里照抄：
  //   · 夜王卡固定只进「夜王」；它们的突袭 / 地图事件 / 未放置场合只作卡头徽标。
  //     roleSummary 本来就只数 nightBosses，这样其余分组的计数才能与 roleSummary 逐项相等；
  //   · 守夜 / 野外首领：每个场合落在哪个分组就出现在哪个分组，**多重归属就在各分组都出现**；
  //     万一带了 nightlord 场合（当前数据没有）归「其它场合」，免得夜王分组混进非夜王；
  //   · 「随从/召唤物」「未放置」各是一个分组，默认隐藏；全部场合都是这两种的组
  //     roleHidden = true，默认不显示（与 boss.hidden 共用「显示隐藏实体」开关）；
  //   · roles 整个缺失（旧数据）时 roleMissing = true，归「其它场合」、不隐藏，
  //     卡上写「出场场合：数据未内置」——不退回 tier 猜分组，那正是这一版要修的错。
  function roleGroups(roles, isNightlord) {
    var list = normalizeRoles(roles);
    var roleHidden = onlyHiddenRoles(list);
    if (isNightlord) return { groups: ["nightlords"], roleHidden: roleHidden, roleMissing: !list.length };
    if (!list.length) return { groups: ["other"], roleHidden: false, roleMissing: true };
    var found = [];
    list.forEach(function (role) {
      var group = roleGroup(role);
      if (group === "nightlords") group = "other";
      if (found.indexOf(group) === -1) found.push(group);
    });
    return {
      groups: GROUP_ORDER.filter(function (key) { return found.indexOf(key) !== -1; }),
      roleHidden: roleHidden,
      roleMissing: false
    };
  }

  // 首领组的分组（不含夜王）。名字沿用上一版，口径已从 tiers 换成 roles。
  function bossGroups(boss) {
    return roleGroups(unionRoles(boss, boss && boss.variants), false).groups;
  }

  // 卡片默认不显示：hidden（召唤物 / 投射物等非首领实体），或全部场合都是默认隐藏的两种。
  function isItemHiddenByDefault(item) {
    return Boolean(item && (item.hidden || item.roleHidden));
  }

  // 卡片所在的默认可见分组（「随从/召唤物」「未放置」不算）。
  function visibleGroups(item) {
    return (item && Array.isArray(item.groups) ? item.groups : []).filter(function (group) {
      return !isHiddenGroup(group);
    });
  }

  // 同时属于多个默认可见分组（macOS 的 BossCard.hasMultipleGroups）。
  function hasMultipleGroups(item) {
    return visibleGroups(item).length > 1;
  }

  // 分组切换里可选的分组：默认隐藏的两个只在打开开关时出现（macOS 的 Group.visibleCases）。
  function visibleTabs(showHidden) {
    return TABS.filter(function (tab) { return showHidden || !tab.hiddenByDefault; });
  }

  // 展开区要逐行列出的行（macOS 的 BossCard.displayRows(includeHidden:)）：默认藏掉只出现在
  //「未放置」「随从/召唤物」的行；整卡都是这种行（只有打开开关才看得到的卡）时全部列出，
  // 免得展开后是空的。演出行 / 无奖励行不在此列——它们只在评选代表行时让位。
  function displayEntries(entries, showHidden) {
    var list = Array.isArray(entries) ? entries.filter(Boolean) : [];
    if (showHidden) return list;
    var shown = list.filter(function (entry) { return !onlyHiddenRoles(entryRoles(entry)); });
    return shown.length ? shown : list;
  }

  function hiddenEntryCount(entries, showHidden) {
    var list = Array.isArray(entries) ? entries.filter(Boolean) : [];
    return list.length - displayEntries(list, showHidden).length;
  }

  // 场合的中文名（macOS 的 BossDataset.roleTitle）：数据集 roleNames 的中文名 → 内置表 →
  // roleNames 的英文名 → 键名原样。未知的新场合也不能渲染成空白徽标。
  function roleTitle(data, role) {
    var table = data && data.roleNames && typeof data.roleNames === "object" ? data.roleNames : null;
    var item = table ? table[role] : null;
    return asText(item && item.zh) || ROLE_TEXT.builtinRoleNames[role] || asText(item && item.en) || asText(role);
  }

  function roleDescription(data, role) {
    var table = data && data.roleNames && typeof data.roleNames === "object" ? data.roleNames : null;
    var item = table ? table[role] : null;
    return asText(item && item.description);
  }

  // 一枚场合徽标的模型：颜色跟它所属的分组走（守夜蓝 / 场景头目绿 …），默认隐藏的两种画灰。
  function roleBadge(data, role) {
    return { role: role, text: roleTitle(data, role), group: roleGroup(role), hidden: isHiddenRole(role), current: true };
  }

  // 卡头的场合徽标：列出这张卡的**全部**场合（含「未放置」「随从/召唤物」，也含夜王卡的
  //「夜王战」），与 macOS 的 BossRoleBadges 同一组；搜索索引收的也正是这些名字。
  // current：场合是否落在当前分组（macOS 着色 / 其余中性，一眼看出这张卡为什么在这个分组里）；
  // 不传分组时全部算当前。
  function cardRoleBadges(item, data, group) {
    var roles = item && Array.isArray(item.roles) ? item.roles : [];
    return roles.map(function (role) {
      var badge = roleBadge(data, role);
      badge.current = group ? roleGroup(role) === group : true;
      return badge;
    });
  }

  // 展开区逐行的场合徽标：该行 roles 全部列出。
  function entryRoleBadges(entry, data) {
    return entryRoles(entry).map(function (role) { return roleBadge(data, role); });
  }

  // 搜索索引里的场合名（macOS 的 BossDataIndex.roleSearchTerms）：每个场合的中文名
  //（roleTitle）+ roleNames 的英文名；不收判定口径（description），也不收取值 key。
  // 收的是全部场合——卡头徽标也是全部场合，搜得到的名字在卡头上都看得见。
  function roleSearchTerms(data, roles) {
    var table = data && data.roleNames && typeof data.roleNames === "object" ? data.roleNames : {};
    var out = [];
    normalizeRoles(roles).forEach(function (role) {
      out.push(roleTitle(data, role));
      var en = asText(table[role] && table[role].en);
      if (en) out.push(en);
    });
    return out;
  }

  // 每个场合涉及这张卡的几条数值行（按变体 / 战斗行的 roles 数，含默认收起的行）。
  function roleEntryCounts(entries, roles) {
    var list = Array.isArray(entries) ? entries.filter(Boolean) : [];
    return normalizeRoles(roles).map(function (role) {
      return {
        role: role,
        rows: list.filter(function (entry) { return entryRoles(entry).indexOf(role) !== -1; }).length
      };
    });
  }

  // 某个场合的出处（坏元素跳过，缺了给空数组；macOS 的 BossFight.evidence(for:)）。
  function roleEvidenceList(entry, role) {
    var table = entry && entry.roleEvidence && typeof entry.roleEvidence === "object" ? entry.roleEvidence : null;
    var list = table && Array.isArray(table[role]) ? table[role] : [];
    return list.filter(function (item) {
      return item !== null && typeof item === "object" && !Array.isArray(item);
    });
  }

  // 出处摘要「表名 行 · 地图」，与 macOS 的 BossRoleEvidence.summary 逐字同一口径：
  //   · row 为空或「—」（未放置那种占位）时只写表名；
  //   · msb 为空、或与 row 相同（「其他地图」那种 row 就是地图名）时不重复写地图；
  //   · 表名与行都没有时写「出处：数据未内置」。
  // note 不进摘要（最长 500 多字），页面放在摘要下面的小字里。
  function evidenceSummaryText(evidence) {
    var table = asText(evidence && evidence.table);
    var row = asText(evidence && evidence.row);
    var msb = asText(evidence && evidence.msb);
    var head = table;
    if (row && row !== "—") head = head ? head + " " + row : row;
    var parts = head ? [head] : [];
    if (msb && msb !== row) parts.push(msb);
    return parts.length ? parts.join(" · ") : ROLE_TEXT.evidenceMissing;
  }

  // 出处的地图名（placementMaps 里的 Paramdex 名或开放地块的地形名）与 MSB part：
  // 摘要本身与 macOS 逐字一致，这两项只放进悬停提示，不改摘要文字。
  function evidenceHint(data, evidence) {
    var msb = asText(evidence && evidence.msb);
    var maps = data && data.placementMaps && typeof data.placementMaps === "object" ? data.placementMaps : null;
    var info = msb && maps ? maps[msb] : null;
    var name = "";
    if (info) name = asText(info.paramdexName) || (info.tileVariant ? asText(info.tileVariant.zh) : "");
    return [name ? msb + "：" + name : "", asText(evidence && evidence.part)].filter(Boolean).join(" · ");
  }

  // 展开区每行「出场场合」小节的模型（macOS 的 BossRoleEvidenceSection）：每个场合给第一条
  // 出处（showAll 时给全部），另报「另有 N 条出处」。出处来自被合并掉的原始行时标「行 N」。
  function roleEvidenceLines(entry, data, showAll) {
    var selfId = entry ? entry.npcId : null;
    return entryRoles(entry).map(function (role) {
      var list = roleEvidenceList(entry, role);
      var shown = showAll ? list : list.slice(0, 1);
      var line = roleBadge(data, role);
      line.total = list.length;
      line.missing = !list.length;
      line.more = list.length - shown.length;
      line.items = shown.map(function (item) {
        var npcId = item.npcId === null || item.npcId === undefined || item.npcId === "" ? null : item.npcId;
        return {
          npcId: npcId !== null && Number(npcId) !== Number(selfId) ? npcId : null,
          summary: evidenceSummaryText(item),
          note: asText(item.note),
          hint: evidenceHint(data, item)
        };
      });
      return line;
    });
  }

  // 有没有哪个场合不止一条出处（此时给「展开全部出处」按钮）。
  function hasMoreEvidence(entry) {
    return entryRoles(entry).some(function (role) { return roleEvidenceList(entry, role).length > 1; });
  }

  // 合并行的原始行按场合归拢（macOS 的 BossFight.rowRoleGroups）：同一组场合的 npcId 放在一起，
  // 顺序按 npcIds 里第一次出现的顺序，rowRoles 里多出来的键按数值升序接在后面；
  // 转不成 npcId 的键丢掉。
  function rowRoleGroups(entry) {
    var raw = entry && entry.rowRoles && typeof entry.rowRoles === "object" ? entry.rowRoles : {};
    var table = {};
    var keys = [];
    Object.keys(raw).forEach(function (key) {
      if (!/^-?\d+$/.test(key)) return;
      var id = Number(key);
      table[String(id)] = normalizeRoles(raw[key]);
      keys.push(id);
    });
    var npcIds = entry && Array.isArray(entry.npcIds) && entry.npcIds.length
      ? entry.npcIds.map(Number)
      : (entry && entry.npcId !== undefined ? [Number(entry.npcId)] : []);
    var ids = npcIds.filter(function (id) { return Object.prototype.hasOwnProperty.call(table, String(id)); })
      .concat(keys.filter(function (id) { return npcIds.indexOf(id) === -1; }).sort(function (a, b) { return a - b; }));
    var order = [];
    var members = {};
    ids.forEach(function (id) {
      var roles = table[String(id)];
      var key = roles.join("+");
      if (!members[key]) { members[key] = { roles: roles, npcIds: [] }; order.push(key); }
      if (members[key].npcIds.indexOf(id) === -1) members[key].npcIds.push(id);
    });
    return order.map(function (key) { return members[key]; });
  }

  // 合并行的「逐行场合」（macOS 的 BossDataset.rowRolesSummary）：
  // 「逐行场合：夜王战 75000020 / 75002020；未放置 75001020」，同一组场合用「 + 」连接。
  // 各原始行场合都一样（或没有 rowRoles）时返回空串——页面不写这一行。
  function rowRolesSummary(entry, data) {
    var groups = rowRoleGroups(entry);
    if (groups.length < 2) return "";
    return ROLE_TEXT.rowRolesTitle + "：" + groups.map(function (group) {
      return group.roles.map(function (role) { return roleTitle(data, role); }).join(" + ") +
        " " + group.npcIds.join(" / ");
    }).join("；");
  }

  // 组级威胁档位（macOS 的 BossCard.tiers）：tiers 非空就用它，否则用 tier；tier 缺字段时
  // 按 "field" 处理（macOS 解码 `bossString(.tier, default: "field")`），空串算没有。
  function cardTiers(boss) {
    if (boss && Array.isArray(boss.tiers) && boss.tiers.length) {
      return boss.tiers.map(asText).filter(Boolean);
    }
    var tier = boss && typeof boss.tier === "string" ? boss.tier : "field";
    return tier ? [tier] : [];
  }

  // 这一行的多人缩放档位名与它是不是守夜首领对不上：不当守夜首领的行挂着「守夜首领威胁档」
  //（铃珠猎人野外版 31000010 就是 7753 · Night Boss Threat，35 行），或守夜首领行挂着
  //「野外首领威胁档」（熔炉骑士那类，10 行）。展开区「多人缩放（档位 #7753 · 守夜首领威胁档）」
  // 在这种行上最容易被读成出场位置，只在这 45 行补一句 threatTierNote；档位名本身不改
  //（与 macOS 的 BossScalingGroup.title 同一套，GROUP_LABELS 注释里写明了它只是档位名）。
  // 默认收起的未放置 / 随从行不算：它们没有出场位置可供误读。
  function threatRoleMismatch(entry, tiers) {
    var roles = entryRoles(entry);
    if (!roles.length || onlyHiddenRoles(roles)) return false;
    var id = entry && entry.scalingId;
    if (id === null || id === undefined) return false;
    var meta = tiers ? tiers[String(id)] : null;
    var group = meta ? meta.group : null;
    var isNightRow = roles.indexOf("night") !== -1;
    if (group === THREAT_TIER_GROUPS.night) return !isNightRow;
    if (group === THREAT_TIER_GROUPS.field) return isNightRow;
    return false;
  }

  // 各分组的卡片数（顶部切换上的数字，macOS 的 cards(in:includeHidden:).count）。
  // 开关关着时两个默认隐藏的分组为 0，其余分组滤掉默认隐藏的卡。
  function groupCounts(items, showHidden) {
    var out = {};
    GROUP_ORDER.forEach(function (key) { out[key] = 0; });
    (Array.isArray(items) ? items : []).forEach(function (item) {
      if (!item || (!showHidden && isItemHiddenByDefault(item))) return;
      (Array.isArray(item.groups) ? item.groups : [item.group]).forEach(function (group) {
        if (!showHidden && isHiddenGroup(group)) return;
        out[group] = (out[group] || 0) + 1;
      });
    });
    return out;
  }

  // 同时属于多个默认可见分组的卡片（macOS 的 BossDataIndex.multiGroupCards）。
  function multiGroupItems(items) {
    return (Array.isArray(items) ? items : []).filter(hasMultipleGroups);
  }

  // 底部「默认隐藏了哪些组」的说明（macOS 的 BossDataIndex.hiddenSummary）：hidden 的非首领实体，
  // 与全部场合都是「未放置」「随从/召唤物」、但没被判成非首领实体的组，名字按数据集顺序。
  // 两类都没有时为空串。
  function hiddenSummaryText(items) {
    var list = (Array.isArray(items) ? items : []).filter(Boolean);
    var names = function (item) { return item.name; };
    return ROLE_TEXT.hiddenSummary(
      list.filter(function (item) { return item.hidden; }).map(names),
      list.filter(function (item) { return !item.hidden && isItemHiddenByDefault(item); }).map(names)
    );
  }

  // 底部「出场场合说明」要列的全部场合（macOS 的 BossDataset.orderedRoles）：内置顺序在前，
  // 数据集里多出来的未知场合（roleNames / roleSummary 的键）按键名排在后面。
  function orderedRoles(data) {
    var extra = [];
    [data && data.roleNames, data && data.roleSummary].forEach(function (table) {
      if (!table || typeof table !== "object") return;
      Object.keys(table).forEach(function (key) {
        if (ROLE_ORDER.indexOf(key) === -1 && extra.indexOf(key) === -1) extra.push(key);
      });
    });
    return ROLE_ORDER.concat(extra.sort());
  }

  // 「出场场合说明」表的一行（macOS 的 BossRoleOverview.roleRow）：场合 → 分组（默认隐藏的
  // 分组后面标「（默认隐藏）」），计数按卡片重数（守夜 / 野外首领里带它的组数 + 带它的夜王数）。
  function roleOverviewRows(data, items) {
    var list = Array.isArray(items) ? items : [];
    return orderedRoles(data).map(function (role) {
      var group = roleGroup(role);
      var bosses = list.filter(function (item) { return item.kind !== "nightlord" && item.roles.indexOf(role) !== -1; }).length;
      var lords = list.filter(function (item) { return item.kind === "nightlord" && item.roles.indexOf(role) !== -1; }).length;
      var names = data && data.roleNames && typeof data.roleNames === "object" ? data.roleNames : {};
      return {
        role: role,
        title: roleTitle(data, role),
        en: asText(names[role] && names[role].en),
        group: group,
        groupText: GROUP_TITLES[group] + (isHiddenGroup(group) ? ROLE_TEXT.hiddenGroupMark : ""),
        countText: ROLE_TEXT.roleCountText(bosses, lords),
        description: roleDescription(data, role)
      };
    });
  }

  // 列表计数里的「已隐藏 / 含隐藏」一段。v4 起只有 hidden 的非首领实体、或全部场合都是
  //「未放置」「随从/召唤物」的组默认隐藏，它们只落在那两个默认隐藏的分组里，所以这段
  // 实际只在打开开关、切到这两个分组时出现（写「含隐藏 N 组」）。
  function hiddenCountText(count, shown) {
    if (!count) return "";
    return shown
      ? "含隐藏 " + count + " 组"
      : "已隐藏 " + count + " 组（未放置 / 随从 / 非首领实体）";
  }

  // 一张卡里有多少行带某类深夜数值。只看代表行会把「首条没有、其余行有」的卡片判错，
  // 所以一律扫描整卡。
  function coverage(entries, has) {
    var list = Array.isArray(entries) ? entries : [];
    if (!list.length) return "none";
    var hit = 0;
    list.forEach(function (entry) { if (entry && has(entry)) hit += 1; });
    if (!hit) return "none";
    return hit === list.length ? "all" : "some";
  }

  // **两套口径，别混用**（函数名与 macOS 端 BossCard 的两个同名属性一一对应）：
  //   · deepCoverage       数的是 depthStats ——「深度模式下这张卡的数值变不变」，
  //     徽标写「深夜数值」；v3 数据里 394 行全有 depthStats，所以实际恒为 all。
  //   · deepOfNightCoverage 数的是 deepOfNight ——「有没有额外那组深夜专属常驻修正」，
  //     徽标写「深夜专属修正」；只有 31 行有。
  //
  // 上一版两个名字**正好反着**（Windows 的 deepCoverage 数 deepOfNight、
  // depthCoverage 数 depthStats），两端对读时必然踩坑，这一轮按 macOS 的语义统一。
  function deepCoverage(item) {
    return coverage(item && item.entries, function (entry) { return entry.depthStats; });
  }

  function deepOfNightCoverage(item) {
    return coverage(item && item.entries, function (entry) { return entry.deepOfNight; });
  }

  // 卡头徽标文案（macOS 端 BossDeepCoverage.badgeText / exclusiveBadgeText）。
  function deepCoverageBadge(kind) {
    if (kind === "all") return TEXT.deepRowBadge;
    if (kind === "some") return TEXT.deepRowBadgePartial;
    return "";
  }

  function deepOfNightCoverageBadge(kind) {
    if (kind === "all") return TEXT.deepExclusiveBadge;
    if (kind === "some") return TEXT.deepExclusiveBadgePartial;
    return "";
  }

  // 把数据集拍平成页面用的卡片列表；fold 用 ctx.helpers.foldForSearch（测试里传 Core.foldForSearch）。
  function buildItems(data, fold) {
    var folder = typeof fold === "function" ? fold : defaultFold;
    var items = [];
    if (!data || typeof data !== "object") return items;

    (Array.isArray(data.nightlords) ? data.nightlords : []).forEach(function (lord) {
      var entries = Array.isArray(lord.fights) ? lord.fights : [];
      var variant = VARIANT_PILL[lord.variantKey] || null;
      var roles = unionRoles(lord, entries);
      var placement = roleGroups(roles, true);
      items.push({
        uid: "nl:" + String(lord.menuId),
        kind: "nightlord",
        group: placement.groups[0],
        groups: placement.groups,
        roles: roles,
        roleHidden: placement.roleHidden,
        roleMissing: placement.roleMissing,
        // 夜王没有 tier / tiers（macOS 的 BossCard.tiers 同样为空），展开区不写威胁档位小字。
        tiers: [],
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
        main: representativeEntry(entries, "nightlords"),
        idText: "菜单行 " + String(lord.menuId),
        // 搜索串的组成两端必须一致：中英文名 + 远征名 + 变体名 + 官方弱点 + 场合名
        //（全部场合的 roleNames 中英文，卡头徽标上都看得见）+ 每行标签。
        // nameSource / threat / variantKey 这类内部枚举值与场合的取值 key 都不进搜索串。
        search: folder(joinSearch([
          lord.nameZh, lord.nameEn, lord.expeditionZh, lord.expeditionEn,
          lord.variantNameZh, lord.variantNameEn
        ].concat((Array.isArray(lord.weakness) ? lord.weakness : []).map(function (weak) {
          return joinSearch([weak.zh, weak.en]);
        })).concat(roleSearchTerms(data, roles))
          .concat(entries.map(function (fight) { return joinSearch([fight.labelZh, fight.labelEn]); })))),
        numbers: numberKeys(entryNumbers(entries))
      });
    });

    (Array.isArray(data.nightBosses) ? data.nightBosses : []).forEach(function (boss) {
      var entries = Array.isArray(boss.variants) ? boss.variants : [];
      var info = displayName(boss);
      var roles = unionRoles(boss, entries);
      var placement = roleGroups(roles, false);
      var groups = placement.groups;
      items.push({
        uid: "nb:" + String(boss.id),
        kind: "boss",
        group: groups[0],
        groups: groups,
        roles: roles,
        // roleHidden：全部场合都是「未放置」「随从/召唤物」，默认隐藏（与 hidden 同一个开关）。
        roleHidden: placement.roleHidden,
        roleMissing: placement.roleMissing,
        // tier / tiers 不再参与分组，只在展开区写成「威胁档位」小字。
        tiers: cardTiers(boss),
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
        namePlaceholder: info.placeholderName,
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
        // displayFallbackZh（「未知敌人 cXXXX」）同理——它现在就是卡头上写着的名字，
        // 页面上看得见的名字必须搜得到。场合名（roleNames 中英文）同样收进来：
        // 卡头挂着的场合徽标（全部场合）必须搜得到。两端同一组搜索键。
        search: folder(joinSearch([
          boss.nameZh, boss.nameEn, boss.nameZhFallback, boss.displayFallbackZh
        ].concat(roleSearchTerms(data, roles))
          .concat(entries.map(function (variant) { return joinSearch([variant.labelZh, variant.labelEn]); })))),
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

  // showHidden 缺省为 false（macOS 的 BossDataIndex.cards(in:query:includeHidden:)）：
  //   · 「随从/召唤物」「未放置」两个分组整组不显示；
  //   · 其余分组滤掉默认隐藏的卡——hidden = true 的组（召唤物 / 投射物等非首领实体）与
  //     roleHidden = true 的组（全部场合都是「未放置」「随从/召唤物」）。
  function filterItems(items, group, query, fold, showHidden) {
    var folder = typeof fold === "function" ? fold : defaultFold;
    var needle = folder(String(query == null ? "" : query).trim());
    if (group && isHiddenGroup(group) && !showHidden) return [];
    return items.filter(function (item) {
      if (!showHidden && isItemHiddenByDefault(item)) return false;
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
    return number === 1 ? TEXT.attackRateUnchanged : fmtMul(number, 3);
  }

  // 血量旁的多人攻击徽标：「多人攻击 ×1.1」（macOS 端 BossRowText.multiplayerAttackBadge）。
  function multiplayerAttackBadge(rate) {
    return "多人攻击 " + fmtMul(rate, 3);
  }

  // 夜王某深度的出现权重文案（macOS 端 BossRowText.depthWeightText）。
  // 上一版这里只写个数字，权重 0 会显示成「0」——用户读不出「这一档根本刷不出来」。
  function depthWeightText(weight) {
    var value = Number(weight);
    if (!isFinite(value) || value <= 0) return TEXT.depthWeightZero;
    // 不加千位分隔符：权重只有 500–1600 这个量级，macOS 端写的也是「权重 1600」。
    return "权重 " + String(Math.round(value));
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
    // 展开了「全部出处」的数值行：key 同上，收起卡片时一并清掉（macOS 每行各自记、收起归零）。
    evidenceOpen: {},
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

  // 八个分组按钮，每个带一个卡片数（renderList 里按隐藏开关刷新）；「随从/召唤物」「未放置」
  // 两个默认隐藏，打开「显示隐藏实体」才出现（renderControls 里切 hidden）。
  function groupControl() {
    return TABS.map(function (tab) {
      var active = tab.key === state.group;
      return "<button type='button' class='segment-button bosses-group-button" + (active ? " is-active" : "") + "'" +
        " data-bosses-group='" + tab.key + "' data-testid='bosses-group-" + tab.key + "'" +
        (tab.hiddenByDefault && !state.showHidden ? " hidden" : "") +
        " role='radio' aria-checked='" + active + "'>" + esc(tab.label) +
        "<span class='bosses-group-count' data-bosses-group-count='" + tab.key + "'></span></button>";
    }).join("");
  }

  // 场合徽标：颜色跟所属分组走（bosses.css 的 .bosses-role--<分组>），默认隐藏的两种画虚线灰；
  // 卡头上不属于当前分组的场合压成中性色（badge.current === false）；
  // 悬停显示 roleNames 里的判定口径。text 可以覆盖（展开区「守夜首领 · 2 行」这种）。
  function rolePill(badge, text) {
    var desc = roleDescription(state.data, badge.role);
    return "<span class='pill bosses-role bosses-role--" + esc(badge.group) +
      (badge.hidden ? " is-hidden-role" : "") + (badge.current === false ? " is-muted" : "") + "'" +
      (desc ? " title='" + esc(desc) + "'" : "") + ">" + esc(text || badge.text) + "</span>";
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
      "<div><h1>首领数据</h1><p>《黑夜君临》首领的出场场合、血量、承伤倍率、韧性、深夜深度与人数缩放</p></div>" +
      "</header>" +
      "<section class='card bosses-toolbar' data-testid='bosses-toolbar'>" +
      "<div class='bosses-toolbar-row'>" +
      "<div class='bosses-control'><span class='bosses-control-label'>人数</span>" +
      "<div class='segmented-control bosses-party' role='radiogroup' aria-label='队伍人数' data-testid='bosses-party'>" +
      partyControl() + "</div></div>" +
      "<div class='bosses-control bosses-control--grow'><span class='bosses-control-label'>搜索</span>" +
      "<label class='search-field'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='搜索首领名、参考译名、远征名、变体标签、出场场合，或输入 npcId / chrId 前缀' autocomplete='off' data-testid='bosses-search'></label></div>" +
      "<div class='bosses-control'><span class='bosses-control-label'>模式</span>" +
      depthControl() + "</div>" +
      "<div class='bosses-control'><span class='bosses-control-label'>隐藏实体</span>" +
      "<label class='switch-control bosses-hidden-switch' title='" + esc(TEXT.hiddenToggleHelp) +
      "：整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出名字 / 被社区标为杂兵。默认不显示；" +
      esc(ROLE_TEXT.hiddenToggleRoleHelp) + "。'>" +
      "<input type='checkbox' data-testid='bosses-hidden'>" +
      "<span class='switch-track'></span><span>" + esc(TEXT.hiddenToggleTitle) + "</span></label></div>" +
      "</div>" +
      "<div class='bosses-toolbar-row bosses-toolbar-row--tabs'>" +
      "<div class='segmented-control bosses-group' role='radiogroup' aria-label='首领分组' data-testid='bosses-group'" +
      " title='" + esc(ROLE_TEXT.groupPickerHelp) + "'>" +
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
      "<div><h1>首领数据</h1><p>《黑夜君临》首领的出场场合、血量、承伤倍率、韧性、深夜深度与人数缩放</p></div>" +
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
    if (item.kind === "nightlord" && item.variantPill) {
      badges.push(pill(item.variantPill.text, item.variantPill.kind));
    }
    // 卡头列出这一组的全部出场场合（与 macOS 的 BossRoleBadges 同一组：含「未放置」
    //「随从/召唤物」，夜王卡含「夜王战」），属于当前分组的着色、其余压成中性色——
    // 一眼看出这张卡为什么出现在这个分组里；「其它场合」分组靠这些徽标说清具体是
    // 高塔 / 突袭 / 入侵 / 事件里的哪一种。夜王卡原来那枚「夜王」徽标由「夜王战」接替。
    if (item.roleMissing) {
      badges.push(pill(ROLE_TEXT.rolesMissing, "gray"));
    } else {
      cardRoleBadges(item, state.data, state.group).forEach(function (badge) {
        badges.push(rolePill(badge));
      });
    }
    (item.nameBadges || []).forEach(function (badge) {
      badges.push(pill(badge.text, badge.kind));
    });
    if (item.hidden) badges.push(pill(BADGE_HIDDEN, "gray"));
    if (state.depth) {
      // 深度模式下只给真有 depthStats 的卡片挂徽标；一条都没有的卡另在展开区写明。
      // 徽标文案不带深度数字：深度已经写在顶部「模式」下拉与列表计数里，
      // 这里要回答的是「这张卡在深度模式下数值变不变」（与 macOS 的同一枚徽标同文案）。
      var depthBadge = deepCoverageBadge(deepCoverage(item));
      if (depthBadge) badges.push(pill(depthBadge, "amber"));
      // 另有一层「深夜专属修正」（2287 条件效果，22 张卡有）：它把永夜之王 / DLC 的
      // 常驻加成在深夜里压回去，数值已经含在 depthStats 里，但值得标出来。
      // 只看代表行会把格诺斯塔·永夜之王这类首条无深夜修正、其余行有的卡片判错，所以扫全卡。
      var exclusiveBadge = deepOfNightCoverageBadge(deepOfNightCoverage(item));
      if (exclusiveBadge) badges.push(pill(exclusiveBadge, "amber"));
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
  //   · 首领组的候选行随分组切换（同一组首领常常横跨几个出场场合）。
  function summaryCaption(item, entry, shown) {
    if (!entry) return "";
    var pool = candidateEntries(item.entries, state.group);
    // 只有「代表行本身有歧义」的卡片才铺开列全部候选行，别把普通卡片的摘要撑成两行
    //（与 macOS 的 BossCardView.primaryRowNote 同一判据）：
    //   · 夜王有多条 isMain（哪条才是「这只夜王的血量」说不清）；
    //   · 同时属于多个默认可见分组的组（同一张卡在不同分组下给的是不同的行）。
    var isLord = item.kind === "nightlord";
    var ambiguous = isLord ? mainRows(item.entries).length > 1 : hasMultipleGroups(item);
    if (ambiguous && pool.length > 1) {
      var list = pool.map(function (row) {
        return entryLabel(row) + " " +
          fmtInt(computeStats(row, state.party, state.depth, null).hp);
      }).join(" · ");
      var lead = isLord
        ? pool.length + " 条主战行，上方取血量最高的一条："
        : "该分组 " + pool.length + " 条数值行，上方取血量最高的一条：";
      return "<div class='bosses-stat-caption bosses-stat-caption--warn'>" + esc(lead + list) + "</div>";
    }
    // 「共 N 组」数的是展开区真正列出来的行（默认不含只在未放置 / 随从场合的行）。
    var count = Array.isArray(shown) ? shown.length : item.entries.length;
    if (count < 2) return "";
    var label = entryLabel(entry);
    return "<div class='bosses-stat-caption'>代表行：" + esc(label) +
      "<span>共 " + count + " 组，展开看全部</span></div>";
  }

  // 夜王的主战行不止一条时要标明头条取的是最高那条，别让用户以为「这只夜王就这点血」。
  // 夜王卡只在「夜王」分组出现，代表行恒为主战行。
  function hpMetricTitle(item) {
    if (item.kind !== "nightlord") return "血量";
    return mainRows(item.entries).length > 1 ? "主战血量 · 最高" : "主战血量";
  }

  // 深度模式下代表行没有 depthStats 时要直说这一行回落到了常规值，
  // 否则摘要与卡头徽标看着像在互相打架。
  function summaryHpHint(stats) {
    if (state.depth) {
      if (!stats.hasDepth) return TEXT.noDepthStatsText;
      return state.party === 1 ? "含深度倍率" : "深度 1 人 " + fmtInt(stats.hpSingle);
    }
    return state.party === 1 ? "含常驻缩放" : "1 人 " + fmtInt(stats.hpSingle);
  }

  // 多人时敌人攻击力也会上浮的四个档位（7744 / 7753 / 7754 / 7758），
  // 在血量旁边直接标出来——「多人只是血更厚」这个常见误解正是这里错的。
  function partyAttackNote(stats) {
    if (!stats.tier || !(stats.partyAttackRate > 1)) return "";
    return "<div class='bosses-stat-caption bosses-stat-caption--warn'>" +
      esc(multiplayerAttackBadge(stats.partyAttackRate) + "：该档位在 " + partyLabel() +
        "时敌人攻击力也会上浮，不只是血条变长。") + "</div>";
  }

  function cardSummary(item, entry, shown) {
    if (!entry) return "<p class='bosses-none'>该首领没有可用的数值行。</p>";
    var stats = computeStats(entry, state.party, state.depth, null);
    return summaryCaption(item, entry, shown) + partyAttackNote(stats) + "<div class='bosses-stat-row'>" +
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
      return "<p class='bosses-note bosses-note--muted'>" + esc(TEXT.noDepthStatsText) +
        "（数据里没有 depthStats）。</p>";
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
    var options = ["<option value=''" + (current ? "" : " selected") + ">" +
      esc(TEXT.mutationPickerNone) + "</option>"].concat(
      pool.map(function (id) {
        var value = String(id);
        return "<option value='" + esc(value) + "'" + (current === value ? " selected" : "") + ">" +
          esc(mutationOptionLabel(id, mutationFor(state.data, id))) + "</option>";
      })
    ).join("");
    return "<div class='bosses-sub'>" + esc(BADGE_MUTATION) + "（可能的变异档位）</div>" +
      "<div class='bosses-chips'>" + chips + "</div>" +
      "<label class='select-field bosses-mutation-field'>" +
      "<span class='sr-only'>" + esc(TEXT.mutationPickerTitle) + "</span>" +
      "<select data-bosses-mutation='" + esc(key) + "' data-testid='bosses-mutation'>" + options + "</select></label>" +
      "<p class='bosses-note bosses-note--muted'>" + esc(TEXT.mutationStackNote) +
      "：选中档位后，本行上面的血量 / 攻击力 / 卢恩会在当前基础上再乘一层。" +
      "变异倍率的 spCategory = 203，与常驻(0)、深度(0)、人数(140) 都不同分类，不互相覆盖——" +
      "「再乘一层」是按参数结构推断的，游戏里没有公开说明。</p>";
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
      out.push(TEXT.noRewardRowNote + "（getSoul / chaosMatchingRewardLotId / itemLotId_enemy 全为 0 或 -1），" +
        "通常是模板行、血条实体或演出行；选代表行时会排在同分组的实战行之后。");
    }
    if (!out.length) return "";
    return out.map(function (note) {
      return "<p class='bosses-note bosses-note--muted'>" + esc(note) + "</p>";
    }).join("");
  }

  // 展开区逐行的「出场场合」小节（macOS 的 BossRoleEvidenceSection）：每个场合给第一条出处
  //（「表名 行 · 地图」+ 下方说明小字），另有几条就写「另有 N 条出处」；有哪个场合不止一条时
  // 给「展开全部出处 / 只看每个场合的第一条出处」切换；合并行各原始行场合不同时再列逐行场合。
  // 地图的 Paramdex 名 / 地形名与 MSB part 放在摘要的悬停提示里，摘要文字与 macOS 逐字一致。
  function entryRoleBlock(item, entry) {
    var key = entryKey(item, entry);
    var showAll = Boolean(state.evidenceOpen[key]);
    var head = "<div class='bosses-sub'>" + esc(ROLE_TEXT.roleSectionTitle) +
      "<span class='bosses-sub-detail'>" + esc(ROLE_TEXT.roleSectionDetail) + "</span></div>";
    if (!entryRoles(entry).length) {
      return "<div class='bosses-role-evidence' data-testid='bosses-role-evidence'>" + head +
        "<p class='bosses-note bosses-note--muted'>" + esc(ROLE_TEXT.rolesMissing) + "</p></div>";
    }
    var lines = roleEvidenceLines(entry, state.data, showAll).map(function (line) {
      var body;
      if (line.missing) {
        body = "<span class='bosses-evidence-missing'>" + esc(ROLE_TEXT.evidenceMissing) + "</span>";
      } else {
        body = line.items.map(function (ev) {
          return "<div class='bosses-evidence-item'><div class='bosses-evidence-head'>" +
            (ev.npcId !== null ? "<span class='bosses-evidence-row'>" + esc("行 " + ev.npcId) + "</span>" : "") +
            "<span class='bosses-evidence-summary'" + (ev.hint ? " title='" + esc(ev.hint) + "'" : "") + ">" +
            esc(ev.summary) + "</span></div>" +
            (ev.note
              ? "<p class='bosses-evidence-note" + (showAll ? "" : " is-clamped") + "' title='" + esc(ev.note) + "'>" +
                esc(ev.note) + "</p>"
              : "") +
            "</div>";
        }).join("") +
          (line.more ? "<span class='bosses-evidence-more'>" + esc(ROLE_TEXT.evidenceMore(line.more)) + "</span>" : "");
      }
      return "<li>" + rolePill(line) + "<div class='bosses-evidence-body'>" + body + "</div></li>";
    }).join("");
    var toggle = hasMoreEvidence(entry)
      ? "<button type='button' class='bosses-evidence-toggle' data-bosses-evidence='" + esc(key) + "'" +
        " aria-expanded='" + showAll + "'>" +
        esc(showAll ? ROLE_TEXT.evidenceCollapse : ROLE_TEXT.evidenceExpand) + "</button>"
      : "";
    var perRow = rowRolesSummary(entry, state.data);
    return "<div class='bosses-role-evidence' data-testid='bosses-role-evidence'>" + head +
      "<ul class='bosses-evidence-list'>" + lines + "</ul>" + toggle +
      (perRow ? "<p class='bosses-note bosses-row-roles'>" + esc(perRow) + "</p>" : "") + "</div>";
  }

  function entryBlock(item, entry) {
    var stats = statsFor(item, entry);
    var tiers = state.data && state.data.scalingTiers ? state.data.scalingTiers : null;
    var caption = scalingCaption(entry, tiers);
    // 场合徽标在前（该行 roles 全部列出），状态徽标在后。行级 threat 不再当徽标：
    // 它只是缩放档位，挨着场合徽标会被读成出场位置，降为标题下方的「威胁档位」小字。
    var badges = entryRoleBadges(entry, state.data).map(function (badge) {
      return rolePill(badge);
    }).concat(entryBadgeTexts(item, entry, stats).map(function (text) {
      if (text === "主战") return pill(text, "green");
      if (text === BADGE_MUTATION) return pill(text, "red");
      return pill(text, "amber");
    }));

    var npcIds = Array.isArray(entry.npcIds) ? entry.npcIds : [];
    var idText = "npcId " + String(entry.npcId) + (npcIds.length > 1 ? "（合并 " + npcIds.length + " 行）" : "");
    // 当前分组对应的行描边高亮（卡里不止一行时才有意义）。
    var inGroup = item.entries.length > 1 && rolesInGroup(entryRoles(entry), state.group).length > 0;
    var threat = asText(entry.threat);

    return "<section class='bosses-entry" + (inGroup ? " is-in-group" : "") + "'>" +
      "<header class='bosses-entry-head'>" +
      "<strong>" + esc(entryLabel(entry)) + "</strong>" +
      "<span class='bosses-entry-badges'>" + badges.join("") + "</span>" +
      "<span class='bosses-entry-id'>" + esc(idText) + "</span>" +
      "</header>" +
      (threat ? "<p class='bosses-entry-threat'>" + esc(ROLE_TEXT.threatTierCaption([threat])) + "</p>" : "") +
      entryRoleBlock(item, entry) +
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
      // 档位名「守夜首领威胁档」挂在场景头目 / 据点首领行上最容易被读成出场位置
      //（铃珠猎人野外版 31000010 就是 7753 · Night Boss Threat）：只在这种行上补一句说明。
      (threatRoleMismatch(entry, tiers)
        ? "<p class='bosses-note bosses-note--muted'>" + esc(ROLE_TEXT.threatTierNote) + "。</p>"
        : "") +
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
    // noReward 只作小字，不影响是否显示：Storm King / 蚯蚓脸这些不掉奖励但仍是首领。
    // 上一版把它漏在这一块外面，于是巨大骷髅躯干（五个名字字段全空、noReward = true）
    // 展开后一句说明都没有，与 macOS 的 showsNameNotes 对不上。
    if (item.noReward) parts.push(TEXT.noRewardGroupNote + "。");
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
        esc(depthWeightText(value)) + "</td>";
    }).join("");
    var head = DEPTHS.map(function (depth) {
      return "<th scope='col'>" + esc(deepText(state.data, "depth") + " " + depth) + "</th>";
    }).join("");
    return "<div class='bosses-sub'>各" + esc(deepText(state.data, "depth")) + "出现权重</div>" +
      "<table class='bosses-mini-table bosses-chance-table'><thead><tr>" + head + "</tr></thead>" +
      "<tbody><tr>" + cells + "</tr></tbody></table>" +
      "<p class='bosses-note bosses-note--muted'>权重来自 NightBossMenuParam.depth1..5ChanceWeight，是同一深度内各夜王之间的相对权重，不是百分比。" +
      "守夜首领、场景头目等其余首领没有按深度的出现权重参数，数据集里也没有。</p>";
  }

  // 卡片级「出场场合」一览（Windows 独有的界面元素）：每个场合涉及几条数值行、当前分组
  // 对应哪几行（下方描边高亮），以及降成小字的「威胁档位」——后者与 macOS 展开区的
  // identifierNote 同一句（threatTierCaption(tiers) + "：" + threatTierNote）。
  // 场合数据缺失时写「出场场合：数据未内置」。
  function roleSectionBlock(item) {
    var parts = [];
    if (item.roleMissing) {
      parts.push("<p class='bosses-note'>" + esc(ROLE_TEXT.rolesMissing) + "</p>");
    } else {
      var chips = roleEntryCounts(item.entries, item.roles).map(function (row) {
        var badge = roleBadge(state.data, row.role);
        return rolePill(badge, ROLE_PAGE_TEXT.roleRowsChip(badge.text, row.rows));
      }).join("");
      parts.push("<div class='bosses-chips'>" + chips + "</div>");
      var here = item.entries.filter(function (entry) {
        return rolesInGroup(entryRoles(entry), state.group).length > 0;
      }).length;
      if (item.entries.length > 1 && here) {
        parts.push("<p class='bosses-note bosses-note--muted'>" +
          esc(ROLE_PAGE_TEXT.currentGroupNote(GROUP_TITLES[state.group] || "", here)) + "</p>");
      }
    }
    if (item.tiers && item.tiers.length) {
      parts.push("<p class='bosses-note bosses-note--muted'>" +
        esc(ROLE_TEXT.threatTierCaption(item.tiers) + "：" + ROLE_TEXT.threatTierNote) + "</p>");
    }
    return "<div class='bosses-role-section' data-testid='bosses-role-section'>" +
      "<div class='bosses-sub'>" + esc(ROLE_TEXT.roleSectionTitle) + "</div>" + parts.join("") + "</div>";
  }

  function cardBody(item, shown) {
    if (!item.entries.length) return "<p class='bosses-none'>没有可用的数值行。</p>";
    var head = "";
    if (item.description) {
      head = "<p class='bosses-desc'>" + esc(item.description) + "</p>";
    }
    var hiddenRows = item.entries.length - shown.length;
    return head + roleSectionBlock(item) + nameNoteBlock(item) + depthChanceBlock(item) + shown.map(function (entry) {
      return entryBlock(item, entry);
    }).join("") +
      (hiddenRows > 0
        ? "<p class='bosses-note bosses-note--muted bosses-hidden-rows' data-testid='bosses-hidden-rows'>" +
          esc(ROLE_TEXT.hiddenRows(hiddenRows)) + "</p>"
        : "");
  }

  function cardInner(item) {
    var expanded = Boolean(state.expanded[item.uid]);
    // 折叠态的代表行跟着当前分组走：同一张卡可能同时出现在「守夜首领」「场景头目」「据点首领」里，
    // 场景头目分组下就该看场景头目那几行，而不是恒取 variants[0]（常常是血量更高的守夜行）。
    var entry = representativeEntry(item.entries, state.group);
    // 展开区列出的行：默认收起只出现在「未放置」「随从/召唤物」的行（开关打开才列）。
    var shown = displayEntries(item.entries, state.showHidden);
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
      "<span class='bosses-entry-count'>" +
      esc(ROLE_TEXT.rowCount(shown.length, item.entries.length - shown.length)) + "</span></div>" +
      cardSummary(item, entry, shown) +
      (expanded ? "<div class='bosses-card-body'>" + cardBody(item, shown) + "</div>" : "");
  }

  function cardHtml(item) {
    var expanded = Boolean(state.expanded[item.uid]);
    return "<article class='card bosses-card" + (expanded ? " is-expanded" : "") +
      (isItemHiddenByDefault(item) ? " is-hidden-entity" : "") + "'" +
      " data-bosses-card='" + esc(item.uid) + "'>" + cardInner(item) + "</article>";
  }

  // ------------------------------------------------------------ 模板：底部

  // 页脚各块共用的卡片列表：页面已经建好的就直接用，否则现建一份（测试 / 首次渲染）。
  function itemsFor(data) {
    return state.data === data && state.items.length ? state.items : buildItems(data, fold);
  }

  function caveatsBlock(data) {
    var list = Array.isArray(data.caveats) ? data.caveats : [];
    if (!list.length) return "";
    // 多重归属说明（macOS 在「数据说明」里的同一句 BossRoleText.multiGroupNote）。
    var multi = multiGroupItems(itemsFor(data));
    return "<details class='card bosses-details' data-testid='bosses-caveats'>" +
      "<summary><span class='bosses-summary-title'>数据说明与已知取舍</span>" +
      pill(list.length + " 条", "amber") + "</summary>" +
      "<div class='bosses-details-body'>" +
      "<p class='bosses-note'>本页数值直接读取游戏参数表，不是官方公布数据，也不是实测结论；标注与实际手感可能有出入。</p>" +
      "<ul class='bosses-caveat-list'>" + list.map(function (text) {
        return "<li>" + esc(text) + "</li>";
      }).join("") + "</ul>" +
      (multi.length
        ? "<p class='bosses-note' data-testid='bosses-multi-group-note'>" + esc(ROLE_TEXT.multiGroupNote(
          multi.length, multi.map(function (item) { return item.name; }))) + "</p>"
        : "") +
      "</div></details>";
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
      "<p class='bosses-note bosses-note--lead'>" + esc(TEXT.multiplayerAuditSummary) + "</p>" +
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
      "<p class='bosses-note bosses-note--lead'>" + esc(TEXT.mutationCountNote) +
      "：数字说的是「该地图、该深度下这一类敌人有几只会变异」，这点最容易读错。" +
      "场景头目与封印监牢首领深度 1 全是 0，也就是深度 1 遇不到变异的场景头目 / 监牢首领。</p>" +
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

  // 「出场场合说明」（macOS 的 BossRoleOverview）：先写为什么「威胁档位」和分组对不上，
  // 再逐个场合列「→ 所属分组（默认隐藏的分组标注）」、卡片计数（守夜 / 野外首领里带它的组数，
  // 夜王另计）与判定口径（roleNames.description），最后是 notes.roleAudit.summary 的对照结论。
  // 「未放置」「随从/召唤物」各自是一个默认隐藏的分组，计数就是打开开关后该分组里的卡片数。
  function roleOverviewBlock(data) {
    var rows = roleOverviewRows(data, itemsFor(data));
    var body = rows.map(function (row) {
      return "<tr><th scope='row'>" + rolePill(roleBadge(data, row.role)) +
        (row.en ? "<span>" + esc(row.en) + "</span>" : "") + "</th>" +
        "<td>" + esc("→ " + row.groupText) + "</td><td>" + esc(row.countText) + "</td>" +
        "<td class='bosses-role-desc'>" + esc(row.description) + "</td></tr>";
    }).join("");
    var audit = data.notes && data.notes.roleAudit && Array.isArray(data.notes.roleAudit.summary)
      ? data.notes.roleAudit.summary
      : [];
    return "<details class='card bosses-details' data-testid='bosses-roles'>" +
      "<summary><span class='bosses-summary-title'>" + esc(ROLE_TEXT.overviewTitle(rows.length)) + "</span></summary>" +
      "<div class='bosses-details-body'>" +
      "<p class='bosses-note bosses-note--lead'>" + esc(ROLE_TEXT.threatTierNote + "。") + "</p>" +
      "<div class='table-wrap bosses-table-wrap'><table class='bosses-mini-table bosses-role-table'>" +
      "<thead><tr><th scope='col'>场合</th><th scope='col'>分组</th><th scope='col'>组数</th>" +
      "<th scope='col'>判定口径</th></tr></thead><tbody>" + body + "</tbody></table></div>" +
      (audit.length
        ? "<div class='bosses-sub'>" + esc(ROLE_TEXT.auditTitle(audit.length)) + "</div>" +
          "<ul class='bosses-caveat-list'>" + audit.map(function (line) {
            return "<li>" + esc(line) + "</li>";
          }).join("") + "</ul>"
        : "") +
      "</div></details>";
  }

  // 底部「收录」一行的数字（macOS 的 BossDataIndex.inventorySummary，同一组数、同一句话）：
  // 每个分组（含默认隐藏的两个）按打开开关计的卡片数、同时属于多个默认可见分组的组数、数值行总数。
  // 「收录」说的是数据集收录了多少，不跟着开关变。
  function inventoryCounts(items) {
    var list = Array.isArray(items) ? items : [];
    var rows = 0;
    list.forEach(function (item) { rows += Array.isArray(item.entries) ? item.entries.length : 0; });
    return {
      groups: groupCounts(list, true),
      multi: multiGroupItems(list).length,
      rows: rows
    };
  }

  function inventoryText(counts) {
    var parts = GROUP_ORDER.map(function (key) {
      return GROUP_TITLES[key] + " " + (counts.groups[key] || 0);
    });
    var text = parts.join(" · ");
    if (counts.multi) text += "（含 " + counts.multi + " 组同时属于多个分组）";
    return text + " · 数值行 " + counts.rows;
  }

  function versionBlock(data) {
    var counts = inventoryCounts(itemsFor(data));

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
      "<div class='bosses-meta-wide'><dt>收录</dt><dd>" + esc(inventoryText(counts)) + "</dd></div>" +
      "</dl>" +
      (sources ? "<div class='bosses-sub'>来源</div><ul class='bosses-source-list'>" + sources + "</ul>" : "") +
      "</div></details>";
  }

  // 默认隐藏了哪些组：不折叠，放在各个说明块之后、「数据版本与来源」之前（与 macOS 底部同一位置）。
  // 开关关着时列表里没有任何地方提到这 12 组，这一段就是唯一的交代。
  function hiddenSummaryBlock(data) {
    var text = hiddenSummaryText(itemsFor(data));
    if (!text) return "";
    return "<section class='card bosses-hidden-summary' data-testid='bosses-hidden-summary'>" +
      "<p class='bosses-note'>" + esc(text) + "</p></section>";
  }

  function footerHtml(data) {
    return caveatsBlock(data) + roleOverviewBlock(data) + scalingTiersBlock(data) + depthOverviewBlock(data) +
      mutationCategoryBlock(data) + hiddenSummaryBlock(data) + versionBlock(data);
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
    var perGroup = groupCounts(state.items, state.showHidden);
    dom.querySelectorAll("[data-bosses-group-count]").forEach(function (node) {
      node.textContent = String(perGroup[node.getAttribute("data-bosses-group-count")] || 0);
    });
    if (count) {
      var inGroup = state.items.filter(function (item) { return itemInGroup(item, state.group); });
      var total = perGroup[state.group] || 0;
      var hiddenCount = inGroup.filter(isItemHiddenByDefault).length;
      var depthText = state.depth ? " · " + depthLabel(state.data, state.depth) : "";
      var hiddenText = hiddenCountText(hiddenCount, state.showHidden);
      count.textContent = "显示 " + visible.length + " / " + total + " 个首领 · " +
        partyLabel() + depthText + (hiddenText ? " · " + hiddenText : "");
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
      var key = button.dataset.bossesGroup;
      var active = key === state.group;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-checked", String(active));
      // 「随从/召唤物」「未放置」只在打开「显示隐藏实体」时出现在分组切换里。
      button.hidden = isHiddenGroup(key) && !state.showHidden;
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
      var evidence = event.target.closest("[data-bosses-evidence]");
      if (evidence) {
        var evidenceKey = evidence.getAttribute("data-bosses-evidence");
        if (state.evidenceOpen[evidenceKey]) delete state.evidenceOpen[evidenceKey];
        else state.evidenceOpen[evidenceKey] = true;
        renderCard(evidenceKey.slice(0, evidenceKey.lastIndexOf("#")), "data-bosses-evidence", evidenceKey);
        return;
      }
      var toggle = event.target.closest("[data-bosses-toggle]");
      if (toggle) {
        var uid = toggle.dataset.bossesToggle;
        if (state.expanded[uid]) {
          delete state.expanded[uid];
          // 收起卡片时「展开全部出处」一并归零（macOS 每行各自记，收起后重来）。
          Object.keys(state.evidenceOpen).forEach(function (key) {
            if (key.slice(0, key.lastIndexOf("#")) === uid) delete state.evidenceOpen[key];
          });
        } else {
          state.expanded[uid] = true;
        }
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
        // 关掉开关时正停在「随从/召唤物」「未放置」上：那两个分组已经不在切换里了，
        // 退回默认的「夜王」（macOS 退回「全部」，Windows 没有「全部」这一项）。
        if (!state.showHidden && isHiddenGroup(state.group)) state.group = GROUP_ORDER[0];
        renderControls();
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
    state.evidenceOpen = {};
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
      normalizeRoles: normalizeRoles,
      entryRoles: entryRoles,
      unionRoles: unionRoles,
      isHiddenRole: isHiddenRole,
      isHiddenGroup: isHiddenGroup,
      onlyHiddenRoles: onlyHiddenRoles,
      roleGroup: roleGroup,
      rolesInGroup: rolesInGroup,
      roleGroups: roleGroups,
      isItemHiddenByDefault: isItemHiddenByDefault,
      visibleGroups: visibleGroups,
      hasMultipleGroups: hasMultipleGroups,
      visibleTabs: visibleTabs,
      displayEntries: displayEntries,
      hiddenEntryCount: hiddenEntryCount,
      roleTitle: roleTitle,
      roleDescription: roleDescription,
      roleBadge: roleBadge,
      cardRoleBadges: cardRoleBadges,
      entryRoleBadges: entryRoleBadges,
      roleSearchTerms: roleSearchTerms,
      roleEntryCounts: roleEntryCounts,
      roleEvidenceList: roleEvidenceList,
      evidenceSummaryText: evidenceSummaryText,
      evidenceHint: evidenceHint,
      roleEvidenceLines: roleEvidenceLines,
      hasMoreEvidence: hasMoreEvidence,
      rowRoleGroups: rowRoleGroups,
      rowRolesSummary: rowRolesSummary,
      cardTiers: cardTiers,
      threatRoleMismatch: threatRoleMismatch,
      groupCounts: groupCounts,
      multiGroupItems: multiGroupItems,
      hiddenSummaryText: hiddenSummaryText,
      hiddenSummaryBlock: hiddenSummaryBlock,
      orderedRoles: orderedRoles,
      roleOverviewRows: roleOverviewRows,
      hiddenCountText: hiddenCountText,
      inventoryCounts: inventoryCounts,
      inventoryText: inventoryText,
      deepCoverage: deepCoverage,
      deepOfNightCoverage: deepOfNightCoverage,
      deepCoverageBadge: deepCoverageBadge,
      deepOfNightCoverageBadge: deepOfNightCoverageBadge,
      isStagingRow: isStagingRow,
      multiplayerAttackBadge: multiplayerAttackBadge,
      depthWeightText: depthWeightText,
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
      GROUP_ORDER: GROUP_ORDER,
      HIDDEN_GROUPS: HIDDEN_GROUPS,
      TABS: TABS,
      ROLE_ORDER: ROLE_ORDER,
      OTHER_GROUP_ROLES: OTHER_GROUP_ROLES,
      ROLE_GROUP: ROLE_GROUP,
      HIDDEN_ROLES: HIDDEN_ROLES,
      THREAT_TIER_GROUPS: THREAT_TIER_GROUPS,
      NAME_SOURCE_BADGES: NAME_SOURCE_BADGES,
      STAGING_LABEL_KEYWORDS: STAGING_LABEL_KEYWORDS,
      TEXT: TEXT,
      ROLE_TEXT: ROLE_TEXT,
      ROLE_PAGE_TEXT: ROLE_PAGE_TEXT
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
