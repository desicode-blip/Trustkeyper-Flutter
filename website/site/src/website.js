'use strict';

if (location.hash.startsWith('#/')) location.replace(`https://trustkeyper.web.app/${location.hash}`);

for (const toggle of document.querySelectorAll('[data-faq-toggle]')) {
  toggle.addEventListener('click', () => {
    const expanded = toggle.getAttribute('aria-expanded') === 'true';
    for (const other of document.querySelectorAll('[data-faq-toggle]')) {
      const open = other === toggle && !expanded;
      other.setAttribute('aria-expanded', String(open));
      document.getElementById(other.getAttribute('aria-controls')).hidden = !open;
      other.querySelector('svg')?.classList.toggle('rotate-180', open);
    }
  });
}

const menuToggle = document.querySelector('[data-menu-toggle]');
const mobileMenu = document.getElementById('mobile-menu');
function closeWebsiteMenu() {
  if (!menuToggle || !mobileMenu) return;
  mobileMenu.hidden = true;
  menuToggle.setAttribute('aria-expanded', 'false');
  menuToggle.setAttribute('aria-label', 'Open menu');
}
menuToggle?.addEventListener('click', () => {
  mobileMenu.hidden = !mobileMenu.hidden;
  menuToggle.setAttribute('aria-expanded', String(!mobileMenu.hidden));
  menuToggle.setAttribute('aria-label', mobileMenu.hidden ? 'Open menu' : 'Close menu');
});
mobileMenu?.addEventListener('click', event => {
  if (event.target.closest('a')) closeWebsiteMenu();
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') closeWebsiteMenu();
});

/* ---- Enquiry form v4 (Nov 2026) ----
   Flow: name -> verify phone OR email with an OTP (popup) -> role -> "need the most" + role questions -> Send.
   Server endpoints this expects (to be built on the backend):
     POST /api/otp/send    { channel: 'phone'|'email', target }          -> { sent: true }
     POST /api/otp/verify  { channel, target, code }                     -> { verified: true, token }
     POST /api/contact     existing endpoint; now also receives email + otpToken
   Preview mode (any host other than trustkeyper.com): no codes are sent, and 123456 is accepted. */
const ROLE_LABEL = { property_owner: 'Property owner', tenant: 'Tenant', broker: 'Property agent', builder: 'Builder' };
const OTP_PREVIEW = !/(^|\.)trustkeyper\.com$/.test(location.hostname);
const MOST_NAME = { property_owner: 'ownerMost', tenant: 'tenantMost', broker: 'agentMost', builder: 'builderMost' };

async function otpCall(path, body) {
  if (OTP_PREVIEW) {
    await new Promise(r => setTimeout(r, 500));
    if (path.endsWith('verify')) return body.code === '123456' ? { verified: true, token: 'preview' } : { verified: false };
    return { sent: true };
  }
  const res = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(20000) });
  const out = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(res.status === 429 ? 'Too many attempts. Please wait a few minutes.' : 'Something went wrong. Please try again.');
  return out;
}

