#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - publish the calculator SEO pages.
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-calc-seo.sh -o /tmp/fh-seo.sh && sudo sh /tmp/fh-seo.sh
#
#  WHAT THIS MAKES PUBLIC
#    cattle-finance-calculator.html            the calculator, out of preview
#    cattle-loan-calculator-canada.html
#    feeder-cattle-financing-calculator.html
#    livestock-loan-calculator-western-canada.html
#    cost-to-finance-cattle-alberta.html
#    sitemap.xml                               28 urls, up from 23
#
#  AND WHAT IT UPDATES BEHIND THE PASSWORD
#    preview/cattle-break-even.html            now with the site header and footer
#
#  The four supporting pages link to the calculator page, so all five go up
#  together or none do. Publishing them separately would leave four pages
#  pointing at a 404 for however long the gap lasted.
#
#  The calculator page is the one that changes visibility - it was noindex
#  inside preview and becomes a public, indexable page here. The preview copy is
#  left exactly where it is and is not touched.
#
#  Safe to run twice.
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
[ -d "$SITE/preview" ] || { echo "Cannot find $SITE/preview - run the calculator deploy first."; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/preview"

PUBLIC="cattle-finance-calculator.html cattle-loan-calculator-canada.html feeder-cattle-financing-calculator.html livestock-loan-calculator-western-canada.html cost-to-finance-cattle-alberta.html"

# ── 1. download everything and check what arrived is real ───────────────────
say "Downloading"
for f in $PUBLIC sitemap.xml preview/cattle-break-even.html; do
  code=$(curl -sSL -m 90 -o "$TMP/$f" -w '%{http_code}' "$RAW/$f" 2>/dev/null)
  size=$(wc -c < "$TMP/$f" 2>/dev/null || echo 0)
  case "$f" in
    sitemap.xml) min=2000; marker='cattle-finance-calculator' ;;
    preview/*)   min=40000; marker='NOT investment advice' ;;
    *)           min=30000; marker='nav-links' ;;
  esac
  if [ "$code" != "200" ]; then
    bad "$f - HTTP $code"
  elif [ "$size" -lt "$min" ]; then
    bad "$f - only $size bytes, that is not the real file"
  elif ! grep -q "$marker" "$TMP/$f"; then
    bad "$f - downloaded but does not look right"
  else
    ok "$f ($size bytes)"
  fi
done
[ "$FAILED" -eq 0 ] || { say "Stopping - nothing has been changed."; exit 1; }

# ── 2. the check that matters most ──────────────────────────────────────────
# This whole exercise exists because the calculator was noindex. If the file we
# just downloaded is still noindex, publishing it achieves nothing at all and we
# would never notice until the rankings did not move.
say "Checking the calculator page is actually indexable"
if grep -qi 'noindex' "$TMP/cattle-finance-calculator.html"; then
  bad "the calculator page still carries noindex - refusing to publish it"
  exit 1
fi
ok "no noindex on the calculator page"

# and the break-even page must still be noindex, it is behind a password
if grep -qi 'noindex' "$TMP/preview/cattle-break-even.html"; then
  ok "the break-even page is still noindex, as it should be"
else
  bad "the break-even page has LOST its noindex - refusing to publish it"
  exit 1
fi

# ── 3. back up whatever is there now ────────────────────────────────────────
STAMP=$(date +%Y%m%d-%H%M%S)
BK="/var/backups/foothills-seo-$STAMP"
say "Backing up to $BK"
mkdir -p "$BK/preview"
cp -p "$SITE/sitemap.xml" "$BK/" 2>/dev/null
for f in $PUBLIC; do cp -p "$SITE/$f" "$BK/" 2>/dev/null; done
cp -p "$SITE/preview/cattle-break-even.html" "$BK/preview/" 2>/dev/null
note "to undo:  sudo cp -p $BK/*.html $BK/sitemap.xml $SITE/ && sudo cp -p $BK/preview/*.html $SITE/preview/"

# ── 4. install ──────────────────────────────────────────────────────────────
say "Installing"
for f in $PUBLIC sitemap.xml; do
  cp "$TMP/$f" "$SITE/$f" && ok "$f" || bad "$f could not be written"
  chown --reference="$SITE" "$SITE/$f" 2>/dev/null
  chmod 644 "$SITE/$f" 2>/dev/null
done
cp "$TMP/preview/cattle-break-even.html" "$SITE/preview/cattle-break-even.html" \
  && ok "preview/cattle-break-even.html" || bad "break-even page could not be written"
chown --reference="$SITE/preview" "$SITE/preview/cattle-break-even.html" 2>/dev/null
chmod 644 "$SITE/preview/cattle-break-even.html" 2>/dev/null

# ── 5. ask the server, not the disk ─────────────────────────────────────────
say "Checking what the server actually serves"
for f in $PUBLIC; do
  code=$(curl -sS -m 25 -o "$TMP/chk" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/$f" 2>/dev/null)
  if [ "$code" = "200" ] && grep -q 'nav-links' "$TMP/chk" && ! grep -qi 'noindex' "$TMP/chk"; then
    ok "$f - 200, has the site nav, indexable"
  else
    bad "$f - HTTP $code (or missing nav, or still noindex)"
  fi
done

code=$(curl -sS -m 25 -o "$TMP/sm" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/sitemap.xml" 2>/dev/null)
n=$(grep -c '<loc>' "$TMP/sm" 2>/dev/null || echo 0)
if [ "$code" = "200" ] && [ "$n" -ge 28 ]; then
  ok "sitemap.xml - 200, $n urls"
else
  bad "sitemap.xml - HTTP $code, $n urls (expected at least 28)"
fi
# a preview url in a public sitemap would invite Google to a password box
if grep -q '/preview/' "$TMP/sm"; then
  bad "the sitemap contains a preview url - that must not ship"
else
  ok "no preview urls in the sitemap"
fi

say "Checking the password-protected page is still password protected"
code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" \
       "http://127.0.0.1/preview/cattle-break-even.html" 2>/dev/null)
[ "$code" = "401" ] && ok "break-even page still returns 401 without a password" \
                    || bad "break-even page returned $code - IT SHOULD BE 401"

say "Checking nothing else broke"
for f in "" forms.html faq.html cattle-financing-rates.html; do
  code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/$f" 2>/dev/null)
  [ "$code" = "200" ] && ok "/$f still 200" || bad "/$f returned $code"
done

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    Five pages live, sitemap updated, break-even page now has the site\n'
  printf '    header and footer.\n\n'
  printf '      https://%s/cattle-finance-calculator.html\n' "$HOST"
  printf '      https://%s/cattle-loan-calculator-canada.html\n' "$HOST"
  printf '      https://%s/feeder-cattle-financing-calculator.html\n' "$HOST"
  printf '      https://%s/livestock-loan-calculator-western-canada.html\n' "$HOST"
  printf '      https://%s/cost-to-finance-cattle-alberta.html\n\n' "$HOST"
  printf '    Next - resubmit the sitemap in Search Console once the domain is verified.\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To undo:  sudo cp -p %s/*.html %s/sitemap.xml %s/ && sudo cp -p %s/preview/*.html %s/preview/\n\n' \
    "$BK" "$BK" "$SITE" "$BK" "$SITE"
fi
exit 0
