// 存档检查报告（导出 TXT / CSV）的纯函数模块。
//
// 与 core.js / savediff.js 一样是 UMD：浏览器里挂 window.NightreignSaveReport，
// node 里 module.exports，方便 tests/save_report.test.mjs 直接 require。
//
// 口径（与 macOS 端 RelicCore/SaveReport.swift 逐行一致，改一处必须改另一处）：
//   * 抬头固定 7 行：标题 / 分隔线 / 存档文件 / 生成时间（可省）/ 存档校验和 /
//     汇总 / 词条库 / 说明；
//   * 「警告」当前不会被 auditRelic 产出，恒为 0 的字段不写进报告，免得读者
//     以为「已检查过、没有告警」；
//   * 存档判定走 auditRelic（不接受 mode），与顶部「校验口径」无关，说明行里
//     明确写出来，免得让人以为换个口径重跑会有别的结论；
//   * CSV 列顺序：角色 / 槽位 / 遗物名 / 遗物ID / 种类 / 颜色 / 状态 /
//     词条1-3 / 诅咒1-3 / 问题摘要；解析失败的槽位补一行占位，否则拿 CSV
//     做统计的人会整段漏掉这个角色。
//
// 本模块不做合法性判定：调用方先用 Core.auditRelic 把 audits 算好再传进来。
(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.NightreignSaveReport = factory();
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  // 抬头 / 角色分段的分隔线（ASCII，记事本与表格软件里都不会错位）。
  var RULE_WIDTH = 46;
  var HEAVY_RULE = repeat("=", RULE_WIDTH);
  var LIGHT_RULE = repeat("-", RULE_WIDTH);

  // CSV 表头（与 csv() 的列顺序一致）。
  var CSV_HEADER = [
    "角色", "槽位", "遗物名", "遗物ID", "种类", "颜色", "状态",
    "词条1", "词条2", "词条3", "诅咒1", "诅咒2", "诅咒3", "问题摘要"
  ];

  // 解析失败的槽位在「状态」列里的标记（CSV 里没有遗物行，用它留痕）。
  var CSV_PARSE_ERROR_STATUS = "槽位解析失败";

  // 说明行：存档判定与顶部「校验口径」无关，写死在报告里。
  var DISCLAIMER =
    "说明：存档判定只依据内置的词条库与遗物表，不受顶部「校验口径」影响" +
    "（口径只作用于词条组合检查页）；本报告由离线社区工具生成，不构成官方判定。";

  function repeat(char, count) {
    var text = "";
    for (var index = 0; index < count; index += 1) text += char;
    return text;
  }

  function normId(value) {
    return value == null || value === 0 || value === -1 || value === 0xFFFFFFFF ? -1 : value;
  }

  function pad2(value) {
    return String(value).padStart(2, "0");
  }

  // 报告里的时间戳：YYYY-MM-DD HH:MM:SS（本地时区）。
  function timestamp(date) {
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate()) +
      " " + pad2(date.getHours()) + ":" + pad2(date.getMinutes()) + ":" + pad2(date.getSeconds());
  }

  // 文件名里的时间戳：YYYYMMDD-HHMMSS。
  function fileTimestamp(date) {
    return date.getFullYear() + pad2(date.getMonth() + 1) + pad2(date.getDate()) +
      "-" + pad2(date.getHours()) + pad2(date.getMinutes()) + pad2(date.getSeconds());
  }

  // 「非法 / 警告 / 合法」三态文案（页面、报告、对比列表统一用这一份口径）。
  function statusLabel(audit) {
    if (!audit) return "合法";
    if (audit.status === "invalid") return "非法";
    return (audit.warnings || []).length > 0 ? "警告" : "合法";
  }

  // 单件遗物的问题摘要：「标题：说明」用「；」串起来，警告加「警告：」前缀。
  function issueSummary(audit) {
    var parts = (audit && audit.issues || []).map(function (issue) {
      return issue.title + "：" + issue.detail;
    });
    (audit && audit.warnings || []).forEach(function (issue) {
      parts.push("警告：" + issue.title + "：" + issue.detail);
    });
    return parts;
  }

  // 词条标签：「名称（ID）」，空词条写「（空）」。
  function affixLabel(effectId, lookup) {
    var id = normId(effectId);
    if (id === -1) return "（空）";
    return lookup.affixName(id) + "（" + id + "）";
  }

  function characterName(character) {
    return (character && character.name) || "未命名";
  }

  function characterSlot(character, index) {
    return (character && Number.isSafeInteger(character.slot) ? character.slot : index) + 1;
  }

  function characterLabel(character, index) {
    return "槽位 " + characterSlot(character, index) + " · " + characterName(character);
  }

  function parseErrorOf(character) {
    var reason = character && character.parseError;
    return typeof reason === "string" && reason.trim() !== "" ? reason : null;
  }

  // 「遗物 N 件 · 非法 M 件[ · 警告 K 件]」：警告恒为 0 时不写这一段。
  function countsText(total, invalid, warning) {
    var text = "遗物 " + total + " 件 · 非法 " + invalid + " 件";
    if (warning > 0) text += " · 警告 " + warning + " 件";
    return text;
  }

  function tally(payload, audits) {
    var totals = { total: 0, invalid: 0, warning: 0 };
    (payload.characters || []).forEach(function (character, index) {
      (audits[index] || []).forEach(function (audit) {
        totals.total += 1;
        var label = statusLabel(audit);
        if (label === "非法") totals.invalid += 1;
        else if (label === "警告") totals.warning += 1;
      });
    });
    return totals;
  }

  // 词条库行：「内置数据 · 1.03（数据 2026-01-01）」。catalog 为空时返回 null，
  // 调用方据此不写这一行。
  function catalogLine(catalog) {
    if (!catalog) return null;
    var text = (catalog.origin || "内置数据") + " · " + (catalog.gameVersion || "未知版本");
    if (catalog.dataVersion) text += "（数据 " + catalog.dataVersion + "）";
    return text;
  }

  // ---- 文本报告 ----

  function relicBlock(relic, audit, lookup) {
    var lines = [];
    lines.push("  [" + statusLabel(audit) + "] " + lookup.relicName(relic.itemId) +
      "（ID " + relic.itemId + "）");
    lines.push("    种类：" + lookup.kindLabel(relic.itemId) + " · " + lookup.colorText(relic.itemId) +
      " · 存档内第 " + (Number(relic.index) + 1) + " 件");

    for (var line = 0; line < 3; line += 1) {
      var effectId = normId((relic.effects || [])[line]);
      var curseId = normId((relic.curses || [])[line]);
      if (effectId === -1 && curseId === -1) continue;
      var text = "    词条" + (line + 1) + "：" + affixLabel(effectId, lookup);
      if (curseId !== -1) text += "｜诅咒：" + affixLabel(curseId, lookup);
      lines.push(text);
    }

    (audit.issues || []).forEach(function (issue) {
      lines.push("    ✗ " + issue.title + "：" + issue.detail);
    });
    (audit.warnings || []).forEach(function (issue) {
      lines.push("    ! " + issue.title + "：" + issue.detail);
    });

    if (audit.officialEffects) {
      var official = audit.officialEffects.filter(function (effectId) { return normId(effectId) !== -1; })
        .map(function (effectId) { return affixLabel(effectId, lookup); }).join("、");
      if (official) lines.push("    官方固定词条（可据此改回）：" + official);
    }
    if (audit.orderedEffects) {
      lines.push("    正确的词条顺序：" + audit.orderedEffects.map(function (effectId) {
        return affixLabel(effectId, lookup);
      }).join("、"));
    }
    return lines;
  }

  // options: { payload, audits, lookup, catalog, generatedAt }
  function text(options) {
    var payload = options.payload;
    var audits = options.audits || [];
    var lookup = options.lookup;
    var characters = payload.characters || [];
    var totals = tally(payload, audits);
    var lines = [];

    lines.push("夜幕验物 · 存档检查报告");
    lines.push(HEAVY_RULE);
    lines.push("存档文件：" + (payload.fileName || "未知"));
    if (options.generatedAt) lines.push("生成时间：" + timestamp(options.generatedAt));
    lines.push("存档校验和：" + (payload.checksumOk === false ? "异常（结果仅供参考）" : "通过"));
    lines.push("角色 " + characters.length + " 个 · " +
      countsText(totals.total, totals.invalid, totals.warning));
    var catalogText = catalogLine(options.catalog);
    if (catalogText) lines.push("词条库：" + catalogText);
    lines.push(DISCLAIMER);
    lines.push("");

    if (!characters.length) lines.push("未在该存档中找到已占用的角色槽位。");

    characters.forEach(function (character, index) {
      lines.push(LIGHT_RULE);
      lines.push(characterLabel(character, index));
      var parseError = parseErrorOf(character);
      if (parseError) {
        lines.push("  该槽位解析失败：" + parseError);
        lines.push("");
        return;
      }

      var relics = character.relics || [];
      var characterAudits = audits[index] || [];
      var flagged = [];
      var invalid = 0;
      var warning = 0;
      relics.forEach(function (relic, relicIndex) {
        var audit = characterAudits[relicIndex];
        if (!audit) return;
        var label = statusLabel(audit);
        if (label === "非法") invalid += 1;
        else if (label === "警告") warning += 1;
        if (label !== "合法") flagged.push({ relic: relic, audit: audit });
      });

      lines.push("  " + countsText(relics.length, invalid, warning));
      if (!flagged.length) {
        lines.push(relics.length ? "  未发现不合法遗物。" : "  该角色没有持有任何遗物。");
      }
      flagged.forEach(function (item) {
        lines.push("");
        relicBlock(item.relic, item.audit, lookup).forEach(function (line) { lines.push(line); });
      });
      lines.push("");
    });

    return lines.join("\n") + "\n";
  }

  // ---- CSV ----

  // 角色名、遗物名都来自别人的存档，完全可控；导出的 CSV 又特意带了 UTF-8 BOM
  // 好让 Excel 双击直接打开，所以以 = + - @ 开头的值要先转义成文本，
  // 否则一个叫 =HYPERLINK(...) 的角色名会在对方的 Excel 里变成活公式。
  // 纯数字（含负数）不转义：遗物 ID / 槽位号要保持数值列。
  function csvField(value) {
    var text = String(value == null ? "" : value);
    if (/^[=+\-@\t\r]/.test(text) && !/^-?\d+(\.\d+)?$/.test(text)) text = "'" + text;
    return /[",\n\r]/.test(text) ? '"' + text.replace(/"/g, '""') + '"' : text;
  }

  function csvRow(fields) {
    return fields.map(csvField).join(",");
  }

  // options: { payload, audits, lookup }
  function csv(options) {
    var payload = options.payload;
    var audits = options.audits || [];
    var lookup = options.lookup;
    var rows = [csvRow(CSV_HEADER)];

    (payload.characters || []).forEach(function (character, index) {
      var slot = characterSlot(character, index);
      var name = characterName(character);
      var parseError = parseErrorOf(character);
      // 槽位解密失败时 relics 为空，若不补一行，拿 CSV 做统计的人会整段漏掉这个角色。
      if (parseError) {
        rows.push(csvRow([name, slot, "", "", "", "", CSV_PARSE_ERROR_STATUS,
          "", "", "", "", "", "", parseError]));
      }
      var characterAudits = audits[index] || [];
      (character.relics || []).forEach(function (relic, relicIndex) {
        var audit = characterAudits[relicIndex];
        if (!audit) return;
        var cell = function (values, line) {
          var effectId = normId((values || [])[line]);
          return effectId === -1 ? "" : affixLabel(effectId, lookup);
        };
        rows.push(csvRow([
          name, slot,
          lookup.relicName(relic.itemId), relic.itemId,
          lookup.kindLabel(relic.itemId), lookup.colorText(relic.itemId),
          statusLabel(audit),
          cell(relic.effects, 0), cell(relic.effects, 1), cell(relic.effects, 2),
          cell(relic.curses, 0), cell(relic.curses, 1), cell(relic.curses, 2),
          issueSummary(audit).join("；")
        ]));
      });
    });

    // RFC 4180 的 CRLF，表格软件（含 Excel）识别最稳；文本报告落盘时由
    // savefile.NormalizeCRLF 统一换行，两端最终字节一致。
    return rows.join("\r\n") + "\r\n";
  }

  // ---- 文件名 ----

  // 建议的导出文件名：夜幕验物-存档报告-NR0000-20260922-203300.txt
  function suggestedFileName(saveFileName, kind, date) {
    var base = String(saveFileName || "").replace(/^.*[\\/]/, "").replace(/\.[^.]*$/, "").trim();
    var safe = base.replace(/[\\/:]/g, "-").trim();
    var name = "夜幕验物-存档报告-" + (safe === "" ? "存档" : safe);
    if (date) name += "-" + fileTimestamp(date);
    return name + (kind === "csv" ? ".csv" : ".txt");
  }

  return Object.freeze({
    CSV_HEADER: Object.freeze(CSV_HEADER.slice()),
    CSV_PARSE_ERROR_STATUS: CSV_PARSE_ERROR_STATUS,
    DISCLAIMER: DISCLAIMER,
    statusLabel: statusLabel,
    issueSummary: issueSummary,
    affixLabel: affixLabel,
    csvField: csvField,
    text: text,
    csv: csv,
    suggestedFileName: suggestedFileName,
  });
});
