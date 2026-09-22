// 存档报告模块（renderer/savereport.js）测试：抬头口径、角色分段、CSV 列顺序与转义。
//
// 口径必须与 macOS 端 RelicCore/SaveReport.swift 逐行一致：那边的同名断言在
// macos/Sources/RelicCoreChecks/SaveCompareChecks.swift 的 checkSaveReport 里。
import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const Report = require("../renderer/savereport.js");

const RULE_HEAVY = "=".repeat(46);
const RULE_LIGHT = "-".repeat(46);

// 名称查询：app.js 里由遗物索引提供，这里用固定表，断言才不依赖真实数据文件。
const lookup = {
  affixName: (id) => ({ 7000000: "生命力＋１", 6820000: "受到损伤时，会累积中毒量表" }[id] || "未知词条 #" + id),
  relicName: (itemId) => ({ 202: "辽阔的火燃情景", 2000002: "辽阔的火燃暗淡情景" }[itemId] || "未知遗物 #" + itemId),
  kindLabel: (itemId) => (itemId === 2000002 ? "深夜遗物" : itemId === 202 ? "商店遗物" : "遗物"),
  colorText: (itemId) => (itemId === 424242 ? "颜色未知" : "红色"),
};

const relic = (index, itemId, effects = [], curses = []) => ({
  index,
  itemId,
  effects: [effects[0] ?? -1, effects[1] ?? -1, effects[2] ?? -1],
  curses: [curses[0] ?? -1, curses[1] ?? -1, curses[2] ?? -1],
});

const valid = () => ({ status: "valid", issues: [], warnings: [], orderedEffects: null, officialEffects: null });
const invalid = (issues) => ({ status: "invalid", issues, warnings: [], orderedEffects: null, officialEffects: null });

const basePayload = {
  fileName: "NR0000.sl2",
  checksumOk: true,
  characters: [
    {
      slot: 0,
      name: "夜巫",
      parseError: null,
      relics: [relic(0, 202, [7000000]), relic(1, 202, [7000000]), relic(2, 424242, [], [6820000])],
    },
    { slot: 1, name: "追踪者", parseError: null, relics: [relic(0, 202, [7000000])] },
  ],
};
const baseAudits = [
  [valid(), valid(), invalid([{ kind: "unknownItem", title: "未知遗物 ID", detail: "遗物 ID 424242 不在内置遗物表中" }])],
  [valid()],
];

const options = (overrides = {}) => Object.assign({
  payload: basePayload,
  audits: baseAudits,
  lookup,
  catalog: { origin: "内置数据", gameVersion: "v1.03.4", dataVersion: "Param 0d2ad1" },
  generatedAt: new Date(2026, 8, 22, 20, 33, 44),
}, overrides);

test("text: 抬头七行的顺序与内容", () => {
  const lines = Report.text(options()).split("\n");
  assert.equal(lines[0], "夜幕验物 · 存档检查报告");
  assert.equal(lines[1], RULE_HEAVY);
  assert.equal(lines[2], "存档文件：NR0000.sl2");
  assert.equal(lines[3], "生成时间：2026-09-22 20:33:44");
  assert.equal(lines[4], "存档校验和：通过");
  assert.equal(lines[5], "角色 2 个 · 遗物 4 件 · 非法 1 件");
  assert.equal(lines[6], "词条库：内置数据 · v1.03.4（数据 Param 0d2ad1）");
  assert.equal(lines[7], Report.DISCLAIMER);
  assert.equal(lines[8], "");
});

test("text: 口径说明写明存档判定不看「校验口径」", () => {
  // 存档页走 Core.auditRelic（不接受 mode），报告里写死这一句，免得让人
  // 以为换个口径重跑会有别的结论。
  assert.ok(Report.DISCLAIMER.includes("不受顶部「校验口径」影响"));
  const text = Report.text(options());
  assert.ok(!text.includes("校验口径："), "报告里不应写出某个具体口径");
  assert.ok(!text.includes("当前口径"));
});

test("text: 校验和异常 / 没有词条库信息 / 没有生成时间", () => {
  const broken = Report.text(options({
    payload: Object.assign({}, basePayload, { checksumOk: false }),
    catalog: null,
    generatedAt: null,
  })).split("\n");
  assert.equal(broken[3], "存档校验和：异常（结果仅供参考）");
  assert.ok(!broken.some((line) => line.startsWith("生成时间：")), "不传时间就不写这一行");
  assert.ok(!broken.some((line) => line.startsWith("词条库：")), "不传词条库信息就不写这一行");
});

