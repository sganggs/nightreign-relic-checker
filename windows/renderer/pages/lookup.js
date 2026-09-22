// 词条反查页（占位实现）。页面模块契约见 renderer/pages/README.md。
// 本文件由「词条反查」功能开发者独占：只改这里与 pages/lookup.css。
// 本页只使用现有数据：ctx.catalog（词条库）与 ctx.relicData（遗物物品表）。
(function () {
  "use strict";

  var PAGE_KEY = "lookup";

  // 页面自身的状态全部放在模块闭包里，不写入 app.js 的 state。
  var dom = null;

  function template(helpers) {
    return "" +
      "<div class='page-content lookup-content'>" +
      "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>词条反查</h1><p>由词条反查可能出现它的遗物与出货池</p></div>" +
      "</header>" +
      "<article class='card page-placeholder-card' data-testid='lookup-card'>" +
      "<div class='section-heading'>" +
      "<div class='section-icon'>⌖</div>" +
      "<div><h2>功能开发中</h2><p>页面脚手架已就绪，业务逻辑请在 renderer/pages/lookup.js 内实现</p></div>" +
      "</div>" +
      "<div class='page-status-row'>" +
      helpers.pill("页面 " + PAGE_KEY, "purple") +
      "<span class='page-data-status' data-testid='lookup-data-status'>正在检查数据…</span>" +
      "</div>" +
      "<p class='data-hint'>本页不需要新增数据文件：词条来自 ctx.catalog.affixes，遗物物品表来自 ctx.relicData" +
      "（存档检查首次载入后才有值，未载入时为 null；可用 ctx.Core.buildRelicIndex(ctx.catalog, ctx.relicData) 建索引）。</p>" +
      "</article>" +
      "</div>";
  }

  function describe(ctx) {
    var helpers = ctx.helpers;
    var parts = [];
    if (ctx.catalog && ctx.catalog.affixes) {
      parts.push(helpers.pill("词条库已就绪", "green") +
        "<span>" + ctx.catalog.affixes.length + " 条记录</span>");
    } else {
      parts.push(helpers.pill("词条库未就绪", "amber") + "<span>ctx.catalog 为空</span>");
    }
    parts.push(ctx.relicData
      ? helpers.pill("遗物物品表已载入", "green")
      : helpers.pill("遗物物品表未载入", "purple"));
    return parts.join("");
  }

  function refresh(ctx) {
    if (!dom) return;
    var status = dom.querySelector("[data-testid='lookup-data-status']");
    if (!status) return;
    status.innerHTML = describe(ctx);
  }

  window.NightreignPages = window.NightreignPages || {};
  window.NightreignPages[PAGE_KEY] = {
    // 首次切换到本页时调用一次；mount 是 [data-mount="lookup"] 元素。
    init: function (mount, ctx) {
      dom = mount;
      mount.innerHTML = template(ctx.helpers);
      refresh(ctx);
    },
    // 词条库 / 存档数据变化后调用（可选实现）。
    refresh: refresh
  };
})();
