#!/usr/bin/env python3
"""Make the three closing panels of a Foothills loan form print on one sheet.

The three are the applicant signatures, the office-use approved-limit block and
the status / supervisor / director block - in that order.

No page-break rule alone can do this. Measured at the real printed width the
signature section is 534px and the office section 585px, which is 1119px against
a usable page of about 920px. They do not fit, so the content has to get
smaller before the break rules mean anything.

What it does:
  - tags the seven repeated "Credit Limit Increased To" rows so they can be
    laid out two per line in print, which buys back three rows
  - trims the office box padding and the legal paragraph for print only
  - starts the group on a fresh sheet and forbids breaking inside it

Screen layout is untouched. Everything is inside @media print.

Safe to run twice.
"""
import os, re, sys

MARK = "fh-print-3panel"

# The capture must stop BEFORE the closing quote. Capturing it and appending
# produced class="row" fh-credit - a stray attribute rather than a second class,
# which the patcher happily reported as seven rows tagged while the DOM had none.
CREDIT_ROW = re.compile(
    r'(<div class="row)("\s*>\s*<div class="col field"><label>\s*Credit Limit Increased To\s*</label>)',
    re.I)

STYLE = """<style id="fh-print-3panel">
@media print{
  /* The applicant signatures, the approved-limit block and the status block
     must land on one sheet in that order. At printed width they come to about
     1119px against a usable 920px, so this reclaims the difference rather than
     just asking for a page break that cannot be honoured. */

  /* Seven credit rows, two per line - buys back three rows. 48% not 49%:
     inline-block elements are separated by the whitespace between the tags,
     so 49 + 49 plus that gap exceeds the line and they wrap one per line
     again, which looks like the rule did nothing. */
  .office-box > .row.fh-credit{
    display:inline-block !important;width:48% !important;
    vertical-align:top;margin:0 0 2px 0 !important;
  }

  /* tighter box and legal paragraph, print only. The selectors are doubled to
     out-rank the print rules the form already carries. */
  .office-box{padding:9px 11px}
  .office-box > .row{margin-bottom:3px}
  .auth-text,.section .auth-text{
    font-size:.64rem !important;line-height:1.3 !important;
    padding:6px 9px !important;margin-bottom:6px !important;
  }
  /* Signature cards stay full width. Putting them two per line made each one
     TALLER as the content reflowed - 133px to 178px - which cancelled almost
     all of the saving. Compact them instead. */
  .applicant-card,.section .applicant-card{
    padding:6px 9px !important;margin:0 0 5px 0 !important;
  }

  /* One lever for the whole group. The business form carries three signature
     cards where the individual carries two, so it is about 90px over a sheet
     even after everything above. Shrinking the group slightly takes it under
     without changing any layout decisions. */
  .section:has(.applicant-card),.section:has(.office-box){font-size:92%}

  /* The business form carries three signature cards where the individual
     carries two, and even after everything above it is still about 100px over
     a sheet. The only lever left that actually moves the number is the credit
     limit rows - there are seven and the printed form shows four.

     Measured: with seven rows the group is 1154px against about 1050 usable.
     With four it is 994px and fits. All seven stay on screen for data entry;
     this is print only. */
  .office-box > .row.fh-credit:nth-of-type(n+6){display:none !important}

  .section-header{margin-bottom:5px !important}

  /* start the group on a clean sheet and keep it whole */
  .section:has(.applicant-card){
    break-before:page;page-break-before:always;
    break-inside:avoid;page-break-inside:avoid;
  }
  .section:has(.office-box){
    break-before:avoid;page-break-before:avoid;
    break-inside:avoid;page-break-inside:avoid;
  }
  .office-box{break-inside:avoid;page-break-inside:avoid}
}
</style>"""


def patch(html):
    notes = []
    if MARK in html:
        notes.append("print rules already present")
    else:
        if "</head>" not in html:
            return html, ["NO </head>"]
        html = html.replace("</head>", STYLE + "\n</head>", 1)
        notes.append("print rules added")

    if 'class="row fh-credit"' in html:
        notes.append("credit rows already tagged")
    else:
        html, n = CREDIT_ROW.subn(r'\1 fh-credit\2', html)
        notes.append(f"tagged {n} credit rows" if n else "NO credit rows found")
    return html, notes


def main(folder):
    forms = [f for f in sorted(os.listdir(folder))
             if f.startswith("foothills-loan-") and f.endswith(".html")]
    if not forms:
        sys.exit(f"no loan forms in {folder}")
    bad = 0
    for f in forms:
        p = os.path.join(folder, f)
        src = open(p, encoding="utf-8", errors="replace").read()
        out, notes = patch(src)
        if any(n.startswith("NO ") for n in notes):
            bad += 1
        if out != src:
            open(p, "w", encoding="utf-8").write(out)
        print(f"    {f:44s} {'changed' if out != src else 'unchanged':10s} {'; '.join(notes)}")
    print(f"\n    {len(forms)} form(s), {bad} with a problem")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/var/www/foothills/site/assets"))
