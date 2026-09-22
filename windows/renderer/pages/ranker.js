// 增伤排名页（占位实现）。页面模块契约见 renderer/pages/README.md。
// 本文件由「增伤排名」功能开发者独占：只改这里与 pages/ranker.css。
(function () {
  "use strict";

  var PAGE_KEY = "ranker";
  var DATA_NAMES = ["skills", "buffs"]; // → resources/skills.json、resources/buffs.json

  // 页面自身的状态全部放在模块闭包里，不写入 app.js 的 state。
  var dom = null;

  function template(helpers) {
    return "" +
      "<div class='page-content ranker-content'>" +
      "<header class='title-block page-title'>" +
      "<div class='logo-mark logo-mark--medium' aria-hidden='true'><i></i><i></i><i></i><span>✓</span></div>" +
      "<div><h1>增伤排名</h1><p>按技能与增益数据排列词条的增伤收益</p></div>" +
      "</header>" +
      "<article class='card page-placeholder-card' data-testid='ranker-card'>" +
      "<div class='section-heading'>" +
      "<div class='section-icon'>⇗</div>" +
      "<div><h2>功能开发中</h2><p>页面脚手架已就绪，业务逻辑请在 renderer/pages/ranker.js 内实现</p></div>" +
      "</div>" +
      "<div class='page-status-row'>" +
      helpers.pill("页面 " + PAGE_KEY, "purple") +
      "<span class='page-data-status' data-testid='ranker-data-status'>正在检查数据文件…</span>" +
      "</div>" +
      "<p class='data-hint'>数据文件：resources/skills.json 与 resources/buffs.json，通过 ctx.getGameData(\"skills\")、" +
      "ctx.getGameData(\"buffs\") 懒加载；任一文件缺失或仍是占位内容时 resolve null，页面据此降级显示「数据未内置」。</p>" +
      "</article>" +
      "</div>";
  }

  // 演示 getGameData 的用法：不解析任何业务结构，只判断有没有数据。
  function describeOne(name, data, helpers) {
    if (!data) return helpers.pill(name + "：未内置", "amber");
    var shape = Array.isArray(data)
      ? data.length + " 项"
      : Object.keys(data).length + " 个字段";
    return helpers.pill(name + "：已内置 " + shape, "green");
  }

  function refresh(ctx) {
    if (!dom) return;
    var status = dom.querySelector("[data-testid='ranker-data-status']");
    if (!status) return;
    Promise.all(DATA_NAMES.map(function (name) { return ctx.getGameData(name); })).then(function (results) {
      var html = results.map(function (data, index) {
        return describeOne(DATA_NAMES[index], data, ctx.helpers);
      }).join("");
      if (results.every(Boolean)) {
        html += "<span>" + ctx.helpers.escapeHtml("两份数据均已就绪") + "</span>";
      } else {
        html += "<span>运行 scripts/sync-data.sh 同步后重试</span>";
      }
      status.innerHTML = html;
    });
  }

  window.NightreignPages = window.NightreignPages || {};
  window.NightreignPages[PAGE_KEY] = {
    // 首次切换到本页时调用一次；mount 是 [data-mount="ranker"] 元素。
    init: function (mount, ctx) {
      dom = mount;
      mount.innerHTML = template(ctx.helpers);
      refresh(ctx);
    },
    // 词条库 / 存档数据变化后调用（可选实现）。
    refresh: refresh
  };
})();
