// 首领数据页：与 macOS 端的「另一端断言」。
//
// 上一版的双端文案测试只是把 Windows 自己的字面量再抄一遍（TEXT 里新增的 8 条场合文案，
// macOS 根本没有同名常量），挡不住两端跑偏。这里改成**直接读 macOS 的 Swift 源码**：
//   · macos/Sources/RelicCore/BossData.swift 的 BossRowText / BossRoleText / BossRoleCatalog /
//     BossCard.Group —— 常量逐项与本页 TEXT / ROLE_TEXT / ROLE_ORDER / GROUP_ORDER 比对；
//   · macos/Sources/RelicCoreChecks/BossDataChecks.swift 里 macOS 自检钉住的对照表
//     （roleParityStrings、代表行 representativeCases、开关前后八个分组的条数、出处摘要、
//     收录统计、逐行场合、默认收起的行数、多重归属组数）—— 逐条拿来跑本页的实现。
// macOS 自检断言的是同一批字面量，于是改任何一端而没改另一端，两边都会红。
//
// macOS 端的出场场合分组（BossRoleText 等）与本分支并行开发，尚未合入时 BossData.swift 里
// 没有 BossRoleText，读源码的那几项跳过并在输出里写明原因；合入后自动生效。
// 合入前想先对一遍，可把环境变量 BOSSES_MACOS_ROOT 指向含该改动的 macos/ 目录：
//   BOSSES_MACOS_ROOT=<另一 worktree>/macos node --test tests/bosses_parity.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const Core = require("../renderer/core.js");
const Page = require("../renderer/pages/bosses.js");
const B = Page._internals;

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const data = JSON.parse(readFileSync(path.join(repoRoot, "windows", "resources", "bosses.json"), "utf8"));
const fold = Core.foldForSearch;
const items = B.buildItems(data, fold);
const byUid = new Map(items.map((item) => [item.uid, item]));
const allEntries = [
  ...data.nightlords.flatMap((lord) => lord.fights),
  ...data.nightBosses.flatMap((boss) => boss.variants),
];
const entryById = new Map(allEntries.map((entry) => [entry.npcId, entry]));

const macRoot = process.env.BOSSES_MACOS_ROOT
  ? path.resolve(process.env.BOSSES_MACOS_ROOT)
  : path.join(repoRoot, "macos");
const readIfExists = (file) => (existsSync(file) ? readFileSync(file, "utf8") : "");
const coreSwift = readIfExists(path.join(macRoot, "Sources", "RelicCore", "BossData.swift"));
const checksSwift = readIfExists(path.join(macRoot, "Sources", "RelicCoreChecks", "BossDataChecks.swift"));
const hasRoleText = /enum\s+BossRoleText\s*\{/.test(coreSwift);
const roleSkip = hasRoleText
  ? false
  : "macOS 源码里还没有 BossRoleText（该端的出场场合分组尚未合入本分支）；" +
    "可设 BOSSES_MACOS_ROOT 指向含该改动的 macos/ 目录手动跑";

// Swift 里 macOS 分组 / 卡片 id 与本页的对应
const GROUP_FROM_SWIFT = { nightlord: "nightlords" };
const groupFromSwift = (name) => GROUP_FROM_SWIFT[name] || name;
const uidFromSwift = (cardId) => {
  if (cardId.startsWith("nightlord-")) return "nl:" + cardId.slice("nightlord-".length);
  if (cardId.startsWith("boss-")) return "nb:" + cardId.slice("boss-".length);
  return cardId;
};

// ------------------------------------------------------------ Swift 源码解析

// 从 `enum <name>` 开始按花括号配对截出整个块（这几个块里没有字符串内的花括号）。
function swiftBlock(source, header) {
  const start = source.search(header);
  if (start === -1) return "";
  const open = source.indexOf("{", start);
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === "{") depth += 1;
    else if (source[i] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(open + 1, i);
    }
  }
  return "";
}

