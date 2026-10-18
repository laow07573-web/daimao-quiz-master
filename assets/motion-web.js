/* ============================================================================
   猫卷官网 · motion-web 行为层
   ----------------------------------------------------------------------------
   与 assets/motion-web.css 配套。刻意保持很小：只做三件 CSS 做不到的事，
   不接管 studio.js 已有的交互（暂停按钮、模式切换、界面切换都还在它那里），
   不写 requestAnimationFrame，也不给任何元素持续写 transform
   —— 一个属性只允许一个驱动，否则会和 CSS 过渡打架。
   ========================================================================= */
(() => {
  'use strict';

  const root   = document.documentElement;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');

  /* 暂停开关的状态在 studio.js 的闭包里，但它把 .paused 打在 <html> 上，
     所以这里读 class 就能和它保持一致，不必改动那个文件。 */
  const isPaused = () => root.classList.contains('paused') || reduce.matches;

  /* ── 1. 产品区的界面按钮没有出现在 studio.js 的观察名单里，补上 ─────────
     门控条件与 studio.js 一致：暂停或系统减弱动态时，不加 reveal-on。
     这样元素保持普通 CSS 的终态（本来就是可见的），不会留下空白。 */
  const extraTargets = document.querySelectorAll('.screen-buttons');
  if (extraTargets.length) {
    if ('IntersectionObserver' in window) {
      const io = new IntersectionObserver(entries => {
        entries.forEach(e => {
          if (!e.isIntersecting) return;
          if (!isPaused()) e.target.classList.add('reveal-on');
          io.unobserve(e.target);
        });
      }, { threshold: 0.1 });
      extraTargets.forEach(el => io.observe(el));
    } else {
      extraTargets.forEach(el => el.classList.add('reveal-on'));
    }
  }

  /* ── 2. 预先加载三张界面图 ────────────────────────────────────────────────
     studio.js 切换界面时直接改 src；新图解码完成前那块区域是空的，会闪一下
     （三张图合计约 250KB，整站最贵的一次交互）。在这里提前拉进缓存之后，
     切换就变成即时命中，不再有空档。 */
  ['start', 'errorbook', 'stats'].forEach(name => {
    const img = new Image();
    img.decoding = 'async';
    img.src = `assets/shots/${name}.png`;
  });

  /* ── 3. 导航当前位置 ──────────────────────────────────────────────────────
     用 aria-current 而不是自定义 class：读屏软件也会播报"当前页"。
     只在穿过视口中部的那个区块上标记，避免多个同时点亮。 */
  const links    = [...document.querySelectorAll('nav > a:not(.nav-get)')]
                     .filter(a => (a.getAttribute('href') || '').startsWith('#'));
  const sections = links
    .map(a => document.getElementById(a.getAttribute('href').slice(1)))
    .filter(Boolean);

  if (links.length && sections.length && 'IntersectionObserver' in window) {
    const spy = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (!e.isIntersecting) return;
        links.forEach(a => {
          if (a.getAttribute('href') === `#${e.target.id}`) {
            a.setAttribute('aria-current', 'true');
          } else {
            a.removeAttribute('aria-current');
          }
        });
      });
    }, { rootMargin: '-45% 0px -50% 0px' });
    sections.forEach(s => spy.observe(s));
  }
})();
