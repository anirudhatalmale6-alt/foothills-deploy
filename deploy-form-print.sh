#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - make the three closing panels print on one sheet.
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-form-print.sh -o /tmp/fh-print.sh && sudo sh /tmp/fh-print.sh
#
#  The applicant signatures, the approved-limit block and the status block now
#  land on one page, in that order, on both loan forms.
#
#  Print only. Nothing about the on-screen form changes.
#  Safe to run twice.
# ─────────────────────────────────────────────────────────────────────────────
set -u
RAW="https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main"
SITE="/var/www/foothills/site"
say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
note() { printf '    %s\n' "$1"; }
FAILED=0
[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
[ -d "$SITE/assets" ] || { echo "Cannot find $SITE/assets - right machine?"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found."; exit 1; }
TMP=$(mktemp -d) || exit 1; trap 'rm -rf "$TMP"' EXIT

say "Downloading the patcher"
code=$(curl -sSL -m 60 -o "$TMP/fix.py" -w '%{http_code}' "$RAW/fix_print.py" 2>/dev/null)
sz=$(wc -c < "$TMP/fix.py" 2>/dev/null || echo 0)
[ "$code" = "200" ] && [ "$sz" -gt 2000 ] || { bad "patcher HTTP $code, $sz bytes"; exit 1; }
python3 -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$TMP/fix.py" \
  && ok "downloaded and parses ($sz bytes)" || { bad "not valid python"; exit 1; }

say "Backing up the forms"
STAMP=$(date +%Y%m%d-%H%M%S); BK="/var/backups/foothills-formprint-$STAMP"
mkdir -p "$BK" && cp -p "$SITE/assets"/foothills-loan-*.html "$BK"/ 2>/dev/null
ok "$(ls -1 "$BK" 2>/dev/null | wc -l) form(s) backed up to $BK"
note "to undo:  sudo cp -p $BK/*.html $SITE/assets/"

say "Applying the print rules"
python3 "$TMP/fix.py" "$SITE/assets" || bad "the patcher reported a problem"

say "Checking"
for f in "$SITE/assets"/foothills-loan-*.html; do
  n=$(basename "$f")
  s=$(grep -c 'fh-print-3panel' "$f" 2>/dev/null || echo 0)
  c=$(grep -o 'class="row fh-credit"' "$f" 2>/dev/null | wc -l)
  if [ "$s" -ge 1 ] && [ "$c" -eq 7 ]; then ok "$n - rules present, $c credit rows tagged"
  else bad "$n - style blocks $s, tagged rows $c (expected 1 and 7)"; fi
done
for f in "$SITE/assets"/foothills-loan-*.html; do
  n=$(basename "$f")
  code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: foothillslivestock.ca" "http://127.0.0.1/assets/$n" 2>/dev/null)
  [ "$code" = "200" ] && ok "$n serves 200" || bad "$n returned $code"
done

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    Open a loan form, press Print, and the signatures, the approved\n'
  printf '    limit block and the status block are on one page in that order.\n\n'
  printf '    The printed form now shows four Credit Limit Increased lines\n'
  printf '    instead of seven. All seven are still there on screen.\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To undo:  sudo cp -p %s/*.html %s/assets/\n\n' "$BK" "$SITE"
fi
exit 0