for (const form of document.querySelectorAll('[data-enquiry-form]')) {
  const root = form.closest('.tkf-wrap').parentElement;
  const modal = root.querySelector('[data-otp-modal]');
  const submit = form.querySelector('[data-enquiry-submit]');
  const status = form.querySelector('[data-enquiry-status]');
  const after = form.querySelector('[data-after]');
  const q = sel => modal.querySelector(sel);
  const contact = { channel: '', target: '', token: '' };
  let otpChannel = 'phone', timer = null, sending = false, requestId = crypto.randomUUID();

  const role = () => form.querySelector('input[name="role"]:checked')?.value || '';
  const visible = el => !el.closest('.tkf-more[hidden]');
  const valid = () => form.elements.name.value.trim().length >= 2 && contact.token && role() && (role() !== 'builder' || form.elements.company.value.trim());
  const refresh = () => { submit.disabled = sending || !valid(); };

  function switchRole() {
    const r = role();
    for (const box of form.querySelectorAll('.tkf-more')) box.hidden = !(box.dataset.for === r || (box.dataset.for === 'any' && r));
    for (const c of form.querySelectorAll('.tkf-role')) c.classList.toggle('is-on', c.querySelector('input').checked);
    form.closest('.tkf-wrap').classList.toggle('is-open', !!contact.token);
  }

  // ---------- OTP popup ----------
  const isEmail = v => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
  function openOtp(channel) {
    otpChannel = channel;
    q('[data-otp-step="enter"]').hidden = false; q('[data-otp-step="code"]').hidden = true;
    q('[data-otp-ico]').textContent = channel === 'phone' ? '📱' : '✉️';
    q('[data-otp-title]').textContent = channel === 'phone' ? 'Verify your phone number' : 'Verify your email address';
    q('[data-otp-sub]').textContent = channel === 'phone' ? "We'll send a 6-digit code by SMS." : "We'll email you a 6-digit code.";
    q('[data-otp-phone-wrap]').hidden = channel !== 'phone'; q('[data-otp-email]').hidden = channel !== 'email';
    q('[data-otp-err]').hidden = true; q('[data-otp-demo]').hidden = !OTP_PREVIEW;
    modal.hidden = false; document.documentElement.classList.add('tkf-lock');
    setTimeout(() => (channel === 'phone' ? q('[data-otp-phone]') : q('[data-otp-email]')).focus(), 50);
    checkSend();
  }
  function closeOtp() { modal.hidden = true; document.documentElement.classList.remove('tkf-lock'); clearInterval(timer); }
  const target = () => otpChannel === 'phone' ? q('[data-otp-phone]').value : q('[data-otp-email]').value.trim();
  const targetOk = () => otpChannel === 'phone' ? /^[6-9]\d{9}$/.test(target()) : isEmail(target());
  function checkSend() { q('[data-otp-send]').disabled = !targetOk(); }
  const boxes = [...modal.querySelectorAll('[data-otp-boxes] input')];
  const code = () => boxes.map(b => b.value).join('');

  function startTimer() {
    let left = 30; const r = q('[data-otp-resend]'), t = q('[data-otp-timer]');
    r.disabled = true; t.textContent = `in ${left}s`; clearInterval(timer);
    timer = setInterval(() => { left--; t.textContent = left > 0 ? `in ${left}s` : ''; if (left <= 0) { clearInterval(timer); r.disabled = false; } }, 1000);
  }
  async function sendCode() {
    const btn = q('[data-otp-send]'); const err = q('[data-otp-err]');
    btn.disabled = true; btn.textContent = 'Sending...'; err.hidden = true;
    try {
      const out = await otpCall('/api/otp/send', { channel: otpChannel, target: target() });
      if (!out.sent) throw new Error('We could not send the code. Please check and try again.');
      q('[data-otp-target]').textContent = otpChannel === 'phone' ? `+91 ${target()}` : target();
      q('[data-otp-step="enter"]').hidden = true; q('[data-otp-step="code"]').hidden = false;
      boxes.forEach(b => (b.value = '')); q('[data-otp-code-err]').hidden = true; q('[data-otp-verify]').disabled = true;
      boxes[0].focus(); startTimer();
    } catch (e) { err.textContent = e.message; err.hidden = false; }
    finally { btn.textContent = 'Send OTP'; checkSend(); }
  }
  async function verify() {
    const btn = q('[data-otp-verify]'); const err = q('[data-otp-code-err]');
    btn.disabled = true; btn.textContent = 'Verifying...'; err.hidden = true;
    try {
      const out = await otpCall('/api/otp/verify', { channel: otpChannel, target: target(), code: code() });
      if (!out.verified) throw new Error('That code is not right. Please try again.');
      Object.assign(contact, { channel: otpChannel, target: target(), token: out.token || '' });
      form.querySelector('[data-verified-value]').textContent = otpChannel === 'phone' ? `+91 ${target()}` : target();
      form.querySelector('[data-reach-choose]').hidden = true; form.querySelector('[data-verify-hint]').hidden = true;
      form.querySelector('[data-verified]').hidden = false; after.hidden = false;
      closeOtp(); switchRole(); refresh();
      after.querySelector('.tkf-role input')?.focus({ preventScroll: true });
    } catch (e) { err.textContent = e.message; err.hidden = false; boxes.forEach(b => (b.value = '')); boxes[0].focus(); }
    finally { btn.textContent = 'Verify'; btn.disabled = code().length !== 6; }
  }

  form.addEventListener('click', e => {
    const o = e.target.closest('[data-open-otp]'); if (o) openOtp(o.dataset.openOtp);
    if (e.target.closest('[data-change-contact]')) {
      Object.assign(contact, { channel: '', target: '', token: '' });
      form.querySelector('[data-verified]').hidden = true; form.querySelector('[data-reach-choose]').hidden = false;
      form.querySelector('[data-verify-hint]').hidden = false; after.hidden = true; switchRole(); refresh();
    }
  });
  modal.addEventListener('click', e => {
    if (e.target === modal || e.target.closest('[data-otp-close]')) closeOtp();
    if (e.target.closest('[data-otp-send]')) sendCode();
    if (e.target.closest('[data-otp-verify]')) verify();
    if (e.target.closest('[data-otp-resend]')) sendCode();
    if (e.target.closest('[data-otp-edit]')) { q('[data-otp-step="enter"]').hidden = false; q('[data-otp-step="code"]').hidden = true; clearInterval(timer); }
  });
  modal.addEventListener('input', e => {
    if (e.target.matches('[data-otp-phone]')) e.target.value = e.target.value.replace(/\D/g, '').slice(0, 10);
    if (e.target.matches('[data-otp-phone],[data-otp-email]')) checkSend();
    const i = boxes.indexOf(e.target);
    if (i >= 0) {
      const v = e.target.value.replace(/\D/g, '');
      if (v.length > 1) { v.slice(0, 6).split('').forEach((d, k) => { if (boxes[k]) boxes[k].value = d; }); boxes[Math.min(v.length, 6) - 1].focus(); }
      else { e.target.value = v; if (v && boxes[i + 1]) boxes[i + 1].focus(); }
      q('[data-otp-verify]').disabled = code().length !== 6;
      if (code().length === 6) verify();
    }
  });
  modal.addEventListener('keydown', e => {
    const i = boxes.indexOf(e.target);
    if (i > 0 && e.key === 'Backspace' && !e.target.value) boxes[i - 1].focus();
    if (e.key === 'Enter') { e.preventDefault(); if (!q('[data-otp-step="enter"]').hidden && targetOk()) sendCode(); }
    if (e.key === 'Escape') closeOtp();
  });

  // ---------- "All of the above" is just another single choice, styled differently ----------
  form.addEventListener('input', e => { if (e.target.name === 'role') switchRole(); refresh(); });
  form.addEventListener('change', refresh);

  function collect() {
    const r = role(); const lines = [`I am a: ${ROLE_LABEL[r]}`];
    const val = n => [...form.querySelectorAll(`[name="${n}"]`)].filter(visible);
    const one = (n, label) => { const el = val(n).find(x => x.type !== 'radio' || x.checked); const v = el && el.value.trim(); if (v) lines.push(`${label}: ${el.tagName === 'SELECT' ? el.options[el.selectedIndex].text : v}`); };
    one(MOST_NAME[r], 'Needs the most');
    if (r === 'property_owner') { one('ownerPropertyType', 'Property type'); one('ownerArea', 'Location'); one('serviceTiming', 'When'); }
    if (r === 'tenant') { one('tenantSize', 'Looking for'); one('tenantBudget', 'Budget'); one('tenantArea', 'Preferred area'); one('serviceTiming', 'Move-in'); }
    if (r === 'broker') { one('agentArea', 'Areas'); }
    if (r === 'builder') { one('company', 'Company'); one('builderRole', 'Role'); one('builderProject', 'Project location'); }
    one('note', 'Note');
    lines.push(`Verified by: ${contact.channel === 'phone' ? 'phone OTP' : 'email OTP'}`);
    const timingEl = val('serviceTiming')[0];
    const parts = form.elements.name.value.trim().split(/\s+/);
    return {
      firstName: parts[0], lastName: parts.slice(1).join(' ') || '-',
      phone: contact.channel === 'phone' ? contact.target : '', email: contact.channel === 'email' ? contact.target : '',
      role: r, serviceTiming: timingEl ? timingEl.value : 'exploring',
      message: lines.join('\n'), otpToken: contact.token, website: form.elements.website.value,
    };
  }

  form.addEventListener('submit', async e => {
    e.preventDefault();
    if (sending || !valid()) return;
    sending = true; refresh(); submit.textContent = 'Sending...'; status.textContent = ''; status.dataset.error = 'false';
    try {
      const res = await fetch('/api/contact', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...collect(), requestId }), signal: AbortSignal.timeout(25000) });
      const out = await res.json();
      if (!res.ok || out.accepted !== true) throw new Error(res.status === 429 ? 'Too many requests. Please try again in an hour, or WhatsApp us on +91 8088516875.' : 'We could not confirm your message. Please retry, or WhatsApp us on +91 8088516875.');
      requestId = crypto.randomUUID();
      form.innerHTML = '<div class="tkf-done"><span aria-hidden="true">✓</span><h3>Thank you!</h3><p>We have your details. Our team will get in touch with you shortly.</p></div>';
    } catch (er) {
      status.dataset.error = 'true';
      status.textContent = er.name === 'TimeoutError' || er.name === 'TypeError' ? 'We could not confirm delivery. Please retry, or WhatsApp us on +91 8088516875.' : er.message;
      sending = false; submit.textContent = 'Send'; refresh();
    }
  });
  switchRole(); refresh();
}