function unescapeSwift(text) {
  return text.replace(/\\(["\\nt])/g, (_, char) => ({ n: "\n", t: "\t" }[char] || char));
}

// `"a" + "b"` 这类字面量拼接 → 一个字符串。
function joinLiterals(expr) {
  const parts = [...expr.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((match) => unescapeSwift(match[1]));
  return parts.join("");
}

// 块里全部 `static let name = "…"`（可跨行、可用 + 拼接）的字符串常量。
function swiftStringConstants(block) {
  const out = {};
  const pattern = /static\s+let\s+(\w+)\s*(?::\s*String\s*)?=\s*((?:"(?:[^"\\]|\\.)*"\s*(?:\+\s*)?)+)/g;
  for (const match of block.matchAll(pattern)) out[match[1]] = joinLiterals(match[2]);
  return out;
}

function swiftIntConstant(block, name) {
  const match = block.match(new RegExp("static\\s+let\\s+" + name + "\\s*(?::\\s*Int\\s*)?=\\s*(\\d+)"));
  return match ? Number(match[1]) : null;
}

function swiftStringArray(block, name) {
  const match = block.match(new RegExp("static\\s+let\\s+" + name + "\\s*:[^=]*=\\s*\\[([^\\]]*)\\]"));
  return match ? [...match[1].matchAll(/"([^"]*)"/g)].map((item) => item[1]) : null;
}

function swiftStringDictionary(block, name) {
  const match = block.match(new RegExp("static\\s+let\\s+" + name + "\\s*:[^=]*=\\s*\\[([^\\]]*)\\]"));
  if (!match) return null;
  return Object.fromEntries([...match[1].matchAll(/"([^"]*)"\s*:\s*"([^"]*)"/g)].map((item) => [item[1], item[2]]));
}

// 自检里某个 `let <name> … = [ … ]` 数组字面量的正文（到与它配对的 `]` 为止）。
function swiftArrayBody(source, name) {
  const start = source.search(new RegExp("let\\s+" + name + "\\b[^=]*=\\s*\\["));
  if (start === -1) return "";
  const open = source.indexOf("[", source.indexOf("=", start));
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === "[") depth += 1;
    else if (source[i] === "]") {
      depth -= 1;
      if (depth === 0) return source.slice(open + 1, i);
    }
  }
  return "";
}

// Swift 调用实参（`visible: 4, hidden: 0` / `count: 2, names: ["甲", "乙"]` / `3`）→ JS 值数组。
function swiftArgs(text) {
  const stripped = text.replace(/(^|[,(\s])[a-zA-Z_]\w*\s*:(?!\s*")/g, "$1").trim();
  return stripped ? JSON.parse("[" + stripped + "]") : [];
}

// ------------------------------------------------------------------ 测试

test("TEXT 与 macOS 的 BossRowText 逐字相同（直接读 Swift 源码）", { skip: coreSwift ? false : "找不到 macOS 源码" }, () => {
  const rowText = swiftStringConstants(swiftBlock(coreSwift, /public\s+enum\s+BossRowText\s*\{/));
  const keys = Object.keys(rowText);
  assert.ok(keys.length >= 15, `BossRowText 的字符串常量解析出 ${keys.length} 条，解析规则大概跟不上源码格式了`);
  for (const key of keys) {
    assert.ok(Object.prototype.hasOwnProperty.call(B.TEXT, key), `macOS 的 BossRowText.${key} 在 Windows 的 TEXT 里没有同名项`);
    assert.equal(B.TEXT[key], rowText[key], `TEXT.${key} 与 BossRowText.${key} 不一致`);
  }
});

test("ROLE_TEXT 钉死与 macOS roleParityStrings 同一批字面量", () => {
  // 与 macOS 自检 ②c 的 roleParityStrings 同一张表（下一条测试再直接读 Swift 源码逐条跑）。
  const strings = Object.fromEntries(Object.entries(B.ROLE_TEXT).filter(([, value]) => typeof value === "string"));
  assert.deepEqual(strings, {
    groupNightlord: "夜王",
    groupNight: "守夜首领",
    groupStronghold: "据点首领",
    groupField: "场景头目",
    groupEvergaol: "封印监牢",
    groupOther: "其它场合",
    groupSummon: "随从/召唤物",
    groupUnplaced: "未放置",
    threatTierLabel: "威胁档位",
    threatTierNote: "威胁档位只是多人缩放档位（Field / Night Boss Threat），不代表出场场合；分组按地图放置判定的出场场合",
    rolesMissing: "出场场合：数据未内置",
    evidenceMissing: "出处：数据未内置",
    roleSectionTitle: "出场场合",
    roleSectionDetail: "按地图放置与抽选参数判定；分组看这里，不看威胁档位",
    evidenceExpand: "展开全部出处",
    evidenceCollapse: "只看每个场合的第一条出处",
    hiddenGroupMark: "（默认隐藏）",
    rowRolesTitle: "逐行场合",
    groupPickerHelp: "按出场场合分组；一组首领可以同时出现在多个分组里",
    hiddenToggleRoleHelp: "也控制「未放置」「随从/召唤物」两个场合（分组与展开区的行）",
  });
  assert.equal(B.ROLE_TEXT.multiGroupNameLimit, 12);
  assert.equal(B.ROLE_TEXT.evidenceMore(3), "另有 3 条出处");
  assert.equal(B.ROLE_TEXT.hiddenRows(2), "另有 2 条「未放置」/「随从/召唤物」行已隐藏，打开「显示隐藏实体」查看");
  assert.equal(B.ROLE_TEXT.rowCount(4, 0), "4 条数值行");
  assert.equal(B.ROLE_TEXT.rowCount(4, 1), "4 条数值行（另 1 条已隐藏）");
  assert.equal(B.ROLE_TEXT.overviewTitle(14), "出场场合说明（14 种）");
  assert.equal(B.ROLE_TEXT.roleCountText(40, 0), "40 组");
  assert.equal(B.ROLE_TEXT.roleCountText(1, 6), "1 组 · 夜王 6");
  assert.equal(B.ROLE_TEXT.roleCountText(0, 18), "夜王 18");
  assert.equal(B.ROLE_TEXT.roleCountText(0, 0), "0 组");
  assert.equal(B.ROLE_TEXT.auditTitle(4), "与威胁档位的对照（数据集 notes.roleAudit，4 条）");
  assert.equal(
    B.ROLE_TEXT.multiGroupNote(2, ["甲", "乙"]),
    "有 2 组首领按出场场合同时属于多个分组（甲、乙），它们在各个分组下都会出现：" +
      "卡头列出全部场合，折叠态代表行跟着当前分组走，展开后每行标了自己的场合与出处。"
  );
  const many = Array.from({ length: 13 }, (_, index) => "名" + (index + 1));
  assert.ok(B.ROLE_TEXT.multiGroupNote(13, many).includes("名12 等）"));
  assert.ok(!B.ROLE_TEXT.multiGroupNote(13, many).includes("名13"));
  assert.equal(B.ROLE_TEXT.threatTierCaption(["night"]), "威胁档位 · 守夜首领威胁档");
});

test("ROLE_TEXT 与 macOS 的 BossRoleText 逐项相同（直接读 Swift 源码）", { skip: roleSkip }, () => {
  const block = swiftBlock(coreSwift, /public\s+enum\s+BossRoleText\s*\{/);
  const swiftStrings = swiftStringConstants(block);
  const windowsStrings = Object.fromEntries(Object.entries(B.ROLE_TEXT).filter(([, value]) => typeof value === "string"));
  assert.deepEqual(swiftStrings, windowsStrings, "BossRoleText 的字符串常量与 ROLE_TEXT 应一一对应、逐字相同");
  assert.equal(swiftIntConstant(block, "multiGroupNameLimit"), B.ROLE_TEXT.multiGroupNameLimit);
  assert.deepEqual(swiftStringDictionary(block, "builtinRoleNames"), B.ROLE_TEXT.builtinRoleNames);
  // ROLE_TEXT 里的每个函数，macOS 都有同名静态函数
  for (const [key, value] of Object.entries(B.ROLE_TEXT)) {
    if (typeof value !== "function") continue;
    assert.ok(new RegExp("static\\s+func\\s+" + key + "\\s*\\(").test(block), `macOS 的 BossRoleText 缺少函数 ${key}`);
  }
});

test("分组顺序 / 场合顺序 / 默认隐藏 / 其它场合合并表与 macOS 相同（直接读 Swift 源码）", { skip: roleSkip }, () => {
  const catalog = swiftBlock(coreSwift, /public\s+enum\s+BossRoleCatalog\s*\{/);
  assert.deepEqual(swiftStringArray(catalog, "order"), B.ROLE_ORDER);
  assert.deepEqual(swiftStringArray(catalog, "hiddenRoles"), B.HIDDEN_ROLES);
  assert.deepEqual(swiftStringArray(catalog, "otherGroupRoles"), B.OTHER_GROUP_ROLES);
  const groupBlock = swiftBlock(coreSwift, /public\s+enum\s+Group\s*:\s*String/);
  const cases = [...groupBlock.matchAll(/^\s*case\s+(\w+)\s*$/gm)].map((match) => groupFromSwift(match[1]));
  assert.deepEqual(cases, B.GROUP_ORDER, "BossCard.Group.allCases 与 GROUP_ORDER 同序");
  const hiddenByDefault = groupBlock.match(/isHiddenByDefault:\s*Bool\s*\{([^}]*)\}/);
  assert.ok(hiddenByDefault, "找不到 Group.isHiddenByDefault");
  assert.deepEqual([...hiddenByDefault[1].matchAll(/\.(\w+)/g)].map((match) => groupFromSwift(match[1])).sort(), [...B.HIDDEN_GROUPS].sort());
});

test("macOS 自检的 roleParityStrings 逐条跑 Windows 实现（直接读 RelicCoreChecks）", { skip: roleSkip }, () => {
  const body = swiftArrayBody(checksSwift, "roleParityStrings");
  assert.ok(body, "macOS 自检里找不到 roleParityStrings");
  const tuples = [...body.matchAll(/\(\s*"(\w+)",\s*([\s\S]*?),\s*((?:"(?:[^"\\]|\\.)*"\s*(?:\+\s*)?)+)\)/g)];
  assert.ok(tuples.length >= 25, `roleParityStrings 解析出 ${tuples.length} 条，解析规则大概跟不上源码格式了`);
  for (const [, key, expr, literal] of tuples) {
    const expected = joinLiterals(literal);
    let actual;
    let match;
    if ((match = expr.match(/^BossCard\.Group\.(\w+)\.title$/))) {
      actual = B.GROUP_TITLES[groupFromSwift(match[1])];
    } else if ((match = expr.match(/^BossRoleText\.(\w+)\(([\s\S]*)\)$/))) {
      assert.equal(typeof B.ROLE_TEXT[match[1]], "function", `ROLE_TEXT 缺少函数 ${match[1]}（${key}）`);
      actual = B.ROLE_TEXT[match[1]](...swiftArgs(match[2]));
    } else if ((match = expr.match(/^BossRoleText\.(\w+)$/))) {
      actual = B.ROLE_TEXT[match[1]];
    } else {
      assert.fail(`不认识 roleParityStrings 里 ${key} 的表达式「${expr}」，请同步本测试的解析`);
    }
    assert.equal(actual, expected, `双端文案 ${key}`);
  }
  // 「威胁档位」小字的另外几条（macOS ③ 节）
  const captions = [...checksSwift.matchAll(/BossRoleText\.threatTierCaption\((\[[^\]]*\])\)\s*==\s*"([^"]*)"/g)];
  assert.ok(captions.length >= 3, "macOS 自检里找不到 threatTierCaption 的对照");
  for (const [, args, expected] of captions) {
    assert.equal(B.ROLE_TEXT.threatTierCaption(JSON.parse(args)), expected, args);
  }
});

test("macOS 自检的对照表逐条跑 Windows 实现：代表行 / 开关计数 / 出处 / 收录 / 逐行场合", { skip: roleSkip }, () => {
  // 代表行对照表（macOS 12e 的 representativeCases）
  const reps = [...swiftArrayBody(checksSwift, "representativeCases")
    .matchAll(/\.init\(title:\s*"([^"]+)",\s*cardId:\s*"([^"]+)",\s*group:\s*\.(\w+),\s*npcId:\s*(\d+)\)/g)];
  assert.ok(reps.length >= 20, `representativeCases 解析出 ${reps.length} 条`);
  for (const [, title, cardId, group, npcId] of reps) {
    const item = byUid.get(uidFromSwift(cardId));
    assert.ok(item, `找不到卡片 ${cardId}（${title}）`);
    assert.ok(item.groups.includes(groupFromSwift(group)), `${title}：卡片应出现在 ${group}`);
    assert.equal(B.representativeEntry(item.entries, groupFromSwift(group)).npcId, Number(npcId), title);
  }

  // 隐藏开关前后八个分组的条数（macOS 的 toggleCounts）
  const toggle = checksSwift.match(/toggleCounts\s*==\s*(\[\[[\d,\s[\]]+\]\])/);
  assert.ok(toggle, "macOS 自检里找不到 toggleCounts");
  assert.deepEqual(
    B.GROUP_ORDER.map((group) => [
      B.filterItems(items, group, "", fold).length,
      B.filterItems(items, group, "", fold, true).length,
    ]),
    JSON.parse(toggle[1])
  );

  // 出处摘要（macOS ⑥ 的 evidenceCases）
  const evidence = [...swiftArrayBody(checksSwift, "evidenceCases").matchAll(/\((\d+),\s*"(\w+)",\s*"([^"]*)"\)/g)];
  assert.ok(evidence.length >= 5, "macOS 自检里找不到 evidenceCases");
  for (const [, npcId, role, expected] of evidence) {
    const entry = entryById.get(Number(npcId));
    assert.ok(entry, `找不到 npcId ${npcId}`);
    assert.equal(B.evidenceSummaryText(B.roleEvidenceList(entry, role)[0]), expected, `${npcId} / ${role}`);
  }

  // 收录统计（macOS 的 expectedInventory）
  const inventory = checksSwift.match(/let\s+expectedInventory\s*=\s*((?:"(?:[^"\\]|\\.)*"\s*(?:\+\s*)?)+)/);
  assert.ok(inventory, "macOS 自检里找不到 expectedInventory");
  assert.equal(B.inventoryText(B.inventoryCounts(items)), joinLiterals(inventory[1]));

  // 合并行的逐行场合（格拉狄乌斯 75000020）
  const rowRoles = checksSwift.match(/rowRolesSummary\(gladiusMain\)\s*==\s*"([^"]*)"/);
  assert.ok(rowRoles, "macOS 自检里找不到格拉狄乌斯的逐行场合");
  assert.equal(B.rowRolesSummary(entryById.get(75000020), data), rowRoles[1]);

  // 展开区默认收起 / 列出的行数、多重归属组数、默认视图的卡片数与出现次数
  const rowTotals = checksSwift.match(/hiddenRowTotal\s*==\s*(\d+)\s*&&\s*shownRowTotal\s*==\s*(\d+)/);
  assert.ok(rowTotals, "macOS 自检里找不到 hiddenRowTotal / shownRowTotal");
  const hiddenRows = items.reduce((sum, item) => sum + B.hiddenEntryCount(item.entries, false), 0);
  const shownRows = items.reduce((sum, item) => sum + B.displayEntries(item.entries, false).length, 0);
  assert.deepEqual([hiddenRows, shownRows], [Number(rowTotals[1]), Number(rowTotals[2])]);
  const multi = checksSwift.match(/multi\.count\s*==\s*(\d+)/);
  assert.ok(multi, "macOS 自检里找不到 multiGroupCards 的组数");
  assert.equal(B.multiGroupItems(items).length, Number(multi[1]));
  const visible = checksSwift.match(/visibleUnique\s*==\s*(\d+)\s*&&\s*visibleAppearances\s*==\s*(\d+)/);
  assert.ok(visible, "macOS 自检里找不到默认视图的卡片数");
  const keys = B.visibleTabs(false).map((tab) => tab.key);
  const unique = new Set(keys.flatMap((group) => B.filterItems(items, group, "", fold).map((item) => item.uid)));
  const appearances = keys.reduce((sum, group) => sum + B.filterItems(items, group, "", fold).length, 0);
  assert.deepEqual([unique.size, appearances], [Number(visible[1]), Number(visible[2])]);
});
