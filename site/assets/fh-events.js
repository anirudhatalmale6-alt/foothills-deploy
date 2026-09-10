/* ─────────────────────────────────────────────────────────────────────────
   Foothills Livestock - event tracking for Google Analytics 4

   The page-view tag on its own answers "how many people came". It cannot
   answer "how many of them did anything", and on this site that second
   question is the whole point: there are no web forms, so a producer either
   phones the office or opens an application form. Neither of those is a page
   view, so neither of them is currently measured anywhere.

   This adds four events. It does not touch the in-house tracker in
   fh-analytics.js, which keeps doing its own thing.

     phone_click      a tel: link was tapped        <- the real conversion
     form_open        an application or claim form was opened
     chat_open        the chat widget was opened
     calculator_use   somebody actually used the loan calculator

   No personal data is collected. Only which link was clicked, and from which
   page.
   ───────────────────────────────────────────────────────────────────────── */
(function () {
  'use strict';

  /* If the GA4 tag is missing on this page, do nothing at all rather than
     queueing events into a dataLayer nobody will ever read. */
  function track(name, params) {
    if (typeof window.gtag !== 'function') return;
    try { window.gtag('event', name, params || {}); } catch (e) { /* never break the page */ }
  }

  var here = location.pathname;

  /* ── phone calls ───────────────────────────────────────────────────────
     Listening on the document rather than binding each link, so numbers
     added later - or rendered by the chat widget - are covered too. */
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href^="tel:"]') : null;
    if (!a) return;
    track('phone_click', {
      phone_number: a.getAttribute('href').replace('tel:', ''),
      page_path: here,
      link_text: (a.textContent || '').trim().slice(0, 60)
    });
  }, true);

  /* ── application and claim forms ───────────────────────────────────────
     These are the six documents under /assets/ plus any PDF. Opening one is
     the strongest signal short of a phone call that somebody is serious. */
  var FORM_NAMES = {
    'foothills-loan-individual': 'Individual loan application',
    'foothills-loan-business': 'Business loan application',
    'foothills-breeders-accidental-claim': 'Breeders accidental claim',
    'foothills-breeders-fm-claim': 'Breeders FM claim',
    'foothills-feeders-fm-claim': 'Feeders FM claim',
    'fcc-producer-consent': 'FCC producer consent'
  };

  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.getAttribute('href') || '';
    if (href.indexOf('/assets/') !== 0 && !/\.pdf(\?|$)/i.test(href)) return;

    var base = href.split('?')[0].split('/').pop().replace(/\.(html?|pdf)$/i, '');
    track('form_open', {
      form_name: FORM_NAMES[base] || base,
      file_name: href.split('?')[0].split('/').pop(),
      page_path: here
    });
  }, true);

  /* ── chat widget ───────────────────────────────────────────────────────
     The widget is third-party markup we do not control, so rather than hook
     its internals, watch for its panel appearing. Fires once per page. */
  var chatSeen = false;
  function watchChat() {
    if (!window.MutationObserver) return;
    var obs = new MutationObserver(function () {
      if (chatSeen) return;
      var open = document.querySelector(
        '[class*="chat"][class*="open"], [class*="chat-window"], [class*="chat-panel"], [id*="chat"][class*="open"]'
      );
      if (open && open.offsetParent !== null) {
        chatSeen = true;
        track('chat_open', { page_path: here });
        obs.disconnect();
      }
    });
    obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] });
    /* Do not watch forever - a permanent observer on a whole document is a
       needless cost on a page somebody leaves open in a truck all day. */
    setTimeout(function () { obs.disconnect(); }, 600000);
  }

  /* ── the loan calculator ───────────────────────────────────────────────
     One event the first time somebody changes any input, not one per
     keystroke, and one when they print. */
  function watchCalculator() {
    var form = document.getElementById('calcForm');
    if (!form) return;
    var fired = false;
    form.addEventListener('input', function () {
      if (fired) return;
      fired = true;
      track('calculator_use', { page_path: here });
    });
    var p = document.getElementById('btnPrint');
    if (p) p.addEventListener('click', function () {
      track('calculator_print', { page_path: here });
    });
  }

  function init() { watchChat(); watchCalculator(); }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