test("text: 角色分段与非法遗物条目", () => {
  const text = Report.text(options());
  assert.ok(text.includes("\n" + RULE_LIGHT + "\n槽位 1 · 夜巫\n"), "段首是分隔线 + 角色行");
  assert.ok(text.includes("  遗物 3 件 · 非法 1 件"));
  assert.ok(text.includes("  [非法] 未知遗物 #424242（ID 424242）"));
  assert.ok(text.includes("    种类：遗物 · 颜色未知 · 存档内第 3 件"));
  assert.ok(text.includes("    词条1：（空）｜诅咒：受到损伤时，会累积中毒量表（6820000）"));
  assert.ok(text.includes("    ✗ 未知遗物 ID：遗物 ID 424242 不在内置遗物表中"));
  assert.ok(!text.includes("辽阔的火燃情景"), "合法遗物不进文本报告");
  assert.ok(text.includes("  未发现不合法遗物。"), "全部合法的角色要显式说明");
});

test("text: 没有警告时不写「警告 0 件」", () => {
  const text = Report.text(options());
  assert.ok(!text.includes("警告 0 件"));
  // 有警告时才写出来
  const audits = [[Object.assign(valid(), {
    warnings: [{ kind: "x", title: "留意", detail: "说明" }],
  }), valid(), baseAudits[0][2]], [valid()]];
  const withWarning = Report.text(options({ audits })).split("\n");
  assert.equal(withWarning[5], "角色 2 个 · 遗物 4 件 · 非法 1 件 · 警告 1 件");
  assert.ok(withWarning.includes("    ! 留意：说明"));
});

test("text: 空存档与解析失败的槽位", () => {
  const empty = Report.text(options({
    payload: { fileName: "空.sl2", checksumOk: true, characters: [] },
    audits: [],
  }));
  assert.ok(empty.includes("未在该存档中找到已占用的角色槽位。"));

  const damaged = Report.text(options({
    payload: {
      fileName: "损坏.sl2",
      checksumOk: true,
      characters: [{ slot: 1, name: "槽位 2", parseError: "该槽位解密失败：条目密文长度不是 16 的倍数", relics: [] }],
    },
    audits: [[]],
  }));
  assert.ok(damaged.includes("  该槽位解析失败：该槽位解密失败：条目密文长度不是 16 的倍数"));
  assert.ok(
    !damaged.includes("\n  遗物 0 件"),
    "解析失败的槽位不写角色汇总行（「遗物 0 件」），那会被当成空槽位"
  );
  assert.ok(!damaged.includes("该角色没有持有任何遗物"));
});

test("text: 没有遗物的角色与有遗物但全合法的角色说法不同", () => {
  const text = Report.text(options({
    payload: {
      fileName: "a.sl2",
      checksumOk: true,
      characters: [{ slot: 0, name: "甲", parseError: null, relics: [] }],
    },
    audits: [[]],
  }));
  assert.ok(text.includes("  该角色没有持有任何遗物。"));
});

test("text: 官方固定词条与正确的词条顺序", () => {
  const audit = Object.assign(invalid([{ kind: "slotMismatch", title: "正面词条不在对应槽池", detail: "第 1 行…" }]), {
    officialEffects: [7000000, -1, -1],
    orderedEffects: [7000000, 6820000, -1],
  });
  const text = Report.text(options({
    payload: { fileName: "a.sl2", checksumOk: true, characters: [{ slot: 0, name: "甲", parseError: null, relics: [relic(0, 202, [7000000])] }] },
    audits: [[audit]],
  }));
  assert.ok(text.includes("    官方固定词条（可据此改回）：生命力＋１（7000000）"));
  assert.ok(text.includes("    正确的词条顺序：生命力＋１（7000000）、受到损伤时，会累积中毒量表（6820000）、（空）"));
});

test("csv: 表头与列顺序", () => {
  const rows = Report.csv(options()).split("\r\n");
  assert.equal(rows[0], "角色,槽位,遗物名,遗物ID,种类,颜色,状态,词条1,词条2,词条3,诅咒1,诅咒2,诅咒3,问题摘要");
  assert.deepEqual(Report.CSV_HEADER, rows[0].split(","));
});

test("csv: 一行一件遗物，角色名与槽位号分列", () => {
  const rows = Report.csv(options()).split("\r\n").filter(Boolean);
  assert.equal(rows.length, 5, "表头 + 4 件遗物");
  assert.ok(rows[1].startsWith("夜巫,1,辽阔的火燃情景,202,商店遗物,红色,合法,生命力＋１（7000000）,,,"));
  assert.ok(rows[3].includes(",非法,"));
  assert.ok(rows[3].endsWith(",未知遗物 ID：遗物 ID 424242 不在内置遗物表中"), "问题摘要是「标题：说明」");
  assert.ok(rows[4].startsWith("追踪者,2,"), "第二个角色的槽位号是 2");
});

