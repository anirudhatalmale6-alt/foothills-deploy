#!/usr/bin/env python3
"""Put the finance calculator into the navigation, in four places.

The site has no shared include - the header and footer are inlined into every
page - so this edits each file in place rather than changing one template.

Every insertion is guarded. Run it twice and the second run reports "already
done" instead of adding a second copy. That guard is not optional: a bare
replace across 28 files gives you 28 duplicate menu entries on run two, and
you find out from the client.
"""
import os, re, sys

MARK = "fh-calc-nav"                     # idempotence marker, present once patched
CALC = "cattle-finance-calculator.html"

STYLE = """<style id="fh-calc-nav">
/* the calculator button - deliberately the only gold control in the header so
   it reads as different from Call and Request Financing rather than a third
   thing of the same weight */
.btn.calc-pop{background:linear-gradient(135deg,#e8c882,#c89a52);color:#2a1c0c;
  border:1px solid #b8873f;font-weight:700;box-shadow:0 2px 10px rgba(200,154,82,.34);
  position:relative}
.btn.calc-pop:hover{background:linear-gradient(135deg,#f0d59a,#d4a862);
  box-shadow:0 4px 16px rgba(200,154,82,.5);transform:translateY(-1px)}
.btn.calc-pop::after{content:"";position:absolute;inset:-3px;border-radius:inherit;
  border:2px solid rgba(200,154,82,.55);opacity:0;animation:fhCalcPulse 2.8s ease-out infinite}
@keyframes fhCalcPulse{0%{opacity:.75;transform:scale(1)}
  70%{opacity:0;transform:scale(1.13)}100%{opacity:0}}
@media (prefers-reduced-motion: reduce){.btn.calc-pop::after{animation:none}}
.mobile-menu .btn.calc-pop{display:block;text-align:center;margin-top:6px}

/* The header buttons are a different size on the inner pages than on the home
   page, and it is not our doing - the two were built from different
   stylesheets. Home defines .btn with font-size .9rem; the inner pages define
   .btn with no font-size at all, so it inherits 16px from the body, and they
   only pick up .9rem below 1120px. On a desktop that makes the header buttons
   70px tall against home's 47px.

   Matching home's values, and only above the width where the existing media
   query takes over, so the responsive behaviour below that is untouched. */
@media (min-width: 1121px){
  .nav-cta .btn, .nav-actions .btn{font-size:.9rem;padding:11px 22px}
}
</style>"""

DESKTOP_BTN = (f'<a href="{CALC}" class="btn calc-pop">Finance Calculator</a>')
DROPDOWN = (f'<a href="{CALC}"><strong>Finance Calculator</strong>'
            f'<span>Know your cost per head</span></a>')
MOBILE = f'<a href="{CALC}">Finance Calculator</a>'
FOOTER = f'<a href="{CALC}">Finance Calculator</a>'


def patch(html, name):
    """Return (html, notes). Each step is independent so a page missing one
    landmark still gets the others, and says which it missed."""
    notes = []

    # Pages differ in how they write nav links. The calculator was built to live
    # in /preview/, where a relative link would have pointed at the wrong place,
    # so its whole header uses absolute paths. Detect which convention this page
    # uses and both match AND insert in the same style - a nav that mixes the
    # two works today and breaks the moment a page moves into a subfolder.
    absolute = '<a href="/fieldmen.html"' in html
    pre = "/" if absolute else ""
    href = pre + CALC

    desktop_btn = f'<a href="{href}" class="btn calc-pop">Finance Calculator</a>'
    dropdown = (f'<a href="{href}"><strong>Finance Calculator</strong>'
                f'<span>Know your cost per head</span></a>')
    mobile = f'<a href="{href}">Finance Calculator</a>'
    footer = f'<a href="{href}">Finance Calculator</a>'
    drop_anchor = f'<a href="{pre}fieldmen.html"><strong>Fieldmen</strong>'
    notes.append("absolute paths" if absolute else "relative paths")

    # Wording changed after the first deploy. Without this, a page carrying the
    # OLD description would not match the new guard, so the patcher would add a
    # SECOND dropdown entry rather than recognising the one already there.
    # Migrate the text first, then every guard below behaves correctly.
    OLD_DESC = "Work out cost per head before you bid"
    NEW_DESC = "Know your cost per head"
    if OLD_DESC in html:
        html = html.replace(OLD_DESC, NEW_DESC)
        notes.append("updated the old wording")

    # 0. the stylesheet, once, just before </head>
    if 'id="fh-calc-nav"' in html:
        notes.append("style already present")
    elif "</head>" in html:
        html = html.replace("</head>", STYLE + "</head>", 1)
        notes.append("style added")
    else:
        notes.append("NO </head>")

    # 1. the prominent button in the desktop header
    anchor = '<div class="nav-actions"><div class="nav-cta desktop-only">'
    if anchor + desktop_btn in html:
        notes.append("header button already present")
    elif anchor in html:
        html = html.replace(anchor, anchor + desktop_btn, 1)
        notes.append("header button added")
    else:
        notes.append("NO nav-actions")

    # 2. the Resources dropdown. <strong>Fieldmen</strong> appears only in the
    #    desktop dropdown - the mobile menu and footer use a bare link - so it
    #    is a safe anchor for this one specifically.
    if dropdown in html:
        notes.append("dropdown already present")
    elif drop_anchor in html:
        html = html.replace(drop_anchor, dropdown + drop_anchor, 1)
        notes.append("dropdown added")
    else:
        notes.append("NO Fieldmen dropdown entry")

    # 3. the mobile menu, under its Resources heading
    m = re.search(r'(<div class="mobile-section-title">Resources</div>\s*)', html)
    if re.search(r'<div class="mobile-section-title">Resources</div>\s*<a href="'
                 + re.escape(href) + '"', html):
        notes.append("mobile already present")
    elif m:
        html = html[:m.end(1)] + mobile + html[m.end(1):]
        notes.append("mobile added")
    else:
        notes.append("NO mobile Resources section")

    # 4. the footer Resources column
    foot_anchor = "<h4>Resources</h4>"
    if re.search(re.escape(foot_anchor) + r'\s*<a href="' + re.escape(href) + '"', html):
        notes.append("footer already present")
    elif foot_anchor in html:
        i = html.index(foot_anchor) + len(foot_anchor)
        html = html[:i] + "\n        " + footer + html[i:]
        notes.append("footer added")
    else:
        notes.append("NO footer Resources column")

    return html, notes


def main(site):
    files = sorted(f for f in os.listdir(site)
                   if f.endswith(".html") and os.path.isfile(os.path.join(site, f)))
    if not files:
        sys.exit(f"no html files in {site}")

    changed = missing = 0
    for f in files:
        p = os.path.join(site, f)
        src = open(p, encoding="utf-8", errors="replace").read()
        out, notes = patch(src, f)
        miss = [n for n in notes if n.startswith("NO ")]
        if miss:
            missing += 1
        if out != src:
            open(p, "w", encoding="utf-8").write(out)
            changed += 1
        state = "changed" if out != src else "unchanged"
        print(f"    {f:48s} {state:10s} {'; '.join(notes)}")

    print(f"\n    {len(files)} files, {changed} changed, {missing} missing a landmark")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/var/www/foothills/site"))