/* ---- Floating WhatsApp button on every page (Nov 2026) ---- */
(() => {
  const WA_NUMBER = '918088516875';
  const WA_TEXT = 'Hi TrustKeyper, I would like to know more.';
  const a = document.createElement('a');
  a.className = 'tk-wa';
  a.href = `https://wa.me/${WA_NUMBER}?text=${encodeURIComponent(WA_TEXT)}`;
  a.target = '_blank'; a.rel = 'noopener noreferrer';
  a.setAttribute('aria-label', 'Chat with TrustKeyper on WhatsApp');
  a.innerHTML = '<svg viewBox="0 0 32 32" aria-hidden="true"><path fill="currentColor" d="M16 3C8.8 3 3 8.7 3 15.8c0 2.5.7 4.9 2 7L3 29l6.4-2c2 1.1 4.3 1.7 6.6 1.7 7.2 0 13-5.7 13-12.8S23.2 3 16 3zm0 23.4c-2.1 0-4.1-.6-5.9-1.6l-.4-.3-3.8 1.2 1.2-3.7-.3-.4a10.4 10.4 0 0 1-1.7-5.7C5.1 9.9 10 5.2 16 5.2S26.9 10 26.9 15.8 22 26.4 16 26.4zm6-7.8c-.3-.2-1.9-.9-2.2-1-.3-.1-.5-.2-.7.2l-1 1.2c-.2.2-.4.2-.7.1-.3-.2-1.4-.5-2.6-1.6-1-.9-1.6-1.9-1.8-2.2-.2-.3 0-.5.1-.7l.5-.6.3-.5c.1-.2 0-.4 0-.6l-1-2.4c-.3-.6-.5-.5-.7-.5h-.6c-.2 0-.6.1-.9.4-.3.3-1.2 1.1-1.2 2.7s1.2 3.1 1.4 3.4c.2.2 2.3 3.5 5.6 4.9 2.8 1.1 3.3.9 3.9.8.6-.1 1.9-.8 2.2-1.5.3-.7.3-1.4.2-1.5-.1-.2-.3-.3-.6-.4z"/></svg><span>Chat with us</span>';
  document.body.appendChild(a);
  // On phones, step aside while the enquiry form is on screen so it never covers a field
  const formArea = document.querySelector('.tkf-wrap');
  if (formArea && 'IntersectionObserver' in window) {
    new IntersectionObserver(([en]) => a.classList.toggle('tk-wa-away', en.isIntersecting), { threshold: 0.05 }).observe(formArea);
  }
})();

