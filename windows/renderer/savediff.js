// 存档对比（「对比另一份存档」）的纯函数模块。
//
// 与 core.js 一样是 UMD：浏览器里挂 window.NightreignSaveDiff，node 里
// module.exports，方便 tests/save_diff.test.mjs 直接 require。
//
// 口径：
//   * 按角色槽位（slot）配对两份存档，任一边缺这个槽位也会列出来；
//   * 每个槽位内把遗物当作多重集比较，身份 = itemId + 三条正面词条 +
//     三条诅咒（都按存档里的顺序，因为顺序本身会影响合法性判定）；
//   * 0 / -1 / 0xFFFFFFFF 统一归一为 -1（与 core.js 的 normalizeEffectId 一致），
//     所以「空词条」的两种写法不会被当成两件不同的遗物。
//   * 任一边的槽位解析失败（character.parseError）时不产出增减列表：解析失败的
//     槽位在 savefile.Parse 里 relics 就是空数组，拿它去比会把「读不出来」报成
//     「遗物被删光」。这种槽位标 unreadable，并且不计入 totals.added/removed。
// 本模块不做合法性判定：状态由调用方用 Core.auditRelic 标注。
(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.NightreignSaveDiff = factory();
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  // 空词条的所有写法归一为 -1：0 / 负值 / 0xFFFFFFFF / 缺字段。
  // 与 macOS 端 SaveRelicIdentity.normalized 同一条规则，两端身份键才等价。
  function normalizeEffectId(value) {
    return value == null || value <= 0 || value === 0xFFFFFFFF ? -1 : value;
  }

  function normalizeTriple(values) {
    var result = [-1, -1, -1];
    for (var index = 0; index < 3; index += 1) {
      result[index] = normalizeEffectId(Array.isArray(values) ? values[index] : -1);
    }
    return result;
  }

  // 遗物身份键：itemId|正面三条|诅咒三条
  function relicIdentity(relic) {
    var itemId = relic && Number.isSafeInteger(relic.itemId) ? relic.itemId : -1;
    return itemId + "|" +
      normalizeTriple(relic && relic.effects).join(",") + "|" +
      normalizeTriple(relic && relic.curses).join(",");
  }

  // 多重集：身份键 → { key, relic, count, positions }
  // positions 是这款遗物在该存档 relics 数组里的全部下标，调用方据此取回
  // 整份存档算过的审查结果（含唯一遗物重复检查），不必对单件重算。
  function countRelics(relics) {
    var counts = new Map();
    (Array.isArray(relics) ? relics : []).forEach(function (relic, position) {
      var key = relicIdentity(relic);
      var entry = counts.get(key);
      if (entry) {
        entry.count += 1;
        entry.positions.push(position);
        return;
      }
      counts.set(key, { key: key, relic: relic, count: 1, positions: [position] });
    });
    return counts;
  }

  // 两个遗物列表的多重集差：added 是 other 多出来的，removed 是 base 少掉的。
  function diffRelicLists(baseRelics, otherRelics) {
    var baseCounts = countRelics(baseRelics);
    var otherCounts = countRelics(otherRelics);
    var added = [];
    var removed = [];
    var common = 0;

    otherCounts.forEach(function (entry, key) {
      var baseEntry = baseCounts.get(key);
      var baseCount = baseEntry ? baseEntry.count : 0;
      var shared = Math.min(baseCount, entry.count);
      common += shared;
      if (entry.count > baseCount) {
        added.push({ key: key, relic: entry.relic, count: entry.count - baseCount, positions: entry.positions });
      }
    });
    baseCounts.forEach(function (entry, key) {
      var otherEntry = otherCounts.get(key);
      var otherCount = otherEntry ? otherEntry.count : 0;
      if (entry.count > otherCount) {
        removed.push({ key: key, relic: entry.relic, count: entry.count - otherCount, positions: entry.positions });
      }
    });

    return {
      base: sumCounts(baseCounts),
      other: sumCounts(otherCounts),
      common: common,
      added: added,
      removed: removed,
      addedCount: sumEntries(added),
      removedCount: sumEntries(removed),
    };
  }

  function sumCounts(counts) {
    var total = 0;
    counts.forEach(function (entry) { total += entry.count; });
    return total;
  }

  function sumEntries(entries) {
    return entries.reduce(function (total, entry) { return total + entry.count; }, 0);
  }

  // 槽位 → { character, index }；index 是 payload.characters 里的下标，调用方
  // 用它对上自己那份 audits 数组。
  function charactersBySlot(payload) {
    var bySlot = new Map();
    var characters = payload && Array.isArray(payload.characters) ? payload.characters : [];
    characters.forEach(function (character, index) {
      var slot = character && Number.isSafeInteger(character.slot) ? character.slot : index;
      if (!bySlot.has(slot)) bySlot.set(slot, { character: character, index: index });
    });
    return bySlot;
  }

  function characterName(character) {
    return character && character.name ? character.name : "";
  }

  // 解析失败的槽位：savefile.Parse 会把原因写进 parseError 并给一个空 relics，
  // 直接拿去比会把「读不出来」当成「一件不剩」。
  function parseErrorOf(character) {
    var reason = character && character.parseError;
    return typeof reason === "string" && reason.trim() !== "" ? reason : null;
  }

  // 对比两份存档，按槽位升序返回每个角色的差异与总计。
  function diffPayloads(basePayload, otherPayload) {
    var baseBySlot = charactersBySlot(basePayload);
    var otherBySlot = charactersBySlot(otherPayload);
    var slots = [];
    baseBySlot.forEach(function (value, slot) { slots.push(slot); });
    otherBySlot.forEach(function (value, slot) { if (!baseBySlot.has(slot)) slots.push(slot); });
    slots.sort(function (left, right) { return left - right; });

    var totals = { base: 0, other: 0, added: 0, removed: 0, changedCharacters: 0, unreadableCharacters: 0 };
    var characters = slots.map(function (slot) {
      var baseSlot = baseBySlot.get(slot) || null;
      var otherSlot = otherBySlot.get(slot) || null;
      var baseCharacter = baseSlot ? baseSlot.character : null;
      var otherCharacter = otherSlot ? otherSlot.character : null;
      var baseParseError = parseErrorOf(baseCharacter);
      var otherParseError = parseErrorOf(otherCharacter);
      var unreadable = Boolean(baseParseError || otherParseError);
      var diff = diffRelicLists(
        baseCharacter ? baseCharacter.relics : [],
        otherCharacter ? otherCharacter.relics : []
      );
      totals.base += diff.base;
      totals.other += diff.other;
      if (unreadable) {
        // 读不出来的槽位不产出增减，也不计入总计，否则结论会反过来。
        diff = { base: diff.base, other: diff.other, common: 0, added: [], removed: [], addedCount: 0, removedCount: 0 };
        totals.unreadableCharacters += 1;
      } else {
        totals.added += diff.addedCount;
        totals.removed += diff.removedCount;
        if (diff.addedCount > 0 || diff.removedCount > 0) totals.changedCharacters += 1;
      }
      return {
        slot: slot,
        baseIndex: baseSlot ? baseSlot.index : -1,
        otherIndex: otherSlot ? otherSlot.index : -1,
        baseName: characterName(baseCharacter),
        otherName: characterName(otherCharacter),
        inBase: Boolean(baseCharacter),
        inOther: Boolean(otherCharacter),
        baseParseError: baseParseError,
        otherParseError: otherParseError,
        unreadable: unreadable,
        base: diff.base,
        other: diff.other,
        common: diff.common,
        added: diff.added,
        removed: diff.removed,
        addedCount: diff.addedCount,
        removedCount: diff.removedCount,
        changed: diff.addedCount > 0 || diff.removedCount > 0,
      };
    });

    return { characters: characters, totals: totals };
  }

  return Object.freeze({
    relicIdentity: relicIdentity,
    countRelics: countRelics,
    diffRelicLists: diffRelicLists,
    diffPayloads: diffPayloads,
  });
});
