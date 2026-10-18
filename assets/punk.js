/* 猫卷官网 · 交互脚本
   只做五件事：版本号回填、滚动进度、入场、学习模式切换、减少动态时的兜底。
   不劫持滚动，不引入依赖，失败时页面内容照常可读。 */
(function () {
  "use strict";

  var root = document.documentElement;
  var reduce = window.matchMedia
    ? window.matchMedia("(prefers-reduced-motion: reduce)").matches
    : false;

  /* ---------- 0. 版本号 ----------
     发布脚本只改 window.MAOJUAN.version，页面里所有版本文字都从这里回填，
     避免发版后各处版本号对不上。 */
  var cfg = window.MAOJUAN || {};
  if (cfg.version) {
    Array.prototype.forEach.call(document.querySelectorAll("[data-ver]"), function (el) {
      var mode = el.getAttribute("data-ver");
      var prefix = mode === "bare" ? "" : mode === "rev" ? "REV " : "v";
      el.textContent = prefix + cfg.version;
    });
  }

  /* ---------- 1. 顶栏进度条 ---------- */
  var progress = document.querySelector(".mast-progress i");
  var ticking = false;

  function paintProgress() {
    ticking = false;
    if (!progress) return;
    var max = root.scrollHeight - window.innerHeight;
    var ratio = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
    progress.style.transform = "scaleX(" + ratio.toFixed(4) + ")";
  }

  function onScroll() {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(paintProgress);
  }

  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll, { passive: true });
  paintProgress();

  /* ---------- 2. 入场 ---------- */
  var items = Array.prototype.slice.call(document.querySelectorAll("[data-rise]"));

  function revealAll() {
    items.forEach(function (el) { el.classList.add("in"); });
  }

  if (reduce || !("IntersectionObserver" in window)) {
    revealAll();
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("in");
        io.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -6% 0px", threshold: 0.06 });

    items.forEach(function (el) {
      /* 横向滑动容器里的卡片不在可视区也会被判为不可见，
         直接显示，避免滑到一半还是空的。 */
      if (el.closest(".plates")) {
        el.classList.add("in");
        return;
      }
      var parent = el.parentElement;
      if (parent) {
        var group = Array.prototype.filter.call(parent.children, function (node) {
          return node.hasAttribute && node.hasAttribute("data-rise");
        });
        var index = group.indexOf(el);
        if (index > 0) {
          el.style.transitionDelay = Math.min(index, 6) * 70 + "ms";
        }
      }
      io.observe(el);
    });
  }

  /* ---------- 3. 学习模式示意 ---------- */
  var modes = Array.prototype.slice.call(document.querySelectorAll(".mode"));
  var modeCopy = document.getElementById("mode-copy");
  var modeText = {
    "刷题": "一题一屏，答完再看讲解。",
    "练习": "慢一点，把每个选项都弄明白。",
    "背题": "先记住题眼，再回到题里验证。"
  };

  modes.forEach(function (btn) {
    btn.addEventListener("click", function () {
      modes.forEach(function (other) {
        var on = other === btn;
        other.classList.toggle("is-on", on);
        other.setAttribute("aria-pressed", on ? "true" : "false");
      });
      if (modeCopy) {
        modeCopy.textContent = modeText[btn.dataset.mode] || "";
      }
    });
  });

  /* ---------- 4. 学习模式示意结束 ---------- */
})();
