#!/usr/bin/env python3
"""Foothills Livestock - make the FCC Producer Consent requirement consistent.

forms.html already presents the consent as a mandatory Step 2: a red-bordered
card with a warning triangle, a "Required" badge, and wording that says an
application sent without it cannot be processed.

breeders-division.html and feeders-division.html demote the very same document
to an ordinary third card in a three-up grid - no badge, no red, and wording
that only says "return with your financing application". A producer reading
those two pages has no way to know it is mandatory.

This lifts the treatment that is already live and approved on forms.html onto
the two division pages. Nothing is invented; the markup and the CSS are copied
from forms.html so all three pages read identically.

It also rebuilds forms.html to carry all NINE forms Glenn listed, grouped by
division, and names every one of them for its division:

    Breeders   Individual Loan / Business Loan / FCC Consent /
               Full Mortality Claim / Accidental Death Claim
    Feeders    Individual Loan / Business Loan / FCC Consent /
               Full Mortality Claim

Nine entries, six files. The two loan applications each serve both divisions
through ?div=, and the consent is one PDF listed once per division - Glenn
confirmed it is the same form for Breeders, Feeders and Breeders/Feeders. So
this is naming and placement, not new documents.

And it puts the division into the filename the loan form downloads as. Until
now a Breeders application and a Feeders application both saved as
Foothills_Individual_Loan_Application_<date>.html, so once they were sitting in
the admin folder nothing told them apart.

Guarded throughout. Run it as many times as you like - it compares what is
already on the page against what it would write, and only reports a change when
it actually made one.
"""
import os, re, sys

MARK = "fh-fcc-req"

# ── the CSS, copied verbatim from forms.html ────────────────────────────────
STYLE = """<style id="fh-fcc-req">
.step-label{font-size:.82rem;font-weight:800;letter-spacing:.08em;text-transform:uppercase;
  color:var(--muted);margin:0 0 14px}
.step-label-req{color:#b5432a;margin-top:30px}
.req-card{display:flex;align-items:flex-start;gap:22px;text-decoration:none;
  background:linear-gradient(135deg,rgba(181,67,42,.07),rgba(181,67,42,.02));
  border:2px solid rgba(181,67,42,.28);border-radius:24px;padding:28px 30px;
  transition:all .35s cubic-bezier(.2,.7,.2,1)}
.req-card:hover{border-color:rgba(181,67,42,.5);box-shadow:0 18px 44px rgba(181,67,42,.14);
  transform:translateY(-3px)}
.req-icon{flex:0 0 auto;width:54px;height:54px;border-radius:16px;display:flex;
  align-items:center;justify-content:center;background:rgba(181,67,42,.12);color:#b5432a}
.req-icon svg{width:26px;height:26px}
.req-body{flex:1 1 auto;min-width:0}
.req-head{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:8px}
.req-head h3{margin:0;color:var(--ink);font-size:1.22rem}
.req-badge{padding:5px 12px;border-radius:999px;font-weight:800;font-size:.72rem;
  letter-spacing:.06em;text-transform:uppercase;background:#b5432a;color:#fff}
.req-body p{margin:0;color:var(--muted);font-size:.95rem;line-height:1.65}
.req-cta{flex:0 0 auto;align-self:center;display:inline-flex;align-items:center;gap:8px;
  font-weight:800;color:#b5432a;white-space:nowrap}
.req-cta svg{width:18px;height:18px}
@media (max-width:760px){
  .req-card{flex-direction:column;gap:16px;padding:22px}
  .req-cta{align-self:flex-start}
}
</style>"""

# ── the required block, copied verbatim from forms.html ─────────────────────
REQ_BLOCK = """<div class="step-label step-label-req">Step 2 &mdash; required with every application</div>
<a class="req-card reveal" href="/assets/fcc-producer-consent.pdf?v=2" download>
  <div class="req-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg></div>
  <div class="req-body">
    <div class="req-head"><h3>FCC Producer Consent</h3><span class="req-badge">Required</span></div>
    <p>Official Farm Credit Canada producer consent form. <strong>Every application must include it</strong> &mdash; individual or business, no exceptions. Download it, complete it, and return it together with your loan application. An application sent without the consent form cannot be processed.</p>
  </div>
  <span class="req-cta">Download <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M5 10h10M11 6l4 4-4 4"/></svg></span>
</a>"""

