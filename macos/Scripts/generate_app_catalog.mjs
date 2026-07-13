import fs from "node:fs/promises";
import path from "node:path";

const projectRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const inputPath = path.resolve(process.argv[2] ?? path.join(projectRoot, "../generated_data/affixes.json"));
const outputPath = path.resolve(
  process.argv[3] ?? path.join(projectRoot, "Sources/NightreignRelicChecker/Resources/affixes.json"),
);

const source = JSON.parse(await fs.readFile(inputPath, "utf8"));

function effectivePoolIds(row) {
  const groups = Object.values(row.poolWeights ?? {});
  const ids = [];
  for (const group of groups) {
    for (const [poolId, weights] of Object.entries(group ?? {})) {
      if (Number(weights?.effective ?? 0) > 0) ids.push(Number(poolId));
    }
  }
  return [...new Set(ids)].sort((a, b) => a - b);
}

function cleanExplanation(value) {
  const text = String(value ?? "").trim();
  if (["", "0", "1", "-", "—", "无", "未知", "暂无"].includes(text)) return "";
  return text;
}

const provenance = source.provenance ?? {};
const catalog = {
  schemaVersion: 1,
  gameVersion: source.targetGameData ?? "v1.03.4 + DLC1",
  dataVersion: `Param ${provenance.gameParamsAndZhText?.commit?.slice(0, 8) ?? "unknown"}`,
  generatedAt: source.generatedAt ?? new Date().toISOString(),
  sources: [
    {
      name: "Elden Ring Nightreign Save Editor（游戏参数与简中 FMG）",
      url: provenance.gameParamsAndZhText?.repository ?? "https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor",
      revision: provenance.gameParamsAndZhText?.commit ?? "",
      license: "MIT",
    },
    {
      name: "NightreignQuickRef（分类、说明与叠加性）",
      url: provenance.quickRefEnrichment?.repository ?? "https://github.com/xxiixi/NightreignQuickRef",
      revision: provenance.quickRefEnrichment?.commit ?? "",
      license: "GPL-3.0",
    },
    {
      name: "叮当市场旧站公开 API（热门度与历史别名）",
      url: provenance.dingdangmarketArchive?.effectListUrl ?? "https://elden.dingdangmarket.com",
      revision: provenance.dingdangmarketArchive?.waybackSnapshot ?? "",
      license: "仅作来源说明",
    },
  ],
  affixes: source.affixes.map(row => ({
    effectId: Number(row.effectId),
    name: row.nameZh,
    aliases: row.aliases ?? [],
    category: row.category ?? "未分类",
    explanation: cleanExplanation(row.explanation),
    superposability: row.stackability ?? "未知",
    compatibilityId: Number(row.compatibilityId ?? -1),
    sortId: Number(row.sortId ?? row.effectId),
    poolIds: effectivePoolIds(row),
    isCurse: Boolean(row.isCurse),
    requiresCurse: Boolean(row.requiresCurse),
    popularity: row.popularity?.queryCount == null ? null : Number(row.popularity.queryCount),
    source: (row.sources ?? []).join(" · "),
  })),
};

const ids = catalog.affixes.map(row => row.effectId);
if (new Set(ids).size !== ids.length) throw new Error("Duplicate effect IDs in generated catalog");
if (catalog.affixes.filter(row => !row.isCurse).length < 3) throw new Error("Too few positive affixes");

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.writeFile(outputPath, `${JSON.stringify(catalog, null, 2)}\n`, "utf8");

const counts = {
  records: catalog.affixes.length,
  positive: catalog.affixes.filter(row => !row.isCurse).length,
  curses: catalog.affixes.filter(row => row.isCurse).length,
  normalCurrent: catalog.affixes.filter(row => row.poolIds.includes(110)).length,
  normalLegacy: catalog.affixes.filter(row => row.poolIds.includes(100)).length,
  deepPositive: catalog.affixes.filter(row => row.poolIds.some(id => [2000000, 2100000, 2200000].includes(id))).length,
  popular: catalog.affixes.filter(row => row.popularity != null).length,
};
console.log(JSON.stringify({ outputPath, counts }, null, 2));
