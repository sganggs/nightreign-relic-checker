(function () {
  "use strict";

  var Core = window.RelicCore;
  if (!Core) {
    document.querySelector("[data-testid='loading-overlay']").textContent = "规则模块载入失败";
    return;
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
    exportCatalog: function () { return Promise.resolve({ canceled: true }); }
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
    busy: false
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
    renderAll();
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

  document.addEventListener("click", function (event) {
    var nav = event.target.closest("[data-page-target]");
    if (nav) { state.page = nav.dataset.pageTarget; renderNav(); return; }
    var mode = event.target.closest("[data-mode]");
    if (mode) { setMode(mode.dataset.mode); return; }
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
    }
  });

  test("library-search").addEventListener("input", function (event) { state.libraryQuery = event.target.value; renderLibrary(); });
  test("library-category").addEventListener("change", function (event) { state.libraryCategory = event.target.value; renderLibrary(); });
  test("library-mode").addEventListener("change", function (event) { setMode(event.target.value); });
  test("library-eligible-toggle").addEventListener("change", function (event) { state.libraryOnlyEligible = event.target.checked; renderLibrary(); });
  test("picker-search").addEventListener("input", function (event) { state.pickerQuery = event.target.value; renderPicker(); });
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
