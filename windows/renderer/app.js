(function () {
  "use strict";

  var Core = window.RelicCore;
  if (!Core) {
    document.querySelector("[data-testid='loading-overlay']").textContent = "规则模块载入失败";
    return;
  }

  // 存档对比模块（renderer/savediff.js）。缺失时只影响「对比另一份存档」。
  var Diff = window.NightreignSaveDiff || null;
  // 存档报告模块（renderer/savereport.js）。缺失时只影响「导出报告 / 导出 CSV」。
  var Report = window.NightreignSaveReport || null;

  // 新页面（首领数据 / 词条反查 / 增伤排名）可用的游戏数据文件。
  var GAME_DATA_NAMES = ["bosses", "skills", "buffs"];

  // 浏览器预览模式下的读取方式，与 affixes.json / relics.json 一致：
  // renderer/ 与 resources/ 同级，所以相对路径是 ../resources/<name>.json。
  function fetchGameData(name) {
    return fetch("../resources/" + name + ".json").then(function (response) {
      if (!response.ok) throw new Error("无法载入 " + name + ".json");
      return response.json();
    });
  }

  var browserPreview = !window.nightreign;
  var api = window.nightreign || {
    platform: "browser-preview",
    loadCatalog: function () {
      return fetch("../resources/affixes.json").then(function (response) {
        if (!response.ok) throw new Error("无法载入内置词条库");
        return response.json();
      }).then(function (catalog) { return { catalog: catalog, origin: "built-in" }; });
    },
    importCatalog: function () { return Promise.resolve(null); },
    saveCustomCatalog: function () { return Promise.resolve({ ok: false }); },
    resetCatalog: function () { return Promise.resolve(null); },
    exportCatalog: function () { return Promise.resolve({ canceled: true }); },
    openSaveFile: function () { return Promise.resolve(null); },
    // 以下四个存档页能力都要读写本机文件，浏览器预览模式下只能给出提示。
    locateSaveFiles: function () { return Promise.resolve([]); },
    openLocatedSave: function () { return Promise.resolve(null); },
    parseSaveData: function () { return Promise.reject(new Error("浏览器预览模式无法解析存档")); },
    exportText: function () { return Promise.resolve({ canceled: true }); },
    loadRelicData: function () {
      return fetch("../resources/relics.json").then(function (response) {
        if (!response.ok) throw new Error("无法载入内置遗物数据");
        return response.json();
      });
    },
    loadGameData: fetchGameData
  };

  var modeKeys = ["currentNormal", "legacyNormal", "deepPositive", "compatibilityOnly"];
  var state = {
    page: "checker",
    mode: "currentNormal",
    catalog: null,
    origin: "built-in",
    selected: [null, null, null],
    result: null,
    pickerSlot: 0,
    pickerQuery: "",
    pickerCategory: "全部",
    pickerShowUnavailable: false,
    libraryQuery: "",
    libraryCategory: "全部",
    libraryOnlyEligible: true,
    busy: false,
    save: {
      relicData: null,
      index: null,
      indexPromise: null,
      payload: null,
      audits: [],
      character: 0,
      filter: "all",
      query: "",
      busy: false,
      locations: null,       // 自动查找结果；null = 还没查过
      compare: null,         // { payload, audits, diff }，见 renderer/savediff.js
      compareQuery: "",      // 对比列表的搜索词
      compareDirection: "all", // all | added | removed
      explained: []          // 展开了说明的词条，键是「角色:遗物序号:effectId」
    }
  };

  var $ = function (selector, root) { return (root || document).querySelector(selector); };
  var $$ = function (selector, root) { return Array.prototype.slice.call((root || document).querySelectorAll(selector)); };
  var test = function (name) { return $("[data-testid='" + name + "']"); };
  var esc = function (value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (char) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[char];
    });
  };
  var asCatalog = function (payload) { return payload && payload.catalog ? payload.catalog : payload; };
  var originLabel = function (origin) { return origin === "custom" ? "自定义数据" : "内置数据"; };
  var currentMode = function () { return Core.MODES[state.mode]; };
  var positiveAffixes = function () { return state.catalog.affixes.filter(function (affix) { return !affix.isCurse; }); };
  var selectedAffixes = function () { return state.selected.filter(Boolean); };
  var categories = function () {
    return Array.from(new Set(positiveAffixes().map(function (affix) { return affix.category || "未分类"; }))).sort(function (a, b) { return a.localeCompare(b, "zh-CN"); });
  };
  var catalogSummary = function () {
    var positive = positiveAffixes().length;
    return positive + " 条正面词条 · " + (state.catalog.affixes.length - positive) + " 条负面词条";
  };
  var pill = function (text, kind) { return "<span class='pill pill--" + (kind || "purple") + "'>" + esc(text) + "</span>"; };

  function showToast(message, isError) {
    var toast = test("toast");
    toast.textContent = message;
    toast.classList.toggle("is-error", Boolean(isError));
    toast.hidden = false;
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(function () { toast.hidden = true; }, 3000);
  }

  function setDataMessage(message, isError) {
    var element = test("data-message");
    element.textContent = message || "";
    element.classList.toggle("is-error", Boolean(isError));
  }

  function setBusy(value) {
    state.busy = value;
    $$('[data-action="import"], [data-action="export"], [data-action="reset"]').forEach(function (button) { button.disabled = value; });
  }

  // ---- 新页面脚手架（renderer/pages/*.js，契约见 renderer/pages/README.md）----

  // 提供给页面模块的通用小函数；行为与 app.js 内部使用的完全一致。
  var helpers = Object.freeze({
    escapeHtml: esc,
    pill: pill,
    foldForSearch: Core.foldForSearch,
    searchableText: Core.searchableText,
    showToast: showToast,
    query: $,
    queryAll: $$,
    byTestId: test
  });

  var gameDataCache = {};
  var pageInited = {};

  // 内置占位文件（go:embed 要求文件必须存在）视同「数据未内置」。
  function hasGameData(data) {
    if (!data || typeof data !== "object") return false;
    return Array.isArray(data) || data.placeholder !== true;
  }

  // 懒加载 + 缓存；文件缺失、仍是占位内容或读取失败都 resolve null，不抛错。
  function getGameData(name) {
    if (GAME_DATA_NAMES.indexOf(name) === -1) return Promise.resolve(null);
    if (!gameDataCache[name]) {
      gameDataCache[name] = Promise.resolve().then(function () {
        return typeof api.loadGameData === "function" ? api.loadGameData(name) : fetchGameData(name);
      }).then(function (data) {
        return hasGameData(data) ? data : null;
      }).catch(function () {
        return null;
      });
    }
    return gameDataCache[name];
  }

  function pageContext() {
    return {
      Core: Core,
      catalog: state.catalog,
      relicData: state.save.relicData,
      getGameData: getGameData,
      helpers: helpers
    };
  }

  function pageModule(key) {
    var registry = window.NightreignPages;
    return registry && registry[key] ? registry[key] : null;
  }

  // 首次切换到某个新页面时调用一次 init；模块出错不影响其余界面。
  function activatePage(key) {
    if (pageInited[key]) return;
    var module = pageModule(key);
    var mount = $("[data-mount='" + key + "']");
    if (!module || !mount || typeof module.init !== "function") return;
    pageInited[key] = true;
    try {
      module.init(mount, pageContext());
    } catch (error) {
      mount.innerHTML = "<p class='page-error'>页面载入失败：" + esc(error.message) + "</p>";
      console.error("页面 " + key + " init 失败", error);
    }
  }

  // 词条库 / 存档数据变化后通知已初始化的页面。
  function refreshPages() {
    Object.keys(pageInited).forEach(function (key) {
      var module = pageModule(key);
      if (!module || typeof module.refresh !== "function") return;
      try {
        module.refresh(pageContext());
      } catch (error) {
        console.error("页面 " + key + " refresh 失败", error);
      }
    });
  }

  function renderNav() {
    $$("[data-page-target]").forEach(function (button) {
      var active = button.dataset.pageTarget === state.page;
      button.classList.toggle("is-active", active);
      if (active) button.setAttribute("aria-current", "page"); else button.removeAttribute("aria-current");
    });
    $$("[data-page]").forEach(function (page) {
      var active = page.dataset.page === state.page;
      page.hidden = !active;
      page.classList.toggle("is-active", active);
    });
  }

  function modeOptions(selectedKey, short) {
    return modeKeys.map(function (key) {
      var mode = Core.MODES[key];
      return "<option value='" + key + "'" + (key === selectedKey ? " selected" : "") + ">" + esc(short ? mode.shortTitle : mode.title) + "</option>";
    }).join("");
  }

  function renderModes() {
    test("checker-mode-control").innerHTML = modeKeys.map(function (key) {
      var mode = Core.MODES[key];
      return "<button type='button' class='segment-button" + (key === state.mode ? " is-active" : "") + "' data-mode='" + key + "' data-testid='mode-" + key + "' role='radio' aria-checked='" + (key === state.mode) + "'>" + esc(mode.shortTitle) + "</button>";
    }).join("");
    test("mode-detail").textContent = currentMode().detail;
    test("library-mode").innerHTML = modeOptions(state.mode, false);
    test("data-mode-options").innerHTML = modeKeys.map(function (key) {
      var mode = Core.MODES[key];
      return "<button type='button' class='mode-option" + (key === state.mode ? " is-active" : "") + "' data-mode='" + key + "' data-testid='data-mode-" + key + "'><span class='mode-radio'>" + (key === state.mode ? "✓" : "") + "</span><span><strong>" + esc(mode.title) + "</strong><p>" + esc(mode.detail) + "</p></span></button>";
    }).join("");
  }

  function renderSlots() {
    $$("[data-slot]").forEach(function (button) {
      var slot = Number(button.dataset.slot);
      var affix = state.selected[slot];
      button.setAttribute("aria-label", affix ? "词条 " + (slot + 1) + "：" + affix.name + (affix.requiresCurse ? "（需诅咒）" : "") : "选择词条 " + (slot + 1));
      button.innerHTML = "<span class='slot-number'>" + (slot + 1) + "</span>" +
        (affix ? "<span class='slot-copy'><span class='slot-name-row'><span class='slot-name'>" + esc(affix.name) + "</span>" + (affix.requiresCurse ? pill("需诅咒", "amber") : "") + "</span><span class='slot-meta'><span>" + esc(affix.category) + "</span><span>ID " + affix.effectId + "</span><span>顺序 " + affix.sortId + "</span></span></span><span class='slot-clear' data-clear-slot='" + slot + "' title='清除此词条' aria-label='清除此词条'>×</span>" :
          "<span class='slot-copy'><span class='slot-name slot-empty'>点击选择第 " + (slot + 1) + " 条词条</span><span class='slot-meta'><span>保持遗物画面从上到下的顺序</span></span></span><span class='slot-add'>＋</span>");
    });
  }

  function resultMeta(status) {
    if (status === "valid") return { icon: "✓", title: "合法", banner: "valid" };
    if (status === "wrongOrder") return { icon: "⇅", title: "顺序错误", banner: "wrongOrder" };
    if (status === "invalid") return { icon: "!", title: "不合法", banner: "invalid" };
    return { icon: "…", title: "尚未完成", banner: "" };
  }

  function renderResult() {
    var host = test("result-content");
    if (!state.result) {
      host.innerHTML = "<div class='waiting-state'><div class='waiting-icon'>✓</div><h3>等待检查</h3><p>选择三个词条后，应用会依次核对出货池、重复效果、compatibilityId 互斥池，以及最终保存顺序。</p></div>";
      return;
    }
    var result = state.result;
    var meta = resultMeta(result.status);
    var issues = (result.issues || []).map(function (issue) {
      return "<div class='issue-row'><span class='issue-symbol'>!</span><div><strong>" + esc(issue.title) + "</strong><p>" + esc(issue.detail) + "</p></div></div>";
    }).join("");
    var warnings = (result.warnings || []).map(function (issue) {
      return "<div class='issue-row issue-row--warning'><span class='issue-symbol'>△</span><div><strong>" + esc(issue.title) + "</strong><p>" + esc(issue.detail) + "</p></div></div>";
    }).join("");
    var ordered = (result.orderedAffixes || []).map(function (affix, index) {
      return "<div class='ordered-row'><span class='order-index'>" + (index + 1) + "</span><span class='order-name'>" + esc(affix.name) + "</span><span class='order-key'>" + affix.sortId + " → " + affix.effectId + "</span></div>";
    }).join("");
    var orderBlock = ordered ? "<div class='order-block'><div class='order-heading'><strong>" + (result.status === "wrongOrder" ? "正确的词条顺序" : "规范顺序") + "</strong><span>sortId → effectId</span></div><div class='order-list'>" + ordered + "</div></div>" : "";
    var reorder = result.status === "wrongOrder" ? "<button type='button' class='button button--primary button--wide reorder-button' data-action='reorder' data-testid='reorder-button'>⇅ 按正确顺序重新排列</button>" : "";
    host.innerHTML = "<div class='result-state'><div class='result-banner result-banner--" + meta.banner + "'><div class='result-banner-icon'>" + meta.icon + "</div><div><strong>" + meta.title + "</strong><p>" + esc(result.message) + "</p></div></div><div class='result-scroll'>" + ((issues || warnings) ? "<div class='issues'>" + issues + warnings + "</div>" : "") + orderBlock + reorder + "</div></div>";
  }

  function renderPopular() {
    var eligible = positiveAffixes().filter(function (affix) { return Core.isEligible(affix, state.mode); });
    var ranked = eligible.filter(function (affix) { return Number.isFinite(affix.popularity); }).sort(function (a, b) { return b.popularity - a.popularity; });
    var popular = (ranked.length ? ranked : eligible.sort(function (a, b) { return a.name.localeCompare(b.name, "zh-CN"); })).slice(0, 18);
    test("popular-list").innerHTML = popular.length ? popular.map(function (affix) {
      return "<button type='button' class='popular-item' data-popular-id='" + affix.effectId + "'><span class='popular-spark'>✦</span><span class='popular-copy'><span class='popular-name'>" + esc(affix.name) + "</span><span class='popular-meta'><span>" + esc(affix.category) + "</span>" + (affix.popularity != null ? "<span>查询 " + affix.popularity.toLocaleString("zh-CN") + "</span>" : "") + "</span></span><span class='popular-plus'>＋</span></button>";
    }).join("") : "<div class='popular-empty'>当前口径暂无可用词条</div>";
  }

  function categoryOptions(selected) {
    return ["全部"].concat(categories()).map(function (category) {
      return "<option value='" + esc(category) + "'" + (category === selected ? " selected" : "") + ">" + esc(category === "全部" ? "全部分类" : category) + "</option>";
    }).join("");
  }

  function renderCatalogHeader() {
    var summary = catalogSummary();
    test("topbar-version").innerHTML = "<b>●</b><span>" + esc(state.catalog.gameVersion || "未知版本") + "</span>";
    test("catalog-summary-badge").textContent = summary;
    test("library-summary").textContent = summary;
    test("catalog-origin").textContent = originLabel(state.origin);
    test("catalog-game-version").textContent = state.catalog.gameVersion || "—";
    test("catalog-data-version").textContent = state.catalog.dataVersion || "—";
    test("catalog-summary").textContent = summary;
    test("catalog-generated-at").textContent = state.catalog.generatedAt || "—";
    test("catalog-schema").textContent = "Schema v" + (state.catalog.schemaVersion || "—");
    test("library-category").innerHTML = categoryOptions(state.libraryCategory);
    test("picker-category").innerHTML = categoryOptions(state.pickerCategory);
  }

  function eligibleModePills(affix) {
    var html = modeKeys.slice(0, 3).filter(function (key) { return Core.isEligible(affix, key); }).map(function (key) { return pill(Core.MODES[key].shortTitle, "green"); }).join("");
    return html + (affix.requiresCurse ? pill("需诅咒", "amber") : "");
  }

  function renderLibrary() {
    var needle = Core.foldForSearch(state.libraryQuery);
    var rows = positiveAffixes().filter(function (affix) {
      if (state.libraryOnlyEligible && !Core.isEligible(affix, state.mode)) return false;
      if (state.libraryCategory !== "全部" && affix.category !== state.libraryCategory) return false;
      return !needle || Core.searchableText(affix).indexOf(needle) !== -1;
    }).sort(function (a, b) { return a.sortId - b.sortId || a.effectId - b.effectId; });
    test("library-table-body").innerHTML = rows.map(function (affix) {
      return "<tr data-effect-id='" + affix.effectId + "'><td class='id-cell'><strong>" + affix.sortId + "</strong><span>" + affix.effectId + "</span></td><td class='affix-cell'><strong>" + esc(affix.name) + "</strong>" + (affix.explanation ? "<p>" + esc(affix.explanation) + "</p>" : "") + "</td><td class='category-cell'>" + esc(affix.category) + "</td><td class='number-cell'>" + affix.compatibilityId + "</td><td class='modes-cell'>" + eligibleModePills(affix) + "</td></tr>";
    }).join("");
    test("library-empty").hidden = rows.length > 0;
    test("library-count").textContent = "当前显示 " + rows.length + " 条";
  }

  function renderData() {
    test("sources-list").innerHTML = (state.catalog.sources || []).map(function (source) {
      var tags = (source.revision ? pill(String(source.revision).slice(0, 10), "purple") : "") + (source.license ? pill(source.license, "green") : "");
      return "<div class='source-row'><span class='source-icon'>▧</span><div><strong>" + esc(source.name) + "</strong><p class='source-url'>" + esc(source.url) + "</p><div class='source-tags'>" + tags + "</div></div></div>";
    }).join("") || "<div class='popular-empty'>未提供来源信息</div>";
  }

  function renderPicker() {
    var needle = Core.foldForSearch(state.pickerQuery);
    var rows = positiveAffixes().filter(function (affix) {
      if (!state.pickerShowUnavailable && !Core.isEligible(affix, state.mode)) return false;
      if (state.pickerCategory !== "全部" && affix.category !== state.pickerCategory) return false;
      return !needle || Core.searchableText(affix).indexOf(needle) !== -1;
    }).sort(function (a, b) {
      var ae = Core.isEligible(a, state.mode), be = Core.isEligible(b, state.mode);
      return ae === be ? a.sortId - b.sortId || a.effectId - b.effectId : (ae ? -1 : 1);
    });
    test("picker-title").textContent = "选择词条 " + (state.pickerSlot + 1);
    test("picker-mode-label").textContent = "当前口径：" + currentMode().title;
    test("picker-count").textContent = rows.length + " 条";
    test("picker-list").innerHTML = rows.length ? rows.map(function (affix) {
      var eligible = Core.isEligible(affix, state.mode);
      return "<button type='button' class='picker-row" + (eligible ? "" : " is-unavailable") + "' data-picker-id='" + affix.effectId + "'><span class='picker-ids'><strong>" + affix.effectId + "</strong><span>" + affix.sortId + "</span></span><span class='picker-copy'><span class='picker-name-row'><strong>" + esc(affix.name) + "</strong>" + pill(affix.category, "purple") + (affix.requiresCurse ? pill("需诅咒", "amber") : "") + "</span>" + (affix.explanation ? "<p class='picker-explanation'>" + esc(affix.explanation) + "</p>" : "") + "<span class='picker-meta'>互斥池 " + affix.compatibilityId + " · " + esc(affix.superposability || "未知") + "</span></span><span class='picker-status'>" + (eligible ? "⊕" : "⊘") + "</span></button>";
    }).join("") : "<div class='empty-state picker-no-results'><div class='empty-icon'>⌕</div><h3>没有匹配词条</h3><p>请更换关键词或分类</p></div>";
  }

  function renderSelectionArea() {
    renderModes();
    renderSlots();
    renderResult();
    renderPopular();
    renderLibrary();
  }

  function renderAll() {
    renderNav();
    renderCatalogHeader();
    renderSelectionArea();
    renderData();
  }

  function setMode(key) {
    if (!Core.MODES[key] || key === state.mode) return;
    state.mode = key;
    state.result = null;
    state.selected = state.selected.map(function (affix) { return affix && Core.isEligible(affix, key) ? affix : null; });
    renderSelectionArea();
  }

  function openPicker(slot) {
    state.pickerSlot = slot;
    state.pickerQuery = "";
    state.pickerCategory = "全部";
    state.pickerShowUnavailable = false;
    test("picker-search").value = "";
    test("picker-category").innerHTML = categoryOptions("全部");
    test("picker-show-unavailable").checked = false;
    renderPicker();
    test("picker-dialog").showModal();
    setTimeout(function () { test("picker-search").focus(); }, 0);
  }

  function findAffix(id) {
    return state.catalog.affixes.find(function (affix) { return affix.effectId === Number(id); }) || null;
  }

  function chooseAffix(affix, slot) {
    state.selected[slot] = affix;
    state.result = null;
    renderSlots();
    renderResult();
  }

  function fillNext(affix) {
    if (state.selected.some(function (item) { return item && item.effectId === affix.effectId; })) {
      showToast("该词条已经在选择中");
      return;
    }
    var empty = state.selected.indexOf(null);
    chooseAffix(affix, empty === -1 ? 2 : empty);
  }

  function performCheck() {
    state.result = Core.check(selectedAffixes(), state.mode);
    renderResult();
  }

  function performRandom() {
    var combination = Core.randomCombination(positiveAffixes(), state.mode);
    if (!combination) {
      state.result = { status: "invalid", message: "当前词条库无法生成合法组合", orderedAffixes: [], issues: [], warnings: [] };
    } else {
      state.selected = combination.slice();
      state.result = Core.check(combination, state.mode);
    }
    renderSlots();
    renderResult();
  }

  function installCatalog(catalog, origin) {
    state.catalog = Core.validateCatalog(catalog);
    state.origin = origin || "built-in";
    state.selected = [null, null, null];
    state.result = null;
    state.libraryCategory = "全部";
    state.pickerCategory = "全部";
    if (state.save.relicData) {
      state.save.index = Core.buildRelicIndex(state.catalog, state.save.relicData);
      if (state.save.payload) { state.save.audits = auditCharacters(state.save.payload); renderSave(); }
    }
    renderAll();
    refreshPages();
  }

  async function importCatalog() {
    if (browserPreview) { setDataMessage("导入词条库仅在桌面应用中可用"); showToast("此功能在桌面应用中可用"); return; }
    setBusy(true);
    try {
      var picked = await api.importCatalog();
      if (!picked) return;
      var catalog = Core.validateCatalog(asCatalog(picked));
      var saved = await api.saveCustomCatalog(catalog);
      installCatalog(catalog, saved && saved.origin ? saved.origin : "custom");
      setDataMessage("已载入 " + catalog.affixes.length + " 条词条" + (picked.fileName ? " · " + picked.fileName : ""));
    } catch (error) {
      setDataMessage("导入失败：" + error.message, true);
      showToast("导入失败：" + error.message, true);
    } finally { setBusy(false); }
  }

  async function exportCatalog() {
    if (browserPreview) { setDataMessage("导出词条库仅在桌面应用中可用"); showToast("此功能在桌面应用中可用"); return; }
    setBusy(true);
    try {
      var safeVersion = String(state.catalog.dataVersion || "current").replace(/[^a-zA-Z0-9._-]+/g, "-");
      var output = await api.exportCatalog(state.catalog, "nightreign-affixes-" + safeVersion + ".json");
      if (output && !output.canceled) setDataMessage("已导出：" + (output.filePath || "词条库 JSON"));
    } catch (error) { setDataMessage("导出失败：" + error.message, true); showToast("导出失败：" + error.message, true); }
    finally { setBusy(false); }
  }

  async function resetCatalog() {
    if (browserPreview) { setDataMessage("恢复内置数据仅在桌面应用中可用"); showToast("此功能在桌面应用中可用"); return; }
    setBusy(true);
    try {
      var payload = await api.resetCatalog();
      installCatalog(asCatalog(payload), payload.origin || "built-in");
      setDataMessage("已恢复内置词条库");
    } catch (error) { setDataMessage("恢复失败：" + error.message, true); showToast("恢复失败：" + error.message, true); }
    finally { setBusy(false); }
  }

  // ---- 存档检查 ----

  var SAVE_FILTERS = [
    { key: "all", label: "全部" },
    { key: "invalid", label: "仅非法" },
    { key: "deep", label: "深夜遗物" }
  ];
  var RELIC_COLOR_PILLS = ["red", "blue", "amber", "green", "gray"];
  var normId = function (value) { return value == null || value === 0 || value === -1 || value === 4294967295 ? -1 : value; };

  function setSaveMessage(message, isError) {
    var element = test("save-message");
    element.textContent = message || "";
    element.classList.toggle("is-error", Boolean(isError));
  }

  function setSaveBusy(value) {
    state.save.busy = value;
    $$("[data-save-busy]").forEach(function (button) { button.disabled = value; });
  }

  function ensureRelicIndex() {
    if (state.save.index) return Promise.resolve(state.save.index);
    if (!state.save.indexPromise) {
      state.save.indexPromise = api.loadRelicData().then(function (relicData) {
        state.save.relicData = relicData;
        state.save.index = Core.buildRelicIndex(state.catalog, relicData);
        refreshPages();
        return state.save.index;
      }).catch(function (error) {
        state.save.indexPromise = null;
        throw error;
      });
    }
    return state.save.indexPromise;
  }

  function auditCharacters(payload) {
    return payload.characters.map(function (character) {
      var relics = character.relics || [];
      var audits = relics.map(function (relic) { return Core.auditRelic(relic, state.save.index); });
      Core.applyUniqueDuplicates(audits, relics);
      return audits;
    });
  }

  function saveAffixName(effectId) {
    var affix = state.save.index.affixIndex.get(effectId);
    return affix && affix.name ? affix.name : "未知词条 #" + effectId;
  }

  // 词条库里的说明文字；没有说明的词条返回空串（界面就不显示展开入口）。
  function saveAffixExplanation(effectId) {
    var affix = state.save.index.affixIndex.get(effectId);
    var explanation = affix && typeof affix.explanation === "string" ? affix.explanation.trim() : "";
    return explanation;
  }

  // 展开状态按「哪张卡的哪一条」记，不按 effectId 全局记：同一条词条出现在同一
  // 角色的多张卡上时，点开一处不应该把别的卡一起撑开。
  function explainKey(cardKey, effectId) {
    return cardKey + ":" + effectId;
  }

  function isExplained(key) {
    return state.save.explained.indexOf(key) !== -1;
  }

  // 词条名（带说明的可点开/悬停查看 explanation，与词条库页的口径一致）
  function saveAffixNameHtml(effectId, isCurse, cardKey) {
    var name = saveAffixName(effectId);
    var explanation = saveAffixExplanation(effectId);
    var className = "save-affix-name" + (isCurse ? " save-affix-name--curse" : "");
    if (!explanation) return "<span class='" + className + "'>" + esc(name) + "</span>";
    var key = explainKey(cardKey, effectId);
    var open = isExplained(key);
    return "<button type='button' class='" + className + " save-affix-name--explain" + (open ? " is-open" : "") +
      "' data-explain-key='" + esc(key) + "' aria-expanded='" + open + "' title='" + esc(explanation) + "'>" +
      esc(name) + "<span class='save-affix-mark' aria-hidden='true'>?</span></button>" +
      (open ? "<span class='save-affix-note' data-testid='save-affix-note'>" + esc(explanation) + "</span>" : "");
  }

  function relicDisplayName(itemId, meta) {
    if (!meta) return "未知遗物 #" + itemId;
    return meta.name || "未命名遗物 #" + itemId;
  }

  // 遗物卡搜索文本：名称、种类、ID、全部正负词条名与 ID
  function relicSearchText(relic, meta) {
    var parts = [relicDisplayName(relic.itemId, meta), String(relic.itemId), Core.relicKindLabel(relic.itemId, meta)];
    relic.effects.concat(relic.curses).forEach(function (effectId) {
      if (effectId === -1) return;
      parts.push(saveAffixName(effectId), String(effectId));
    });
    return Core.foldForSearch(parts.join(" "));
  }

  // 状态三态：文案与 renderer/savereport.js 的 statusLabel 同一份口径
  // （「非法 / 警告 / 合法」），这里只额外带出配色与筛选用的 key。
  var STATUS_META = {
    "非法": { key: "invalid", pill: "red" },
    "警告": { key: "warning", pill: "amber" },
    "合法": { key: "valid", pill: "green" }
  };

  function relicStatusMeta(audit) {
    var label = Report ? Report.statusLabel(audit)
      : (audit.status === "invalid" ? "非法" : ((audit.warnings || []).length > 0 ? "警告" : "合法"));
    var meta = STATUS_META[label];
    return { key: meta.key, label: label, pill: meta.pill };
  }

  function saveRelicCard(relic, audit, meta, cardKey) {
    var status = relicStatusMeta(audit);
    var pills = pill(Core.relicKindLabel(relic.itemId, meta), "purple");
    if (meta) {
      pills += pill(Core.relicColorLabel(meta.color) + "色", RELIC_COLOR_PILLS[meta.color] || "purple");
      if (meta.deep) pills += pill("深夜", "purple");
    }

    var lines = [];
    for (var line = 0; line < 3; line += 1) {
      var effectId = normId((relic.effects || [])[line]);
      var curseId = normId((relic.curses || [])[line]);
      if (effectId === -1 && curseId === -1) continue;
      var content = effectId === -1
        ? "<span class='save-affix-empty'>（空）</span>"
        : saveAffixNameHtml(effectId, false, cardKey);
      if (curseId !== -1) content += "<span class='save-affix-curse'>｜" + saveAffixNameHtml(curseId, true, cardKey) + "</span>";
      lines.push("<div class='save-affix-row'><span class='save-affix-index'>" + (line + 1) + "</span><span class='save-affix-text'>" + content + "</span></div>");
    }
    if (!lines.length) lines.push("<div class='save-affix-row save-affix-row--none'>（没有词条）</div>");

    var issues = (audit.issues || []).map(function (issue) {
      return "<div class='issue-row'><span class='issue-symbol'>!</span><div><strong>" + esc(issue.title) + "</strong><p>" + esc(issue.detail) + "</p></div></div>";
    }).join("");
    var warnings = (audit.warnings || []).map(function (issue) {
      return "<div class='issue-row issue-row--warning'><span class='issue-symbol'>△</span><div><strong>" + esc(issue.title) + "</strong><p>" + esc(issue.detail) + "</p></div></div>";
    }).join("");

    var orderBlock = "";
    var hasWrongOrder = (audit.issues || []).some(function (issue) { return issue.kind === "wrongOrder"; });
    if (hasWrongOrder && audit.orderedEffects) {
      var orderedRows = audit.orderedEffects.map(function (effectId, index) {
        return "<div class='ordered-row'><span class='order-index'>" + (index + 1) + "</span><span class='order-name'>" +
          (effectId === -1 ? "（空）" : esc(saveAffixName(effectId))) + "</span></div>";
      }).join("");
      orderBlock = "<div class='order-block'><div class='order-heading'><strong>正确的词条顺序</strong><span>sortId → effectId</span></div><div class='order-list'>" + orderedRows + "</div></div>";
    }
    if (audit.officialEffects) {
      var officialRows = audit.officialEffects.filter(function (effectId) { return effectId !== -1; })
        .map(function (effectId, index) {
          return "<div class='ordered-row'><span class='order-index'>" + (index + 1) + "</span><span class='order-name'>" +
            esc(saveAffixName(effectId)) + " <span class='order-id'>(" + effectId + ")</span></span></div>";
        }).join("");
      orderBlock += "<div class='order-block'><div class='order-heading'><strong>该遗物的官方固定词条</strong><span>可据此改回</span></div><div class='order-list'>" + officialRows + "</div></div>";
    }

    return "<article class='save-relic save-relic--" + status.key + (meta ? " save-relic--c" + meta.color : "") + "' data-testid='save-relic'>" +
      "<div class='save-relic-head'><strong class='save-relic-name'>" + esc(relicDisplayName(relic.itemId, meta)) + "</strong>" + pill(status.label, status.pill) + "</div>" +
      "<div class='save-relic-pills'>" + pills + "<span class='save-relic-slot'>#" + (Number(relic.index) + 1 || "—") + "</span></div>" +
      "<div class='save-affix-list'>" + lines.join("") + "</div>" +
      ((issues || warnings) ? "<div class='issues save-relic-issues'>" + issues + warnings + "</div>" : "") +
      orderBlock +
      "</article>";
  }

  function renderSaveRelics() {
    var payload = state.save.payload;
    if (!payload) return;
    var character = payload.characters[state.save.character];
    var audits = state.save.audits[state.save.character] || [];
    var relics = (character && character.relics) || [];

    var counts = { total: relics.length, valid: 0, invalid: 0, warning: 0 };
    audits.forEach(function (audit) { counts[relicStatusMeta(audit).key] += 1; });
    test("save-stats").innerHTML =
      pill("遗物 " + counts.total, "purple") +
      pill("合法 " + counts.valid, "green") +
      pill("非法 " + counts.invalid, "red");

    test("save-filter").innerHTML = SAVE_FILTERS.map(function (filter) {
      var active = filter.key === state.save.filter;
      return "<button type='button' class='segment-button" + (active ? " is-active" : "") + "' data-save-filter='" + filter.key + "' data-testid='save-filter-" + filter.key + "' role='radio' aria-checked='" + active + "'>" + filter.label + "</button>";
    }).join("");

    var notice = test("save-notice");
    var grid = test("save-relic-grid");
    if (character && character.parseError) {
      notice.innerHTML = "<div class='issue-row'><span class='issue-symbol'>!</span><div><strong>该槽位解析失败</strong><p>" + esc(character.parseError) + "</p></div></div>";
      grid.innerHTML = "";
      return;
    }
    notice.innerHTML = counts.total > 0 && counts.invalid === 0
      ? "<div class='save-congrats' data-testid='save-congrats'>🎉 未发现不合法遗物</div>"
      : "";

    var needle = Core.foldForSearch(state.save.query || "");
    var cards = [];
    relics.forEach(function (relic, index) {
      var audit = audits[index];
      if (!audit) return;
      var meta = state.save.index.relicsById.get(relic.itemId);
      if (state.save.filter === "invalid" && audit.status !== "invalid") return;
      if (state.save.filter === "deep" && !(meta && meta.deep)) return;
      if (needle && relicSearchText(relic, meta).indexOf(needle) === -1) return;
      cards.push(saveRelicCard(relic, audit, meta, state.save.character + ":" + index));
    });
    grid.innerHTML = cards.length ? cards.join("") : (
      "<div class='empty-state save-empty' data-testid='save-empty'><div class='empty-icon'>" +
      (state.save.filter === "invalid" ? "🎉" : "⌕") + "</div><h3>" +
      (state.save.filter === "invalid" ? "未发现不合法遗物" : (counts.total === 0 ? "该角色没有遗物" : "没有符合条件的遗物")) +
      "</h3></div>");
  }

  function renderSave() {
    var payload = state.save.payload;
    test("save-results").hidden = !payload;
    test("save-checksum").hidden = !payload || payload.checksumOk !== false;
    test("save-file-meta").textContent = payload ? payload.fileName || "" : "";
    renderSaveCompare();
    if (!payload) return;
    test("save-character").innerHTML = payload.characters.map(function (character, index) {
      var label = "槽位 " + (character.slot + 1) + "：" + (character.name || "未命名");
      if (character.parseError) label += "（解析失败）";
      return "<option value='" + index + "'" + (index === state.save.character ? " selected" : "") + ">" + esc(label) + "</option>";
    }).join("");
    renderSaveRelics();
  }

  // 解析成功后统一入口：重置筛选/对比状态并重绘。
  function applySavePayload(payload) {
    state.save.payload = payload;
    state.save.audits = auditCharacters(payload);
    state.save.character = 0;
    state.save.filter = "all";
    state.save.query = "";
    state.save.compare = null;
    state.save.compareQuery = "";
    state.save.compareDirection = "all";
    state.save.explained = []; // 换存档后旧卡片的展开状态没有意义
    test("save-search").value = "";
    setSaveMessage("已解析 " + (payload.fileName || "存档") + " · " + payload.characters.length + " 个角色");
    renderSave();
    refreshPages();
  }

  // 存档来源统一走这里：拿到 payload 前先确保遗物索引就绪，异常统一提示。
  async function loadSaveWith(loader, failPrefix, pendingMessage) {
    if (browserPreview) { setSaveMessage("存档检查仅在桌面应用中可用"); showToast("此功能在桌面应用中可用"); return; }
    setSaveBusy(true);
    setSaveMessage(pendingMessage || "");
    try {
      await ensureRelicIndex();
      var payload = await loader();
      if (!payload) return; // 用户取消
      applySavePayload(payload);
    } catch (error) {
      setSaveMessage(failPrefix + "：" + error.message, true);
      showToast(failPrefix + "：" + error.message, true);
    } finally {
      setSaveBusy(false);
    }
  }

  function openSave() {
    return loadSaveWith(function () { return api.openSaveFile(); }, "解析失败");
  }

  // ---- 自动查找存档 ----

  function formatFileSize(bytes) {
    if (!Number.isFinite(bytes) || bytes < 0) return "";
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
  }

  function formatDateTime(value) {
    var date = value ? new Date(value) : null;
    if (!date || isNaN(date.getTime())) return "";
    var pad = function (part) { return String(part).padStart(2, "0"); };
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) +
      " " + pad(date.getHours()) + ":" + pad(date.getMinutes());
  }

  // 自动查找的扫描范围与找不到时的路径规则。四段结构（标题 / 路径规则 /
  // 无缝联机 / 手动兜底）与 macOS 端 SaveLocator.pathHint 保持一致，只有中间
  // 那行路径按平台不同。
  var SAVE_SCAN_RANGE = "%APPDATA%\\Nightreign\\<Steam ID>\\";
  var SAVE_PATH_HINT = [
    "没有找到存档文件。",
    "路径规则：%APPDATA%\\Nightreign\\<Steam ID>\\NR0000.sl2",
    "无缝联机存档（.co2）在同一个目录下。",
    "其它情况（游戏装在别的 Windows 账号下、存档拷到了别处）请用「选择存档文件」手动打开，也可以直接把存档文件拖进来。"
  ];

  // 自动查找结果里也不放搜索框：一台机器上通常只有几个 Steam 账号目录，
  // 结果条数是个位数（macOS 端同理，两端保持一致）。
  function renderSaveLocations() {
    var container = test("save-locate");
    var locations = state.save.locations;
    if (!locations) { container.hidden = true; container.innerHTML = ""; return; }
    container.hidden = false;
    var scanRange = "<p class='save-locate-range' data-testid='save-locate-range'>扫描范围：" +
      esc(SAVE_SCAN_RANGE) + "</p>";
    if (!locations.length) {
      container.innerHTML = scanRange + "<div class='save-locate-empty' data-testid='save-locate-empty'>" +
        "<strong>" + esc(SAVE_PATH_HINT[0]) + "</strong>" +
        SAVE_PATH_HINT.slice(1).map(function (line) { return "<p>" + esc(line) + "</p>"; }).join("") +
        "</div>";
      return;
    }
    var rows = locations.map(function (location, index) {
      var meta = [location.steamId ? "Steam ID " + location.steamId : "Nightreign 根目录"];
      if (formatFileSize(location.size)) meta.push(formatFileSize(location.size));
      if (formatDateTime(location.modifiedAt)) meta.push("修改于 " + formatDateTime(location.modifiedAt));
      var coop = /\.co2$/i.test(location.fileName || "")
        ? pill("无缝联机", "amber")
        : "";
      return "<div class='save-locate-row' data-testid='save-locate-row'>" +
        "<div class='save-locate-copy'>" +
        "<div class='save-locate-name'><strong>" + esc(location.fileName) + "</strong>" + coop + "</div>" +
        "<span>" + esc(meta.join(" · ")) + "</span>" +
        "<code>" + esc(location.path) + "</code></div>" +
        "<button class='button button--secondary' type='button' data-locate-index='" + index +
        "' data-save-busy data-testid='save-locate-open'>打开</button></div>";
    }).join("");
    container.innerHTML = scanRange + "<div class='save-locate-list'>" + rows + "</div>";
    if (state.save.busy) setSaveBusy(true); // 新渲染出来的按钮同步当前忙碌状态
  }

  async function locateSaves() {
    if (browserPreview) { setSaveMessage("自动查找仅在桌面应用中可用"); showToast("此功能在桌面应用中可用"); return; }
    setSaveBusy(true);
    setSaveMessage("");
    try {
      var list = await api.locateSaveFiles();
      state.save.locations = Array.isArray(list) ? list : [];
      renderSaveLocations();
      setSaveMessage(state.save.locations.length
        ? "找到 " + state.save.locations.length + " 个存档文件"
        : "没有在 %APPDATA%\\Nightreign 下找到存档文件");
    } catch (error) {
      state.save.locations = null;
      renderSaveLocations();
      setSaveMessage("自动查找失败：" + error.message, true);
      showToast("自动查找失败：" + error.message, true);
    } finally {
      setSaveBusy(false);
    }
  }

  function openLocatedSave(index) {
    var location = (state.save.locations || [])[index];
    if (!location) return;
    return loadSaveWith(function () { return api.openLocatedSave(location.path); }, "打开失败");
  }

  // ---- 拖拽打开 ----

  var DROP_EXTENSIONS = [".sl2", ".co2"];
  var MAX_DROP_BYTES = 96 * 1024 * 1024;
  var dragDepth = 0;

  function isSaveFileName(name) {
    var lower = String(name || "").toLowerCase();
    return DROP_EXTENSIONS.some(function (ext) { return lower.endsWith(ext); });
  }

  // WebView2 里拿不到 File.path，只能把内容读成 ArrayBuffer 再转 base64 交给 Go。
  function fileToBase64(file) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onerror = function () { reject(new Error("无法读取该文件")); };
      reader.onload = function () {
        try {
          var bytes = new Uint8Array(reader.result);
          var chunk = 0x8000;
          var parts = [];
          for (var offset = 0; offset < bytes.length; offset += chunk) {
            parts.push(String.fromCharCode.apply(null, bytes.subarray(offset, offset + chunk)));
          }
          resolve(btoa(parts.join("")));
        } catch (error) {
          reject(new Error("无法读取该文件：" + error.message));
        }
      };
      reader.readAsArrayBuffer(file);
    });
  }

  function openDroppedFile(file) {
    if (!file) return;
    if (!isSaveFileName(file.name)) {
      setSaveMessage("只支持 .sl2 / .co2 存档文件：" + file.name, true);
      showToast("只支持 .sl2 / .co2 存档文件", true);
      return;
    }
    if (file.size > MAX_DROP_BYTES) {
      setSaveMessage("文件过大，无法解析：" + file.name, true);
      showToast("文件过大，无法解析", true);
      return;
    }
    return loadSaveWith(function () {
      return fileToBase64(file).then(function (encoded) { return api.parseSaveData(encoded, file.name); });
    }, "解析失败", "正在读取 " + file.name + " …");
  }

  function setDragActive(active) {
    test("save-drop-overlay").hidden = !active;
    $(".save-content").classList.toggle("is-dragover", active);
  }

  function dragHasFiles(event) {
    var transfer = event.dataTransfer;
    return Boolean(transfer && Array.prototype.indexOf.call(transfer.types || [], "Files") !== -1);
  }

  // 落点是否在存档页内（顶栏、别的页都不算）。
  function inSaveDropZone(target) {
    var zone = test("page-save");
    return Boolean(zone && target && zone.contains(target.nodeType === 1 ? target : target.parentNode));
  }

  // 全局兜底：Chromium / WebView2 对没被处理的文件 drop 的默认动作是导航到该
  // 文件，界面上没有返回入口，只能杀进程。桌面壳的 bridgeJS 已经在文档创建时
  // 挂了一层 window 级 preventDefault（bindings.go），这里再挂一层：既覆盖浏览器
  // 预览，也能在落点不在存档页时给出提示，而不是悄无声息地吞掉。
  function bindGlobalDropGuard() {
    document.addEventListener("dragover", function (event) {
      if (!dragHasFiles(event)) return;
      event.preventDefault();
    });
    document.addEventListener("drop", function (event) {
      if (!dragHasFiles(event)) return;
      event.preventDefault();
      if (inSaveDropZone(event.target)) return; // 存档页自己的处理器已经接手
      dragDepth = 0;
      setDragActive(false);
      showToast("请切到「存档检查」页，再把存档文件松开", true);
    });
  }

  function bindSaveDropZone() {
    var zone = test("page-save");
    var hasFiles = dragHasFiles;
    zone.addEventListener("dragenter", function (event) {
      if (!hasFiles(event)) return;
      event.preventDefault();
      dragDepth += 1;
      setDragActive(true);
    });
    zone.addEventListener("dragover", function (event) {
      if (!hasFiles(event)) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = "copy";
    });
    zone.addEventListener("dragleave", function () {
      dragDepth = Math.max(0, dragDepth - 1);
      if (dragDepth === 0) setDragActive(false);
    });
    zone.addEventListener("drop", function (event) {
      event.preventDefault();
      dragDepth = 0;
      setDragActive(false);
      var files = event.dataTransfer && event.dataTransfer.files;
      if (!files || !files.length) return;
      if (state.save.busy) { showToast("正在处理上一个存档，请稍候", true); return; }
      openDroppedFile(files[0]);
    });
  }

  // ---- 导出报告 ----

  // 报告正文全部由 renderer/savereport.js 生成（与 macOS 端
  // RelicCore/SaveReport.swift 逐行同口径）；这里只准备名称查询与落盘。
  function reportLookup() {
    return {
      affixName: saveAffixName,
      relicName: function (itemId) {
        return relicDisplayName(itemId, state.save.index.relicsById.get(itemId));
      },
      kindLabel: function (itemId) {
        return Core.relicKindLabel(itemId, state.save.index.relicsById.get(itemId));
      },
      // 颜色文案统一口径：遗物卡、TXT 报告、CSV 都写「红色」/「颜色未知」，
      // 不再一处写「红色」一处写「红」。
      colorText: function (itemId) {
        var meta = state.save.index.relicsById.get(itemId);
        return meta ? Core.relicColorLabel(meta.color) + "色" : "颜色未知";
      }
    };
  }

  function reportOptions(generatedAt) {
    var catalog = state.catalog || {};
    return {
      payload: state.save.payload,
      audits: state.save.audits,
      lookup: reportLookup(),
      catalog: {
        origin: originLabel(state.origin),
        gameVersion: catalog.gameVersion,
        dataVersion: catalog.dataVersion
      },
      generatedAt: generatedAt
    };
  }

  async function exportSaveReport(kind) {
    if (!state.save.payload) return;
    if (browserPreview) { setSaveMessage("导出报告仅在桌面应用中可用"); showToast("此功能在桌面应用中可用"); return; }
    if (!Report) { showToast("报告模块未载入", true); return; }
    var isCsv = kind === "csv";
    var now = new Date();
    var name = Report.suggestedFileName(state.save.payload.fileName, isCsv ? "csv" : "text", now);
    setSaveBusy(true);
    try {
      var options = reportOptions(now);
      var content = isCsv ? Report.csv(options) : Report.text(options);
      var output = await api.exportText(name, content);
      if (output && !output.canceled) {
        setSaveMessage("已导出：" + (output.filePath || name));
        showToast("报告已导出");
      }
    } catch (error) {
      setSaveMessage("导出失败：" + error.message, true);
      showToast("导出失败：" + error.message, true);
    } finally {
      setSaveBusy(false);
    }
  }

  // ---- 存档对比 ----

  // 整张对比卡的渲染预算（跨角色累计，不是「每角色每方向」）：存档最多 10 个
  // 槽位，按方向分别封顶的话，改过档的存档一次要拼几千行。
  var COMPARE_ROW_BUDGET = 400;
  var COMPARE_DIRECTIONS = [
    { key: "all", label: "全部" },
    { key: "added", label: "只看新增" },
    { key: "removed", label: "只看减少" }
  ];
  var STATUS_SEVERITY = { valid: 0, warning: 1, invalid: 2 };

  // 对比行的状态取自那一份存档「整体」算过的审查结果（与遗物网格同一套，
  // 含 Core.applyUniqueDuplicates 的唯一遗物重复检查），同款多件时取最严重的
  // 一件；拿不到整体结果时才退回单件判定。
  function compareEntryStatus(entry, audits) {
    var worst = null;
    (entry.positions || []).forEach(function (position) {
      var audit = audits && audits[position];
      if (!audit) return;
      var meta = relicStatusMeta(audit);
      if (!worst || STATUS_SEVERITY[meta.key] > STATUS_SEVERITY[worst.key]) worst = meta;
    });
    return worst || relicStatusMeta(Core.auditRelic(entry.relic, state.save.index));
  }

  function compareRelicRow(entry, direction, audits) {
    var relic = entry.relic;
    var meta = state.save.index.relicsById.get(relic.itemId);
    var status = compareEntryStatus(entry, audits);
    var affixes = [];
    for (var line = 0; line < 3; line += 1) {
      var effectId = normId((relic.effects || [])[line]);
      var curseId = normId((relic.curses || [])[line]);
      if (effectId === -1 && curseId === -1) continue;
      var text = effectId === -1 ? "（空）" : saveAffixName(effectId);
      if (curseId !== -1) text += "｜" + saveAffixName(curseId);
      affixes.push(esc(text));
    }
    return "<div class='save-diff-row save-diff-row--" + direction + "' data-testid='save-diff-row'>" +
      "<span class='save-diff-sign' aria-hidden='true'>" + (direction === "added" ? "＋" : "－") + "</span>" +
      "<div class='save-diff-copy'><div class='save-diff-head'><strong>" +
      esc(relicDisplayName(relic.itemId, meta)) + "</strong>" + pill(status.label, status.pill) +
      pill(Core.relicKindLabel(relic.itemId, meta), "purple") +
      (entry.count > 1 ? "<span class='save-diff-count'>×" + entry.count + "</span>" : "") +
      "<span class='save-diff-id'>ID " + relic.itemId + "</span></div>" +
      (affixes.length ? "<p class='save-diff-affixes'>" + affixes.join(" · ") + "</p>" : "") +
      "</div></div>";
  }

  function compareEntryMatches(entry, needle) {
    if (!needle) return true;
    var meta = state.save.index.relicsById.get(entry.relic.itemId);
    return relicSearchText(entry.relic, meta).indexOf(needle) !== -1;
  }

  // 槽位层面的提示（只在一侧存在 / 两侧角色名不同）。文案与 macOS 端
  // SaveCompareCharacter.presenceNote 逐字一致。
  function comparePresenceNote(entry) {
    if (!entry.inBase) return "该槽位只在对比存档中存在";
    if (!entry.inOther) return "该槽位只在当前存档中存在";
    if (entry.baseName && entry.otherName && entry.baseName !== entry.otherName) {
      return "两份存档的同一槽位角色名不同：" + entry.baseName + " → " + entry.otherName;
    }
    return "";
  }

  function compareCharacterHead(entry) {
    var name = entry.baseName || entry.otherName || "未命名";
    var note = comparePresenceNote(entry);
    var counts = pill("当前 " + entry.base, "purple") + pill("对比 " + entry.other, "blue");
    counts += entry.unreadable
      ? pill("无法对比", "amber")
      : pill("新增 " + entry.addedCount, entry.addedCount ? "green" : "gray") +
        pill("减少 " + entry.removedCount, entry.removedCount ? "red" : "gray");
    return "<header class='save-diff-character-head'><strong>槽位 " + (entry.slot + 1) + " · " + esc(name) + "</strong>" +
      (note ? "<span class='save-diff-note'>" + esc(note) + "</span>" : "") +
      "<span class='save-diff-counts'>" + counts + "</span></header>";
  }

  // 返回该角色的差异区块；没有可显示的行时返回空串。ctx 带着跨角色累计的渲染
  // 预算与筛选条件。
  function compareCharacterBlock(entry, ctx) {
    var section = function (body) {
      return "<section class='save-diff-character' data-testid='save-diff-character'>" +
        compareCharacterHead(entry) + body + "</section>";
    };

    // 解析失败的槽位 relics 是空数组，拿去比会把「读不出来」报成「被删光」。
    if (entry.unreadable) {
      var reasons = [];
      if (entry.baseParseError) reasons.push("当前存档：" + entry.baseParseError);
      if (entry.otherParseError) reasons.push("对比存档：" + entry.otherParseError);
      return section("<div class='issue-row issue-row--warning' data-testid='save-diff-unreadable'>" +
        "<span class='issue-symbol'>△</span><div><strong>该槽位解析失败，无法对比</strong><p>" +
        esc(reasons.join("；")) + "</p></div></div>");
    }
    // 只改了角色名（或槽位只在一侧存在但两侧都没遗物）的槽位：遗物没变，
    // 但提示不能被吞掉——与 macOS 端一致。
    if (!entry.changed) {
      return comparePresenceNote(entry)
        ? section("<p class='save-diff-same'>该角色的遗物与当前存档一致。</p>")
        : "";
    }

    var added = ctx.direction === "removed" ? [] : entry.added.filter(function (item) {
      return compareEntryMatches(item, ctx.needle);
    });
    var removed = ctx.direction === "added" ? [] : entry.removed.filter(function (item) {
      return compareEntryMatches(item, ctx.needle);
    });
    if (!added.length && !removed.length) return "";

    var renderList = function (entries, direction, title, audits) {
      if (!entries.length) return "";
      var shown = entries.slice(0, Math.max(0, ctx.left));
      ctx.left -= shown.length;
      ctx.skipped += entries.length - shown.length;
      if (!shown.length) return "";
      var total = entries.reduce(function (sum, item) { return sum + item.count; }, 0);
      return "<div class='save-diff-group'><h4>" + title + "（" + total + "）</h4>" +
        shown.map(function (item) { return compareRelicRow(item, direction, audits); }).join("") + "</div>";
    };

    var baseAudits = state.save.audits[entry.baseIndex] || [];
    var otherAudits = (state.save.compare.audits || [])[entry.otherIndex] || [];
    var body = renderList(added, "added", "对比存档中新增", otherAudits) +
      renderList(removed, "removed", "对比存档中减少", baseAudits);
    return body ? section(body) : "";
  }

  function compareToolsHtml() {
    var buttons = COMPARE_DIRECTIONS.map(function (item) {
      var active = item.key === state.save.compareDirection;
      return "<button type='button' class='segment-button" + (active ? " is-active" : "") +
        "' data-diff-direction='" + item.key + "' data-testid='save-diff-direction-" + item.key +
        "' role='radio' aria-checked='" + active + "'>" + item.label + "</button>";
    }).join("");
    return "<div class='save-diff-tools'>" +
      "<div class='segmented-control' role='radiogroup' aria-label='差异方向'>" + buttons + "</div>" +
      "<label class='search-field save-diff-search-field'><span aria-hidden='true'>⌕</span>" +
      "<input type='search' placeholder='搜索遗物名、词条名或 ID' autocomplete='off' value='" +
      esc(state.save.compareQuery) + "' data-testid='save-diff-search'></label></div>";
  }

  // 只重绘差异列表；工具条（搜索框）保持原样，输入时不会掉焦点。
  function renderSaveCompareList() {
    var body = test("save-diff-body");
    var compare = state.save.compare;
    if (!body || !compare) return;
    var totals = compare.diff.totals;
    var ctx = {
      needle: Core.foldForSearch(state.save.compareQuery || ""),
      direction: state.save.compareDirection,
      left: COMPARE_ROW_BUDGET,
      skipped: 0
    };
    var blocks = compare.diff.characters.map(function (entry) {
      return compareCharacterBlock(entry, ctx);
    }).filter(Boolean).join("");

    if (!blocks) {
      body.innerHTML = "<p class='save-diff-same' data-testid='save-diff-empty'>" +
        (totals.added || totals.removed ? "没有符合筛选条件的差异" : "两份存档的遗物完全一致") + "</p>";
      return;
    }
    body.innerHTML = "<div class='save-diff-list'>" + blocks + "</div>" +
      (ctx.skipped > 0
        ? "<p class='save-diff-more' data-testid='save-diff-more'>另有 " + ctx.skipped +
          " 条差异未显示（单次最多渲染 " + COMPARE_ROW_BUDGET + " 行），请用搜索或方向筛选缩小范围。</p>"
        : "");
  }

  function renderSaveCompare() {
    var container = test("save-compare");
    var compare = state.save.compare;
    if (!compare || !state.save.payload) { container.hidden = true; container.innerHTML = ""; return; }
    container.hidden = false;
    var totals = compare.diff.totals;
    container.innerHTML = "<article class='card save-diff-card'>" +
      "<div class='section-heading'><div class='section-icon'>⇄</div>" +
      "<div><h2>存档对比</h2><p>当前：" + esc(state.save.payload.fileName || "存档") +
      "　对比：" + esc(compare.payload.fileName || "存档") + "</p></div>" +
      "<button class='button button--ghost' type='button' data-action='clear-compare' data-testid='clear-compare-button'>退出对比</button></div>" +
      "<div class='save-diff-totals'>" +
      pill("当前共 " + totals.base + " 件", "purple") +
      pill("对比共 " + totals.other + " 件", "blue") +
      pill("新增 " + totals.added + " 件", totals.added ? "green" : "gray") +
      pill("减少 " + totals.removed + " 件", totals.removed ? "red" : "gray") +
      pill("有差异角色 " + totals.changedCharacters, totals.changedCharacters ? "amber" : "gray") +
      (totals.unreadableCharacters
        ? pill("无法对比槽位 " + totals.unreadableCharacters, "amber")
        : "") +
      "</div>" +
      compareToolsHtml() +
      "<div class='save-diff-body' data-testid='save-diff-body'></div>" +
      "<p class='data-hint'>对比以「遗物 ID + 三条正面词条 + 三条诅咒」为一件遗物的身份（都按存档里的顺序，" +
      "顺序本身会影响合法性判定），按角色槽位分别统计；任一边解析失败的槽位只提示、不计入增减。" +
      "新增/减少遗物的合法性状态由当前词条库判定，取自该遗物所在存档的整体检查结果。</p>" +
      "</article>";
    renderSaveCompareList();
  }

  function setCompareDirection(key) {
    if (!state.save.compare || state.save.compareDirection === key) return;
    state.save.compareDirection = key;
    // 只改按钮状态，不重建工具条，免得搜索框掉焦点。
    $$("[data-diff-direction]").forEach(function (button) {
      var active = button.dataset.diffDirection === key;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-checked", String(active));
    });
    renderSaveCompareList();
  }

  async function compareSave() {
    if (!state.save.payload) return;
    if (browserPreview) { setSaveMessage("存档对比仅在桌面应用中可用"); showToast("此功能在桌面应用中可用"); return; }
    if (!Diff) { showToast("对比模块未载入", true); return; }
    setSaveBusy(true);
    try {
      await ensureRelicIndex();
      var payload = await api.openSaveFile();
      if (!payload) return;
      state.save.compareQuery = "";
      state.save.compareDirection = "all";
      state.save.compare = {
        payload: payload,
        audits: auditCharacters(payload),
        diff: Diff.diffPayloads(state.save.payload, payload)
      };
      renderSaveCompare();
      var totals = state.save.compare.diff.totals;
      setSaveMessage("已对比 " + (payload.fileName || "存档") + "：新增 " + totals.added +
        " 件 · 减少 " + totals.removed + " 件" +
        (totals.unreadableCharacters ? " · " + totals.unreadableCharacters + " 个槽位解析失败无法对比" : ""));
    } catch (error) {
      setSaveMessage("对比失败：" + error.message, true);
      showToast("对比失败：" + error.message, true);
    } finally {
      setSaveBusy(false);
    }
  }

  function clearCompare() {
    state.save.compare = null;
    state.save.compareQuery = "";
    state.save.compareDirection = "all";
    renderSaveCompare();
  }

  document.addEventListener("click", function (event) {
    var nav = event.target.closest("[data-page-target]");
    if (nav) {
      state.page = nav.dataset.pageTarget;
      renderNav();
      if (state.page === "save") {
        ensureRelicIndex().catch(function (error) { setSaveMessage("遗物数据载入失败：" + error.message, true); });
      }
      activatePage(state.page);
      return;
    }
    var mode = event.target.closest("[data-mode]");
    if (mode) { setMode(mode.dataset.mode); return; }
    var saveFilter = event.target.closest("[data-save-filter]");
    if (saveFilter) { state.save.filter = saveFilter.dataset.saveFilter; renderSaveRelics(); return; }
    var locateRow = event.target.closest("[data-locate-index]");
    if (locateRow) { openLocatedSave(Number(locateRow.dataset.locateIndex)); return; }
    var explain = event.target.closest("[data-explain-key]");
    if (explain) {
      var explainedKey = explain.dataset.explainKey;
      var position = state.save.explained.indexOf(explainedKey);
      if (position === -1) state.save.explained.push(explainedKey);
      else state.save.explained.splice(position, 1);
      renderSaveRelics();
      return;
    }
    var diffDirection = event.target.closest("[data-diff-direction]");
    if (diffDirection) { setCompareDirection(diffDirection.dataset.diffDirection); return; }
    var clearSlot = event.target.closest("[data-clear-slot]");
    if (clearSlot) { event.stopPropagation(); state.selected[Number(clearSlot.dataset.clearSlot)] = null; state.result = null; renderSlots(); renderResult(); return; }
    var slot = event.target.closest("[data-slot]");
    if (slot) { openPicker(Number(slot.dataset.slot)); return; }
    var popular = event.target.closest("[data-popular-id]");
    if (popular) { fillNext(findAffix(popular.dataset.popularId)); return; }
    var pickerRow = event.target.closest("[data-picker-id]");
    if (pickerRow) { chooseAffix(findAffix(pickerRow.dataset.pickerId), state.pickerSlot); test("picker-dialog").close(); return; }
    var action = event.target.closest("[data-action]");
    if (!action) return;
    switch (action.dataset.action) {
      case "check": performCheck(); break;
      case "random": performRandom(); break;
      case "clear": state.selected = [null, null, null]; state.result = null; renderSlots(); renderResult(); break;
      case "reorder": state.selected = Core.canonicalOrder(selectedAffixes()); state.result = Core.check(state.selected, state.mode); renderSlots(); renderResult(); break;
      case "close-picker": test("picker-dialog").close(); break;
      case "import": importCatalog(); break;
      case "export": exportCatalog(); break;
      case "reset": browserPreview ? resetCatalog() : test("confirm-dialog").showModal(); break;
      case "open-save": openSave(); break;
      case "locate-save": locateSaves(); break;
      case "export-save-report": exportSaveReport("text"); break;
      case "export-save-csv": exportSaveReport("csv"); break;
      case "compare-save": compareSave(); break;
      case "clear-compare": clearCompare(); break;
    }
  });

  bindGlobalDropGuard();
  bindSaveDropZone();

  test("save-character").addEventListener("change", function (event) {
    state.save.character = Number(event.target.value);
    renderSaveRelics();
  });

  test("library-search").addEventListener("input", function (event) { state.libraryQuery = event.target.value; renderLibrary(); });
  test("library-category").addEventListener("change", function (event) { state.libraryCategory = event.target.value; renderLibrary(); });
  test("library-mode").addEventListener("change", function (event) { setMode(event.target.value); });
  test("library-eligible-toggle").addEventListener("change", function (event) { state.libraryOnlyEligible = event.target.checked; renderLibrary(); });
  test("picker-search").addEventListener("input", function (event) { state.pickerQuery = event.target.value; renderPicker(); });
  test("save-search").addEventListener("input", function (event) { state.save.query = event.target.value; renderSaveRelics(); });
  // 对比卡是动态渲染的，搜索框只能用委托监听；只重绘列表，输入时不掉焦点。
  document.addEventListener("input", function (event) {
    var target = event.target;
    if (!target || target.nodeType !== 1 || !target.matches("[data-testid='save-diff-search']")) return;
    state.save.compareQuery = target.value;
    renderSaveCompareList();
  });
  test("picker-category").addEventListener("change", function (event) { state.pickerCategory = event.target.value; renderPicker(); });
  test("picker-show-unavailable").addEventListener("change", function (event) { state.pickerShowUnavailable = event.target.checked; renderPicker(); });
  test("confirm-dialog").addEventListener("close", function (event) { if (event.target.returnValue === "confirm") resetCatalog(); });
  test("picker-dialog").addEventListener("click", function (event) { if (event.target === event.currentTarget) event.currentTarget.close(); });
  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && test("picker-dialog").open) test("picker-dialog").close();
    if (event.key === "Enter" && state.page === "checker" && !test("picker-dialog").open && !test("confirm-dialog").open && event.target.tagName !== "BUTTON") performCheck();
  });

  api.loadCatalog().then(function (payload) {
    installCatalog(asCatalog(payload), payload && payload.origin ? payload.origin : "built-in");
    test("loading-overlay").hidden = true;
  }).catch(function (error) {
    var loading = test("loading-overlay");
    loading.innerHTML = "<span>词条库载入失败：" + esc(error.message) + "</span>";
    showToast("词条库载入失败", true);
  });
})();