STEP1 = '<div class="step-label">Step 1 &mdash; choose your application</div>'

INTRO = ('Two steps. Choose the application that fits your situation, then complete the '
         'FCC Producer Consent &mdash; it is <strong>required with every application</strong>, '
         'individual or business.')


def put_style(html, notes):
    """Insert or update the stylesheet.

    Guard on the id, decide on the content. A guard that only asks "is it
    there?" silently does nothing the day the CSS changes, and still prints OK.
    """
    found = re.search(r'<style id="%s">.*?</style>' % MARK, html, re.S)
    if found:
        if found.group(0).strip() == STYLE.strip():
            notes.append("style already current")
        else:
            html = html[:found.start()] + STYLE + html[found.end():]
            notes.append("style UPDATED")
    elif "</head>" in html:
        html = html.replace("</head>", STYLE + "\n</head>", 1)
        notes.append("style added")
    else:
        notes.append("NO </head>")
    return html


def find_apply_section(html):
    """Return (start, end) of the <section> holding 'Apply for Financing'."""
    m = re.search(r'Apply for Financing', html)
    if not m:
        return None
    start = html.rfind("<section", 0, m.start())
    end = html.find("</section>", m.start())
    if start < 0 or end < 0:
        return None
    return start, end + len("</section>")


def patch_division(html, division, notes):
    """Give the division page the same mandatory treatment as forms.html."""
    span = find_apply_section(html)
    if not span:
        notes.append("NO Apply for Financing section")
        return html
    a, b = span
    sec = html[a:b]

    want = consent_card(division)

    if 'class="req-card' in sec:
        # Present - but is it CURRENT? Guarding on presence alone is how the
        # nav script silently skipped 28 live pages. Compare the content.
        s0 = sec.index('<div class="step-label step-label-req">')
        s1 = sec.index("</a>", sec.index("req-cta", s0)) + 4
        if sec[s0:s1].strip() == want.strip():
            notes.append("required block already current")
        else:
            sec = sec[:s0] + want + sec[s1:]
            notes.append("required block UPDATED")
    else:
        # 1. drop the FCC card out of the grid. It is the card whose heading is
        #    the consent form; take the whole <div class="card ...">...</div>.
        cards = list(re.finditer(r'<div class="card reveal"', sec))
        fcc_at = sec.find("FCC Producer Consent")
        if fcc_at < 0:
            notes.append("NO FCC card to replace")
            return html
        card_start = max(c.start() for c in cards if c.start() < fcc_at)
        # walk forward balancing <div> ... </div> from card_start
        depth, i = 0, card_start
        while i < len(sec):
            if sec.startswith("<div", i):
                depth += 1; i += 4
            elif sec.startswith("</div>", i):
                depth -= 1; i += 6
                if depth == 0:
                    break
            else:
                i += 1
        if depth != 0:
            notes.append("NO balanced FCC card")
            return html
        card_end = i
        sec = sec[:card_start] + sec[card_end:]

        # 2. three cards became two
        sec = sec.replace('class="grid grid-3"', 'class="grid grid-2"', 1)

        # 3. label the grid as step 1, and put step 2 after it
        gi = sec.find('<div class="grid grid-2"')
        if gi < 0:
            notes.append("NO grid to label")
            return html
        sec = sec[:gi] + STEP1 + sec[gi:]

        # close the grid, then append the required block after it
        gi = sec.find('<div class="grid grid-2"')
        depth, i = 0, gi
        while i < len(sec):
            if sec.startswith("<div", i):
                depth += 1; i += 4
            elif sec.startswith("</div>", i):
                depth -= 1; i += 6
                if depth == 0:
                    break
            else:
                i += 1
        sec = sec[:i] + "\n" + want + "\n" + sec[i:]
        notes.append("required block added, FCC card removed from the grid")

    # 3b. Glenn asked that every form be "named correctly". On these pages the
    #     division was only a small kicker above the heading, so the heading
    #     itself read "Individual Loan Application" - identical on both pages.
    #     Put the division into the heading and drop the now-duplicated kicker.
    for kind in ("Individual Loan Application", "Business Loan Application"):
        want = "<h3>%s %s</h3>" % (division, kind)
        if want in sec:
            notes.append("%s heading already named" % kind.split()[0].lower())
            continue
        # the kicker is a span immediately before the heading: "Breeders" or "Breeders /"
        m = re.search(r'<span style="color:#8b5e34;[^"]*">%s\s*/?\s*</span>(<h3>)%s</h3>'
                      % (division, re.escape(kind)), sec)
        if m:
            sec = sec[:m.start()] + "<h3>%s %s</h3>" % (division, kind) + sec[m.end():]
            notes.append("%s heading NAMED" % kind.split()[0].lower())
        elif "<h3>%s</h3>" % kind in sec:
            sec = sec.replace("<h3>%s</h3>" % kind, want, 1)
            notes.append("%s heading NAMED" % kind.split()[0].lower())
        else:
            notes.append("NO %s heading" % kind.split()[0].lower())

    # 4. the section intro should say there are two steps
    if INTRO in sec:
        notes.append("intro already current")
    else:
        old = re.search(r'(<div class="section-head reveal"><h2>Apply for Financing</h2><p>)(.*?)(</p>)',
                        sec, re.S)
        if old:
            sec = sec[:old.start(2)] + INTRO + sec[old.end(2):]
            notes.append("intro UPDATED")
        else:
            notes.append("NO intro paragraph")

    return html[:a] + sec + html[b:]


