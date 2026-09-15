#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - put the finance calculator into the navigation.
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-calc-nav.sh -o /tmp/fh-nav.sh && sudo sh /tmp/fh-nav.sh
#
#  Four places on every page:
#    - a gold button in the header, next to Call and Request Financing
#    - an entry in the Resources dropdown
#    - an entry in the mobile menu under Resources
#    - a link in the footer Resources column
#
#  The site has no shared header file - it is inlined into all 28 pages - so
#  this edits each page in place. Every insertion is guarded, so running it
#  twice does not give you two menu entries.
#
#  Run this AFTER deploy-calc-seo.sh. If you ever re-run the SEO deploy, run
#  this again afterwards - it is safe either way, and it will report
#  "already present" on anything it has already done.
# ─────────────────────────────────────────────────────────────────────────────
set -u

RAW="https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main"
SITE="/var/www/foothills/site"
HOST="foothillslivestock.ca"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
note() { printf '    %s\n' "$1"; }
FAILED=0

[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
[ -d "$SITE" ] || { echo "Cannot find $SITE - is this the right machine?"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found on this VM."; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

say "Downloading the patcher"
code=$(curl -sSL -m 60 -o "$TMP/patch.py" -w '%{http_code}' "$RAW/add_calc_links.py" 2>/dev/null)
size=$(wc -c < "$TMP/patch.py" 2>/dev/null || echo 0)
if [ "$code" != "200" ] || [ "$size" -lt 3000 ]; then
  bad "patcher - HTTP $code, $size bytes"
  exit 1
fi
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$TMP/patch.py" 2>/dev/null \
  && ok "patcher downloaded and parses ($size bytes)" || { bad "patcher is not valid python"; exit 1; }

say "Backing up every page first"
STAMP=$(date +%Y%m%d-%H%M%S)
BK="/var/backups/foothills-nav-$STAMP"
mkdir -p "$BK" || exit 1
cp -p "$SITE"/*.html "$BK"/ 2>/dev/null
n=$(ls -1 "$BK"/*.html 2>/dev/null | wc -l)
ok "$n pages backed up to $BK"
note "to undo:  sudo cp -p $BK/*.html $SITE/"

say "Adding the calculator to the navigation"
python3 "$TMP/patch.py" "$SITE" || bad "the patcher reported a problem"

say "Checking what the server serves"
CHECKED=0; WITH=0
for f in index.html forms.html faq.html cattle-financing-rates.html; do
  [ -f "$SITE/$f" ] || continue
  CHECKED=$((CHECKED+1))
  code=$(curl -sS -m 25 -o "$TMP/c" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/$f" 2>/dev/null)
  hits=$(grep -o 'cattle-finance-calculator\.html' "$TMP/c" 2>/dev/null | wc -l)
  if [ "$code" = "200" ] && [ "$hits" -ge 4 ]; then
    WITH=$((WITH+1)); ok "$f - 200, calculator linked $hits times"
  else
    bad "$f - HTTP $code, calculator linked $hits times (expected at least 4)"
  fi
done
[ "$CHECKED" -gt 0 ] && [ "$WITH" -eq "$CHECKED" ] && ok "all $CHECKED sampled pages carry the links"

say "Checking nothing got duplicated"
DUPE=0
for f in "$SITE"/*.html; do
  n=$(grep -o 'class="btn calc-pop"' "$f" 2>/dev/null | wc -l)
  if [ "$n" -gt 1 ]; then
    bad "$(basename "$f") has $n calculator buttons - it has been patched twice"
    DUPE=$((DUPE+1))
  fi
done
[ "$DUPE" -eq 0 ] && ok "no page has more than one calculator button"

say "Checking the target page exists"
code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" \
       "http://127.0.0.1/cattle-finance-calculator.html" 2>/dev/null)
if [ "$code" = "200" ]; then
  ok "cattle-finance-calculator.html returns 200"
else
  bad "the calculator page returns $code - the new menu links point at nothing"
  note "Run deploy-calc-seo.sh first, then run this again."
fi

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    The calculator is now in the header, the Resources dropdown, the\n'
  printf '    mobile menu and the footer on every page.\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To undo:  sudo cp -p %s/*.html %s/\n\n' "$BK" "$SITE"
fi
exit 0
