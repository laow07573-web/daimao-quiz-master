/* 猫卷官网 · 瑞士风格版脚本
   只做三件事：版本号回填、入场、学习模式切换。
   没有任何滚动劫持、视差或循环动画。 */
(function () {
  'use strict';

  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var cfg = window.MAOJUAN || {};
  var ver = cfg.version || '1.29.0';

  /* ---- 版本号：页面上所有 data-ver 从配置块回填 ---- */
  var spans = document.querySelectorAll('[data-ver]');
  for (var i = 0; i < spans.length; i++) {
    var mode = spans[i].getAttribute('data-ver');
    var text = mode === 'v' ? 'v' + ver : mode === 'rev' ? 'REV ' + ver : ver;
    spans[i].textContent = text;
  }

  /* ---- 入场：每条元素只播一次 ---- */
  var rises = document.querySelectorAll('[data-rise]');
  function show(el) {
    el.classList.add('in');
  }

  if (reduced || !('IntersectionObserver' in window)) {
    for (var j = 0; j < rises.length; j++) show(rises[j]);
  } else {
    var io = new IntersectionObserver(function (entries) {
      for (var k = 0; k < entries.length; k++) {
        if (!entries[k].isIntersecting) continue;
        var el = entries[k].target;
        var sibs = el.parentNode ? el.parentNode.children : null;
        var order = sibs ? Array.prototype.indexOf.call(sibs, el) : 0;
        el.style.transitionDelay = Math.min(order, 4) * 45 + 'ms';
        show(el);
        io.unobserve(el);
      }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

    for (var m = 0; m < rises.length; m++) io.observe(rises[m]);
  }

  /* ---- 学习模式切换（真按钮，键盘可达） ---- */
  var modeBtns = document.querySelectorAll('[data-mode]');
  var modeCopy = document.getElementById('mode-copy');
  var MODE_TEXT = {
    '刷题': '一题一屏，答完再看讲解。',
    '练习': '答完即时核对，边做边理解。',
    '背题': '先记住题眼，再回到题里验证。'
  };

  for (var n = 0; n < modeBtns.length; n++) {
    modeBtns[n].addEventListener('click', function () {
      for (var p = 0; p < modeBtns.length; p++) {
        modeBtns[p].setAttribute('aria-pressed', String(modeBtns[p] === this));
      }
      if (modeCopy) modeCopy.textContent = MODE_TEXT[this.textContent.trim()] || '';
    });
  }
})();
