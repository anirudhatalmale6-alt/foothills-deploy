#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - make the FCC Producer Consent form unmissable
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-forms.sh -o /tmp/fh-forms.sh && sudo sh /tmp/fh-forms.sh
#
#  Four files:
#    forms.html                     two numbered steps, the consent pulled out
#                                   of the row of three into its own required block
#    assets/foothills-loan-individual.html
#    assets/foothills-loan-business.html
#                                   a reminder at the top of page one and again
#                                   at the end - these print, which is the point
#    faq.html                       one more question, plus the matching schema
#
#  Static files only. No nginx changes, no restart. Safe to run twice.
# ─────────────────────────────────────────────────────────────────────────────
set -u

RAW="https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/site"
SITE="/var/www/foothills/site"
HOST="foothillslivestock.ca"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
note() { printf '    %s\n' "$1"; }
FAILED=0

[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
[ -d "$SITE" ] || { echo "Cannot find $SITE - is this the right machine?"; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# ── 1. back up ──────────────────────────────────────────────────────────────
STAMP=$(date +%Y%m%d-%H%M%S)
BK="/var/backups/foothills-forms-$STAMP"
say "Backing up the four files to $BK"
mkdir -p "$BK/assets" || exit 1
cp -p "$SITE/forms.html" "$SITE/faq.html" "$BK"/ 2>/dev/null
cp -p "$SITE/assets/foothills-loan-individual.html" "$SITE/assets/foothills-loan-business.html" "$BK/assets"/ 2>/dev/null
note "to undo:  sudo cp -p $BK/*.html $SITE/ && sudo cp -p $BK/assets/*.html $SITE/assets/"

# ── 2. download, checking each one really arrived ───────────────────────────
# curl -o writes a 404 page straight over the target, so nothing is installed
# until every file has been fetched and recognised.
say "Downloading"
FILES="forms.html faq.html assets/foothills-loan-individual.html assets/foothills-loan-business.html"
mkdir -p "$TMP/assets"
for f in $FILES; do
  code=$(curl -sSL -m 90 -o "$TMP/$f" -w '%{http_code}' "$RAW/$f" 2>/dev/null)
  size=$(wc -c < "$TMP/$f" 2>/dev/null || echo 0)
  case "$f" in
    forms.html) marker='Step 2' ;;
    faq.html)   marker='FCC Producer Consent form' ;;
    *)          marker='FCC Producer Consent form must be completed' ;;
  esac
  if [ "$code" != "200" ]; then
    bad "$f - HTTP $code"
  elif [ "$size" -lt 20000 ]; then
    bad "$f - only $size bytes, that is not the real file"
  elif ! grep -q "$marker" "$TMP/$f"; then
    bad "$f - downloaded but does not contain the change"
  else
    ok "$f ($size bytes)"
  fi
done
[ "$FAILED" -eq 0 ] || { say "Stopping - nothing has been changed."; exit 1; }

# ── 3. install ──────────────────────────────────────────────────────────────
say "Installing"
for f in $FILES; do
  cp "$TMP/$f" "$SITE/$f" && ok "$f" || bad "$f could not be written"
done
chown --reference="$SITE" "$SITE/forms.html" "$SITE/faq.html" 2>/dev/null
chown --reference="$SITE/assets" "$SITE/assets/foothills-loan-individual.html" "$SITE/assets/foothills-loan-business.html" 2>/dev/null
chmod 644 "$SITE/forms.html" "$SITE/faq.html" "$SITE/assets/foothills-loan-individual.html" "$SITE/assets/foothills-loan-business.html" 2>/dev/null

# ── 4. ask the server, not the disk ─────────────────────────────────────────
say "Checking the server serves them"
for f in $FILES; do
  code=$(curl -sS -m 25 -o "$TMP/chk" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/$f" 2>/dev/null)
  case "$f" in
    forms.html) want='Required' ;;
    faq.html)   want='Do I have to complete the FCC Producer Consent form' ;;
    *)          want='have you completed the FCC Producer Consent form' ;;
  esac
  if [ "$code" = "200" ] && grep -q "$want" "$TMP/chk"; then ok "$f"; else bad "$f - HTTP $code, change not visible"; fi
done

# The consent PDF is what all of this points at. A required step linking to a
# 404 would be worse than the original problem.
code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/assets/fcc-producer-consent.pdf" 2>/dev/null)
[ "$code" = "200" ] && ok "the consent PDF itself is still served" || bad "the consent PDF returned $code"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/" 2>/dev/null)
[ "$code" = "200" ] && ok "home page still 200" || bad "HOME PAGE IS $code - undo with the copy command above"

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    The consent form is now a required step rather than a third option,\n'
  printf '    and both loan applications carry the reminder on the printed page.\n\n'
  printf '      https://foothillslivestock.ca/forms.html\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To undo:  sudo cp -p %s/*.html %s/ && sudo cp -p %s/assets/*.html %s/assets/\n\n' "$BK" "$SITE" "$BK" "$SITE"
fi
exit 0
