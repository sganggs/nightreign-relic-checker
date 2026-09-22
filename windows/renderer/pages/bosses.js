// 首领数据页（占位实现）。页面模块契约见 renderer/pages/README.md。
// 本文件由「首领数据」功能开发者独占：只改这里与 pages/bosses.css。
(function () {
  "use strict";

  var PAGE_KEY = "bosses";
  var DATA_NAME = "bosses"; // ctx.getGameData("bosses") → resources/bosses.json

  // 页面自身的状态全部放在模块闭包里，不写入 app.js 的 state。
  var dom = null;

  function template(helpers) {
    return "" +
      "<div class='page-content bosses-content'>" +
      "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>首领数据</h1><p>《黑夜君临》首领的属性、弱点与阶段数据</p></div>" +
      "</header>" +
      "<article class='card page-placeholder-card' data-testid='bosses-card'>" +
      "<div class='section-heading'>" +
      "<div class='section-icon'>✸</div>" +
      "<div><h2>功能开发中</h2><p>页面脚手架已就绪，业务逻辑请在 renderer/pages/bosses.js 内实现</p></div>" +
      "</div>" +
      "<div class='page-status-row'>" +
      helpers.pill("页面 " + PAGE_KEY, "purple") +
      "<span class='page-data-status' data-testid='bosses-data-status'>正在检查数据文件…</span>" +
      "</div>" +
      "<p class='data-hint'>数据文件：resources/" + DATA_NAME + ".json，通过 ctx.getGameData(\"" + DATA_NAME + "\") 懒加载；" +
      "文件缺失或仍是占位内容时会 resolve null，页面据此降级显示「数据未内置」。</p>" +
      "</article>" +
      "</div>";
  }

  // 演示 getGameData 的用法：不解析任何业务结构，只判断有没有数据。
  function describe(data, helpers) {
    if (!data) {
      return helpers.pill("数据未内置", "amber") +
        "<span>尚未提供 resources/" + DATA_NAME + ".json，运行 scripts/sync-data.sh 同步后重试</span>";
    }
    var shape = Array.isArray(data)
      ? "数组 · " + data.length + " 项"
      : "对象 · " + Object.keys(data).length + " 个顶层字段";
    return helpers.pill("数据已内置", "green") + "<span>" + helpers.escapeHtml(shape) + "</span>";
  }

  function refresh(ctx) {
    if (!dom) return;
    var status = dom.querySelector("[data-testid='bosses-data-status']");
    if (!status) return;
    ctx.getGameData(DATA_NAME).then(function (data) {
      status.innerHTML = describe(data, ctx.helpers);
    });
  }

  window.NightreignPages = window.NightreignPages || {};
  window.NightreignPages[PAGE_KEY] = {
    // 首次切换到本页时调用一次；mount 是 [data-mount="bosses"] 元素。
    init: function (mount, ctx) {
      dom = mount;
      mount.innerHTML = template(ctx.helpers);
      refresh(ctx);
    },
    // 词条库 / 存档数据变化后调用（可选实现）。
    refresh: refresh
  };
})();
