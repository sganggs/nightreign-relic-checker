// 增伤排名页。页面模块契约见 renderer/pages/README.md。
// 本文件由「增伤排名」功能开发者独占：只改这里与 pages/ranker.css。
//
// 数据：ctx.getGameData("skills") → resources/skills.json（schemaVersion 2）
//       ctx.getGameData("buffs")  → resources/buffs.json（schemaVersion 6：sourceSlot / appliesTo /
//                                   slotRules / weaponAffixes / fixedRelics / stackInput / exclusiveKey）
//       ctx.Core + ctx.catalog    → 遗物合法性（core.js 的 check / isEligible / canonicalOrder）
//
// 页面结构：「自己组一套配置」
//   ① 输出手段：战技（+ 武器）或法术；分段勾选、伤害构成（与旧版相同，算法不变）。
//   ② 常规 / 深夜开关（slotRules.modes）：决定武器词条上限、深夜专属上限、遗物格数。
//   ③ 局内武器词条栏（weaponAffixes）：按对当前输出的有效倍率排序，数量步进，受上限约束。
//   ④ 遗物栏：3 或 6 张卡，每张二选一——官方固定词条遗物（fixedRelics）或自组
//      （普通遗物走 Core.check("currentNormal")，深夜遗物走 Core.check("deepPositive") + 诅咒配对）。
//   ⑤ 护符栏：2 个槽位（sourceSlots 含 accessory 的条目按护符分组）。
//   ⑥ 其它增益栏：道具 / 增益法术 / 战技自增益 / 武器固有 / 角色 / 永久强化 / 局内叠层 / 其它。
//   ⑦ 汇总：总倍率、各栏小计、槽位用量、生效条目清单、「按推荐填满」。
//
// 算法口径（全部照数据集自带的说明，不写死任何具体数值）：
//   · 生效判定一律用 buffs[].appliesTo[输出类别]（战技 → skill，含子弹段；魔法 → sorcery；
//     祷告 → incantation）。yes 计入；no 不计入并显示 appliesToDetail.reason；conditional 看
//     requires：hand / attackWeaponTypes / physicalType 按当前输出自动判定，subCategoriesAny 用
//     attackIndex 对所选战技／法术逐段判定（全命中＝生效，全不命中＝不生效，部分命中＝按段数加权），
//     attackContexts 用「攻击情境」勾选，imbuedWeaponOnly / attachedWeaponOnly 与没有机读条件的
//     一律要用户确认。页面不再按 subCategories / weaponSlot 自己猜。
//   · direction=decrease 的条目一律不计入（notes.ranking 第②步：只要 increase／mixed）。
//   · activation ≠ passive 的条目要用户确认「条件成立」：用户亲手放进栏位的（武器词条、自组遗物词条、
//     护符、其它栏勾选）默认视为已确认；随固定遗物整件带进来的、当前武器固有自动列入的默认不确认
//     （notes.ranking 第③步：自动带入不算用户放入）。stackInput 的条目以层数代替确认（层数 0 = 不计入）。
//   · 同一遗物词条下挂的多档（affixVariant：按出击武器类别只生效一档）只算选中的那一档；数据还没有
//     affixVariant 时按参数结构推断分组，互斥键按 "affix#<词条 ID>" 合并（参数推断，未实测）。
//   · 单条的倍率表：只有 countsAsDamage 且 valueKind=multiplier 的字段进乘积（攻击力倍率层与伤害倍率层
//     相乘，物理子类型只乘对应那一格），attackPowerFlat 只按占比加权展示、不进连乘。
//   · 叠层：stackInput.mode=ladder 第 n 层取 tierMultipliers[n-1]，mode=copies 取 perStackMultiplier^n，
//     都替换 appliesToRateKeys 那几个字段；accumulatorLadder 让用户选层，只算选中的那一层。
//   · 去重：按 stacking.exclusiveKey，同键只留一份（applyHighest 先比 categoryPriority，
//     否则取当前构成下有效倍率高的，再相同取 spEffectId 小的），不同键相乘。
//   · 总倍率 = Σ_type 占比_type × Π_(去重后的条目) 该条目在 type 上的倍率（与旧版单条有效倍率同一公式，
//     推广到整套配置）；各栏小计同理只取本栏条目。
//   · 按推荐填满：只挑「被动、自动判定生效、无需确认、非叠层」的条目，按有效倍率贪心填空槽，
//     同键不重复、不改动已选内容；武器词条遵守总上限与深夜专属上限，遗物遵守 Core 合法性。
//
// **两端同一口径**：macOS 版由同事并行实现同一套算法；配置部分（工具条、四栏、汇总、口径说明、一览）
// 的文案串全部集中在下方 TEXT 常量表，对照时逐键比对即可。原样保留的输出手段／分段命中／伤害构成／
// 底部原文折叠沿用旧版的行内文案，不在此表。本页只做「相对伤害构成」：没有强化等级、能力值补正与 AttackElementCorrectParam，
// 绝对伤害不在范围内（见 skills 数据集的 usage.本数据集的边界）。
(function (root) {
  "use strict";

  var PAGE_KEY = "ranker";
  var SKILLS_DATA = "skills";
  var BUFFS_DATA = "buffs";

  // ---------------------------------------------------------------- 常量表

  // 伤害类型轴：物理按攻击类型细分 + 四种属性。顺序即展示顺序。
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

  // 输出类别（appliesTo 的键）。战技的子弹段同样按 skill。
  var OUTPUT_CLASSES = ["skill", "sorcery", "incantation"];

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

  // 栏目：汇总与去重时的先后顺序（完全并列时先出现的留下）。
  var COLUMN_ORDER = ["weaponAffix", "relic", "accessory", "other"];

  // 其它增益栏的分组（sourceSlot 主槽位）与展示顺序。
  var OTHER_SLOTS = [
    "consumable", "spellBuff", "weaponSkill", "weaponInnate",
    "character", "permanent", "runStack", "other"
  ];

  // 角色分组：Paramdex 行名 [Skill - X] / [Ultimate - X] / [Passive - X] 里的 X。
  // 中文名与 heroes 数据集 heroes[].nameZh 一致。
  var CHARACTER_NAMES = {
    Wylder: "追踪者", Guardian: "守护者", Ironeye: "铁之眼", Duchess: "女爵", Raider: "无赖",
    Revenant: "复仇者", Recluse: "隐士", Executor: "执行者", Scholar: "学者", Undertaker: "送葬者"
  };

  // 深夜遗物负面词条池的兜底值（与 core.js 的 DEEP_CURSE_POOL_ID 同值）。实际取值由 buildCatalogIndex
  // 从词条库现算（只装诅咒词条的那个池），词条库里算不出来才用这里。
  var DEEP_CURSE_POOL_ID = 3000000;

  var PAGE_SIZE = 40;
  var PICKER_LIMIT = 40;

  // ==================================================== 文案常量表（两端对照）
  // 配置部分的所有文案都从这里取（原样保留的输出手段／分段命中／伤害构成／底部原文折叠除外）。
  // 带 {0} {1} 的是格式串，由 fmt() 按位置替换。
  // 取自 core.js 的遗物合法性文案（「词条重复」「同一互斥池」…）不在这里重复：直接用 Core.check 的输出；
  // core.js 没有导出的那几条（深夜诅咒配对）在 relic* 键里逐字照抄 auditRelic / auditDeepRelic。
  var TEXT = {
    pageTitle: "增伤排名",
    pageSubtitle: "选一个战技／法术，再自己组一套局内配置：武器词条、遗物、护符与其它增益，看总增伤",
    runMode: { normal: "常规", deep: "深夜" },
    runModeHint: "常规：武器词条最多 {0} 条、遗物 {1} 件；深夜：武器词条最多 {2} 条（其中深夜专属最多 {3} 条）、遗物 {4} 件（普通 {5} ＋ 深夜 {6}）",
    columns: { weaponAffix: "局内武器词条", relic: "遗物", accessory: "护符", other: "其它增益" },
    otherGroups: {
      consumable: "道具", spellBuff: "增益法术", weaponSkill: "战技自增益", weaponInnate: "武器固有",
      character: "角色", permanent: "永久强化", runStack: "局内叠层", other: "其它"
    },
    outputClass: { skill: "战技", sorcery: "魔法", incantation: "祷告" },
    hand: { 1: "右手", 2: "左手" },
    wepTypeFallback: "类别 {0}",
    characterOther: "其他角色",
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
      noDamage: "不含伤害倍率"
    },
    badges: {
      conditional: "条件型",
      activated: "发动型",
      copies: "按份数叠加",
      ladder: "叠层",
      accLadder: "累积阶梯",
      variant: "按武器类别取一档"
    },
    // appliesTo 判定
    verdictMissing: "数据未给出这类输出的 appliesTo，按不生效处理",
    verdictNoFallback: "数据判定对这类输出不生效",
    requireHandFail: "只作用于{0}武器（当前为{1}）",
    requireWepTypeFail: "只对用{0}发动的攻击生效（当前为{1}）",
    requireWepTypeNoWeapon: "只对用{0}发动的攻击生效（当前没有选武器）",
    requirePhysicalFail: "只作用于{0}攻击（当前构成里没有这一类）",
    requireSubsFail: "所选{0}的命中段都不带子类别 {1}",
    requireSubsPartial: "所选{0}只有 {1}/{2} 段带子类别 {3}，按段数加权（段数取 attackIndex 对整招的统计，不随上方分段勾选变化）",
    requireSubsUnknown: "attackIndex 里没有所选{0}，子类别 {1} 无法自动判定，需确认",
    requireContext: "需勾选攻击情境：{0}",
    requireImbued: "只对附加了属性的那把武器生效（附魔／油脂／出击时附加）",
    requireAttached: "只对带这条词条的那把武器生效",
    requireUnknown: "数据要求 {0}，本页无法自动判定，需确认",
    requireManual: "数据判定为有条件生效：{0}",
    activationNeed: {
      conditional: "条件型：需满足发动条件（残血、双手持、命中触发…）",
      activated: "发动型：只在技艺／绝招／战技发动期间存在"
    },
    reasonNoDamage: "不含计入伤害的倍率字段",
    reasonDecrease: "direction=decrease：这是减益（降低自己的伤害、降低敌人攻击力等），按 notes.ranking 第②步只保留 increase／mixed，不计入增伤",
    reasonVariantOff: "同一遗物词条的 {0} 档按出击武器类别只生效一档，当前按第 {1} 档计算（{2}）",
    variantSourceData: "数据 affixVariant",
    variantSourceInferred: "按参数结构推断分组，未实测",
    variantLabel: "档",
    variantOption: "第 {0} 档{1}",
    variantRates: "（{0}）",
    reasonAlly: "只作用于队友（target=ally），不计入自己的输出",
    reasonTarget: "作用对象不是自己（target={0}）",
    reasonZeroStacks: "层数为 0，不计入",
    reasonTierOff: "累积阶梯只算选中的那一层（当前选第 {0} 层）",
    reasonRelicInvalid: "所在遗物不合法，整件不计入",
    reasonDupSameStackSelf: "同一效果已由「{0}」计入；数据标注可与自身叠加（stackSelf），本页按互斥键只计一份（参数推断，未实测）",
    reasonDupSameRefresh: "同一效果已由「{0}」计入：重复获得只刷新，不叠第二份",
    reasonDupKey: "与「{0}」同属互斥键 {1}，同键只取一份",
    // 叠层
    stackLabel: "层数",
    stackLabelCopies: "份数",
    stackOverPractical: "超过一局实际能达到的 {0} 层（{1}）",
    stackOverParam: "参数表只有 {0} 层，按第 {0} 层计算",
    stackOverLabel: "游戏文本只备到＋{0}，更多层数按同一倍率外推（未实测）",
    stackHintGrace: "本局新发现的赐福数",
    tierLabel: "第 {0} 层",
    tierSelectLabel: "层",
    // 武器词条栏
    waUsage: "已用 {0} / {1}",
    waDeepOnlyUsage: "深夜专属 {0} / {1}",
    waFilterWeapon: "当前武器类别（{0}）",
    waFilterAll: "全部类别",
    waFilterNone: "当前输出没有武器类别，显示全部",
    waCapReached: "已达上限",
    waDeepOnlyCapReached: "深夜专属已达上限",
    waNotInMode: "常规模式没有这条（只出现在深夜诅咒武器上）",
    waDupHint: "同一条词条多份：互斥键相同只计 1 份（stackingRules：重复获得只刷新）",
    waTierHint: "不同档位各自一个互斥键，按相乘计算（参数推断，未实测）",
    waBadgeDeepOnly: "深夜专属",
    waBadgeBlessing: "赐福",
    waBadgeFixed: "固定词条",
    waPotency: "档位{0}",
    waEmpty: "当前筛选下没有能增伤的武器词条",
    waIntro: "局内捡到的武器随机带的词条；{0} 把武器的词条全局生效。按对当前输出的有效倍率排序",
    waFilterAria: "武器类别过滤",
    stepperAria: "数量",
    stepDown: "减少",
    stepUp: "增加",
    // 遗物栏
    relicIntro: "每格二选一：官方固定词条遗物整件选入，或按现有词条规范自组（实时检查合法性）",
    relicTypeAria: "遗物来源",
    relicEffectsLabel: "词条",
    relicCountedLabel: "计入情况（非增伤词条只显示不计入）",
    relicStatus: { valid: "合法", partial: "预检通过", invalid: "不合法", empty: "空" },
    relicValidDeep: "合法：正面词条按「深夜正面」口径通过，诅咒配对已逐行校验",
    relicCursePairingTitle: "诅咒配对已校验",
    relicCursePairingDetail: "本页已按 core.js 深夜遗物审计的配对规则逐行核对：需要诅咒的词条各配一条诅咒池（{0}）里的诅咒，不需要的不带；自组遗物按 3 格计，不涉及具体遗物 ID",
    optionInactive: "（不生效）",
    optionScore: "（{0}）",
    optionPotential: "（{0}，确认条件后 {1}）",
    relicCardNormal: "普通遗物 {0}",
    relicCardDeep: "深夜遗物 {0}",
    relicTypeEmpty: "空",
    relicTypeFixed: "固定遗物",
    relicTypeCustom: "自组",
    relicFixedPlaceholder: "选择官方固定词条遗物…",
    relicFixedNone: "数据未内置深夜固定遗物",
    relicAffixPlaceholder: "（空）",
    relicCursePlaceholder: "（未选诅咒）",
    relicCurseLabel: "诅咒（不计增伤，但要占位）",
    relicPlaceholderAffix: "其余不增伤词条",
    relicEmpty: "未选择词条",
    relicPartial: "预检通过：已选 {0} 条，其余 {1} 条可填任意不增伤的合法词条",
    relicInvalid: "该遗物组合不合法",
    relicNoCatalog: "词条库未载入，无法自组遗物",
    relicUnknownEffectTitle: "存在未知词条 ID",
    relicUnknownEffectDetail: "以下词条 ID 不在词条索引中：{0}",
    // 与 core.js auditDeepRelic / auditRelic 同文
    relicCurseMissingTitle: "需诅咒的词条缺少负面词条",
    relicCurseMissingDetail: "第 {0} 行的正面词条需要配对负面词条：{1}",
    relicCurseUnexpectedTitle: "多余的负面词条",
    relicCurseUnexpectedDetail: "第 {0} 行的正面词条不需要负面词条，却携带负面词条：{1}",
    relicCurseMismatchTitle: "负面词条不在诅咒池",
    relicCurseMismatchDetail: "第 {0} 行的负面词条不在诅咒池：{1}",
    relicDuplicateTitle: "词条重复",
    relicDuplicateDetail: "同一词条在一件遗物上重复出现：{0}",
    relicConflictTitle: "互斥词条同时出现",
    relicConflictDetail: "同一互斥池的词条不能同时出现：{0}",
    cardControlsHint: "条件型效果请在下方「汇总」里勾选「条件成立」；叠层效果在那里填层数、累积阶梯在那里选层、按武器类别取一档的词条在那里选档",
    relicFixedUsedElsewhere: "（已在别的遗物格）",
    // 护符栏
    accIntro: "最多 {0} 个，同一护符不能装两个",
    accSlotLabel: "护符 {0}",
    accPlaceholder: "选择护符…",
    accUsedElsewhere: "（已装备）",
    // 其它栏
    otherIntro: "不占槽位，按需勾选；条件型勾上即视为条件成立，叠层类填层数",
    otherAutoInnate: "当前武器固有，自动列入",
    otherInnateHint: "当前武器的固有效果自动列入（取消勾选可排除）：被动的直接计入；条件型默认不计入，要在下方「汇总」里勾选「条件成立」；叠层类默认 0 层，要在「汇总」里填层数",
    selectUse: "选用",
    otherEmpty: "这一组里没有能增伤的条目",
    otherInferred: "来源为推断",
    otherAlly: "队友增益",
    // 汇总
    summaryHeading: "汇总",
    summaryTotal: "总倍率",
    summaryGain: "相对提升",
    summaryFlat: "另有攻击力加算",
    summaryFlatNote: "攻击力加算（点数）没有绝对攻击力就折不成倍率，只按占比加权展示，不进连乘",
    summaryNoComposition: "先勾选至少一段带伤害的命中，才能计算倍率",
    summaryEmpty: "还没有放入任何增益",
    summaryColumnNote: "总倍率 = Σ 占比 × 各伤害类型上全部计入条目的倍率连乘；各栏小计只算本栏",
    summaryTick: "条件成立",
    summaryCount: "{0} 条",
    summaryHiddenNo: "另有 {0} 条对当前输出不生效（打开「{1}」查看原因）。",
    flatInline: "攻击力 {0}",
    fillButton: "按推荐填满",
    clearButton: "清空配置",
    fillNote: "只填空着的槽位：挑被动、自动判定生效、不用确认的条目，按有效倍率从高到低，同键不重复",
    fillDone: "已按推荐填入 {0} 项",
    fillNothing: "没有可填的空槽或可用条目",
    warnDuplicate: "互斥键 {0}：{1} 份只计 1 份（{2}）",
    warnTiers: "「{0}」的不同档位／来源同时计入，各自独立相乘：参数推断，未实测",
    warn204: "多条 spCategory 204 存档阶梯同时生效（{0}）：各阶梯 categoryPriority 不同、按参数结构判为互不顶替，未实测",
    warnExclusivity: "「{0}」同属遗物互斥组 exclusivityId={1}：按参数推断分装在不同遗物上时只有一条生效，本页仍分别计入（未实测）",
    // 工具条
    runModeLabel: "出击模式",
    runModeAria: "常规或深夜",
    // 口径说明与一览
    briefHeading: "口径说明",
    briefIntro: "数据集 notes.ranking / stackingRules / notes.userQuestions 的结论简述",
    overviewTitle: "全部增益一览",
    overviewPill: "查阅用",
    overviewSearch: "搜索增益名称、来源或 Paramdex 行名",
    overviewCount: "共 {0} 条（按「放进来能拿到多少」口径逐条评估，未去重、未连乘；只供查阅）。",
    overviewMore: "再显示 {0} 条（剩余 {1} 条）",
    overviewNoMatch: "没有匹配的条目",
    briefStack: {
      item: "{0}：{1}",
      ladder: "第 n 层取第 n 档（每层约 ×{0}），参数表 {1} 层",
      practical: "，一局实际上限 {0} 层（×{1}）",
      copies: "每份 ×{0}、N 份按 N 次方相乘，参数表无上限",
      unit: "（层数＝{0}）",
      separator: "；"
    },
    // 通用
    showInactive: "显示不生效项",
    contextsLabel: "攻击情境（勾选后，只在该情境成立的倍率才计入）",
    searchPlaceholder: "搜索名称",
    schemaTooOld: "增益数据是 schemaVersion {0}：本页按 v6 的 appliesTo / slotRules / exclusiveKey 组配置，旧数据缺这些字段，结果不可信",
    noData: "数据未内置",
    // 说明区（结论简述；条数一律照数据现算）
    brief: {
      appliesTo: "生效判定一律按数据的 appliesTo：战技（含战技射出的子弹段）看 skill、魔法看 sorcery、祷告看 incantation。conditional 的机读条件里，持武器的手、出手武器类别、物理攻击类型按当前输出自动判定；子类别按 attackIndex 对所选战技／法术逐段判定（部分段命中时按段数加权；attackIndex 只给整招各子类别组合的段数、没有逐段对应，所以权重不随上方的分段勾选变化）；攻击情境用上方的情境勾选；附魔武器限定等无法自动判定的需要手动确认。",
      direction: "减益不计入：direction=decrease 的 {0} 条（附加异常时的武器伤害惩罚、降低敌人攻击力等）按 notes.ranking 第②步不进增伤；mixed（有增有减，例如附加属性时物理减、属性加）照常计入。",
      affixVariant: "同一遗物词条下挂多档的（{0} 组 {1} 条，例如「出击时的武器，附加…」的 4 档）：游戏按出击武器的类别只生效一档、不能相乘，参数里也没有指向哪一档的列，本页只算汇总里选中的那一档（默认第 1 档）。{2}",
      affixVariantData: "分组取自数据的 affixVariant。",
      affixVariantInferred: "数据尚未给出 affixVariant：按「同一遗物词条、同名多档、倍率字段相同」的参数结构推断分组，互斥键合并为 affix#<词条 ID>——参数推断，未实测。",
      innate: "当前武器的固有效果自动列入「其它增益 · 武器固有」：被动的直接计入；条件型默认不计入，要在汇总里勾选「条件成立」；叠层类默认 0 层，要填层数（notes.ranking 第③步：自动带入不算用户放入）。",
      stacking: "叠加：同一互斥键（stacking.exclusiveKey）只计一份、取倍率高的那份，不同键相乘。这是依据 SpEffectParam 的 spCategory／categoryPriority 等参数结构推断的，未经木桩实测（stackingRules）。数据把 spCategory=10 标成「可与自身叠加」，但本页按互斥键只计一份。",
      tiers: "同一词条的不同档位（＋1／＋2／＋3、档位1／2／3）是不同的 SpEffect、各有自己的互斥键，本页按相乘计算——参数推断，未实测。",
      deepWeapon: "深夜诅咒武器每把 2 条正面词条，其中深夜专属正面词条最多 1 条（6 把最多 {0} 条，按 weaponAffixDeepOnlyPositive 计数）；负面诅咒另按每把 1 条算，不占这个名额，也不计增伤。同一把武器的两条正面词条能否相同（或同一词条的不同档位），参数表里查不到（duplicateWithinWeapon.status={1}），本页只校验总数与深夜专属上限，不按把分配。",
      relic: "遗物：普通遗物按 core.js 的「普通 1.03」口径（三条不重复、compatibilityId 两两不同、能分配到槽池模板）；深夜遗物按「深夜正面」口径预检，并要求 requiresCurse 的词条各配一条负面诅咒池（{0}）里的诅咒。不足三条时用可落任一槽池、不参与互斥的占位词条补足后再检查。官方固定遗物整件计入；随整件带进来的条件型效果要手动确认。",
      skillAttack: "「提升战技攻击力」类（子类别 {0}）只作用于战技（含战技的子弹段），不作用于法术与普通攻击；法术吃到的「提升攻击力（XX・战技）」是战技发动后给自己的全伤害增益（sourceSlot=weaponSkill），名字里的「战技」是来源（notes.userQuestions.Q1）。",
      equipped: "「装备三把以上类别为 X 的武器」判的是装备中的数量，与出手的武器无关，对战技与法术都生效；「提升 X 的攻击力」只对用 X 发动的攻击生效（notes.userQuestions.Q3）。",
      runStack: "叠层：{0}。同一阶梯各层互斥、只取当前层；不同阶梯（封印监牢、黑夜入侵者等）按 categoryPriority 判为互不顶替、可以同时生效——参数推断，未实测。",
      formula: "总倍率 = Σ 伤害类型占比 × 该类型上全部计入条目的倍率连乘；攻击力倍率层与最终伤害倍率层相乘，物理子类型倍率只乘对应那一部分；攻击力加算（点数）只展示、不进连乘。",
      fill: "「按推荐填满」只填空着的槽位，只挑被动、自动判定生效、不用手动确认、不需要填层数的条目，按当前构成下的有效倍率从高到低贪心选取，同一互斥键不重复；遗物逐格比较「最好的固定遗物」与「贪心自组的合法遗物」，取倍率高的。",
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

  // 武器在这个战技里用的那一套动作。缺 skillVariant = 这把武器的战技没有命中段。
  function selectVariant(skill, weapon) {
    var variants = skill && Array.isArray(skill.variants) ? skill.variants : null;
    if (!variants || !variants.length) return null;
    var index = weapon && typeof weapon.skillVariant === "number" ? weapon.skillVariant : -1;
    if (index < 0 || index >= variants.length) return null;
    return variants[index] || null;
  }

  // 返回「这把武器实际会打出的段」。variants 存在时一律走 atkIds，
  // 缺失才退回 ctx 单选（武器名 → 武器类别 → ctx 缺失），任何情况下都不取并集。
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
    var byWeapon = weapon && weapon.nameEn
      ? hits.filter(function (hit) { return hit.ctx === weapon.nameEn; })
      : [];
    if (byWeapon.length) return byWeapon;
    var byType = weapon && weapon.wepTypeEn
      ? hits.filter(function (hit) { return hit.ctx === weapon.wepTypeEn; })
      : [];
    if (byType.length) return byType;
    return hits.filter(function (hit) { return !hit.ctx; });
  }

  // 分段列表工具条的三个动作，返回完整的 override 表（reset＝清空，退回默认规则）。
  // 「全选」只勾**当前这一侧**的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍。
  function hitOverridesFor(hits, action, noFp) {
    var overrides = {};
    if (action === "reset") return overrides;
    (hits || []).forEach(function (hit) {
      if (!hit || hit.noDamage) return;
      overrides[hit.atkId] = action === "all" && Boolean(hit.noFp) === Boolean(noFp);
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
  // restrictedType 非空（requires.physicalType）时倍率只落在那一个物理通道上。
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

  function buffDisplayName(buff) {
    if (!buff) return "";
    return buff.displayNameZh || buff.nameZh || buff.displayNameEn || buff.nameEn ||
      buff.paramName || ("#" + buff.spEffectId);
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
    return CHARACTER_NAMES[key] || key;
  }

  // ---- buff 索引（只建一次，选段变化时不重建）--------------------------

  function indexBuff(buff, plan) {
    var rates = (buff && buff.rates) || {};
    var stacking = (buff && buff.stacking) || {};
    var usedMultiplier = [];
    var usedFlat = [];
    var multiplier = multiplierMap(rates, plan, usedMultiplier, null);
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
      countsAsDamage: hasMultiplier || hasFlat,
      target: buff.target || "self",
      activation: buff.activation || "conditional",
      direction: buff.direction || "increase",
      duration: typeof buff.duration === "number" ? buff.duration : -1,
      slot: slot,
      slots: slots,
      appliesTo: buff.appliesTo && typeof buff.appliesTo === "object" ? buff.appliesTo : null,
      appliesToDetail: buff.appliesToDetail && typeof buff.appliesToDetail === "object" ? buff.appliesToDetail : {},
      key: exclusiveKeyOf(buff),
      exclusiveScope: stacking.exclusiveScope || "",
      behavior: stacking.spCategoryBehavior || "",
      spCategory: num(stacking.spCategory),
      categoryPriority: num(stacking.categoryPriority),
      family: familyKey(buff),
      stackInput: buff.stackInput && typeof buff.stackInput === "object" ? buff.stackInput : null,
      accLadder: acc,
      ladderGroup: accIds.length ? accIds[0] : null,
      ladderTier: acc ? num(acc.tier) : 0,
      innate: buff.weaponInnate && typeof buff.weaponInnate === "object" ? buff.weaponInnate : null,
      // 同一遗物词条下的多档（affixVariant）：variantMembers 由 indexBuffs 统一填（按档位排好序的整组）。
      variantGroup: variant ? String(variant.key || ("affix#" + variant.attachEffectId)) : null,
      variantTier: variant ? num(variant.variant) : 0,
      variantSource: variant ? "data" : "",
      variantMembers: null,
      keyInferred: false,
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

  // 数据里实际要求过的攻击情境（appliesToDetail.<cls>.requires.attackContexts），只统计
  // 带伤害倍率字段的条目。中文名取 enums.attackContext[key].zh，顺序用固定表。
  function availableContexts(buffsData, entries) {
    var labels = (buffsData && buffsData.enums && buffsData.enums.attackContext) || {};
    var counts = {};
    (entries || []).forEach(function (entry) {
      if (!entry.countsAsDamage) return;
      var seen = {};
      OUTPUT_CLASSES.forEach(function (cls) {
        var detail = entry.appliesToDetail[cls];
        var keys = detail && detail.requires && Array.isArray(detail.requires.attackContexts)
          ? detail.requires.attackContexts : [];
        keys.forEach(function (key) { seen[key] = true; });
      });
      Object.keys(seen).forEach(function (key) { counts[key] = (counts[key] || 0) + 1; });
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
  // 数据给了 affixVariant 就只用数据；数据里一条都没有时按参数结构推断：同一 relicAffixes.attachEffectId、
  // 同族（行名去掉档位后相同）、倍率字段集合相同、各自一个互斥键、至少两条——推断出的组把互斥键合并成
  // "affix#<词条 ID>"（与数据将来给的键同形），并标 keyInferred。返回 { 组键 → 按档位排序的成员 }。
  function assignAffixVariants(entries) {
    var hasData = entries.some(function (entry) { return entry.variantSource === "data"; });
    if (!hasData) {
      var buckets = {};
      var order = [];
      entries.forEach(function (entry) {
        var buff = entry.buff || {};
        if (!entry.countsAsDamage || entry.accLadder || entry.stackInput) return;
        if (buff.accumulatorStages || buff.selfAllyPair) return;
        if (entry.relicAttachIds.length !== 1) return;
        var bucketKey = entry.relicAttachIds[0] + "|" + entry.family + "|" + Object.keys(entry.rates).sort().join(",");
        if (!buckets[bucketKey]) { buckets[bucketKey] = []; order.push(bucketKey); }
        buckets[bucketKey].push(entry);
      });
      order.forEach(function (bucketKey) {
        var members = buckets[bucketKey];
        if (members.length < 2) return;
        var keys = {};
        members.forEach(function (entry) { keys[entry.key] = true; });
        if (Object.keys(keys).length !== members.length) return;
        members.sort(function (a, b) { return a.id - b.id; });
        var group = "affix#" + members[0].relicAttachIds[0];
        members.forEach(function (entry, i) {
          entry.variantGroup = group;
          entry.variantTier = i + 1;
          entry.variantSource = "inferred";
          entry.key = group;
          entry.keyInferred = true;
        });
      });
    }
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
    return { plan: plan, entries: entries, byId: byId, variants: variants, contexts: availableContexts(buffsData, entries) };
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
      contextNames: enums.attackContext || {}
    };
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

  // 返回 { state, reasons, needs, notes, weight, restrictedType }：
  //   state = yes（生效）/ no（不生效）/ context（要勾选攻击情境）/ pending（要用户确认）
  //   weight ∈ (0, 1]：subCategoriesAny 部分段命中时按段数加权
  //   restrictedType：requires.physicalType 时倍率只落在那一个物理通道
  function appliesVerdict(entry, out) {
    var cls = out && out.mode ? out.mode : "skill";
    var verdict = { state: "yes", reasons: [], needs: [], notes: [], weight: 1, restrictedType: null };
    var value = entry && entry.appliesTo ? entry.appliesTo[cls] : null;
    var detail = (entry && entry.appliesToDetail && entry.appliesToDetail[cls]) || {};
    if (value === "yes") return verdict;
    if (value !== "conditional") {
      verdict.state = "no";
      verdict.reasons.push(detail.reason || (value ? TEXT.verdictNoFallback : TEXT.verdictMissing));
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
      var need = requires[key];
      if (key === "hand") {
        if (need !== out.hand) {
          fails.push(fmt(TEXT.requireHandFail, TEXT.hand[need === 2 ? 2 : 1], TEXT.hand[out.hand === 2 ? 2 : 1]));
        }
      } else if (key === "attackWeaponTypes") {
        var list = Array.isArray(need) ? need : [];
        var names = list.map(function (type) { return wepTypeLabel(out, type); }).join("／");
        var own = outputWepType(out);
        if (own === null) fails.push(fmt(TEXT.requireWepTypeNoWeapon, names));
        else if (list.indexOf(own) === -1) fails.push(fmt(TEXT.requireWepTypeFail, names, wepTypeLabel(out, own)));
      } else if (key === "physicalType") {
        var type = PHYS_BY_INDEX[need] || null;
        if (type) {
          verdict.restrictedType = type;
          if (out.hasComposition && !(num(out.shares[type]) > 0)) {
            fails.push(fmt(TEXT.requirePhysicalFail, TYPE_INFO[type].zh));
          }
        } else {
          verdict.needs.push(fmt(TEXT.requireUnknown, "physicalType=" + need));
        }
      } else if (key === "subCategoriesAny") {
        var subs = Array.isArray(need) ? need : [];
        var label = subCategoryLabel(out, subs);
        var match = subCategoryMatch(out, subs);
        if (!match) {
          verdict.needs.push(fmt(TEXT.requireSubsUnknown, clsZh, label));
        } else if (match.matched === 0) {
          fails.push(fmt(TEXT.requireSubsFail, clsZh, label));
        } else if (match.matched < match.total) {
          verdict.weight = match.matched / match.total;
          verdict.notes.push(fmt(TEXT.requireSubsPartial, clsZh, match.matched, match.total, label));
        }
      } else if (key === "attackContexts") {
        var wanted = Array.isArray(need) ? need : [];
        var picked = wanted.some(function (ctxKey) { return out.contexts && out.contexts[ctxKey] === true; });
        if (!picked) contexts = wanted.slice();
      } else if (key === "imbuedWeaponOnly") {
        if (need) verdict.needs.push(TEXT.requireImbued);
      } else if (key === "attachedWeaponOnly") {
        if (need) verdict.needs.push(TEXT.requireAttached);
      }
    });
    Object.keys(requires).forEach(function (key) {
      if (REQUIRE_ORDER.indexOf(key) !== -1) return;
      known += 1;
      verdict.needs.push(fmt(TEXT.requireUnknown, key));
    });
    if (!known) verdict.needs.push(fmt(TEXT.requireManual, detail.reason || ""));
    if (fails.length) {
      verdict.state = "no";
      verdict.reasons = fails.concat(detail.reason ? [detail.reason] : []);
      verdict.needs = [];
      return verdict;
    }
    if (contexts.length) {
      verdict.state = "context";
      var names2 = contexts.map(function (key) {
        var one = out.contextNames && out.contextNames[key];
        return one && one.zh ? one.zh : key;
      }).join("／");
      verdict.reasons = [fmt(TEXT.requireContext, names2)];
      verdict.contexts = contexts;
      return verdict;
    }
    if (verdict.needs.length) {
      verdict.state = "pending";
      verdict.reasons = detail.reason ? [detail.reason] : [];
    }
    return verdict;
  }

  // ---- 单条的倍率表（叠层 / 物理类型限定 / 按段加权）------------------

  function defaultStacks(entry, explicit) {
    var si = entry && entry.stackInput;
    if (!si) return null;
    if (!explicit) return 0;
    if (typeof si.practicalMaxStacks === "number" && si.practicalMaxStacks > 0) return si.practicalMaxStacks;
    return 1;
  }

  function stacksFor(entry, config, explicit) {
    if (!entry || !entry.stackInput) return null;
    var value = config && config.stacks ? config.stacks[entry.id] : undefined;
    if (typeof value === "number" && isFinite(value)) return Math.max(0, Math.floor(value));
    return defaultStacks(entry, explicit);
  }

  // 层数的计数单位以游戏文本为准（notes.stackInput）：descZh 写着「新发现的赐福」的按赐福数提示。
  function isGraceStack(entry) {
    return Boolean(entry && entry.stackInput && /赐福/.test(String(entry.buff && entry.buff.descZh)));
  }

  // 叠层上限：ladder 取 paramMaxStacks（tierMultipliers 的长度），copies 参数表无上限。
  function stackParamMax(entry) {
    var si = entry && entry.stackInput;
    if (!si) return null;
    if (si.mode === "ladder") {
      var tiers = Array.isArray(si.tierMultipliers) ? si.tierMultipliers.length : 0;
      return numOr(si.paramMaxStacks, tiers) || tiers || null;
    }
    return typeof si.paramMaxStacks === "number" ? si.paramMaxStacks : null;
  }

  function stackWarnings(entry, stacks) {
    var si = entry && entry.stackInput;
    var out = [];
    if (!si || !(stacks > 0)) return out;
    if (typeof si.practicalMaxStacks === "number" && stacks > si.practicalMaxStacks) {
      var source = String(si.practicalMaxSource || "").split(/[：:（(]/)[0];
      out.push(fmt(TEXT.stackOverPractical, si.practicalMaxStacks, source || "practicalMaxStacks"));
    }
    var paramMax = stackParamMax(entry);
    if (si.mode === "ladder" && paramMax && stacks > paramMax) out.push(fmt(TEXT.stackOverParam, paramMax));
    if (si.mode === "copies" && typeof si.uiLabelMax === "number" && stacks > si.uiLabelMax) {
      out.push(fmt(TEXT.stackOverLabel, si.uiLabelMax));
    }
    return out;
  }

  // 叠层后的 rates：ladder 第 n 层取 tierMultipliers[n-1]（超出参数表按最后一层），
  // copies 取 perStackMultiplier^n；都替换 appliesToRateKeys（缺失时退回 multiplierKey）。
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
    } else if (si.mode === "copies") {
      if (typeof si.perStackMultiplier === "number") value = Math.pow(si.perStackMultiplier, n);
    }
    if (typeof value !== "number" || !isFinite(value)) return rates;
    var keys = Array.isArray(si.appliesToRateKeys) && si.appliesToRateKeys.length
      ? si.appliesToRateKeys : (si.multiplierKey ? [si.multiplierKey] : []);
    var copy = {};
    Object.keys(rates).forEach(function (key) { copy[key] = rates[key]; });
    keys.forEach(function (key) { copy[key] = value; });
    return copy;
  }

  // 这一条在 9 个伤害类型上的倍率表与加算表。weight < 1 时按段数加权：1 + (m − 1) × weight。
  function entryTables(entry, plan, restrictedType, weight, stacks) {
    var rates = entry.stackInput ? stackedRates(entry, stacks) : entry.rates;
    if (rates === null) return { table: emptyTypeMap(1), flat: emptyTypeMap(0) };
    var table = multiplierMap(rates, plan, null, restrictedType || null);
    var flat = flatMap(rates, plan, null);
    var w = typeof weight === "number" && weight >= 0 && weight < 1 ? weight : 1;
    if (w < 1) {
      TYPE_KEYS.forEach(function (type) {
        table[type] = 1 + (table[type] - 1) * w;
        flat[type] = flat[type] * w;
      });
    }
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

  // 旧版单条有效倍率（「全部增益一览」与对照测试仍用）：Σ 占比 × 该类型的倍率连乘。
  function effectiveFor(entry, shares) {
    var m = weightedMultiplier(entry.multiplier, shares);
    if (m === null) return { multiplier: 1, flat: 0, useful: false };
    var f = weightedFlat(entry.flat, shares);
    return { multiplier: m, flat: f, useful: m > USEFUL_EPSILON || f > 0 };
  }

  // ---- 单条评估 --------------------------------------------------------

  // env = { plan, out, config, ladders }；origin = { column, explicit, label, key }
  // 返回的 item.state：counted / no / context / pending / zeroStacks / tierOff / variantOff / noDamage
  // （去重后另有 duplicate，遗物不合法另有 relicInvalid）。判定顺序：不含伤害 → 多档只留选中的一档 →
  // 作用对象（notes.ranking ①）→ 减益（②）→ appliesTo → 累积阶梯 → 叠层 → 发动条件（③）。
  function evaluateEntry(entry, env, origin) {
    var config = env.config || {};
    var out = env.out;
    var src = origin || {};
    var explicit = src.explicit === true;
    var verdict = appliesVerdict(entry, out);
    var stacks = entry.stackInput ? stacksFor(entry, config, explicit) : null;
    var tables = entryTables(entry, env.plan, verdict.restrictedType, verdict.weight, stacks);
    var item = {
      entry: entry,
      column: src.column || "other",
      originLabel: src.label || "",
      originKey: src.key || "",
      explicit: explicit,
      verdict: verdict,
      needs: [],
      ticked: false,
      stacks: stacks,
      stackWarnings: entry.stackInput ? stackWarnings(entry, stacks) : [],
      tier: null,
      state: "counted",
      reasons: [],
      notes: verdict.notes.slice(),
      table: tables.table,
      flatTable: tables.flat,
      multiplier: out && out.hasComposition ? weightedMultiplier(tables.table, out.shares) : null,
      flat: out && out.hasComposition ? weightedFlat(tables.flat, out.shares) : 0
    };
    function finish(state, reasons) {
      item.state = state;
      item.reasons = reasons || [];
      return item;
    }
    if (!entry.countsAsDamage) return finish("noDamage", [TEXT.reasonNoDamage]);
    if (entry.variantGroup) {
      var variant = selectedVariant(entry, config);
      item.variant = variant;
      if (variant.id !== entry.id) {
        return finish("variantOff", [fmt(TEXT.reasonVariantOff, variant.tiers, variant.tier,
          entry.variantSource === "data" ? TEXT.variantSourceData : TEXT.variantSourceInferred)]);
      }
    }
    if (entry.target === "ally") return finish("no", [TEXT.reasonAlly]);
    if (entry.target !== "self") return finish("no", [fmt(TEXT.reasonTarget, entry.target)]);
    if (entry.direction === "decrease") return finish("no", [TEXT.reasonDecrease]);
    if (verdict.state === "no") return finish("no", verdict.reasons);
    if (verdict.state === "context") return finish("context", verdict.reasons);
    if (entry.accLadder) {
      var tier = selectedLadderTier(entry, config, env.ladders);
      item.tier = tier;
      if (tier.id !== entry.id) return finish("tierOff", [fmt(TEXT.reasonTierOff, tier.tier)]);
    }
    if (entry.stackInput && !(stacks > 0)) return finish("zeroStacks", [TEXT.reasonZeroStacks]);
    var needs = verdict.needs.slice();
    if (entry.activation !== "passive" && !entry.stackInput) {
      needs.push(TEXT.activationNeed[entry.activation] || TEXT.activationNeed.conditional);
    }
    item.needs = needs;
    if (needs.length) {
      var tick = config.ticks ? config.ticks[entry.id] : undefined;
      item.ticked = tick === true || (tick !== false && explicit);
      if (!item.ticked) return finish("pending", needs);
    }
    return finish("counted", []);
  }

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

  // 累积阶梯（accumulatorLadder）：同一组只算选中的那一层；默认取数据里收录的最高层。
  function ladderMembers(ladders, groupId) {
    return (ladders && ladders[groupId]) || [];
  }

  function selectedLadderTier(entry, config, ladders) {
    var members = ladderMembers(ladders, entry.ladderGroup);
    var chosen = config && config.tiers ? config.tiers[entry.ladderGroup] : undefined;
    var pick = null;
    members.forEach(function (member) { if (member.id === chosen) pick = member; });
    if (!pick && members.length) pick = members[members.length - 1];
    if (!pick) pick = entry;
    return { id: pick.id, tier: pick.ladderTier || 1, tiers: members.length };
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
    if (am !== bm) return am > bm;
    if (candidate.flat !== current.flat) return candidate.flat > current.flat;
    if (a.id !== b.id) return a.id < b.id;
    return false;
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
      var label = winner.originLabel ? winner.originLabel : winner.entry.name;
      if (winner.entry.id === item.entry.id) {
        item.reasons = [fmt(item.entry.behavior === "stackSelf" ? TEXT.reasonDupSameStackSelf : TEXT.reasonDupSameRefresh, label)];
      } else {
        item.reasons = [fmt(TEXT.reasonDupKey, winner.entry.name, item.entry.key)];
      }
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

  // 词条库索引：effectId → 词条；诅咒按 (sortId, effectId) 排序。
  function buildCatalogIndex(catalog) {
    var byId = new Map();
    var affixes = catalog && Array.isArray(catalog.affixes) ? catalog.affixes : [];
    affixes.forEach(function (affix) { byId.set(affix.effectId, affix); });
    var cursePoolId = cursePoolOf(affixes);
    var curses = affixes.filter(function (affix) {
      return affix.isCurse === true && (affix.poolIds || []).indexOf(cursePoolId) !== -1;
    }).sort(function (a, b) { return a.sortId !== b.sortId ? a.sortId - b.sortId : a.effectId - b.effectId; });
    return { available: affixes.length > 0, byId: byId, curses: curses, cursePoolId: cursePoolId };
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

    // 累积阶梯：组 id → 按层数排序的成员
    var ladders = {};
    entries.forEach(function (entry) {
      if (entry.ladderGroup == null) return;
      if (!ladders[entry.ladderGroup]) ladders[entry.ladderGroup] = [];
      ladders[entry.ladderGroup].push(entry);
    });
    Object.keys(ladders).forEach(function (key) {
      ladders[key].sort(function (a, b) { return a.ladderTier - b.ladderTier || a.id - b.id; });
    });

    // 局内武器词条（按 AttachEffect 列出；诅咒不进正面词条栏）
    var weaponAffixes = [];
    var weaponAffixById = {};
    ((buffsData && buffsData.weaponAffixes) || []).forEach(function (raw) {
      if (!raw || isCurseAffix(raw)) return;
      var own = (raw.spEffectIds || []).map(function (id) { return byId[id]; }).filter(Boolean);
      if (!own.some(function (entry) { return entry.countsAsDamage; })) return;
      var deepOnlyPositive = raw.deepOnlyPositive === true || own.some(function (entry) {
        return entry.buff && entry.buff.weaponAffixDeepOnlyPositive === true;
      });
      var item = {
        id: raw.attachEffectId,
        nameZh: raw.nameZh || raw.nameEn || ("#" + raw.attachEffectId),
        potency: typeof raw.potency === "number" ? raw.potency : null,
        roles: (raw.roles || []).slice(),
        compatibilityId: raw.compatibilityId,
        normalWepTypes: (raw.normalWepTypes || []).slice(),
        deepWepTypes: (raw.deepWepTypes || raw.normalWepTypes || []).slice(),
        deepOnly: raw.deepOnly === true,
        deepOnlyPositive: deepOnlyPositive,
        entries: own,
        search: [raw.nameZh, raw.nameEn, raw.paramName, raw.attachEffectId].join(" ").toLowerCase()
      };
      item.label = item.nameZh + (item.potency ? "（" + fmt(TEXT.waPotency, item.potency) + "）" : "");
      weaponAffixes.push(item);
      weaponAffixById[item.id] = item;
    });

    // 官方固定词条遗物
    var fixedRelics = [];
    var fixedRelicByKey = {};
    ((buffsData && buffsData.fixedRelics) || []).forEach(function (raw) {
      if (!raw) return;
      var key = (raw.relicIds || []).join("-") || raw.nameZh;
      var own = (raw.spEffectIds || []).map(function (id) { return byId[id]; }).filter(Boolean);
      var item = {
        key: key,
        relicIds: (raw.relicIds || []).slice(),
        nameZh: raw.nameZh || raw.nameEn || key,
        color: raw.color,
        isDeepRelic: raw.isDeepRelic === true,
        effectNames: (raw.attachEffectNamesZh || []).map(function (name, i) {
          return name || ("#" + (raw.attachEffectIds || [])[i]);
        }),
        entries: own,
        hasDamage: own.some(function (entry) { return entry.countsAsDamage; })
      };
      fixedRelics.push(item);
      fixedRelicByKey[key] = item;
    });

    // 遗物词条：词条库 effectId → 条目
    var relicAffixEntries = new Map();
    entries.forEach(function (entry) {
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
        if (!affix || affix.isCurse) return;
        if (!own.some(function (entry) { return entry.countsAsDamage; })) return;
        if (Core && typeof Core.isEligible === "function" && !Core.isEligible(affix, modeKey)) return;
        list.push({ id: effectId, affix: affix, name: affix.name, entries: own });
      });
      list.sort(function (a, b) { return a.affix.sortId - b.affix.sortId || a.id - b.id; });
      return list;
    }

    // 护符：sourceSlots 含 accessory 的条目按护符（sources[].kind=accessory 的 id）分组
    var talismans = [];
    var talismanById = {};
    entries.forEach(function (entry) {
      if (entry.slots.indexOf("accessory") === -1) return;
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
    talismans = talismans.filter(function (one) {
      return one.entries.some(function (entry) { return entry.countsAsDamage; });
    });
    talismans.sort(function (a, b) { return a.id - b.id; });

    // 其它增益：按主槽位分组；累积阶梯合成一行（行键＝阶梯第 1 层 id）
    var otherRows = {};
    OTHER_SLOTS.forEach(function (slot) { otherRows[slot] = []; });
    var seenLadder = {};
    entries.forEach(function (entry) {
      if (!entry.countsAsDamage) return;
      if (OTHER_SLOTS.indexOf(entry.slot) === -1) return;
      if (entry.ladderGroup != null) {
        if (seenLadder[entry.ladderGroup]) return;
        seenLadder[entry.ladderGroup] = true;
        var members = ladders[entry.ladderGroup] || [entry];
        otherRows[entry.slot].push({
          key: members[0].id, entries: members, ladder: true,
          name: members[0].name.replace(/（第\d+层）$/, ""), character: entry.character
        });
        return;
      }
      otherRows[entry.slot].push({ key: entry.id, entries: [entry], ladder: false, name: entry.name, character: entry.character });
    });

    return {
      plan: idx.plan,
      index: idx,
      byId: byId,
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
      otherRows: otherRows
    };
  }

  // ---- 配置（用户组的一套）----------------------------------------------

  function emptyRelicCard() {
    return { type: "empty", key: null, affixIds: [null, null, null], curseIds: [null, null, null] };
  }

  function emptyConfig() {
    return {
      runMode: "normal",
      weaponAffixes: [],        // [{ id: attachEffectId, count }]，按加入顺序
      relics: [emptyRelicCard(), emptyRelicCard(), emptyRelicCard(), emptyRelicCard(), emptyRelicCard(), emptyRelicCard()],
      accessories: [null, null],
      others: {},               // 行键（spEffectId / 阶梯第 1 层 id）→ true
      innateOff: {},            // 当前武器固有里被用户排除的 spEffectId
      ticks: {},                // spEffectId → true/false（覆盖默认确认状态）
      stacks: {},               // spEffectId → 层数
      tiers: {},                // 累积阶梯组 id → 选中的那一层 spEffectId
      variants: {}              // 多档词条组键（affix#…）→ 选中的那一档 spEffectId
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

  // 切模式：去掉新模式下不存在的词条，再从最后加入的开始削到上限以内。
  function applyRunMode(cfgIndex, config, runMode) {
    var next = cloneConfig(config);
    next.runMode = runMode === "deep" ? "deep" : "normal";
    next.weaponAffixes = next.weaponAffixes.filter(function (one) {
      return weaponAffixAvailable(cfgIndex.weaponAffixById[one.id], next.runMode) && one.count > 0;
    });
    var caps = slotCaps(cfgIndex.slotRules, next.runMode);
    function trim(limitFn, capacity) {
      for (var i = next.weaponAffixes.length - 1; i >= 0; i -= 1) {
        var usage = limitFn();
        if (usage <= capacity) return;
        var one = next.weaponAffixes[i];
        var over = usage - capacity;
        var cut = Math.min(one.count, over);
        if (limitFn === deepOnlyUsed && !cfgIndex.weaponAffixById[one.id].deepOnlyPositive) continue;
        one.count -= cut;
        if (one.count <= 0) next.weaponAffixes.splice(i, 1);
      }
    }
    function totalUsed() { return weaponAffixUsage(cfgIndex, next).used; }
    function deepOnlyUsed() { return weaponAffixUsage(cfgIndex, next).deepOnlyUsed; }
    trim(deepOnlyUsed, caps.deepOnly);
    trim(totalUsed, caps.weaponAffix);
    return next;
  }

  // ---- 遗物合法性 ------------------------------------------------------

  // 这一格算不算「用上了」：固定遗物要选中一件，自组要至少有一条词条。
  function relicCardFilled(card) {
    if (!card) return false;
    if (card.type === "fixed") return Boolean(card.key);
    if (card.type === "custom") return (card.affixIds || []).some(function (id) { return id != null; });
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

  function relicRows(card, catalogIndex) {
    var rows = [];
    var unknown = [];
    (card.affixIds || []).forEach(function (id, position) {
      if (id == null) return;
      var affix = catalogIndex.byId.get(id);
      if (!affix) { unknown.push(id); return; }
      var curseId = card.curseIds ? card.curseIds[position] : null;
      var curse = null;
      if (curseId != null) {
        curse = catalogIndex.byId.get(curseId) || null;
        if (!curse) unknown.push(curseId);
      }
      rows.push({ row: position, affix: affix, curse: curse });
    });
    return { rows: rows, unknown: unknown };
  }

  // 自组遗物检查。kind = normal / deep。返回 { status, message, issues, warnings, rows }：
  //   status = empty / partial（不足三条，预检通过）/ valid / invalid
  // 正面词条一律走 Core.check（不足三条先用占位词条补足）；深夜再按 core.js 的深夜配对口径查诅咒。
  function checkCustomRelic(card, kind, catalogIndex, Core) {
    var result = { status: "empty", message: TEXT.relicEmpty, issues: [], warnings: [], rows: [] };
    if (!catalogIndex || !catalogIndex.available || !Core || typeof Core.check !== "function") {
      result.status = "invalid";
      result.message = TEXT.relicNoCatalog;
      result.issues.push({ kind: "noCatalog", title: TEXT.relicNoCatalog, detail: "", effectIds: [] });
      return result;
    }
    var parsed = relicRows(card, catalogIndex);
    result.rows = parsed.rows;
    if (parsed.unknown.length) {
      result.status = "invalid";
      result.message = TEXT.relicInvalid;
      result.issues.push({
        kind: "unknownEffect", title: TEXT.relicUnknownEffectTitle,
        detail: fmt(TEXT.relicUnknownEffectDetail, parsed.unknown.join("、")), effectIds: parsed.unknown.slice()
      });
      return result;
    }
    if (!parsed.rows.length) return result;
    var modeKey = relicModeKey(kind);
    var affixes = parsed.rows.map(function (row) { return row.affix; });
    var padded = affixes.slice();
    while (padded.length < 3) padded.push(placeholderAffix(padded.length, modeKey, Core));
    var checked = Core.check(Core.canonicalOrder(padded), modeKey);
    checked.issues.forEach(function (issue) {
      result.issues.push({
        kind: issue.kind, title: issue.title, detail: issue.detail,
        effectIds: (issue.effectIds || []).filter(function (id) { return id > 0; })
      });
    });
    var cursePoolId = numOr(catalogIndex.cursePoolId, DEEP_CURSE_POOL_ID);
    checked.warnings.forEach(function (warning) {
      // 深夜正面口径的「仅作预检，仍需校验负面词条配对」由本页下面的 curseIssues 接着做完了，不再照抄。
      if (kind === "deep" && warning.kind === "cursePairing") return;
      result.warnings.push({ kind: warning.kind, title: warning.title, detail: warning.detail, effectIds: [] });
    });
    var curseCount = result.issues.length;
    if (kind === "deep") curseIssues(parsed.rows, result.issues, cursePoolId);
    var cursesOk = result.issues.length === curseCount;
    if (kind === "deep" && cursesOk) {
      result.warnings.push({ kind: "cursePairingChecked", title: TEXT.relicCursePairingTitle,
        detail: fmt(TEXT.relicCursePairingDetail, cursePoolId), effectIds: [] });
    }
    if (result.issues.length) {
      result.status = "invalid";
      result.message = TEXT.relicInvalid;
    } else if (parsed.rows.length < 3) {
      result.status = "partial";
      result.message = fmt(TEXT.relicPartial, parsed.rows.length, 3 - parsed.rows.length);
    } else {
      result.status = "valid";
      result.message = kind === "deep" ? TEXT.relicValidDeep : checked.message;
    }
    return result;
  }

  // 深夜诅咒配对：与 core.js auditDeepRelic / auditRelic 同一口径、同一文案。
  // 正面词条之间的重复与互斥已由 Core.check 查过，这里只补与诅咒有关的那部分。
  function curseIssues(rows, issues, cursePoolId) {
    var poolId = numOr(cursePoolId, DEEP_CURSE_POOL_ID);
    rows.forEach(function (row) {
      var line = row.row + 1;
      if (row.affix.requiresCurse && !row.curse) {
        issues.push({ kind: "curseMissing", title: TEXT.relicCurseMissingTitle,
          detail: fmt(TEXT.relicCurseMissingDetail, line, row.affix.name), effectIds: [row.affix.effectId] });
      } else if (!row.affix.requiresCurse && row.curse) {
        issues.push({ kind: "curseUnexpected", title: TEXT.relicCurseUnexpectedTitle,
          detail: fmt(TEXT.relicCurseUnexpectedDetail, line, row.curse.name), effectIds: [row.curse.effectId] });
      }
      if (row.curse && !(row.curse.isCurse === true && (row.curse.poolIds || []).indexOf(poolId) !== -1)) {
        issues.push({ kind: "curseMismatch", title: TEXT.relicCurseMismatchTitle,
          detail: fmt(TEXT.relicCurseMismatchDetail, line, row.curse.name), effectIds: [row.curse.effectId] });
      }
    });
    var all = [];
    rows.forEach(function (row) { all.push({ affix: row.affix, curse: false }); });
    rows.forEach(function (row) { if (row.curse) all.push({ affix: row.curse, curse: true }); });
    var byId = {};
    all.forEach(function (one) {
      var id = one.affix.effectId;
      if (!byId[id]) byId[id] = [];
      byId[id].push(one);
    });
    var dupIds = Object.keys(byId).filter(function (id) {
      return byId[id].length > 1 && byId[id].some(function (one) { return one.curse; });
    }).map(Number);
    if (dupIds.length) {
      issues.push({ kind: "duplicate", title: TEXT.relicDuplicateTitle,
        detail: fmt(TEXT.relicDuplicateDetail, dupIds.map(function (id) { return byId[id][0].affix.name; }).join("、")),
        effectIds: dupIds });
    }
    var byCompat = {};
    all.forEach(function (one) {
      var compat = one.affix.compatibilityId;
      if (compat === -1 || compat == null) return;
      if (!byCompat[compat]) byCompat[compat] = [];
      byCompat[compat].push(one);
    });
    var conflicting = [];
    Object.keys(byCompat).forEach(function (compat) {
      var group = byCompat[compat];
      if (group.length < 2 || !group.some(function (one) { return one.curse; })) return;
      group.forEach(function (one) {
        if (conflicting.indexOf(one.affix) === -1) conflicting.push(one.affix);
      });
    });
    if (conflicting.length) {
      issues.push({ kind: "conflict", title: TEXT.relicConflictTitle,
        detail: fmt(TEXT.relicConflictDetail, conflicting.map(function (affix) { return affix.name; }).join("、")),
        effectIds: conflicting.map(function (affix) { return affix.effectId; }) });
    }
  }

  // 给需诅咒的词条自动配第一条合法诅咒（词条库顺序），配不上就留空。
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
      for (var i = 0; i < catalogIndex.curses.length; i += 1) {
        next.curseIds[position] = catalogIndex.curses[i].effectId;
        var probe = checkCustomRelic(next, kind, catalogIndex, Core);
        var clash = probe.issues.some(function (issue) {
          return (issue.effectIds || []).indexOf(catalogIndex.curses[i].effectId) !== -1;
        });
        if (!clash) return;
      }
      next.curseIds[position] = null;
    });
    return next;
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
      return entry.countsAsDamage && entry.innate && Array.isArray(entry.innate.weaponIds) &&
        entry.innate.weaponIds.indexOf(weapon.id) !== -1;
    });
  }

  // 把配置展开成「来源 → 条目」的清单（还没评估）。
  function collectSources(cfgIndex, out, config, Core) {
    var caps = slotCaps(cfgIndex.slotRules, config.runMode);
    var list = [];
    var relicChecks = [];
    (config.weaponAffixes || []).forEach(function (one) {
      var affix = cfgIndex.weaponAffixById[one.id];
      if (!affix || !(one.count > 0) || !weaponAffixAvailable(affix, config.runMode)) return;
      for (var copy = 1; copy <= one.count; copy += 1) {
        var label = affix.label + (one.count > 1 ? " #" + copy : "");
        affix.entries.forEach(function (entry) {
          list.push({ entry: entry, column: "weaponAffix", explicit: true, label: label, key: "wa:" + affix.id + ":" + copy });
        });
      }
    });
    for (var cardIndex = 0; cardIndex < caps.relics; cardIndex += 1) {
      var card = (config.relics || [])[cardIndex] || emptyRelicCard();
      var kind = relicKindForCard(caps, cardIndex);
      var cardLabel = relicCardLabel(caps, cardIndex);
      if (card.type === "fixed") {
        var fixed = cfgIndex.fixedRelicByKey[card.key];
        relicChecks[cardIndex] = { status: fixed ? "fixed" : "empty", message: "", issues: [], warnings: [], rows: [] };
        if (!fixed) continue;
        fixed.entries.forEach(function (entry) {
          list.push({ entry: entry, column: "relic", explicit: false, label: cardLabel + "：" + fixed.nameZh, key: "relic:" + cardIndex });
        });
      } else if (card.type === "custom") {
        var check = checkCustomRelic(card, kind, cfgIndex.catalog, Core);
        relicChecks[cardIndex] = check;
        var invalid = check.status === "invalid";
        check.rows.forEach(function (row) {
          (cfgIndex.relicAffixEntries.get(row.affix.effectId) || []).forEach(function (entry) {
            list.push({
              entry: entry, column: "relic", explicit: true, invalid: invalid,
              label: cardLabel + "：" + row.affix.name, key: "relic:" + cardIndex
            });
          });
        });
      } else {
        relicChecks[cardIndex] = { status: "empty", message: "", issues: [], warnings: [], rows: [] };
      }
    }
    (config.accessories || []).slice(0, caps.accessory).forEach(function (id, slot) {
      var talisman = id == null ? null : cfgIndex.talismanById[id];
      if (!talisman) return;
      talisman.entries.forEach(function (entry) {
        list.push({ entry: entry, column: "accessory", explicit: true, label: talisman.nameZh, key: "acc:" + slot });
      });
    });
    // 当前武器固有：自动列入，但不算用户亲手放入——条件型默认未确认、叠层默认 0 层（notes.ranking ③）。
    var innate = currentInnateEntries(cfgIndex, out);
    var innateIds = {};
    innate.forEach(function (entry) {
      innateIds[entry.id] = true;
      if (config.innateOff && config.innateOff[entry.id]) return;
      list.push({ entry: entry, column: "other", explicit: false, label: TEXT.otherAutoInnate, key: "innate:" + entry.id, auto: true });
    });
    OTHER_SLOTS.forEach(function (slot) {
      (cfgIndex.otherRows[slot] || []).forEach(function (row) {
        if (!(config.others && config.others[row.key])) return;
        row.entries.forEach(function (entry) {
          if (innateIds[entry.id]) return;
          list.push({ entry: entry, column: "other", explicit: true, label: TEXT.otherGroups[slot], key: "other:" + row.key });
        });
      });
    });
    return { sources: list, relicChecks: relicChecks, caps: caps };
  }

  // ---- 整套配置的评估 ----------------------------------------------------

  function makeEnv(cfgIndex, out, config) {
    return { plan: cfgIndex.plan, out: out, config: config, ladders: cfgIndex.ladders };
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

  function evaluateConfig(cfgIndex, out, config, Core) {
    var env = makeEnv(cfgIndex, out, config);
    var collected = collectSources(cfgIndex, out, config, Core);
    var items = collected.sources.map(function (source) {
      var item = evaluateEntry(source.entry, env, source);
      item.auto = source.auto === true;
      if (source.invalid && item.state !== "noDamage") {
        item.state = "relicInvalid";
        item.reasons = [TEXT.reasonRelicInvalid];
      }
      return item;
    });
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
    var accUsed = (config.accessories || []).slice(0, collected.caps.accessory).filter(function (id) { return id != null; }).length;
    return {
      items: items,
      counted: winners,
      byColumn: byColumn,
      total: total,
      caps: collected.caps,
      relicChecks: collected.relicChecks,
      slots: {
        weaponAffix: weaponUsage,
        relic: { used: relicUsed, cap: collected.caps.relics },
        accessory: { used: accUsed, cap: collected.caps.accessory }
      },
      warnings: configWarnings(items, winners),
      hasComposition: out.hasComposition
    };
  }

  function configWarnings(items, winners) {
    var warnings = [];
    var dupByKey = {};
    var dupOrder = [];
    items.forEach(function (item) {
      if (item.state !== "duplicate") return;
      var key = item.entry.key;
      if (!dupByKey[key]) { dupByKey[key] = [item.dupOf]; dupOrder.push(key); }
      dupByKey[key].push(item);
    });
    dupOrder.forEach(function (key) {
      var names = [];
      dupByKey[key].forEach(function (item) {
        var name = item.originLabel || item.entry.name;
        if (names.indexOf(name) === -1) names.push(name);
      });
      warnings.push({ kind: "duplicate", text: fmt(TEXT.warnDuplicate, key, dupByKey[key].length, names.join("、")) });
    });
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
      var name = group[0].entry.name.replace(/（[^（）]*）$/, "").replace(/\s*[＋+]\s*[0-9０-９]+$/, "");
      warnings.push({ kind: "tiers", text: fmt(TEXT.warnTiers, name) });
    });
    var ladders = winners.filter(function (item) { return /^sp204@p/.test(item.entry.key); });
    if (ladders.length >= 2) {
      warnings.push({ kind: "ladder204", text: fmt(TEXT.warn204, ladders.map(function (item) { return item.entry.name; }).join("、")) });
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
        var name = item.originLabel || item.entry.name;
        if (group.names.indexOf(name) === -1) group.names.push(name);
      });
    });
    exclusivityOrder.forEach(function (exclusivityId) {
      var group = byExclusivity[exclusivityId];
      if (Object.keys(group.attach).length < 2) return;
      warnings.push({ kind: "exclusivity", text: fmt(TEXT.warnExclusivity, group.names.join("、"), exclusivityId) });
    });
    return warnings;
  }

  // ---- 候选的「放进去能拿到多少」-------------------------------------------

  // 一组条目（一条词条 / 一件遗物 / 一个护符）的分数：同键只取最高，跨键连乘。
  //   strict=false：按用户亲手放入的口径（条件型默认已确认），列表展示用；
  //   strict=true ：推荐口径——只要被动、自动判定生效、不用确认、不需要填层数的。
  // taken：已经占用的互斥键，这些键上的条目不再加分。
  function packageScore(entries, env, taken, strict) {
    var best = {};
    var bestItem = {};
    (entries || []).forEach(function (entry) {
      var item = evaluateEntry(entry, env, { column: "probe", explicit: !strict });
      if (item.state !== "counted") return;
      if (strict && (item.needs.length || entry.activation !== "passive" || entry.stackInput || entry.accLadder)) return;
      if (taken && taken[entry.key]) return;
      var m = item.multiplier == null ? 1 : item.multiplier;
      if (!(entry.key in best) || m > best[entry.key]) { best[entry.key] = m; bestItem[entry.key] = item; }
    });
    var score = 1;
    var flat = 0;
    var keys = Object.keys(best);
    keys.forEach(function (key) {
      score *= best[key];
      flat += bestItem[key].flat || 0;
    });
    return { score: score, flat: flat, keys: keys, items: keys.map(function (key) { return bestItem[key]; }) };
  }

  // 一组条目在当前输出下的展示状态：有任一条会计入 → counted；否则取「最接近生效」的那种原因。
  // explicit 缺省为 true（用户亲手放入的口径）；自动列入的当前武器固有传 false。
  // 多档词条未选的档（variantOff）排在最后：整条词条的状态看选中的那一档。
  function packageState(entries, env, explicit) {
    var rank = { counted: 0, pending: 1, context: 2, zeroStacks: 3, tierOff: 4, no: 5, noDamage: 6, variantOff: 7 };
    var best = null;
    var reasons = [];
    (entries || []).forEach(function (entry) {
      var item = evaluateEntry(entry, env, { column: "probe", explicit: explicit !== false });
      if (best === null || rank[item.state] < rank[best]) { best = item.state; reasons = item.reasons.slice(); }
    });
    return { state: best || "noDamage", reasons: reasons };
  }

  // 行是否「对当前输出有收益」：倍率 > 1 或有攻击力加算。没有构成时一律算有（排不出序也要能选）。
  function rowUseful(row, hasComposition) {
    if (!hasComposition) return true;
    return row.score > USEFUL_EPSILON || (row.flat || 0) > 0;
  }

  function sortRowsByScore(rows) {
    rows.sort(function (a, b) {
      if (b.score !== a.score) return b.score - a.score;
      return (a.sortId || 0) - (b.sortId || 0);
    });
    return rows;
  }

  // 武器词条栏的行（已按有效倍率排序）。filterType=null 表示「全部类别」。
  function weaponAffixRows(cfgIndex, out, config, filterType) {
    var env = makeEnv(cfgIndex, out, config);
    var rows = [];
    cfgIndex.weaponAffixes.forEach(function (affix) {
      if (!weaponAffixAvailable(affix, config.runMode)) return;
      var count = weaponAffixCount(config, affix.id);
      if (count === 0 && !weaponAffixMatchesType(affix, config.runMode, filterType)) return;
      var score = packageScore(affix.entries, env, null, false);
      var status = packageState(affix.entries, env);
      rows.push({
        affix: affix, count: count, score: score.score, flat: score.flat, state: status.state, reasons: status.reasons,
        can: canAddWeaponAffix(cfgIndex, config, affix.id), sortId: affix.id
      });
    });
    return sortRowsByScore(rows);
  }

  function relicAffixRows(cfgIndex, out, config, kind) {
    var env = makeEnv(cfgIndex, out, config);
    return sortRowsByScore(((cfgIndex.relicCandidates || {})[kind] || []).map(function (candidate) {
      var status = packageState(candidate.entries, env);
      var pack = packageScore(candidate.entries, env, null, false);
      return {
        candidate: candidate, id: candidate.id, name: candidate.name,
        score: pack.score, flat: pack.flat,
        state: status.state, reasons: status.reasons, sortId: candidate.id
      };
    }));
  }

  function fixedRelicRows(cfgIndex, out, config, kind) {
    var env = makeEnv(cfgIndex, out, config);
    return sortRowsByScore(cfgIndex.fixedRelics.filter(function (relic) {
      return relic.isDeepRelic === (kind === "deep");
    }).map(function (relic) {
      var status = packageState(relic.entries, env);
      // 固定遗物整件带进来的条件型效果默认不确认，所以分数按「随整件带入」的口径算。
      var implicitScore = 1;
      var best = {};
      relic.entries.forEach(function (entry) {
        var item = evaluateEntry(entry, env, { column: "probe", explicit: false });
        if (item.state !== "counted") return;
        var m = item.multiplier == null ? 1 : item.multiplier;
        if (!(entry.key in best) || m > best[entry.key]) best[entry.key] = m;
      });
      Object.keys(best).forEach(function (key) { implicitScore *= best[key]; });
      return {
        relic: relic, key: relic.key, name: relic.nameZh, score: implicitScore,
        potential: packageScore(relic.entries, env, null, false).score,
        state: status.state, reasons: status.reasons, sortId: relic.relicIds[0] || 0
      };
    }));
  }

  function talismanRows(cfgIndex, out, config) {
    var env = makeEnv(cfgIndex, out, config);
    return sortRowsByScore(cfgIndex.talismans.map(function (talisman) {
      var status = packageState(talisman.entries, env);
      var pack = packageScore(talisman.entries, env, null, false);
      return {
        talisman: talisman, id: talisman.id, name: talisman.nameZh,
        score: pack.score, flat: pack.flat,
        state: status.state, reasons: status.reasons, sortId: talisman.id
      };
    }));
  }

  function otherRowsFor(cfgIndex, out, config, slot) {
    var env = makeEnv(cfgIndex, out, config);
    var innateIds = {};
    currentInnateEntries(cfgIndex, out).forEach(function (entry) { innateIds[entry.id] = true; });
    return sortRowsByScore(((cfgIndex.otherRows || {})[slot] || []).map(function (row) {
      var auto = row.entries.some(function (entry) { return innateIds[entry.id]; });
      // 自动列入的固有效果按「未亲手放入」口径显示状态（条件型＝未确认），分数仍是确认后能拿到的。
      var status = packageState(row.entries, env, !auto);
      var pack = packageScore(row.entries, env, null, false);
      return {
        row: row, key: row.key, name: row.name, auto: auto,
        selected: auto ? !(config.innateOff && row.entries.every(function (entry) { return config.innateOff[entry.id]; }))
          : Boolean(config.others && config.others[row.key]),
        score: pack.score, flat: pack.flat,
        state: status.state, reasons: status.reasons, sortId: row.key
      };
    }));
  }

  // ---- 按推荐填满 ----------------------------------------------------------

  // 只填空槽、不改已选；返回 { config, added: [{column, label}] }。
  // filterType：武器词条按类别过滤（与武器词条栏当前的筛选一致；null＝全部）。
  function recommendFill(cfgIndex, out, config, Core, filterType) {
    var next = cloneConfig(config);
    var added = [];
    if (!out.hasComposition) return { config: next, added: added };
    var env = makeEnv(cfgIndex, out, next);
    var current = evaluateConfig(cfgIndex, out, next, Core);
    var taken = {};
    current.counted.forEach(function (item) { taken[item.entry.key] = true; });
    function take(keys) { keys.forEach(function (key) { taken[key] = true; }); }

    // ① 武器词条：每条最多一份（同键多份不叠加），遵守总上限与深夜专属上限。
    var candidates = cfgIndex.weaponAffixes.filter(function (affix) {
      return weaponAffixAvailable(affix, next.runMode) && weaponAffixMatchesType(affix, next.runMode, filterType);
    }).map(function (affix) {
      return { affix: affix, pack: packageScore(affix.entries, env, taken, true) };
    }).filter(function (one) {
      return one.pack.score > USEFUL_EPSILON;
    }).sort(function (a, b) {
      return b.pack.score - a.pack.score || a.affix.id - b.affix.id;
    });
    candidates.forEach(function (one) {
      var fresh = packageScore(one.affix.entries, env, taken, true);
      if (!(fresh.score > USEFUL_EPSILON)) return;
      if (!canAddWeaponAffix(cfgIndex, next, one.affix.id).ok) return;
      next = stepWeaponAffix(cfgIndex, next, one.affix.id, 1);
      env = makeEnv(cfgIndex, out, next);
      take(fresh.keys);
      added.push({ column: "weaponAffix", label: one.affix.label });
    });

    // ② 遗物：逐个空格比较「最好的固定遗物」与「贪心自组」。
    var caps = slotCaps(cfgIndex.slotRules, next.runMode);
    var usedFixed = {};
    next.relics.forEach(function (card, i) {
      if (i < caps.relics && card.type === "fixed" && card.key) usedFixed[card.key] = true;
    });
    // 固定遗物是唯一遗物（core.js 的 uniqueDuplicate：同一角色至多一件），推荐不会放第二件。
    for (var cardIndex = 0; cardIndex < caps.relics; cardIndex += 1) {
      if (relicCardFilled(next.relics[cardIndex])) continue;
      var kind = relicKindForCard(caps, cardIndex);
      var bestFixed = null;
      cfgIndex.fixedRelics.forEach(function (relic) {
        if (relic.isDeepRelic !== (kind === "deep") || usedFixed[relic.key]) return;
        var pack = packageScore(relic.entries, env, taken, true);
        if (!(pack.score > USEFUL_EPSILON)) return;
        if (!bestFixed || pack.score > bestFixed.pack.score ||
          (pack.score === bestFixed.pack.score && (relic.relicIds[0] || 0) < (bestFixed.relic.relicIds[0] || 0))) {
          bestFixed = { relic: relic, pack: pack };
        }
      });
      var custom = greedyCustomRelic(cfgIndex, env, taken, kind, Core);
      var useFixed = bestFixed && (!custom || bestFixed.pack.score >= custom.score);
      if (useFixed) {
        next.relics[cardIndex] = { type: "fixed", key: bestFixed.relic.key, affixIds: [null, null, null], curseIds: [null, null, null] };
        usedFixed[bestFixed.relic.key] = true;
        take(bestFixed.pack.keys);
        added.push({ column: "relic", label: relicCardLabel(caps, cardIndex) + "：" + bestFixed.relic.nameZh });
      } else if (custom) {
        next.relics[cardIndex] = custom.card;
        take(custom.keys);
        added.push({ column: "relic", label: relicCardLabel(caps, cardIndex) + "：" + custom.names.join("＋") });
      }
      env = makeEnv(cfgIndex, out, next);
    }

    // ③ 护符
    for (var slot = 0; slot < caps.accessory; slot += 1) {
      if (next.accessories[slot] != null) continue;
      var bestTalisman = null;
      cfgIndex.talismans.forEach(function (talisman) {
        if (next.accessories.indexOf(talisman.id) !== -1) return;
        var pack = packageScore(talisman.entries, env, taken, true);
        if (!(pack.score > USEFUL_EPSILON)) return;
        if (!bestTalisman || pack.score > bestTalisman.pack.score) bestTalisman = { talisman: talisman, pack: pack };
      });
      if (!bestTalisman) continue;
      next.accessories[slot] = bestTalisman.talisman.id;
      take(bestTalisman.pack.keys);
      added.push({ column: "accessory", label: bestTalisman.talisman.nameZh });
      env = makeEnv(cfgIndex, out, next);
    }
    return { config: next, added: added };
  }

  // 贪心自组一件遗物：每一步挑「加进去后仍合法（或预检通过）」且新增分数最高的词条，最多三条。
  function greedyCustomRelic(cfgIndex, env, taken, kind, Core) {
    var candidates = (cfgIndex.relicCandidates || {})[kind] || [];
    if (!candidates.length) return null;
    var card = emptyRelicCard();
    card.type = "custom";
    var local = {};
    Object.keys(taken).forEach(function (key) { local[key] = true; });
    var chosenKeys = [];
    var names = [];
    var score = 1;
    for (var step = 0; step < 3; step += 1) {
      var best = null;
      candidates.forEach(function (candidate) {
        if (card.affixIds.indexOf(candidate.id) !== -1) return;
        var pack = packageScore(candidate.entries, env, local, true);
        if (!(pack.score > USEFUL_EPSILON)) return;
        if (best && (pack.score < best.pack.score || (pack.score === best.pack.score && candidate.id > best.candidate.id))) return;
        var trial = { type: "custom", key: null, affixIds: card.affixIds.slice(), curseIds: card.curseIds.slice() };
        trial.affixIds[step] = candidate.id;
        trial = autoAssignCurses(trial, kind, cfgIndex.catalog, Core);
        var check = checkCustomRelic(trial, kind, cfgIndex.catalog, Core);
        if (check.status === "invalid") return;
        best = { candidate: candidate, pack: pack, card: trial };
      });
      if (!best) break;
      card = best.card;
      best.pack.keys.forEach(function (key) { local[key] = true; chosenKeys.push(key); });
      names.push(best.candidate.name);
      score *= best.pack.score;
    }
    if (!names.length) return null;
    return { card: card, score: score, keys: chosenKeys, names: names };
  }

  // ---- 全部增益一览（折叠表）----------------------------------------------

  // 全表逐条按当前输出评估（用户亲手放入的口径），countsAsDamage 且作用于自己的才列。
  function overviewRows(cfgIndex, out, config) {
    var env = makeEnv(cfgIndex, out, config);
    var rows = [];
    cfgIndex.index.entries.forEach(function (entry) {
      if (!entry.countsAsDamage) return;
      var item = evaluateEntry(entry, env, { column: "overview", explicit: true });
      rows.push(item);
    });
    var order = { counted: 0, pending: 1, context: 2, zeroStacks: 3, tierOff: 3, variantOff: 3, no: 4, noDamage: 5 };
    rows.sort(function (a, b) {
      var sa = order[a.state] > 0 && order[a.state] < 4 ? 0 : order[a.state];
      var sb = order[b.state] > 0 && order[b.state] < 4 ? 0 : order[b.state];
      if (sa !== sb) return sa - sb;
      var am = a.multiplier == null ? 1 : a.multiplier;
      var bm = b.multiplier == null ? 1 : b.multiplier;
      if (bm !== am) return bm - am;
      return a.entry.id - b.entry.id;
    });
    return rows;
  }

  // ---- 输出手段列表 ----------------------------------------------------

  function weaponsForSkill(skillsData, skill) {
    var byId = skillsData && skillsData._weaponById;
    var ids = (skill && Array.isArray(skill.weaponIds)) ? skill.weaponIds : [];
    var out = [];
    ids.forEach(function (id) {
      var weapon = byId ? byId[id] : null;
      if (weapon) out.push(weapon);
    });
    return out;
  }

  // 按 wepTypeZh 分组，组内按武器 id 升序；用于武器下拉的 optgroup。
  function groupWeapons(weapons) {
    var order = [];
    var groups = {};
    (weapons || []).forEach(function (weapon) {
      var key = weapon.wepTypeZh || weapon.wepTypeEn || "未分类";
      if (!groups[key]) { groups[key] = []; order.push(key); }
      groups[key].push(weapon);
    });
    return order.map(function (key) {
      return { label: key, weapons: groups[key] };
    });
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

  // 战技：任意一把引用它的武器能打出非 0 构成就收录。
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

  // 战技 + 法术的统一检索条目：至少有一段能算出非 0 相对值才收录。
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
        badge: "战技",
        badgeColor: "purple",
        weaponCount: Array.isArray(skill.weaponIds) ? skill.weaponIds.length : 0,
        search: foldText((skill.nameZh || "") + " " + (skill.nameEn || ""))
      });
    });
    ((skillsData && skillsData.spells) || []).forEach(function (spell) {
      if (!Array.isArray(spell.hits) || !spell.hits.length) return;
      if (!hasAnyDamage(spell.hits, null, true)) return;
      items.push({
        kind: spell.kind === "incantation" ? "incantation" : "sorcery",
        id: spell.id,
        nameZh: spell.nameZh || "",
        nameEn: spell.nameEn || "",
        badge: spell.kindZh || (spell.kind === "incantation" ? "祷告" : "魔法"),
        badgeColor: spell.kind === "incantation" ? "amber" : "blue",
        mp: spell.mp,
        search: foldText((spell.nameZh || "") + " " + (spell.nameEn || ""))
      });
    });
    return items;
  }

  function filterMeans(items, query, kind) {
    var folded = foldText(query).trim();
    return (items || []).filter(function (item) {
      if (kind === "skill" && item.kind !== "skill") return false;
      if (kind === "spell" && item.kind === "skill") return false;
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
        text = fmt(TEXT.briefStack.ladder, fmtNumber(si.perStackRatio, 4), stackParamMax(entry) || tiers.length);
        if (typeof si.practicalMaxStacks === "number") {
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
    var variantFromData = variantKeys.some(function (key) {
      return variantGroups[key].some(function (entry) { return entry.variantSource === "data"; });
    });
    var catalogIndex = cfgIndex && cfgIndex.catalog;
    var cursePool = catalogIndex && catalogIndex.available ? catalogIndex.cursePoolId : null;
    var skillSubs = skillOnlySubCategories(buffsData);
    var notes = [
      TEXT.brief.appliesTo,
      TEXT.brief.formula,
      fmt(TEXT.brief.direction, decreaseCount),
      TEXT.brief.stacking,
      TEXT.brief.tiers
    ];
    if (variantKeys.length) {
      notes.push(fmt(TEXT.brief.affixVariant, variantKeys.length, variantMembers,
        variantFromData ? TEXT.brief.affixVariantData : TEXT.brief.affixVariantInferred));
    }
    return notes.concat([
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
    meansKind: "skill",
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

  function pill(text, kind) {
    var h = helpers();
    if (h && typeof h.pill === "function") return h.pill(text, kind);
    return "<span class='pill pill--" + (kind || "purple") + "'>" + esc(text) + "</span>";
  }

  var STATE_COLOR = {
    counted: "green", duplicate: "gray", pending: "amber", context: "amber",
    no: "gray", zeroStacks: "gray", tierOff: "gray", variantOff: "gray", relicInvalid: "red", noDamage: "gray"
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
    if (spell) return Array.isArray(spell.hits) ? spell.hits.slice() : [];
    return [];
  }

  // 默认：与「使用专注值不足版本」开关同侧的段全勾，另一侧全不勾；用户手动勾选写进 overrides。
  function hitEnabled(hit) {
    if (!hit || hit.noDamage) return false;
    var override = state.hitOverrides[hit.atkId];
    if (override === true || override === false) return override;
    return Boolean(hit.noFp) === Boolean(state.noFp);
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
    return (rows || "<p class='ranker-empty'>没有匹配的战技／法术</p>") + more;
  }

  function pickerHtml() {
    var kindButtons = [
      { key: "skill", label: "战技" },
      { key: "spell", label: "法术（魔法／祷告）" }
    ].map(function (option) {
      var active = state.meansKind === option.key ? " is-active" : "";
      return "<button class='segment-button" + active + "' type='button' data-ranker-means-kind='" +
        option.key + "'>" + esc(option.label) + "</button>";
    }).join("");

    return "<div class='section-heading'><div class='section-icon'>◎</div>" +
      "<div><h2>输出手段</h2><p>搜索战技或法术（中文／英文名都可）；战技再选一把武器</p></div></div>" +
      "<div class='ranker-picker-row'>" +
      "<div class='segmented-control ranker-means-kind' role='radiogroup' aria-label='输出手段类型' " +
      "data-testid='ranker-means-kind'>" + kindButtons + "</div>" +
      "<label class='search-field ranker-means-search'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='搜索战技 / 法术名称' autocomplete='off' " +
      "data-testid='ranker-means-search'></label>" +
      "</div>" +
      "<div class='ranker-means-list' data-testid='ranker-means-list'>" + meansListHtml() + "</div>" +
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
        "<div class='ranker-selection-pills'>" + pill(spell.kindZh || "法术", spell.kind === "incantation" ? "amber" : "blue") +
        pill("专注值 " + spell.mp, "gray") + pill("法术段只用固定值", "gray") + "</div>" +
        "<div class='ranker-picker-row'>" + handControlHtml() + "</div>" +
        "<p class='ranker-note'>法术没有武器动作套：按 usage「法术 / 子弹段」只取每段的固定伤害值（flat），" +
        "不把 motion 乘到施法器攻击力上。武器槽用于匹配 appliesTo 的 requires.hand——" +
        "施法器同样占左右手之一；武器词条栏按" + esc(mode === "incantation" ? "圣印记" : "手杖") + "的类别过滤。</p></div>";
    }
    var skill = currentSkill();
    if (!skill) return "<p class='ranker-note'>找不到这个战技。</p>";
    var weapons = weaponsForSkill(state.skillsData, skill);
    var groups = groupWeapons(weapons);
    var options = groups.map(function (group) {
      return "<optgroup label='" + esc(group.label) + "'>" + group.weapons.map(function (weapon) {
        var selected = weapon.id === state.selection.weaponId ? " selected" : "";
        return "<option value='" + weapon.id + "'" + selected + ">" +
          esc(weapon.nameZh || weapon.nameEn) + "（" + esc(weapon.rarityZh || "") + "）</option>";
      }).join("") + "</optgroup>";
    }).join("");
    var weapon = currentWeapon();

    return "<div class='ranker-selection' data-testid='ranker-selection'>" +
      "<div class='ranker-selection-name'>" + esc(skill.nameZh || skill.nameEn) +
      "<span class='ranker-means-en'>" + esc(skill.nameEn) + "</span></div>" +
      "<div class='ranker-selection-pills'>" + pill("战技", "purple") +
      pill(weapons.length + " 把武器可用", "gray") +
      (skill.sparring ? pill("训练场可用", "green") : "") + "</div>" +
      "<div class='ranker-picker-row'>" +
      "<label class='select-field ranker-weapon-field'><span class='ranker-field-label'>武器</span>" +
      "<select data-testid='ranker-weapon'" + (options ? "" : " disabled") + ">" +
      (options || "<option>这个战技没有可用武器</option>") + "</select></label>" +
      handControlHtml() +
      "</div>" + weaponStatsHtml(weapon) + "</div>";
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
        ? "按 usage 的选段规则，这把武器在这个战技上没有任何命中段（weapons[].skillVariant 缺失）。"
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
      "title='只勾当前这一侧的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍'>" +
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
        "，共 " + variant.atkIds.length + " 段）。</p>"
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
        ? "<p class='ranker-quote'><span class='ranker-quote-label'>skills usage.本数据集的边界</span>" +
          esc(boundary) + "</p>"
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
    var contexts = (state.index && state.index.contexts) || [];
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
      pill(TEXT.columns.weaponAffix + " " + slots.weaponAffix.used + "/" + slots.weaponAffix.cap, "purple") +
      (caps.deepOnly ? pill(fmt(TEXT.waDeepOnlyUsage, slots.weaponAffix.deepOnlyUsed, slots.weaponAffix.deepOnlyCap), "purple") : "") +
      pill(TEXT.columns.relic + " " + slots.relic.used + "/" + slots.relic.cap, "blue") +
      pill(TEXT.columns.accessory + " " + slots.accessory.used + "/" + slots.accessory.cap, "blue") +
      "</div>";
    return "<div class='ranker-toolbar-row'>" +
      "<div class='ranker-control'><span class='ranker-field-label'>" + esc(TEXT.runModeLabel) + "</span>" +
      "<div class='segmented-control ranker-runmode' role='radiogroup' aria-label='" + esc(TEXT.runModeAria) + "' data-testid='ranker-runmode'>" +
      modeButtons + "</div></div>" +
      quick +
      "<div class='ranker-toolbar-actions'>" +
      "<label class='switch-control'><input type='checkbox' data-testid='ranker-show-inactive'" +
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

  function scoreHtml(score, stateKey, hasComposition, flat) {
    if (!hasComposition) return "<span class='ranker-score is-muted'>—</span>";
    var cls = stateKey === "counted" ? "" : " is-muted";
    return "<span class='ranker-score" + cls + "'>" + esc(fmtMultiplier(score)) +
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
    if (entry.inferred) badges += pill(TEXT.otherInferred, "gray");
    if (entry.target === "ally") badges += pill(TEXT.otherAlly, "blue");
    return badges;
  }

  // ---- 武器词条栏 ------------------------------------------------------

  function waffixListHtml(out) {
    var filterType = waFilterType(out);
    var rows = weaponAffixRows(state.cfgIndex, out, state.config, filterType);
    var query = foldText(state.waQuery).trim();
    var shown = rows.filter(function (row) {
      if (row.count > 0) return true;
      if (!state.showInactive && row.state !== "counted" && row.state !== "pending" && row.state !== "context") return false;
      if (!state.showInactive && !rowUseful(row, out.hasComposition)) return false;
      if (query && row.affix.search.indexOf(query) === -1 && foldText(row.affix.nameZh).indexOf(query) === -1) return false;
      return true;
    });
    if (!shown.length) return "<p class='ranker-empty'>" + esc(TEXT.waEmpty) + "</p>";
    return shown.map(function (row) {
      var affix = row.affix;
      var badges = "";
      if (affix.potency) badges += pill(fmt(TEXT.waPotency, affix.potency), "gray");
      if (affix.deepOnlyPositive) badges += pill(TEXT.waBadgeDeepOnly, "purple");
      if (affix.roles.indexOf("blessing") !== -1) badges += pill(TEXT.waBadgeBlessing, "blue");
      if (affix.roles.indexOf("fixed") !== -1) badges += pill(TEXT.waBadgeFixed, "gray");
      var first = affix.entries[0];
      if (first) badges += entryBadges(first);
      var inactive = row.state === "no" || row.state === "noDamage";
      return "<div class='ranker-row" + (inactive ? " is-inactive" : "") + (row.count ? " is-picked" : "") +
        "' data-ranker-wa-row='" + affix.id + "'>" +
        "<div class='ranker-row-main'><span class='ranker-row-name'>" + esc(affix.nameZh) + "</span>" +
        "<span class='ranker-row-badges'>" + badges + "</span>" +
        (row.state !== "counted" ? reasonHtml(row.reasons) : "") + "</div>" +
        scoreHtml(row.score, row.state, out.hasComposition, row.flat) +
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
    var dupNote = result.items.some(function (item) {
      return item.column === "weaponAffix" && item.state === "duplicate";
    }) ? "<p class='ranker-note ranker-note--warn'>" + esc(TEXT.waDupHint) + "</p>" : "";
    var tierNote = result.warnings.some(function (warning) { return warning.kind === "tiers"; })
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
      "<input type='search' placeholder='" + esc(TEXT.searchPlaceholder) + "' autocomplete='off' data-testid='ranker-wa-search'></label>" +
      "</div>" + dupNote + tierNote +
      "<div class='ranker-list' data-testid='ranker-wa-list'>" + waffixListHtml(out) + "</div>";
  }

  // ---- 遗物栏 ----------------------------------------------------------

  // 卡片下的逐条计入情况：多档词条未选的那几档（variantOff）不列，只列选中的一档。
  function relicEffectLinesHtml(items) {
    items = items.filter(function (item) { return item.state !== "variantOff"; });
    if (!items.length) return "";
    var needsControl = items.some(function (item) {
      return item.state === "pending" || item.state === "zeroStacks" ||
        (Boolean(item.entry.variantGroup) && item.state === "counted");
    });
    return "<ul class='ranker-mini-list'>" + items.map(function (item) {
      return "<li class='is-" + esc(item.state) + "'><span class='ranker-mini-name'>" + esc(item.entry.name) + "</span>" +
        statePill(item.state) +
        (item.multiplier != null && item.state !== "noDamage" ? "<span class='ranker-mini-mul'>" + esc(fmtMultiplier(item.multiplier)) +
          (hasFlat(item.flat) ? " · " + esc(fmt(TEXT.flatInline, fmtFlat(item.flat))) : "") + "</span>" : "") +
        (item.state !== "counted" ? reasonHtml(item.reasons) : "") + "</li>";
    }).join("") + "</ul>" +
      (needsControl ? "<p class='ranker-note ranker-note--muted'>" + esc(TEXT.cardControlsHint) + "</p>" : "");
  }

  function relicCardHtml(cardIndex, out, result) {
    var caps = result.caps;
    var kind = relicKindForCard(caps, cardIndex);
    var card = state.config.relics[cardIndex] || emptyRelicCard();
    var typeButtons = [
      { key: "empty", label: TEXT.relicTypeEmpty },
      { key: "fixed", label: TEXT.relicTypeFixed },
      { key: "custom", label: TEXT.relicTypeCustom }
    ].map(function (option) {
      var active = card.type === option.key ? " is-active" : "";
      return "<button class='segment-button" + active + "' type='button' data-ranker-relic-type='" +
        cardIndex + ":" + option.key + "'>" + esc(option.label) + "</button>";
    }).join("");
    var cardItems = result.items.filter(function (item) { return item.originKey === "relic:" + cardIndex; });
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
              relicEffectLinesHtml(cardItems.filter(function (item) { return item.state !== "noDamage"; })) + "</div>"
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
            return state.showInactive || candidate.state !== "no" || candidate.id === chosen;
          }).map(function (candidate) {
            var label = candidate.name + (out.hasComposition ? fmt(TEXT.optionScore, fmtMultiplier(candidate.score)) : "") +
              (candidate.state === "no" ? TEXT.optionInactive : "");
            return "<option value='" + candidate.id + "'" + (candidate.id === chosen ? " selected" : "") + ">" + esc(label) + "</option>";
          }).join("");
          var affix = chosen == null ? null : state.cfgIndex.catalog.byId.get(chosen);
          var curseSelect = "";
          if (kind === "deep" && affix && affix.requiresCurse) {
            var curseId = card.curseIds[row];
            curseSelect = "<label class='select-field ranker-curse-field'><span class='ranker-field-label'>" + esc(TEXT.relicCurseLabel) + "</span>" +
              "<select data-ranker-relic-curse='" + cardIndex + ":" + row + "'><option value=''>" + esc(TEXT.relicCursePlaceholder) + "</option>" +
              state.cfgIndex.catalog.curses.map(function (curse) {
                return "<option value='" + curse.effectId + "'" + (curse.effectId === curseId ? " selected" : "") + ">" + esc(curse.name) + "</option>";
              }).join("") + "</select></label>";
          }
          return "<div class='ranker-relic-row'><label class='select-field'><select data-ranker-relic-affix='" + cardIndex + ":" + row + "'>" +
            "<option value=''>" + esc(TEXT.relicAffixPlaceholder) + "</option>" + options + "</select></label>" + curseSelect + "</div>";
        }).join("");
        var statusColor = check.status === "valid" ? "green" : (check.status === "partial" ? "blue" : (check.status === "invalid" ? "red" : "gray"));
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
          relicEffectLinesHtml(cardItems.filter(function (item) { return item.state !== "noDamage"; }));
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
      "<div><h2>" + esc(TEXT.columns.relic) + "</h2><p>" + esc(TEXT.relicIntro) + "</p></div>" +
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
        return state.showInactive || row.state !== "no" || row.id === chosen;
      }).map(function (row) {
        var elsewhere = state.config.accessories.indexOf(row.id) !== -1 && row.id !== chosen;
        var label = row.name + (out.hasComposition ? fmt(TEXT.optionScore, fmtMultiplier(row.score)) : "") +
          (row.state === "no" ? TEXT.optionInactive : "") + (elsewhere ? TEXT.accUsedElsewhere : "");
        return "<option value='" + row.id + "'" + (row.id === chosen ? " selected" : "") + (elsewhere ? " disabled" : "") + ">" +
          esc(label) + "</option>";
      }).join("");
      var slotItems = result.items.filter(function (item) { return item.originKey === "acc:" + slot; });
      slots.push("<div class='ranker-talisman-slot'><label class='select-field'><span class='ranker-field-label'>" +
        esc(fmt(TEXT.accSlotLabel, slot + 1)) + "</span>" +
        "<select data-ranker-accessory='" + slot + "'><option value=''>" + esc(TEXT.accPlaceholder) + "</option>" + options +
        "</select></label>" + relicEffectLinesHtml(slotItems.filter(function (item) { return item.state !== "noDamage"; })) + "</div>");
    }
    return "<div class='section-heading'><div class='section-icon'>❖</div>" +
      "<div><h2>" + esc(TEXT.columns.accessory) + "</h2><p>" + esc(fmt(TEXT.accIntro, result.caps.accessory)) + "</p></div>" +
      "<div class='ranker-heading-pills'>" + pill(result.slots.accessory.used + " / " + result.slots.accessory.cap, "blue") + "</div></div>" +
      "<div class='ranker-talisman-grid'>" + slots.join("") + "</div>";
  }

  // ---- 其它增益栏 ------------------------------------------------------

  function stackControlHtml(entry, stacks) {
    var si = entry.stackInput;
    var max = stackParamMax(entry);
    var label = si.mode === "copies" ? TEXT.stackLabelCopies : TEXT.stackLabel;
    var hint = isGraceStack(entry) ? TEXT.stackHintGrace : "";
    return "<label class='ranker-stack'><span>" + esc(label) + "</span>" +
      "<input type='number' min='0' step='1'" + (max ? " max='" + max + "'" : "") +
      " value='" + (stacks == null ? 0 : stacks) + "' data-ranker-stacks='" + entry.id + "'" +
      (hint ? " title='" + esc(hint) + "'" : "") + "></label>";
  }

  function tierControlHtml(entry) {
    var members = ladderMembers(state.cfgIndex.ladders, entry.ladderGroup);
    var selected = selectedLadderTier(entry, state.config, state.cfgIndex.ladders);
    return "<label class='ranker-stack'><span>" + esc(TEXT.tierSelectLabel) + "</span><select data-ranker-tier='" + entry.ladderGroup + "'>" +
      members.map(function (member) {
        return "<option value='" + member.id + "'" + (member.id === selected.id ? " selected" : "") + ">" +
          esc(fmt(TEXT.tierLabel, member.ladderTier)) + "</option>";
      }).join("") + "</select></label>";
  }

  // 多档词条选档：选项写出每一档的倍率字段（加算带符号），方便按出击武器类别对照词条说明。
  function variantControlHtml(entry) {
    var members = entry.variantMembers || [entry];
    var selected = selectedVariant(entry, state.config);
    return "<label class='ranker-stack'><span>" + esc(TEXT.variantLabel) + "</span><select data-ranker-variant='" +
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
      if (!state.showInactive && row.state !== "counted" && row.state !== "pending" && row.state !== "context" && row.state !== "zeroStacks") return false;
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
    shown.forEach(function (row) {
      if (slot === "character") {
        var group = characterLabel(row.row.character);
        if (group !== lastGroup) {
          html += "<div class='ranker-list-group'>" + esc(group) + "</div>";
          lastGroup = group;
        }
      }
      var first = row.row.entries[0];
      var inactive = row.state === "no" || row.state === "noDamage";
      var controls = "";
      if (row.selected && first.stackInput) {
        controls = stackControlHtml(first, stacksFor(first, state.config, !row.auto));
      } else if (row.selected && row.row.ladder) {
        controls = tierControlHtml(first);
      }
      html += "<div class='ranker-row" + (inactive ? " is-inactive" : "") + (row.selected ? " is-picked" : "") + "'>" +
        "<label class='ranker-row-check'><input type='checkbox' data-ranker-other='" + row.key + "'" +
        (row.selected ? " checked" : "") + "><span class='sr-only'>" + esc(TEXT.selectUse) + "</span></label>" +
        "<div class='ranker-row-main'><span class='ranker-row-name'>" + esc(row.name) + "</span>" +
        "<span class='ranker-row-badges'>" + (row.auto ? pill(TEXT.otherAutoInnate, "green") : "") + entryBadges(first) + "</span>" +
        (row.state !== "counted" ? reasonHtml(row.reasons) : "") + "</div>" +
        scoreHtml(row.score, row.state, out.hasComposition, row.flat) +
        "<div class='ranker-row-controls'>" + controls + "</div></div>";
    });
    return html;
  }

  function othersHtml(out) {
    var innateHint = otherRowsFor(state.cfgIndex, out, state.config, state.otherTab).some(function (row) { return row.auto; })
      ? "<p class='ranker-note ranker-note--muted' data-testid='ranker-innate-hint'>" + esc(TEXT.otherInnateHint) + "</p>"
      : "";
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
      "<input type='search' placeholder='" + esc(TEXT.searchPlaceholder) + "' autocomplete='off' data-testid='ranker-other-search'></label>" +
      "<span class='ranker-note ranker-note--inline'>" + esc(slotNoteFor(state.otherTab)) + "</span></div>" + innateHint +
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
    var controls = "";
    if (entry.stackInput && item.state !== "no" && item.state !== "context") {
      controls += stackControlHtml(entry, item.stacks);
    }
    if (entry.accLadder && item.state !== "tierOff") controls += tierControlHtml(entry);
    if (entry.variantGroup && item.state !== "variantOff") controls += variantControlHtml(entry);
    if (item.needs.length) {
      controls += "<label class='ranker-tick' title='" + esc(item.needs.join("；")) + "'><input type='checkbox' data-ranker-tick='" +
        entry.id + "'" + (item.ticked ? " checked" : "") + "><span>" + esc(TEXT.summaryTick) + "</span></label>";
    }
    var notes = item.notes.concat(item.stackWarnings || []);
    return "<div class='ranker-sum-row is-" + esc(item.state) + "'>" +
      "<div class='ranker-row-main'><span class='ranker-row-name'>" + esc(entry.name) + "</span>" +
      "<span class='ranker-sum-origin'>" + esc(item.originLabel) + " · " + esc(entry.key) + "</span>" +
      (item.state !== "counted" ? reasonHtml(item.reasons) : (item.needs.length ? reasonHtml(item.needs) : "")) +
      (notes.length ? "<span class='ranker-reason is-note'>" + esc(notes.join("；")) + "</span>" : "") + "</div>" +
      statePill(item.state) +
      scoreHtml(item.multiplier, item.state, item.multiplier != null, item.flat) +
      "<div class='ranker-row-controls'>" + controls + "</div></div>";
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
      "</div>";
    if (!out.hasComposition) {
      return heading + totals + "<p class='ranker-empty'>" + esc(TEXT.summaryNoComposition) + "</p>";
    }
    var visible = result.items.filter(function (item) {
      if (item.state === "noDamage" || item.state === "tierOff" || item.state === "variantOff") return false;
      if (!state.showInactive && item.state === "no") return false;
      return true;
    });
    var groups = COLUMN_ORDER.map(function (column) {
      var own = visible.filter(function (item) { return item.column === column; });
      if (!own.length) return "";
      return "<div class='ranker-list-group'>" + esc(TEXT.columns[column]) + "</div>" + own.map(summaryRowHtml).join("");
    }).join("");
    var hiddenNo = result.items.filter(function (item) { return item.state === "no"; }).length;
    var warnings = result.warnings.length
      ? "<ul class='ranker-warn-list' data-testid='ranker-warnings'>" + result.warnings.map(function (warning) {
        return "<li class='is-" + esc(warning.kind) + "'>" + esc(warning.text) + "</li>";
      }).join("") + "</ul>"
      : "";
    return heading + totals + warnings +
      (hasFlat(result.total.flat) ? "<p class='ranker-note'>" + esc(TEXT.summaryFlatNote) + "</p>" : "") +
      "<div class='ranker-sum-list' data-testid='ranker-sum-list'>" +
      (groups || "<p class='ranker-empty'>" + esc(TEXT.summaryEmpty) + "</p>") + "</div>" +
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
      if (!state.showInactive && (item.state === "no" || item.state === "noDamage")) return false;
      if (query && item.entry.searchText.indexOf(query) === -1) return false;
      return true;
    });
    var shown = filtered.slice(0, state.overviewLimit);
    var list = shown.map(function (item, i) {
      var entry = item.entry;
      return "<div class='ranker-ov-row is-" + esc(item.state) + "'>" +
        "<span class='ranker-ov-rank'>" + (i + 1) + "</span>" +
        "<div class='ranker-row-main'><span class='ranker-row-name'>" + esc(entry.name) + "</span>" +
        "<span class='ranker-row-badges'>" + pill(slotLabel(state.buffsData, entry.slot), "purple") + entryBadges(entry) + "</span>" +
        (item.state !== "counted" ? reasonHtml(item.reasons) : (item.notes.length ? reasonHtml(item.notes) : "")) + "</div>" +
        scoreHtml(item.multiplier, item.state === "counted" ? "counted" : "other", true) +
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
      " · 分段 " + esc(counts.hits) + "</dd></div>" +
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
    return caveatsHtml() + noteBlocksHtml() +
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
      var weapons = weaponsForSkill(state.skillsData, skill);
      state.selection = { kind: "skill", id: id, weaponId: weapons.length ? weapons[0].id : null };
    } else {
      state.selection = { kind: kind, id: id, weaponId: null };
    }
  }

  function selectMeans(kind, id) {
    applySelection(kind, id);
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

  // 用户亲手放入的来源：清掉这些条目上残留的确认覆盖，回到「默认已确认」。
  function resetTicks(config, entries) {
    (entries || []).forEach(function (entry) { delete config.ticks[entry.id]; });
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
      state.meansKind = meansKind.dataset.rankerMeansKind;
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
      updateConfig(applyRunMode(state.cfgIndex, state.config, runMode.dataset.rankerRunmode));
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
      var next = stepWeaponAffix(state.cfgIndex, state.config, affixId, Number(stepParts[1]));
      var affix = state.cfgIndex.weaponAffixById[affixId];
      if (Number(stepParts[1]) > 0 && affix) resetTicks(next, affix.entries);
      updateConfig(next);
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
      var card = relicCardAt(next, cardIndex);
      card.type = "custom";
      card.affixIds[row] = target.value ? Number(target.value) : null;
      card.curseIds[row] = null;
      var caps = slotCaps(state.cfgIndex.slotRules, next.runMode);
      next.relics[cardIndex] = autoAssignCurses(card, relicKindForCard(caps, cardIndex), state.cfgIndex.catalog, coreRef());
      if (target.value) resetTicks(next, state.cfgIndex.relicAffixEntries.get(Number(target.value)));
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
      if (id != null && state.cfgIndex.talismanById[id]) resetTicks(next, state.cfgIndex.talismanById[id].entries);
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-other]")) {
      next = cloneConfig(state.config);
      var key = Number(target.dataset.rankerOther);
      var rowInfo = null;
      OTHER_SLOTS.forEach(function (slot) {
        (state.cfgIndex.otherRows[slot] || []).forEach(function (one) { if (one.key === key) rowInfo = one; });
      });
      var innate = currentInnateEntries(state.cfgIndex, currentOutput());
      var isInnate = rowInfo && rowInfo.entries.some(function (entry) { return innate.indexOf(entry) !== -1; });
      if (isInnate) {
        rowInfo.entries.forEach(function (entry) {
          if (target.checked) delete next.innateOff[entry.id];
          else next.innateOff[entry.id] = true;
        });
      } else if (target.checked) {
        next.others[key] = true;
        if (rowInfo) resetTicks(next, rowInfo.entries);
      } else {
        delete next.others[key];
      }
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-tick]")) {
      next = cloneConfig(state.config);
      next.ticks[Number(target.dataset.rankerTick)] = Boolean(target.checked);
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-stacks]")) {
      next = cloneConfig(state.config);
      var value = Math.max(0, Math.floor(Number(target.value)));
      next.stacks[Number(target.dataset.rankerStacks)] = isFinite(value) ? value : 0;
      updateConfig(next);
      return;
    }
    if (target.matches("[data-ranker-tier]")) {
      next = cloneConfig(state.config);
      next.tiers[Number(target.dataset.rankerTier)] = Number(target.value);
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
      TYPE_KEYS: TYPE_KEYS,
      TYPE_INFO: TYPE_INFO,
      TYPES_BY_ELEMENT: TYPES_BY_ELEMENT,
      ELEMENTS: ELEMENTS,
      ATTACK_CONTEXT_ORDER: ATTACK_CONTEXT_ORDER,
      USEFUL_EPSILON: USEFUL_EPSILON,
      OUTPUT_CLASSES: OUTPUT_CLASSES,
      CASTER_WEP_TYPE: CASTER_WEP_TYPE,
      COLUMN_ORDER: COLUMN_ORDER,
      OTHER_SLOTS: OTHER_SLOTS,
      CHARACTER_NAMES: CHARACTER_NAMES,
      selectVariant: selectVariant,
      selectHits: selectHits,
      hitOverridesFor: hitOverridesFor,
      physicalTypeForHit: physicalTypeForHit,
      usesMotion: usesMotion,
      hitContribution: hitContribution,
      hitChipPlan: hitChipPlan,
      zhFpText: zhFpText,
      composition: composition,
      hitPoise: hitPoise,
      hitStamina: hitStamina,
      parseRateFieldKey: parseRateFieldKey,
      rateFieldPlan: rateFieldPlan,
      multiplierMap: multiplierMap,
      flatMap: flatMap,
      familyKey: familyKey,
      buffDisplayName: buffDisplayName,
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
      defaultStacks: defaultStacks,
      stacksFor: stacksFor,
      stackParamMax: stackParamMax,
      stackWarnings: stackWarnings,
      stackedRates: stackedRates,
      entryTables: entryTables,
      weightedMultiplier: weightedMultiplier,
      weightedFlat: weightedFlat,
      productTable: productTable,
      effectiveFor: effectiveFor,
      evaluateEntry: evaluateEntry,
      selectedLadderTier: selectedLadderTier,
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
      relicKindForCard: relicKindForCard,
      relicCardFilled: relicCardFilled,
      checkCustomRelic: checkCustomRelic,
      autoAssignCurses: autoAssignCurses,
      currentInnateEntries: currentInnateEntries,
      collectSources: collectSources,
      evaluateConfig: evaluateConfig,
      packageScore: packageScore,
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
      packageState: packageState,
      weaponsForSkill: weaponsForSkill,
      groupWeapons: groupWeapons,
      hasAnyDamage: hasAnyDamage,
      skillHasDamage: skillHasDamage,
      buildMeansItems: buildMeansItems,
      meansWithoutDamage: meansWithoutDamage,
      filterMeans: filterMeans,
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
