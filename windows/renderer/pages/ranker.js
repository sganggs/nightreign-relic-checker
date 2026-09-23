// 增伤排名页。页面模块契约见 renderer/pages/README.md。
// 本文件由「增伤排名」功能开发者独占：只改这里与 pages/ranker.css。
//
// 数据：ctx.getGameData("skills") → resources/skills.json（schemaVersion 2）
//       ctx.getGameData("buffs")  → resources/buffs.json（schemaVersion ≥ 3；v4 / v5 只增字段，本页向前兼容）
//
// 算法口径（全部照数据集自带的说明实现，不写死任何具体数值）：
//   · 选段：usage.选段（必读）——v = skills[i].variants[weapon.skillVariant]，
//     段 = hits 中 atkId ∈ v.atkIds 的那些；variants 缺失时才退回 ctx 单选逻辑，绝不取并集，
//     一个都对不上就是「这把武器打不出段」（返回空），不退回全表。
//   · 武器段（含战技的子弹段）：该属性数值 ≈ 武器该属性攻击力 × motion/100 + flat，
//     addBaseAtk 再加一份武器该属性攻击力。
//   · 法术段：只用 flat[el]。usage「法术 / 子弹段」的理由是「施法器的 attackBase 只有 physical，
//     乘上去会凭空造出物理伤害」，结论是「motion 只在施法器该属性 attackBase 非 0 时才有意义」——
//     所以这条只对 weapon=null 的法术成立，战技的子弹段挂的是真武器、motion 是真实动作值，照常乘。
//   · 伤害类型：hits[].attribute 为 WeaponAtkAttribute / WeaponAtkAttribute2 时
//     回 weapons[].atkAttribute / atkAttribute2 取斩 / 打 / 突 / 标准。
//   · 增伤排名：notes.ranking 的 ①target ②direction ③activation ④scope（v4 起 scope.attackContexts
//     优先，非空时默认不计入，勾选该情境后才乘）⑤rates ⑥stacking ⑦displayName。
//     ①②都是**白名单**：target 只取 self（开关放开 ally），direction 只取 increase / mixed，
//     将来数据集加新取值时不会被静默放行。
//   · scope.atkAttribute（0…3 = 斩 / 打 / 突 / 标准，本版本 0 例）：倍率只落在那一个物理通道上，
//     当前构成里该通道占比为 0 时判为作用域不符。与 macOS 端 makeProfile / scopeVerdict 同口径。
//   · 推荐组合：**先剔掉不增伤的行再分桶**，「组数」＝取用条目数（macOS 端 groupCount 同一定义）；
//     纯加算行不该占掉一个叠加组。
//   · 有效倍率 = Σ_type 占比_type × Π(该类型适用的倍率字段)，attackPower 层与 damage 层都乘，
//     物理子类型倍率只乘对应子类型那一份；countsAsDamage=false 的字段一律不乘。
//   · v4 stackLadder：数据集只收第 1 层，topRates 才是满层数值；同一阶梯各层互斥、绝不相乘，
//     所以推荐组合里同一阶梯共用一个组键，另给一个「按满层计算」的可选开关。
//   · v5 selfInflictedStatus：那 20 条的 status 加算是玩家自伤，countsAsDamage 全为 false，
//     伤害乘积一个数都不受影响；本页给它们单独打标，将来若开异常累积轴必须整条排除。
//
// **两端同一口径**：macOS 版（RelicCore/SkillData.swift + BuffRanker.swift）实现的是同一套算法，
// 任何取舍改动都要同步改两边，并在 windows/tests/ranker*.test.mjs 与
// macos/Sources/RelicCoreChecks/BuffRankerChecks.swift 里各自固化同一组对照用例。
//
// 本页只做「相对伤害构成」：没有强化等级、能力值补正与 AttackElementCorrectParam，
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

  // enums.sourceKind 的展示顺序与徽标配色。
  var SOURCE_KINDS = [
    { key: "relicAffix", zh: "遗物词条", color: "purple" },
    { key: "accessory", zh: "护符／饰品", color: "blue" },
    { key: "goods", zh: "消耗品／道具", color: "green" },
    { key: "weaponPassive", zh: "武器被动", color: "amber" },
    { key: "spell", zh: "魔法／祷告", color: "blue" },
    { key: "permanent", zh: "永久强化", color: "green" },
    { key: "heroSkill", zh: "角色技艺／绝招", color: "purple" },
    { key: "other", zh: "其他", color: "gray" }
  ];

  // 战技命中在 enums.atkSubCategory 里的归属（112 战技攻击）；
  // 130＝近战武器攻击，战技命中算不算它数据集没给判据，见 scopeInfo 的注释。
  var SKILL_SUB_CATEGORY = 112;
  var MELEE_SUB_CATEGORY = 130;
  // 「这条真的增伤吗」的阈值：两端同一个数（macOS 端 BuffRankingRow.isUseful 也是它），
  // 差在小数第七位的只是加权求和的浮点噪音。
  var USEFUL_EPSILON = 1.0000001;

  // 攻击情境 chip 的固定顺序（enums.attackContext 的 15 个键；数据集里没出现的不显示）。
  // 与 macOS 端 BuffRankerIndex.attackContextOrder 逐项相同。
  var ATTACK_CONTEXT_ORDER = [
    "criticalHit", "thrustingCounter", "guardCounter", "chainFinisher",
    "chargedHeavyAttack", "chargedSkill", "chargedSpell",
    "jumpAttack", "dashAttack", "rollingAttack", "backstepAttack",
    "initialAttack", "horsebackAttack", "twoHanded", "dualWield"
  ];
  var PAGE_SIZE = 40;
  var PICKER_LIMIT = 40;

  // ============================================================== 纯计算层
  // 以下函数不碰 DOM，windows/tests/ranker.test.mjs 直接 require 本文件测试。

  function emptyTypeMap(value) {
    var out = {};
    for (var i = 0; i < TYPE_KEYS.length; i += 1) out[TYPE_KEYS[i]] = value;
    return out;
  }

  function num(value) {
    var n = Number(value);
    return isFinite(n) ? n : 0;
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
  // 「全选」只勾**当前这一侧**的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍，
  // 相对值合计直接翻倍，构成与排名权重跟着失真。
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
  // attackBase 非 0 时才有意义」——法术走 weapon=null（attackBase 全 0），所以这里直接按
  // isSpell 判；而战技的子弹段挂的是真武器（attackBase 非 0、motion 是真实动作值），
  // 一律忽略 motion 会把 203 段里的 65 段算成 0、并连带丢掉 122 段的 addBaseAtk。
  // 武器某属性 attackBase 为 0 时 attack × motion 本来就是 0，不需要额外分支。
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

  // 分段芯片的展示计划：只留「对当前武器真正有贡献」的属性。
  //
  // 这是 macOS 端 SkillDamageMath.segment + SkillSegment.visibleComponents /
  // hiddenZeroComponentCount 的逐字翻译：chip 的 motion / flat / baseAttack 与
  // SkillSegmentComponent 的三个字段一一对应，**数据集没声明的那一项写 null**
  // （不是 0），展示侧照 null 判断这一格要不要出现，两端才不会在「数据里写了个 0」
  // 这种边角上分叉。
  //
  // 动作值（motion）是「武器该属性基础攻击力的百分比」，参数表里每段常常五个属性同值
  // （尸横遍野每段都是 99% / 99% / 99% / 99% / 99%），但武器这一属性 attackBase 为 0 时
  // 乘出来恒为 0——尸山血海只有物理 46 与火 46，魔力／雷／圣三项对构成与排名毫无影响，
  // 并排列出来只会让人以为是 bug。所以展示口径统一成「这一档算出来 > 0 才显示」：
  //   · 近战段：武器该属性 attackBase > 0 且（motion > 0 或 flat > 0）；
  //   · 战技的子弹段：同上（子弹段挂的是真武器，motion 照常参与）；
  //   · addBaseAtk（额外加一份武器该属性攻击力）**单独也算一条通道**：这一档哪怕没有
  //     motion 也没有 flat 照样出芯片，写成「+基础攻击力」。漏掉它会把芯片行读成假的——
  //     113 主教冲锋 + 23000600 雷电主教大火槌的 #30000831 数据里只有 flat.fire = 55，
  //     真正打出来的 219 里有 164 来自 addBaseAtk 的标准 82 + 雷 82；本版本还有 467 对
  //     （段 × 武器）整段只靠 addBaseAtk 出伤害，漏掉就直接显示成「无伤害数值」。
  //   · 法术段：weapon 为 null、motion 不参与，等价于「flat > 0 的属性」。
  // 由此得到的不变量：**可见芯片的相对值之和 == 这一段的总量**（隐藏的那些本来就是 0）。
  // hidden 只数「motion 声明了但恒为 0」的属性，用来在行末补一句「其余属性该武器为 0」；
  // 法术段不用 motion，所以不会产生 hidden（那几项缺席的原因是法术本来就只用 flat）。
  function hitChipPlan(hit, weapon, isSpell) {
    // noDamage 段与 hitContribution 第一行同样整段短路：不出芯片，也不数 hidden。
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
      // 同一伤害类型只会来自一个属性槽，这里仍合并一次以防数据出现重复键（macOS 端同理）。
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

  // ---- 作用范围（notes.ranking ④ scope）--------------------------------

  // scope 的机读部分 + 三条本页自己承担的判定（数据集没有直接字段）：
  //  · throwOnly：affectsThrow 单独为真＝只作用于「投げ」攻击，也就是致命一击 /
  //    背刺 / 处决（『强化致命一击』全系都是这个签名）。无条件相乘会让它稳居榜首。
  //    **只在没有 scope.attackContexts 时才用这条推断**：v4 起 attackContexts 给出了
  //    机读依据（criticalHit 等），有它就以它为准。
  //  · spellOnly：weaponSlot=3 且只点亮魔法／祷告、没点亮秘术＝『强化魔法』『强化祷告』
  //    那一类只作用于法术的条目，不能算进武器／战技命中。
  //  · meleeOnly：subCategories 只有 130（近战武器攻击）而没有 112（战技攻击）。战技的近战
  //    命中算不算 130，数据集没有给出判据，本页保守地判为作用域不符并在底部说明里列出。
  // scope.spAttribute（本版本 356 条、其中 121 条带伤害倍率）是「只对带某个特殊属性／异常的
  // 攻击生效」：本页拿不到「这一段带不带该属性」的判据，按 macOS 端的更严口径默认不计入，
  // 由「包含属性／异常限定」开关放开。
  function scopeInfo(buff) {
    var scope = (buff && buff.scope) || {};
    var slot = typeof scope.weaponSlot === "number" ? scope.weaponSlot : 0;
    var sorcery = scope.affectsSorcery === true;
    var incantation = scope.affectsIncantation === true;
    var shaman = scope.affectsShaman === true;
    var thrown = scope.affectsThrow === true;
    // v4 新增；v3 数据里没有这个键，contexts 恒为空数组 → 全部判定保持原样。
    var contexts = Array.isArray(scope.attackContexts) ? scope.attackContexts.slice() : [];
    var subCategories = Array.isArray(scope.subCategories) ? scope.subCategories.slice() : [];
    // scope.atkAttribute（0…3 = 斩 / 打 / 突 / 标准）：这条倍率只作用于某一个物理攻击类型。
    // 本版本数据集 0 例，但 macOS 端已按这条实现（倍率只落在那个通道 + 当前构成里该通道
    // 占比为 0 时判为作用域不符），两端必须同口径，否则数据集补上这个字段就会立刻分叉。
    var atkAttribute = typeof scope.atkAttribute === "number" ? scope.atkAttribute : null;
    var restrictedType = (atkAttribute !== null && PHYS_BY_INDEX[atkAttribute]) || null;
    return {
      slot: slot,
      sorcery: sorcery,
      incantation: incantation,
      shaman: shaman,
      thrown: thrown,
      spAttribute: typeof scope.spAttribute === "number" ? scope.spAttribute : null,
      attributeScoped: typeof scope.spAttribute === "number",
      atkAttribute: atkAttribute,
      restrictedType: restrictedType,
      subCategories: subCategories,
      attackContexts: contexts,
      throwOnly: contexts.length ? false : (thrown && !sorcery && !incantation && !shaman),
      spellOnly: slot === 3 && (sorcery || incantation) && !shaman,
      meleeOnly: subCategories.indexOf(MELEE_SUB_CATEGORY) !== -1 &&
        subCategories.indexOf(SKILL_SUB_CATEGORY) === -1
    };
  }

  // target = { mode, hand, contexts, includeAttributeScoped }
  //   mode     "skill" | "sorcery" | "incantation"
  //   hand     1 右手 / 2 左手（法术同样按手判定：施法器也是握在某只手上的武器槽）
  //   contexts {攻击情境键: true}，用户勾选的攻击情境（v4 scope.attackContexts）
  function scopeVerdict(info, target) {
    var mode = target && target.mode;
    var hand = target && target.hand === 2 ? 2 : 1;
    var chosen = (target && target.contexts) || {};
    // notes.ranking（v4）第④步：attackContexts 非空＝只在这些攻击情境下吃得到，
    // 默认不得乘进通用排名，勾选了其中任一情境才参与。
    if (info.attackContexts && info.attackContexts.length) {
      var hit = info.attackContexts.some(function (key) { return chosen[key] === true; });
      if (!hit) {
        return { ok: false, reason: "只在特定攻击情境成立", context: true, contexts: info.attackContexts.slice() };
      }
    } else if (info.throwOnly) {
      return { ok: false, reason: "只作用于致命一击／投掷攻击" };
    }
    // wepParamChange：0（缺失）不限、3（自身）不限，1 / 2 必须对上当前手，
    // 其余取值（4 踢击）与武器 / 法术命中无关，一律判为作用域不符。
    if (info.slot !== 0 && info.slot !== 3 && info.slot !== hand) {
      return {
        ok: false,
        reason: info.slot === 1 ? "只作用于右手武器"
          : (info.slot === 2 ? "只作用于左手武器" : "只作用于别的武器槽（踢击等）")
      };
    }
    // scope.spAttribute：只对带某个特殊属性／异常的攻击生效，本页无从判定当前段带不带，
    // 默认不计入（与 macOS 端同一口径），由开关放开。
    if (info.attributeScoped && !(target && target.includeAttributeScoped)) {
      return { ok: false, reason: "限定属性／异常攻击", attribute: true };
    }
    if (mode === "skill") {
      if (info.spellOnly) return { ok: false, reason: "只作用于魔法／祷告" };
      if (info.meleeOnly) return { ok: false, reason: "只作用于近战武器攻击子类别（130）" };
    } else if (mode === "sorcery" && !info.sorcery) {
      return { ok: false, reason: "不作用于魔法" };
    } else if (mode === "incantation" && !info.incantation) {
      return { ok: false, reason: "不作用于祷告" };
    }
    if (info.subCategories.length) {
      if (mode !== "skill") return { ok: false, reason: "限定法术流派／蓄力，数据集无流派字段" };
      if (info.subCategories.indexOf(SKILL_SUB_CATEGORY) === -1) {
        return { ok: false, reason: "限定别的攻击子类别" };
      }
    }
    // scope.atkAttribute：只作用于某一个物理攻击类型。当前构成里那个通道占比为 0 就吃不到。
    // 没有构成（一段都没勾）时不判，与 macOS 端的 context.hasComposition 同一口径。
    if (info.restrictedType) {
      var shares = target && target.shares;
      var hasComposition = shares && TYPE_KEYS.some(function (key) { return num(shares[key]) > 0; });
      if (hasComposition && !(num(shares[info.restrictedType]) > 0)) {
        return { ok: false, reason: "限定物理攻击类型" };
      }
    }
    return { ok: true, reason: "" };
  }

  // scopeVerdict 需要当前伤害构成（scope.atkAttribute 那一关要看对应通道有没有占比），
  // 但 options 是调用方的对象、不能改写：这里另拼一个只读的判定目标。
  function verdictTarget(options, shares) {
    return {
      mode: options && options.mode,
      hand: options && options.hand,
      contexts: (options && options.contexts) || {},
      includeAttributeScoped: Boolean(options && options.includeAttributeScoped),
      shares: shares || null
    };
  }

  // ---- 叠加分组（stackingRules）---------------------------------------

  // 叠加组一律用数据集算好的 stacking.group（stackingRules 第 2 条：
  // stackSelf / none 用 "sp<spCategory>#<spEffectId>"，其余用 "sp<spCategory>"）。
  // stateInfo **不**参与分组：stackingRules 第 3 条明写「并不是互斥分组」，
  // 实测 stateInfo=71 下挂着 32 条互不相干的效果（护符『强化魔法』『强化祷告』、
  // 多条遗物与武器被动），按它合并会把本可共存的组合砍掉。
  function stackingGroupKey(buff) {
    var stacking = (buff && buff.stacking) || {};
    if (stacking.group) return String(stacking.group);
    return "sp" + num(stacking.spCategory);
  }

  // stackingRules 第 3 条的「交叉参考」：两条 buff 的 stateInfo 相同且非 0 时，
  // 值得怀疑它们是同一状态的不同档位。只是怀疑，不是规则，所以单独给一个默认关闭的
  // 开关（bucketRows 的 mergeStates），让用户可以按保守口径合并，也能退回原始口径。
  // behavior 本身就互斥的组（removePrevious / applyHighest / applyFirst）不需要它。
  function stateGroupKey(buff) {
    var stacking = (buff && buff.stacking) || {};
    var behavior = stacking.spCategoryBehavior;
    if (behavior !== "none" && behavior !== "stackSelf") return null;
    if (num(stacking.stateInfo) === 0) return null;
    return "state#" + stacking.stateInfo;
  }

  // 同族＝Paramdex 行名去掉档位后缀后相同（[Item - Level 3] X → [Item] X，
  // [Weapon] X - Potency 2 → [Weapon] X，[Relic] X +3 → [Relic] X）。
  // 数据集自己就用「同族」概念统一 displayName 的限定词，这里复用同一口径。
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

  // ---- buff 索引（只建一次，选段变化时不重建）--------------------------

  function sourceKindsOf(buff) {
    var seen = {};
    var kinds = [];
    ((buff && buff.sources) || []).forEach(function (source) {
      var kind = source && source.kind ? String(source.kind) : "other";
      if (seen[kind]) return;
      seen[kind] = true;
      kinds.push(kind);
    });
    return kinds.length ? kinds : ["other"];
  }

  function buffDisplayName(buff) {
    if (!buff) return "";
    return buff.displayNameZh || buff.nameZh || buff.displayNameEn || buff.nameEn ||
      buff.paramName || ("#" + buff.spEffectId);
  }

  // 把一组 rates 折成「伤害类型 → 倍率」的 9 格表：只有 countsAsDamage 且 valueKind=multiplier
  // 的字段进乘积，取值必须是有限正数且不等于该字段的默认值（数据集只列非默认值）。
  // used 非空时顺带记下用到的字段，供详情展开显示。
  // restrictedType 非空（scope.atkAttribute）时倍率只落在那一个物理通道上，
  // 与 macOS 端 makeProfile 里的 `restricted` 同一口径。
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

  // v4 stackLadder：这条只是一段叠层阶梯的第 1 层，topRates 才是满层数值。
  // 同一阶梯各层互斥（notes.stackLadder），推荐组合里必须共用一个组键，绝不能相乘。
  // tierSpEffectIds 按 v5 的口径是「第 2 层起」，这里并上自己再排序，组键取最小 id。
  function ladderInfo(buff, plan, restrictedType) {
    var raw = buff && buff.stackLadder;
    if (!raw || typeof raw !== "object") return null;
    var ids = (Array.isArray(raw.tierSpEffectIds) ? raw.tierSpEffectIds.slice() : [])
      .concat([buff.spEffectId])
      .filter(function (id) { return typeof id === "number"; })
      .sort(function (a, b) { return a - b; });
    return {
      tiers: num(raw.tiers),
      saved: raw.saved === true,
      tierSpEffectIds: ids,
      key: "ladder#" + (ids.length ? ids[0] : buff.spEffectId),
      multiplier: multiplierMap(raw.topRates, plan, null, restrictedType)
    };
  }

  // 每条 buff 预先折成「伤害类型 → 倍率 / 加算」两张 9 格表；
  // 之后选段变化只需要 Σ 占比 × 这张表，不再碰 rates。
  function indexBuff(buff, plan) {
    var rates = (buff && buff.rates) || {};
    var info = scopeInfo(buff);
    var flat = emptyTypeMap(0);
    var usedMultiplier = [];
    var usedFlat = [];
    var multiplier = multiplierMap(rates, plan, usedMultiplier, info.restrictedType);
    plan.flat.forEach(function (field) {
      var value = rates[field.key];
      if (typeof value !== "number" || !isFinite(value) || value === field.fallback) return;
      usedFlat.push({ key: field.key, zh: field.zh, value: value, types: field.types });
      field.types.forEach(function (type) { flat[type] += value; });
    });
    var others = Object.keys(rates).filter(function (key) {
      var field = plan.byKey[key];
      return !field || field.countsAsDamage !== true;
    });
    var hasMultiplier = TYPE_KEYS.some(function (type) { return multiplier[type] !== 1; });
    var hasFlat = TYPE_KEYS.some(function (type) { return flat[type] !== 0; });
    var ladder = ladderInfo(buff, plan, info.restrictedType);
    var kinds = sourceKindsOf(buff);
    var inferred = ((buff && buff.sources) || []).some(function (source) { return source && source.inferred === true; });
    return {
      id: buff.spEffectId,
      buff: buff,
      name: buffDisplayName(buff),
      paramName: buff.paramName || "",
      multiplier: multiplier,
      flat: flat,
      usedMultiplier: usedMultiplier,
      usedFlat: usedFlat,
      otherRateKeys: others,
      hasMultiplier: hasMultiplier,
      hasFlat: hasFlat,
      countsAsDamage: hasMultiplier || hasFlat,
      scope: info,
      kinds: kinds,
      inferred: inferred,
      target: buff.target || "self",
      activation: buff.activation || "conditional",
      direction: buff.direction || "increase",
      duration: typeof buff.duration === "number" ? buff.duration : -1,
      group: stackingGroupKey(buff),
      state: stateGroupKey(buff),
      family: familyKey(buff),
      ladder: ladder,
      // v5 selfInflictedStatus：status 组的加算点数是累在玩家自己身上的自伤。
      // 那些字段 countsAsDamage 全为 false，伤害乘积不受影响；本页只打标 + 写进说明，
      // 将来若加「异常累积」轴必须整条排除。
      selfInflictedStatus: buff && buff.selfInflictedStatus === true,
      // 可检索字段两端取并集：名称（中英 + displayName）+ paramName + descZh
      // + 全部来源名 + 来源类型中文标签 + spEffectId。与 macOS 端 makeProfile 的
      // searchParts 逐项相同，同一个关键词在两端必须命中同一批行。
      searchText: [
        buff.displayNameZh, buff.nameZh, buff.displayNameEn, buff.nameEn,
        buff.paramName, buff.descZh,
        ((buff.sources || []).map(function (s) { return [s.nameZh, s.nameEn, s.effectNameZh].join(" "); }).join(" ")),
        kinds.map(sourceKindLabel).join(" "),
        String(buff.spEffectId)
      ].join(" ").toLowerCase()
    };
  }

  // 数据里实际出现过的攻击情境（v4 scope.attackContexts）。v3 没有这个键 → 返回空数组，
  // 对应的整块 UI 不渲染，判定也全部是 no-op。中文名一律取 enums.attackContext[key].zh。
  //
  // 两端同一口径：
  //  · 只统计 countsAsDamage 的条目——这排 chip 是**排名列表的筛选器**，永远进不了榜的
  //    条目（没有任何伤害倍率字段）不该把数字撑大；
  //  · 顺序用下面这张固定表，不按计数排——按计数排会让数据集改一个数就把整排 chip 重排。
  function availableContexts(buffsData, entries) {
    var labels = (buffsData && buffsData.enums && buffsData.enums.attackContext) || {};
    var counts = {};
    (entries || []).forEach(function (entry) {
      if (!entry.countsAsDamage) return;
      (entry.scope.attackContexts || []).forEach(function (key) {
        counts[key] = (counts[key] || 0) + 1;
      });
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

  function indexBuffs(buffsData) {
    var plan = rateFieldPlan(buffsData);
    var entries = ((buffsData && buffsData.buffs) || []).map(function (buff) {
      return indexBuff(buff, plan);
    });
    return { plan: plan, entries: entries, contexts: availableContexts(buffsData, entries) };
  }

  // 有效倍率 = Σ_type 占比_type × Π(该类型适用的倍率字段)；
  // 加算是点数，没有绝对攻击力就折不成倍率，只按占比加权后单独展示。
  // useLadderTop＝「叠层类按满层计算」：改用 stackLadder.topRates 折出来的那张表。
  // 没有勾选任何段（占比全 0）时一律判为「算不出」，不退回任何近似值——
  // 两端同一口径：排名必须建立在一个真实的伤害构成上。
  function effectiveFor(entry, shares, useLadderTop) {
    var table = (useLadderTop && entry.ladder) ? entry.ladder.multiplier : entry.multiplier;
    var multiplier = 0;
    var flat = 0;
    var weight = 0;
    TYPE_KEYS.forEach(function (type) {
      var share = shares ? num(shares[type]) : 0;
      if (!share) return;
      weight += share;
      multiplier += share * table[type];
      flat += share * entry.flat[type];
    });
    if (weight <= 0) return { multiplier: 1, flat: 0, useful: false };
    var m = multiplier / weight;
    var f = flat / weight;
    return { multiplier: m, flat: f, useful: m > USEFUL_EPSILON || f > 0 };
  }

  // 「可用」= target / direction / activation / scope 四关都过。
  function candidateFilter(entry, options, target) {
    // notes.ranking ①：**白名单**——self 恒取，ally 看开关，其余取值（summon / enemy，
    // 以及将来新增的任何取值）一律排除。黑名单写法会在数据集加新取值时静默放行，
    // 与 macOS 端 passesEntryFilters 的 switch 同一口径。
    if (entry.target === "ally") {
      if (!options.includeAlly) return { ok: false, reason: "ally" };
    } else if (entry.target !== "self") {
      return { ok: false, reason: "target" };
    }
    // notes.ranking ②：只取 increase / mixed，别的取值（decrease 或将来的新值）一律不进。
    if (entry.direction !== "increase" && entry.direction !== "mixed") {
      return { ok: false, reason: "direction" };
    }
    if (!entry.countsAsDamage) return { ok: false, reason: "noDamageRate" };
    if (entry.activation !== "passive" && !options.includeConditional) {
      return { ok: false, reason: "activation" };
    }
    var verdict = scopeVerdict(entry.scope, target || options);
    if (!verdict.ok) {
      // 攻击情境限制与属性限定单独计数：它们不是「不适用」，而是「开关打开后才计入」。
      var reason = verdict.context ? "context" : (verdict.attribute ? "attribute" : "scope");
      return { ok: false, reason: reason, detail: verdict.reason };
    }
    return { ok: true, reason: "" };
  }

  // 把候选条目折成排名行；shares 为空（没勾任何段）时只给结构、不给倍率。
  // excluded.scopeReasons 给出「作用域不符」的分项，UI 照它展开说明。
  function rankEntries(entries, shares, options) {
    var rows = [];
    var excluded = {
      target: 0, ally: 0, direction: 0, noDamageRate: 0,
      activation: 0, scope: 0, context: 0, attribute: 0, useless: 0, scopeReasons: {}
    };
    var useLadderTop = options && options.ladderTop === true;
    var target = verdictTarget(options, shares);
    entries.forEach(function (entry) {
      var pass = candidateFilter(entry, options, target);
      if (!pass.ok) {
        excluded[pass.reason] += 1;
        if (pass.reason !== "scope" && pass.reason !== "context") return;
        if (pass.detail) {
          excluded.scopeReasons[pass.detail] = (excluded.scopeReasons[pass.detail] || 0) + 1;
        }
        return;
      }
      var effective = effectiveFor(entry, shares, useLadderTop);
      if (!effective.useful) { excluded.useless += 1; return; }
      rows.push({
        entry: entry,
        id: entry.id,
        multiplier: effective.multiplier,
        flat: effective.flat,
        // 满层数值始终算出来展示（与「按满层计算」开关无关），否则 ×1.007 看着像噪音。
        ladderTop: entry.ladder ? effectiveFor(entry, shares, true).multiplier : null,
        conditional: entry.activation !== "passive"
      });
    });
    rows.sort(function (a, b) {
      if (b.multiplier !== a.multiplier) return b.multiplier - a.multiplier;
      if (b.flat !== a.flat) return b.flat - a.flat;
      return a.id - b.id;
    });
    return { rows: rows, excluded: excluded };
  }

  // 分组键：一般是数据集算好的 stacking.group；叠层阶梯的各层共用一个键，
  // 保证同一条阶梯绝不会有两层同时进组合相乘（当前数据集每条阶梯只收第 1 层，
  // 将来收全层时这一层保护才真正派上用场）。与 macOS 端的 stackKey(for:) 同一口径。
  function stackKeyFor(entry) {
    if (entry && entry.ladder && entry.ladder.key) return entry.ladder.key;
    return entry ? entry.group : "";
  }

  // 同组内谁留下（stackingRules 第 1／4 条）：两边都是 applyHighest 时先按 categoryPriority
  // 取数值小的那一份（「同一カテゴリ内での優先度（低い方が優先）」），否则取有效倍率高的，
  // 再相同就取 spEffectId 小的。与 macOS 端的 prefers(_:over:) 同一口径。
  function prefersRow(candidate, current) {
    var a = (candidate.entry.buff && candidate.entry.buff.stacking) || {};
    var b = (current.entry.buff && current.entry.buff.stacking) || {};
    if (a.spCategoryBehavior === "applyHighest" && b.spCategoryBehavior === "applyHighest" &&
      num(a.categoryPriority) !== num(b.categoryPriority)) {
      return num(a.categoryPriority) < num(b.categoryPriority);
    }
    if (candidate.multiplier !== current.multiplier) return candidate.multiplier > current.multiplier;
    return candidate.id < current.id;
  }

  // 同组只取一条：以数据集的 stacking.group（叠层阶梯用阶梯键）为准；打开「同族只取最高档」
  // 时再把同族的组并起来，打开「同 stateInfo 视为同一状态」时再按 stateInfo 并一次。
  // 用并查集做一次合并。
  function bucketRows(rows, mergeFamilies, mergeStates) {
    var parent = {};
    function find(key) {
      if (!(key in parent)) parent[key] = key;
      while (parent[key] !== key) {
        parent[key] = parent[parent[key]];
        key = parent[key];
      }
      return key;
    }
    function add(key) { if (!(key in parent)) parent[key] = key; }
    function union(a, b) {
      add(a); add(b);
      var ra = find(a);
      var rb = find(b);
      if (ra !== rb) parent[rb] = ra;
    }
    rows.forEach(function (row) {
      var rowKey = "row#" + row.id;
      var group = "grp:" + stackKeyFor(row.entry);
      union(group, rowKey);
      if (mergeFamilies) union(group, "fam:" + row.entry.family);
      if (mergeStates && row.entry.state) union(group, "st:" + row.entry.state);
    });
    var buckets = {};
    rows.forEach(function (row) {
      var key = find("row#" + row.id);
      if (!buckets[key]) buckets[key] = [];
      buckets[key].push(row);
    });
    return buckets;
  }

  // 推荐组合：每个叠加组取有效倍率最高的一条，跨组相乘。
  //
  // **先筛后分桶**（与 macOS 端 stackPlan 同一口径）：纯加算行（multiplier 恒为 1、只有 flat）
  // 不该占掉一个叠加组。先分桶再丢弃的写法有两个毛病：① 组数会把「一条都没取到」的桶也算进去，
  // 两端显示的数字对不上；② prefersRow 在两边都是 applyHighest 时先比 categoryPriority，
  // 一条 multiplier==1 的行完全可能凭更小的 categoryPriority 赢下同组的倍率行，随后被丢掉，
  // 整组一条都不取。所以这里先把不增伤的行剔出去，`groups` 也就等于 picks.length。
  function recommendCombo(rows, mergeFamilies, mergeStates) {
    var pool = (rows || []).filter(function (row) { return row.multiplier > USEFUL_EPSILON; });
    var buckets = bucketRows(pool, mergeFamilies, mergeStates);
    var picks = [];
    Object.keys(buckets).forEach(function (key) {
      var members = buckets[key];
      var best = null;
      members.forEach(function (row) {
        if (!best) { best = row; return; }
        if (prefersRow(row, best)) best = row;
      });
      if (best) picks.push({ row: best, size: members.length });
    });
    // 并列时按 spEffectId 升序，与 macOS 端 stackPlan 的 picks 排序一致
    //（rankEntries / rankResult 的主排序两端都有这条 tiebreak，组合列表也不能漏）。
    picks.sort(function (a, b) {
      if (b.row.multiplier !== a.row.multiplier) return b.row.multiplier - a.row.multiplier;
      return a.row.id - b.row.id;
    });
    var product = 1;
    var flat = 0;
    picks.forEach(function (pick) {
      product *= pick.row.multiplier;
      flat += pick.row.flat;
    });
    return { picks: picks, product: product, flat: flat, groups: picks.length };
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

  // 这条输出手段至少有一段能算出非 0 的相对值吗？算不出来的（全是 noDamage、
  // 或只有占位 motion 而武器该属性攻击力为 0）选中后构成恒为 0，是死路。
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

  // 被输出手段列表挡在外面的条数：有段、有武器，但一段都算不出非 0 相对值的战技；
  // 有段但一个固定值都没有的法术。底部说明照这里现算，绝不写死具体数字——
  // 与 macOS 端 SkillDataIndex.skillsWithoutDamage / spellsWithoutDamage 同一口径。
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

  // 战技 + 法术的统一检索条目。
  // 战技必须同时有命中段与引用它的武器：没有武器就拿不到 attackBase，
  // 也就算不出任何构成（这类战技的段在本作根本打不出来）。
  // 另外两侧统一一条口径：**至少有一段能算出非 0 相对值**才收录——否则选中后构成恒为 0，
  // 页面只会停在「当前没有勾选任何带伤害的段」（战技 6 条纯增益技、法术 18 条恢复／庇佑）。
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
      // 法术没有武器，构成只来自 flat；一个 flat 都没有的（冰雾、各种恢复／庇佑／防护）排除。
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

  // 「本页自己承担的判定」13 条：与 macOS 端 RelicCore/BuffRanker.swift 的
  // BuffRankerPageNotes.rules **逐字同文**，任何一句改动都要同时改两边
  //（两端测试各有一份锚点表 + 正文摘要把顺序与措辞钉住）。
  // 所有条数一律照数据现算，不写死任何具体数值。抽成纯函数是为了让测试能直接对照。
  function pageRuleNotes(skillsData, buffsData, index) {
    var hasContexts = ((index && index.contexts) || []).length > 0;
    var buffList = (buffsData.buffs || []);
    var attributeScoped = buffList.filter(function (buff) {
      return buff.scope && typeof buff.scope.spAttribute === "number";
    }).length;
    var ladderCount = buffList.filter(function (buff) { return buff.stackLadder; }).length;
    var selfInflicted = buffList.filter(function (buff) { return buff.selfInflictedStatus === true; }).length;
    var meleeOnly = ((index && index.entries) || []).filter(function (entry) {
      return entry.scope.meleeOnly;
    }).length;
    var withoutDamage = meansWithoutDamage(skillsData);
    return [
      "选段一律走 weapons[].skillVariant → skills[].variants[i].atkIds，不按 ctx 取并集" +
        "（usage.选段（必读））；一个都对不上就是这把武器打不出段。",
      "只有法术段忽略 motion：usage「法术 / 子弹段」的结论是「motion 只在施法器该属性 attackBase 非 0 时" +
        "才有意义」，而法术在本页走「没有武器」这一路（attackBase 全 0）。战技的子弹段挂的是真武器、" +
        "motion 是真实动作值，照常按 攻击力 × motion/100 + flat 计算，addBaseAtk 也照常加一份。",
      "只有 rateFields[].countsAsDamage 为 true 且 valueKind 为 multiplier 的字段进入连乘；" +
        "特攻（weakness）、致命一击（critical）是 conditionalDamage，削韧／异常／special／flag／economy 一律不乘。",
      "武器槽（scope.weaponSlot）：缺失与 3（自身）视为不限，1／2 必须对上当前选的手，其余取值" +
        "（4 踢击）判为作用域不符。法术同样按当前手判定——施法器也占左右手之一。",
      "scope.spAttribute（只对带某种属性／异常的攻击生效，本版本 " + attributeScoped + " 条）默认不计入：" +
        "本页拿不到「这一段带不带该属性」的判据，要看请打开「包含属性／异常限定」。",
      "叠层阶梯（stackLadder，本版本 " + ladderCount + " 条）：数据集只收第 1 层，topRates 才是满层数值。" +
        "行上同时标出第 1 层与满层倍率；同一阶梯的各层互斥（notes.stackLadder），" +
        "推荐组合里共用一个叠加组，绝不相乘；想按满层看请打开「叠层类按满层计算」。",
      "selfInflictedStatus（v5，本版本 " + selfInflicted + " 条）标的是「status 组的加算点数累在玩家自己身上」" +
        "的自伤行。这些字段 countsAsDamage 全为 false，伤害排名的乘积一个数都不受它们影响；" +
        "本页只在行上打「自伤型异常累积」标，将来若加异常累积轴必须整条排除。",
      "本页额外做了三条数据集没有直接字段的判定：① affectsThrow 单独为真＝只作用于致命一击／投掷攻击" +
        "（『强化致命一击』全系都是这个签名，无条件相乘会让它稳居榜首）——" +
        (hasContexts
          ? "这条只在该条目没有 scope.attackContexts 时才用，有 attackContexts 就以它为准；"
          : "数据集给出 scope.attackContexts 后，本页会改以该字段为准；") +
        "② weaponSlot=3 且只点亮魔法／祷告、没点亮秘术＝只作用于法术（『强化魔法』『强化祷告』）；" +
        "③ subCategories 只标 130（近战武器攻击）而没有 112（战技攻击）的条目" +
        "（『提升近战攻击力』等 " + meleeOnly + " 条）在战技模式下判为作用域不符——" +
        "战技的近战命中算不算 130，数据集没有给出判据，本页取保守口径，" +
        "排除条数按原因分项列在「增伤排名」的汇总行下方。",
      "叠加分组只用数据集算好的 stacking.group（叠层阶梯的各层共用一个阶梯键）；stateInfo 默认不参与分组" +
        "（stackingRules 第 3 条：它「并不是互斥分组」，实测同一个 stateInfo 下挂着几十条互不相干的效果）。" +
        "需要保守口径时可在「推荐组合」里打开「同 stateInfo 视为同一状态」。" +
        "同组留哪一条：两边都是 applyHighest 时按 categoryPriority 取数值小的那一份" +
        "（stackingRules 第 4 条「低い方が優先」），否则取有效倍率高的。",
      "「推荐组合」用全部命中条目计算，不受排名列表的搜索框与来源类型筛选影响——那两个是视图筛选；" +
        "要排除某一条请在列表里勾掉它，会即时回退到同组次高的那一条。",
      "攻击力加算（attackPowerFlat）是点数，必须先加进攻击力再乘倍率；本页没有绝对攻击力，" +
        "所以只按占比加权展示，不折成倍率、不进连乘。",
      "输出手段列表只收「至少有一段能算出非 0 相对值」的战技与法术：战技还要求至少有一把武器引用它" +
        "（没有武器就没有 attackBase），法术要求至少有一段带固定值。纯增益的战技（" + withoutDamage.skills +
        " 条）与恢复／庇佑类法术（" + withoutDamage.spells + " 条）选中后构成恒为 0，是死路，所以不进列表。",
      hasContexts
        ? "只在特定攻击情境成立的倍率（scope.attackContexts：突刺反击／防御反击／跳跃攻击…）" +
          "按 notes.ranking 第④步默认不计入，在「增伤排名」里勾选对应情境后才参与乘算。"
        : "有些增益的生效条件写在攻击本身而不是 SpEffect 的 scope 里（例如『强化突刺反击』这类反击时机）。" +
          "当前数据版本还没有 scope.attackContexts，数据集把它们标成 activation=passive、" +
          "activationSource=noEvidence，本页没有依据把它们排除，看到明显只在特定时机成立的条目请自行勾掉；" +
          "数据集补上 attackContexts 后本页会自动按情境分区。"
    ];
  }

  // ---- 格式化 ----------------------------------------------------------

  function fmtPercent(value, digits) {
    var n = num(value) * 100;
    return n.toFixed(typeof digits === "number" ? digits : 1) + "%";
  }

  function fmtMultiplier(value) {
    return "×" + num(value).toFixed(3);
  }

  function fmtGain(value) {
    var n = (num(value) - 1) * 100;
    return (n >= 0 ? "+" : "") + n.toFixed(1) + "%";
  }

  function fmtNumber(value, digits) {
    var n = num(value);
    var fixed = n.toFixed(typeof digits === "number" ? digits : 1);
    return fixed.replace(/\.0+$/, "").replace(/(\.\d*?)0+$/, "$1");
  }

  function fmtDuration(seconds) {
    var n = num(seconds);
    if (n < 0) return "永久";
    if (n === 0) return "瞬间";
    return fmtNumber(n, 1) + " 秒";
  }

  function sourceKindLabel(kind) {
    for (var i = 0; i < SOURCE_KINDS.length; i += 1) {
      if (SOURCE_KINDS[i].key === kind) return SOURCE_KINDS[i].zh;
    }
    return kind;
  }

  function sourceKindColor(kind) {
    for (var i = 0; i < SOURCE_KINDS.length; i += 1) {
      if (SOURCE_KINDS[i].key === kind) return SOURCE_KINDS[i].color;
    }
    return "gray";
  }

  // ================================================================ 渲染层

  var dom = null;
  var ctxRef = null;

  var state = {
    loaded: false,
    skillsData: null,
    buffsData: null,
    index: null,
    means: [],
    meansKind: "skill",
    meansQuery: "",
    selection: null,      // { kind, id, weaponId }
    hand: 1,
    noFp: false,
    hitOverrides: {},     // atkId → true/false
    buffQuery: "",
    kindOff: {},          // sourceKind → true 表示筛掉
    includeConditional: false,
    includeAlly: false,
    includeAttributeScoped: false,  // scope.spAttribute 限定，默认不计入
    ladderTop: false,               // 叠层阶梯（stackLadder）按满层计算
    mergeFamilies: true,
    mergeStates: false,   // stackingRules 第 3 条的交叉参考，默认按原始口径不合并
    contexts: {},         // 用户勾选的攻击情境（v4 scope.attackContexts）
    dropped: {},          // 被动条目里被用户勾掉的
    picked: {},           // 条件型里被用户勾上的
    limit: PAGE_SIZE
  };

  function helpers() {
    return ctxRef && ctxRef.helpers ? ctxRef.helpers : null;
  }

  // 展示层统一口径：数据集原文里还留着英文的 FP——hits[].labelZh 的「无FP版」（本版本
  // 162 段）、caveats 第 4 条的「12 段（6 段带 FP + 6 段 No FP）」——页面一律说中文的
  // 「专注值」。只换展示：数据集、JSON 字段名与 noFp 字段一个都不动。
  //
  // 规则表与 macOS 端 SkillTextZh.fpText 逐条相同（两端都走正则，`\s` 把全角空格一起吃下，
  // 数据集以后写成「无　FP版」也不会只有一端替换掉），顺序有意义：先认长的写法，
  // 最后才把剩下的孤零零 FP 换成「专注值」。
  //
  // 只对这两处**说明文字**用。buffs 数据集里「Determination - Right No FP Damage Buff」
  // 这类是游戏参数表的英文原名（本版本上百条），套上去只会变成中英夹杂的乱码。
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

  function rankOptions() {
    return {
      mode: currentMode(),
      hand: state.hand,
      includeAlly: state.includeAlly,
      includeConditional: state.includeConditional,
      includeAttributeScoped: state.includeAttributeScoped,
      ladderTop: state.ladderTop,
      contexts: state.contexts
    };
  }

  function visibleRows(rows) {
    var query = foldText(state.buffQuery).trim();
    return rows.filter(function (row) {
      var kinds = row.entry.kinds;
      var kindOk = kinds.some(function (kind) { return !state.kindOff[kind]; });
      if (!kindOk) return false;
      if (!query) return true;
      return row.entry.searchText.indexOf(query) !== -1;
    });
  }

  function rowPicked(row) {
    if (row.conditional) return state.picked[row.id] === true;
    return state.dropped[row.id] !== true;
  }

  // ---- HTML 片段 -------------------------------------------------------

  function header() {
    return "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>增伤排名</h1><p>按战技／法术的伤害构成，给增伤手段排一个相对收益顺序</p></div>" +
      "</header>";
  }

  function unavailableShell(message) {
    return "<div class='page-content ranker-content'>" + header() +
      "<article class='card page-placeholder-card' data-testid='ranker-card'>" +
      "<div class='section-heading'><div class='section-icon'>⇗</div>" +
      "<div><h2>数据未内置</h2><p>" + esc(message) + "</p></div></div>" +
      "<div class='page-status-row'>" + pill("数据未内置", "amber") +
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
      "<section class='card ranker-rank' data-testid='ranker-rank'></section>" +
      "<section class='card ranker-combo' data-testid='ranker-combo'></section>" +
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
      "<div><h2>选择输出手段</h2><p>搜索战技或法术（中文／英文名都可）；战技再选一把武器</p></div></div>" +
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

  // 武器槽（手）选择：法术也要给——scope.weaponSlot 对施法器同样区分左右手，
  // 两端统一按「当前手」判定（macOS 端同此）。
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
        "不把 motion 乘到施法器攻击力上。武器槽用于匹配 scope.weaponSlot——" +
        "施法器同样占左右手之一，只作用于另一只手的增益不计入。</p></div>";
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
      // 与 macOS 端 RankerSegmentRow.componentChip 同文同序：动作值 → 固定值 →
      // 「+基础攻击力」，分隔符是「 · 」。判 null 而不是判真假，数据里写 0 也照样列出来。
      var parts = [];
      if (chip.motion !== null) parts.push(fmtNumber(chip.motion, 0) + "%");
      if (chip.flat !== null) parts.push("固定 " + fmtNumber(chip.flat, 0));
      if (chip.baseAttack !== null) parts.push("+基础攻击力");
      return "<span class='ranker-hit-el ranker-hit-el--" + esc(chip.type) + "'>" +
        esc(label) + " " + esc(parts.join(" · ")) + "</span>";
    });
    // 全部属性都无贡献 → 维持原来的「无伤害数值」。
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
      // 段级徽标与 macOS 端 RankerSegmentRow 同文同色：「专注值不足版」「只挂状态」。
      // 「只挂状态」比「无伤害」更准确——这些段仍会挂上异常，只是不产生伤害数值。
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
      // 「没蓝时打出的弱化版战技」只放在 title 里：.switch-control 是 nowrap，再并一段
      // 可见小字会把整条工具条撑长，窄窗口下只能靠 flex-wrap 兜底，而且与 title 完全同文。
      // macOS 端 BuffRankerView 的 Toggle 也是同样处理（help 留着，并排的 Text 去掉）。
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
      "<div><h2>伤害构成</h2><p>勾选段的相对占比，用来给增伤手段加权</p></div></div>";
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

  // ---- 增伤排名 --------------------------------------------------------

  function buffDetailHtml(entry) {
    var parts = entry.usedMultiplier.map(function (field) {
      return "<span class='ranker-rate'>" + esc(field.zh) + " ×" + fmtNumber(field.value, 3) + "</span>";
    });
    entry.usedFlat.forEach(function (field) {
      parts.push("<span class='ranker-rate ranker-rate--flat'>" + esc(field.zh) + " " +
        (field.value >= 0 ? "+" : "") + fmtNumber(field.value, 1) + "</span>");
    });
    if (entry.otherRateKeys.length) {
      parts.push("<span class='ranker-rate ranker-rate--muted'>另有 " + entry.otherRateKeys.length +
        " 个不计入伤害的字段</span>");
    }
    return parts.join("");
  }

  function buffSourcesHtml(entry) {
    var names = [];
    (entry.buff.sources || []).forEach(function (source) {
      var name = source.nameZh || source.nameEn;
      if (name && names.indexOf(name) === -1) names.push(name);
    });
    var shown = names.slice(0, 3).map(esc).join("、");
    if (names.length > 3) shown += " 等 " + names.length + " 个";
    return shown || esc(entry.paramName || "来源未知");
  }

  // v4 enums.attackContext / enums.stateInfo 的中文标签；v3 没有就退回原值。
  function contextLabel(key) {
    var labels = (state.buffsData && state.buffsData.enums && state.buffsData.enums.attackContext) || {};
    return (labels[key] && labels[key].zh) || key;
  }

  // 两端同一个格式：中文在前、数字在括号里（「强化致命一击（367）」）。
  // 与 macOS 端 BuffDataset.stateInfoLabel 逐字符相同。
  function stateInfoLabel(value) {
    var labels = (state.buffsData && state.buffsData.enums && state.buffsData.enums.stateInfo) || {};
    var one = labels[String(value)];
    return one && one.zh ? one.zh + "（" + value + "）" : String(value);
  }

  function buffRowHtml(row, rank) {
    var entry = row.entry;
    var badges = entry.kinds.map(function (kind) {
      return pill(sourceKindLabel(kind), sourceKindColor(kind));
    }).join("");
    if (entry.scope.attackContexts.length) {
      badges += pill("情境：" + entry.scope.attackContexts.map(contextLabel).join("／"), "amber");
    }
    if (entry.target === "ally") badges += pill("队友增益", "blue");
    if (entry.inferred) badges += pill("来源为推断", "gray");
    if (entry.activation === "conditional") badges += pill("需满足条件", "amber");
    if (entry.activation === "activated") badges += pill("发动期间", "amber");
    if (entry.ladder) {
      badges += pill("叠层 1/" + entry.ladder.tiers + (entry.ladder.saved ? " · 存档保留" : ""), "amber");
    }
    // v5：status 组的加算是玩家自伤，不是「攻击附带累积」；不打标用户会当成增益。
    if (entry.selfInflictedStatus) badges += pill("自伤型异常累积", "gray");

    var stacking = entry.buff.stacking || {};
    var checked = rowPicked(row) ? " checked" : "";
    var ladderValue = entry.ladder && typeof row.ladderTop === "number"
      ? "<span class='ranker-buff-ladder'>满 " + entry.ladder.tiers + " 层 " +
        fmtMultiplier(row.ladderTop) + "</span>"
      : "";

    return "<div class='ranker-buff-row" + (row.conditional ? " is-conditional" : "") + "' " +
      "data-ranker-buff-row='" + entry.id + "'>" +
      "<label class='ranker-buff-pick'><input type='checkbox' data-ranker-buff='" + entry.id + "'" +
      checked + "><span class='sr-only'>纳入推荐组合</span></label>" +
      "<span class='ranker-buff-rank'>" + rank + "</span>" +
      "<div class='ranker-buff-main'>" +
      "<div class='ranker-buff-name'>" + esc(entry.name) + "</div>" +
      "<div class='ranker-buff-badges'>" + badges + "</div>" +
      "<div class='ranker-buff-source'>" + buffSourcesHtml(entry) + "</div>" +
      "</div>" +
      "<div class='ranker-buff-value'>" +
      "<strong>" + fmtMultiplier(row.multiplier) + "</strong>" +
      "<span>" + fmtGain(row.multiplier) + "</span>" +
      (row.flat ? "<span class='ranker-buff-flat'>攻击力 +" + fmtNumber(row.flat, 1) + "</span>" : "") +
      ladderValue +
      "</div>" +
      "<div class='ranker-buff-rates'>" + buffDetailHtml(entry) + "</div>" +
      "<div class='ranker-buff-meta'>" +
      "<span>" + esc(fmtDuration(entry.duration)) + "</span>" +
      "<span class='ranker-buff-group'>叠加组 " + esc(entry.group) + "</span>" +
      "<span class='ranker-buff-group'>spCategory " + esc(stacking.spCategory) +
      " · stateInfo " + esc(stateInfoLabel(stacking.stateInfo)) + "</span>" +
      "</div></div>";
  }

  function kindFilterHtml() {
    return SOURCE_KINDS.map(function (kind) {
      var on = !state.kindOff[kind.key];
      return "<button class='ranker-chip" + (on ? " is-on" : "") + "' type='button' " +
        "data-ranker-kind='" + kind.key + "' aria-pressed='" + (on ? "true" : "false") + "'>" +
        esc(kind.zh) + "</button>";
    }).join("");
  }

  // 攻击情境（v4 scope.attackContexts）。默认一个都不勾＝这些条目不计入通用排名；
  // 勾上「跳跃攻击」就表示「我这一下是跳跃攻击」，对应的倍率才参与乘算。
  // v3 数据没有这个键 → contexts 为空 → 整块不渲染。
  function contextFilterHtml() {
    var contexts = (state.index && state.index.contexts) || [];
    if (!contexts.length) return "";
    var chips = contexts.map(function (item) {
      var on = state.contexts[item.key] === true;
      return "<button class='ranker-chip ranker-chip--context" + (on ? " is-on" : "") + "' type='button' " +
        "data-ranker-context='" + esc(item.key) + "' aria-pressed='" + (on ? "true" : "false") + "'>" +
        esc(item.zh) + "<span class='ranker-chip-count'>" + item.count + "</span></button>";
    }).join("");
    return "<div class='ranker-context-block' data-testid='ranker-contexts'>" +
      "<div class='ranker-field-label'>攻击情境（勾选后这些只在特定情境成立的倍率才参与乘算）</div>" +
      "<div class='ranker-chip-row'>" + chips + "</div>" +
      "<p class='ranker-note'>数据集的 scope.attackContexts：这些条目只在列出的情境下吃得到，" +
      "按 notes.ranking 第④步默认不计入通用排名。</p></div>";
  }

  // 「作用域不符」的分项：数据集没给判据、由本页承担的判定（例如只标 130 近战武器攻击的条目）
  // 不该藏在一个总数里。
  function scopeBreakdownHtml(excluded) {
    var reasons = excluded.scopeReasons || {};
    // 条数降序、同数按原因串排（与 macOS 端 scopeReasonBreakdown 同一顺序，
    // 没有 tiebreak 的话两端的分项顺序会随各自的 key 遍历顺序漂移）。
    var keys = Object.keys(reasons).sort(function (a, b) {
      if (reasons[b] !== reasons[a]) return reasons[b] - reasons[a];
      return a < b ? -1 : (a > b ? 1 : 0);
    });
    if (!keys.length) return "";
    return "<p class='ranker-note ranker-note--muted' data-testid='ranker-scope-breakdown'>" +
      "作用域不符的分项：" + keys.map(function (key) {
        return esc(key) + " " + reasons[key] + " 条";
      }).join("；") + "。</p>";
  }

  function rankBodyHtml(comp, result) {
    if (!comp.hasDamage) {
      return "<p class='ranker-empty' data-testid='ranker-rank-empty'>先勾选至少一段带伤害的命中。</p>";
    }
    var rows = visibleRows(result.rows);
    var shown = rows.slice(0, state.limit);
    var list = shown.map(function (row, index) { return buffRowHtml(row, index + 1); }).join("");
    var more = rows.length > shown.length
      ? "<button class='button button--secondary button--wide ranker-more' type='button' " +
        "data-testid='ranker-more'>再显示 " + Math.min(PAGE_SIZE, rows.length - shown.length) +
        " 条（剩余 " + (rows.length - shown.length) + " 条）</button>"
      : "";

    var excluded = result.excluded;
    var summary = "<div class='page-status-row' data-testid='ranker-rank-summary'>" +
      pill("命中 " + rows.length + " 条", "green") +
      pill("显示前 " + shown.length + " 条", "gray") +
      pill("作用域不符 " + excluded.scope + " 条", "gray") +
      pill("对当前构成无收益 " + excluded.useless + " 条", "gray") +
      (excluded.context ? pill("受攻击情境限制 " + excluded.context + " 条未计入", "amber") : "") +
      (state.includeAttributeScoped || !excluded.attribute
        ? ""
        : pill("属性／异常限定 " + excluded.attribute + " 条未计入", "amber")) +
      (state.includeConditional ? "" : pill("条件／发动型 " + excluded.activation + " 条未计入", "amber")) +
      (state.includeAlly ? "" : pill("队友增益 " + excluded.ally + " 条未计入", "amber")) +
      "</div>" + scopeBreakdownHtml(excluded);

    return summary + "<div class='ranker-buff-list' data-testid='ranker-buff-list'>" +
      (list || "<p class='ranker-empty'>没有匹配的增益条目</p>") + "</div>" + more;
  }

  function rankingHtml(comp, result) {
    var heading = "<div class='section-heading'><div class='section-icon'>↥</div>" +
      "<div><h2>增伤排名</h2><p>有效倍率 = Σ 占比 × 该伤害类型适用的倍率连乘</p></div></div>";

    var filters = "<div class='ranker-filter-row'>" +
      "<label class='search-field ranker-buff-search'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='搜索增益名称、来源或 Paramdex 行名' autocomplete='off' " +
      "data-testid='ranker-buff-search'></label>" +
      "<label class='switch-control'><input type='checkbox' data-testid='ranker-conditional'" +
      (state.includeConditional ? " checked" : "") + "><span class='switch-track'></span>" +
      "<span>包含条件型（需触发）</span></label>" +
      "<label class='switch-control'><input type='checkbox' data-testid='ranker-ally'" +
      (state.includeAlly ? " checked" : "") + "><span class='switch-track'></span>" +
      "<span>包含队友给的增益</span></label>" +
      "<label class='switch-control' title='scope.spAttribute 限定：只对带某种属性／异常的攻击生效。" +
      "本页拿不到「这一段带不带该属性」的判据，默认不计入'>" +
      "<input type='checkbox' data-testid='ranker-attribute'" +
      (state.includeAttributeScoped ? " checked" : "") + "><span class='switch-track'></span>" +
      "<span>包含属性／异常限定</span></label>" +
      "<label class='switch-control' title='stackLadder：数据集只收第 1 层，topRates 才是满层数值。" +
      "同一阶梯各层互斥，永远只按一层计算'>" +
      "<input type='checkbox' data-testid='ranker-ladder-top'" +
      (state.ladderTop ? " checked" : "") + "><span class='switch-track'></span>" +
      "<span>叠层类按满层计算</span></label>" +
      "</div>" +
      "<div class='ranker-chip-row' data-testid='ranker-kinds'>" + kindFilterHtml() + "</div>" +
      contextFilterHtml();

    return heading + filters +
      "<div data-testid='ranker-rank-body'>" + rankBodyHtml(comp, result) + "</div>";
  }

  // ---- 推荐组合 --------------------------------------------------------

  function comboHtml(comp, result) {
    var heading = "<div class='section-heading'><div class='section-icon section-icon--green'>✦</div>" +
      "<div><h2>推荐组合</h2><p>同一个叠加组只取有效倍率最高的一条，跨组相乘</p></div></div>";
    if (!comp.hasDamage) {
      return heading + "<p class='ranker-empty'>先勾选至少一段带伤害的命中。</p>";
    }
    // 推荐组合用**全部命中条目**，不吃搜索框与来源类型 chip：那两个是看列表用的视图筛选，
    // 不是取舍。要排除某一条请在列表里勾掉它（勾掉会即时重算并回退到同组次高）。
    var pool = result.rows.filter(rowPicked);
    var hidden = pool.length - visibleRows(pool).length;
    var combo = recommendCombo(pool, state.mergeFamilies, state.mergeStates);
    var items = combo.picks.map(function (pick) {
      var entry = pick.row.entry;
      return "<div class='ranker-combo-row'>" +
        "<span class='ranker-combo-mul'>" + fmtMultiplier(pick.row.multiplier) + "</span>" +
        "<span class='ranker-combo-name'>" + esc(entry.name) + "</span>" +
        "<span class='ranker-combo-kind'>" + esc(entry.kinds.map(sourceKindLabel).join(" / ")) + "</span>" +
        "<span class='ranker-combo-group'>" + esc(entry.group) +
        (pick.size > 1 ? "（组内 " + pick.size + " 条取最高）" : "") + "</span>" +
        "</div>";
    }).join("");

    return heading +
      "<div class='ranker-filter-row'>" +
      "<label class='switch-control'><input type='checkbox' data-testid='ranker-merge'" +
      (state.mergeFamilies ? " checked" : "") + "><span class='switch-track'></span>" +
      "<span>同族效果只取最高档（按 Paramdex 行名词干合并）</span></label>" +
      "<label class='switch-control' title='stackingRules 第 3 条只说同一 stateInfo「值得怀疑」是同一状态的" +
      "不同档位，并不是互斥分组；打开＝按这条交叉参考保守合并，可能把护符与武器被动这类本可共存的效果并成一组'>" +
      "<input type='checkbox' data-testid='ranker-merge-states'" +
      (state.mergeStates ? " checked" : "") + "><span class='switch-track'></span>" +
      "<span>同 stateInfo 视为同一状态（stackingRules 第 3 条的交叉参考，偏保守）</span></label>" +
      "<button class='button button--ghost' type='button' data-testid='ranker-combo-reset'>恢复全部勾选</button>" +
      "</div>" +
      (hidden > 0
        ? "<p class='ranker-note' data-testid='ranker-combo-scope'>组合按<strong>全部 " + pool.length +
          " 条命中条目</strong>计算，不受上方搜索框与来源类型筛选影响（当前有 " + hidden +
          " 条被筛掉但仍计入）。要排除某一条，请在排名列表里勾掉它。</p>"
        : "") +
      "<div class='ranker-combo-total' data-testid='ranker-combo-total'>" +
      "<div><dt>连乘总倍率</dt><dd>" + fmtMultiplier(combo.product) + "</dd></div>" +
      "<div><dt>相对提升</dt><dd>" + fmtGain(combo.product) + "</dd></div>" +
      "<div><dt>取用条目</dt><dd>" + combo.picks.length + " 条 / " + combo.groups + " 组</dd></div>" +
      (combo.flat ? "<div><dt>另有攻击力加算</dt><dd>+" + fmtNumber(combo.flat, 1) + "</dd></div>" : "") +
      "</div>" +
      "<div class='ranker-combo-list' data-testid='ranker-combo-list'>" +
      (items || "<p class='ranker-empty'>没有可用的增益条目</p>") + "</div>" +
      "<p class='ranker-note ranker-note--warn'>叠加分组用数据集算好的 stacking.group" +
      "（来自 SpEffectParam 的 spCategory / categoryPriority / saveCategory），是<strong>参数结构推断，" +
      "未经木桩验证</strong>；stateInfo 按 stackingRules 第 3 条默认<strong>不</strong>参与分组，" +
      "要按它保守合并请打开上面的开关。攻击力加算（点数）没有绝对攻击力就折不成倍率，" +
      "只按占比加权后单独列出，未计入连乘。</p>";
  }

  // ---- 底部折叠 --------------------------------------------------------

  function textBlock(title, body, testId, color) {
    if (!body) return "";
    return "<details class='card ranker-details'" + (testId ? " data-testid='" + testId + "'" : "") + ">" +
      "<summary><span class='ranker-summary-title'>" + esc(title) + "</span>" +
      pill("原文", color || "gray") + "</summary>" +
      "<div class='ranker-details-body'><p class='ranker-raw'>" + esc(body) + "</p></div></details>";
  }

  function caveatsHtml() {
    var list = Array.isArray(state.skillsData.caveats) ? state.skillsData.caveats : [];
    var pageNotes = pageRuleNotes(state.skillsData, state.buffsData, state.index);
    return "<details class='card ranker-details' data-testid='ranker-caveats'>" +
      "<summary><span class='ranker-summary-title'>数据说明与本页口径</span>" +
      pill((list.length + pageNotes.length) + " 条", "amber") + "</summary>" +
      "<div class='ranker-details-body'>" +
      "<div class='ranker-sub'>本页自己承担的判定</div>" +
      "<ul class='ranker-caveat-list'>" + pageNotes.map(function (text) {
        return "<li>" + esc(text) + "</li>";
      }).join("") + "</ul>" +
      "<div class='ranker-sub'>skills 数据集的已知取舍</div>" +
      // 数据集原文里还写着「6 段带 FP + 6 段 No FP」，这里与段名走同一套展示层替换
      // （macOS 端 BuffRankerRankingSection 的「战技数据的取舍与已知问题」同理），
      // 免得同一页上段名说「专注值不足版」、底部说「No FP」。数据集本身不动。
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
      esc(buffCounts.buffs) + " 条 · 倍率字段 " +
      esc((buffs.rateFields || []).length) + " 个</dd></div>" +
      "<div><dt>v4 / v5 字段</dt><dd>攻击情境 " + esc(buffCounts.buffsWithAttackContext) +
      " 条 · 叠层阶梯 " + esc(buffCounts.buffsWithStackLadder) +
      " 条 · 自伤型异常累积 " + esc(buffCounts.buffsWithSelfInflictedStatus) +
      " 条 · stateInfo 标签 " + esc(buffCounts.stateInfoLabels) + " 项</dd></div>" +
      "<div><dt>生成时间</dt><dd>" + esc(skills.generatedAt || "—") + " / " +
      esc(buffs.generatedAt || "—") + "</dd></div>" +
      "</dl></div></details>";
  }

  // 底部原文折叠的顺序与 macOS 端的 noteKeys 一致：先排名算法，再情境 / 叠层 / 倍率用法，
  // 最后是目标、条件、命名这些取舍说明。数据集新增的 notes 键会自动排在后面，不会漏掉。
  var NOTE_ORDER = [
    { key: "ranking", zh: "排名步骤" },
    { key: "attackContext", zh: "攻击情境（与发动条件正交）" },
    { key: "stackLadder", zh: "叠层阶梯的字段口径" },
    { key: "howToUseRates", zh: "倍率怎么用" },
    { key: "activation", zh: "发动条件" },
    { key: "target", zh: "作用目标" },
    { key: "conditions", zh: "条件字段" },
    { key: "displayName", zh: "显示名" },
    { key: "damageTypeNaming", zh: "伤害类型命名" },
    { key: "zh", zh: "数据集总说明" }
  ];

  function noteBlocksHtml() {
    var notes = state.buffsData.notes || {};
    var shown = {};
    var blocks = NOTE_ORDER.map(function (item) {
      shown[item.key] = true;
      return textBlock(item.zh + "（buffs notes." + item.key + "）", notes[item.key],
        "ranker-notes-" + item.key, "purple");
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

  // 搜索框输入时只换列表，避免整块重绘把光标弹走。
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

  // 有效倍率与推荐组合共用一次 rankEntries，避免重复扫全表。
  function computeResults() {
    var comp = currentComposition();
    return { comp: comp, result: rankEntries(state.index.entries, comp.shares, rankOptions()) };
  }

  function renderRankBody(computed) {
    var data = computed || computeResults();
    var body = section("rank-body");
    if (body) body.innerHTML = rankBodyHtml(data.comp, data.result);
    var comboNode = section("combo");
    if (comboNode) comboNode.innerHTML = comboHtml(data.comp, data.result);
  }

  function renderResults() {
    var data = computeResults();
    var compNode = section("comp");
    if (compNode) compNode.innerHTML = compositionHtml(data.comp);
    var rankNode = section("rank");
    if (rankNode) {
      rankNode.innerHTML = rankingHtml(data.comp, data.result);
      var search = rankNode.querySelector("[data-testid='ranker-buff-search']");
      if (search) search.value = state.buffQuery;
    }
    var comboNode = section("combo");
    if (comboNode) comboNode.innerHTML = comboHtml(data.comp, data.result);
  }

  function renderAll() {
    renderPicker();
    renderHits();
    renderResults();
    var footer = section("footer");
    if (footer) footer.innerHTML = footerHtml();
  }

  // ---- 交互 ------------------------------------------------------------

  // 换一个输出手段＝重新开始：排名侧的搜索词与勾掉／勾上的条目也一并清空，
  // 否则上一个战技的筛选会静默套到下一个（搜到 1 条、连乘只剩一条的假象）。
  function applySelection(kind, id) {
    state.hitOverrides = {};
    state.noFp = false;
    state.limit = PAGE_SIZE;
    state.buffQuery = "";
    state.dropped = {};
    state.picked = {};
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

  function bindEvents() {
    if (!dom) return;

    dom.addEventListener("click", function (event) {
      var meansKind = event.target.closest("[data-ranker-means-kind]");
      if (meansKind) {
        state.meansKind = meansKind.dataset.rankerMeansKind;
        renderPicker();
        return;
      }
      var handButton = event.target.closest("[data-ranker-hand]");
      if (handButton) {
        state.hand = Number(handButton.dataset.rankerHand) === 2 ? 2 : 1;
        renderWeaponBlock();
        renderResults();
        return;
      }
      var means = event.target.closest("[data-ranker-means]");
      if (means) {
        var parts = means.dataset.rankerMeans.split(":");
        selectMeans(parts[0], Number(parts[1]));
        return;
      }
      var hitsAction = event.target.closest("[data-ranker-hits]");
      if (hitsAction) {
        state.hitOverrides = hitOverridesFor(currentHits(), hitsAction.dataset.rankerHits, state.noFp);
        renderHits();
        renderResults();
        return;
      }
      var kindChip = event.target.closest("[data-ranker-kind]");
      if (kindChip) {
        var key = kindChip.dataset.rankerKind;
        if (state.kindOff[key]) delete state.kindOff[key];
        else state.kindOff[key] = true;
        state.limit = PAGE_SIZE;
        kindChip.classList.toggle("is-on", !state.kindOff[key]);
        kindChip.setAttribute("aria-pressed", state.kindOff[key] ? "false" : "true");
        renderRankBody();
        return;
      }
      var contextChip = event.target.closest("[data-ranker-context]");
      if (contextChip) {
        var contextKey = contextChip.dataset.rankerContext;
        if (state.contexts[contextKey]) delete state.contexts[contextKey];
        else state.contexts[contextKey] = true;
        state.limit = PAGE_SIZE;
        contextChip.classList.toggle("is-on", state.contexts[contextKey] === true);
        contextChip.setAttribute("aria-pressed", state.contexts[contextKey] ? "true" : "false");
        renderRankBody();
        return;
      }
      if (event.target.closest("[data-testid='ranker-more']")) {
        state.limit += PAGE_SIZE;
        renderRankBody();
        return;
      }
      if (event.target.closest("[data-testid='ranker-combo-reset']")) {
        state.dropped = {};
        state.picked = {};
        renderRankBody();
      }
    });

    dom.addEventListener("change", function (event) {
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
      if (target.matches("[data-testid='ranker-conditional']")) {
        state.includeConditional = Boolean(target.checked);
        state.limit = PAGE_SIZE;
        renderRankBody();
        return;
      }
      if (target.matches("[data-testid='ranker-ally']")) {
        state.includeAlly = Boolean(target.checked);
        state.limit = PAGE_SIZE;
        renderRankBody();
        return;
      }
      if (target.matches("[data-testid='ranker-attribute']")) {
        state.includeAttributeScoped = Boolean(target.checked);
        state.limit = PAGE_SIZE;
        renderRankBody();
        return;
      }
      if (target.matches("[data-testid='ranker-ladder-top']")) {
        state.ladderTop = Boolean(target.checked);
        state.limit = PAGE_SIZE;
        renderRankBody();
        return;
      }
      if (target.matches("[data-testid='ranker-merge']")) {
        state.mergeFamilies = Boolean(target.checked);
        renderRankBody();
        return;
      }
      if (target.matches("[data-testid='ranker-merge-states']")) {
        state.mergeStates = Boolean(target.checked);
        renderRankBody();
        return;
      }
      if (target.matches("[data-ranker-buff]")) {
        var id = Number(target.dataset.rankerBuff);
        var row = dom.querySelector("[data-ranker-buff-row='" + id + "']");
        var conditional = row ? row.classList.contains("is-conditional") : false;
        if (conditional) {
          if (target.checked) state.picked[id] = true;
          else delete state.picked[id];
        } else if (target.checked) {
          delete state.dropped[id];
        } else {
          state.dropped[id] = true;
        }
        // 只重画推荐组合，排名列表保持原样（勾选状态已经由浏览器更新）。
        var comboNode = section("combo");
        if (comboNode) {
          var data = computeResults();
          comboNode.innerHTML = comboHtml(data.comp, data.result);
        }
      }
    });

    dom.addEventListener("input", function (event) {
      var target = event.target;
      if (target.matches("[data-testid='ranker-means-search']")) {
        state.meansQuery = target.value || "";
        renderMeansList();
        return;
      }
      if (target.matches("[data-testid='ranker-buff-search']")) {
        state.buffQuery = target.value || "";
        state.limit = PAGE_SIZE;
        renderRankBody();
      }
    });
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

  function renderData(skillsData, buffsData) {
    state.skillsData = decorateSkills(skillsData);
    state.buffsData = buffsData;
    state.index = indexBuffs(buffsData);
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
        dom.innerHTML = unavailableShell("战技／法术与增益数据尚未内置，页面无法计算排名。");
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
      if (!state.loaded) load(ctx);
    },
    // 纯计算部分，供 windows/tests/ranker.test.mjs 直接测试。
    _internals: {
      TYPE_KEYS: TYPE_KEYS,
      TYPE_INFO: TYPE_INFO,
      TYPES_BY_ELEMENT: TYPES_BY_ELEMENT,
      ELEMENTS: ELEMENTS,
      ATTACK_CONTEXT_ORDER: ATTACK_CONTEXT_ORDER,
      USEFUL_EPSILON: USEFUL_EPSILON,
      SOURCE_KINDS: SOURCE_KINDS,
      SKILL_SUB_CATEGORY: SKILL_SUB_CATEGORY,
      MELEE_SUB_CATEGORY: MELEE_SUB_CATEGORY,
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
      ladderInfo: ladderInfo,
      scopeInfo: scopeInfo,
      scopeVerdict: scopeVerdict,
      stackingGroupKey: stackingGroupKey,
      stackKeyFor: stackKeyFor,
      prefersRow: prefersRow,
      stateGroupKey: stateGroupKey,
      familyKey: familyKey,
      sourceKindsOf: sourceKindsOf,
      buffDisplayName: buffDisplayName,
      indexBuff: indexBuff,
      indexBuffs: indexBuffs,
      availableContexts: availableContexts,
      effectiveFor: effectiveFor,
      candidateFilter: candidateFilter,
      rankEntries: rankEntries,
      bucketRows: bucketRows,
      recommendCombo: recommendCombo,
      weaponsForSkill: weaponsForSkill,
      groupWeapons: groupWeapons,
      hasAnyDamage: hasAnyDamage,
      skillHasDamage: skillHasDamage,
      buildMeansItems: buildMeansItems,
      meansWithoutDamage: meansWithoutDamage,
      pageRuleNotes: pageRuleNotes,
      filterMeans: filterMeans,
      fmtMultiplier: fmtMultiplier,
      fmtPercent: fmtPercent,
      fmtGain: fmtGain,
      fmtNumber: fmtNumber,
      fmtDuration: fmtDuration,
      sourceKindLabel: sourceKindLabel,
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
