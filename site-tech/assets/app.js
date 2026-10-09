/* ============================================================
   猫卷 MAOJUAN — site-tech 交互与动效
   动效基调「精密切入」：快、准、无弹跳；一律尊重 prefers-reduced-motion。
   零依赖：只用原生 JS + IntersectionObserver + SVG SMIL。
   ============================================================ */
(function () {
  'use strict';

  // 一次性读取系统动效偏好：减少分支处的重复查询
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ------------------------------------------------------------
     1. 终端打字机：逐字 28ms、行尾闪烁光标、三条命令循环、
        每条停留 1.2s 后清屏。纯 JS 定时链，不引任何库。
     ------------------------------------------------------------ */
  var TERMINAL = [
    [
      { prompt: true,  parts: [{ c: 'tcmd', t: 'maojuan import 2026真题.docx' }] },
      { prompt: false, parts: [{ c: '', t: '切题 … 132 题 · 插图 18 张随题保留' }] },
      { prompt: false, parts: [{ c: '', t: '入库 ' }, { c: 'tok', t: '✓' }, { c: '', t: ' — 输入 maojuan start 开刷' }] }
    ],
    [
      { prompt: true,  parts: [{ c: 'tcmd', t: 'maojuan import 习题集.pdf' }] },
      { prompt: false, parts: [{ c: '', t: '切题 … 87 题 · 插图 6 张随题保留' }] },
      { prompt: false, parts: [{ c: '', t: '入库 ' }, { c: 'tok', t: '✓' }] }
    ],
    [
      { prompt: true,  parts: [{ c: 'tcmd', t: 'maojuan import 题库.json' }] },
      { prompt: false, parts: [{ c: '', t: '直入库 … 240 题' }] },
      { prompt: false, parts: [{ c: 'tcmd', t: '开刷' }] }
    ]
  ];

  function sleep(ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  }

  function buildLine(line) {
    var el = document.createElement('div');
    el.className = 'tline';
    if (line.prompt) {
      var p = document.createElement('span');
      p.className = 'tp';
      p.textContent = '$ ';
      el.appendChild(p);
    }
    line.parts.forEach(function (part) {
      var s = document.createElement('span');
      if (part.c) s.className = part.c;
      s.textContent = part.t;
      el.appendChild(s);
    });
    return el;
  }

  function initTerminal() {
    var body = document.getElementById('term-body');
    if (!body) return;

    // 减少动效：三组命令一次性铺满，等价于终端回滚历史，信息不丢
    if (reduce) {
      TERMINAL.forEach(function (cycle) {
        cycle.forEach(function (line) { body.appendChild(buildLine(line)); });
      });
      return;
    }

    var cursor = document.createElement('span');
    cursor.className = 'tcur';

    (async function loop() {
      var i = 0;
      for (;;) {
        body.textContent = '';
        await sleep(320); // 清屏后留一口气，模拟真实终端节奏
        var cycle = TERMINAL[i];
        for (var li = 0; li < cycle.length; li++) {
          var line = cycle[li];
          var el = document.createElement('div');
          el.className = 'tline';
          if (line.prompt) {
            var pr = document.createElement('span');
            pr.className = 'tp';
            pr.textContent = '$ ';
            el.appendChild(pr);
          }
          body.appendChild(el);
          el.appendChild(cursor); // 光标恒在行尾，随打字前进
          for (var pi = 0; pi < line.parts.length; pi++) {
            var part = line.parts[pi];
            var s = document.createElement('span');
            if (part.c) s.className = part.c;
            el.insertBefore(s, cursor);
            var chars = Array.from(part.t);
            for (var ci = 0; ci < chars.length; ci++) {
              s.textContent += chars[ci];
              await sleep(28); // 逐字 28ms
            }
          }
          await sleep(140); // 行间呼吸
        }
        await sleep(1200); // 每条停留 1.2s 后清屏
        i = (i + 1) % TERMINAL.length;
      }
    })();
  }

  /* ------------------------------------------------------------
     2. 管线图：滚动进入 → 连线 dashoffset 画入 600ms →
        电蓝圆点沿路径 2.8s 线性循环（SVG animateMotion），
        圆点经过节点 → 节点描边脉冲 150ms。
        脉冲用 SMIL 的 beginEvent / repeatEvent 排程，
        保证每圈都与圆点位置同步，长跑不漂移。
     ------------------------------------------------------------ */
  function initPipeline() {
    var wrap = document.querySelector('.pl-wrap');
    var rail = document.querySelector('.pl-rail');
    var dot = document.querySelector('.pl-dot');
    var motion = document.getElementById('dot-move');
    var nodes = Array.prototype.slice.call(document.querySelectorAll('.pnode'));
    if (!wrap || !rail) return;

    // 减少动效：连线直接完整呈现，圆点与脉冲不上演
    if (reduce) {
      rail.classList.add('in');
      return;
    }

    function pulseOnce(g) {
      var r = g.querySelector('rect');
      if (!r) return;
      r.classList.add('pulse');
      setTimeout(function () { r.classList.remove('pulse'); }, 150);
    }

    // 一圈 2.8s：按圆点到达各节点的时间比例排脉冲
    function scheduleCycle() {
      nodes.forEach(function (g) {
        var t = (parseFloat(g.getAttribute('data-p')) || 0) * 2800;
        setTimeout(function () { pulseOnce(g); }, t);
      });
    }

    var io = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        obs.disconnect();
        rail.classList.add('in'); // 画入 600ms
        setTimeout(function () {
          if (!dot || !motion) return;
          dot.classList.add('on');
          motion.addEventListener('beginEvent', scheduleCycle);
          motion.addEventListener('repeatEvent', scheduleCycle);
          try { motion.beginElement(); } catch (e) { /* 不支持 SMIL 时静默降级为静态图 */ }
        }, 640); // 等画入完成再放行圆点（“随后”）
      });
    }, { threshold: 0.35 });
    io.observe(wrap);
  }

  /* ------------------------------------------------------------
     3. 数字 count-up：378 / 7 / 5 进入视口 700ms ease-out 滚动，
        等宽数字（tabular-nums）防抖。
     ------------------------------------------------------------ */
  function initCountUp() {
    var nums = Array.prototype.slice.call(document.querySelectorAll('.bignum[data-count]'));
    if (!nums.length) return;

    // 减少动效或无 JS 时 HTML 里就是终值，直接返回
    if (reduce) return;
    nums.forEach(function (n) { n.textContent = '0'; });

    function run(el) {
      var target = parseInt(el.getAttribute('data-count'), 10) || 0;
      var t0 = performance.now();
      var dur = 700;
      function step(now) {
        var t = Math.min(1, (now - t0) / dur);
        var e = 1 - Math.pow(1 - t, 3); // ease-out
        el.textContent = String(Math.round(target * e));
        if (t < 1) requestAnimationFrame(step);
        else el.textContent = String(target);
      }
      requestAnimationFrame(step);
    }

    var host = nums[0].closest('.bignums') || nums[0];
    var io = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        obs.disconnect();
        nums.forEach(run);
      });
    }, { threshold: 0.5 });
    io.observe(host);
  }

  /* ------------------------------------------------------------
     4. 一次性进视口揭示：opacity + translateY(12px)，200ms，交错 40ms。
        初始隐藏态只在 JS 可用时施加，脚本失效内容照常可读。
     ------------------------------------------------------------ */
  function initReveal() {
    var groups = Array.prototype.slice.call(document.querySelectorAll('[data-reveal]'));
    if (!groups.length || reduce) return;

    function itemsOf(c) {
      var sel = c.getAttribute('data-reveal-items');
      return sel
        ? Array.prototype.slice.call(c.querySelectorAll(sel))
        : Array.prototype.slice.call(c.children);
    }

    groups.forEach(function (c) {
      itemsOf(c).forEach(function (el, i) {
        el.classList.add('rv');
        el.style.setProperty('--rd', ((i % 8) * 40) + 'ms');
      });
    });

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        io.unobserve(en.target); // 一次性，回滚不重播
        itemsOf(en.target).forEach(function (el) { el.classList.add('in'); });
      });
    }, { threshold: 0.1, rootMargin: '0px 0px -8% 0px' });
    groups.forEach(function (c) { io.observe(c); });
  }

  /* ------------------------------------------------------------
     5. 区块标题下细线：scaleX 0→1 画入 400ms，transform-origin left。
     ------------------------------------------------------------ */
  function initRules() {
    var rules = Array.prototype.slice.call(document.querySelectorAll('.rule[data-rule]'));
    if (!rules.length) return;
    if (reduce) {
      rules.forEach(function (r) { r.classList.add('in'); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        io.unobserve(en.target);
        en.target.classList.add('in');
      });
    }, { threshold: 0.6 });
    rules.forEach(function (r) { io.observe(r); });
  }

  /* ------------------------------------------------------------
     6. 截图轻微视差：图以 0.92 倍速随滚动 → 相对位移 8%，
        钳制 ±8px。CSS 变量 --py + rAF 节流，克制优先。
     ------------------------------------------------------------ */
  function initParallax() {
    if (reduce) return;
    var imgs = Array.prototype.slice.call(document.querySelectorAll('.shot-clip img'));
    if (!imgs.length) return;

    var ticking = false;
    function update() {
      var vc = window.innerHeight / 2;
      imgs.forEach(function (img) {
        var r = img.getBoundingClientRect();
        var c = r.top + r.height / 2;
        var py = (vc - c) * 0.08;
        if (py > 8) py = 8;
        if (py < -8) py = -8;
        img.style.setProperty('--py', py.toFixed(2) + 'px');
      });
      ticking = false;
    }
    function onScroll() {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(update);
    }
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    update();
  }

  /* ------------------------------------------------------------
     7. 顶栏锚点选中态（电蓝 = 当前区块）
     ------------------------------------------------------------ */
  function initSpy() {
    var links = Array.prototype.slice.call(document.querySelectorAll('.nav a'));
    if (!links.length) return;
    var pairs = [];
    links.forEach(function (a) {
      var sec = document.querySelector(a.getAttribute('href'));
      if (sec) pairs.push({ sec: sec, a: a });
    });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        links.forEach(function (l) { l.classList.remove('is-active'); });
        pairs.forEach(function (p) {
          if (p.sec === en.target) p.a.classList.add('is-active');
        });
      });
    }, { rootMargin: '-30% 0px -60% 0px', threshold: 0 });
    pairs.forEach(function (p) { io.observe(p.sec); });
  }

  function init() {
    initTerminal();
    initPipeline();
    initCountUp();
    initReveal();
    initRules();
    initParallax();
    initSpy();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