test("csv: 问题摘要用「；」串起来，警告带前缀", () => {
  const audit = {
    status: "invalid",
    issues: [{ title: "甲", detail: "说明甲" }, { title: "乙", detail: "说明乙" }],
    warnings: [{ title: "丙", detail: "说明丙" }],
  };
  assert.deepEqual(Report.issueSummary(audit), ["甲：说明甲", "乙：说明乙", "警告：丙：说明丙"]);
});

test("csv: 解析失败的槽位补一行占位", () => {
  const rows = Report.csv(options({
    payload: {
      fileName: "损坏.sl2",
      checksumOk: true,
      characters: [
        { slot: 1, name: "槽位 2", parseError: "该槽位解密失败", relics: [] },
        { slot: 2, name: "丙", parseError: null, relics: [relic(0, 202, [7000000])] },
      ],
    },
    audits: [[], [valid()]],
  })).split("\r\n").filter(Boolean);
  assert.equal(rows.length, 3, "表头 + 占位行 + 一件遗物");
  assert.equal(rows[1], "槽位 2,2,,,,,槽位解析失败,,,,,,,该槽位解密失败");
  assert.ok(rows[2].startsWith("丙,3,"));
});

test("csv: 公式注入与引号转义", () => {
  assert.equal(Report.csvField("普通"), "普通");
  assert.equal(Report.csvField("a,b"), '"a,b"');
  assert.equal(Report.csvField('a"b'), '"a""b"');
  assert.equal(Report.csvField("=1+1"), "'=1+1");
  assert.equal(Report.csvField("-12"), "-12", "纯数字不加撇号：遗物 ID / 槽位号要保持数值列");
  assert.equal(Report.csvField("-12.5"), "-12.5");
  assert.equal(Report.csvField("-a"), "'-a");
  const rows = Report.csv(options({
    payload: {
      fileName: "a.sl2",
      checksumOk: true,
      characters: [{ slot: 0, name: "=HYPERLINK(\"http://x\")", parseError: null, relics: [relic(0, 202, [7000000])] }],
    },
    audits: [[valid()]],
  })).split("\r\n");
  assert.ok(rows[1].startsWith('"\'=HYPERLINK(""http://x"")",1,'), "可控的角色名要先转义成文本：" + rows[1]);
});

test("csv: 以 CRLF 结尾（RFC 4180，Excel 识别最稳）", () => {
  const csv = Report.csv(options());
  assert.ok(csv.endsWith("\r\n"));
  assert.ok(!/[^\r]\n/.test(csv), "不应出现裸 LF");
});

test("statusLabel: 非法 / 警告 / 合法三态", () => {
  assert.equal(Report.statusLabel({ status: "invalid", issues: [], warnings: [] }), "非法");
  assert.equal(Report.statusLabel({ status: "valid", issues: [], warnings: [{ title: "x", detail: "y" }] }), "警告");
  assert.equal(Report.statusLabel({ status: "valid", issues: [], warnings: [] }), "合法");
  assert.equal(Report.statusLabel(null), "合法");
});

test("affixLabel: 「名称（ID）」，空词条写「（空）」", () => {
  assert.equal(Report.affixLabel(7000000, lookup), "生命力＋１（7000000）");
  assert.equal(Report.affixLabel(-1, lookup), "（空）");
  assert.equal(Report.affixLabel(0, lookup), "（空）", "0 是空词条的另一种写法");
  assert.equal(Report.affixLabel(0xFFFFFFFF, lookup), "（空）");
});

test("suggestedFileName: 夜幕验物-存档报告-<存档名>-时间戳", () => {
  const date = new Date(2026, 8, 22, 20, 33, 44);
  assert.equal(Report.suggestedFileName("NR0000.sl2", "text", date), "夜幕验物-存档报告-NR0000-20260922-203344.txt");
  assert.equal(Report.suggestedFileName("NR0000.sl2", "csv", date), "夜幕验物-存档报告-NR0000-20260922-203344.csv");
  assert.equal(Report.suggestedFileName("C:\\\\save\\\\NR0001.co2", "text", date), "夜幕验物-存档报告-NR0001-20260922-203344.txt");
  assert.equal(Report.suggestedFileName("", "text", date), "夜幕验物-存档报告-存档-20260922-203344.txt");
  assert.equal(Report.suggestedFileName("NR0000.sl2", "text", null), "夜幕验物-存档报告-NR0000.txt");
});

test("text/csv: 不修改入参", () => {
  const snapshot = JSON.stringify(basePayload);
  Report.text(options());
  Report.csv(options());
  assert.equal(JSON.stringify(basePayload), snapshot);
});