# ── the nine forms, grouped the way Glenn listed them ───────────────────────
#
# There are nine ENTRIES but only six files behind them. The two loan
# applications each serve both divisions through ?div=, and the FCC consent is
# one PDF listed once per division - Glenn's own note says it is the same form
# for Breeders, Feeders and Breeders/Feeders. So nothing new had to be
# authored; this is naming and placement.

FORMS9 = "fh-forms-9"

ICON_IND = ('<svg viewBox="0 0 40 40" fill="none" stroke="#6b3f1f" stroke-width="2" stroke-linecap="round">'
            '<circle cx="20" cy="14" r="7"/><path d="M8 35c0-7 5-13 12-13s12 6 12 13"/></svg>')
ICON_BUS = ('<svg viewBox="0 0 40 40" fill="none" stroke="#6b3f1f" stroke-width="2" stroke-linecap="round">'
            '<rect x="6" y="12" width="28" height="18" rx="3"/><path d="M14 12V9a6 6 0 0112 0v3"/>'
            '<path d="M20 22v4M17 24h6"/></svg>')
ICON_FM_F = ('<svg viewBox="0 0 40 40" fill="none" stroke="#314233" stroke-width="2" stroke-linecap="round">'
             '<path d="M8 28h24"/><path d="M12 28V16l8-8 8 8v12"/><rect x="17" y="20" width="6" height="8"/></svg>')
ICON_ACC = ('<svg viewBox="0 0 40 40" fill="none" stroke="#314233" stroke-width="2" stroke-linecap="round">'
            '<circle cx="20" cy="20" r="14"/><path d="M20 12v8l5 5"/></svg>')
ICON_FM_B = ('<svg viewBox="0 0 40 40" fill="none" stroke="#314233" stroke-width="2" stroke-linecap="round">'
             '<rect x="6" y="6" width="28" height="28" rx="4"/><path d="M14 14l12 12M26 14L14 26"/></svg>')

ARROW = ('<span class="form-arrow">Open Form <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" '
         'stroke-width="2.5"><path d="M5 10h10M11 6l4 4-4 4"/></svg></span>')


def card(href, icon, icon_cls, title, desc, badge_cls, badge):
    return ('<a class="form-card reveal" href="%s" target="_blank" style="text-decoration:none">\n'
            '  <div class="form-icon-box %s">%s</div>\n'
            '  <h3>%s</h3>\n  <p>%s</p>\n'
            '  <div class="form-card-footer"><span class="form-badge %s">%s</span>%s</div>\n'
            '</a>' % (href, icon_cls, icon, title, desc, badge_cls, badge, ARROW))


