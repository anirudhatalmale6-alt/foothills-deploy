#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - add the "Powered by SiteBuilder360" footer credit
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-credit.sh -o /tmp/fh-credit.sh && sudo sh /tmp/fh-credit.sh
#
#  Edits the pages in place rather than downloading replacements, so it cannot
#  undo anything else that has been deployed since.
#
#  This site has TWO footer markups - the home page uses footer-bottom and every
#  other page uses pf-bottom - but both end with the same "Proudly serving..."
#  line, so one anchor covers all of them.
#
#  Safe to run twice. Each page is skipped if it already has the credit.
# ─────────────────────────────────────────────────────────────────────────────
set -u

SITE="/var/www/foothills/site"
HOST="foothillslivestock.ca"
ANCHOR='<span>Proudly serving Western Canadian producers since 1996.</span>'

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
note() { printf '    %s\n' "$1"; }
FAILED=0

[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
[ -d "$SITE" ] || { echo "Cannot find $SITE - is this the right machine?"; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

STAMP=$(date +%Y%m%d-%H%M%S)
BK="/var/backups/foothills-credit-$STAMP"
say "Backing up to $BK"
mkdir -p "$BK" || exit 1
cp -p "$SITE"/*.html "$BK"/ 2>/dev/null
note "to undo:  sudo cp -p $BK/*.html $SITE/"

# The credit itself. Same muted colour and hover behaviour as the Sitemap link
# already in that row, so it reads as part of the footer rather than bolted on.
CREDIT='<a href="https://sitebuilder360.com/" target="_blank" rel="noopener" style="color:#7a7468;text-decoration:none;font-size:.84rem;opacity:.7;transition:opacity .2s" onmouseover="this.style.opacity=&apos;1&apos;" onmouseout="this.style.opacity=&apos;.7&apos;">Powered by SiteBuilder360</a>'

say "Adding the credit"
ADDED=0; HAD=0; MISS=0
for f in "$SITE"/*.html "$SITE"/preview/*.html; do
  [ -f "$f" ] || continue
  n=$(basename "$f")
  if grep -q 'sitebuilder360\.com' "$f"; then HAD=$((HAD+1)); continue; fi
  if ! grep -q 'Proudly serving Western Canadian producers since 1996\.' "$f"; then
    MISS=$((MISS+1)); note "no footer line in $n - skipped"; continue
  fi
  # awk, not sed - the credit contains slashes, ampersands and quotes, and one
  # page with an odd character silently getting nothing is exactly the failure
  # that is hard to notice afterwards.
  awk -v anchor="$ANCHOR" -v credit="$CREDIT" '
    { line = $0
      p = index(line, anchor)
      if (!done && p > 0) {
        printf "%s%s%s\n", substr(line, 1, p + length(anchor) - 1), credit, substr(line, p + length(anchor))
        done = 1
        next
      }
      print
    }
  ' "$f" > "$TMP/out" && cp "$TMP/out" "$f"
  if grep -q 'sitebuilder360\.com' "$f"; then ADDED=$((ADDED+1)); else bad "could not add it to $n"; fi
done
ok "$ADDED page(s) credited, $HAD already had it, $MISS had no footer line"

say "Checking the server"
SERVED=0; TOTAL=0
for f in "$SITE"/*.html; do
  n=$(basename "$f"); TOTAL=$((TOTAL+1))
  curl -sS -m 20 -o "$TMP/c" -H "Host: $HOST" "http://127.0.0.1/$n" 2>/dev/null
  grep -q 'sitebuilder360\.com' "$TMP/c" && SERVED=$((SERVED+1))
done
[ "$SERVED" -eq "$TOTAL" ] && ok "all $TOTAL pages serve the credit" || bad "$SERVED of $TOTAL pages serve it"

# A credit that links nowhere is worse than none. Check the target answers.
code=$(curl -sSL -m 25 -o /dev/null -w '%{http_code}' "https://sitebuilder360.com/" 2>/dev/null)
[ "$code" = "200" ] && ok "sitebuilder360.com answers 200" || bad "sitebuilder360.com returned $code"

code=$(curl -sS -m 20 -o "$TMP/h" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/" 2>/dev/null)
if [ "$code" = "200" ] && grep -q '</html>' "$TMP/h"; then ok "home page still complete"; else bad "home page returned $code"; fi

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    The credit is in the footer of every page, opening in a new tab.\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To undo:  sudo cp -p %s/*.html %s/\n\n' "$BK" "$SITE"
fi
exit 0
