#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - make the FCC Producer Consent requirement consistent
#  across the whole site, and make a saved application say which division it
#  came from.
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-fcc.sh -o /tmp/fh-fcc.sh && sudo sh /tmp/fh-fcc.sh
#
#  What it changes:
#
#   1. breeders-division.html and feeders-division.html
#      The consent form was the third card in a three-up grid - no badge, no
#      red, and wording that only said "return it with your application". It
#      now gets exactly the treatment forms.html already uses: a red STEP 2
#      heading, a red-bordered card, a REQUIRED badge, and wording that says an
#      application without it cannot be processed. The markup and CSS are
#      copied from forms.html, so all three pages now read identically.
#
#   2. forms.html
#      Rebuilt to carry all NINE forms, grouped by division, each named for its
#      division exactly as Glenn listed them:
#
#        Breeders  Individual Loan / Business Loan / FCC Consent /
#                  Full Mortality Claim / Accidental Death Claim
#        Feeders   Individual Loan / Business Loan / FCC Consent /
#                  Full Mortality Claim
#
#      Nine entries, six files behind them - the loan forms serve both
#      divisions through ?div=, and the consent PDF is listed once per
#      division because it is the same document for both.
#
#   3. The loan forms themselves
#      A Breeders application and a Feeders application used to download under
#      the SAME filename, so once they were sitting in the admin folder nothing
#      told them apart. The division now goes into the filename:
#          Foothills_Breeders_Individual_Loan_Application_2026-09-16.html
#      The saved file already carried the division in its title bar; now the
#      filename matches it.
#
#  Existing saved applications are not touched - only new ones get the new
#  name. Safe to run more than once.
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
code=$(curl -sSL -m 60 -o "$TMP/fcc.py" -w '%{http_code}' "$RAW/add_fcc.py" 2>/dev/null)
size=$(wc -c < "$TMP/fcc.py" 2>/dev/null || echo 0)
if [ "$code" != "200" ] || [ "$size" -lt 4000 ]; then
  bad "patcher - HTTP $code, $size bytes"; exit 1
fi
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$TMP/fcc.py" 2>/dev/null \
  && ok "patcher downloaded and parses ($size bytes)" || { bad "patcher is not valid python"; exit 1; }

say "Backing up first"
STAMP=$(date +%Y%m%d-%H%M%S)
BK="/var/backups/foothills-fcc-$STAMP"
mkdir -p "$BK/assets" || exit 1
cp -p "$SITE"/*.html "$BK"/ 2>/dev/null
cp -p "$SITE"/assets/*.html "$BK/assets"/ 2>/dev/null
n=$(ls -1 "$BK"/*.html "$BK"/assets/*.html 2>/dev/null | wc -l)
ok "$n files backed up to $BK"
note "to undo:  sudo cp -p $BK/*.html $SITE/ && sudo cp -p $BK/assets/*.html $SITE/assets/"

say "Applying the changes"
python3 "$TMP/fcc.py" "$SITE" || bad "the patcher reported a problem"

say "Checking what the server actually serves"
for f in breeders-division.html feeders-division.html; do
  code=$(curl -sS -m 25 -o "$TMP/c" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/$f" 2>/dev/null)
  card=$(grep -o 'class="req-card' "$TMP/c" 2>/dev/null | wc -l)
  badge=$(grep -o 'req-badge">Required' "$TMP/c" 2>/dev/null | wc -l)
  if [ "$code" = "200" ] && [ "$card" -eq 1 ] && [ "$badge" -eq 1 ]; then
    ok "$f - 200, one required card with a Required badge"
  else
    bad "$f - HTTP $code, $card required card(s), $badge badge(s) - expected exactly 1 of each"
  fi
done

code=$(curl -sS -m 25 -o "$TMP/c" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/forms.html" 2>/dev/null)
# 'class="form-card' on its own also matches class="form-card-footer", which is
# inside every card - it counted 14 for 7 cards. Match the full class list.
cards=$(grep -o 'class="form-card reveal"' "$TMP/c" 2>/dev/null | wc -l)
reqs=$(grep -o 'class="req-card' "$TMP/c" 2>/dev/null | wc -l)
# 7 ordinary cards + 2 consent cards = the 9 forms Glenn listed
if [ "$code" = "200" ] && [ "$cards" -eq 7 ] && [ "$reqs" -eq 2 ]; then
  ok "forms.html - 200, all 9 forms present (7 cards + 2 consent)"
else
  bad "forms.html - HTTP $code, $cards form cards and $reqs consent cards (expected 7 and 2)"
fi
MISSING=0
for want in "Breeders Individual Loan Application" "Breeders Business Loan Application" \
            "Breeders FCC Producer Consent" "Breeders Full Mortality Claim" \
            "Breeders Accidental Death Claim" "Feeders Individual Loan Application" \
            "Feeders Business Loan Application" "Feeders FCC Producer Consent" \
            "Feeders Full Mortality Claim"; do
  n=$(grep -o "$want" "$TMP/c" 2>/dev/null | wc -l)
  if [ "$n" -lt 1 ]; then bad "forms.html is missing: $want"; MISSING=$((MISSING+1)); fi
done
[ "$MISSING" -eq 0 ] && ok "every one of the 9 forms is named exactly as you listed it"

say "Checking the saved-application filename"
for f in foothills-loan-individual.html foothills-loan-business.html; do
  code=$(curl -sS -m 25 -o "$TMP/c" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/assets/$f" 2>/dev/null)
  hits=$(grep -o '_divLabel?_divLabel+"_"' "$TMP/c" 2>/dev/null | wc -l)
  if [ "$code" = "200" ] && [ "$hits" -ge 1 ]; then
    ok "$f - 200, the division goes into the filename"
  else
    bad "$f - HTTP $code, division-in-filename not found"
  fi
done

say "Checking nothing got applied twice"
DUPE=0
for f in "$SITE"/breeders-division.html "$SITE"/feeders-division.html; do
  n=$(grep -o 'class="req-card' "$f" 2>/dev/null | wc -l)
  s=$(grep -o '<style id="fh-fcc-req">' "$f" 2>/dev/null | wc -l)
  if [ "$n" -gt 1 ] || [ "$s" -gt 1 ]; then
    bad "$(basename "$f") has $n required cards and $s stylesheets - patched twice"
    DUPE=$((DUPE+1))
  fi
done
[ "$DUPE" -eq 0 ] && ok "no page was patched twice"

say "Checking the consent PDF is actually there"
code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" \
       "http://127.0.0.1/assets/fcc-producer-consent.pdf" 2>/dev/null)
[ "$code" = "200" ] && ok "fcc-producer-consent.pdf returns 200" \
                    || bad "the consent PDF returns $code - the Required card points at nothing"

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    All three pages now say the consent form is required, in the same\n'
  printf '    words. New applications save with the division in the filename.\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To undo:  sudo cp -p %s/*.html %s/ && sudo cp -p %s/assets/*.html %s/assets/\n\n' \
         "$BK" "$SITE" "$BK" "$SITE"
fi
exit 0