def consent_card(division):
    """The red REQUIRED consent card, labelled per division.

    Same PDF behind both - Glenn confirmed the consent form is identical for
    Breeders, Feeders and Breeders/Feeders - so the wording says so plainly
    rather than implying there are two different documents.
    """
    return ('<div class="step-label step-label-req">Step 2 &mdash; required with every application</div>\n'
            '<a class="req-card reveal" href="/assets/fcc-producer-consent.pdf?v=2" download>\n'
            '  <div class="req-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
            'stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 '
            '0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/>'
            '<line x1="12" y1="17" x2="12.01" y2="17"/></svg></div>\n'
            '  <div class="req-body">\n'
            '    <div class="req-head"><h3>%s FCC Producer Consent</h3>'
            '<span class="req-badge">Required</span></div>\n'
            '    <p>Official Farm Credit Canada producer consent form. <strong>Every application must include it'
            '</strong> &mdash; individual or business, no exceptions. An application sent without the consent form '
            'cannot be processed. This is the same consent form for Breeders and Feeders, so one copy covers you '
            'either way.</p>\n'
            '  </div>\n'
            '  <span class="req-cta">Download <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" '
            'stroke-width="2.5"><path d="M5 10h10M11 6l4 4-4 4"/></svg></span>\n'
            '</a>' % division)


def division_block(division, label_svg, claims):
    d = division.lower()
    return """<section style="padding:20px 0 44px"><div class="container">
<div class="forms-section-label label-app reveal">%s %s Division</div>
<div class="section-head reveal" style="margin-bottom:26px"><h2>%s Division Forms</h2><p>Every form for the %s division in one place. Complete the application that fits your situation, then include the FCC Producer Consent &mdash; it is <strong>required with every application</strong>.</p></div>
<div class="step-label">Step 1 &mdash; choose your application</div>
<div class="grid grid-2">
%s
%s
</div>
%s
<div class="step-label" style="margin-top:34px">Claim forms</div>
<div class="grid grid-2">
%s
</div>
</div></section>""" % (
        label_svg, division, division, d,
        card("/assets/foothills-loan-individual.html?div=%s" % d, ICON_IND, "form-icon-app",
             "%s Individual Loan Application" % division,
             "Complete application package for individual producers applying for %s cattle financing." % d.rstrip('s'),
             "badge-app", "Application"),
        card("/assets/foothills-loan-business.html?div=%s" % d, ICON_BUS, "form-icon-app",
             "%s Business Loan Application" % division,
             "Application package for business entities, partnerships or corporations seeking %s cattle financing."
             % d.rstrip('s'),
             "badge-app", "Application"),
        consent_card(division),
        "\n".join(claims))


LABEL_SVG = ('<svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">'
             '<rect x="3" y="2" width="14" height="16" rx="2"/><path d="M7 7h6M7 10h6M7 13h4"/></svg>')


def build_nine():
    breeders = division_block("Breeders", LABEL_SVG, [
        card("/assets/foothills-breeders-fm-claim.html", ICON_FM_B, "form-icon-claim",
             "Breeders Full Mortality Claim",
             "Full mortality claim for breeder cattle. Complete and submit to begin the claims process.",
             "badge-claim", "Breeder Claim"),
        card("/assets/foothills-breeders-accidental-claim.html", ICON_ACC, "form-icon-claim",
             "Breeders Accidental Death Claim",
             "Accidental death or injury claim for breeder cattle. Report incidents promptly to the office.",
             "badge-claim", "Breeder Claim"),
    ])
    feeders = division_block("Feeders", LABEL_SVG, [
        card("/assets/foothills-feeders-fm-claim.html", ICON_FM_F, "form-icon-claim",
             "Feeders Full Mortality Claim",
             "Full mortality claim form for feeder cattle covered under the Foothills protection program.",
             "badge-claim", "Feeder Claim"),
    ])
    # Comment delimiters, not a wrapper div. On a re-run this block has to be
    # found and replaced exactly; searching for the last </section> would have
    # swallowed the "Not sure which form you need?" section that follows ours,
    # and balancing nested divs is more machinery than the job needs.
    return ("<!--%s-start-->\n" % FORMS9) + breeders + "\n" + feeders + ("\n<!--%s-end-->" % FORMS9)


