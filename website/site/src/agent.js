'use strict';
/* Property Agent page: language switch (English / Hindi / Telugu) + scroll reveal.
   Text lives in src/i18n/agent-page.json and is embedded in the page at build time. */
(() => {
  const dataEl = document.getElementById('tk-i18n');
  const dict = dataEl ? JSON.parse(dataEl.textContent) : null;
  if (dict) {
  const KEY = 'tk-lang';
  const pick = () => {
    try { const saved = localStorage.getItem(KEY); if (dict[saved]) return saved; } catch (e) {}
    const nav = (navigator.language || 'en').slice(0, 2);
    return dict[nav] ? nav : 'en';
  };
  function apply(lang) {
    const t = dict[lang] || dict.en;
    document.documentElement.lang = lang;
    for (const el of document.querySelectorAll('[data-i18n]')) {
      const v = t[el.dataset.i18n];
      if (v != null) el.textContent = v;
    }
    for (const b of document.querySelectorAll('[data-lang]')) b.setAttribute('aria-pressed', String(b.dataset.lang === lang));
    try { localStorage.setItem(KEY, lang); } catch (e) {}
  }
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-lang]');
    if (b) apply(b.dataset.lang);
  });
  const start = pick();
  if (start !== 'en') apply(start);
  }

  // Reveal sections as they scroll into view
  if (!('IntersectionObserver' in window) || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const items = document.querySelectorAll('.tka-sec h2, .tka-cmp, .tka-steps li, .tka-visual-col, .tka-tool, .tka-pace, .tka-final h2, .tkb-tile, .tkb-role, .tkb-flow li, .tkb-ps-col, .tkb-values-grid > div');
  const io = new IntersectionObserver(entries => {
    for (const en of entries) if (en.isIntersecting) { en.target.classList.add('tka-in'); io.unobserve(en.target); }
  }, { threshold: 0.15, rootMargin: '0px 0px -40px 0px' });
  items.forEach((el, i) => { el.classList.add('tka-reveal'); el.style.transitionDelay = (i % 4) * 70 + 'ms'; io.observe(el); });
})();