/* ---- Page change: always start at the top, with a visible transition (added Nov 2026) ---- */
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
  const toTop = () => {
    if (location.hash) return; // links like #get-started keep their own position
    window.scrollTo(0, 0);
    // also scrolls any page that embeds this site (e.g. a preview frame)
    try { document.body.scrollIntoView({ block: 'start', behavior: 'instant' }); } catch (e) {}
  };
  toTop();
  document.documentElement.classList.add('tk-page-in');
  window.addEventListener('pageshow', e => { if (e.persisted) document.documentElement.classList.remove('tk-page-out'); });

  document.addEventListener('click', e => {
    const a = e.target.closest('a[href]');
    if (!a || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if (a.target && a.target !== '_self') return;
    const url = new URL(a.href, location.href);
    if (url.origin !== location.origin) return;
    const samePage = url.pathname.replace(/index\.html$/, '') === location.pathname.replace(/index\.html$/, '');
    if (samePage && url.hash) return; // in-page jump, let smooth scroll handle it
    e.preventDefault();
    if (reduce) { location.href = url.href; return; }
    window.scrollTo({ top: 0, behavior: 'smooth' });
    try { document.body.scrollIntoView({ block: 'start', behavior: 'smooth' }); } catch (err) {}
    document.documentElement.classList.add('tk-page-out');
    setTimeout(() => { location.href = url.href; }, 280);
  });
})();