def patch_forms_page(html, notes):
    """Replace the Apply + Claim sections with the nine forms, grouped by division."""
    new = build_nine()
    start_tag, end_tag = "<!--%s-start-->" % FORMS9, "<!--%s-end-->" % FORMS9

    if start_tag in html:
        a = html.index(start_tag)
        if end_tag not in html:
            notes.append("NO closing marker - refusing to guess")
            return html
        b = html.index(end_tag) + len(end_tag)
        if html[a:b].strip() == new.strip():
            notes.append("nine forms already current")
        else:
            html = html[:a] + new + html[b:]
            notes.append("nine forms UPDATED")
        return html

    start_m = re.search(r'<section[^>]*>(?:(?!</section>).)*?Apply for Financing', html, re.S)
    if not start_m:
        notes.append("NO Apply for Financing section")
        return html
    a = start_m.start()

    claim_m = re.search(r'Submit a Claim', html[a:])
    if not claim_m:
        notes.append("NO Submit a Claim section")
        return html
    b = html.index("</section>", a + claim_m.start()) + len("</section>")

    html = html[:a] + new + html[b:]
    notes.append("nine forms BUILT (replaced 6 cards in 2 sections)")
    return html


def patch_form_asset(html, kind, notes):
    """Put the division into the downloaded filename.

    Without this a Breeders and a Feeders application both land in the admin
    folder as Foothills_<kind>_Loan_Application_<date>.html and nothing on the
    filename says which division it belongs to.

    _divLabel is declared with var in the same <script>, so it is assigned long
    before anyone clicks download; the typeof guard is belt and braces.
    """
    old = 'var fn="Foothills_%s_Loan_Application_"' % kind
    new = ('var fn="Foothills_"+(typeof _divLabel!=="undefined"&&_divLabel?_divLabel+"_":"")'
           '+"%s_Loan_Application_"' % kind)
    if new in html:
        notes.append("filename already carries the division")
    elif old in html:
        html = html.replace(old, new, 1)
        notes.append("filename now carries the division")
    else:
        notes.append("NO filename line found")
    return html


def fix_form_count(html, notes):
    """The hero chip counts the forms on the page. It said 6; there are now 9."""
    if "9 Online Forms" in html:
        notes.append("count already 9")
    elif re.search(r'\d+ Online Forms', html):
        html = re.sub(r'\d+ Online Forms', "9 Online Forms", html, count=1)
        notes.append("hero count UPDATED to 9")
    else:
        notes.append("NO form count chip")
    return html


def name_claims(html, notes):
    """Glenn's list calls it the Accidental DEATH Claim; the site said 'Accidental Claim'."""
    old, new = "Breeders Accidental Claim", "Breeders Accidental Death Claim"
    if new in html:
        notes.append("accidental claim already named")
    elif old in html:
        html = html.replace(old, new)
        notes.append("accidental claim RENAMED")
    return html


def write(path, before, after, notes):
    changed = after != before
    if changed:
        open(path, "w", encoding="utf-8").write(after)
    bad = any(n.startswith("NO ") for n in notes)
    print("    %-38s %-10s %s" % (os.path.basename(path),
                                  "changed" if changed else "unchanged",
                                  "; ".join(notes)))
    return bad


def main(site):
    assets = os.path.join(site, "assets")
    bad = 0

    print("\n  Division pages")
    for page, div in (("breeders-division.html", "Breeders"),
                      ("feeders-division.html", "Feeders")):
        p = os.path.join(site, page)
        if not os.path.exists(p):
            print("    %-38s MISSING" % page); bad += 1; continue
        src = open(p, encoding="utf-8", errors="replace").read()
        notes = []
        out = put_style(src, notes)
        out = patch_division(out, div, notes)
        out = name_claims(out, notes)
        bad += write(p, src, out, notes)

    print("\n  Forms page")
    p = os.path.join(site, "forms.html")
    if os.path.exists(p):
        src = open(p, encoding="utf-8", errors="replace").read()
        notes = []
        out = patch_forms_page(src, notes)
        out = fix_form_count(out, notes)
        bad += write(p, src, out, notes)
    else:
        print("    forms.html MISSING"); bad += 1

    print("\n  Loan forms (admin filename)")
    for f, kind in (("foothills-loan-individual.html", "Individual"),
                    ("foothills-loan-business.html", "Business")):
        p = os.path.join(assets, f)
        if not os.path.exists(p):
            print("    %-38s MISSING" % f); bad += 1; continue
        src = open(p, encoding="utf-8", errors="replace").read()
        notes = []
        bad += write(p, src, patch_form_asset(src, kind, notes), notes)

    print("\n    %d problem(s)" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/var/www/foothills/site"))
