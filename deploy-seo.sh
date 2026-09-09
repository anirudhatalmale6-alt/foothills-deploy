#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - deploy the eight new SEO pages, LIVE
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-seo.sh -o /tmp/fh-seo.sh && sudo sh /tmp/fh-seo.sh
#
#  Safe to run more than once. Every step is checked, and the footer edit is
#  guarded so a second run cannot duplicate the links.
# ─────────────────────────────────────────────────────────────────────────────
set -u

RAW="https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/site"
SITE="/var/www/foothills/site"

PAGES="livestock-financing-alberta.html
ranch-financing-western-canada.html
feeder-association-alberta.html
cattle-financing-canada.html
livestock-financing-manitoba.html
cattle-financing-rates.html
first-time-rancher-financing.html
backgrounding-cattle-financing.html"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
note() { printf '    %s\n' "$1"; }
FAILED=0

[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
[ -d "$SITE" ] || { echo "Cannot find $SITE - is this the right machine?"; exit 1; }

# ── 1. back up what we are about to touch ───────────────────────────────────
STAMP=$(date +%Y%m%d-%H%M%S)
BK="/var/backups/foothills-seo-$STAMP"
say "Backing up the current pages to $BK"
mkdir -p "$BK" || exit 1
cp -p "$SITE"/*.html "$BK"/ 2>/dev/null
cp -p "$SITE"/sitemap.xml "$BK"/ 2>/dev/null
note "$(ls -1 "$BK" | wc -l) files copied. If anything goes wrong:"
note "  sudo cp -p $BK/*.html $BK/sitemap.xml $SITE/"

# ── 2. download the new pages ───────────────────────────────────────────────
# curl -o writes whatever it gets, INCLUDING a 404 page, straight over the
# target. So every file is fetched to a temp name, checked for size and for
# actually being one of our pages, and only then moved into place.
say "Downloading the eight new pages"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

for f in $PAGES sitemap.xml; do
  code=$(curl -sSL -m 90 -o "$TMP/$f" -w '%{http_code}' "$RAW/$f" 2>/dev/null)
  size=$(wc -c < "$TMP/$f" 2>/dev/null || echo 0)
  case "$f" in
    *.xml)  marker='<urlset' ;;
    *)      marker='Foothills Livestock Co-op' ;;
  esac
  if [ "$code" != "200" ]; then
    bad "$f - HTTP $code"
  elif [ "$size" -lt 2000 ]; then
    bad "$f - only $size bytes, that is not the real file"
  elif ! grep -q "$marker" "$TMP/$f"; then
    bad "$f - downloaded but does not look like a Foothills file"
  else
    ok "$f ($size bytes)"
  fi
done

if [ "$FAILED" -gt 0 ]; then
  say "Stopping - $FAILED file(s) did not download properly. Nothing has been changed."
  exit 1
fi

# ── 3. install ──────────────────────────────────────────────────────────────
say "Installing into $SITE"
for f in $PAGES sitemap.xml; do
  cp "$TMP/$f" "$SITE/$f" && ok "$f" || bad "$f could not be written"
done
chown --reference="$SITE" "$SITE"/*.html "$SITE"/sitemap.xml 2>/dev/null
chmod 644 "$SITE"/*.html "$SITE"/sitemap.xml 2>/dev/null

# ── 4. footer links on the existing pages ───────────────────────────────────
# The three new links go into the footer "Financing" column on every page, so
# the new pages actually have something pointing at them.
#
# The grep is not decoration. Without it a second run appends the same three
# links again, and a third run a third time - the sed anchor is still present
# after the insert. Guard first, edit second.
say "Adding the new links to the footer on every page"
ADDED=0; SKIPPED=0
for f in "$SITE"/*.html; do
  if grep -q 'href="livestock-financing-alberta.html"' "$f"; then
    SKIPPED=$((SKIPPED+1)); continue
  fi
  grep -q 'href="livestock-financing-british-columbia.html">Financing in BC</a>' "$f" || continue
  sed -i 's#<a href="livestock-financing-british-columbia.html">Financing in BC</a>#&<a href="livestock-financing-alberta.html">Financing in Alberta</a><a href="ranch-financing-western-canada.html">Ranch Financing</a><a href="cattle-financing-rates.html">Rates \&amp; Costs</a>#' "$f" \
    && ADDED=$((ADDED+1))
done
ok "$ADDED page(s) updated, $SKIPPED already had the links"

# ── 5. prove it from the server itself ──────────────────────────────────────
# Asking the local web server is the only way to know nginx is really serving
# these, rather than that a file exists on disk.
say "Checking the server actually serves them"
HOST="foothillslivestock.ca"
for f in $PAGES; do
  code=$(curl -sS -m 25 -o "$TMP/check" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/$f" 2>/dev/null)
  if [ "$code" = "200" ] && grep -q '<h1' "$TMP/check"; then
    ok "$f"
  else
    bad "$f - HTTP $code from the server"
  fi
done

code=$(curl -sS -m 25 -o "$TMP/sm" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/sitemap.xml" 2>/dev/null)
n=$(grep -c '<loc>' "$TMP/sm" 2>/dev/null || echo 0)
if [ "$code" = "200" ] && [ "$n" -ge 23 ]; then ok "sitemap.xml - $n urls"; else bad "sitemap.xml - HTTP $code, $n urls"; fi

# The whole point of a self-check is that it can fail. Confirm the site itself
# is still fine, not just the new pages.
code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/" 2>/dev/null)
[ "$code" = "200" ] && ok "home page still 200" || bad "HOME PAGE IS $code - restore from $BK"

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    Everything above passed. The eight new pages are live.\n\n'
  printf '    Next: submit the updated sitemap in Google Search Console -\n'
  printf '      https://foothillslivestock.ca/sitemap.xml\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To put everything back:  sudo cp -p %s/*.html %s/sitemap.xml %s/\n\n' "$BK" "$BK" "$SITE"
fi
exit 0
