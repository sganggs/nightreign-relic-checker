// 增伤排名页。页面模块契约见 renderer/pages/README.md。
// 本文件由「增伤排名」功能开发者独占：只改这里与 pages/ranker.css。
//
// 数据：ctx.getGameData("skills") → resources/skills.json（schemaVersion 3：局内战技池进 weaponIds / weaponSources，
//                                   选段读 weapons[].skillVariants[战技 ID]，variants[].atkIds 已按 TAE 核实；
//                                   hits[].notInvoked / fpBoth / selfOrAllyOnly 见数据集 fieldNotes；
//                                   spells[] 只收可施放的法术，每个都有 casterWeaponIds）
//       ctx.getGameData("buffs")  → resources/buffs.json（schemaVersion 6：sourceSlot / appliesTo /
//                                   slotRules / weaponAffixes / fixedRelics / stackInput / exclusiveKey /
//                                   affixVariant / selfAllyPair / accumulatorLadder / goodsLevel）
//       ctx.Core + ctx.catalog    → 遗物合法性（core.js 的 check / isEligible / canonicalOrder）
//
// 页面结构：「自己组一套配置」
//   ① 输出手段：战技（+ 武器）、魔法或祷告（类型开关三档，只做界面层过滤）；分段勾选、伤害构成（与旧版相同，算法不变）。
//   ② 常规 / 深夜开关（slotRules.modes）：决定武器词条上限、深夜专属上限、遗物格数。
//   ③ 局内武器词条栏（weaponAffixes）：按对当前输出的有效倍率排序，数量步进，受上限约束。
//   ④ 遗物栏：3 或 6 张卡，每张二选一——官方固定词条遗物（fixedRelics）或自组
//      （普通遗物走 Core.check("currentNormal")，深夜遗物走 Core.check("deepPositive") + 诅咒配对）。
//   ⑤ 护符栏：2 个槽位（主槽位是 accessory 的条目按护符分组）。
//   ⑥ 其它增益栏：道具 / 增益法术 / 战技自增益 / 武器固有 / 角色 / 永久强化 / 局内叠层 / 其它。
//      「道具」里携物知识 2／3 级的行（goodsLevel ≥ 2）在名字旁标等级，分栏说明区说明等级来自学者的能力。
//   ⑦ 汇总：总倍率、各栏小计、槽位用量、生效条目清单、「按推荐填满」。
//
// **两端同一口径**（macOS：RelicCore/BuffLoadout.swift；数据以 stackingRules / notes.ranking 为准）：
//   · 生效判定一律用 buffs[].appliesTo[输出类别]（战技 → skill，含子弹段；魔法 → sorcery；祷告 → incantation）。
//     conditional 看 requires：hand / attackWeaponTypes（法术按施法器）/ physicalType 自动判定，subCategoriesAny
//     用 attackIndex 判定（部分段命中按 1＋(倍率−1)×命中段占比近似），attackContexts 用「攻击情境」勾选，
//     imbuedWeaponOnly / attachedWeaponOnly / requiresGoodsIds / 认不出的键要用户确认。
//   · 作用对象只留 self / ally（selfAllyPair 的 Allies 那一行不算施放者自己）；direction=decrease 一律不计入。
//   · activation ≠ passive 与要确认的条件默认不计入：占槽位的栏（武器词条、遗物、护符、当前武器固有）放进来
//     ≠ 条件成立，要勾「条件成立」；「其它增益」栏里勾选即确认；叠层填层数、累积阶梯选层同样算确认。
//   · 多档词条（数据 affixVariant）只算选中的一档（默认第 1 档，参数里查不到武器类别 → 档位的映射）。
//   · 去重按 stacking.exclusiveKey：同键只留一份（applyHighest 按 categoryPriority 取数值小的，其余取有效
//     倍率高的，再取 spEffectId 小的），不同键相乘；同一 spEffectId 多份：stackSelf 各份相乘，其余只算一份。
//   · 总倍率 = Σ_type 占比_type × Π_(去重后的条目) 该条目在 type 上的倍率；各栏小计同法只取本栏条目。
//   · 按推荐填满：武器词条 → 遗物逐格（固定 vs 自组，同分取固定）→ 护符；每步取总倍率增幅最大的
//     （同增幅取 ID 小的），不选条件型、叠层与累积阶梯。
// 配置部分的文案串全部集中在下方 TEXT 常量表，与 macOS 端 LoadoutText.table 是同一张表（点号路径逐键对照，
// 两端测试都校验同一个摘要）。原样保留的输出手段／分段命中／伤害构成／底部原文折叠沿用旧版的行内文案，不在此表；
// 例外是 v3 新增的武器来源标记（weaponSource.*）与输出手段的类型开关／检索框文案（meansKind.* / meansCard.* /
// meansSearch.* / meansSpellFlatNote），三端同名同值，也放在表里。
// 本页只做「相对伤害构成」：没有强化等级、能力值补正与 AttackElementCorrectParam，绝对伤害不在范围内。
(function (root) {
  "use strict";

  var PAGE_KEY = "ranker";
  var SKILLS_DATA = "skills";
  var BUFFS_DATA = "buffs";

  // ---------------------------------------------------------------- 常量表

  // 伤害类型轴：物理按攻击类型细分 + 四种属性。顺序即展示顺序（与 macOS SkillDamageChannel 同序）。
  var TYPE_KEYS = [
    "slash", "blow", "thrust", "neutral", "physNone",
    "magic", "fire", "lightning", "holy"
  ];

  var TYPE_INFO = {
    slash: { zh: "斩击", element: "physical", short: "斩" },
    blow: { zh: "打击", element: "physical", short: "打" },
    thrust: { zh: "突刺", element: "physical", short: "突" },
    neutral: { zh: "标准", element: "physical", short: "标准" },
    physNone: { zh: "物理（无类型）", element: "physical", short: "物理" },
    magic: { zh: "魔力", element: "magic", short: "魔力" },
    fire: { zh: "火", element: "fire", short: "火" },
    lightning: { zh: "雷", element: "lightning", short: "雷" },
    holy: { zh: "圣", element: "holy", short: "圣" }
  };

  var ELEMENTS = ["physical", "magic", "fire", "lightning", "holy"];

  var TYPES_BY_ELEMENT = {
    physical: ["slash", "blow", "thrust", "neutral", "physNone"],
    magic: ["magic"],
    fire: ["fire"],
    lightning: ["lightning"],
    holy: ["holy"]
  };

  // enums.atkAttribute 的 0..3；252 / 253 要回查武器，254（None）落到 physNone。
  var PHYS_BY_INDEX = ["slash", "blow", "thrust", "neutral"];
  var ATTRIBUTE_TO_TYPE = { Slash: "slash", Strike: "blow", Pierce: "thrust", Standard: "neutral" };

  // rateFields[].key 的前缀 → 伤害类型轴。physics 覆盖全部物理子类型。
  var RATE_PREFIX_ELEMENT = {
    physics: "physical", magic: "magic", fire: "fire", thunder: "lightning", dark: "holy"
  };
  var RATE_PREFIX_PHYS = { slash: "slash", blow: "blow", thrust: "thrust", neutral: "neutral" };

  // 「这条真的增伤吗」的阈值：差在小数第七位的只是加权求和的浮点噪音。
  var USEFUL_EPSILON = 1.0000001;
  // 比较倍率时的容差（两端同值）：两个倍率相差不超过它就算相同。
  var EPSILON = 1e-9;

  // 输出类别（appliesTo 的键）。战技的子弹段同样按 skill。
  var OUTPUT_CLASSES = ["skill", "sorcery", "incantation"];

  // 输出手段类型开关的三档（展示顺序，默认第一档）。只做界面层过滤，文案取 TEXT.meansKind。
  var MEANS_KINDS = ["skill", "sorcery", "incantation"];

  // 法术的「出手武器」：魔法由手杖（wepType 57）施放，祷告由圣印记（61）施放
  // （notes.userQuestions.Q2 的口径）。用于 requires.attackWeaponTypes 与武器词条栏的类别过滤。
  var CASTER_WEP_TYPE = { sorcery: 57, incantation: 61 };

  // requires 各键的判定顺序（appliesToDetail.<cls>.requires）。未知键一律要用户确认。
  var REQUIRE_ORDER = [
    "hand", "attackWeaponTypes", "physicalType", "subCategoriesAny",
    "attackContexts", "imbuedWeaponOnly", "attachedWeaponOnly"
  ];

  // 攻击情境 chip 的固定顺序（enums.attackContext 的键；数据里没用到的不显示）。
  var ATTACK_CONTEXT_ORDER = [
    "criticalHit", "thrustingCounter", "guardCounter", "chainFinisher",
    "chargedHeavyAttack", "chargedSkill", "chargedSpell",
    "jumpAttack", "dashAttack", "rollingAttack", "backstepAttack",
    "initialAttack", "horsebackAttack", "twoHanded", "dualWield"
  ];

  // 汇总的四栏（小计按这四栏算；「其它增益」含当前武器固有）。
  var COLUMN_ORDER = ["weaponAffix", "relic", "accessory", "other"];

  // 其它增益栏的分组（sourceSlot 主槽位）与展示顺序。
  var OTHER_SLOTS = [
    "consumable", "spellBuff", "weaponSkill", "weaponInnate",
    "character", "permanent", "runStack", "other"
  ];

  // 深夜遗物负面词条池的兜底值（与 core.js 的 DEEP_CURSE_POOL_ID 同值）。实际取值由 buildCatalogIndex
  // 从词条库现算（只装诅咒词条的那个池），词条库里算不出来才用这里。
  var DEEP_CURSE_POOL_ID = 3000000;

  var PAGE_SIZE = 40;
  var PICKER_LIMIT = 40;

  // ==================================================== 文案常量表（两端对照）
  // 配置部分的所有文案都从这里取（原样保留的输出手段／分段命中／伤害构成／底部原文折叠除外）。
  // 带 {0} {1} 的是格式串，由 fmt() 按位置替换；macOS 端 LoadoutText.table 按点号路径逐键同文。
  var TEXT = {
    pageTitle: "增伤排名",
    pageSubtitle: "选一个战技、魔法或祷告，再自己组一套局内配置：武器词条、遗物、护符与其它增益，看总增伤",
    noData: "数据未内置",
    loadoutMissing: "增益数据缺少配置页需要的字段（slotRules／appliesTo，需 schemaVersion 6）",
    schemaTooOld: "增益数据是 schemaVersion {0}：本页按 v6 的 appliesTo / slotRules / exclusiveKey 组配置，旧数据缺这些字段，结果不可信",
    // 输出手段 · 类型开关三档（战技 / 魔法 / 祷告，游戏里魔法与祷告是两类）、检索框与选中魔法／祷告时的标记。
    // 只是界面层的过滤：输出手段条目与所选的 kind 不变，生效判定照旧按 appliesTo 的 skill / sorcery / incantation。
    // 三端同名同值（macOS LoadoutText.table / 安卓文案表）。
    meansKind: { skill: "战技", sorcery: "魔法", incantation: "祷告" },
    meansCard: { subtitle: "搜索战技、魔法或祷告（中文／英文名都可）；战技再选一把武器" },
    meansSearch: { placeholder: "搜索战技 / 魔法 / 祷告名称", empty: "没有匹配的输出手段" },
    meansSpellFlatNote: "魔法／祷告的段只用固定值",
    // 输出手段 · 武器选择器（skills schemaVersion 3 的 weaponSources：固定战技 / 局内战技池）
    weaponSource: {
      fixed: "固定战技",
      pool: "局内可抽到",
      poolHint: "局内掉落的这把武器有机会抽到这个战技（按战技池权重）",
      note: "武器列表含固定带这个战技的武器与局内战技池能抽到它的武器；动作套按这一把武器实解。"
    },
    // 工具条
    runMode: { normal: "常规", deep: "深夜" },
    runModeLabel: "出击模式",
    runModeAria: "常规或深夜",
    runModeHint: "常规：武器词条最多 {0} 条、遗物 {1} 件；深夜：武器词条最多 {2} 条（其中深夜专属最多 {3} 条）、遗物 {4} 件（普通 {5} ＋ 深夜 {6}）",
    modeTrimmed: "切到常规：已去掉 {0} 条深夜专属／超出常规上限的武器词条，深夜遗物格已清空",
    fillButton: "按推荐填满",
    fillNote: "只填空着的槽位：先局内武器词条，再逐格遗物（最好的固定遗物与贪心自组的合法遗物比较，同分取固定遗物），最后护符；每一步取让总倍率增幅最大的候选（同增幅取 ID 小的），不选条件型、叠层与累积阶梯，已选的一律保留",
    fillDone: "已按推荐填入 {0} 项",
    fillNothing: "没有可填的空槽或可用条目",
    clearButton: "清空配置",
    showInactive: "显示不生效项",
    showInactiveHelp: "appliesTo 判为不生效（或条件不满足）的条目默认隐藏；打开后虚化显示并写明原因",
    contextsLabel: "攻击情境（勾选后，只在该情境成立的倍率才计入）",
    handLabel: "武器槽",
    handHelp: "按增益的 appliesToDetail.requires.hand 判定当前手（只作用于另一只手的增益不计入），默认按右手计算",
    spellHandNote: "施法器同样握在左右手之一：按 appliesToDetail.requires.hand 判定，只作用于另一只手的增益不计入；武器词条栏按施法器（魔法＝手杖、祷告＝圣印记）的类别过滤。",
    searchPlaceholder: "搜索名称",
    // 栏目与分组
    columns: { weaponAffix: "局内武器词条", relic: "遗物", accessory: "护符", other: "其它增益" },
    otherGroups: {
      consumable: "道具", spellBuff: "增益法术", weaponSkill: "战技自增益", weaponInnate: "武器固有",
      character: "角色", permanent: "永久强化", runStack: "局内叠层", other: "其它"
    },
    outputClass: { skill: "战技", sorcery: "魔法", incantation: "祷告" },
    hand: { 1: "右手", 2: "左手" },
    wepTypeFallback: "类别 {0}",
    characterOther: "其他角色",
    characterNames: {
      Wylder: "追踪者", Guardian: "守护者", Ironeye: "铁之眼", Duchess: "女爵", Raider: "无赖",
      Revenant: "复仇者", Recluse: "隐士", Executor: "执行者", Scholar: "学者", Undertaker: "送葬者"
    },
    characterKinds: { Skill: "技艺", Ultimate: "绝招", Passive: "被动" },
    groupUnknownSkill: "未标明战技",
    groupAutoInnate: "当前武器自带（自动列入）",
    groupOtherInnate: "其它武器的固有效果（手动勾选）",
    // 一条的状态（短标签）
    states: {
      counted: "计入",
      duplicate: "同键不叠加",
      pending: "条件未确认",
      context: "需勾选攻击情境",
      no: "不生效",
      zeroStacks: "层数为 0",
      tierOff: "未选的层",
      variantOff: "未选的档",
      relicInvalid: "遗物不合法",
      noDamage: "不含伤害倍率",
      neutral: "对当前构成无增益"
    },
    // 生效判定的短标签（appliesTo）
    verdict: {
      yes: "生效",
      partial: "部分段生效",
      needsUser: "条件生效",
      conditionalMet: "生效（条件已满足）",
      no: "不生效"
    },
    badges: {
      conditional: "条件型",
      activated: "发动型",
      copies: "按份数叠加",
      ladder: "叠层",
      accLadder: "累积阶梯",
      variant: "按武器类别取一档",
      inferredSource: "来源为推断",
      ally: "队友增益",
      allyPair: "队友那一行",
      potency: "档位{0}",
      deepOnly: "深夜专属",
      blessing: "武器赐福",
      fixed: "固定词条",
      curse: "诅咒",
      requiresCurse: "需诅咒",
      outsideWeaponType: "不在当前武器类别",
      inferredTiers: "参数推断，未实测",
      currentSkill: "当前战技",
      autoInnate: "当前武器固有，自动列入",
      inferredInnate: "行名推断"
    },
    // appliesTo 判定
    verdictMissing: "数据未给出这类输出的 appliesTo，按不生效处理",
    verdictNoFallback: "数据判定对这类输出不生效",
    requireHand: "只作用于{0}武器（当前为{1}）",
    requireWepType: "只对用{0}发动的攻击生效（当前为{1}）",
    requireWepTypeNoWeapon: "只对用{0}发动的攻击生效（当前没有选武器）",
    requirePhysical: "只作用于{0}攻击",
    requirePhysicalFail: "只作用于{0}攻击（当前构成里没有这一类）",
    requireSubsAll: "所选{0}的 {1} 段都带子类别 {2}",
    requireSubsFail: "所选{0}的命中段都不带子类别 {1}",
    requireSubsPartial: "所选{0}只有 {1}/{2} 段带子类别 {3}：按 1＋(倍率−1)×{1}/{2} 近似加权（段数取 attackIndex 对整招的统计，与上方分段勾选无关）",
    requireSubsUnknown: "attackIndex 里没有所选{0}，子类别 {1} 无法自动判定，需确认",
    requireContext: "只在「{0}」时成立（在「攻击情境」里勾选）",
    requireImbued: "只对附加了属性的那把武器生效（附魔／油脂／出击时附加），需确认",
    requireAttached: "只对带这条词条的那把武器生效，需确认",
    requireUnknown: "数据要求 {0}，本页无法自动判定，需确认",
    requireManual: "数据判定为有条件生效：{0}，需确认",
    requireGoods: "需同时使用道具：{0}，需确认",
    goodsFallback: "道具 #{0}",
    activationNeed: {
      conditional: "条件型：需满足发动条件（残血、双手持、命中触发…）",
      activated: "发动型：只在技艺／绝招／战技发动期间存在",
      equipped: "条件型：装备中有 {0} 把以上{1}（与出手的武器无关）"
    },
    // 不计入的原因
    reasonNoDamage: "不含计入伤害的倍率字段",
    reasonVariantOff: "同一遗物词条的 {0} 档按出击武器类别只生效一档（数据 affixVariant），当前按第 {1} 档计算",
    reasonAllyPair: "同一战技的队友那一行（selfAllyPair.role=ally）：施放者自己吃不到，只在队友施放、落到自己身上时计入",
    reasonTarget: "作用对象不是自己（target={0}）",
    reasonDecrease: "direction=decrease：这是减益（降低自己的伤害、降低敌人攻击力等），按 notes.ranking 第②步只保留 increase／mixed，不计入增伤",
    reasonZeroStacks: "层数为 0，不计入（填层数即视为条件成立）",
    reasonTierNone: "累积阶梯还没选层（选层即视为条件成立）",
    reasonTierOff: "累积阶梯只算选中的那一层（当前选第 {0} 层）",
    reasonRelicInvalid: "所在的自组遗物不合法，整件不计入",
    reasonNeutral: "对当前伤害构成没有增益（倍率 ×1、没有正的攻击力加算）",
    reasonDupKey: "与「{0}」同属互斥键 {1}，同键只取一份（取有效倍率高的）",
    reasonDupPriority: "与「{0}」同属互斥键 {1}（applyHighest）：按 categoryPriority 取数值小的那份（{2} 优先于 {3}），本条被压掉",
    noteCopiesSingle: "装了 {0} 份：同一 spEffectId 多份只算一份（stackingRules：只有按 ID 互斥的 stackSelf 才各份相乘）",
    noteCopiesStackSelf: "stackSelf：{0} 份各自相乘（stackingRules 第 2 条，参数推断，未实测）",
    // 叠层 / 累积阶梯 / 多档
    stackLabel: "层数",
    stackLabelCopies: "份数",
    stackHintGrace: "本局新发现的赐福数",
    stackHintLadder: "阶梯：第 n 层取 tierMultipliers[n-1]，参数表共 {0} 层，各层互斥只取当前层",
    stackHintCopies: "每份 ×{0}，N 份按 ×{0}^N 相乘（参数表无上限）",
    stackHintPractical: "一局实际最多 {0} 层，可以填更多但会提示",
    stackHintLabel: "游戏文本备有『＋1』到『＋{0}』的标签",
    stackOverPractical: "填了 {0} 层，超过一局实际能叠到的 {1} 层（{2}）",
    stackOverParam: "参数表只有 {0} 层，按第 {0} 层计算",
    stackOverCeiling: "份数按上限 {0} 计算",
    stackOverLabel: "游戏文本只备到＋{0}，更多层数按同一倍率外推（未实测）",
    tierSelectLabel: "层",
    tierLabel: "第 {0} 层",
    tierLabelThreshold: "第 {0} 层（累积 {1}）",
    tierNone: "不计",
    ladderTierCount: "共 {0} 层，选中后选层",
    variantLabel: "档",
    variantOption: "第 {0} 档{1}",
    variantRates: "（{0}）",
    variantNoMapping: "参数里查不到「出击武器类别 → 档位」的映射（词条只有一个按武器派发的行，没有任何列指向这几档），默认按第 1 档计算，请按出击武器自行选档",
    // 武器词条栏
    waIntro: "局内捡到的武器随机带的词条；{0} 把武器的词条全局生效。按对当前输出的有效倍率排序",
    waUsage: "已用 {0} / {1}",
    waDeepOnlyUsage: "深夜专属 {0} / {1}",
    waFilterWeapon: "当前武器类别（{0}）",
    waFilterAll: "全部类别",
    waFilterNone: "当前输出没有武器类别，显示全部",
    waFilterAria: "武器类别过滤",
    waSearch: "搜索武器词条",
    waCapReached: "已达上限",
    waDeepOnlyCapReached: "深夜专属已达上限",
    waNotInMode: "常规模式没有这条（只出现在深夜诅咒武器上）",
    waCopiesHint: "同一条词条装多份：按 ID 互斥的 stackSelf 各份相乘，其余只算一份（stackingRules 第 2 条，参数推断，未实测）",
    waTierHint: "同一词条的不同档位各自一个互斥键，按相乘计算（参数推断，未实测）",
    waEmpty: "当前筛选下没有能增伤的武器词条",
    stepperAria: "数量",
    stepDown: "减少",
    stepUp: "增加",
    // 遗物栏
    relicIntro: "常规 {0} 个普通遗物格；深夜另加 {1} 个深夜遗物格。每格二选一：官方固定词条遗物整件选入，或按词条检查页的规则自组不超过 3 条（普通遗物用「普通 1.03」口径，深夜遗物用「深夜正面」口径＋诅咒配对，实时检查合法性）",
    relicTypeAria: "遗物来源",
    relicType: { empty: "空", fixed: "固定遗物", custom: "自组" },
    relicCardNormal: "普通遗物 {0}",
    relicCardDeep: "深夜遗物 {0}",
    relicStatus: { empty: "空", fixed: "固定遗物", partial: "预检通过", valid: "合法", invalid: "不合法" },
    relicEmpty: "未选择词条",
    relicFixedValid: "官方固定词条遗物：整件按数据的 spEffectIds 计入，非增伤词条只显示",
    relicPartial: "预检通过：已选 {0} 条，其余 {1} 条可填任意不增伤、不冲突的合法词条",
    relicValidNormal: "合法：三条词条按「普通 1.03」口径通过",
    relicValidDeep: "合法：正面词条按「深夜正面」口径通过，诅咒配对已逐行校验",
    relicInvalid: "该遗物组合不合法",
    relicNoCatalog: "词条库未载入，无法自组遗物",
    relicUnknownEffectTitle: "存在未知词条 ID",
    relicUnknownEffectDetail: "以下词条 ID 不在词条索引中：{0}",
    relicUnnamedEffect: "词条 #{0}",
    relicPlaceholderAffix: "其余不增伤词条",
    // 正面词条的检查（Core.check / LegalityChecker 判不合法时按问题类型改用这几句）
    checkDuplicateTitle: "词条重复",
    checkDuplicateDetail: "同一个效果不能在一件遗物上出现两次：{0}",
    checkConflictTitle: "同一互斥池",
    checkConflictDetail: "{0} 不能同时出现",
    checkTemplateTitle: "不符合当前槽池模板",
    checkTemplateDetail: "{0} 无法分配到任一合法三词条槽模板",
    checkPoolTitle: "不在当前出货池",
    checkPoolDetail: "{0} 不在当前校验模式的候选词条池",
    // 深夜诅咒配对（与存档检查的深夜遗物审计 auditRelic / RelicAudit 同文）
    curseMissingTitle: "需诅咒的词条缺少负面词条",
    curseMissingDetail: "第 {0} 行的正面词条需要配对负面词条：{1}",
    curseUnexpectedTitle: "多余的负面词条",
    curseUnexpectedDetail: "第 {0} 行的正面词条不需要负面词条，却携带负面词条：{1}",
    curseMismatchTitle: "负面词条不在诅咒池",
    curseMismatchDetail: "第 {0} 行的负面词条不在诅咒池：{1}",
    curseDuplicateTitle: "词条重复",
    curseDuplicateDetail: "同一词条在一件遗物上重复出现：{0}",
    curseConflictTitle: "互斥词条同时出现",
    curseConflictDetail: "同一互斥池的词条不能同时出现：{0}",
    cursePairingTitle: "诅咒配对已校验",
    cursePairingDetail: "已按存档检查的深夜遗物审计规则逐行核对：需要诅咒的词条各配一条诅咒池（{0}）里的诅咒，不需要的不带；自组遗物按 3 格计，不涉及具体遗物 ID",
    relicFixedPlaceholder: "选择官方固定词条遗物…",
    relicFixedNone: "数据未内置深夜固定遗物，深夜遗物格只能自组",
    relicFixedUsedElsewhere: "（已在别的遗物格）",
    relicFixedSubtitle: "{0}色 · 遗物 #{1}",
    relicColors: { 0: "红", 1: "蓝", 2: "黄", 3: "绿", 4: "白" },
    relicRowLabel: "词条 {0}",
    relicAffixEmpty: "（空）",
    relicPickAffix: "选择词条…",
    relicCurseLabel: "诅咒（不计增伤，但要占位）",
    relicCursePlaceholder: "（未选诅咒）",
    relicCurseNote: "诅咒只占位，不计增伤",
    relicEffectsLabel: "词条",
    relicCountedLabel: "计入情况（非增伤词条只显示不计入）",
    relicNonDamage: "不计增伤",
    relicSearch: "搜索词条名称、分类或 ID",
    relicFixedSearch: "搜索固定遗物名称或词条",
    relicCurseSearch: "搜索诅咒",
    relicAffixPickerHint: "按对当前输出的有效倍率排序；红字＝选上后这件遗物不合法的原因",
    pickerDone: "完成",
    relicRemove: "移除",
    cardControlsHint: "条件型效果请在下方勾选「条件成立」；叠层效果在这里填层数、累积阶梯在这里选层、按武器类别取一档的词条在这里选档",
    optionInactive: "（不生效）",
    optionScore: "（{0}）",
    optionPotential: "（{0}，条件成立时 {1}）",
    // 护符栏
    accIntro: "最多 {0} 个，同一护符不能装两个（护符格数来自游戏文本与用户说明，参数表没有字段）",
    accSlotLabel: "护符 {0}",
    accPlaceholder: "选择护符…",
    accUsedElsewhere: "（已装备）",
    accFull: "护符已满",
    accRemove: "移除",
    accEffectCount: "{0} 条效果",
    // 其它栏
    otherIntro: "不占槽位，按需勾选；勾选即视为条件成立，叠层类勾选后先填一局实际上限、累积阶梯先选最高层（都可以改）",
    otherAutoInnate: "当前武器固有，自动列入",
    otherInnateHint: "当前武器的固有效果自动列入（取消勾选可排除）：被动的直接计入；条件型默认不计入，要勾选「条件成立」；叠层类默认 0 层，要填层数",
    otherInnateNoWeapon: "魔法与祷告没有出手武器，这里只有需手动勾选的固有效果",
    // 道具等级（buffs v6 的 goodsLevel）：「道具」分栏里 goodsLevel ≥ 2 的行在名字旁标 tag（悬停看 hint），
    // 分栏说明区给 note。三端同名同值（macOS LoadoutText.table / 安卓文案表）。
    goodsLevel: {
      tag: "携物知识 {0} 级",
      hint: "学者的能力「携物知识」把道具提升到这一级后才有这条效果；其它角色只有 1 级。",
      note: "道具的 2／3 级效果来自学者的能力「携物知识」，未升级的道具只有 1 级效果。"
    },
    otherSearch: "搜索增益名称、来源或 SpEffect 行号",
    otherEmpty: "这一组里没有能增伤的条目",
    selectUse: "选用",
    innateRemove: "不计入",
    innateRestore: "计入",
    // 汇总
    summaryHeading: "汇总",
    summaryColumnNote: "总倍率＝按互斥键去重后逐伤害类型连乘，再按伤害构成占比加权；各栏小计只算本栏（同法），不一定相乘等于总倍率",
    summaryTotal: "总倍率",
    summaryGain: "相对提升",
    summaryFlat: "另有攻击力加算",
    summaryFlatNote: "攻击力加算（点数）没有绝对攻击力就折不成倍率，只按占比加权展示，不进连乘",
    summaryNoComposition: "先勾选至少一段带伤害的命中，才能计算倍率",
    summaryEmpty: "还没有放入任何增益。可以在下面各栏里挑选，或点「按推荐填满」。",
    summaryCounted: "当前生效条目（{0}）",
    summaryUncounted: "选了但未计入（{0} 条）",
    summarySubtotals: "各栏小计（本栏单独计算）",
    summaryCount: "{0} 条",
    summaryHiddenNo: "另有 {0} 条对当前输出不生效（打开「{1}」查看原因）。",
    summaryTick: "条件成立",
    summaryTickHelp: "条件型：勾上表示你确认这个条件在出手时成立，才计入总倍率",
    summaryRemove: "移除",
    summaryContribution: "贡献",
    usageWeaponAffix: "武器词条",
    usageDeepOnly: "深夜专属",
    usageRelic: "遗物",
    usageAccessory: "护符",
    flatInline: "攻击力 {0}",
    potentialText: "条件成立时 {0}",
    potentialOneStack: "条件成立时（未设上限，按 1 层）{0}",
    detailActivation: "发动条件",
    detailStatus: "状态",
    detailKey: "互斥键",
    detailDesc: "说明",
    // 提示与超限
    warnDuplicateKey: "互斥键 {0}：{1} 份只计 1 份（{2}）",
    warnPriority: "互斥键 {0}（applyHighest）：按 categoryPriority 取数值小的「{1}」，压掉 {2}",
    warnCopiesSingle: "同一效果装了多份，按数据 stackingRules 只算一份（只有按 ID 互斥的 stackSelf 才各份相乘）：{0}",
    warnCopiesStackSelf: "同一效果装了多份，按 stackSelf 各份相乘（stackingRules 第 2 条，参数推断，未实测）：{0}",
    warnTiers: "「{0}」的不同档位同时计入（{1}），各自独立相乘：参数推断，未实测",
    warnLadders: "不同叠层阶梯同时生效（{0}）：各阶梯 categoryPriority 不同、按参数结构判为互不顶替、结果相乘，未实测",
    warnExclusivity: "「{0}」同属遗物互斥组 exclusivityId={1}：按参数推断分装在不同遗物上时只有一条生效，本页仍分别计入（未实测）",
    warnFixedDuplicate: "同一件固定遗物只能装备一件：{0}",
    violationWeaponAffix: "局内武器词条 {0} 条，超过{1}上限 {2} 条",
    violationDeepOnlyInNormal: "常规模式没有深夜专属词条（当前选了 {0} 条）",
    violationDeepOnly: "深夜专属正面词条 {0} 条，超过上限 {1} 条（每把武器最多 1 条）",
    violationAccessory: "护符 {0} 个，超过上限 {1} 个",
    violationAccessoryDuplicate: "同一护符不能装两个",
    violationRelic: "{0}：{1}",
    // 全部增益一览
    overviewTitle: "全部增益一览",
    overviewPill: "查阅用",
    overviewSearch: "搜索增益名称、来源或 Paramdex 行名",
    overviewCount: "共 {0} 条（每条单独按「条件全部成立」算：叠层取一局实际上限、没有上限的按 1 层，累积阶梯与多档词条按每一层／每一档自己算；未去重、未连乘，只供查阅）。",
    overviewMore: "再显示 {0} 条（剩余 {1} 条）",
    overviewNoMatch: "没有匹配的条目",
    overviewPage: "第 {0} / {1} 页 · 每页 {2} 条",
    overviewPrev: "上一页",
    overviewNext: "下一页",
    overviewOneStack: "按 1 层",
    overviewOneStackHelp: "叠层条目没有实际上限（practicalMaxStacks／uiLabelMax 都没有），一览只按 1 层算；在栏里填层数后按实际层数",
    // 口径说明
    briefHeading: "口径说明",
    briefIntro: "数据集 notes.ranking / stackingRules / notes.userQuestions 的结论简述",
    questionsTitle: "数据集的问答（notes.userQuestions，{0} 条）",
    briefStack: {
      item: "{0}：{1}",
      ladder: "第 n 层取第 n 档（每层约 ×{0}），参数表 {1} 层",
      practical: "，一局实际上限 {0} 层（×{1}）",
      copies: "每份 ×{0}、N 份按 N 次方相乘，参数表无上限",
      unit: "（层数＝{0}）",
      separator: "；"
    },
    brief: {
      appliesTo: "生效判定一律按数据的 appliesTo：战技（含战技射出的子弹段）看 skill、魔法看 sorcery、祷告看 incantation。conditional 的机读条件里，持武器的手、出手武器类别（法术按施法器：魔法＝手杖、祷告＝圣印记）、物理攻击类型按当前输出自动判定；子类别按 attackIndex 对所选战技／法术判定；攻击情境用上方的情境勾选；附魔武器限定、需同时使用道具等无法自动判定的要手动确认。",
      formula: "总倍率＝按互斥键去重后，全部计入条目在每个伤害类型上的倍率连乘，再按伤害构成占比加权；攻击力倍率层与最终伤害倍率层相乘，物理子类型倍率只乘对应那一部分；各栏小计同法只算本栏；攻击力加算（点数）只展示、不进连乘。",
      partial: "子类别只有部分段命中（requires.subCategoriesAny）时按近似加权：每个伤害类型取 1＋(倍率−1)×命中段占比，占比＝attackIndex 里所选战技／法术带该子类别的段数÷总段数；attackIndex 只给整招各子类别组合的段数、没有逐段对应，所以占比不随上方的分段勾选变化。",
      direction: "减益不计入：direction=decrease 的 {0} 条（附加异常时的武器伤害惩罚、降低敌人攻击力等）按 notes.ranking 第②步一律不进乘积；mixed（有增有减，例如附加属性时物理减、属性加）照常计入。",
      target: "作用对象按 notes.ranking 第①步只保留 self 与 ally（ally＝自己与／或附近队友）；同一战技成对的 Self／Allies 两行（selfAllyPair）算施放者自己时只计 Self 那一行，Allies 那一行只在队友施放时计入。",
      activation: "activation 不是 passive 的条目（条件型／发动型）与需要手动确认的条件，默认不计入：占槽位的栏（武器词条、遗物、护符、当前武器固有）放进来≠条件成立，要单独勾选「条件成立」；不占槽位的「其它增益」栏里勾选本身就是确认；叠层填层数、累积阶梯选层同样算确认。",
      stacking: "叠加按 stacking.exclusiveKey：同键只计一份（applyHighest 按 categoryPriority 取数值小的，其余取有效倍率高的，再相同取 spEffectId 小的），不同键相乘。同一个 spEffectId 从多处各拿一份时，spCategory=10（stackSelf）且按 ID 互斥的各份相乘，其余只算一份（多档词条同一词条装两件也只算一份）——都是按 SpEffectParam 参数结构推断，未经木桩实测（stackingRules）。",
      affixVariant: "同一遗物词条下挂多档的（数据 affixVariant，{0} 组 {1} 条，例如「出击时的武器，附加…」的 4 档）：游戏按出击武器的类别只生效一档、不能相乘；参数里查不到武器类别到档位的映射，本页默认按第 1 档计算，让你按出击武器选档。",
      tiers: "同一词条的不同档位（＋1／＋2、档位1／2／3）是不同的 SpEffect、各有自己的互斥键，本页按相乘计算——参数推断，未实测。",
      deepWeapon: "深夜诅咒武器每把 2 条正面词条，其中深夜专属正面词条最多 1 条（6 把最多 {0} 条，按 weaponAffixDeepOnlyPositive 计数）；负面诅咒另按每把 1 条算，不占这个名额，也不计增伤。同一把武器的两条正面词条能否相同（或同一词条的不同档位），参数表里查不到（duplicateWithinWeapon.status={1}），本页只校验总数与深夜专属上限，不按把分配。",
      relic: "遗物：普通遗物按「普通 1.03」口径（三条不重复、compatibilityId 两两不同、能分配到槽池模板）；深夜遗物按「深夜正面」口径，并要求 requiresCurse 的词条各配一条负面诅咒池（{0}）里的诅咒（与存档检查的深夜遗物审计同一规则、同一文案）。不足三条时用可落任一槽池、不参与互斥的占位词条补足后再检查。官方固定遗物整件计入；随整件带进来的条件型效果要手动确认。",
      skillAttack: "「提升战技攻击力」类（子类别 {0}）只作用于战技（含战技的子弹段），不作用于法术与普通攻击；法术吃到的「提升攻击力（XX・战技）」是战技发动后给自己的全伤害增益（sourceSlot=weaponSkill），名字里的「战技」是来源（notes.userQuestions.Q1）。",
      equipped: "「装备三把以上类别为 X 的武器」判的是装备中的数量，与出手的武器无关，对战技与法术都生效；「提升 X 的攻击力」只对用 X 发动的攻击生效（notes.userQuestions.Q3）。",
      innate: "当前武器的固有效果自动列入「其它增益 · 武器固有」：被动的直接计入；条件型默认不计入，要勾选「条件成立」；叠层类默认 0 层，要填层数（notes.ranking 第③步：自动带入不算用户确认）。其它武器的固有效果可以手动勾选。",
      runStack: "叠层：{0}。同一阶梯各层互斥、只取当前层；不同阶梯（封印监牢、黑夜入侵者等）按 categoryPriority 判为互不顶替、可以同时生效——参数推断，未实测。",
      fill: "「按推荐填满」只填空着的槽位，顺序是武器词条 → 遗物逐格（最好的固定遗物与贪心自组的合法遗物比较，分数相同取固定遗物）→ 护符；每一步都按「加进去之后的总倍率」取增幅最大的候选，增幅相同取 ID 小的；只算不用确认、不用填层数或选层就会计入的条目，不选条件型。",
      throwInferred: "appliesTo 对致命一击（throw）的判定是推断，而且与 Paramdex 对 throwAttackParamChange 的字面说明相反（notes.appliesTo）；本页的输出只有战技与法术，不涉及致命一击。"
    }
  };

  function fmt(template) {
    var args = Array.prototype.slice.call(arguments, 1);
    return String(template == null ? "" : template).replace(/\{(\d+)\}/g, function (match, index) {
      var value = args[Number(index)];
      return value == null ? "" : String(value);
    });
  }

  // ============================================================== 纯计算层
  // 以下函数不碰 DOM，windows/tests/ranker*.test.mjs 直接 require 本文件测试。

  function emptyTypeMap(value) {
    var out = {};
    for (var i = 0; i < TYPE_KEYS.length; i += 1) out[TYPE_KEYS[i]] = value;
    return out;
  }

  function num(value) {
    var n = Number(value);
    return isFinite(n) ? n : 0;
  }

  function numOr(value, fallback) {
    return typeof value === "number" && isFinite(value) ? value : fallback;
  }

  // ---- 选段（usage.选段（必读））---------------------------------------

  // 本页按 skills schemaVersion 3 取段：weapons[].skillVariants（逐 (战技, 武器) 实解的动作套下标）、
  // skills[].weaponSources（固定 / 局内战技池）与按 TAE 核实过的 variants[].atkIds。旧数据缺这些字段，
  // 局内战技池的武器取不到段、不打出的段也没剔除，页面照样渲染但要提示结果不可信。
  var SKILLS_SCHEMA_MIN = 3;

  function skillsSchemaWarning(skillsData) {
    var version = skillsData ? skillsData.schemaVersion : null;
    if (num(version) >= SKILLS_SCHEMA_MIN) return "";
    return "战技数据是 schemaVersion " + (version == null ? "（缺失）" : version) + "：本页按 v" + SKILLS_SCHEMA_MIN +
      " 的 skillVariants / weaponSources / TAE 核实过的动作套取段，旧数据缺这些字段，结果不可信";
  }

  // 这把武器用这个战技时的 variants 下标：一律读 weapons[].skillVariants[战技 ID]（v3，覆盖武器
  // skillIds 里每个有命中段的战技，含局内战技池抽到的）。缺失时才回退旧的 skillVariant，而且只在这个战技
  // 就是武器的固定战技（swordArtsParamId）时——skillVariant 只指固定战技，拿去套池里抽到的战技会选错套。
  function variantIndexFor(skill, weapon) {
    if (!skill || !weapon) return -1;
    var map = weapon.skillVariants;
    if (map && typeof map === "object") {
      var own = map[String(skill.id)];
      if (typeof own === "number") return own;
    }
    if (typeof weapon.skillVariant === "number" && weapon.swordArtsParamId === skill.id) return weapon.skillVariant;
    return -1;
  }

  // 武器在这个战技里用的那一套动作。找不到下标 = 这把武器用这个战技没有命中段。
  function selectVariant(skill, weapon) {
    var variants = skill && Array.isArray(skill.variants) ? skill.variants : null;
    if (!variants || !variants.length) return null;
    var index = variantIndexFor(skill, weapon);
    if (index < 0 || index >= variants.length) return null;
    return variants[index] || null;
  }

  // 直接从 hits[] 取段时先剔掉 TAE 判定为永远打不出的段（hits[].notInvoked，v3）：它们不在任何
  // variants[].atkIds 里，只留在 hits[] 备查。法术不做 TAE 过滤，这一步对法术是空操作。
  function invokedHits(hits) {
    return (hits || []).filter(function (hit) { return hit && hit.notInvoked !== true; });
  }

  // 返回「这把武器实际会打出的段」。variants 存在时一律走 atkIds（页面只从 variants 取段），
  // 缺失才退回 ctx 单选（武器名 → 武器类别 → ctx 缺失），任何情况下都不取并集；回退路径直接读 hits[]，
  // 所以要再剔掉 notInvoked 与 noDamage 段。
  function selectHits(skill, weapon) {
    var hits = skill && Array.isArray(skill.hits) ? skill.hits : [];
    if (!hits.length) return [];
    var variants = skill && Array.isArray(skill.variants) ? skill.variants : [];
    if (variants.length) {
      var variant = selectVariant(skill, weapon);
      if (!variant || !Array.isArray(variant.atkIds)) return [];
      var wanted = {};
      variant.atkIds.forEach(function (id) { wanted[id] = true; });
      return hits.filter(function (hit) { return wanted[hit.atkId] === true; });
    }
    var pool = invokedHits(hits).filter(function (hit) { return hit.noDamage !== true; });
    var byWeapon = weapon && weapon.nameEn
      ? pool.filter(function (hit) { return hit.ctx === weapon.nameEn; })
      : [];
    if (byWeapon.length) return byWeapon;
    var byType = weapon && weapon.wepTypeEn
      ? pool.filter(function (hit) { return hit.ctx === weapon.wepTypeEn; })
      : [];
    if (byType.length) return byType;
    return pool.filter(function (hit) { return !hit.ctx; });
  }

  // 这一段在「使用专注值不足版本」开关的这一侧吗：noFp 与开关同侧；fpBoth 段（带 FP 与无 FP
  // 两侧动画都会打出，v3 按 TAE 标出）两侧都计。只看 noFp 会在专注值不足侧漏掉 fpBoth 段。
  function hitOnSide(hit, noFp) {
    if (!hit) return false;
    return hit.fpBoth === true || Boolean(hit.noFp) === Boolean(noFp);
  }

  // 分段列表工具条的三个动作，返回完整的 override 表（reset＝清空，退回默认规则）。
  // 「全选」只勾**当前这一侧**的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍；
  // 两侧共用的 fpBoth 段在哪一侧都勾上。
  function hitOverridesFor(hits, action, noFp) {
    var overrides = {};
    if (action === "reset") return overrides;
    (hits || []).forEach(function (hit) {
      if (!hit || hit.noDamage) return;
      overrides[hit.atkId] = action === "all" && hitOnSide(hit, noFp);
    });
    return overrides;
  }

  // ---- 伤害构成 --------------------------------------------------------

  // 这一段的物理攻击类型；253 / 252 要回查武器的 atkAttribute / atkAttribute2。
  function physicalTypeForHit(hit, weapon) {
    var attribute = hit && hit.attribute;
    if (attribute === "WeaponAtkAttribute") {
      return PHYS_BY_INDEX[weapon && weapon.atkAttribute] || "physNone";
    }
    if (attribute === "WeaponAtkAttribute2") {
      return PHYS_BY_INDEX[weapon && weapon.atkAttribute2] || "physNone";
    }
    return ATTRIBUTE_TO_TYPE[attribute] || "physNone";
  }

  // 只有法术段忽略 motion。usage「法术 / 子弹段」的结论是「motion 只在施法器该属性
  // attackBase 非 0 时才有意义」——法术走 weapon=null（attackBase 全 0）；战技的子弹段挂的是
  // 真武器（attackBase 非 0、motion 是真实动作值），照常乘。
  function usesMotion(hit, isSpell) {
    return !isSpell;
  }

  // 单段在各伤害类型上的相对数值（不含强化、补正，只做配比用）。
  function hitContribution(hit, weapon, isSpell) {
    var out = emptyTypeMap(0);
    if (!hit || hit.noDamage) return out;
    var base = (weapon && weapon.attackBase) || {};
    var motionOn = usesMotion(hit, isSpell);
    var physType = physicalTypeForHit(hit, weapon);
    for (var i = 0; i < ELEMENTS.length; i += 1) {
      var element = ELEMENTS[i];
      var attack = num(base[element]);
      var motion = motionOn ? num(hit.motion && hit.motion[element]) : 0;
      var flat = num(hit.flat && hit.flat[element]);
      var value = (attack * motion) / 100 + flat;
      // addBaseAtk 是「再加一份武器该属性攻击力」，与 motion 是两回事，不受 motion 开关影响。
      if (hit.addBaseAtk) value += attack;
      if (!(value > 0)) continue;
      out[element === "physical" ? physType : element] += value;
    }
    return out;
  }

  // 分段芯片的展示计划：只留「对当前武器真正有贡献」的属性（数据集没声明的那一项写 null）。
  // 不变量：**可见芯片的相对值之和 == 这一段的总量**（隐藏的那些本来就是 0）。
  // hidden 只数「motion 声明了但恒为 0」的属性，用来在行末补一句「其余属性该武器为 0」。
  function hitChipPlan(hit, weapon, isSpell) {
    if (!hit || hit.noDamage) return { chips: [], hidden: 0 };
    var motionOn = usesMotion(hit, isSpell);
    var physType = physicalTypeForHit(hit, weapon);
    var base = (weapon && weapon.attackBase) || {};
    var byType = {};
    var chips = [];
    var hidden = 0;
    for (var i = 0; i < ELEMENTS.length; i += 1) {
      var element = ELEMENTS[i];
      var attack = num(base[element]);
      var motion = motionOn && hit.motion && hit.motion[element] != null
        ? num(hit.motion[element])
        : null;
      var flat = hit.flat && hit.flat[element] != null ? num(hit.flat[element]) : null;
      var baseAttack = hit.addBaseAtk === true && attack > 0 ? attack : null;
      if (motion === null && flat === null && baseAttack === null) continue;
      var amount = (attack * (motion || 0)) / 100 + (flat || 0) + (baseAttack || 0);
      if (!(amount > 0)) {
        if (motion > 0) hidden += 1;
        continue;
      }
      var type = element === "physical" ? physType : element;
      var chip = byType[type];
      if (chip) {
        if (chip.motion === null) chip.motion = motion;
        if (flat !== null) chip.flat = (chip.flat || 0) + flat;
        if (baseAttack !== null) chip.baseAttack = (chip.baseAttack || 0) + baseAttack;
      } else {
        chip = { type: type, motion: motion, flat: flat, baseAttack: baseAttack };
        byType[type] = chip;
        chips.push(chip);
      }
    }
    return { chips: chips, hidden: hidden };
  }

  // 勾选中的段汇总成占比。total 是相对值，没有绝对意义。
  function composition(hits, weapon, isSpell) {
    var parts = emptyTypeMap(0);
    var total = 0;
    (hits || []).forEach(function (hit) {
      var one = hitContribution(hit, weapon, isSpell);
      TYPE_KEYS.forEach(function (key) {
        if (!one[key]) return;
        parts[key] += one[key];
        total += one[key];
      });
    });
    var shares = emptyTypeMap(0);
    if (total > 0) {
      TYPE_KEYS.forEach(function (key) { shares[key] = parts[key] / total; });
    }
    return { parts: parts, total: total, shares: shares, hasDamage: total > 0 };
  }

  // 单段削韧 = poise + 武器 poiseDamageBase × poiseMv / 100。
  function hitPoise(hit, weapon) {
    if (!hit) return 0;
    var base = num(weapon && weapon.poiseDamageBase);
    return num(hit.poise) + (base * num(hit.poiseMv)) / 100;
  }

  // 单段削精力（对格挡敌人精力条的削减）= stamina + 武器 staminaBase × staminaMv / 100。
  function hitStamina(hit, weapon) {
    if (!hit) return 0;
    var base = num(weapon && weapon.staminaBase);
    return num(hit.stamina) + (base * num(hit.staminaMv)) / 100;
  }

  // ---- 倍率字段表 ------------------------------------------------------

  // physicsAttackRate / physicsAttackPowerRate / physicsAttackPower → 前缀 + 作用层。
  function parseRateFieldKey(key) {
    var match = /^([a-z]+)Attack(PowerRate|Power|Rate)$/.exec(String(key || ""));
    if (!match) return null;
    var prefix = match[1];
    var tail = match[2];
    var types = null;
    if (RATE_PREFIX_ELEMENT[prefix]) types = TYPES_BY_ELEMENT[RATE_PREFIX_ELEMENT[prefix]];
    else if (RATE_PREFIX_PHYS[prefix]) types = [RATE_PREFIX_PHYS[prefix]];
    if (!types) return null;
    var layer = tail === "Rate" ? "damage" : (tail === "PowerRate" ? "attackPower" : "flat");
    return { prefix: prefix, layer: layer, types: types.slice() };
  }

  // 只收 countsAsDamage 的字段：multiplier 进乘积，flat 进加算，其余（weakness /
  // critical / stance / status / special / flag / economy）一律不参与伤害乘算。
  function rateFieldPlan(buffsData) {
    var fields = (buffsData && Array.isArray(buffsData.rateFields)) ? buffsData.rateFields : [];
    var plan = { multiplier: [], flat: [], byKey: {}, skipped: [], unmapped: [] };
    fields.forEach(function (field) {
      plan.byKey[field.key] = field;
      if (field.countsAsDamage !== true) { plan.skipped.push(field.key); return; }
      var parsed = parseRateFieldKey(field.key);
      if (!parsed) { plan.unmapped.push(field.key); return; }
      var entry = {
        key: field.key,
        zh: field.zh || field.key,
        layer: parsed.layer,
        types: parsed.types,
        fallback: typeof field.default === "number" ? field.default : (parsed.layer === "flat" ? 0 : 1)
      };
      if (field.valueKind === "multiplier" && parsed.layer !== "flat") plan.multiplier.push(entry);
      else if (field.valueKind === "flat" && parsed.layer === "flat") plan.flat.push(entry);
      else plan.unmapped.push(field.key);
    });
    return plan;
  }

  // 把一组 rates 折成「伤害类型 → 倍率」的 9 格表：只有 countsAsDamage 且 valueKind=multiplier
  // 的字段进乘积，取值必须是有限正数且不等于该字段的默认值（数据集只列非默认值）。
  // restrictedType 非空（requires.physicalType / scope.atkAttribute）时倍率只落在那一个物理通道上。
  function multiplierMap(rates, plan, used, restrictedType) {
    var table = emptyTypeMap(1);
    plan.multiplier.forEach(function (field) {
      var value = (rates || {})[field.key];
      if (typeof value !== "number" || !isFinite(value) || value <= 0 || value === field.fallback) return;
      var types = restrictedType
        ? field.types.filter(function (type) { return type === restrictedType; })
        : field.types;
      if (!types.length) return;
      if (used) used.push({ key: field.key, zh: field.zh, layer: field.layer, value: value, types: types.slice() });
      types.forEach(function (type) { table[type] *= value; });
    });
    return table;
  }

  function flatMap(rates, plan, used) {
    var table = emptyTypeMap(0);
    plan.flat.forEach(function (field) {
      var value = (rates || {})[field.key];
      if (typeof value !== "number" || !isFinite(value) || value === field.fallback) return;
      if (used) used.push({ key: field.key, zh: field.zh, value: value, types: field.types });
      field.types.forEach(function (type) { table[type] += value; });
    });
    return table;
  }

  // ---- 分组键与显示名 --------------------------------------------------

  // 同族＝Paramdex 行名去掉档位后缀后相同（[Item - Level 3] X → [Item] X，
  // [Weapon] X - Potency 2 → [Weapon] X，[Relic] X +3 → [Relic] X）。
  // 只用来提示「不同档位同时计入」，不参与去重（去重只看 exclusiveKey）。
  function familyKey(buff) {
    var name = buff && buff.paramName;
    if (!name) return "id#" + (buff && buff.spEffectId);
    var text = String(name);
    var bracket = /^\[([^\]]*)\]\s*(.*)$/.exec(text);
    if (bracket) text = "[" + bracket[1].split(" - ")[0].trim() + "] " + bracket[2];
    text = text.replace(/\s*-\s*(?:Potency|Level|Tier)\s*\d+\s*$/i, "");
    text = text.replace(/\s*\+\d+\s*$/, "");
    return text.trim() || ("id#" + buff.spEffectId);
  }

  // 同族提示里的名字：显示名去掉末尾的全角括注与「＋N」。
  function familyName(name) {
    return String(name || "").replace(/（[^（）]*）$/, "").replace(/\s*[＋+]\s*[0-9０-９]+$/, "");
  }

  function buffDisplayName(buff) {
    if (!buff) return "";
    return buff.displayNameZh || buff.nameZh || buff.displayNameEn || buff.nameEn ||
      buff.paramName || ("#" + buff.spEffectId);
  }

  // 道具等级标记（buffs v6 的 goodsLevel = 这一行要道具升到第几级才有，取最低那一级；缺省＝1 级）：
  // 2／3 级只来自学者的能力「携物知识」（notes.goodsLevel），名字旁标「携物知识 N 级」；1 级不标。
  // 参数可以是条目（indexBuff 的结果）或「其它增益」栏的一行（buildConfigIndex 的 otherRows）。
  function goodsLevelTag(item) {
    var level = item ? num(item.goodsLevel) : 0;
    return level >= 2 ? fmt(TEXT.goodsLevel.tag, level) : "";
  }

  // 「其它增益」某个分栏的道具等级说明：这一栏里有 goodsLevel ≥ 2 的行才给（本版本只有「道具」栏）。
  function goodsLevelNoteFor(cfgIndex, slot) {
    var rows = ((cfgIndex && cfgIndex.otherRows) || {})[slot] || [];
    return rows.some(function (row) { return goodsLevelTag(row) !== ""; }) ? TEXT.goodsLevel.note : "";
  }

  // exclusiveKey 缺失（v5 之前的数据）时退回 stacking.group，再退回 sp<cat>#<id>。
  function exclusiveKeyOf(buff) {
    var stacking = (buff && buff.stacking) || {};
    if (stacking.exclusiveKey) return String(stacking.exclusiveKey);
    if (stacking.group) return String(stacking.group);
    return "sp" + num(stacking.spCategory) + "#" + (buff && buff.spEffectId);
  }

  // 角色分组键：[Skill - Revenant] → Revenant。拿不到就归「其他角色」。
  function characterKey(buff) {
    var match = /^\[[^\]]*?-\s*([^\]]+?)\s*\]/.exec(String((buff && buff.paramName) || ""));
    return match ? match[1] : "";
  }

  function characterLabel(key) {
    if (!key) return TEXT.characterOther;
    return TEXT.characterNames[key] || key;
  }

  // ---- buff 索引（只建一次，选段变化时不重建）--------------------------

  function indexBuff(buff, plan) {
    var rates = (buff && buff.rates) || {};
    var stacking = (buff && buff.stacking) || {};
    var scope = (buff && buff.scope) || {};
    var scopeRestricted = typeof scope.atkAttribute === "number" ? (PHYS_BY_INDEX[scope.atkAttribute] || null) : null;
    var usedMultiplier = [];
    var usedFlat = [];
    var multiplier = multiplierMap(rates, plan, usedMultiplier, scopeRestricted);
    var flat = flatMap(rates, plan, usedFlat);
    var others = Object.keys(rates).filter(function (key) {
      var field = plan.byKey[key];
      return !field || field.countsAsDamage !== true;
    });
    var hasMultiplier = TYPE_KEYS.some(function (type) { return multiplier[type] !== 1; });
    var hasFlat = TYPE_KEYS.some(function (type) { return flat[type] !== 0; });
    var slot = buff.sourceSlot || "other";
    var slots = Array.isArray(buff.sourceSlots) && buff.sourceSlots.length ? buff.sourceSlots.slice() : [slot];
    var acc = buff.accumulatorLadder && typeof buff.accumulatorLadder === "object" ? buff.accumulatorLadder : null;
    var accIds = acc && Array.isArray(acc.tierSpEffectIds) ? acc.tierSpEffectIds.slice() : [];
    var inferred = ((buff && buff.sources) || []).some(function (source) { return source && source.inferred === true; });
    var variant = buff.affixVariant && typeof buff.affixVariant === "object" ? buff.affixVariant : null;
    var relicLinks = Array.isArray(buff.relicAffixes) ? buff.relicAffixes.filter(Boolean) : [];
    var pair = buff.selfAllyPair && typeof buff.selfAllyPair === "object" ? buff.selfAllyPair : null;
    var weaponTypes = scope.weaponTypes && typeof scope.weaponTypes === "object" ? scope.weaponTypes : null;
    var target = buff.target || "self";
    var direction = buff.direction || "increase";
    var countsAsDamage = hasMultiplier || hasFlat;
    return {
      id: buff.spEffectId,
      buff: buff,
      name: buffDisplayName(buff),
      paramName: buff.paramName || "",
      rates: rates,
      multiplier: multiplier,
      flat: flat,
      usedMultiplier: usedMultiplier,
      usedFlat: usedFlat,
      otherRateKeys: others,
      hasMultiplier: hasMultiplier,
      hasFlat: hasFlat,
      countsAsDamage: countsAsDamage,
      // 能进配置页各栏与一览的条目：带伤害倍率字段、作用于自己或队友、不是减益。
      listable: countsAsDamage && (target === "self" || target === "ally") && direction !== "decrease",
      target: target,
      activation: buff.activation || "conditional",
      direction: direction,
      duration: typeof buff.duration === "number" ? buff.duration : -1,
      slot: slot,
      slots: slots,
      appliesTo: buff.appliesTo && typeof buff.appliesTo === "object" ? buff.appliesTo : null,
      appliesToDetail: buff.appliesToDetail && typeof buff.appliesToDetail === "object" ? buff.appliesToDetail : {},
      key: exclusiveKeyOf(buff),
      exclusiveScope: stacking.exclusiveScope || "",
      behavior: stacking.spCategoryBehavior || "",
      // 同一 spEffectId 多份：stackSelf 且按 ID 互斥（exclusiveScope=perSpEffect）的各份相乘；多档词条
      // （exclusiveScope=affixVariant）同一词条装两件也只算一份（notes.affixVariant）。
      copiesMultiply: stacking.spCategoryBehavior === "stackSelf" &&
        (!stacking.exclusiveScope || stacking.exclusiveScope === "perSpEffect"),
      spCategory: num(stacking.spCategory),
      categoryPriority: num(stacking.categoryPriority),
      family: familyKey(buff),
      scopeRestricted: scopeRestricted,
      stackInput: buff.stackInput && typeof buff.stackInput === "object" ? buff.stackInput : null,
      accLadder: acc,
      ladderGroup: accIds.length ? accIds[0] : null,
      ladderTier: acc ? num(acc.tier) : 0,
      innate: buff.weaponInnate && typeof buff.weaponInnate === "object" ? buff.weaponInnate : null,
      // 同一遗物词条下的多档（数据 affixVariant）：variantMembers 由 indexBuffs 统一填（按档位排好序的整组）。
      variantGroup: variant ? String(variant.key || ("affix#" + variant.attachEffectId)) : null,
      variantTier: variant ? num(variant.variant) : 0,
      variantMembers: null,
      pairRole: pair && (pair.role === "self" || pair.role === "ally") ? pair.role : null,
      goodsIds: Array.isArray(buff.requiresGoodsIds) ? buff.requiresGoodsIds.slice() : [],
      // 道具等级（v6 的 goodsLevel，缺省＝1 级）：只用来标「携物知识 N 级」，不参与计算。
      goodsLevel: numOr(buff.goodsLevel, 1),
      equipped: weaponTypes && weaponTypes.mode === "equippedCount" ? weaponTypes : null,
      relicAttachIds: relicLinks.map(function (link) { return link.attachEffectId; }),
      exclusivityIds: relicLinks.filter(function (link) {
        return typeof link.exclusivityId === "number" && link.exclusivityId >= 0;
      }).map(function (link) { return link.exclusivityId; }),
      character: slot === "character" ? characterKey(buff) : "",
      inferred: inferred,
      selfInflictedStatus: buff && buff.selfInflictedStatus === true,
      searchText: [
        buff.displayNameZh, buff.nameZh, buff.displayNameEn, buff.nameEn, buff.suggestedNameZh,
        buff.paramName, buff.descZh,
        ((buff.sources || []).map(function (s) {
          return [s.nameZh, s.nameEn, s.effectNameZh, s.artsNameZh].join(" ");
        }).join(" ")),
        String(buff.spEffectId)
      ].join(" ").toLowerCase()
    };
  }

  // 当前输出类别下，数据里实际要求过的攻击情境（appliesTo[类别]=conditional 的
  // appliesToDetail[类别].requires.attackContexts），只统计能进计算的条目。顺序用固定表。
  function availableContexts(buffsData, entries, cls) {
    var labels = (buffsData && buffsData.enums && buffsData.enums.attackContext) || {};
    var mode = cls || "skill";
    var counts = {};
    (entries || []).forEach(function (entry) {
      if (!entry.listable || !entry.appliesTo || entry.appliesTo[mode] !== "conditional") return;
      var detail = entry.appliesToDetail[mode];
      var keys = detail && detail.requires && Array.isArray(detail.requires.attackContexts)
        ? detail.requires.attackContexts : [];
      keys.forEach(function (key) { counts[key] = (counts[key] || 0) + 1; });
    });
    return Object.keys(counts).sort(function (a, b) {
      var left = ATTACK_CONTEXT_ORDER.indexOf(a);
      var right = ATTACK_CONTEXT_ORDER.indexOf(b);
      if (left < 0) left = ATTACK_CONTEXT_ORDER.length;
      if (right < 0) right = ATTACK_CONTEXT_ORDER.length;
      if (left !== right) return left - right;
      return a < b ? -1 : (a > b ? 1 : 0);
    }).map(function (key) {
      var label = labels[key] || {};
      return { key: key, zh: label.zh || key, en: label.en || "", count: counts[key] };
    });
  }

  // 同一遗物词条下挂的多档（schema 复核三轮的 affixVariant：「出击时的武器，附加魔力／火／雷／圣属性攻击力」
  // 「…附加异常状态冻伤／中毒／出血」各 4 档）：游戏按出击武器的类别只生效一档，不能相乘。
  // 一律只读数据的 affixVariant（不再按 compatibilityId 或行名猜）。返回 { 组键 → 按档位排序的成员 }。
  function assignAffixVariants(entries) {
    var groups = {};
    entries.forEach(function (entry) {
      if (!entry.variantGroup) return;
      if (!groups[entry.variantGroup]) groups[entry.variantGroup] = [];
      groups[entry.variantGroup].push(entry);
    });
    Object.keys(groups).forEach(function (group) {
      var members = groups[group];
      members.sort(function (a, b) { return (a.variantTier || 0) - (b.variantTier || 0) || a.id - b.id; });
      members.forEach(function (entry) { entry.variantMembers = members; });
    });
    return groups;
  }

  function indexBuffs(buffsData) {
    var plan = rateFieldPlan(buffsData);
    var entries = ((buffsData && buffsData.buffs) || []).map(function (buff) {
      return indexBuff(buff, plan);
    });
    var variants = assignAffixVariants(entries);
    var byId = {};
    entries.forEach(function (entry) { byId[entry.id] = entry; });
    return { plan: plan, entries: entries, byId: byId, variants: variants, buffsData: buffsData || null };
  }

  // ---- 输出上下文 ------------------------------------------------------

  // 把「当前输出」折成判定用的只读对象。meansId 是战技 / 法术的 id（查 attackIndex 用）。
  function makeOutput(options, buffsData) {
    var opts = options || {};
    var shares = opts.shares || emptyTypeMap(0);
    var hasComposition = TYPE_KEYS.some(function (key) { return num(shares[key]) > 0; });
    var enums = (buffsData && buffsData.enums) || {};
    return {
      mode: opts.mode === "sorcery" || opts.mode === "incantation" ? opts.mode : "skill",
      meansId: opts.meansId == null ? null : opts.meansId,
      weapon: opts.weapon || null,
      hand: opts.hand === 2 ? 2 : 1,
      shares: shares,
      hasComposition: hasComposition,
      contexts: opts.contexts || {},
      attackIndex: (buffsData && buffsData.attackIndex) || null,
      wepTypeNames: enums.wepType || {},
      subCategoryNames: enums.atkSubCategory || {},
      contextNames: enums.attackContext || {},
      goodsNames: goodsNameIndex(buffsData)
    };
  }

  // requiresGoodsIds 的道具名：取 sources[].kind=goods 且 id 相同的中文名（缓存在数据对象上）。
  function goodsNameIndex(buffsData) {
    if (!buffsData || typeof buffsData !== "object") return {};
    if (buffsData.__rankerGoodsNames) return buffsData.__rankerGoodsNames;
    var names = {};
    (buffsData.buffs || []).forEach(function (buff) {
      (buff.sources || []).forEach(function (source) {
        if (!source || source.kind !== "goods" || source.id == null || !source.nameZh) return;
        if (!(source.id in names)) names[source.id] = source.nameZh;
      });
    });
    try {
      Object.defineProperty(buffsData, "__rankerGoodsNames", { value: names, enumerable: false });
    } catch (error) { /* 冻结的数据对象：不缓存 */ }
    return names;
  }

  // 当前输出的「出手武器类别」：战技＝所选武器的 wepType；魔法＝手杖；祷告＝圣印记。
  function outputWepType(out) {
    if (!out) return null;
    if (out.mode === "skill") {
      return out.weapon && typeof out.weapon.wepType === "number" ? out.weapon.wepType : null;
    }
    return CASTER_WEP_TYPE[out.mode] || null;
  }

  function wepTypeLabel(out, wepType) {
    var names = (out && out.wepTypeNames) || {};
    var one = names[String(wepType)];
    return one && one.zh ? one.zh : fmt(TEXT.wepTypeFallback, wepType);
  }

  function subCategoryLabel(out, subs) {
    var names = (out && out.subCategoryNames) || {};
    return "[" + (subs || []).map(function (sub) {
      var one = names[String(sub)];
      return sub + (one && one.zh ? " " + one.zh : "");
    }).join("、") + "]";
  }

  // attackIndex 对所选战技／法术的逐段判定：有交集的段数 / 总段数。拿不到返回 null。
  function subCategoryMatch(out, subs) {
    var idx = (out && out.attackIndex) || {};
    var table = out && out.mode === "skill" ? idx.skills : idx.spells;
    var one = table && out.meansId != null ? table[String(out.meansId)] : null;
    if (!one || !Array.isArray(one.subCategorySets)) return null;
    var matched = 0;
    var total = 0;
    one.subCategorySets.forEach(function (set) {
      var hits = num(set && set.hits);
      total += hits;
      var own = (set && set.subs) || [];
      if (own.some(function (sub) { return subs.indexOf(sub) !== -1; })) matched += hits;
    });
    if (!(total > 0)) return null;
    return { matched: matched, total: total };
  }

  // ---- appliesTo 判定（notes.appliesTo）--------------------------------

  // 返回 { value, state, reasons, needs, notes, weight, restrictedType, requirements }：
  //   state = yes（生效）/ no（不生效）/ context（要勾选攻击情境）/ pending（要用户确认）
  //   weight ∈ (0, 1]：subCategoriesAny 部分段命中时按段数加权（近似，见 brief.partial）
  //   restrictedType：requires.physicalType 时倍率只落在那一个物理通道
  //   requirements：逐项 {key, text, state: met / unmet / partial / needsUser}（详情展示用）
  function appliesVerdict(entry, out) {
    var cls = out && out.mode ? out.mode : "skill";
    var verdict = {
      value: "missing", state: "yes", reasons: [], needs: [], notes: [], weight: 1,
      restrictedType: null, requirements: [], contexts: []
    };
    var value = entry && entry.appliesTo ? entry.appliesTo[cls] : null;
    var detail = (entry && entry.appliesToDetail && entry.appliesToDetail[cls]) || {};
    verdict.value = value === "yes" || value === "no" || value === "conditional" ? value : (value ? "no" : "missing");
    function need(key, text) {
      verdict.needs.push(text);
      verdict.requirements.push({ key: key, text: text, state: "needsUser" });
    }
    if (value !== "yes" && value !== "conditional") {
      verdict.state = "no";
      verdict.reasons.push(detail.reason || (value ? TEXT.verdictNoFallback : TEXT.verdictMissing));
      return verdict;
    }
    if (entry && entry.goodsIds && entry.goodsIds.length) {
      need("goods", fmt(TEXT.requireGoods, entry.goodsIds.map(function (id) {
        return (out && out.goodsNames && out.goodsNames[id]) || fmt(TEXT.goodsFallback, id);
      }).join("／")));
    }
    if (value === "yes") {
      if (verdict.needs.length) verdict.state = "pending";
      return verdict;
    }
    var requires = detail.requires && typeof detail.requires === "object" ? detail.requires : {};
    var fails = [];
    var contexts = [];
    var known = 0;
    var clsZh = TEXT.outputClass[cls] || cls;
    REQUIRE_ORDER.forEach(function (key) {
      if (!(key in requires)) return;
      known += 1;
      var needValue = requires[key];
      var text;
      if (key === "hand") {
        text = fmt(TEXT.requireHand, TEXT.hand[needValue === 2 ? 2 : 1], TEXT.hand[out.hand === 2 ? 2 : 1]);
        var handOk = needValue === out.hand;
        verdict.requirements.push({ key: key, text: text, state: handOk ? "met" : "unmet" });
        if (!handOk) fails.push(text);
      } else if (key === "attackWeaponTypes") {
        var list = Array.isArray(needValue) ? needValue : [];
        var names = list.map(function (type) { return wepTypeLabel(out, type); }).join("／");
        var own = outputWepType(out);
        text = own === null ? fmt(TEXT.requireWepTypeNoWeapon, names) : fmt(TEXT.requireWepType, names, wepTypeLabel(out, own));
        var typeOk = own !== null && list.indexOf(own) !== -1;
        verdict.requirements.push({ key: key, text: text, state: typeOk ? "met" : "unmet" });
        if (!typeOk) fails.push(text);
      } else if (key === "physicalType") {
        var type = PHYS_BY_INDEX[needValue] || null;
        if (type) {
          verdict.restrictedType = type;
          var present = !out.hasComposition || num(out.shares[type]) > 0;
          text = fmt(present ? TEXT.requirePhysical : TEXT.requirePhysicalFail, TYPE_INFO[type].zh);
          verdict.requirements.push({ key: key, text: text, state: present ? "met" : "unmet" });
          if (!present) fails.push(text);
        } else {
          need(key, fmt(TEXT.requireUnknown, "physicalType=" + needValue));
        }
      } else if (key === "subCategoriesAny") {
        var subs = Array.isArray(needValue) ? needValue : [];
        var label = subCategoryLabel(out, subs);
        var match = subCategoryMatch(out, subs);
        if (!match) {
          need(key, fmt(TEXT.requireSubsUnknown, clsZh, label));
        } else if (match.matched === 0) {
          text = fmt(TEXT.requireSubsFail, clsZh, label);
          verdict.requirements.push({ key: key, text: text, state: "unmet" });
          fails.push(text);
        } else if (match.matched < match.total) {
          verdict.weight = match.matched / match.total;
          text = fmt(TEXT.requireSubsPartial, clsZh, match.matched, match.total, label);
          verdict.requirements.push({ key: key, text: text, state: "partial", share: verdict.weight });
          verdict.notes.push(text);
        } else {
          verdict.requirements.push({ key: key, text: fmt(TEXT.requireSubsAll, clsZh, match.total, label), state: "met" });
        }
      } else if (key === "attackContexts") {
        var wanted = Array.isArray(needValue) ? needValue : [];
        var contextNames = wanted.map(function (ctxKey) {
          var one = out.contextNames && out.contextNames[ctxKey];
          return one && one.zh ? one.zh : ctxKey;
        }).join("／");
        var picked = wanted.some(function (ctxKey) { return out.contexts && out.contexts[ctxKey] === true; });
        text = fmt(TEXT.requireContext, contextNames);
        verdict.requirements.push({ key: key, text: text, state: picked ? "met" : "unmet" });
        if (!picked) contexts = wanted.slice();
      } else if (key === "imbuedWeaponOnly") {
        if (needValue) need(key, TEXT.requireImbued);
      } else if (key === "attachedWeaponOnly") {
        if (needValue) need(key, TEXT.requireAttached);
      }
    });
    Object.keys(requires).sort().forEach(function (key) {
      if (REQUIRE_ORDER.indexOf(key) !== -1) return;
      known += 1;
      need("unknown-" + key, fmt(TEXT.requireUnknown, key));
    });
    if (!known) need("detail", fmt(TEXT.requireManual, detail.reason || ""));
    if (fails.length) {
      verdict.state = "no";
      verdict.reasons = fails.concat(detail.reason ? [detail.reason] : []);
      verdict.needs = [];
      verdict.weight = 1;
      verdict.notes = [];
      return verdict;
    }
    if (contexts.length) {
      verdict.state = "context";
      verdict.reasons = [fmt(TEXT.requireContext, contexts.map(function (key) {
        var one = out.contextNames && out.contextNames[key];
        return one && one.zh ? one.zh : key;
      }).join("／"))];
      verdict.contexts = contexts;
      return verdict;
    }
    if (verdict.needs.length) {
      verdict.state = "pending";
      verdict.reasons = detail.reason ? [detail.reason] : [];
    }
    return verdict;
  }

  // 生效判定的短标签（两端同一口径）：不生效 → 部分段生效 → 要确认 → 条件已满足 → 生效。
  function verdictLabel(entry, verdict) {
    if (verdict.state === "no" || verdict.state === "context") return TEXT.verdict.no;
    if (verdict.weight < 1) return TEXT.verdict.partial;
    if (verdict.needs.length || (entry && entry.activation !== "passive")) return TEXT.verdict.needsUser;
    if (verdict.value === "conditional") return TEXT.verdict.conditionalMet;
    return TEXT.verdict.yes;
  }

  // 发动条件的说明：发动型 / 条件型；「装备三把以上 X」写出数量与类别。
  function activationNote(entry, out) {
    if (!entry || entry.activation === "passive") return "";
    if (entry.activation === "activated") return TEXT.activationNeed.activated;
    if (entry.equipped) {
      var names = Array.isArray(entry.equipped.namesZh) && entry.equipped.namesZh.length
        ? entry.equipped.namesZh
        : (entry.equipped.wepTypes || []).map(function (type) { return wepTypeLabel(out, type); });
      return fmt(TEXT.activationNeed.equipped, typeof entry.equipped.count === "number" ? entry.equipped.count : 3, names.join("／"));
    }
    return TEXT.activationNeed.conditional;
  }

  // ---- 叠层 ------------------------------------------------------------

  var COPIES_CEILING = 99;

  // 层数上限：ladder 取参数表层数（与 tierMultipliers 长度取小），copies 参数表无上限，页面按 99 截断误输入。
  function stackParamMax(entry) {
    var si = entry && entry.stackInput;
    if (!si) return null;
    if (si.mode === "ladder") {
      var tiers = Array.isArray(si.tierMultipliers) ? si.tierMultipliers.length : 0;
      if (typeof si.paramMaxStacks === "number" && si.paramMaxStacks > 0) {
        return tiers > 0 ? Math.min(si.paramMaxStacks, tiers) : si.paramMaxStacks;
      }
      return Math.max(tiers, 1);
    }
    return COPIES_CEILING;
  }

  // 「一局实际能叠到」的上限：practicalMaxStacks，没有就退游戏文本备好的『＋N』标签数。
  function stackSoftMax(entry) {
    var si = entry && entry.stackInput;
    if (!si) return null;
    if (typeof si.practicalMaxStacks === "number" && si.practicalMaxStacks > 0) return si.practicalMaxStacks;
    if (typeof si.uiLabelMax === "number" && si.uiLabelMax > 0) return si.uiLabelMax;
    return null;
  }

  // 用户填的层数（缺省 0：叠层要用户自己填，填层数即视为条件成立）。
  function stacksFor(entry, config) {
    if (!entry || !entry.stackInput) return null;
    var value = config && config.stacks ? config.stacks[entry.id] : undefined;
    if (typeof value === "number" && isFinite(value)) return Math.max(0, Math.floor(value));
    return 0;
  }

  // 勾选不占槽位的叠层条目时预填的层数：一局实际上限（没有实测上限的填 1），不超过参数表层数。
  function defaultStacks(entry) {
    var si = entry && entry.stackInput;
    if (!si) return null;
    var practical = typeof si.practicalMaxStacks === "number" && si.practicalMaxStacks > 0 ? si.practicalMaxStacks : 1;
    return Math.min(practical, stackParamMax(entry));
  }

  // 层数的计数单位以游戏文本为准（notes.stackInput）：descZh 写着「新发现的赐福」的按赐福数提示。
  function isGraceStack(entry) {
    return Boolean(entry && entry.stackInput && /赐福/.test(String(entry.buff && entry.buff.descZh)));
  }

  // practicalMaxSource 的短来源（「实测」「用户反馈」…）：取第一个冒号／括号之前的部分。
  function practicalSourceLabel(entry) {
    var si = entry && entry.stackInput;
    return String((si && si.practicalMaxSource) || "").split(/[：:（(]/)[0];
  }

  function stackWarnings(entry, raw, stacks) {
    var si = entry && entry.stackInput;
    var out = [];
    if (!si || !(stacks > 0)) return out;
    if (typeof si.practicalMaxStacks === "number" && si.practicalMaxStacks > 0 && stacks > si.practicalMaxStacks) {
      out.push(fmt(TEXT.stackOverPractical, stacks, si.practicalMaxStacks, practicalSourceLabel(entry) || "practicalMaxStacks"));
    }
    var max = stackParamMax(entry);
    if (raw > max) out.push(fmt(si.mode === "ladder" ? TEXT.stackOverParam : TEXT.stackOverCeiling, max));
    if (si.mode !== "ladder" && typeof si.uiLabelMax === "number" && stacks > si.uiLabelMax) {
      out.push(fmt(TEXT.stackOverLabel, si.uiLabelMax));
    }
    return out;
  }

  // 叠层后的 rates：ladder 第 n 层取 tierMultipliers[n-1]（没有表时 perStackRatio^n），
  // copies 取 perStackMultiplier^n；都替换 appliesToRateKeys（缺失时退回 multiplierKey）。
  // stacks 已按 stackParamMax 截断；≤ 0 返回 null（不计入）。
  function stackedRates(entry, stacks) {
    var si = entry && entry.stackInput;
    var rates = (entry && entry.rates) || {};
    if (!si || stacks == null) return rates;
    var n = Math.floor(stacks);
    if (!(n > 0)) return null;
    var value = null;
    if (si.mode === "ladder") {
      var tiers = Array.isArray(si.tierMultipliers) ? si.tierMultipliers : [];
      if (tiers.length) value = tiers[Math.min(n, tiers.length) - 1];
      else if (typeof si.perStackRatio === "number" && si.perStackRatio > 0) value = Math.pow(si.perStackRatio, n);
    } else if (typeof si.perStackMultiplier === "number" && si.perStackMultiplier > 0) {
      value = Math.pow(si.perStackMultiplier, n);
    }
    if (typeof value !== "number" || !isFinite(value)) return rates;
    var keys = Array.isArray(si.appliesToRateKeys) && si.appliesToRateKeys.length
      ? si.appliesToRateKeys : (si.multiplierKey ? [si.multiplierKey] : []);
    var copy = {};
    Object.keys(rates).forEach(function (key) { copy[key] = rates[key]; });
    keys.forEach(function (key) { copy[key] = value; });
    return copy;
  }

  // 这一条在 9 个伤害类型上的倍率表与加算表。
  //   weight < 1（子类别只有部分段命中）：每个类型按 1 + (m − 1) × weight 近似，加算 × weight；
  //   copies > 1（stackSelf 多份）：再按份数乘方，加算 × 份数。
  function entryTables(entry, plan, restrictedType, weight, stacks, copies) {
    var rates = entry.stackInput ? stackedRates(entry, stacks) : entry.rates;
    if (rates === null) return { table: emptyTypeMap(1), flat: emptyTypeMap(0) };
    var table = multiplierMap(rates, plan, null, restrictedType || entry.scopeRestricted || null);
    var flat = flatMap(rates, plan, null);
    var w = typeof weight === "number" && weight >= 0 && weight < 1 ? weight : 1;
    var n = typeof copies === "number" && copies > 1 ? Math.floor(copies) : 1;
    TYPE_KEYS.forEach(function (type) {
      if (w < 1) {
        table[type] = 1 + (table[type] - 1) * w;
        flat[type] = flat[type] * w;
      }
      if (n > 1) {
        table[type] = Math.pow(table[type], n);
        flat[type] = flat[type] * n;
      }
    });
    return { table: table, flat: flat };
  }

  // 按当前构成加权：Σ 占比 × 表 / Σ 占比。没有构成时返回 null（算不出）。
  function weightedMultiplier(table, shares) {
    var sum = 0;
    var weight = 0;
    TYPE_KEYS.forEach(function (type) {
      var share = shares ? num(shares[type]) : 0;
      if (!share) return;
      weight += share;
      sum += share * table[type];
    });
    return weight > 0 ? sum / weight : null;
  }

  function weightedFlat(flat, shares) {
    var sum = 0;
    var weight = 0;
    TYPE_KEYS.forEach(function (type) {
      var share = shares ? num(shares[type]) : 0;
      if (!share) return;
      weight += share;
      sum += share * flat[type];
    });
    return weight > 0 ? sum / weight : 0;
  }

  function productTable(tables) {
    var out = emptyTypeMap(1);
    (tables || []).forEach(function (table) {
      TYPE_KEYS.forEach(function (type) { out[type] *= table[type]; });
    });
    return out;
  }

  // 单条有效倍率（对照测试用）：Σ 占比 × 该类型的倍率。
  function effectiveFor(entry, shares) {
    var m = weightedMultiplier(entry.multiplier, shares);
    if (m === null) return { multiplier: 1, flat: 0, useful: false };
    var f = weightedFlat(entry.flat, shares);
    return { multiplier: m, flat: f, useful: m > USEFUL_EPSILON || f > 0 };
  }

  // ---- 多档词条 / 累积阶梯的选择 ------------------------------------------

  // 同一遗物词条下的多档（affixVariant）：同一组只算选中的那一档；默认第 1 档（参数里没有按武器类别
  // 选档的列，只能让用户选）。config.variants：组键 → 选中那一档的 spEffectId。
  function selectedVariant(entry, config) {
    var members = (entry && entry.variantMembers) || [];
    var chosen = config && config.variants ? config.variants[entry.variantGroup] : undefined;
    var pick = null;
    members.forEach(function (member) { if (member.id === chosen) pick = member; });
    if (!pick && members.length) pick = members[0];
    if (!pick) pick = entry;
    var position = members.indexOf(pick);
    return { id: pick.id, tier: pick.variantTier || (position + 1) || 1, tiers: members.length || 1 };
  }

  // 累积阶梯（accumulatorLadder）：同一组只算选中的那一层；没选层就一层都不算（选层即确认）。
  // config.tiers：阶梯组 id（第 1 层的 spEffectId）→ 选中那一层的 spEffectId。
  function ladderMembers(ladders, groupId) {
    return (ladders && ladders[groupId]) || [];
  }

  function ladderTopTier(ladders, groupId) {
    var members = ladderMembers(ladders, groupId);
    return members.length ? members[members.length - 1] : null;
  }

  function selectedLadderTier(entry, config, ladders) {
    var members = ladderMembers(ladders, entry.ladderGroup);
    var chosen = config && config.tiers ? config.tiers[entry.ladderGroup] : undefined;
    var pick = null;
    members.forEach(function (member) { if (member.id === chosen) pick = member; });
    return { id: pick ? pick.id : null, tier: pick ? (pick.ladderTier || 1) : 0, tiers: members.length };
  }

  // ---- 单条评估 --------------------------------------------------------

  // env = { plan, out, config, ladders, strict, assumeAll, ownTier, ownVariant }
  //   strict：推荐口径——条件型、发动型、要确认的、叠层与累积阶梯一律不计入（不看用户的确认）；
  //   assumeAll：「条件全部成立」口径——要确认的都当成立，叠层取一局实际上限（没有就 1 层），
  //              累积阶梯取最高层；ownTier / ownVariant：累积阶梯与多档词条按这一条自己的层／档算（一览用）。
  // source = { column, copies, autoConfirm, auto, labels, keys }
  //   autoConfirm：不占槽位的「其它增益」栏里用户亲手勾选的——勾选即确认。
  // 判定顺序：不含伤害 → 多档只留选中的一档 → 作用对象（notes.ranking ①，含 selfAllyPair）→ 减益（②）
  //   → appliesTo → 累积阶梯选层 → 叠层层数 → 发动条件与手动确认（③）→ 份数 → 对当前构成有没有增益。
  function evaluateEntry(entry, env, source) {
    var config = env.config || {};
    var out = env.out;
    var src = source || {};
    var copies = typeof src.copies === "number" && src.copies > 1 ? Math.floor(src.copies) : 1;
    var verdict = appliesVerdict(entry, out);
    var raw = entry.stackInput ? stacksFor(entry, config) : null;
    var assumedOneStack = false;
    if (entry.stackInput && env.assumeAll) {
      var soft = stackSoftMax(entry);
      if (soft === null && !(raw > 0)) assumedOneStack = true;
      raw = Math.max(raw, Math.min(soft === null ? 1 : soft, stackParamMax(entry)));
    }
    var stacks = entry.stackInput ? Math.min(raw, stackParamMax(entry)) : null;
    var item = {
      entry: entry,
      column: src.column || "other",
      labels: (src.labels || []).slice(),
      keys: (src.keys || []).slice(),
      copies: copies,
      countedCopies: 1,
      autoConfirm: src.autoConfirm === true,
      auto: src.auto === true,
      verdict: verdict,
      label: verdictLabel(entry, verdict),
      activationNote: activationNote(entry, out),
      needs: [],
      ticked: false,
      stacks: stacks,
      stackWarnings: entry.stackInput ? stackWarnings(entry, raw, stacks) : [],
      assumedOneStack: assumedOneStack,
      tier: null,
      variant: null,
      state: "counted",
      reasons: [],
      notes: verdict.notes.slice(),
      table: emptyTypeMap(1),
      flatTable: emptyTypeMap(0),
      multiplier: null,
      flat: 0
    };
    function finish(state, reasons) {
      item.state = state;
      item.reasons = reasons || [];
      if (state !== "counted" && state !== "neutral") {
        // 不计入的也给出「单独看这一条」的倍率，列表展示用（不进汇总）。
        var probe = entryTables(entry, env.plan, verdict.restrictedType, verdict.weight, stacks, 1);
        item.table = probe.table;
        item.flatTable = probe.flat;
        item.multiplier = out && out.hasComposition ? weightedMultiplier(probe.table, out.shares) : null;
        item.flat = out && out.hasComposition ? weightedFlat(probe.flat, out.shares) : 0;
      }
      return item;
    }
    if (!entry.countsAsDamage) return finish("noDamage", [TEXT.reasonNoDamage]);
    if (entry.variantGroup) {
      var variant = env.ownVariant ? { id: entry.id, tier: entry.variantTier, tiers: (entry.variantMembers || []).length }
        : selectedVariant(entry, config);
      item.variant = variant;
      if (variant.id !== entry.id) {
        return finish("variantOff", [fmt(TEXT.reasonVariantOff, variant.tiers, variant.tier)]);
      }
    }
    if (entry.pairRole === "ally") return finish("no", [TEXT.reasonAllyPair]);
    if (entry.target !== "self" && entry.target !== "ally") return finish("no", [fmt(TEXT.reasonTarget, entry.target)]);
    if (entry.direction === "decrease") return finish("no", [TEXT.reasonDecrease]);
    if (verdict.state === "no") return finish("no", verdict.reasons);
    if (verdict.state === "context") return finish("context", verdict.reasons);
    var selectionConfirms = false;
    if (entry.accLadder) {
      var tier;
      if (env.ownTier) tier = { id: entry.id, tier: entry.ladderTier, tiers: ladderMembers(env.ladders, entry.ladderGroup).length };
      else if (env.assumeAll) {
        var top = ladderTopTier(env.ladders, entry.ladderGroup);
        tier = { id: top ? top.id : entry.id, tier: top ? top.ladderTier : entry.ladderTier, tiers: ladderMembers(env.ladders, entry.ladderGroup).length };
      } else tier = selectedLadderTier(entry, config, env.ladders);
      item.tier = tier;
      if (tier.id === null) return finish("tierOff", [TEXT.reasonTierNone]);
      if (tier.id !== entry.id) return finish("tierOff", [fmt(TEXT.reasonTierOff, tier.tier)]);
      selectionConfirms = true;
    }
    if (entry.stackInput) {
      if (!(stacks > 0)) return finish("zeroStacks", [TEXT.reasonZeroStacks]);
      selectionConfirms = true;
    }
    var needs = selectionConfirms ? [] : verdict.needs.slice();
    if (!selectionConfirms && item.activationNote) needs.unshift(item.activationNote);
    item.needs = needs;
    if (env.strict && (needs.length || selectionConfirms)) {
      return finish("pending", needs.length ? needs : [TEXT.fillNote]);
    }
    if (needs.length && !env.assumeAll) {
      item.ticked = Boolean(config.ticks && config.ticks[entry.id] === true) || item.autoConfirm;
      if (!item.ticked) return finish("pending", needs);
    }
    var countedCopies = 1;
    if (copies > 1) {
      if (entry.copiesMultiply) {
        countedCopies = copies;
        item.notes.push(fmt(TEXT.noteCopiesStackSelf, copies));
      } else {
        item.notes.push(fmt(TEXT.noteCopiesSingle, copies));
      }
    }
    item.countedCopies = countedCopies;
    item.notes = item.notes.concat(item.stackWarnings);
    var tables = entryTables(entry, env.plan, verdict.restrictedType, verdict.weight, stacks, countedCopies);
    item.table = tables.table;
    item.flatTable = tables.flat;
    item.multiplier = out && out.hasComposition ? weightedMultiplier(tables.table, out.shares) : null;
    item.flat = out && out.hasComposition ? weightedFlat(tables.flat, out.shares) : 0;
    if (out && out.hasComposition && Math.abs(item.multiplier - 1) <= EPSILON && item.flat <= EPSILON) {
      item.state = "neutral";
      item.reasons = [TEXT.reasonNeutral];
      return item;
    }
    item.state = "counted";
    item.reasons = [];
    return item;
  }

  // ---- 去重（stacking.exclusiveKey）------------------------------------

  // 同键谁留下：两边都是 applyHighest 且 categoryPriority 不同 → 数值小的；
  // 否则当前构成下有效倍率高的；再比加算；再比 spEffectId 小的；完全并列时先出现的留下。
  function prefersItem(candidate, current) {
    var a = candidate.entry;
    var b = current.entry;
    if (a.behavior === "applyHighest" && b.behavior === "applyHighest" &&
      a.categoryPriority !== b.categoryPriority) {
      return a.categoryPriority < b.categoryPriority;
    }
    var am = candidate.multiplier == null ? 1 : candidate.multiplier;
    var bm = current.multiplier == null ? 1 : current.multiplier;
    if (Math.abs(am - bm) > EPSILON) return am > bm;
    if (Math.abs((candidate.flat || 0) - (current.flat || 0)) > EPSILON) return candidate.flat > current.flat;
    if (a.id !== b.id) return a.id < b.id;
    return false;
  }

  function isPriorityWin(winner, loser) {
    return winner.entry.behavior === "applyHighest" && loser.entry.behavior === "applyHighest" &&
      winner.entry.categoryPriority !== loser.entry.categoryPriority;
  }

  function dedupeItems(items) {
    var winners = {};
    var order = [];
    items.forEach(function (item) {
      if (item.state !== "counted") return;
      var key = item.entry.key;
      if (!winners[key]) { winners[key] = item; order.push(key); return; }
      if (prefersItem(item, winners[key])) winners[key] = item;
    });
    items.forEach(function (item) {
      if (item.state !== "counted") return;
      var winner = winners[item.entry.key];
      if (winner === item) return;
      item.state = "duplicate";
      item.dupOf = winner;
      item.reasons = [isPriorityWin(winner, item)
        ? fmt(TEXT.reasonDupPriority, winner.entry.name, item.entry.key, winner.entry.categoryPriority, item.entry.categoryPriority)
        : fmt(TEXT.reasonDupKey, winner.entry.name, item.entry.key)];
    });
    return order.map(function (key) { return winners[key]; });
  }


  // ---- 槽位规则（slotRules）--------------------------------------------

  function slotCaps(slotRules, runMode) {
    var rules = slotRules || {};
    var wa = rules.weaponAffix || {};
    var modes = rules.modes || {};
    var relic = rules.relic || {};
    var acc = rules.accessory || {};
    var deep = runMode === "deep";
    var maxWeapons = numOr(wa.maxWeapons, 6);
    var mode = modes[deep ? "deep" : "normal"] || {};
    var affixCap = deep
      ? numOr(wa.maxAffixesDeep, maxWeapons * numOr(mode.weaponAffixesPerWeapon, 2))
      : numOr(wa.maxAffixesNormal, maxWeapons * numOr(mode.weaponAffixesPerWeapon, 1));
    var deepOnlyCap = deep
      ? numOr(wa.maxDeepOnlyAffixes, maxWeapons * numOr(mode.deepOnlyAffixesPerWeapon, numOr(wa.deepOnlyPerWeaponMax, 1)))
      : maxWeapons * numOr(mode.deepOnlyAffixesPerWeapon, 0);
    var relicNormal = numOr(relic.normal, 3);
    var relicDeep = deep ? numOr(relic.deepExtra, Math.max(0, numOr(mode.relicSlots, 6) - relicNormal)) : 0;
    return {
      runMode: deep ? "deep" : "normal",
      maxWeapons: maxWeapons,
      weaponAffix: affixCap,
      deepOnly: deepOnlyCap,
      relicNormal: relicNormal,
      relicDeep: relicDeep,
      relics: relicNormal + relicDeep,
      accessory: numOr(acc.slots, 2)
    };
  }

  // ---- 配置索引（只建一次；词条库变化时重建）----------------------------

  // 深夜遗物的负面词条池：词条库里只装诅咒词条的池（有多个时取成员最多、再取 ID 小的）。
  // 词条库里找不到这样的池就退回与 core.js 同值的兜底常量。
  function cursePoolOf(affixes) {
    var curseCount = {};
    var mixed = {};
    (affixes || []).forEach(function (affix) {
      (affix.poolIds || []).forEach(function (pool) {
        if (affix.isCurse === true) curseCount[pool] = (curseCount[pool] || 0) + 1;
        else mixed[pool] = true;
      });
    });
    var best = null;
    Object.keys(curseCount).forEach(function (pool) {
      if (mixed[pool]) return;
      if (best === null || curseCount[pool] > curseCount[best] ||
        (curseCount[pool] === curseCount[best] && Number(pool) < Number(best))) best = pool;
    });
    return best === null ? DEEP_CURSE_POOL_ID : Number(best);
  }

  // 词条库索引：effectId → 词条；诅咒池里的诅咒按 effectId 升序（配诅咒时 ID 小的先试）。
  function buildCatalogIndex(catalog) {
    var byId = new Map();
    var affixes = catalog && Array.isArray(catalog.affixes) ? catalog.affixes : [];
    affixes.forEach(function (affix) { byId.set(affix.effectId, affix); });
    var cursePoolId = cursePoolOf(affixes);
    var curses = affixes.filter(function (affix) {
      return affix.isCurse === true && (affix.poolIds || []).indexOf(cursePoolId) !== -1;
    }).sort(function (a, b) { return a.effectId - b.effectId; });
    return { available: affixes.length > 0, byId: byId, curses: curses, cursePoolId: cursePoolId, checkCache: new Map() };
  }

  function isCurseAffix(affix) {
    var roles = (affix && affix.roles) || [];
    return roles.indexOf("curse") !== -1 || (affix && affix.isDebuff === true);
  }

  // Core 可缺（测试里没有 DOM 也要能建索引）：自组遗物候选需要 Core.isEligible。
  function buildConfigIndex(buffsData, index, catalog, Core) {
    var idx = index || indexBuffs(buffsData);
    var byId = idx.byId || {};
    var entries = idx.entries || [];
    function listableOf(ids) {
      var seen = {};
      return (ids || []).map(function (id) { return byId[id]; }).filter(function (entry) {
        if (!entry || !entry.listable || seen[entry.id]) return false;
        seen[entry.id] = true;
        return true;
      });
    }

    // 累积阶梯：组 id → 按层数排序的成员
    var ladders = {};
    entries.forEach(function (entry) {
      if (entry.ladderGroup == null || !entry.listable) return;
      if (!ladders[entry.ladderGroup]) ladders[entry.ladderGroup] = [];
      ladders[entry.ladderGroup].push(entry);
    });
    Object.keys(ladders).forEach(function (key) {
      ladders[key].sort(function (a, b) { return a.ladderTier - b.ladderTier || a.id - b.id; });
    });

    // 局内武器词条（按 AttachEffect 升序列出；诅咒不进正面词条栏）
    var weaponAffixes = [];
    var weaponAffixById = {};
    ((buffsData && buffsData.weaponAffixes) || []).slice().sort(function (a, b) {
      return num(a && a.attachEffectId) - num(b && b.attachEffectId);
    }).forEach(function (raw) {
      if (!raw || isCurseAffix(raw)) return;
      var own = listableOf(raw.spEffectIds);
      if (!own.length) return;
      var deepOnlyPositive = raw.deepOnlyPositive === true || own.some(function (entry) {
        return entry.buff && entry.buff.weaponAffixDeepOnlyPositive === true;
      });
      var item = {
        id: raw.attachEffectId,
        nameZh: raw.nameZh || raw.nameEn || ("#" + raw.attachEffectId),
        paramName: raw.paramName || "",
        potency: typeof raw.potency === "number" ? raw.potency : null,
        roles: (raw.roles || []).slice(),
        normalWepTypes: (raw.normalWepTypes || []).slice(),
        // 深夜能出现的类别：deepWepTypes，缺失时退常规的类别表（两端同一口径）。
        deepWepTypes: (raw.deepWepTypes && raw.deepWepTypes.length ? raw.deepWepTypes : (raw.normalWepTypes || [])).slice(),
        deepOnly: raw.deepOnly === true,
        deepOnlyPositive: deepOnlyPositive,
        entries: own,
        search: [raw.nameZh, raw.nameEn, raw.paramName, raw.attachEffectId].join(" ").toLowerCase()
      };
      item.label = item.nameZh + (item.potency ? "（" + fmt(TEXT.badges.potency, item.potency) + "）" : "");
      weaponAffixes.push(item);
      weaponAffixById[item.id] = item;
    });

    // 官方固定词条遗物（按 relicIds[0] 升序）
    var fixedRelics = [];
    var fixedRelicByKey = {};
    ((buffsData && buffsData.fixedRelics) || []).slice().sort(function (a, b) {
      return num(((a && a.relicIds) || [])[0]) - num(((b && b.relicIds) || [])[0]);
    }).forEach(function (raw) {
      if (!raw) return;
      var key = (raw.relicIds || []).join("-") || raw.nameZh;
      var own = listableOf(raw.spEffectIds);
      var item = {
        key: key,
        relicIds: (raw.relicIds || []).slice(),
        nameZh: raw.nameZh || raw.nameEn || key,
        color: raw.color,
        isDeepRelic: raw.isDeepRelic === true,
        effectNames: (raw.attachEffectNamesZh || []).map(function (name, i) {
          return name || fmt(TEXT.relicUnnamedEffect, (raw.attachEffectIds || [])[i]);
        }),
        entries: own,
        hasDamage: own.length > 0
      };
      fixedRelics.push(item);
      fixedRelicByKey[key] = item;
    });

    // 遗物词条：词条库 effectId → 条目（只收能进计算的）
    var relicAffixEntries = new Map();
    entries.forEach(function (entry) {
      if (!entry.listable) return;
      ((entry.buff && entry.buff.relicAffixes) || []).forEach(function (link) {
        if (!link || link.catalogEffectId == null) return;
        if (!relicAffixEntries.has(link.catalogEffectId)) relicAffixEntries.set(link.catalogEffectId, []);
        var list = relicAffixEntries.get(link.catalogEffectId);
        if (list.indexOf(entry) === -1) list.push(entry);
      });
    });

    var catalogIndex = buildCatalogIndex(catalog);
    function relicCandidates(modeKey) {
      var list = [];
      if (!catalogIndex.available) return list;
      relicAffixEntries.forEach(function (own, effectId) {
        var affix = catalogIndex.byId.get(effectId);
        if (!affix || affix.isCurse || !own.length) return;
        if (Core && typeof Core.isEligible === "function" && !Core.isEligible(affix, modeKey)) return;
        list.push({ id: effectId, affix: affix, name: affix.name, entries: own });
      });
      list.sort(function (a, b) { return a.id - b.id; });
      return list;
    }

    // 护符：主槽位是 accessory 的条目按护符（sources[].kind=accessory 的 id）分组，按 id 升序
    var talismans = [];
    var talismanById = {};
    entries.forEach(function (entry) {
      if (!entry.listable || entry.slot !== "accessory") return;
      ((entry.buff && entry.buff.sources) || []).forEach(function (source) {
        if (!source || source.kind !== "accessory" || source.id == null) return;
        var one = talismanById[source.id];
        if (!one) {
          one = { id: source.id, nameZh: source.nameZh || source.nameEn || ("#" + source.id), entries: [] };
          talismanById[source.id] = one;
          talismans.push(one);
        }
        if (one.entries.indexOf(entry) === -1) one.entries.push(entry);
      });
    });
    talismans.sort(function (a, b) { return a.id - b.id; });

    // 其它增益：按主槽位分组；累积阶梯合成一行（行键＝阶梯第 1 层 id）
    var otherRows = {};
    OTHER_SLOTS.forEach(function (slot) { otherRows[slot] = []; });
    var seenLadder = {};
    entries.forEach(function (entry) {
      if (!entry.listable) return;
      if (OTHER_SLOTS.indexOf(entry.slot) === -1) return;
      if (entry.ladderGroup != null) {
        if (seenLadder[entry.ladderGroup]) return;
        seenLadder[entry.ladderGroup] = true;
        var members = ladders[entry.ladderGroup] || [entry];
        otherRows[entry.slot].push({
          key: members[0].id, entries: members, ladder: true,
          name: members[0].name.replace(/（第\d+[层档]）$/, ""), character: entry.character,
          goodsLevel: members[0].goodsLevel
        });
        return;
      }
      otherRows[entry.slot].push({
        key: entry.id, entries: [entry], ladder: false, name: entry.name, character: entry.character,
        goodsLevel: entry.goodsLevel
      });
    });

    return {
      plan: idx.plan,
      index: idx,
      byId: byId,
      buffsData: buffsData || null,
      slotRules: (buffsData && buffsData.slotRules) || {},
      ladders: ladders,
      weaponAffixes: weaponAffixes,
      weaponAffixById: weaponAffixById,
      fixedRelics: fixedRelics,
      fixedRelicByKey: fixedRelicByKey,
      relicAffixEntries: relicAffixEntries,
      catalog: catalogIndex,
      relicCandidates: { normal: relicCandidates("currentNormal"), deep: relicCandidates("deepPositive") },
      talismans: talismans,
      talismanById: talismanById,
      otherRows: otherRows,
      Core: Core || null
    };
  }

  // ---- 配置（用户组的一套）----------------------------------------------

  function emptyRelicCard() {
    return { type: "empty", key: null, affixIds: [null, null, null], curseIds: [null, null, null] };
  }

  function emptyConfig() {
    return {
      runMode: "normal",
      weaponAffixes: [],        // [{ id: attachEffectId, count }]，按加入顺序（计算时一律按 id 升序）
      relics: [emptyRelicCard(), emptyRelicCard(), emptyRelicCard(), emptyRelicCard(), emptyRelicCard(), emptyRelicCard()],
      accessories: [null, null],
      others: {},               // 行键（spEffectId / 阶梯第 1 层 id）→ true
      innateOff: {},            // 当前武器固有里被用户排除的 spEffectId
      ticks: {},                // spEffectId → true（勾了「条件成立」）
      stacks: {},               // spEffectId → 层数（缺省 0）
      tiers: {},                // 累积阶梯组 id → 选中的那一层 spEffectId（缺省＝不计）
      variants: {}              // 多档词条组键（affix#…）→ 选中的那一档 spEffectId（缺省＝第 1 档）
    };
  }

  function cloneConfig(config) {
    var src = config || emptyConfig();
    function copyMap(map) {
      var out = {};
      Object.keys(map || {}).forEach(function (key) { out[key] = map[key]; });
      return out;
    }
    return {
      runMode: src.runMode === "deep" ? "deep" : "normal",
      weaponAffixes: (src.weaponAffixes || []).map(function (one) { return { id: one.id, count: one.count }; }),
      relics: (src.relics || []).map(function (card) {
        return {
          type: card.type, key: card.key,
          affixIds: (card.affixIds || [null, null, null]).slice(),
          curseIds: (card.curseIds || [null, null, null]).slice()
        };
      }),
      accessories: (src.accessories || [null, null]).slice(),
      others: copyMap(src.others),
      innateOff: copyMap(src.innateOff),
      ticks: copyMap(src.ticks),
      stacks: copyMap(src.stacks),
      tiers: copyMap(src.tiers),
      variants: copyMap(src.variants)
    };
  }

  // 这条武器词条在当前模式下能不能出现：常规看 normalWepTypes，深夜看 deepWepTypes（⊇ 常规）。
  function weaponAffixAvailable(affix, runMode) {
    if (!affix) return false;
    if (runMode === "deep") return affix.deepWepTypes.length > 0;
    return !affix.deepOnly && affix.normalWepTypes.length > 0;
  }

  function weaponAffixMatchesType(affix, runMode, wepType) {
    if (wepType == null) return true;
    var list = runMode === "deep" ? affix.deepWepTypes : affix.normalWepTypes;
    return list.indexOf(wepType) !== -1;
  }

  function weaponAffixCount(config, id) {
    var found = (config.weaponAffixes || []).filter(function (one) { return one.id === id; })[0];
    return found ? found.count : 0;
  }

  function weaponAffixUsage(cfgIndex, config) {
    var caps = slotCaps(cfgIndex.slotRules, config.runMode);
    var used = 0;
    var deepOnly = 0;
    (config.weaponAffixes || []).forEach(function (one) {
      var affix = cfgIndex.weaponAffixById[one.id];
      if (!affix || !(one.count > 0)) return;
      used += one.count;
      if (affix.deepOnlyPositive) deepOnly += one.count;
    });
    return { used: used, cap: caps.weaponAffix, deepOnlyUsed: deepOnly, deepOnlyCap: caps.deepOnly };
  }

  // 能不能再加一份：模式可用、总数未满、深夜专属未满。返回 { ok, reason }。
  function canAddWeaponAffix(cfgIndex, config, id) {
    var affix = cfgIndex.weaponAffixById[id];
    if (!affix) return { ok: false, reason: "" };
    if (!weaponAffixAvailable(affix, config.runMode)) return { ok: false, reason: TEXT.waNotInMode };
    var usage = weaponAffixUsage(cfgIndex, config);
    if (usage.used >= usage.cap) return { ok: false, reason: TEXT.waCapReached };
    if (affix.deepOnlyPositive && usage.deepOnlyUsed >= usage.deepOnlyCap) {
      return { ok: false, reason: TEXT.waDeepOnlyCapReached };
    }
    return { ok: true, reason: "" };
  }

  // 数量步进：delta = +1 / -1。越界时原样返回（不抛错）。
  function stepWeaponAffix(cfgIndex, config, id, delta) {
    var next = cloneConfig(config);
    var list = next.weaponAffixes;
    var found = list.filter(function (one) { return one.id === id; })[0];
    if (delta > 0) {
      if (!canAddWeaponAffix(cfgIndex, next, id).ok) return next;
      if (found) found.count += 1;
      else list.push({ id: id, count: 1 });
    } else if (delta < 0 && found) {
      found.count -= 1;
      if (found.count <= 0) list.splice(list.indexOf(found), 1);
    }
    return next;
  }

  // 切模式（两端同一口径）：去掉新模式下不存在的词条，深夜专属超限的按 AttachEffect id 从大到小削，
  // 总数超限的再按 id 从大到小削；切回常规时深夜遗物格清空。
  function applyRunMode(cfgIndex, config, runMode) {
    var next = cloneConfig(config);
    next.runMode = runMode === "deep" ? "deep" : "normal";
    next.weaponAffixes = next.weaponAffixes.filter(function (one) {
      return weaponAffixAvailable(cfgIndex.weaponAffixById[one.id], next.runMode) && one.count > 0;
    });
    var caps = slotCaps(cfgIndex.slotRules, next.runMode);
    function trim(onlyDeep, capacity) {
      var usage = weaponAffixUsage(cfgIndex, next);
      var excess = (onlyDeep ? usage.deepOnlyUsed : usage.used) - capacity;
      next.weaponAffixes.slice().sort(function (a, b) { return b.id - a.id; }).forEach(function (one) {
        if (excess <= 0) return;
        if (onlyDeep && !cfgIndex.weaponAffixById[one.id].deepOnlyPositive) return;
        var cut = Math.min(one.count, excess);
        one.count -= cut;
        excess -= cut;
      });
      next.weaponAffixes = next.weaponAffixes.filter(function (one) { return one.count > 0; });
    }
    trim(true, caps.deepOnly);
    trim(false, caps.weaponAffix);
    if (next.runMode === "normal") {
      for (var i = caps.relicNormal; i < next.relics.length; i += 1) next.relics[i] = emptyRelicCard();
    }
    return next;
  }

  // 切模式去掉的武器词条条数（「切到常规」的提示用）。
  function trimmedCount(cfgIndex, before, after) {
    return weaponAffixUsage(cfgIndex, before).used - weaponAffixUsage(cfgIndex, after).used;
  }

  // 填层数：截到 0..参数表上限（份数型 0..99）；0 就是不计入。
  function setStacks(config, entry, value) {
    var next = cloneConfig(config);
    if (!entry || !entry.stackInput) return next;
    var n = Math.floor(Number(value));
    if (!isFinite(n)) n = 0;
    next.stacks[entry.id] = Math.max(0, Math.min(n, stackParamMax(entry)));
    return next;
  }

  // 勾选／取消「其它增益」栏的一行。当前武器固有：勾掉＝排除。勾上不占槽位的叠层／累积阶梯时，
  // 没填过层数就先填一局实际上限（没有就 1 层），没选过层就先选数据里收录的最高层（两端同一口径）。
  function toggleOtherRow(cfgIndex, out, config, rowKey, checked) {
    var next = cloneConfig(config);
    var rowInfo = null;
    OTHER_SLOTS.forEach(function (slot) {
      (cfgIndex.otherRows[slot] || []).forEach(function (one) { if (one.key === rowKey) rowInfo = one; });
    });
    if (!rowInfo) return next;
    var innate = currentInnateEntries(cfgIndex, out);
    if (rowInfo.entries.some(function (entry) { return innate.indexOf(entry) !== -1; })) {
      rowInfo.entries.forEach(function (entry) {
        if (checked) delete next.innateOff[entry.id];
        else next.innateOff[entry.id] = true;
      });
      return next;
    }
    if (!checked) {
      delete next.others[rowKey];
      return next;
    }
    next.others[rowKey] = true;
    rowInfo.entries.forEach(function (entry) {
      if (entry.stackInput && !(stacksFor(entry, next) > 0)) next.stacks[entry.id] = defaultStacks(entry);
    });
    var first = rowInfo.entries[0];
    if (first && first.accLadder && selectedLadderTier(first, next, cfgIndex.ladders).id === null) {
      var top = ladderTopTier(cfgIndex.ladders, first.ladderGroup);
      if (top) next.tiers[first.ladderGroup] = top.id;
    }
    return next;
  }

  // 按来源键移除：wa:<词条>（减一份）/ relic:<格>（整件清空）/ relic:<格>:<行>（清掉这一行的词条与诅咒）/
  // acc:<格> / innate:<spEffectId>（排除当前武器固有）/ other:<行键>（取消勾选）。
  function removeSource(cfgIndex, config, key) {
    var parts = String(key || "").split(":");
    var next = cloneConfig(config);
    var id = Number(parts[1]);
    if (parts[0] === "wa") return stepWeaponAffix(cfgIndex, config, id, -1);
    if (parts[0] === "relic" && next.relics[id]) {
      if (parts.length > 2 && next.relics[id].type === "custom") {
        next.relics[id].affixIds[Number(parts[2])] = null;
        next.relics[id].curseIds[Number(parts[2])] = null;
      } else {
        next.relics[id] = emptyRelicCard();
      }
    } else if (parts[0] === "acc") {
      next.accessories[id] = null;
    } else if (parts[0] === "innate") {
      next.innateOff[id] = true;
    } else if (parts[0] === "other") {
      delete next.others[id];
    }
    return next;
  }

  // ---- 遗物合法性 ------------------------------------------------------

  // 这一格算不算「用上了」：固定遗物要选中一件，自组要至少有一条词条或诅咒。
  function relicCardFilled(card) {
    if (!card) return false;
    if (card.type === "fixed") return Boolean(card.key);
    if (card.type === "custom") {
      return (card.affixIds || []).some(function (id) { return id != null; }) ||
        (card.curseIds || []).some(function (id) { return id != null; });
    }
    return false;
  }

  function relicKindForCard(caps, cardIndex) {
    return cardIndex < caps.relicNormal ? "normal" : "deep";
  }

  function relicModeKey(kind) {
    return kind === "deep" ? "deepPositive" : "currentNormal";
  }

  // 不足三条时补的占位词条：能落进该模式的任一槽池、不参与互斥、排在最后。
  function placeholderAffix(position, modeKey, Core) {
    var mode = Core && Core.MODES ? Core.MODES[modeKey] : null;
    return {
      effectId: -(position + 1),
      name: TEXT.relicPlaceholderAffix,
      compatibilityId: -1,
      sortId: Number.MAX_SAFE_INTEGER,
      poolIds: mode ? mode.slotPoolIds.slice() : [],
      isCurse: false,
      requiresCurse: false,
      placeholder: true
    };
  }

  // 三行：{ row, affix, curse }（没有词条也没有诅咒的行不列）；词条库里找不到的 ID 进 unknown。
  function relicRows(card, catalogIndex) {
    var rows = [];
    var unknown = [];
    for (var position = 0; position < 3; position += 1) {
      var id = (card.affixIds || [])[position];
      var curseId = (card.curseIds || [])[position];
      var affix = null;
      var curse = null;
      if (id != null) {
        affix = catalogIndex.byId.get(id) || null;
        if (!affix && unknown.indexOf(id) === -1) unknown.push(id);
      }
      if (curseId != null) {
        curse = catalogIndex.byId.get(curseId) || null;
        if (!curse && unknown.indexOf(curseId) === -1) unknown.push(curseId);
      }
      if (affix || curse) rows.push({ row: position, affix: affix, curse: curse });
    }
    return { rows: rows, unknown: unknown };
  }

  function namesOf(affixes) {
    return affixes.map(function (affix) { return affix.name; }).join("、");
  }

  function intersects(left, right) {
    return (left || []).some(function (value) { return (right || []).indexOf(value) !== -1; });
  }

  // Core.check 判出的问题按类型改用本页文案（两端逐字一致），只列真实词条（占位词条不出现在文案里）；
  // 排序：重复 → 互斥 → 出货池／槽池模板，同类按涉及词条的规范顺序。
  var CHECK_KIND_ORDER = ["duplicate", "conflict", "unavailable"];

  function checkerIssues(issues, ordered, mode) {
    var position = {};
    ordered.forEach(function (affix, i) { if (!(affix.effectId in position)) position[affix.effectId] = i; });
    var byId = {};
    ordered.forEach(function (affix) { byId[affix.effectId] = affix; });
    var out = [];
    (issues || []).forEach(function (issue) {
      var kind = CHECK_KIND_ORDER.indexOf(issue.kind) === -1 ? "unavailable" : issue.kind;
      var affected = [];
      (issue.effectIds || []).forEach(function (id) {
        var affix = byId[id];
        if (affix && !affix.placeholder && affected.indexOf(affix) === -1) affected.push(affix);
      });
      affected.sort(function (a, b) { return position[a.effectId] - position[b.effectId]; });
      var real = ordered.filter(function (affix) { return !affix.placeholder; });
      var title;
      var detail;
      if (kind === "duplicate") {
        title = TEXT.checkDuplicateTitle;
        detail = fmt(TEXT.checkDuplicateDetail, (affected[0] || real[0] || {}).name || "");
      } else if (kind === "conflict") {
        title = TEXT.checkConflictTitle;
        detail = fmt(TEXT.checkConflictDetail, namesOf(affected));
      } else {
        var outside = real.filter(function (affix) { return !intersects(affix.poolIds, mode ? mode.slotPoolIds : []); });
        if (outside.length) {
          affected = outside;
          title = TEXT.checkPoolTitle;
          detail = fmt(TEXT.checkPoolDetail, namesOf(outside));
        } else {
          affected = real;
          title = TEXT.checkTemplateTitle;
          detail = fmt(TEXT.checkTemplateDetail, namesOf(real));
        }
      }
      out.push({
        kind: kind, title: title, detail: detail,
        effectIds: affected.map(function (affix) { return affix.effectId; }),
        order: CHECK_KIND_ORDER.indexOf(kind) * 10 + (affected.length ? position[affected[0].effectId] : 9)
      });
    });
    out.sort(function (a, b) { return a.order - b.order; });
    return out.map(function (issue) {
      return { kind: issue.kind, title: issue.title, detail: issue.detail, effectIds: issue.effectIds };
    });
  }

  // 自组遗物检查。kind = normal / deep。返回 { status, message, issues, warnings, rows }：
  //   status = empty / partial（不足三条，预检通过）/ valid / invalid
  // 正面词条一律走 Core.check（不足三条先用占位词条补足）；深夜再按存档检查的深夜遗物审计口径查诅咒配对。
  function checkCustomRelic(card, kind, catalogIndex, Core) {
    var result = { status: "empty", message: TEXT.relicEmpty, issues: [], warnings: [], rows: [] };
    if (!catalogIndex || !catalogIndex.available || !Core || typeof Core.check !== "function") {
      result.status = "invalid";
      result.message = TEXT.relicNoCatalog;
      result.issues.push({ kind: "noCatalog", title: TEXT.relicNoCatalog, detail: "", effectIds: [] });
      return result;
    }
    var cacheKey = kind + "|" + (card.affixIds || []).join(",") + "|" + (card.curseIds || []).join(",");
    var cache = catalogIndex.checkCache;
    if (cache && cache.has(cacheKey)) return cache.get(cacheKey);
    var parsed = relicRows(card, catalogIndex);
    result.rows = parsed.rows;
    if (parsed.unknown.length) {
      result.status = "invalid";
      result.message = TEXT.relicInvalid;
      result.issues.push({
        kind: "unknownEffect", title: TEXT.relicUnknownEffectTitle,
        detail: fmt(TEXT.relicUnknownEffectDetail, parsed.unknown.join("、")), effectIds: parsed.unknown.slice()
      });
      if (cache) cache.set(cacheKey, result);
      return result;
    }
    if (!parsed.rows.length) {
      if (cache) cache.set(cacheKey, result);
      return result;
    }
    var modeKey = relicModeKey(kind);
    var affixes = parsed.rows.filter(function (row) { return row.affix; }).map(function (row) { return row.affix; });
    if (affixes.length) {
      var padded = affixes.slice();
      while (padded.length < 3) padded.push(placeholderAffix(padded.length, modeKey, Core));
      var ordered = Core.canonicalOrder(padded);
      var checked = Core.check(ordered, modeKey);
      if (checked.status === "invalid") {
        result.issues = checkerIssues(checked.issues, ordered, Core.MODES ? Core.MODES[modeKey] : null);
      }
    }
    var cursePoolId = numOr(catalogIndex.cursePoolId, DEEP_CURSE_POOL_ID);
    var before = result.issues.length;
    if (kind === "deep") curseIssues(parsed.rows, result.issues, cursePoolId);
    if (kind === "deep" && result.issues.length === before) {
      result.warnings.push({ kind: "cursePairing", title: TEXT.cursePairingTitle,
        detail: fmt(TEXT.cursePairingDetail, cursePoolId), effectIds: [] });
    }
    if (kind !== "deep") {
      // 普通遗物没有诅咒槽：带了诅咒一律是多余的。
      parsed.rows.forEach(function (row) {
        if (!row.curse) return;
        result.issues.push({ kind: "curseUnexpected", title: TEXT.curseUnexpectedTitle,
          detail: fmt(TEXT.curseUnexpectedDetail, row.row + 1, row.curse.name), effectIds: [row.curse.effectId] });
      });
    }
    if (result.issues.length) {
      result.status = "invalid";
      result.message = TEXT.relicInvalid;
    } else if (affixes.length < 3) {
      result.status = "partial";
      result.message = fmt(TEXT.relicPartial, affixes.length, 3 - affixes.length);
    } else {
      result.status = "valid";
      result.message = kind === "deep" ? TEXT.relicValidDeep : TEXT.relicValidNormal;
    }
    if (cache) cache.set(cacheKey, result);
    return result;
  }

  // 深夜诅咒配对：与存档检查的深夜遗物审计（core.js auditRelic → auditDeepRelic、Swift RelicAudit）
  // 同一口径、同一文案：逐行「需诅咒 ⇔ 带诅咒」、诅咒须在诅咒池；另查涉及诅咒的重复与互斥
  // （正面词条之间的重复与互斥已由 Core.check 查过），词条按出现顺序（先三行正面、再三行诅咒）列出。
  function curseIssues(rows, issues, cursePoolId) {
    var poolId = numOr(cursePoolId, DEEP_CURSE_POOL_ID);
    rows.forEach(function (row) {
      var line = row.row + 1;
      var needsCurse = Boolean(row.affix && row.affix.requiresCurse);
      if (needsCurse && !row.curse) {
        issues.push({ kind: "curseMissing", title: TEXT.curseMissingTitle,
          detail: fmt(TEXT.curseMissingDetail, line, row.affix.name), effectIds: [row.affix.effectId] });
      } else if (!needsCurse && row.curse) {
        issues.push({ kind: "curseUnexpected", title: TEXT.curseUnexpectedTitle,
          detail: fmt(TEXT.curseUnexpectedDetail, line, row.curse.name), effectIds: [row.curse.effectId] });
      }
    });
    rows.forEach(function (row) {
      if (row.curse && !(row.curse.isCurse === true && (row.curse.poolIds || []).indexOf(poolId) !== -1)) {
        issues.push({ kind: "curseMismatch", title: TEXT.curseMismatchTitle,
          detail: fmt(TEXT.curseMismatchDetail, row.row + 1, row.curse.name), effectIds: [row.curse.effectId] });
      }
    });
    var all = [];
    rows.forEach(function (row) { if (row.affix) all.push({ affix: row.affix, curse: false }); });
    rows.forEach(function (row) { if (row.curse) all.push({ affix: row.curse, curse: true }); });
    var dupIds = [];
    all.forEach(function (one) {
      var id = one.affix.effectId;
      if (dupIds.indexOf(id) !== -1) return;
      var same = all.filter(function (other) { return other.affix.effectId === id; });
      if (same.length > 1 && same.some(function (other) { return other.curse; })) dupIds.push(id);
    });
    if (dupIds.length) {
      issues.push({ kind: "duplicate", title: TEXT.curseDuplicateTitle,
        detail: fmt(TEXT.curseDuplicateDetail, dupIds.map(function (id) {
          return all.filter(function (one) { return one.affix.effectId === id; })[0].affix.name;
        }).join("、")), effectIds: dupIds });
    }
    var conflicting = [];
    all.forEach(function (one) {
      var compat = one.affix.compatibilityId;
      if (compat === -1 || compat == null) return;
      var group = all.filter(function (other) { return other.affix.compatibilityId === compat; });
      if (group.length < 2 || !group.some(function (other) { return other.curse; })) return;
      if (conflicting.indexOf(one.affix) === -1) conflicting.push(one.affix);
    });
    if (conflicting.length) {
      issues.push({ kind: "conflict", title: TEXT.curseConflictTitle,
        detail: fmt(TEXT.curseConflictDetail, namesOf(conflicting)),
        effectIds: conflicting.map(function (affix) { return affix.effectId; }) });
    }
  }

  // 给这一行挑一条诅咒：诅咒池里按 effectId 升序，取第一条不会让这件遗物因它出问题的；配不上返回 null。
  function pickCurse(card, row, catalogIndex, Core) {
    for (var i = 0; i < catalogIndex.curses.length; i += 1) {
      var curse = catalogIndex.curses[i];
      var trial = { type: "custom", key: null, affixIds: card.affixIds.slice(), curseIds: card.curseIds.slice() };
      trial.curseIds[row] = curse.effectId;
      var probe = checkCustomRelic(trial, "deep", catalogIndex, Core);
      var clash = probe.issues.some(function (issue) {
        return (issue.effectIds || []).indexOf(curse.effectId) !== -1;
      });
      if (!clash) return curse.effectId;
    }
    return null;
  }

  // 给需诅咒的词条自动配诅咒（pickCurse），不需要诅咒的行清掉诅咒；普通遗物不带诅咒。
  function autoAssignCurses(card, kind, catalogIndex, Core) {
    var next = { type: card.type, key: card.key, affixIds: card.affixIds.slice(), curseIds: card.curseIds.slice() };
    if (kind !== "deep") {
      next.curseIds = [null, null, null];
      return next;
    }
    next.affixIds.forEach(function (id, position) {
      var affix = id == null ? null : catalogIndex.byId.get(id);
      if (!affix || !affix.requiresCurse) { next.curseIds[position] = null; return; }
      if (next.curseIds[position] != null) return;
      next.curseIds[position] = pickCurse(next, position, catalogIndex, Core);
    });
    return next;
  }

  // 自组遗物某一行换词条（两端同法，macOS 为 LoadoutEvaluator.withRelicAffix）：这一行的旧诅咒先清掉，
  // 再 autoAssignCurses —— 深夜遗物选了需诅咒的词条就自动配一条（换成另一条需诅咒的词条时按新词条重配），
  // 不需要诅咒的行清掉诅咒；普通遗物不带诅咒。
  function withRelicAffix(card, kind, row, affixId, catalogIndex, Core) {
    var next = { type: "custom", key: card.key, affixIds: card.affixIds.slice(), curseIds: card.curseIds.slice() };
    next.affixIds[row] = affixId == null ? null : affixId;
    next.curseIds[row] = null;
    return autoAssignCurses(next, kind, catalogIndex, Core);
  }

  // ---- 收集配置里的条目 --------------------------------------------------

  function relicCardLabel(caps, cardIndex) {
    var kind = relicKindForCard(caps, cardIndex);
    return kind === "deep"
      ? fmt(TEXT.relicCardDeep, cardIndex - caps.relicNormal + 1)
      : fmt(TEXT.relicCardNormal, cardIndex + 1);
  }

  // 当前武器的固有效果（weaponInnate.weaponIds 含当前武器）。法术没有武器 → 空。
  function currentInnateEntries(cfgIndex, out) {
    var weapon = out && out.mode === "skill" ? out.weapon : null;
    if (!weapon) return [];
    return cfgIndex.index.entries.filter(function (entry) {
      return entry.listable && entry.innate && Array.isArray(entry.innate.weaponIds) &&
        entry.innate.weaponIds.indexOf(weapon.id) !== -1;
    });
  }

  // 把配置展开成「来源 → 条目」的清单（还没评估），两端同一顺序：
  //   武器词条（AttachEffect id 升序）→ 遗物格 → 护符格 → 当前武器固有 → 其它栏勾选（spEffectId 升序）。
  function collectSources(cfgIndex, out, config, Core) {
    var caps = slotCaps(cfgIndex.slotRules, config.runMode);
    var list = [];
    var relicChecks = [];
    (config.weaponAffixes || []).slice().sort(function (a, b) { return a.id - b.id; }).forEach(function (one) {
      var affix = cfgIndex.weaponAffixById[one.id];
      if (!affix || !(one.count > 0) || !weaponAffixAvailable(affix, config.runMode)) return;
      var label = affix.label + (one.count > 1 ? " ×" + one.count : "");
      affix.entries.forEach(function (entry) {
        list.push({ entry: entry, column: "weaponAffix", copies: one.count, label: label, key: "wa:" + affix.id });
      });
    });
    for (var cardIndex = 0; cardIndex < caps.relics; cardIndex += 1) {
      var card = (config.relics || [])[cardIndex] || emptyRelicCard();
      var kind = relicKindForCard(caps, cardIndex);
      var cardLabel = relicCardLabel(caps, cardIndex);
      if (card.type === "fixed") {
        var fixed = card.key ? cfgIndex.fixedRelicByKey[card.key] : null;
        relicChecks[cardIndex] = fixed
          ? { status: "fixed", message: TEXT.relicFixedValid, issues: [], warnings: [], rows: [] }
          : { status: "empty", message: TEXT.relicEmpty, issues: [], warnings: [], rows: [] };
        if (!fixed) continue;
        fixed.entries.forEach(function (entry) {
          list.push({ entry: entry, column: "relic", copies: 1, label: cardLabel + "：" + fixed.nameZh, key: "relic:" + cardIndex });
        });
      } else if (card.type === "custom") {
        var check = checkCustomRelic(card, kind, cfgIndex.catalog, Core);
        relicChecks[cardIndex] = check;
        var invalid = check.status === "invalid";
        check.rows.forEach(function (row) {
          if (!row.affix) return;
          (cfgIndex.relicAffixEntries.get(row.affix.effectId) || []).forEach(function (entry) {
            list.push({
              entry: entry, column: "relic", copies: 1, invalid: invalid,
              label: cardLabel + "：" + row.affix.name, key: "relic:" + cardIndex + ":" + row.row
            });
          });
        });
      } else {
        relicChecks[cardIndex] = { status: "empty", message: TEXT.relicEmpty, issues: [], warnings: [], rows: [] };
      }
    }
    (config.accessories || []).slice(0, caps.accessory).forEach(function (id, slot) {
      var talisman = id == null ? null : cfgIndex.talismanById[id];
      if (!talisman) return;
      talisman.entries.forEach(function (entry) {
        list.push({ entry: entry, column: "accessory", copies: 1, label: talisman.nameZh, key: "acc:" + slot });
      });
    });
    // 当前武器固有：自动列入，但不算用户确认——条件型默认未确认、叠层默认 0 层（notes.ranking ③）。
    var innate = currentInnateEntries(cfgIndex, out);
    var innateIds = {};
    innate.forEach(function (entry) {
      innateIds[entry.id] = true;
      if (config.innateOff && config.innateOff[entry.id]) return;
      list.push({ entry: entry, column: "other", copies: 1, label: TEXT.otherAutoInnate, key: "innate:" + entry.id, auto: true });
    });
    var picked = [];
    OTHER_SLOTS.forEach(function (slot) {
      (cfgIndex.otherRows[slot] || []).forEach(function (row) {
        if (!(config.others && config.others[row.key])) return;
        row.entries.forEach(function (entry) {
          if (innateIds[entry.id]) return;
          picked.push({ entry: entry, column: "other", copies: 1, label: TEXT.otherGroups[slot], key: "other:" + row.key, autoConfirm: true });
        });
      });
    });
    picked.sort(function (a, b) { return a.entry.id - b.entry.id; });
    return { sources: list.concat(picked), relicChecks: relicChecks, caps: caps };
  }

  // 同一个 spEffectId 从多处来的合并成一条（份数相加、来源并列）；不合法自组遗物里的单独成条（不计入）。
  function mergeSources(sources) {
    var merged = [];
    var byId = {};
    var invalid = [];
    sources.forEach(function (source) {
      if (source.invalid) {
        invalid.push({
          entry: source.entry, column: source.column, copies: source.copies || 1,
          labels: [source.label], keys: [source.key], autoConfirm: false, auto: false, invalid: true
        });
        return;
      }
      var id = source.entry.id;
      var one = byId[id];
      if (!one) {
        one = {
          entry: source.entry, column: source.column, copies: 0, labels: [], keys: [],
          autoConfirm: false, auto: source.auto === true
        };
        byId[id] = one;
        merged.push(one);
      }
      one.copies += source.copies || 1;
      if (one.labels.indexOf(source.label) === -1) one.labels.push(source.label);
      if (one.keys.indexOf(source.key) === -1) one.keys.push(source.key);
      if (source.autoConfirm) one.autoConfirm = true;
      if (source.auto !== true) one.auto = false;
    });
    return merged.concat(invalid);
  }

  // ---- 整套配置的评估 ----------------------------------------------------

  function makeEnv(cfgIndex, out, config, options) {
    var opts = options || {};
    return {
      plan: cfgIndex.plan, out: out, config: config, ladders: cfgIndex.ladders,
      strict: opts.strict === true, assumeAll: opts.assumeAll === true,
      ownTier: opts.ownTier === true, ownVariant: opts.ownVariant === true
    };
  }

  function evaluateMerged(merged, env) {
    return merged.map(function (source) {
      var item = evaluateEntry(source.entry, env, source);
      if (source.invalid) {
        item.state = "relicInvalid";
        item.reasons = [TEXT.reasonRelicInvalid];
      }
      return item;
    });
  }

  function columnSummary(items, shares) {
    var counted = items.filter(function (item) { return item.state === "counted"; });
    var table = productTable(counted.map(function (item) { return item.table; }));
    var flat = emptyTypeMap(0);
    counted.forEach(function (item) {
      TYPE_KEYS.forEach(function (type) { flat[type] += item.flatTable[type]; });
    });
    return {
      count: counted.length,
      table: table,
      multiplier: weightedMultiplier(table, shares),
      flat: weightedFlat(flat, shares)
    };
  }

  function evaluateConfig(cfgIndex, out, config, Core, options) {
    var env = makeEnv(cfgIndex, out, config, options);
    var collected = collectSources(cfgIndex, out, config, Core);
    var items = evaluateMerged(mergeSources(collected.sources), env);
    var winners = dedupeItems(items);
    var byColumn = {};
    COLUMN_ORDER.forEach(function (column) {
      byColumn[column] = columnSummary(winners.filter(function (item) { return item.column === column; }), out.shares);
    });
    var total = columnSummary(winners, out.shares);
    var weaponUsage = weaponAffixUsage(cfgIndex, config);
    var relicUsed = 0;
    for (var i = 0; i < collected.caps.relics; i += 1) {
      if (relicCardFilled((config.relics || [])[i])) relicUsed += 1;
    }
    var accessories = (config.accessories || []).slice(0, collected.caps.accessory).filter(function (id) { return id != null; });
    var slots = {
      weaponAffix: weaponUsage,
      relic: { used: relicUsed, cap: collected.caps.relics },
      accessory: { used: accessories.length, cap: collected.caps.accessory }
    };
    return {
      items: items,
      counted: winners,
      byColumn: byColumn,
      total: total,
      caps: collected.caps,
      relicChecks: collected.relicChecks,
      slots: slots,
      warnings: configWarnings(items, winners, cfgIndex, config, collected.caps),
      violations: configViolations(cfgIndex, config, collected, slots, accessories),
      hasComposition: out.hasComposition
    };
  }

  // 只算总倍率（「按推荐填满」的内层循环用；strict＝推荐口径）。
  function totalOf(cfgIndex, out, config, Core, strict) {
    var env = makeEnv(cfgIndex, out, config, { strict: strict });
    var collected = collectSources(cfgIndex, out, config, Core);
    var items = evaluateMerged(mergeSources(collected.sources), env);
    var winners = dedupeItems(items);
    var m = weightedMultiplier(productTable(winners.map(function (item) { return item.table; })), out.shares);
    return m === null ? 1 : m;
  }

  // 提示（两端同一顺序）：互斥键压掉 → 同一效果多份只算一份 → stackSelf 多份相乘 → 同族不同档位相乘
  //   → 不同叠层阶梯相乘 → 遗物 exclusivityId → 同一件固定遗物装了两件。
  function configWarnings(items, winners, cfgIndex, config, caps) {
    var warnings = [];
    var losersByKey = {};
    var keyOrder = [];
    items.forEach(function (item) {
      if (item.state !== "duplicate") return;
      var key = item.entry.key;
      if (!losersByKey[key]) { losersByKey[key] = []; keyOrder.push(key); }
      losersByKey[key].push(item);
    });
    keyOrder.forEach(function (key) {
      var losers = losersByKey[key];
      var winner = losers[0].dupOf;
      var names = [];
      losers.forEach(function (item) { if (names.indexOf(item.entry.name) === -1) names.push(item.entry.name); });
      if (losers.every(function (item) { return isPriorityWin(winner, item); })) {
        warnings.push({ kind: "priority", text: fmt(TEXT.warnPriority, key, winner.entry.name, names.join("、")) });
      } else {
        var all = [winner.entry.name];
        names.forEach(function (name) { if (all.indexOf(name) === -1) all.push(name); });
        warnings.push({ kind: "duplicate", text: fmt(TEXT.warnDuplicateKey, key, losers.length + 1, all.join("、")) });
      }
    });
    var single = winners.filter(function (item) { return item.copies > 1 && item.countedCopies === 1; });
    if (single.length) {
      warnings.push({ kind: "copiesSingle", text: fmt(TEXT.warnCopiesSingle, single.map(function (item) {
        return item.entry.name;
      }).join("、")) });
    }
    var multiplied = winners.filter(function (item) { return item.countedCopies > 1; });
    if (multiplied.length) {
      warnings.push({ kind: "copiesStackSelf", text: fmt(TEXT.warnCopiesStackSelf, multiplied.map(function (item) {
        return item.entry.name + " ×" + item.countedCopies;
      }).join("、")) });
    }
    var byFamily = {};
    var familyOrder = [];
    winners.forEach(function (item) {
      var family = item.entry.family;
      if (!byFamily[family]) { byFamily[family] = []; familyOrder.push(family); }
      byFamily[family].push(item);
    });
    familyOrder.forEach(function (family) {
      var group = byFamily[family];
      var keys = {};
      group.forEach(function (item) { keys[item.entry.key] = true; });
      if (Object.keys(keys).length < 2) return;
      warnings.push({ kind: "tiers", text: fmt(TEXT.warnTiers, familyName(group[0].entry.name), group.map(function (item) {
        return item.entry.name;
      }).join("、")) });
    });
    var ladders = winners.filter(function (item) { return item.entry.stackInput && item.entry.stackInput.mode === "ladder"; });
    var ladderKeys = {};
    ladders.forEach(function (item) { ladderKeys[item.entry.key] = true; });
    if (Object.keys(ladderKeys).length >= 2) {
      warnings.push({ kind: "ladders", text: fmt(TEXT.warnLadders, ladders.map(function (item) { return item.entry.name; }).join("、")) });
    }
    // relicAffixes[].exclusivityId（已装备的几件遗物之间互斥，Smithbox 注释）：同组不同词条同时计入时提示。
    var byExclusivity = {};
    var exclusivityOrder = [];
    winners.forEach(function (item) {
      if (item.column !== "relic") return;
      item.entry.exclusivityIds.forEach(function (exclusivityId) {
        if (!byExclusivity[exclusivityId]) { byExclusivity[exclusivityId] = { attach: {}, names: [] }; exclusivityOrder.push(exclusivityId); }
        var group = byExclusivity[exclusivityId];
        item.entry.relicAttachIds.forEach(function (attachId) { group.attach[attachId] = true; });
        if (group.names.indexOf(item.entry.name) === -1) group.names.push(item.entry.name);
      });
    });
    exclusivityOrder.forEach(function (exclusivityId) {
      var group = byExclusivity[exclusivityId];
      if (Object.keys(group.attach).length < 2) return;
      warnings.push({ kind: "exclusivity", text: fmt(TEXT.warnExclusivity, group.names.join("、"), exclusivityId) });
    });
    if (cfgIndex && config && caps) {
      var seenFixed = {};
      var reported = {};
      (config.relics || []).slice(0, caps.relics).forEach(function (card) {
        if (!card || card.type !== "fixed" || !card.key) return;
        if (seenFixed[card.key] && !reported[card.key]) {
          reported[card.key] = true;
          var fixed = cfgIndex.fixedRelicByKey[card.key];
          warnings.push({ kind: "fixedDuplicate", text: fmt(TEXT.warnFixedDuplicate, fixed ? fixed.nameZh : card.key) });
        }
        seenFixed[card.key] = true;
      });
    }
    return warnings;
  }

  // 超限（正常操作到不了，程序化构造的配置才会出现）：武器词条总数、深夜专属、护符数与重复、不合法的自组遗物。
  function configViolations(cfgIndex, config, collected, slots, accessories) {
    var list = [];
    var usage = slots.weaponAffix;
    if (usage.used > usage.cap) list.push(fmt(TEXT.violationWeaponAffix, usage.used, TEXT.runMode[collected.caps.runMode], usage.cap));
    if (usage.deepOnlyUsed > usage.deepOnlyCap) {
      list.push(collected.caps.runMode === "normal"
        ? fmt(TEXT.violationDeepOnlyInNormal, usage.deepOnlyUsed)
        : fmt(TEXT.violationDeepOnly, usage.deepOnlyUsed, usage.deepOnlyCap));
    }
    if (accessories.length > slots.accessory.cap) list.push(fmt(TEXT.violationAccessory, accessories.length, slots.accessory.cap));
    var seen = {};
    if (accessories.some(function (id) { var dup = seen[id]; seen[id] = true; return dup; })) {
      list.push(TEXT.violationAccessoryDuplicate);
    }
    collected.relicChecks.forEach(function (check, cardIndex) {
      if (check && check.status === "invalid") list.push(fmt(TEXT.violationRelic, relicCardLabel(collected.caps, cardIndex), check.message));
    });
    return list;
  }

  // ---- 候选的「放进去能拿到多少」-------------------------------------------

  // 一项候选（一条词条 / 一件遗物 / 一个护符 / 一行其它增益）单独放进来的评估：
  //   current  ＝按当前的确认／层数／选层／选档，单独选它时的有效倍率；
  //   potential＝条件全部成立时（叠层取一局实际上限、没有就 1 层，阶梯取最高层）的有效倍率。
  // column = 占槽位的栏或 "other"；auto＝当前武器固有（不算用户确认）。
  var STATE_RANK = { counted: 0, pending: 1, zeroStacks: 2, tierOff: 3, context: 4, neutral: 5, duplicate: 6, no: 7, variantOff: 8, relicInvalid: 9, noDamage: 10 };

  function candidateScore(cfgIndex, out, config, entries, column, auto) {
    var sources = (entries || []).map(function (entry) {
      return {
        entry: entry, column: column, copies: 1, labels: [], keys: [],
        autoConfirm: column === "other" && !auto, auto: auto === true
      };
    });
    function run(options) {
      var items = evaluateMerged(sources, makeEnv(cfgIndex, out, config, options));
      var winners = dedupeItems(items);
      var table = productTable(winners.map(function (item) { return item.table; }));
      var flat = 0;
      winners.forEach(function (item) { flat += item.flat || 0; });
      return { items: items, total: weightedMultiplier(table, out.shares), flat: flat };
    }
    var current = run({});
    var potential = run({ assumeAll: true });
    var best = null;
    var reasons = [];
    current.items.forEach(function (item) {
      if (best === null || STATE_RANK[item.state] < STATE_RANK[best]) { best = item.state; reasons = item.reasons.slice(); }
    });
    var applicable = current.items.some(function (item) {
      return item.state !== "no" && item.state !== "context" && item.state !== "variantOff" && item.state !== "noDamage";
    });
    var needs = current.items.some(function (item) {
      return item.state === "pending" || item.state === "zeroStacks" || item.state === "tierOff";
    });
    var oneStack = potential.items.some(function (item) { return item.assumedOneStack && item.state === "counted"; });
    return {
      items: current.items,
      score: current.total == null ? 1 : current.total,
      potential: potential.total == null ? 1 : potential.total,
      flat: potential.flat,
      state: best || "noDamage",
      reasons: reasons,
      applicable: applicable,
      needsConfirmation: needs,
      assumesOneStack: oneStack && Math.abs((potential.total || 1) - (current.total || 1)) > EPSILON
    };
  }

  // 行是否「对当前输出有收益」：条件成立时倍率 > 1 或有正的攻击力加算。没有构成时一律算有。
  function rowUseful(row, hasComposition) {
    if (!hasComposition) return true;
    return row.applicable && (row.potential > USEFUL_EPSILON || (row.flat || 0) > 0);
  }

  // 排序（两端同一口径）：生效的在前 → 当前倍率降序 → 条件成立时倍率降序 → ID 升序。
  function sortRowsByScore(rows) {
    rows.sort(function (a, b) {
      if (a.applicable !== b.applicable) return a.applicable ? -1 : 1;
      if (Math.abs(b.score - a.score) > EPSILON) return b.score - a.score;
      if (Math.abs(b.potential - a.potential) > EPSILON) return b.potential - a.potential;
      return (a.sortId || 0) - (b.sortId || 0);
    });
    return rows;
  }

  function scoredRow(base, score) {
    Object.keys(score).forEach(function (key) { base[key] = score[key]; });
    return base;
  }

  // 武器词条栏的行（已按有效倍率排序）。filterType=null 表示「全部类别」；已选的一律列出。
  function weaponAffixRows(cfgIndex, out, config, filterType) {
    var rows = [];
    cfgIndex.weaponAffixes.forEach(function (affix) {
      var count = weaponAffixCount(config, affix.id);
      if (count === 0 && !weaponAffixAvailable(affix, config.runMode)) return;
      if (count === 0 && !weaponAffixMatchesType(affix, config.runMode, filterType)) return;
      rows.push(scoredRow({
        affix: affix, count: count, sortId: affix.id,
        outsideFilter: count > 0 && !weaponAffixMatchesType(affix, config.runMode, filterType),
        can: canAddWeaponAffix(cfgIndex, config, affix.id)
      }, candidateScore(cfgIndex, out, config, affix.entries, "weaponAffix", false)));
    });
    return sortRowsByScore(rows);
  }

  function relicAffixRows(cfgIndex, out, config, kind) {
    return sortRowsByScore(((cfgIndex.relicCandidates || {})[kind] || []).map(function (candidate) {
      return scoredRow({ candidate: candidate, id: candidate.id, name: candidate.name, sortId: candidate.id },
        candidateScore(cfgIndex, out, config, candidate.entries, "relic", false));
    }));
  }

  function fixedRelicRows(cfgIndex, out, config, kind) {
    return sortRowsByScore(cfgIndex.fixedRelics.filter(function (relic) {
      return relic.isDeepRelic === (kind === "deep");
    }).map(function (relic) {
      return scoredRow({ relic: relic, key: relic.key, name: relic.nameZh, sortId: relic.relicIds[0] || 0 },
        candidateScore(cfgIndex, out, config, relic.entries, "relic", false));
    }));
  }

  function talismanRows(cfgIndex, out, config) {
    return sortRowsByScore(cfgIndex.talismans.map(function (talisman) {
      return scoredRow({ talisman: talisman, id: talisman.id, name: talisman.nameZh, sortId: talisman.id },
        candidateScore(cfgIndex, out, config, talisman.entries, "accessory", false));
    }));
  }

  function otherRowsFor(cfgIndex, out, config, slot) {
    var innateIds = {};
    currentInnateEntries(cfgIndex, out).forEach(function (entry) { innateIds[entry.id] = true; });
    return sortRowsByScore(((cfgIndex.otherRows || {})[slot] || []).map(function (row) {
      var auto = row.entries.some(function (entry) { return innateIds[entry.id]; });
      return scoredRow({
        row: row, key: row.key, name: row.name, auto: auto, sortId: row.key,
        selected: auto ? !(config.innateOff && row.entries.every(function (entry) { return config.innateOff[entry.id]; }))
          : Boolean(config.others && config.others[row.key])
      }, candidateScore(cfgIndex, out, config, row.entries, "other", auto));
    }));
  }

  // ---- 按推荐填满 ----------------------------------------------------------

  // 这项候选在推荐口径下能不能贡献（有没有一条会计入）：没有的不必试（结果不变，只为快）。
  function strictCounts(cfgIndex, out, config, entries, column) {
    var env = makeEnv(cfgIndex, out, config, { strict: true });
    return (entries || []).some(function (entry) {
      return evaluateEntry(entry, env, { column: column, copies: 1 }).state === "counted";
    });
  }

  // 两端同一口径：只填空槽、不改已选；顺序 武器词条 → 遗物逐格 → 护符；每一步取让（推荐口径的）总倍率
  // 增幅最大的候选，增幅相同取 ID 小的，增幅 ≤ 1e-9 就停。推荐口径不计条件型、要确认的、叠层与累积阶梯。
  // 返回 { config, added: [{column, label}] }。filterType：武器词条按类别过滤（null＝全部）。
  function recommendFill(cfgIndex, out, config, Core, filterType) {
    var next = cloneConfig(config);
    var added = [];
    if (!out.hasComposition) return { config: next, added: added };
    var best = totalOf(cfgIndex, out, next, Core, true);
    var caps = slotCaps(cfgIndex.slotRules, next.runMode);

    // ① 武器词条：可以同一条多份（stackSelf 的各份相乘），受总上限与深夜专属上限约束。
    var weaponPool = cfgIndex.weaponAffixes.filter(function (affix) {
      return weaponAffixAvailable(affix, next.runMode) && weaponAffixMatchesType(affix, next.runMode, filterType) &&
        strictCounts(cfgIndex, out, next, affix.entries, "weaponAffix");
    });
    while (true) {
      var choice = null;
      weaponPool.forEach(function (affix) {
        if (!canAddWeaponAffix(cfgIndex, next, affix.id).ok) return;
        var trial = stepWeaponAffix(cfgIndex, next, affix.id, 1);
        var value = totalOf(cfgIndex, out, trial, Core, true);
        if (value > (choice ? choice.total : best) + EPSILON) choice = { affix: affix, total: value };
      });
      if (!choice) break;
      next = stepWeaponAffix(cfgIndex, next, choice.affix.id, 1);
      best = choice.total;
      added.push({ column: "weaponAffix", label: choice.affix.label });
    }

    // ② 遗物：逐个空格比较「最好的固定遗物」与「贪心自组」，分数相同取固定遗物。
    for (var cardIndex = 0; cardIndex < caps.relics; cardIndex += 1) {
      if (relicCardFilled(next.relics[cardIndex])) continue;
      var kind = relicKindForCard(caps, cardIndex);
      var usedFixed = {};
      next.relics.forEach(function (card, i) {
        if (i < caps.relics && card.type === "fixed" && card.key) usedFixed[card.key] = true;
      });
      var cardBest = null;
      cfgIndex.fixedRelics.forEach(function (relic) {
        if (relic.isDeepRelic !== (kind === "deep") || usedFixed[relic.key]) return;
        if (!strictCounts(cfgIndex, out, next, relic.entries, "relic")) return;
        var trial = cloneConfig(next);
        trial.relics[cardIndex] = { type: "fixed", key: relic.key, affixIds: [null, null, null], curseIds: [null, null, null] };
        var value = totalOf(cfgIndex, out, trial, Core, true);
        if (value > (cardBest ? cardBest.total : best) + EPSILON) {
          cardBest = { card: trial.relics[cardIndex], total: value, label: relic.nameZh };
        }
      });
      var custom = greedyCustomRelic(cfgIndex, out, next, cardIndex, kind, Core, best);
      if (custom && custom.total > (cardBest ? cardBest.total : best) + EPSILON) cardBest = custom;
      if (cardBest) {
        next.relics[cardIndex] = cardBest.card;
        best = cardBest.total;
        added.push({ column: "relic", label: relicCardLabel(caps, cardIndex) + "：" + cardBest.label });
      }
    }

    // ③ 护符：不重复，取增幅最大的，填进第一个空格。
    while (true) {
      var slot = next.accessories.slice(0, caps.accessory).indexOf(null);
      if (slot === -1 && next.accessories.length < caps.accessory) slot = next.accessories.length;
      if (slot === -1) break;
      var pick = null;
      cfgIndex.talismans.forEach(function (talisman) {
        if (next.accessories.indexOf(talisman.id) !== -1) return;
        if (!strictCounts(cfgIndex, out, next, talisman.entries, "accessory")) return;
        var trial = cloneConfig(next);
        trial.accessories[slot] = talisman.id;
        var value = totalOf(cfgIndex, out, trial, Core, true);
        if (value > (pick ? pick.total : best) + EPSILON) pick = { talisman: talisman, total: value };
      });
      if (!pick) break;
      next.accessories[slot] = pick.talisman.id;
      best = pick.total;
      added.push({ column: "accessory", label: pick.talisman.nameZh });
    }
    return { config: next, added: added };
  }

  // 贪心自组一件遗物：逐行挑「加进去后仍合法（或预检通过）、且总倍率增幅最大」的词条（同增幅取 ID 小的），
  // 深夜需诅咒的词条先配一条诅咒（pickCurse），最多三行；没有正增益就停。
  function greedyCustomRelic(cfgIndex, out, config, cardIndex, kind, Core, base) {
    var candidates = ((cfgIndex.relicCandidates || {})[kind] || []).filter(function (candidate) {
      return strictCounts(cfgIndex, out, config, candidate.entries, "relic");
    });
    if (!candidates.length) return null;
    var card = emptyRelicCard();
    card.type = "custom";
    var total = base;
    var names = [];
    for (var row = 0; row < 3; row += 1) {
      var step = null;
      candidates.forEach(function (candidate) {
        if (card.affixIds.indexOf(candidate.id) !== -1) return;
        var trialCard = { type: "custom", key: null, affixIds: card.affixIds.slice(), curseIds: card.curseIds.slice() };
        trialCard.affixIds[row] = candidate.id;
        if (kind === "deep" && candidate.affix.requiresCurse) {
          var curse = pickCurse(trialCard, row, cfgIndex.catalog, Core);
          if (curse == null) return;
          trialCard.curseIds[row] = curse;
        }
        if (checkCustomRelic(trialCard, kind, cfgIndex.catalog, Core).status === "invalid") return;
        var trial = cloneConfig(config);
        trial.relics[cardIndex] = trialCard;
        var value = totalOf(cfgIndex, out, trial, Core, true);
        if (value > (step ? step.total : total) + EPSILON) step = { card: trialCard, total: value, name: candidate.name };
      });
      if (!step) break;
      card = step.card;
      total = step.total;
      names.push(step.name);
    }
    if (!names.length) return null;
    return { card: card, total: total, label: names.join("＋") };
  }

  // ---- 全部增益一览（折叠表）----------------------------------------------

  // 能进计算的条目逐条单独评估（两端同一口径）：「条件全部成立」——要确认的当成立，叠层取一局实际上限
  // （没有就 1 层），累积阶梯与多档词条按这一条自己的层／档。生效的在前，按有效倍率降序，再按 spEffectId。
  // 与用户当前的配置无关（叠层按一局实际上限、不看已填层数），两端同一张表。
  function overviewRows(cfgIndex, out) {
    var env = makeEnv(cfgIndex, out, emptyConfig(), { assumeAll: true, ownTier: true, ownVariant: true });
    var rows = [];
    cfgIndex.index.entries.forEach(function (entry) {
      if (!entry.listable) return;
      var item = evaluateEntry(entry, env, { column: "other", copies: 1 });
      item.applicable = item.state !== "no" && item.state !== "context";
      if (!item.applicable) item.multiplier = out.hasComposition ? 1 : null;
      rows.push(item);
    });
    rows.sort(function (a, b) {
      if (a.applicable !== b.applicable) return a.applicable ? -1 : 1;
      var am = a.multiplier == null ? 1 : a.multiplier;
      var bm = b.multiplier == null ? 1 : b.multiplier;
      if (Math.abs(bm - am) > EPSILON) return bm - am;
      return a.entry.id - b.entry.id;
    });
    return rows;
  }

  // ---- 输出手段列表 ----------------------------------------------------

  // 每把武器带这个战技的来源（usage「战技来源（v3）」读 skills[].weaponSources）：fixed＝武器的固定战技
  // （EquipParamWeapon.swordArtsParamId），pool＝局内掉落时战技池能抽到。两者都成立时只记 fixed。
  // 缺 weaponSources 的旧数据按 swordArtsParamId 判固定，判不出的不标。
  function weaponSourceMap(skill) {
    var map = {};
    var list = skill && Array.isArray(skill.weaponSources) ? skill.weaponSources : [];
    list.forEach(function (entry) {
      if (!entry || typeof entry.id !== "number") return;
      if (entry.fixed === true) map[entry.id] = "fixed";
      else if (Array.isArray(entry.pool) && entry.pool.length && map[entry.id] !== "fixed") map[entry.id] = "pool";
    });
    return map;
  }

  function weaponSourceOf(skill, weapon, map) {
    if (!skill || !weapon) return null;
    var sources = map || weaponSourceMap(skill);
    if (sources[weapon.id]) return sources[weapon.id];
    return weapon.swordArtsParamId === skill.id ? "fixed" : null;
  }

  // 能带这个战技的武器（skills[].weaponIds = 固定引用 ∪ 局内战技池）：固定战技的武器排前，其余按 id 升序。
  function weaponsForSkill(skillsData, skill) {
    var byId = skillsData && skillsData._weaponById;
    var ids = (skill && Array.isArray(skill.weaponIds)) ? skill.weaponIds : [];
    var sources = weaponSourceMap(skill);
    var out = [];
    ids.forEach(function (id) {
      var weapon = byId ? byId[id] : null;
      if (weapon) out.push(weapon);
    });
    var rank = function (weapon) { return weaponSourceOf(skill, weapon, sources) === "fixed" ? 0 : 1; };
    out.sort(function (a, b) { return (rank(a) - rank(b)) || (a.id - b.id); });
    return out;
  }

  // 按 wepTypeZh 分组，组与组内都保持传入顺序（weaponsForSkill 已按「固定在前、再按 id」排好）；
  // 用于武器下拉的 optgroup。
  // 传了 skill 时按三端同一规则排组（macOS SkillDataIndex.weaponGroups / Android weaponGroups 同口径）：
  // 含固定战技武器的组排前，其次按组内武器数降序，再按类别名升序；组内顺序沿用 weaponsForSkill
  // （固定武器在前、再按 id）。默认武器 = 第一组的第一把。不传 skill 时保持首次出现顺序（旧行为）。
  function groupWeapons(weapons, skill) {
    var order = [];
    var groups = {};
    var sources = skill ? weaponSourceMap(skill) : null;
    (weapons || []).forEach(function (weapon) {
      var key = weapon.wepTypeZh || weapon.wepTypeEn || "未分类";
      if (!groups[key]) { groups[key] = { label: key, weapons: [], fixedCount: 0 }; order.push(key); }
      groups[key].weapons.push(weapon);
      if (skill && weaponSourceOf(skill, weapon, sources) === "fixed") groups[key].fixedCount += 1;
    });
    var list = order.map(function (key) { return groups[key]; });
    if (skill) {
      list.sort(function (a, b) {
        var aFixed = a.fixedCount > 0, bFixed = b.fixedCount > 0;
        if (aFixed !== bFixed) return aFixed ? -1 : 1;
        if (a.weapons.length !== b.weapons.length) return b.weapons.length - a.weapons.length;
        return a.label < b.label ? -1 : (a.label > b.label ? 1 : 0);
      });
    }
    return list;
  }

  // 战技的默认武器：分组后第一组的第一把（含固定武器的组优先，组内固定武器优先）。
  function defaultWeaponFor(skillsData, skill) {
    var groups = groupWeapons(weaponsForSkill(skillsData, skill), skill);
    return groups.length && groups[0].weapons.length ? groups[0].weapons[0] : null;
  }

  function foldText(value) {
    return String(value == null ? "" : value).toLowerCase();
  }

  // 这条输出手段至少有一段能算出非 0 的相对值吗？算不出来的选中后构成恒为 0，是死路。
  function hasAnyDamage(hits, weapon, isSpell) {
    return (hits || []).some(function (hit) {
      var one = hitContribution(hit, weapon, isSpell);
      return TYPE_KEYS.some(function (key) { return one[key] > 0; });
    });
  }

  // 战技：任意一把能带它的武器（skills[].weaponIds：固定战技或局内战技池）能打出非 0 构成就收录。
  function skillHasDamage(skillsData, skill) {
    var byId = (skillsData && skillsData._weaponById) || {};
    var ids = (skill && Array.isArray(skill.weaponIds)) ? skill.weaponIds : [];
    for (var i = 0; i < ids.length; i += 1) {
      var weapon = byId[ids[i]];
      if (!weapon) continue;
      if (hasAnyDamage(selectHits(skill, weapon), weapon, false)) return true;
    }
    return false;
  }

  // 被输出手段列表挡在外面的条数（照数据现算）。
  function meansWithoutDamage(skillsData) {
    var skillCount = 0;
    var spellCount = 0;
    ((skillsData && skillsData.skills) || []).forEach(function (skill) {
      if (!Array.isArray(skill.hits) || !skill.hits.length) return;
      if (!Array.isArray(skill.weaponIds) || !skill.weaponIds.length) return;
      if (!skillHasDamage(skillsData, skill)) skillCount += 1;
    });
    ((skillsData && skillsData.spells) || []).forEach(function (spell) {
      if (!Array.isArray(spell.hits) || !spell.hits.length) return;
      if (!hasAnyDamage(spell.hits, null, true)) spellCount += 1;
    });
    return { skills: skillCount, spells: spellCount };
  }

  // 战技 + 法术的统一检索条目：至少有一段能算出非 0 相对值才收录。战技还要至少有一把武器——
  // v3 把局内战技池也算进 weaponIds 之后，没有武器的只剩 1 无战技 / 9999 ？？？ 两个占位条目。
  function buildMeansItems(skillsData) {
    var items = [];
    ((skillsData && skillsData.skills) || []).forEach(function (skill) {
      if (!Array.isArray(skill.hits) || !skill.hits.length) return;
      if (!Array.isArray(skill.weaponIds) || !skill.weaponIds.length) return;
      if (!skillHasDamage(skillsData, skill)) return;
      items.push({
        kind: "skill",
        id: skill.id,
        nameZh: skill.nameZh || "",
        nameEn: skill.nameEn || "",
        badge: TEXT.meansKind.skill,
        badgeColor: "purple",
        weaponCount: Array.isArray(skill.weaponIds) ? skill.weaponIds.length : 0,
        search: foldText((skill.nameZh || "") + " " + (skill.nameEn || ""))
      });
    });
    ((skillsData && skillsData.spells) || []).forEach(function (spell) {
      if (!Array.isArray(spell.hits) || !spell.hits.length) return;
      if (!hasAnyDamage(spell.hits, null, true)) return;
      var spellKind = spellKindOf(spell);
      items.push({
        kind: spellKind,
        spellKind: spellKind,
        id: spell.id,
        nameZh: spell.nameZh || "",
        nameEn: spell.nameEn || "",
        badge: spell.kindZh || TEXT.meansKind[spellKind],
        badgeColor: spellKind === "incantation" ? "amber" : "blue",
        mp: spell.mp,
        search: foldText((spell.nameZh || "") + " " + (spell.nameEn || ""))
      });
    });
    return items;
  }

  // 法术的类别：spells[].kind 只有 sorcery / incantation 两种，认不出的按魔法（与施法器口径一致）。
  function spellKindOf(spell) {
    return spell && spell.kind === "incantation" ? "incantation" : "sorcery";
  }

  // 一条输出手段落在类型开关的哪一档：战技 → skill；法术条目按 spellKind（没有就看条目自己的 kind，
  // 即原始 spells[].kind）分成 sorcery / incantation。
  function meansKindOf(item) {
    if (!item || item.kind === "skill") return "skill";
    return (item.spellKind || item.kind) === "incantation" ? "incantation" : "sorcery";
  }

  // 类型开关的取值规整：只认三档，其余（含旧的二档取值 spell）回落到默认的「战技」。
  function normalizeMeansKind(kind) {
    return MEANS_KINDS.indexOf(kind) !== -1 ? kind : "skill";
  }

  // kind：skill / sorcery / incantation 只出对应一档；兼容旧的二档取值 spell（＝魔法＋祷告）；
  // 不给（或认不出）就不按类别过滤。
  function filterMeans(items, query, kind) {
    var folded = foldText(query).trim();
    return (items || []).filter(function (item) {
      var itemKind = meansKindOf(item);
      if (kind === "spell") {
        if (itemKind === "skill") return false;
      } else if (MEANS_KINDS.indexOf(kind) !== -1 && itemKind !== kind) {
        return false;
      }
      if (!folded) return true;
      return item.search.indexOf(folded) !== -1;
    });
  }

  // ---- 说明区（结论简述；条数照数据现算）--------------------------------

  // 「提升战技攻击力」类的子类别，从数据现算：appliesTo 为 skill=conditional、sorcery=no、incantation=no 的
  // requires.subCategoriesAny 里，没有在任何法术、近战普通攻击、弓弩射击命中段出现过的那些子类别
  // （attackIndex 的人口统计）。按编号降序，中文名取 enums.atkSubCategory。
  function skillOnlySubCategories(buffsData) {
    var idx = (buffsData && buffsData.attackIndex) || {};
    var seen = {};
    Object.keys(idx.spells || {}).forEach(function (id) {
      ((idx.spells[id] || {}).subCategorySets || []).forEach(function (set) {
        ((set && set.subs) || []).forEach(function (sub) { seen[sub] = true; });
      });
    });
    ["melee", "ranged"].forEach(function (population) {
      (idx[population] || []).forEach(function (row) {
        ((row && row.subs) || []).forEach(function (sub) { seen[sub] = true; });
      });
    });
    var found = {};
    ((buffsData && buffsData.buffs) || []).forEach(function (buff) {
      var applies = buff.appliesTo || {};
      if (applies.skill !== "conditional" || applies.sorcery !== "no" || applies.incantation !== "no") return;
      var detail = (buff.appliesToDetail || {}).skill || {};
      var subs = detail.requires && Array.isArray(detail.requires.subCategoriesAny) ? detail.requires.subCategoriesAny : [];
      if (!subs.length || subs.some(function (sub) { return seen[sub]; })) return;
      subs.forEach(function (sub) { found[sub] = true; });
    });
    var names = (buffsData && buffsData.enums && buffsData.enums.atkSubCategory) || {};
    return Object.keys(found).map(Number).sort(function (a, b) { return b - a; }).map(function (sub) {
      var one = names[String(sub)];
      return sub + (one && one.zh ? " " + one.zh : "");
    });
  }

  // 说明区（两端同一顺序、同一文案，数字照数据现算）。
  function briefNotes(buffsData, cfgIndex) {
    var rules = (buffsData && buffsData.slotRules) || {};
    var wa = rules.weaponAffix || {};
    var deepCaps = slotCaps(rules, "deep");
    var dupStatus = (wa.duplicateWithinWeapon && wa.duplicateWithinWeapon.status) || "unknown";
    var entries = (cfgIndex && cfgIndex.index && cfgIndex.index.entries) || [];
    var stackTexts = [];
    entries.forEach(function (entry) {
      var si = entry.stackInput;
      if (!si) return;
      var text = "";
      if (si.mode === "ladder") {
        var tiers = Array.isArray(si.tierMultipliers) ? si.tierMultipliers : [];
        text = fmt(TEXT.briefStack.ladder, fmtNumber(si.perStackRatio, 4), stackParamMax(entry));
        if (typeof si.practicalMaxStacks === "number" && si.practicalMaxStacks > 0 && tiers.length) {
          text += fmt(TEXT.briefStack.practical, si.practicalMaxStacks,
            fmtNumber(tiers[Math.min(si.practicalMaxStacks, tiers.length) - 1], 4));
        }
      } else {
        text = fmt(TEXT.briefStack.copies, fmtNumber(si.perStackMultiplier, 4));
        if (isGraceStack(entry)) text += fmt(TEXT.briefStack.unit, TEXT.stackHintGrace);
      }
      stackTexts.push(fmt(TEXT.briefStack.item, entry.name, text));
    });
    var decreaseCount = entries.filter(function (entry) {
      return entry.countsAsDamage && entry.direction === "decrease";
    }).length;
    var variantGroups = (cfgIndex && cfgIndex.index && cfgIndex.index.variants) || {};
    var variantKeys = Object.keys(variantGroups);
    var variantMembers = variantKeys.reduce(function (sum, key) { return sum + variantGroups[key].length; }, 0);
    var catalogIndex = cfgIndex && cfgIndex.catalog;
    var cursePool = catalogIndex && catalogIndex.available ? catalogIndex.cursePoolId : null;
    var skillSubs = skillOnlySubCategories(buffsData);
    var notes = [
      TEXT.brief.appliesTo,
      TEXT.brief.formula,
      TEXT.brief.partial,
      fmt(TEXT.brief.direction, decreaseCount),
      TEXT.brief.target,
      TEXT.brief.activation,
      TEXT.brief.stacking
    ];
    if (variantKeys.length) notes.push(fmt(TEXT.brief.affixVariant, variantKeys.length, variantMembers));
    return notes.concat([
      TEXT.brief.tiers,
      fmt(TEXT.brief.deepWeapon, deepCaps.deepOnly, dupStatus),
      fmt(TEXT.brief.relic, cursePool == null ? TEXT.noData : cursePool),
      fmt(TEXT.brief.skillAttack, skillSubs.length ? skillSubs.join("／") : TEXT.noData),
      TEXT.brief.equipped,
      TEXT.brief.innate,
      fmt(TEXT.brief.runStack, stackTexts.join(TEXT.briefStack.separator) || TEXT.noData),
      TEXT.brief.fill,
      TEXT.brief.throwInferred
    ]);
  }

  // 文案常量表展开成「点号路径 → 文案」（两端逐键对照：macOS 端 LoadoutText.table 是同一张表）。
  function flattenText(node, prefix, out) {
    var target = out || {};
    Object.keys(node).forEach(function (key) {
      var value = node[key];
      var path = prefix ? prefix + "." + key : key;
      if (value && typeof value === "object") flattenText(value, path, target);
      else target[path] = String(value);
    });
    return target;
  }

  // ---- 双端对拍行（NR_RANKER_DUMP=1 时两端各自打印，逐行比）---------------

  function fixed9(value) {
    return (value == null ? 1 : value).toFixed(9);
  }

  // 一整套配置的对拍行：模式、总倍率、四栏小计、配置本身与计入条目（份数 >1 的写 ×n）。
  function configDumpLine(key, config, result) {
    var caps = result.caps;
    var relics = (config.relics || []).slice(0, caps.relics).map(function (card) {
      if (!card || card.type === "empty") return "-";
      if (card.type === "fixed") return card.key ? "F" + String(card.key).split("-")[0] : "-";
      return "C" + [0, 1, 2].map(function (row) {
        var affix = card.affixIds[row];
        var curse = card.curseIds[row];
        return (affix == null ? "-" : affix) + (curse == null ? "" : "/" + curse);
      }).join("+");
    }).join("|");
    var weaponAffixes = (config.weaponAffixes || []).slice().sort(function (a, b) { return a.id - b.id; })
      .map(function (one) { return one.id + "x" + one.count; }).join(",");
    var accessories = (config.accessories || []).slice(0, caps.accessory).filter(function (id) { return id != null; }).join(",");
    var counted = result.counted.slice().sort(function (a, b) { return a.entry.id - b.entry.id; }).map(function (item) {
      return item.entry.id + (item.countedCopies > 1 ? "x" + item.countedCopies : "");
    }).join(",");
    var subtotals = COLUMN_ORDER.map(function (column) {
      return column + ":" + fixed9(result.byColumn[column].multiplier);
    }).join(",");
    return "CONFIG " + key + " mode=" + config.runMode + " total=" + fixed9(result.total.multiplier) +
      " sub=" + subtotals + " weaponAffixes=" + weaponAffixes + " relics=" + relics +
      " accessories=" + accessories + " counted=" + counted;
  }

  // 一个输出手段的对拍行：选段、九类占比、一览里生效且 > 1 的条数与前 10 名。
  function caseDumpLine(key, selectedIds, comp, rows) {
    var useful = rows.filter(function (row) { return row.applicable && row.multiplier > USEFUL_EPSILON; });
    return "CASE " + key + " selected=" + selectedIds.join(",") +
      " shares=" + TYPE_KEYS.map(function (type) { return comp.shares[type].toFixed(9); }).join(",") +
      " applicable=" + rows.filter(function (row) { return row.applicable; }).length +
      " useful=" + useful.length +
      " top10=" + useful.slice(0, 10).map(function (row) { return row.entry.id + ":" + row.multiplier.toFixed(9); }).join(",");
  }

  // ---- 格式化 ----------------------------------------------------------

  function fmtPercent(value, digits) {
    var n = num(value) * 100;
    return n.toFixed(typeof digits === "number" ? digits : 1) + "%";
  }

  function fmtMultiplier(value) {
    if (value == null) return "—";
    return "×" + num(value).toFixed(3);
  }

  function fmtGain(value) {
    if (value == null) return "—";
    var n = (num(value) - 1) * 100;
    return (n >= 0 ? "+" : "") + n.toFixed(1) + "%";
  }

  function fmtNumber(value, digits) {
    var n = num(value);
    var fixed = n.toFixed(typeof digits === "number" ? digits : 1);
    return fixed.replace(/\.0+$/, "").replace(/(\.\d*?)0+$/, "$1");
  }

  // 攻击力加算带符号：正数写「+」，负数照常是「-」，四舍五入后为 0 写「0」。
  function fmtFlat(value, digits) {
    var text = fmtNumber(value, typeof digits === "number" ? digits : 1);
    if (/^-0(\.0*)?$/.test(text)) text = "0";
    return (num(value) > 0 && text !== "0" ? "+" : "") + text;
  }

  // 加算是否值得显示：四舍五入到一位小数后不为 0。
  function hasFlat(value) {
    return Math.abs(num(value)) >= 0.05;
  }

  function fmtDuration(seconds) {
    var n = num(seconds);
    if (n < 0) return "永久";
    if (n === 0) return "瞬间";
    return fmtNumber(n, 1) + " 秒";
  }

  function slotLabel(buffsData, slot) {
    var labels = (buffsData && buffsData.enums && buffsData.enums.sourceSlot) || {};
    return (labels[slot] && labels[slot].zh) || TEXT.otherGroups[slot] || TEXT.columns[slot] || slot;
  }

  // ================================================================ 渲染层

  var dom = null;
  var ctxRef = null;

  var state = {
    loaded: false,
    skillsData: null,
    buffsData: null,
    index: null,
    cfgIndex: null,
    catalogRef: null,
    means: [],
    meansKind: "skill",   // 类型开关当前档：skill / sorcery / incantation（MEANS_KINDS）
    meansQuery: "",
    selection: null,      // { kind, id, weaponId }
    hand: 1,
    noFp: false,
    hitOverrides: {},     // atkId → true/false
    config: emptyConfig(),
    contexts: {},         // 用户勾选的攻击情境
    showInactive: false,
    waFilter: "weapon",   // weapon / all
    waQuery: "",
    otherTab: "consumable",
    otherQuery: "",
    overviewQuery: "",
    overviewLimit: PAGE_SIZE,
    overviewOpen: false,
    flash: ""
  };

  function helpers() {
    return ctxRef && ctxRef.helpers ? ctxRef.helpers : null;
  }

  function coreRef() {
    return ctxRef && ctxRef.Core ? ctxRef.Core : null;
  }

  // 展示层统一口径：数据集原文里还留着英文的 FP，页面一律说中文的「专注值」。
  // 规则表顺序有意义：先认长的写法，最后才把剩下的孤零零 FP 换成「专注值」。
  var FP_TEXT_RULES = [
    [/无\s*FP\s*版/g, "专注值不足版"],
    [/\s*[Nn]o\s*FP(?:\s*版)?/g, "专注值不足版"],
    [/带\s*FP(?:\s*版)?/g, "正常版"],
    [/FP/g, "专注值"]
  ];

  function zhFpText(value) {
    var text = String(value == null ? "" : value);
    if (text.indexOf("FP") === -1) return text;
    FP_TEXT_RULES.forEach(function (rule) { text = text.replace(rule[0], rule[1]); });
    return text;
  }

  function esc(value) {
    var h = helpers();
    if (h && typeof h.escapeHtml === "function") return h.escapeHtml(value);
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (char) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[char];
    });
  }

  // 数据集原文用 Markdown 的 **粗体** 标记重点；转义后再把成对的 ** 换成 <strong>，
  // 否则页面会把星号原样显示出来。
  function strongHtml(text) {
    var parts = esc(text).split("**");
    if (parts.length < 3) return parts.join("**");
    return parts.map(function (part, index) {
      if (index === parts.length - 1 && index % 2 === 1) return "**" + part;
      return index % 2 === 1 ? "<strong>" + part + "</strong>" : part;
    }).join("");
  }

  function pill(text, kind) {
    var h = helpers();
    if (h && typeof h.pill === "function") return h.pill(text, kind);
    return "<span class='pill pill--" + (kind || "purple") + "'>" + esc(text) + "</span>";
  }

  var STATE_COLOR = {
    counted: "green", duplicate: "gray", pending: "amber", context: "amber", neutral: "gray",
    no: "gray", zeroStacks: "amber", tierOff: "amber", variantOff: "gray", relicInvalid: "red", noDamage: "gray"
  };

  function statePill(stateKey) {
    return pill(TEXT.states[stateKey] || stateKey, STATE_COLOR[stateKey] || "gray");
  }

  // ---- 取当前选择 ------------------------------------------------------

  function currentSkill() {
    if (!state.selection || state.selection.kind !== "skill") return null;
    return (state.skillsData._skillById || {})[state.selection.id] || null;
  }

  function currentSpell() {
    if (!state.selection || state.selection.kind === "skill") return null;
    return (state.skillsData._spellById || {})[state.selection.id] || null;
  }

  function currentWeapon() {
    if (!state.selection || state.selection.kind !== "skill") return null;
    return (state.skillsData._weaponById || {})[state.selection.weaponId] || null;
  }

  function currentMode() {
    if (!state.selection) return "skill";
    return state.selection.kind;
  }

  function currentHits() {
    var skill = currentSkill();
    if (skill) return selectHits(skill, currentWeapon());
    var spell = currentSpell();
    if (spell) return invokedHits(spell.hits);
    return [];
  }

  // 默认：与「使用专注值不足版本」开关同侧的段全勾，另一侧全不勾，两侧共用的 fpBoth 段恒勾；
  // 用户手动勾选写进 overrides。
  function hitEnabled(hit) {
    if (!hit || hit.noDamage) return false;
    var override = state.hitOverrides[hit.atkId];
    if (override === true || override === false) return override;
    return hitOnSide(hit, state.noFp);
  }

  function selectedHits() {
    return currentHits().filter(hitEnabled);
  }

  function currentComposition() {
    return composition(selectedHits(), currentWeapon(), currentMode() !== "skill");
  }

  function currentOutput(comp) {
    var composed = comp || currentComposition();
    return makeOutput({
      mode: currentMode(),
      meansId: state.selection ? state.selection.id : null,
      weapon: currentWeapon(),
      hand: state.hand,
      shares: composed.shares,
      contexts: state.contexts
    }, state.buffsData);
  }

  function waFilterType(out) {
    if (state.waFilter === "all") return null;
    return outputWepType(out);
  }

  // ---- HTML 片段 -------------------------------------------------------

  function header() {
    return "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>" + esc(TEXT.pageTitle) + "</h1><p>" + esc(TEXT.pageSubtitle) + "</p></div>" +
      "</header>";
  }

  function unavailableShell(message) {
    return "<div class='page-content ranker-content'>" + header() +
      "<article class='card page-placeholder-card' data-testid='ranker-card'>" +
      "<div class='section-heading'><div class='section-icon'>⇗</div>" +
      "<div><h2>" + esc(TEXT.noData) + "</h2><p>" + esc(message) + "</p></div></div>" +
      "<div class='page-status-row'>" + pill(TEXT.noData, "amber") +
      "<span>缺少 resources/skills.json 或 resources/buffs.json</span></div>" +
      "<p class='data-hint'>源文件生成后运行仓库根的 scripts/sync-data.sh 同步到 windows/resources/ 与 " +
      "macOS 的 Resources/，两端都不需要改代码。</p>" +
      "</article></div>";
  }

  function shell() {
    return "<div class='page-content ranker-content'>" + header() +
      "<section class='card ranker-picker' data-testid='ranker-picker'></section>" +
      "<section class='card ranker-hits' data-testid='ranker-hits'></section>" +
      "<section class='card ranker-comp' data-testid='ranker-comp'></section>" +
      "<section class='card ranker-toolbar' data-testid='ranker-toolbar'></section>" +
      "<section class='card ranker-waffix' data-testid='ranker-waffix'></section>" +
      "<section class='card ranker-relics' data-testid='ranker-relics'></section>" +
      "<section class='card ranker-talismans' data-testid='ranker-talismans'></section>" +
      "<section class='card ranker-others' data-testid='ranker-others'></section>" +
      "<section class='card ranker-summary' data-testid='ranker-summary'></section>" +
      "<section class='card ranker-brief' data-testid='ranker-brief'></section>" +
      "<div data-testid='ranker-overview-slot'></div>" +
      "<div data-testid='ranker-footer'></div>" +
      "</div>";
  }

  // ---- 输出手段选择 ----------------------------------------------------

  function meansListHtml() {
    var list = filterMeans(state.means, state.meansQuery, state.meansKind);
    var shown = list.slice(0, PICKER_LIMIT);
    var rows = shown.map(function (item) {
      var active = state.selection && state.selection.kind === item.kind && state.selection.id === item.id;
      return "<button class='ranker-means-row" + (active ? " is-active" : "") + "' type='button' " +
        "data-ranker-means='" + esc(item.kind) + ":" + item.id + "'>" +
        "<span class='ranker-means-name'>" + esc(item.nameZh || item.nameEn) + "</span>" +
        "<span class='ranker-means-en'>" + esc(item.nameEn) + "</span>" +
        pill(item.badge, item.badgeColor) +
        (item.kind === "skill"
          ? "<span class='ranker-means-meta'>" + item.weaponCount + " 把武器</span>"
          : "<span class='ranker-means-meta'>专注值 " + esc(item.mp) + "</span>") +
        "</button>";
    }).join("");
    var more = list.length > shown.length
      ? "<p class='ranker-note'>共 " + list.length + " 条，先显示前 " + shown.length +
        " 条，请继续输入关键字缩小范围。</p>"
      : "";
    return (rows || "<p class='ranker-empty'>" + esc(TEXT.meansSearch.empty) + "</p>") + more;
  }

  // 类型开关三档（战技 / 魔法 / 祷告）的按钮，active 是当前档。
  function meansKindButtonsHtml(active) {
    return MEANS_KINDS.map(function (key) {
      var on = active === key;
      return "<button class='segment-button" + (on ? " is-active" : "") + "' type='button' role='radio' " +
        "aria-checked='" + (on ? "true" : "false") + "' data-ranker-means-kind='" + key + "'>" +
        esc(TEXT.meansKind[key]) + "</button>";
    }).join("");
  }

  function pickerHtml() {
    var kindButtons = meansKindButtonsHtml(state.meansKind);
    // 战技数据 schemaVersion < 3：照样渲染，但选段缺局内战技池与 TAE 核实，明确提示结果不可信。
    var schemaWarn = skillsSchemaWarning(state.skillsData);

    return "<div class='section-heading'><div class='section-icon'>◎</div>" +
      "<div><h2>输出手段</h2><p>" + esc(TEXT.meansCard.subtitle) + "</p></div></div>" +
      "<div class='ranker-picker-row'>" +
      "<div class='segmented-control ranker-means-kind' role='radiogroup' aria-label='输出手段类型' " +
      "data-testid='ranker-means-kind'>" + kindButtons + "</div>" +
      "<label class='search-field ranker-means-search'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='" + esc(TEXT.meansSearch.placeholder) + "' autocomplete='off' " +
      "data-testid='ranker-means-search'></label>" +
      "</div>" +
      "<div class='ranker-means-list' data-testid='ranker-means-list'>" + meansListHtml() + "</div>" +
      (schemaWarn ? "<p class='ranker-note ranker-note--warn' data-testid='ranker-skills-schema-warn'>" + esc(schemaWarn) + "</p>" : "") +
      "<div data-testid='ranker-weapon-block'>" + weaponPickerHtml() + "</div>";
  }

  function weaponStatsHtml(weapon) {
    if (!weapon) return "";
    var base = weapon.attackBase || {};
    var cells = ELEMENTS.map(function (element) {
      var label = element === "physical" ? "物理" : TYPE_INFO[element].zh;
      return "<div class='ranker-stat'><dt>" + esc(label) + "</dt><dd>" + fmtNumber(base[element], 1) + "</dd></div>";
    }).join("");
    return "<dl class='ranker-stat-row' data-testid='ranker-weapon-stats'>" + cells +
      "<div class='ranker-stat'><dt>物理攻击类型</dt><dd>" +
      esc(weapon.atkAttributeZh || "—") + " / " + esc(weapon.atkAttribute2Zh || "—") + "</dd></div>" +
      "<div class='ranker-stat'><dt>削韧基础</dt><dd>" + fmtNumber(weapon.poiseDamageBase, 1) + "</dd></div>" +
      "</dl>";
  }

  // 持武器的手：appliesToDetail.requires.hand 按它判定（法术同样占左右手之一）。
  function handButtonsHtml() {
    return [
      { key: 1, label: "右手" },
      { key: 2, label: "左手" }
    ].map(function (option) {
      var active = state.hand === option.key ? " is-active" : "";
      return "<button class='segment-button" + active + "' type='button' data-ranker-hand='" +
        option.key + "'>" + esc(option.label) + "</button>";
    }).join("");
  }

  function handControlHtml() {
    return "<div class='ranker-control'><span class='ranker-field-label'>武器槽</span>" +
      "<div class='segmented-control ranker-hand' role='radiogroup' aria-label='武器槽' " +
      "data-testid='ranker-hand'>" + handButtonsHtml() + "</div></div>";
  }

  function weaponPickerHtml() {
    if (!state.selection) {
      return "<p class='ranker-note' data-testid='ranker-selection'>尚未选择输出手段。</p>";
    }
    var mode = currentMode();
    if (mode !== "skill") {
      var spell = currentSpell();
      if (!spell) return "<p class='ranker-note'>找不到这条法术。</p>";
      return "<div class='ranker-selection' data-testid='ranker-selection'>" +
        "<div class='ranker-selection-name'>" + esc(spell.nameZh || spell.nameEn) +
        "<span class='ranker-means-en'>" + esc(spell.nameEn) + "</span></div>" +
        "<div class='ranker-selection-pills'>" +
        pill(spell.kindZh || TEXT.meansKind[spellKindOf(spell)], spellKindOf(spell) === "incantation" ? "amber" : "blue") +
        pill("专注值 " + spell.mp, "gray") + pill(TEXT.meansSpellFlatNote, "gray") + "</div>" +
        "<div class='ranker-picker-row'>" + handControlHtml() + "</div>" +
        "<p class='ranker-note'>法术没有武器动作套：按 usage「法术 / 子弹段」只取每段的固定伤害值（flat），" +
        "不把 motion 乘到施法器攻击力上。武器槽用于匹配 appliesTo 的 requires.hand——" +
        "施法器同样占左右手之一；武器词条栏按" + esc(mode === "incantation" ? "圣印记" : "手杖") + "的类别过滤。</p></div>";
    }
    var skill = currentSkill();
    if (!skill) return "<p class='ranker-note'>找不到这个战技。</p>";
    var weapons = weaponsForSkill(state.skillsData, skill);
    var sources = weaponSourceMap(skill);
    var groups = groupWeapons(weapons, skill);
    var options = groups.map(function (group) {
      return "<optgroup label='" + esc(group.label) + "'>" + group.weapons.map(function (weapon) {
        var selected = weapon.id === state.selection.weaponId ? " selected" : "";
        var source = weaponSourceOf(skill, weapon, sources);
        return "<option value='" + weapon.id + "'" + selected +
          (source === "pool" ? " title='" + esc(TEXT.weaponSource.poolHint) + "'" : "") + ">" +
          esc(weaponOptionLabel(weapon, source)) + "</option>";
      }).join("") + "</optgroup>";
    }).join("");
    var weapon = currentWeapon();
    var sourceCount = { fixed: 0, pool: 0 };
    weapons.forEach(function (one) {
      var source = weaponSourceOf(skill, one, sources);
      if (source) sourceCount[source] += 1;
    });

    return "<div class='ranker-selection' data-testid='ranker-selection'>" +
      "<div class='ranker-selection-name'>" + esc(skill.nameZh || skill.nameEn) +
      "<span class='ranker-means-en'>" + esc(skill.nameEn) + "</span></div>" +
      "<div class='ranker-selection-pills'>" + pill(TEXT.meansKind.skill, "purple") +
      pill(weapons.length + " 把武器可用", "gray") +
      (sourceCount.fixed ? pill(TEXT.weaponSource.fixed + " " + sourceCount.fixed, "gray") : "") +
      (sourceCount.pool ? pill(TEXT.weaponSource.pool + " " + sourceCount.pool, "gray") : "") +
      (skill.sparring ? pill("训练场可用", "green") : "") + "</div>" +
      "<div class='ranker-picker-row'>" +
      "<label class='select-field ranker-weapon-field'><span class='ranker-field-label'>武器</span>" +
      "<select data-testid='ranker-weapon'" + (options ? "" : " disabled") + ">" +
      (options || "<option>这个战技没有可用武器</option>") + "</select></label>" +
      weaponSourceBadgeHtml(skill, weapon, sources) +
      handControlHtml() +
      "</div>" +
      (weapons.length ? "<p class='ranker-note' data-testid='ranker-weapon-source-note'>" + esc(TEXT.weaponSource.note) + "</p>" : "") +
      weaponStatsHtml(weapon) + "</div>";
  }

  // 下拉选项的文字：名称（稀有度）· 来源标记（固定战技 / 局内可抽到；两者都成立时只标固定）。
  function weaponOptionLabel(weapon, source) {
    var text = (weapon.nameZh || weapon.nameEn || ("#" + weapon.id)) + "（" + (weapon.rarityZh || "") + "）";
    if (source === "fixed") return text + " · " + TEXT.weaponSource.fixed;
    if (source === "pool") return text + " · " + TEXT.weaponSource.pool;
    return text;
  }

  // 当前武器的来源标记（下拉旁的小标签，局内可抽到的悬停给出说明）。
  function weaponSourceBadgeHtml(skill, weapon, sources) {
    var source = weaponSourceOf(skill, weapon, sources);
    if (source === "fixed") {
      return "<span class='ranker-weapon-source' data-testid='ranker-weapon-source' data-source='fixed'>" +
        pill(TEXT.weaponSource.fixed, "green") + "</span>";
    }
    if (source === "pool") {
      return "<span class='ranker-weapon-source' data-testid='ranker-weapon-source' data-source='pool' title='" +
        esc(TEXT.weaponSource.poolHint) + "'>" + pill(TEXT.weaponSource.pool, "blue") + "</span>";
    }
    return "";
  }

  // ---- 分段命中 --------------------------------------------------------

  function hitDamageHtml(hit, weapon, isSpell) {
    var plan = hitChipPlan(hit, weapon, isSpell);
    var cells = plan.chips.map(function (chip) {
      var label = TYPE_INFO[chip.type].zh;
      var parts = [];
      if (chip.motion !== null) parts.push(fmtNumber(chip.motion, 0) + "%");
      if (chip.flat !== null) parts.push("固定 " + fmtNumber(chip.flat, 0));
      if (chip.baseAttack !== null) parts.push("+基础攻击力");
      return "<span class='ranker-hit-el ranker-hit-el--" + esc(chip.type) + "'>" +
        esc(label) + " " + esc(parts.join(" · ")) + "</span>";
    });
    if (!cells.length) return "<span class='ranker-hit-el ranker-hit-el--none'>无伤害数值</span>";
    if (plan.hidden) cells.push("<span class='ranker-hit-el-note'>其余属性该武器为 0</span>");
    return cells.join("");
  }

  // 分段列表下的一句来源说明：命中段是否按 TAE 动画事件核实过（数据 counts.taeVerified、skills[].taeUnmatched）。
  function taeNote(skill) {
    var counts = (state.skillsData && state.skillsData.counts) || {};
    if (!skill || counts.taeVerified !== true) return "";
    if (skill.taeUnmatched === true) {
      return "这个战技的动画匹配不到（弓系战技，伤害走箭矢），命中段没有经 TAE 过滤。";
    }
    return "命中段已按 TAE 动画事件核实：参数表里有、但本作动画打不出的段不列出（依据见页面底部「命中段已按 TAE 核实」）。";
  }

  function hitsHtml() {
    var hits = currentHits();
    var weapon = currentWeapon();
    var isSpell = currentMode() !== "skill";
    var skill = currentSkill();

    if (!state.selection) {
      return "<div class='section-heading'><div class='section-icon'>≡</div>" +
        "<div><h2>分段命中</h2><p>先在上面选一个战技或法术</p></div></div>" +
        "<p class='ranker-empty' data-testid='ranker-hits-empty'>尚未选择输出手段。</p>";
    }
    if (!hits.length) {
      var why = skill
        ? "按 usage 的选段规则，这把武器在这个战技上没有任何命中段（weapons[].skillVariants 里没有这个战技）。"
        : "这条法术没有带数值的命中段。";
      return "<div class='section-heading'><div class='section-icon'>≡</div>" +
        "<div><h2>分段命中</h2><p>这把武器打不出任何段</p></div></div>" +
        "<p class='ranker-empty' data-testid='ranker-hits-empty'>" + esc(why) + "</p>";
    }

    var hasNoFp = hits.some(function (hit) { return hit.noFp === true; });
    var onCount = hits.filter(hitEnabled).length;
    var variant = skill ? selectVariant(skill, weapon) : null;

    var rows = hits.map(function (hit) {
      var disabled = hit.noDamage === true;
      var on = hitEnabled(hit);
      var marks = [];
      if (hit.noFp) marks.push(pill("专注值不足版", "amber"));
      if (hit.fpBoth) {
        marks.push("<span title='正常版与专注值不足版的动画都会打出这一段（数据 hits[].fpBoth，按 TAE 标出），开关在哪一侧都计入'>" +
          pill("两版共用", "gray") + "</span>");
      }
      if (hit.isBullet) marks.push(pill("子弹", "blue"));
      if (hit.noDamage) marks.push(pill("只挂状态", "gray"));
      if (hit.addBaseAtk) marks.push(pill("额外加一份攻击力", "purple"));
      if (hit.overrideAecId) marks.push(pill("改用补正表 " + hit.overrideAecId, "gray"));
      return "<label class='ranker-hit-row" + (on ? " is-on" : "") + (disabled ? " is-disabled" : "") + "'>" +
        "<input type='checkbox' data-ranker-hit='" + hit.atkId + "'" +
        (on ? " checked" : "") + (disabled ? " disabled" : "") + ">" +
        "<span class='ranker-hit-name'>" + esc(zhFpText(hit.labelZh) || hit.label || ("段 " + hit.atkId)) +
        "<span class='ranker-hit-id'>#" + hit.atkId + "</span></span>" +
        "<span class='ranker-hit-damage'>" + hitDamageHtml(hit, weapon, isSpell) + "</span>" +
        "<span class='ranker-hit-poise' title='削韧：对敌人韧性（削韧槽）的削减量；削精力：对格挡中敌人精力条的削减量（武器基础精力伤害 × 动作值），与角色自己的精力无关'>削韧 " + fmtNumber(hitPoise(hit, weapon), 1) +
        " · 削精力 " + fmtNumber(hitStamina(hit, weapon), 1) + "</span>" +
        "<span class='ranker-hit-marks'>" + marks.join("") + "</span></label>";
    }).join("");

    var toolbar = "<div class='ranker-hits-toolbar'>" +
      "<button class='button button--ghost' type='button' data-ranker-hits='all' " +
      "title='只勾当前这一侧的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍（两版共用的段两侧都勾）'>" +
      "全选（当前版本）</button>" +
      "<button class='button button--ghost' type='button' data-ranker-hits='none'>全不选</button>" +
      "<button class='button button--ghost' type='button' data-ranker-hits='reset'>恢复默认</button>" +
      (hasNoFp
        ? "<label class='switch-control ranker-nofp' " +
          "title='没蓝时打出的弱化版战技：正常版与专注值不足版互斥，这里整体切换'>" +
          "<input type='checkbox' data-testid='ranker-nofp'" +
          (state.noFp ? " checked" : "") + "><span class='switch-track'></span>" +
          "<span>使用专注值不足版本</span></label>"
        : "") +
      "<span class='ranker-hits-count' data-testid='ranker-hits-count'>已勾选 " + onCount +
      " / " + hits.length + " 段</span></div>";

    var variantNote = variant
      ? "<p class='ranker-note'>动作套：" + esc(variant.ctxZh || variant.ctx || "默认") +
        "（来源 " + esc(variant.via === "behavior" ? "BehaviorParam_PC 实解" : "按 ctx 单选") +
        "，共 " + variant.atkIds.length + " 段）。" + esc(taeNote(skill)) + "</p>"
      : "";

    return "<div class='section-heading'><div class='section-icon'>≡</div>" +
      "<div><h2>分段命中</h2><p>勾掉不打的段即可（例如只算刀气那一段）</p></div></div>" +
      toolbar + variantNote +
      "<div class='ranker-hit-list' data-testid='ranker-hit-list'>" + rows + "</div>";
  }

  // ---- 伤害构成 --------------------------------------------------------

  function compositionHtml(comp) {
    var heading = "<div class='section-heading'><div class='section-icon'>▤</div>" +
      "<div><h2>伤害构成</h2><p>勾选段的相对占比，用来给每条增益加权</p></div></div>";
    if (!comp.hasDamage) {
      return heading + "<p class='ranker-empty' data-testid='ranker-comp-empty'>" +
        "当前没有勾选任何带伤害的段，无法计算构成。</p>";
    }
    var active = TYPE_KEYS.filter(function (key) { return comp.shares[key] > 0; });
    var offset = 0;
    var bars = active.map(function (key) {
      var width = comp.shares[key] * 100;
      var rect = "<rect class='ranker-bar-seg ranker-bar-seg--" + key + "' x='" +
        offset.toFixed(4) + "' y='0' width='" + Math.max(width, 0.01).toFixed(4) + "' height='10'></rect>";
      offset += width;
      return rect;
    }).join("");

    var legend = active.map(function (key) {
      return "<div class='ranker-legend-item' data-ranker-type='" + key + "'>" +
        "<span class='ranker-swatch ranker-swatch--" + key + "' aria-hidden='true'></span>" +
        "<span class='ranker-legend-name'>" + esc(TYPE_INFO[key].zh) + "</span>" +
        "<span class='ranker-legend-value'>" + fmtPercent(comp.shares[key]) + "</span>" +
        "<span class='ranker-legend-raw'>" + fmtNumber(comp.parts[key], 1) + "</span>" +
        "</div>";
    }).join("");

    var physShare = TYPES_BY_ELEMENT.physical.reduce(function (sum, key) {
      return sum + comp.shares[key];
    }, 0);

    var boundary = (state.skillsData.usage && state.skillsData.usage["本数据集的边界"]) || "";

    return heading +
      "<svg class='ranker-bar' viewBox='0 0 100 10' preserveAspectRatio='none' role='img' " +
      "aria-label='伤害构成条形图' data-testid='ranker-bar'>" + bars + "</svg>" +
      "<div class='ranker-legend' data-testid='ranker-legend'>" + legend + "</div>" +
      "<div class='page-status-row'>" +
      pill("物理合计 " + fmtPercent(physShare), "gray") +
      pill("属性合计 " + fmtPercent(1 - physShare), "gray") +
      pill("相对值合计 " + fmtNumber(comp.total, 1), "gray") + "</div>" +
      "<p class='ranker-note ranker-note--warn' data-testid='ranker-comp-note'>" +
      "这里只是<strong>相对构成</strong>：不含强化等级、亲和、能力值补正与 AttackElementCorrectParam，" +
      "绝对伤害不在本页范围。</p>" +
      (boundary
        ? "<p class='ranker-quote'><span class='ranker-quote-label'>数据集说明 · 本数据集的边界</span>" +
          strongHtml(boundary) + "</p>"
        : "");
  }

  // ---- 配置工具条（常规／深夜、情境、开关、按钮、总倍率速览）-----------------

  function toolbarHtml(out, result) {
    var caps = slotCaps(state.cfgIndex.slotRules, state.config.runMode);
    var normalCaps = slotCaps(state.cfgIndex.slotRules, "normal");
    var deepCaps = slotCaps(state.cfgIndex.slotRules, "deep");
    var modeButtons = ["normal", "deep"].map(function (key) {
      var active = state.config.runMode === key ? " is-active" : "";
      return "<button class='segment-button" + active + "' type='button' data-ranker-runmode='" + key + "'>" +
        esc(TEXT.runMode[key]) + "</button>";
    }).join("");
    var contexts = availableContexts(state.buffsData, (state.index && state.index.entries) || [], out.mode);
    var chips = contexts.map(function (item) {
      var on = state.contexts[item.key] === true;
      return "<button class='ranker-chip ranker-chip--context" + (on ? " is-on" : "") + "' type='button' " +
        "data-ranker-context='" + esc(item.key) + "' aria-pressed='" + (on ? "true" : "false") + "'>" +
        esc(item.zh) + "<span class='ranker-chip-count'>" + item.count + "</span></button>";
    }).join("");
    var slots = result.slots;
    var quick = "<div class='ranker-quick' data-testid='ranker-quick'>" +
      "<div class='ranker-quick-total'><span>" + esc(TEXT.summaryTotal) + "</span><strong data-testid='ranker-quick-total'>" +
      esc(fmtMultiplier(result.total.multiplier)) + "</strong><em>" + esc(fmtGain(result.total.multiplier)) + "</em></div>" +
      pill(TEXT.usageWeaponAffix + " " + slots.weaponAffix.used + "/" + slots.weaponAffix.cap, "purple") +
      (caps.deepOnly ? pill(TEXT.usageDeepOnly + " " + slots.weaponAffix.deepOnlyUsed + "/" + slots.weaponAffix.deepOnlyCap, "purple") : "") +
      pill(TEXT.usageRelic + " " + slots.relic.used + "/" + slots.relic.cap, "blue") +
      pill(TEXT.usageAccessory + " " + slots.accessory.used + "/" + slots.accessory.cap, "blue") +
      "</div>";
    return "<div class='ranker-toolbar-row'>" +
      "<div class='ranker-control'><span class='ranker-field-label'>" + esc(TEXT.runModeLabel) + "</span>" +
      "<div class='segmented-control ranker-runmode' role='radiogroup' aria-label='" + esc(TEXT.runModeAria) + "' data-testid='ranker-runmode'>" +
      modeButtons + "</div></div>" +
      quick +
      "<div class='ranker-toolbar-actions'>" +
      "<label class='switch-control' title='" + esc(TEXT.showInactiveHelp) + "'><input type='checkbox' data-testid='ranker-show-inactive'" +
      (state.showInactive ? " checked" : "") + "><span class='switch-track'></span><span>" +
      esc(TEXT.showInactive) + "</span></label>" +
      "<button class='button button--primary' type='button' data-testid='ranker-fill'" +
      (out.hasComposition ? "" : " disabled") + " title='" + esc(TEXT.fillNote) + "'>" + esc(TEXT.fillButton) + "</button>" +
      "<button class='button button--ghost' type='button' data-testid='ranker-clear'>" + esc(TEXT.clearButton) + "</button>" +
      "</div></div>" +
      "<p class='ranker-note'>" + esc(fmt(TEXT.runModeHint, normalCaps.weaponAffix, normalCaps.relics,
        deepCaps.weaponAffix, deepCaps.deepOnly, deepCaps.relics, deepCaps.relicNormal, deepCaps.relicDeep)) + "</p>" +
      (chips
        ? "<div class='ranker-context-block' data-testid='ranker-contexts'><div class='ranker-field-label'>" +
          esc(TEXT.contextsLabel) + "</div><div class='ranker-chip-row'>" + chips + "</div></div>"
        : "") +
      (state.flash ? "<p class='ranker-note ranker-note--ok' data-testid='ranker-flash'>" + esc(state.flash) + "</p>" : "") +
      (num(state.buffsData && state.buffsData.schemaVersion) < 6
        ? "<p class='ranker-note ranker-note--warn' data-testid='ranker-schema-warn'>" +
          esc(fmt(TEXT.schemaTooOld, state.buffsData && state.buffsData.schemaVersion)) + "</p>"
        : "");
  }

  // ---- 通用小片段 ------------------------------------------------------

  // 当前倍率；条件成立时的倍率与当前不同就在下面补一行（与 macOS 候选行同一口径）。
  function scoreHtml(score, stateKey, hasComposition, flat, potential, oneStack) {
    if (!hasComposition) return "<span class='ranker-score is-muted'>—</span>";
    var cls = stateKey === "counted" ? "" : " is-muted";
    var extra = typeof potential === "number" && Math.abs(potential - (score == null ? 1 : score)) > 1e-7
      ? "<small class='is-potential'>" + esc(fmt(oneStack ? TEXT.potentialOneStack : TEXT.potentialText, fmtMultiplier(potential))) + "</small>"
      : "";
    return "<span class='ranker-score" + cls + "'>" + esc(fmtMultiplier(score)) + extra +
      (hasFlat(flat) ? "<small>" + esc(fmt(TEXT.flatInline, fmtFlat(flat))) + "</small>" : "") + "</span>";
  }

  function shortText(text, max) {
    var value = String(text == null ? "" : text);
    return value.length > max ? value.slice(0, max) + "…" : value;
  }

  function reasonHtml(reasons) {
    if (!reasons || !reasons.length) return "";
    return "<span class='ranker-reason'>" + esc(reasons.join("；")) + "</span>";
  }

  function entryBadges(entry) {
    var badges = "";
    if (entry.activation === "conditional") badges += pill(TEXT.badges.conditional, "amber");
    if (entry.activation === "activated") badges += pill(TEXT.badges.activated, "amber");
    if (entry.stackInput) badges += pill(entry.stackInput.mode === "copies" ? TEXT.badges.copies : TEXT.badges.ladder, "amber");
    if (entry.accLadder) badges += pill(TEXT.badges.accLadder, "amber");
    if (entry.variantGroup) badges += pill(TEXT.badges.variant, "amber");
    if (entry.inferred) badges += pill(TEXT.badges.inferredSource, "gray");
    if (entry.pairRole === "ally") badges += pill(TEXT.badges.allyPair, "gray");
    else if (entry.target === "ally") badges += pill(TEXT.badges.ally, "blue");
    return badges;
  }

  // 一条已放进配置的增益的控件（汇总与遗物卡共用）：叠层填层数、累积阶梯选层、多档词条选档、
  // 占槽位的栏里的条件型勾「条件成立」。不占槽位的「其它增益」栏勾选本身就是确认，不再给勾选框。
  function itemControlsHtml(item) {
    var entry = item.entry;
    var controls = "";
    if (item.state === "no" || item.state === "context" || item.state === "relicInvalid" || item.state === "noDamage") return "";
    if (entry.stackInput) controls += stackControlHtml(entry, item.stacks);
    if (entry.accLadder && ladderOwner(item)) controls += tierControlHtml(entry);
    if (entry.variantGroup && item.state !== "variantOff") controls += variantControlHtml(entry);
    if (item.needs.length && !item.autoConfirm) {
      controls += "<label class='ranker-tick' title='" + esc(TEXT.summaryTickHelp + "：" + item.needs.join("；")) + "'>" +
        "<input type='checkbox' data-ranker-tick='" + entry.id + "'" + (item.ticked ? " checked" : "") + "><span>" +
        esc(TEXT.summaryTick) + "</span></label>";
    }
    return controls;
  }

  // 累积阶梯的选层控件只放在一行上：有计入的那一层就放在那一层，否则放在第 1 层（与 macOS 同一口径）。
  function ladderOwner(item) {
    var entry = item.entry;
    if (!entry.accLadder) return false;
    var picked = state.config.tiers ? state.config.tiers[entry.ladderGroup] : undefined;
    var members = ladderMembers(state.cfgIndex.ladders, entry.ladderGroup);
    if (members.some(function (member) { return member.id === picked; })) return picked === entry.id;
    return members.length ? members[0].id === entry.id : true;
  }

  // 某一处列出的条目：未选的档（variantOff）不列，累积阶梯没选层时只留放选层控件的那一行。
  function visibleItems(items) {
    return items.filter(function (item) {
      if (item.state === "variantOff" || item.state === "noDamage") return false;
      if (item.state === "tierOff") return ladderOwner(item);
      return true;
    });
  }

  // 移除按钮：按来源键（wa:<词条> / relic:<格>[:<行>] / acc:<格> / innate:<id> / other:<行键>）。
  function removeButtonsHtml(item) {
    return (item.keys || []).map(function (key, i) {
      return "<button type='button' class='button button--ghost ranker-remove' data-ranker-remove='" + esc(key) + "' title='" +
        esc(item.labels[i] || item.labels[0] || "") + "'>" + esc(key.indexOf("innate:") === 0 ? TEXT.innateRemove : TEXT.summaryRemove) + "</button>";
    }).join("");
  }

  // ---- 武器词条栏 ------------------------------------------------------

  // 同一词条（行名去掉「 - Potency N」后相同）的另一个档位也选了：按独立键相乘，标「参数推断，未实测」。
  function weaponAffixFamilyKey(affix) {
    var param = String(affix.paramName || "").trim();
    if (param) return "param:" + param.replace(/\s*-\s*Potency\s*\d+\s*$/i, "");
    return "zh:" + affix.nameZh;
  }

  function selectedTierFamilies(cfgIndex, config) {
    var families = {};
    (config.weaponAffixes || []).forEach(function (one) {
      var affix = cfgIndex.weaponAffixById[one.id];
      if (!affix || !(one.count > 0)) return;
      var key = weaponAffixFamilyKey(affix);
      if (!families[key]) families[key] = [];
      families[key].push(affix.id);
    });
    return Object.keys(families).map(function (key) { return families[key].sort(function (a, b) { return a - b; }); })
      .filter(function (ids) { return ids.length > 1; })
      .sort(function (a, b) { return a[0] - b[0]; });
  }

  function waffixListHtml(out) {
    var filterType = waFilterType(out);
    var rows = weaponAffixRows(state.cfgIndex, out, state.config, filterType);
    var tierSiblings = {};
    selectedTierFamilies(state.cfgIndex, state.config).forEach(function (ids) {
      ids.forEach(function (id) { tierSiblings[id] = true; });
    });
    var query = foldText(state.waQuery).trim();
    var shown = rows.filter(function (row) {
      if (row.count > 0) return true;
      if (!state.showInactive && !rowUseful(row, out.hasComposition)) return false;
      if (query && row.affix.search.indexOf(query) === -1 && foldText(row.affix.nameZh).indexOf(query) === -1) return false;
      return true;
    });
    if (!shown.length) return "<p class='ranker-empty'>" + esc(TEXT.waEmpty) + "</p>";
    return shown.map(function (row) {
      var affix = row.affix;
      var badges = "";
      if (affix.potency) badges += pill(fmt(TEXT.badges.potency, affix.potency), "gray");
      if (affix.deepOnlyPositive) badges += pill(TEXT.badges.deepOnly, "purple");
      if (affix.roles.indexOf("blessing") !== -1) badges += pill(TEXT.badges.blessing, "blue");
      if (affix.roles.indexOf("fixed") !== -1) badges += pill(TEXT.badges.fixed, "gray");
      if (row.outsideFilter) badges += pill(TEXT.badges.outsideWeaponType, "amber");
      if (tierSiblings[affix.id]) badges += pill(TEXT.badges.inferredTiers, "amber");
      var first = affix.entries[0];
      if (first) badges += entryBadges(first);
      return "<div class='ranker-row" + (row.applicable ? "" : " is-inactive") + (row.count ? " is-picked" : "") +
        "' data-ranker-wa-row='" + affix.id + "'>" +
        "<div class='ranker-row-main'><span class='ranker-row-name'>" + esc(affix.nameZh) + "</span>" +
        "<span class='ranker-row-badges'>" + badges + "</span>" +
        (row.state !== "counted" ? reasonHtml(row.reasons) : "") + "</div>" +
        scoreHtml(row.score, row.state, out.hasComposition, row.flat, row.potential, row.assumesOneStack) +
        "<div class='ranker-stepper' role='group' aria-label='" + esc(TEXT.stepperAria) + "'>" +
        "<button type='button' class='ranker-step' data-ranker-wa-step='" + affix.id + ":-1'" +
        (row.count > 0 ? "" : " disabled") + " aria-label='" + esc(TEXT.stepDown) + "'>−</button>" +
        "<span class='ranker-step-count' data-testid='ranker-wa-count-" + affix.id + "'>" + row.count + "</span>" +
        "<button type='button' class='ranker-step' data-ranker-wa-step='" + affix.id + ":1'" +
        (row.can.ok ? "" : " disabled title='" + esc(row.can.reason) + "'") + " aria-label='" + esc(TEXT.stepUp) + "'>＋</button>" +
        "</div></div>";
    }).join("");
  }

  function waffixHtml(out, result) {
    var usage = result.slots.weaponAffix;
    var wepType = outputWepType(out);
    var filterButtons = [
      { key: "weapon", label: wepType == null ? TEXT.waFilterNone : fmt(TEXT.waFilterWeapon, wepTypeLabel(out, wepType)) },
      { key: "all", label: TEXT.waFilterAll }
    ].map(function (option) {
      var active = state.waFilter === option.key ? " is-active" : "";
      return "<button class='segment-button" + active + "' type='button' data-ranker-wa-filter='" + option.key + "'>" +
        esc(option.label) + "</button>";
    }).join("");
    var copiesNote = result.items.some(function (item) {
      return item.column === "weaponAffix" && item.copies > 1;
    }) ? "<p class='ranker-note ranker-note--warn'>" + esc(TEXT.waCopiesHint) + "</p>" : "";
    var tierNote = selectedTierFamilies(state.cfgIndex, state.config).length
      ? "<p class='ranker-note ranker-note--muted'>" + esc(TEXT.waTierHint) + "</p>" : "";
    return "<div class='section-heading'><div class='section-icon'>⚔</div>" +
      "<div><h2>" + esc(TEXT.columns.weaponAffix) + "</h2><p>" + esc(fmt(TEXT.waIntro, result.caps.maxWeapons)) + "</p></div>" +
      "<div class='ranker-heading-pills'>" +
      pill(fmt(TEXT.waUsage, usage.used, usage.cap), usage.used >= usage.cap ? "amber" : "purple") +
      (usage.deepOnlyCap ? pill(fmt(TEXT.waDeepOnlyUsage, usage.deepOnlyUsed, usage.deepOnlyCap),
        usage.deepOnlyUsed >= usage.deepOnlyCap ? "amber" : "purple") : "") +
      "</div></div>" +
      "<div class='ranker-filter-row'>" +
      "<div class='segmented-control ranker-wa-filter' role='radiogroup' aria-label='" + esc(TEXT.waFilterAria) + "' data-testid='ranker-wa-filter'>" +
      filterButtons + "</div>" +
      "<label class='search-field ranker-list-search'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='" + esc(TEXT.waSearch) + "' autocomplete='off' data-testid='ranker-wa-search'></label>" +
      "</div>" + copiesNote + tierNote +
      "<div class='ranker-list' data-testid='ranker-wa-list'>" + waffixListHtml(out) + "</div>";
  }

  // ---- 遗物栏 ----------------------------------------------------------

  // 卡片下的逐条计入情况与控件（与 macOS 遗物卡同一口径：选层／选档／填层数／「条件成立」就地给出）。
  function relicEffectLinesHtml(items) {
    items = visibleItems(items);
    if (!items.length) return "";
    return "<ul class='ranker-mini-list'>" + items.map(function (item) {
      var controls = itemControlsHtml(item);
      return "<li class='is-" + esc(item.state) + "'><span class='ranker-mini-name'>" + esc(item.entry.name) + "</span>" +
        statePill(item.state) +
        (item.multiplier != null && item.state !== "noDamage" ? "<span class='ranker-mini-mul'>" + esc(fmtMultiplier(item.multiplier)) +
          (hasFlat(item.flat) ? " · " + esc(fmt(TEXT.flatInline, fmtFlat(item.flat))) : "") + "</span>" : "") +
        (item.state !== "counted" ? reasonHtml(item.reasons) : "") +
        (controls ? "<div class='ranker-row-controls'>" + controls + "</div>" : "") + "</li>";
    }).join("") + "</ul>";
  }

  function relicCardHtml(cardIndex, out, result) {
    var caps = result.caps;
    var kind = relicKindForCard(caps, cardIndex);
    var card = state.config.relics[cardIndex] || emptyRelicCard();
    var typeButtons = ["empty", "fixed", "custom"].map(function (key) {
      var active = card.type === key ? " is-active" : "";
      return "<button class='segment-button" + active + "' type='button' data-ranker-relic-type='" +
        cardIndex + ":" + key + "'>" + esc(TEXT.relicType[key]) + "</button>";
    }).join("");
    var cardItems = result.items.filter(function (item) {
      return (item.keys || []).some(function (key) { return key === "relic:" + cardIndex || key.indexOf("relic:" + cardIndex + ":") === 0; });
    });
    var body = "";
    if (card.type === "fixed") {
      var rows = fixedRelicRows(state.cfgIndex, out, state.config, kind);
      var usedElsewhere = {};
      state.config.relics.forEach(function (other, i) {
        if (i !== cardIndex && i < caps.relics && other.type === "fixed" && other.key) usedElsewhere[other.key] = true;
      });
      if (!rows.length) {
        body = "<p class='ranker-note'>" + esc(TEXT.relicFixedNone) + "</p>";
      } else {
        var options = rows.filter(function (row) {
          return state.showInactive || row.relic.hasDamage || row.key === card.key;
        }).map(function (row) {
          var selected = row.key === card.key ? " selected" : "";
          // 同名的固定遗物很多（「辽阔的光耀情景」就有好几件），名字后面带上词条摘要才分得清。
          var label = row.name + "：" + shortText(row.relic.effectNames.join("／"), 34) +
            (out.hasComposition
              ? (row.potential > row.score + 1e-9
                ? fmt(TEXT.optionPotential, fmtMultiplier(row.score), fmtMultiplier(row.potential))
                : fmt(TEXT.optionScore, fmtMultiplier(row.score)))
              : "") +
            (usedElsewhere[row.key] ? TEXT.relicFixedUsedElsewhere : "");
          return "<option value='" + esc(row.key) + "'" + selected + (usedElsewhere[row.key] ? " disabled" : "") + ">" +
            esc(label) + "</option>";
        }).join("");
        var fixed = state.cfgIndex.fixedRelicByKey[card.key];
        body = "<label class='select-field'><select data-ranker-relic-fixed='" + cardIndex + "'>" +
          "<option value=''>" + esc(TEXT.relicFixedPlaceholder) + "</option>" + options + "</select></label>" +
          (fixed
            ? "<div class='ranker-relic-effects'><div class='ranker-field-label'>" + esc(TEXT.relicEffectsLabel) + "</div><ul class='ranker-mini-list'>" +
              fixed.effectNames.map(function (name) { return "<li><span class='ranker-mini-name'>" + esc(name) + "</span></li>"; }).join("") +
              "</ul><div class='ranker-field-label'>" + esc(TEXT.relicCountedLabel) + "</div>" +
              relicEffectLinesHtml(cardItems) + "</div>"
            : "");
      }
    } else if (card.type === "custom") {
      var check = result.relicChecks[cardIndex] || { status: "empty", issues: [], warnings: [], message: "" };
      if (!state.cfgIndex.catalog.available) {
        body = "<p class='ranker-note ranker-note--warn'>" + esc(TEXT.relicNoCatalog) + "</p>";
      } else {
        var candidates = relicAffixRows(state.cfgIndex, out, state.config, kind);
        body = [0, 1, 2].map(function (row) {
          var chosen = card.affixIds[row];
          var options = candidates.filter(function (candidate) {
            return state.showInactive || rowUseful(candidate, out.hasComposition) || candidate.id === chosen;
          }).map(function (candidate) {
            var label = candidate.name + (out.hasComposition
              ? (candidate.potential > candidate.score + 1e-9
                ? fmt(TEXT.optionPotential, fmtMultiplier(candidate.score), fmtMultiplier(candidate.potential))
                : fmt(TEXT.optionScore, fmtMultiplier(candidate.score)))
              : "") +
              (candidate.applicable ? "" : TEXT.optionInactive);
            return "<option value='" + candidate.id + "'" + (candidate.id === chosen ? " selected" : "") + ">" + esc(label) + "</option>";
          }).join("");
          var affix = chosen == null ? null : state.cfgIndex.catalog.byId.get(chosen);
          var curseId = card.curseIds[row];
          var curseSelect = "";
          if (kind === "deep" && ((affix && affix.requiresCurse) || curseId != null)) {
            curseSelect = "<label class='select-field ranker-curse-field'><span class='ranker-field-label'>" + esc(TEXT.relicCurseLabel) + "</span>" +
              "<select data-ranker-relic-curse='" + cardIndex + ":" + row + "'><option value=''>" + esc(TEXT.relicCursePlaceholder) + "</option>" +
              state.cfgIndex.catalog.curses.map(function (curse) {
                return "<option value='" + curse.effectId + "'" + (curse.effectId === curseId ? " selected" : "") + ">" + esc(curse.name) + "</option>";
              }).join("") + "</select></label>";
          }
          var remove = chosen != null || curseId != null
            ? "<button type='button' class='button button--ghost ranker-remove' data-ranker-remove='relic:" + cardIndex + ":" + row + "'>" +
              esc(TEXT.relicRemove) + "</button>"
            : "";
          return "<div class='ranker-relic-row'><span class='ranker-field-label'>" + esc(fmt(TEXT.relicRowLabel, row + 1)) + "</span>" +
            "<label class='select-field'><select data-ranker-relic-affix='" + cardIndex + ":" + row + "'>" +
            "<option value=''>" + esc(TEXT.relicAffixEmpty) + "</option>" + options + "</select></label>" + remove + curseSelect + "</div>";
        }).join("");
        var statusColor = { valid: "green", partial: "blue", invalid: "red" }[check.status] || "gray";
        var statusText = TEXT.relicStatus[check.status] || TEXT.relicStatus.empty;
        body += "<div class='ranker-relic-status' data-testid='ranker-relic-status-" + cardIndex + "'>" + pill(statusText, statusColor) +
          "<span>" + esc(check.message || "") + "</span></div>" +
          (check.issues.length
            ? "<ul class='ranker-issue-list'>" + check.issues.map(function (issue) {
              return "<li><strong>" + esc(issue.title) + "</strong>" + (issue.detail ? "：" + esc(issue.detail) : "") + "</li>";
            }).join("") + "</ul>"
            : "") +
          (check.warnings.length
            ? "<ul class='ranker-issue-list is-muted'>" + check.warnings.map(function (warning) {
              return "<li><strong>" + esc(warning.title) + "</strong>：" + esc(warning.detail) + "</li>";
            }).join("") + "</ul>"
            : "") +
          relicEffectLinesHtml(cardItems);
      }
    }
    return "<div class='ranker-relic-card ranker-relic-card--" + kind + "' data-testid='ranker-relic-card-" + cardIndex + "'>" +
      "<div class='ranker-relic-head'><strong>" + esc(relicCardLabel(caps, cardIndex)) + "</strong>" +
      "<div class='segmented-control ranker-relic-type' role='radiogroup' aria-label='" + esc(TEXT.relicTypeAria) + "'>" + typeButtons + "</div></div>" +
      body + "</div>";
  }

  function relicsHtml(out, result) {
    var cards = [];
    for (var i = 0; i < result.caps.relics; i += 1) cards.push(relicCardHtml(i, out, result));
    return "<div class='section-heading'><div class='section-icon'>◈</div>" +
      "<div><h2>" + esc(TEXT.columns.relic) + "</h2><p>" + esc(fmt(TEXT.relicIntro, result.caps.relicNormal,
        slotCaps(state.cfgIndex.slotRules, "deep").relicDeep)) + "</p></div>" +
      "<div class='ranker-heading-pills'>" + pill(result.slots.relic.used + " / " + result.slots.relic.cap, "blue") + "</div></div>" +
      "<div class='ranker-relic-grid'>" + cards.join("") + "</div>";
  }

  // ---- 护符栏 ----------------------------------------------------------

  function talismansHtml(out, result) {
    var rows = talismanRows(state.cfgIndex, out, state.config);
    var slots = [];
    for (var slot = 0; slot < result.caps.accessory; slot += 1) {
      var chosen = state.config.accessories[slot];
      var options = rows.filter(function (row) {
        return state.showInactive || rowUseful(row, out.hasComposition) || row.id === chosen;
      }).map(function (row) {
        var elsewhere = state.config.accessories.indexOf(row.id) !== -1 && row.id !== chosen;
        var label = row.name + (out.hasComposition
          ? (row.potential > row.score + 1e-9
            ? fmt(TEXT.optionPotential, fmtMultiplier(row.score), fmtMultiplier(row.potential))
            : fmt(TEXT.optionScore, fmtMultiplier(row.score)))
          : "") +
          (row.applicable ? "" : TEXT.optionInactive) + (elsewhere ? TEXT.accUsedElsewhere : "");
        return "<option value='" + row.id + "'" + (row.id === chosen ? " selected" : "") + (elsewhere ? " disabled" : "") + ">" +
          esc(label) + "</option>";
      }).join("");
      var slotItems = result.items.filter(function (item) { return (item.keys || []).indexOf("acc:" + slot) !== -1; });
      slots.push("<div class='ranker-talisman-slot'><label class='select-field'><span class='ranker-field-label'>" +
        esc(fmt(TEXT.accSlotLabel, slot + 1)) + "</span>" +
        "<select data-ranker-accessory='" + slot + "'><option value=''>" + esc(TEXT.accPlaceholder) + "</option>" + options +
        "</select></label>" +
        (chosen != null
          ? "<button type='button' class='button button--ghost ranker-remove' data-ranker-remove='acc:" + slot + "'>" + esc(TEXT.accRemove) + "</button>"
          : "") +
        relicEffectLinesHtml(slotItems) + "</div>");
    }
    var full = result.slots.accessory.used >= result.slots.accessory.cap;
    return "<div class='section-heading'><div class='section-icon'>❖</div>" +
      "<div><h2>" + esc(TEXT.columns.accessory) + "</h2><p>" + esc(fmt(TEXT.accIntro, result.caps.accessory)) + "</p></div>" +
      "<div class='ranker-heading-pills'>" + pill(result.slots.accessory.used + " / " + result.slots.accessory.cap, "blue") +
      (full ? pill(TEXT.accFull, "green") : "") + "</div></div>" +
      "<div class='ranker-talisman-grid'>" + slots.join("") + "</div>";
  }

  // ---- 其它增益栏 ------------------------------------------------------

  // 层数：−／＋ 步进与输入框（与 macOS 的 Stepper 同一口径，0 到参数表上限）。
  function stackControlHtml(entry, stacks) {
    var si = entry.stackInput;
    var max = stackParamMax(entry);
    var value = stacks == null ? 0 : stacks;
    var label = si.mode === "copies" ? TEXT.stackLabelCopies : TEXT.stackLabel;
    var hints = [];
    if (si.mode === "ladder") hints.push(fmt(TEXT.stackHintLadder, max));
    else hints.push(fmt(TEXT.stackHintCopies, fmtNumber(si.perStackMultiplier, 4)));
    if (typeof si.practicalMaxStacks === "number") hints.push(fmt(TEXT.stackHintPractical, si.practicalMaxStacks));
    else if (typeof si.uiLabelMax === "number") hints.push(fmt(TEXT.stackHintLabel, si.uiLabelMax));
    if (isGraceStack(entry)) hints.push(TEXT.stackHintGrace);
    return "<div class='ranker-stack' title='" + esc(hints.join("；")) + "'><span>" + esc(label) + "</span>" +
      "<button type='button' class='ranker-step' data-ranker-stack-step='" + entry.id + ":-1'" + (value > 0 ? "" : " disabled") +
      " aria-label='" + esc(TEXT.stepDown) + "'>−</button>" +
      "<input type='number' min='0' step='1' max='" + max + "' value='" + value + "' data-ranker-stacks='" + entry.id + "'>" +
      "<button type='button' class='ranker-step' data-ranker-stack-step='" + entry.id + ":1'" + (value < max ? "" : " disabled") +
      " aria-label='" + esc(TEXT.stepUp) + "'>＋</button></div>";
  }

  function tierControlHtml(entry) {
    var members = ladderMembers(state.cfgIndex.ladders, entry.ladderGroup);
    var selected = selectedLadderTier(entry, state.config, state.cfgIndex.ladders);
    var thresholds = (entry.accLadder && Array.isArray(entry.accLadder.thresholds)) ? entry.accLadder.thresholds : [];
    return "<label class='ranker-stack'><span>" + esc(TEXT.tierSelectLabel) + "</span><select data-ranker-tier='" + entry.ladderGroup + "'>" +
      "<option value=''" + (selected.id === null ? " selected" : "") + ">" + esc(TEXT.tierNone) + "</option>" +
      members.map(function (member) {
        var threshold = thresholds[member.ladderTier - 1];
        var text = typeof threshold === "number"
          ? fmt(TEXT.tierLabelThreshold, member.ladderTier, fmtNumber(threshold, 0))
          : fmt(TEXT.tierLabel, member.ladderTier);
        return "<option value='" + member.id + "'" + (member.id === selected.id ? " selected" : "") + ">" + esc(text) + "</option>";
      }).join("") + "</select></label>";
  }

  // 多档词条选档：选项写出每一档的倍率字段（加算带符号），方便按出击武器类别对照词条说明。
  function variantControlHtml(entry) {
    var members = entry.variantMembers || [entry];
    var selected = selectedVariant(entry, state.config);
    return "<label class='ranker-stack' title='" + esc(TEXT.variantNoMapping) + "'><span>" + esc(TEXT.variantLabel) + "</span><select data-ranker-variant='" +
      esc(entry.variantGroup) + "'>" + members.map(function (member, i) {
        var parts = member.usedMultiplier.map(function (one) { return one.zh + " ×" + fmtNumber(one.value, 3); })
          .concat(member.usedFlat.map(function (one) { return one.zh + " " + fmtFlat(one.value, 0); }));
        return "<option value='" + member.id + "'" + (member.id === selected.id ? " selected" : "") + ">" +
          esc(fmt(TEXT.variantOption, member.variantTier || (i + 1), parts.length ? fmt(TEXT.variantRates, parts.join("、")) : "")) +
          "</option>";
      }).join("") + "</select></label>";
  }

  function otherListHtml(out) {
    var slot = state.otherTab;
    var rows = otherRowsFor(state.cfgIndex, out, state.config, slot);
    var query = foldText(state.otherQuery).trim();
    var shown = rows.filter(function (row) {
      if (row.selected) return true;
      if (!state.showInactive && !rowUseful(row, out.hasComposition)) return false;
      if (query && !row.row.entries.some(function (entry) { return entry.searchText.indexOf(query) !== -1; })) return false;
      return true;
    });
    if (!shown.length) return "<p class='ranker-empty'>" + esc(TEXT.otherEmpty) + "</p>";
    var html = "";
    var lastGroup = null;
    if (slot === "character") {
      shown.sort(function (a, b) {
        var ga = characterLabel(a.row.character);
        var gb = characterLabel(b.row.character);
        if (ga !== gb) return ga < gb ? -1 : 1;
        return b.score - a.score || a.key - b.key;
      });
    }
    if (slot === "weaponInnate") {
      shown.sort(function (a, b) { return (a.auto === b.auto ? 0 : (a.auto ? -1 : 1)); });
    }
    shown.forEach(function (row) {
      var group = slot === "character" ? characterLabel(row.row.character)
        : (slot === "weaponInnate" ? (row.auto ? TEXT.groupAutoInnate : TEXT.groupOtherInnate) : null);
      if (group !== null && group !== lastGroup) {
        html += "<div class='ranker-list-group'>" + esc(group) + "</div>";
        lastGroup = group;
      }
      var first = row.row.entries[0];
      var controls = "";
      if (row.selected) {
        var owned = row.items.filter(function (item) { return item.state !== "variantOff"; });
        var shownControls = owned.filter(function (item) {
          if (item.entry.accLadder) return ladderOwner(item);
          return true;
        });
        controls = shownControls.map(function (item) {
          var copy = {};
          Object.keys(item).forEach(function (key) { copy[key] = item[key]; });
          copy.autoConfirm = !row.auto;
          return itemControlsHtml(copy);
        }).join("");
      }
      html += "<div class='ranker-row" + (row.applicable ? "" : " is-inactive") + (row.selected ? " is-picked" : "") + "'>" +
        "<label class='ranker-row-check' title='" + esc(row.auto ? (row.selected ? TEXT.innateRemove : TEXT.innateRestore) : TEXT.selectUse) + "'>" +
        "<input type='checkbox' data-ranker-other='" + row.key + "'" +
        (row.selected ? " checked" : "") + "><span class='sr-only'>" + esc(TEXT.selectUse) + "</span></label>" +
        "<div class='ranker-row-main'><span class='ranker-row-name'>" + esc(row.name) + goodsLevelTagHtml(row.row) + "</span>" +
        "<span class='ranker-row-badges'>" + (row.auto ? pill(TEXT.badges.autoInnate, "green") : "") + entryBadges(first) + "</span>" +
        (row.state !== "counted" ? reasonHtml(row.reasons) : "") + "</div>" +
        scoreHtml(row.score, row.state, out.hasComposition, row.flat, row.potential, row.assumesOneStack) +
        "<div class='ranker-row-controls'>" + controls + "</div></div>";
    });
    return html;
  }

  // 道具等级标记：紧跟在名字后面的小标签，悬停给出说明（TEXT.goodsLevel.hint）；1 级的行不标。
  function goodsLevelTagHtml(row) {
    var tag = goodsLevelTag(row);
    if (!tag) return "";
    return "<span class='ranker-goods-level' data-testid='ranker-goods-level' title='" + esc(TEXT.goodsLevel.hint) + "'>" +
      pill(tag, "blue") + "</span>";
  }

  function othersHtml(out) {
    var innateHint = otherRowsFor(state.cfgIndex, out, state.config, state.otherTab).some(function (row) { return row.auto; })
      ? "<p class='ranker-note ranker-note--muted' data-testid='ranker-innate-hint'>" + esc(TEXT.otherInnateHint) + "</p>"
      : (state.otherTab === "weaponInnate" && out.mode !== "skill"
        ? "<p class='ranker-note ranker-note--muted'>" + esc(TEXT.otherInnateNoWeapon) + "</p>" : "");
    // 分栏说明区：有携物知识 2／3 级行的分栏（「道具」）说明等级从哪来。
    var goodsNote = goodsLevelNoteFor(state.cfgIndex, state.otherTab);
    var goodsNoteHtml = goodsNote
      ? "<p class='ranker-note ranker-note--muted' data-testid='ranker-goods-level-note'>" + esc(goodsNote) + "</p>" : "";
    var tabs = OTHER_SLOTS.map(function (slot) {
      var count = ((state.cfgIndex.otherRows || {})[slot] || []).length;
      var picked = ((state.cfgIndex.otherRows || {})[slot] || []).filter(function (row) {
        return state.config.others[row.key];
      }).length;
      var active = state.otherTab === slot ? " is-active" : "";
      return "<button class='ranker-tab" + active + "' type='button' data-ranker-other-tab='" + slot + "'>" +
        esc(TEXT.otherGroups[slot]) + "<span class='ranker-chip-count'>" + (picked ? picked + "/" : "") + count + "</span></button>";
    }).join("");
    return "<div class='section-heading'><div class='section-icon'>✚</div>" +
      "<div><h2>" + esc(TEXT.columns.other) + "</h2><p>" + esc(TEXT.otherIntro) + "</p></div></div>" +
      "<div class='ranker-tab-row' role='tablist' data-testid='ranker-other-tabs'>" + tabs + "</div>" +
      "<div class='ranker-filter-row'><label class='search-field ranker-list-search'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='" + esc(TEXT.otherSearch) + "' autocomplete='off' data-testid='ranker-other-search'></label>" +
      "<span class='ranker-note ranker-note--inline'>" + esc(slotNoteFor(state.otherTab)) + "</span></div>" + goodsNoteHtml + innateHint +
      "<div class='ranker-list' data-testid='ranker-other-list'>" + otherListHtml(out) + "</div>";
  }

  function slotNoteFor(slot) {
    var labels = (state.buffsData && state.buffsData.enums && state.buffsData.enums.sourceSlot) || {};
    var one = labels[slot];
    var text = one && one.note ? String(one.note) : "";
    return text.replace(/\*\*/g, "").split("。")[0];
  }

  // ---- 汇总 ------------------------------------------------------------

  function summaryRowHtml(item) {
    var entry = item.entry;
    var controls = itemControlsHtml(item);
    var notes = item.notes.slice();
    return "<div class='ranker-sum-row is-" + esc(item.state) + "'>" +
      "<div class='ranker-row-main'><span class='ranker-row-name'>" + esc(entry.name) + "</span>" +
      "<span class='ranker-sum-origin'>" + esc(item.labels.join("、")) + " · " + esc(entry.key) + "</span>" +
      (item.state !== "counted" ? reasonHtml(item.reasons) : "") +
      (notes.length ? "<span class='ranker-reason is-note'>" + esc(notes.join("；")) + "</span>" : "") + "</div>" +
      statePill(item.state) +
      scoreHtml(item.multiplier, item.state, item.multiplier != null, item.flat) +
      "<div class='ranker-row-controls'>" + controls + removeButtonsHtml(item) + "</div></div>";
  }

  function summaryHtml(out, result) {
    var heading = "<div class='section-heading'><div class='section-icon section-icon--green'>✦</div>" +
      "<div><h2>" + esc(TEXT.summaryHeading) + "</h2><p>" + esc(TEXT.summaryColumnNote) + "</p></div></div>";
    var totals = "<div class='ranker-combo-total' data-testid='ranker-summary-total'>" +
      "<div><dt>" + esc(TEXT.summaryTotal) + "</dt><dd data-testid='ranker-total'>" + esc(fmtMultiplier(result.total.multiplier)) + "</dd></div>" +
      "<div><dt>" + esc(TEXT.summaryGain) + "</dt><dd>" + esc(fmtGain(result.total.multiplier)) + "</dd></div>" +
      COLUMN_ORDER.map(function (column) {
        var one = result.byColumn[column];
        var slotText = column === "weaponAffix"
          ? result.slots.weaponAffix.used + "/" + result.slots.weaponAffix.cap
          : (column === "relic" ? result.slots.relic.used + "/" + result.slots.relic.cap
            : (column === "accessory" ? result.slots.accessory.used + "/" + result.slots.accessory.cap : fmt(TEXT.summaryCount, one.count)));
        return "<div data-testid='ranker-sub-" + column + "'><dt>" + esc(TEXT.columns[column]) + " · " + esc(slotText) + "</dt><dd>" +
          esc(fmtMultiplier(one.multiplier)) + "</dd></div>";
      }).join("") +
      (hasFlat(result.total.flat) ? "<div><dt>" + esc(TEXT.summaryFlat) + "</dt><dd data-testid='ranker-total-flat'>" +
        esc(fmtFlat(result.total.flat)) + "</dd></div>" : "") +
      "</div>" +
      "<p class='ranker-note ranker-note--muted'>" + esc(TEXT.summarySubtotals) + "</p>";
    if (!out.hasComposition) {
      return heading + totals + "<p class='ranker-empty'>" + esc(TEXT.summaryNoComposition) + "</p>";
    }
    var visible = visibleItems(result.items).filter(function (item) {
      return state.showInactive || (item.state !== "no" && item.state !== "context");
    });
    var counted = visible.filter(function (item) { return item.state === "counted"; });
    var uncounted = visible.filter(function (item) { return item.state !== "counted"; });
    function grouped(list) {
      return COLUMN_ORDER.map(function (column) {
        var own = list.filter(function (item) { return item.column === column; });
        if (!own.length) return "";
        return "<div class='ranker-list-group'>" + esc(TEXT.columns[column]) + "</div>" + own.map(summaryRowHtml).join("");
      }).join("");
    }
    var hiddenNo = result.items.filter(function (item) { return item.state === "no" || item.state === "context"; }).length;
    var messages = result.violations.map(function (text) { return "<li class='is-violation'>" + esc(text) + "</li>"; })
      .concat(result.warnings.map(function (warning) { return "<li class='is-" + esc(warning.kind) + "'>" + esc(warning.text) + "</li>"; }));
    var warnings = messages.length
      ? "<ul class='ranker-warn-list' data-testid='ranker-warnings'>" + messages.join("") + "</ul>"
      : "";
    return heading + totals + warnings +
      (hasFlat(result.total.flat) ? "<p class='ranker-note'>" + esc(TEXT.summaryFlatNote) + "</p>" : "") +
      "<div class='ranker-sum-list' data-testid='ranker-sum-list'>" +
      "<div class='ranker-field-label'>" + esc(fmt(TEXT.summaryCounted, result.counted.length)) + "</div>" +
      (counted.length ? grouped(counted) : "<p class='ranker-empty'>" + esc(TEXT.summaryEmpty) + "</p>") +
      (uncounted.length
        ? "<div class='ranker-field-label'>" + esc(fmt(TEXT.summaryUncounted, uncounted.length)) + "</div>" + grouped(uncounted)
        : "") +
      "</div>" +
      (!state.showInactive && hiddenNo
        ? "<p class='ranker-note ranker-note--muted'>" + esc(fmt(TEXT.summaryHiddenNo, hiddenNo, TEXT.showInactive)) + "</p>"
        : "");
  }

  // ---- 说明区 ----------------------------------------------------------

  function briefHtml() {
    var notes = briefNotes(state.buffsData, state.cfgIndex);
    return "<div class='section-heading'><div class='section-icon'>ⓘ</div>" +
      "<div><h2>" + esc(TEXT.briefHeading) + "</h2><p>" + esc(TEXT.briefIntro) + "</p></div></div>" +
      "<ul class='ranker-caveat-list'>" + notes.map(function (text) { return "<li>" + esc(text) + "</li>"; }).join("") + "</ul>";
  }

  // ---- 全部增益一览（折叠）----------------------------------------------

  function overviewBodyHtml(out) {
    if (!out.hasComposition) return "<p class='ranker-empty'>" + esc(TEXT.summaryNoComposition) + "</p>";
    var rows = overviewRows(state.cfgIndex, out, state.config);
    var query = foldText(state.overviewQuery).trim();
    var filtered = rows.filter(function (item) {
      if (!state.showInactive && !item.applicable) return false;
      if (query && item.entry.searchText.indexOf(query) === -1) return false;
      return true;
    });
    var shown = filtered.slice(0, state.overviewLimit);
    var list = shown.map(function (item, i) {
      var entry = item.entry;
      return "<div class='ranker-ov-row is-" + esc(item.state) + "'>" +
        "<span class='ranker-ov-rank'>" + (i + 1) + "</span>" +
        "<div class='ranker-row-main'><span class='ranker-row-name'>" + esc(entry.name) + "</span>" +
        "<span class='ranker-row-badges'>" + pill(slotLabel(state.buffsData, entry.slot), "purple") +
        pill(item.label, item.applicable ? "green" : "gray") + entryBadges(entry) +
        (item.assumedOneStack ? "<span title='" + esc(TEXT.overviewOneStackHelp) + "'>" + pill(TEXT.overviewOneStack, "amber") + "</span>" : "") +
        "</span>" +
        (item.applicable ? (item.notes.length ? reasonHtml(item.notes) : "") : reasonHtml(item.reasons)) + "</div>" +
        scoreHtml(item.multiplier, item.applicable ? "counted" : "other", true) +
        "<span class='ranker-sum-origin'>" + esc(entry.key) + "</span></div>";
    }).join("");
    var more = filtered.length > shown.length
      ? "<button class='button button--secondary button--wide ranker-more' type='button' data-testid='ranker-ov-more'>" +
        esc(fmt(TEXT.overviewMore, Math.min(PAGE_SIZE, filtered.length - shown.length), filtered.length - shown.length)) + "</button>"
      : "";
    return "<p class='ranker-note'>" + esc(fmt(TEXT.overviewCount, filtered.length)) + "</p>" +
      "<div class='ranker-list ranker-list--tall' data-testid='ranker-ov-list'>" +
      (list || "<p class='ranker-empty'>" + esc(TEXT.overviewNoMatch) + "</p>") + "</div>" + more;
  }

  function overviewHtml(out) {
    return "<details class='card ranker-details' data-testid='ranker-overview'" + (state.overviewOpen ? " open" : "") + ">" +
      "<summary><span class='ranker-summary-title'>" + esc(TEXT.overviewTitle) + "</span>" + pill(TEXT.overviewPill, "gray") + "</summary>" +
      "<div class='ranker-details-body'><div class='ranker-filter-row ranker-filter-row--top'>" +
      "<label class='search-field ranker-list-search'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='" + esc(TEXT.overviewSearch) + "' autocomplete='off' data-testid='ranker-ov-search'></label></div>" +
      "<div data-testid='ranker-ov-body'>" + (state.overviewOpen ? overviewBodyHtml(out) : "") + "</div></div></details>";
  }

  // ---- 底部折叠 --------------------------------------------------------

  function textBlock(title, body, testId, color) {
    if (!body) return "";
    var text = typeof body === "string" ? body : JSON.stringify(body, null, 1);
    return "<details class='card ranker-details'" + (testId ? " data-testid='" + testId + "'" : "") + ">" +
      "<summary><span class='ranker-summary-title'>" + esc(title) + "</span>" +
      pill("原文", color || "gray") + "</summary>" +
      "<div class='ranker-details-body'><p class='ranker-raw'>" + esc(text) + "</p></div></details>";
  }

  function caveatsHtml() {
    var list = Array.isArray(state.skillsData.caveats) ? state.skillsData.caveats : [];
    return "<details class='card ranker-details' data-testid='ranker-caveats'>" +
      "<summary><span class='ranker-summary-title'>战技数据的已知取舍</span>" +
      pill(list.length + " 条", "amber") + "</summary>" +
      "<div class='ranker-details-body'>" +
      "<ul class='ranker-caveat-list'>" + list.map(function (text) {
        return "<li>" + esc(zhFpText(text)) + "</li>";
      }).join("") + "</ul></div></details>";
  }

  // 数据集 usage 里「命中段已按 TAE 核实（v3）」一节：分段命中卡只取 variants 的依据，原文放在底部。
  var TAE_USAGE_KEY = "命中段已按 TAE 核实（v3）";

  function taeUsageHtml() {
    var usage = state.skillsData.usage || {};
    var text = usage[TAE_USAGE_KEY];
    if (!text) return "";
    var counts = state.skillsData.counts || {};
    return "<details class='card ranker-details' data-testid='ranker-tae'>" +
      "<summary><span class='ranker-summary-title'>命中段已按 TAE 核实</span>" +
      pill(counts.taeVerified === true ? "已核实" : "未核实", counts.taeVerified === true ? "green" : "amber") +
      pill("原文", "gray") + "</summary>" +
      "<div class='ranker-details-body'>" +
      "<p class='ranker-note'>分段命中只从 variants[].atkIds 取段：那里已按动画事件（TAE）剔掉本作打不出的段；" +
      "hits[] 里保留的这类段标了 notInvoked，本页不列出。来源：战技数据集 usage「" + esc(TAE_USAGE_KEY) + "」。</p>" +
      "<p class='ranker-raw'>" + strongHtml(zhFpText(text)) + "</p></div></details>";
  }

  function versionHtml() {
    var skills = state.skillsData;
    var buffs = state.buffsData;
    var counts = skills.counts || {};
    var buffCounts = buffs.counts || {};
    return "<details class='card ranker-details' data-testid='ranker-version'>" +
      "<summary><span class='ranker-summary-title'>数据版本与来源</span>" +
      pill(skills.gameVersion || "未知版本", "green") + "</summary>" +
      "<div class='ranker-details-body'><dl class='ranker-meta'>" +
      "<div><dt>游戏版本</dt><dd>" + esc(skills.gameVersion || "—") + "</dd></div>" +
      "<div><dt>数据版本</dt><dd>" + esc(skills.dataVersion || "—") + "</dd></div>" +
      "<div><dt>skills</dt><dd>schemaVersion " + esc(skills.schemaVersion) + " · 武器 " +
      esc(counts.weapons) + " · 战技 " + esc(counts.skills) + " · 法术 " + esc(counts.spells) +
      " · 分段 " + esc(counts.hits) +
      (counts.taeVerified === true ? " · 命中段已按 TAE 核实（打不出的 " + esc(counts.hitsNotInvoked) + " 段不列出）" : "") +
      "</dd></div>" +
      "<div><dt>buffs</dt><dd>schemaVersion " + esc(buffs.schemaVersion) + " · 增益 " +
      esc(buffCounts.buffs) + " 条 · 倍率字段 " + esc((buffs.rateFields || []).length) + " 个</dd></div>" +
      "<div><dt>v6 字段</dt><dd>局内武器词条 " + esc(buffCounts.weaponAffixes) + " 条 · 固定遗物 " +
      esc(buffCounts.fixedRelics) + " 件 · 叠层输入 " + esc(buffCounts.buffsWithStackInput) +
      " 条 · 互斥键 " + esc(buffCounts.exclusiveKeys) + " 个</dd></div>" +
      "<div><dt>生成时间</dt><dd>" + esc(skills.generatedAt || "—") + " / " +
      esc(buffs.generatedAt || "—") + "</dd></div>" +
      "</dl></div></details>";
  }

  // 底部原文折叠的顺序：先排名步骤与叠加，再 v6 的生效范围 / 槽位 / 叠层，最后是其余 notes。
  var NOTE_ORDER = [
    { key: "ranking", zh: "排名步骤" },
    { key: "appliesTo", zh: "生效范围 appliesTo" },
    { key: "sourceSlot", zh: "来源槽位 sourceSlot" },
    { key: "weaponAffix", zh: "局内武器词条" },
    { key: "relicAffix", zh: "遗物词条" },
    { key: "stackInput", zh: "叠层输入" },
    { key: "userQuestions", zh: "用户问题的研究结论" },
    { key: "activation", zh: "发动条件" },
    { key: "attackContext", zh: "攻击情境" },
    { key: "howToUseRates", zh: "倍率怎么用" },
    { key: "target", zh: "作用目标" },
    { key: "displayName", zh: "显示名" },
    { key: "zh", zh: "数据集总说明" }
  ];

  function noteBlocksHtml() {
    var notes = state.buffsData.notes || {};
    var shown = {};
    var blocks = NOTE_ORDER.map(function (item) {
      shown[item.key] = true;
      var body = notes[item.key];
      if (item.key === "userQuestions" && body && typeof body === "object") {
        body = Object.keys(body).map(function (key) {
          var one = body[key] || {};
          return key + "　" + (one.question || "") + "\n" + (one.answer || "");
        }).join("\n\n");
      }
      return textBlock(item.zh + "（buffs notes." + item.key + "）", body, "ranker-notes-" + item.key, "purple");
    });
    Object.keys(notes).sort().forEach(function (key) {
      if (shown[key]) return;
      blocks.push(textBlock("buffs notes." + key, notes[key], "ranker-notes-" + key, "purple"));
    });
    return blocks.join("");
  }

  function footerHtml() {
    var stackingRules = state.buffsData.stackingRules || {};
    return caveatsHtml() + taeUsageHtml() + noteBlocksHtml() +
      textBlock("叠加规则（buffs stackingRules）", stackingRules.zh, "ranker-stacking-rules", "amber") +
      versionHtml();
  }

  // ---- 渲染调度 --------------------------------------------------------

  function section(name) {
    return dom ? dom.querySelector("[data-testid='ranker-" + name + "']") : null;
  }

  function renderPicker() {
    var node = section("picker");
    if (!node) return;
    node.innerHTML = pickerHtml();
    var search = node.querySelector("[data-testid='ranker-means-search']");
    if (search) search.value = state.meansQuery;
  }

  function renderMeansList() {
    var node = section("means-list");
    if (node) node.innerHTML = meansListHtml();
  }

  function renderWeaponBlock() {
    var node = section("weapon-block");
    if (node) node.innerHTML = weaponPickerHtml();
  }

  function renderHits() {
    var node = section("hits");
    if (node) node.innerHTML = hitsHtml();
  }

  function computeAll() {
    var comp = currentComposition();
    var out = currentOutput(comp);
    var result = evaluateConfig(state.cfgIndex, out, state.config, coreRef());
    return { comp: comp, out: out, result: result };
  }

  function setHtml(name, html, searchTestId, value) {
    var node = section(name);
    if (!node) return;
    node.innerHTML = html;
    if (searchTestId) {
      var input = node.querySelector("[data-testid='" + searchTestId + "']");
      if (input) input.value = value || "";
    }
  }

  // 配置相关的全部区块（构成变化、配置变化都走这里）。
  function renderBuild(computed) {
    var data = computed || computeAll();
    setHtml("toolbar", toolbarHtml(data.out, data.result));
    setHtml("waffix", waffixHtml(data.out, data.result), "ranker-wa-search", state.waQuery);
    setHtml("relics", relicsHtml(data.out, data.result));
    setHtml("talismans", talismansHtml(data.out, data.result));
    setHtml("others", othersHtml(data.out), "ranker-other-search", state.otherQuery);
    setHtml("summary", summaryHtml(data.out, data.result));
    var slot = section("overview-slot");
    if (slot) {
      slot.innerHTML = overviewHtml(data.out);
      var input = slot.querySelector("[data-testid='ranker-ov-search']");
      if (input) input.value = state.overviewQuery;
    }
    return data;
  }

  function renderResults() {
    var data = computeAll();
    var compNode = section("comp");
    if (compNode) compNode.innerHTML = compositionHtml(data.comp);
    renderBuild(data);
  }

  function renderAll() {
    renderPicker();
    renderHits();
    renderResults();
    var brief = section("brief");
    if (brief) brief.innerHTML = briefHtml();
    var footer = section("footer");
    if (footer) footer.innerHTML = footerHtml();
  }

  function renderListOnly(name, html) {
    var node = section(name);
    if (node) node.innerHTML = html;
  }

  // ---- 交互 ------------------------------------------------------------

  // 换输出手段只重置选段；配置保留（同一套配置换一招比较）。
  function applySelection(kind, id) {
    state.hitOverrides = {};
    state.noFp = false;
    state.overviewLimit = PAGE_SIZE;
    if (kind === "skill") {
      var skill = (state.skillsData._skillById || {})[id];
      var weapon = defaultWeaponFor(state.skillsData, skill);
      state.selection = { kind: "skill", id: id, weaponId: weapon ? weapon.id : null };
    } else {
      state.selection = { kind: kind, id: id, weaponId: null };
    }
  }

  function selectMeans(kind, id) {
    applySelection(kind, id);
    // 「已按推荐填入 N 项」之类的提示只对填入时的那一招有意义，换招就清掉。
    state.flash = "";
    renderMeansList();
    renderWeaponBlock();
    renderHits();
    renderResults();
  }

  function updateConfig(next, message) {
    state.config = next;
    state.flash = message || "";
    renderBuild();
  }

  function relicCardAt(config, index) {
    var card = config.relics[index];
    if (!card) {
      card = emptyRelicCard();
      config.relics[index] = card;
    }
    return card;
  }

  function onClick(event) {
    var target = event.target;
    var meansKind = target.closest("[data-ranker-means-kind]");
    if (meansKind) {
      // 只换列表的档位，已选的输出手段（哪怕是另一档的）原样保留。
      state.meansKind = normalizeMeansKind(meansKind.dataset.rankerMeansKind);
      renderPicker();
      return;
    }
    var handButton = target.closest("[data-ranker-hand]");
    if (handButton) {
      state.hand = Number(handButton.dataset.rankerHand) === 2 ? 2 : 1;
      renderWeaponBlock();
      renderResults();
      return;
    }
    var means = target.closest("[data-ranker-means]");
    if (means) {
      var parts = means.dataset.rankerMeans.split(":");
      selectMeans(parts[0], Number(parts[1]));
      return;
    }
    var hitsAction = target.closest("[data-ranker-hits]");
    if (hitsAction) {
      state.hitOverrides = hitOverridesFor(currentHits(), hitsAction.dataset.rankerHits, state.noFp);
      renderHits();
      renderResults();
      return;
    }
    var runMode = target.closest("[data-ranker-runmode]");
    if (runMode) {
      var switched = applyRunMode(state.cfgIndex, state.config, runMode.dataset.rankerRunmode);
      var trimmed = trimmedCount(state.cfgIndex, state.config, switched);
      updateConfig(switched, switched.runMode === "normal" && state.config.runMode === "deep" && trimmed > 0
        ? fmt(TEXT.modeTrimmed, trimmed) : "");
      return;
    }
    var contextChip = target.closest("[data-ranker-context]");
    if (contextChip) {
      var contextKey = contextChip.dataset.rankerContext;
      if (state.contexts[contextKey]) delete state.contexts[contextKey];
      else state.contexts[contextKey] = true;
      renderBuild();
      return;
    }
    var waStep = target.closest("[data-ranker-wa-step]");
    if (waStep) {
      var stepParts = waStep.dataset.rankerWaStep.split(":");
      var affixId = Number(stepParts[0]);
      updateConfig(stepWeaponAffix(state.cfgIndex, state.config, affixId, Number(stepParts[1])));
      return;
    }
    var stackStep = target.closest("[data-ranker-stack-step]");
    if (stackStep) {
      var stackParts = stackStep.dataset.rankerStackStep.split(":");
      var stackId = Number(stackParts[0]);
      var stackEntry = state.cfgIndex.byId[stackId];
      updateConfig(setStacks(state.config, stackEntry, stacksFor(stackEntry, state.config) + Number(stackParts[1])));
      return;
    }
    var remove = target.closest("[data-ranker-remove]");
    if (remove) {
      updateConfig(removeSource(state.cfgIndex, state.config, remove.dataset.rankerRemove));
      return;
    }
    var waFilter = target.closest("[data-ranker-wa-filter]");
    if (waFilter) {
      state.waFilter = waFilter.dataset.rankerWaFilter === "all" ? "all" : "weapon";
      renderBuild();
      return;
    }
    var relicType = target.closest("[data-ranker-relic-type]");
    if (relicType) {
      var typeParts = relicType.dataset.rankerRelicType.split(":");
      var cardIndex = Number(typeParts[0]);
      var nextConfig = cloneConfig(state.config);
      var card = relicCardAt(nextConfig, cardIndex);
      if (card.type !== typeParts[1]) {
        nextConfig.relics[cardIndex] = emptyRelicCard();
        nextConfig.relics[cardIndex].type = typeParts[1];
      }
      updateConfig(nextConfig);
      return;
    }
    var tab = target.closest("[data-ranker-other-tab]");
    if (tab) {
      state.otherTab = tab.dataset.rankerOtherTab;
      renderBuild();
      return;
    }
    if (target.closest("[data-testid='ranker-fill']")) {
      var comp = currentComposition();
      var out = currentOutput(comp);
      var filled = recommendFill(state.cfgIndex, out, state.config, coreRef(), waFilterType(out));
      updateConfig(filled.config, filled.added.length ? fmt(TEXT.fillDone, filled.added.length) : TEXT.fillNothing);
      return;
    }
    if (target.closest("[data-testid='ranker-clear']")) {
      var cleared = emptyConfig();
      cleared.runMode = state.config.runMode;
      updateConfig(cleared);
      return;
    }
    if (target.closest("[data-testid='ranker-ov-more']")) {
      state.overviewLimit += PAGE_SIZE;
      var ovBody = section("ov-body");
      if (ovBody) ovBody.innerHTML = overviewBodyHtml(currentOutput());
    }
  }

  function onChange(event) {
    var target = event.target;
    if (target.matches("[data-testid='ranker-weapon']")) {
      state.selection.weaponId = Number(target.value);
      state.hitOverrides = {};
      renderWeaponBlock();
      renderHits();
      renderResults();
      return;
    }
    if (target.matches("[data-testid='ranker-nofp']")) {
      state.noFp = Boolean(target.checked);
      state.hitOverrides = {};
      renderHits();
      renderResults();
      return;
    }
    if (target.matches("[data-ranker-hit]")) {
      state.hitOverrides[Number(target.dataset.rankerHit)] = Boolean(target.checked);
      renderHits();
      renderResults();
      return;
    }
    if (target.matches("[data-testid='ranker-show-inactive']")) {
      state.showInactive = Boolean(target.checked);
      renderBuild();
      return;
    }
    var next;
    if (target.matches("[data-ranker-relic-fixed]")) {
      next = cloneConfig(state.config);
      var fixedCard = relicCardAt(next, Number(target.dataset.rankerRelicFixed));
      fixedCard.type = "fixed";
      fixedCard.key = target.value || null;
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-relic-affix]")) {
      var parts = target.dataset.rankerRelicAffix.split(":");
      var cardIndex = Number(parts[0]);
      var row = Number(parts[1]);
      next = cloneConfig(state.config);
      var caps = slotCaps(state.cfgIndex.slotRules, next.runMode);
      next.relics[cardIndex] = withRelicAffix(relicCardAt(next, cardIndex), relicKindForCard(caps, cardIndex), row,
        target.value ? Number(target.value) : null, state.cfgIndex.catalog, coreRef());
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-relic-curse]")) {
      var curseParts = target.dataset.rankerRelicCurse.split(":");
      next = cloneConfig(state.config);
      relicCardAt(next, Number(curseParts[0])).curseIds[Number(curseParts[1])] = target.value ? Number(target.value) : null;
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-accessory]")) {
      next = cloneConfig(state.config);
      var slotIndex = Number(target.dataset.rankerAccessory);
      var id = target.value ? Number(target.value) : null;
      next.accessories[slotIndex] = id;
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-other]")) {
      updateConfig(toggleOtherRow(state.cfgIndex, currentOutput(), state.config, Number(target.dataset.rankerOther), Boolean(target.checked)));
      return;
    }
    if (target.matches("[data-ranker-tick]")) {
      next = cloneConfig(state.config);
      if (target.checked) next.ticks[Number(target.dataset.rankerTick)] = true;
      else delete next.ticks[Number(target.dataset.rankerTick)];
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-stacks]")) {
      var stackEntry = state.cfgIndex.byId[Number(target.dataset.rankerStacks)];
      updateConfig(setStacks(state.config, stackEntry, Number(target.value)));
      return;
    }
    if (target.matches("[data-ranker-tier]")) {
      next = cloneConfig(state.config);
      if (target.value) next.tiers[Number(target.dataset.rankerTier)] = Number(target.value);
      else delete next.tiers[Number(target.dataset.rankerTier)];
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-variant]")) {
      next = cloneConfig(state.config);
      next.variants[target.dataset.rankerVariant] = Number(target.value);
      updateConfig(next);
    }
  }

  function onInput(event) {
    var target = event.target;
    if (target.matches("[data-testid='ranker-means-search']")) {
      state.meansQuery = target.value || "";
      renderMeansList();
      return;
    }
    if (target.matches("[data-testid='ranker-wa-search']")) {
      state.waQuery = target.value || "";
      renderListOnly("wa-list", waffixListHtml(currentOutput()));
      return;
    }
    if (target.matches("[data-testid='ranker-other-search']")) {
      state.otherQuery = target.value || "";
      renderListOnly("other-list", otherListHtml(currentOutput()));
      return;
    }
    if (target.matches("[data-testid='ranker-ov-search']")) {
      state.overviewQuery = target.value || "";
      state.overviewLimit = PAGE_SIZE;
      renderListOnly("ov-body", overviewBodyHtml(currentOutput()));
    }
  }

  function onToggle(event) {
    var target = event.target;
    if (!target || !target.matches || !target.matches("[data-testid='ranker-overview']")) return;
    state.overviewOpen = target.open;
    if (target.open) {
      var body = section("ov-body");
      if (body && !body.innerHTML) body.innerHTML = overviewBodyHtml(currentOutput());
    }
  }

  function bindEvents() {
    if (!dom || dom.__rankerBound) return;
    dom.__rankerBound = true;
    dom.addEventListener("click", onClick);
    dom.addEventListener("change", onChange);
    dom.addEventListener("input", onInput);
    dom.addEventListener("toggle", onToggle, true);
  }

  // ---- 装载 ------------------------------------------------------------

  function decorateSkills(data) {
    var byWeapon = {};
    (data.weapons || []).forEach(function (weapon) { byWeapon[weapon.id] = weapon; });
    var bySkill = {};
    (data.skills || []).forEach(function (skill) { bySkill[skill.id] = skill; });
    var bySpell = {};
    (data.spells || []).forEach(function (spell) { bySpell[spell.id] = spell; });
    data._weaponById = byWeapon;
    data._skillById = bySkill;
    data._spellById = bySpell;
    return data;
  }

  function rebuildConfigIndex() {
    state.catalogRef = ctxRef ? ctxRef.catalog : null;
    state.cfgIndex = buildConfigIndex(state.buffsData, state.index, state.catalogRef, coreRef());
  }

  function renderData(skillsData, buffsData) {
    state.skillsData = decorateSkills(skillsData);
    state.buffsData = buffsData;
    state.index = indexBuffs(buffsData);
    rebuildConfigIndex();
    state.means = buildMeansItems(skillsData);
    if (!state.selection && state.means.length) {
      var first = state.means[0];
      applySelection(first.kind, first.id);
    }
    dom.innerHTML = shell();
    bindEvents();
    renderAll();
  }

  function load(ctx) {
    ctxRef = ctx;
    if (!dom) return;
    Promise.all([ctx.getGameData(SKILLS_DATA), ctx.getGameData(BUFFS_DATA)]).then(function (results) {
      if (!dom) return;
      var skillsData = results[0];
      var buffsData = results[1];
      if (!skillsData || !buffsData || typeof skillsData !== "object" || typeof buffsData !== "object") {
        state.loaded = false;
        dom.innerHTML = unavailableShell("战技／法术与增益数据尚未内置，页面无法计算。");
        return;
      }
      state.loaded = true;
      renderData(skillsData, buffsData);
    });
  }

  var api = {
    init: function (mount, ctx) {
      dom = mount;
      ctxRef = ctx;
      mount.innerHTML = "<div class='page-content ranker-content'><p class='ranker-loading' " +
        "data-testid='ranker-loading'>正在载入战技与增益数据…</p></div>";
      load(ctx);
    },
    refresh: function (ctx) {
      ctxRef = ctx;
      if (!dom) return;
      if (!state.loaded) { load(ctx); return; }
      // 词条库导入 / 恢复内置后，自组遗物的候选与合法性要按新词条库重算。
      if (ctx && ctx.catalog !== state.catalogRef) {
        rebuildConfigIndex();
        renderBuild();
      }
    },
    // 纯计算部分，供 windows/tests/ranker*.test.mjs 直接测试。
    _internals: {
      TEXT: TEXT,
      fmt: fmt,
      flattenText: flattenText,
      TYPE_KEYS: TYPE_KEYS,
      TYPE_INFO: TYPE_INFO,
      TYPES_BY_ELEMENT: TYPES_BY_ELEMENT,
      ELEMENTS: ELEMENTS,
      ATTACK_CONTEXT_ORDER: ATTACK_CONTEXT_ORDER,
      USEFUL_EPSILON: USEFUL_EPSILON,
      EPSILON: EPSILON,
      OUTPUT_CLASSES: OUTPUT_CLASSES,
      MEANS_KINDS: MEANS_KINDS,
      CASTER_WEP_TYPE: CASTER_WEP_TYPE,
      COLUMN_ORDER: COLUMN_ORDER,
      OTHER_SLOTS: OTHER_SLOTS,
      CHARACTER_NAMES: TEXT.characterNames,
      COPIES_CEILING: COPIES_CEILING,
      SKILLS_SCHEMA_MIN: SKILLS_SCHEMA_MIN,
      TAE_USAGE_KEY: TAE_USAGE_KEY,
      skillsSchemaWarning: skillsSchemaWarning,
      variantIndexFor: variantIndexFor,
      selectVariant: selectVariant,
      invokedHits: invokedHits,
      selectHits: selectHits,
      hitOnSide: hitOnSide,
      hitOverridesFor: hitOverridesFor,
      physicalTypeForHit: physicalTypeForHit,
      usesMotion: usesMotion,
      hitContribution: hitContribution,
      hitChipPlan: hitChipPlan,
      zhFpText: zhFpText,
      strongHtml: strongHtml,
      composition: composition,
      hitPoise: hitPoise,
      hitStamina: hitStamina,
      parseRateFieldKey: parseRateFieldKey,
      rateFieldPlan: rateFieldPlan,
      multiplierMap: multiplierMap,
      flatMap: flatMap,
      familyKey: familyKey,
      familyName: familyName,
      buffDisplayName: buffDisplayName,
      goodsLevelTag: goodsLevelTag,
      goodsLevelNoteFor: goodsLevelNoteFor,
      exclusiveKeyOf: exclusiveKeyOf,
      characterKey: characterKey,
      characterLabel: characterLabel,
      indexBuff: indexBuff,
      indexBuffs: indexBuffs,
      assignAffixVariants: assignAffixVariants,
      selectedVariant: selectedVariant,
      availableContexts: availableContexts,
      makeOutput: makeOutput,
      outputWepType: outputWepType,
      subCategoryMatch: subCategoryMatch,
      appliesVerdict: appliesVerdict,
      verdictLabel: verdictLabel,
      activationNote: activationNote,
      defaultStacks: defaultStacks,
      stacksFor: stacksFor,
      stackParamMax: stackParamMax,
      stackSoftMax: stackSoftMax,
      stackWarnings: stackWarnings,
      stackedRates: stackedRates,
      entryTables: entryTables,
      weightedMultiplier: weightedMultiplier,
      weightedFlat: weightedFlat,
      productTable: productTable,
      effectiveFor: effectiveFor,
      evaluateEntry: evaluateEntry,
      makeEnv: makeEnv,
      selectedLadderTier: selectedLadderTier,
      ladderTopTier: ladderTopTier,
      prefersItem: prefersItem,
      dedupeItems: dedupeItems,
      slotCaps: slotCaps,
      buildCatalogIndex: buildCatalogIndex,
      cursePoolOf: cursePoolOf,
      buildConfigIndex: buildConfigIndex,
      emptyConfig: emptyConfig,
      emptyRelicCard: emptyRelicCard,
      cloneConfig: cloneConfig,
      weaponAffixAvailable: weaponAffixAvailable,
      weaponAffixMatchesType: weaponAffixMatchesType,
      weaponAffixUsage: weaponAffixUsage,
      canAddWeaponAffix: canAddWeaponAffix,
      stepWeaponAffix: stepWeaponAffix,
      applyRunMode: applyRunMode,
      trimmedCount: trimmedCount,
      setStacks: setStacks,
      toggleOtherRow: toggleOtherRow,
      removeSource: removeSource,
      relicKindForCard: relicKindForCard,
      relicCardFilled: relicCardFilled,
      checkCustomRelic: checkCustomRelic,
      curseIssues: curseIssues,
      pickCurse: pickCurse,
      autoAssignCurses: autoAssignCurses,
      withRelicAffix: withRelicAffix,
      currentInnateEntries: currentInnateEntries,
      collectSources: collectSources,
      mergeSources: mergeSources,
      evaluateConfig: evaluateConfig,
      totalOf: totalOf,
      candidateScore: candidateScore,
      rowUseful: rowUseful,
      weaponAffixRows: weaponAffixRows,
      relicAffixRows: relicAffixRows,
      fixedRelicRows: fixedRelicRows,
      talismanRows: talismanRows,
      otherRowsFor: otherRowsFor,
      recommendFill: recommendFill,
      greedyCustomRelic: greedyCustomRelic,
      overviewRows: overviewRows,
      briefNotes: briefNotes,
      skillOnlySubCategories: skillOnlySubCategories,
      configWarnings: configWarnings,
      configDumpLine: configDumpLine,
      caseDumpLine: caseDumpLine,
      weaponSourceMap: weaponSourceMap,
      weaponSourceOf: weaponSourceOf,
      weaponOptionLabel: weaponOptionLabel,
      weaponsForSkill: weaponsForSkill,
      groupWeapons: groupWeapons,
      defaultWeaponFor: defaultWeaponFor,
      hasAnyDamage: hasAnyDamage,
      skillHasDamage: skillHasDamage,
      buildMeansItems: buildMeansItems,
      meansWithoutDamage: meansWithoutDamage,
      filterMeans: filterMeans,
      meansKindOf: meansKindOf,
      spellKindOf: spellKindOf,
      normalizeMeansKind: normalizeMeansKind,
      meansKindButtonsHtml: meansKindButtonsHtml,
      fmtMultiplier: fmtMultiplier,
      fmtPercent: fmtPercent,
      fmtGain: fmtGain,
      fmtNumber: fmtNumber,
      fmtFlat: fmtFlat,
      hasFlat: hasFlat,
      fmtDuration: fmtDuration,
      slotLabel: slotLabel,
      decorateSkills: decorateSkills
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
