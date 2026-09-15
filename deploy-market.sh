#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - publish the break-even and market timing page
#  into the EXISTING password-protected preview area.
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-market.sh -o /tmp/fh-market.sh && sudo sh /tmp/fh-market.sh
#
#  It makes NO nginx changes. The preview folder is already locked, and this
#  page goes inside that same lock. Last time we touched nginx to build a lock
#  it took four attempts and left a page briefly readable in between; there is
#  no reason to repeat that when the lock already exists.
#
#  THE ORDER MATTERS AND IT IS DELIBERATE:
#    1. prove the preview folder really does demand a password, using a
#       throwaway file that is not the real page
#    2. only if that comes back 401, install the real page
#    3. prove the real page also demands a password
#
#  If step 1 fails nothing is installed at all. The page can never sit
#  unprotected, not even for a second.
#
#  Safe to run twice.
# ─────────────────────────────────────────────────────────────────────────────
set -u

RAW="https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/site"
SITE="/var/www/foothills/site"
PREVIEW="$SITE/preview"
HOST="foothillslivestock.ca"
PAGE="cattle-break-even.html"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
note() { printf '    %s\n' "$1"; }
FAILED=0

[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
[ -d "$SITE" ] || { echo "Cannot find $SITE - is this the right machine?"; exit 1; }

TMP=$(mktemp -d) || exit 1
PROBE=""
cleanup() { rm -rf "$TMP"; [ -n "$PROBE" ] && rm -f "$PROBE"; }
trap cleanup EXIT INT TERM HUP

# ── 1. does the preview folder even exist and is it locked? ─────────────────
say "Proving the preview folder is locked BEFORE putting anything in it"

if [ ! -d "$PREVIEW" ]; then
  bad "$PREVIEW does not exist - the calculator deploy has not been run on this box"
  note "Nothing has been changed. Tell me and I will send the right script."
  exit 1
fi
ok "preview folder exists"

# A throwaway file, not the page. If the lock is broken we have only exposed
# a meaningless string, and we find out before the real page is anywhere near
# the server.
PROBE="$PREVIEW/.lock-probe-$$.html"
printf 'lock probe, delete me\n' > "$PROBE"
chmod 644 "$PROBE"
PROBE_URL="http://127.0.0.1/preview/$(basename "$PROBE")"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "$PROBE_URL" 2>/dev/null)
if [ "$code" = "401" ]; then
  ok "the preview folder asks for a password (probe returned 401)"
else
  bad "probe returned $code, expected 401 - the preview folder is NOT protected"
  note ""
  note "Nothing has been installed. The page is not on the server."
  note "Send me this output and I will fix the lock first."
  exit 1
fi

# and a wrong password must also be refused
code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" \
       -u "foothills:definitely-not-the-password" "$PROBE_URL" 2>/dev/null)
[ "$code" = "401" ] && ok "a wrong password is refused too (401)" \
                    || bad "a wrong password returned $code - it should be 401"

rm -f "$PROBE"; PROBE=""
[ "$FAILED" -eq 0 ] || { say "Stopping. Nothing has been installed."; exit 1; }

# ── 2. fetch, and check what arrived is really the page ─────────────────────
say "Downloading the page"
code=$(curl -sSL -m 90 -o "$TMP/$PAGE" -w '%{http_code}' "$RAW/$PAGE" 2>/dev/null)
size=$(wc -c < "$TMP/$PAGE" 2>/dev/null || echo 0)
if [ "$code" != "200" ]; then
  bad "HTTP $code"
elif [ "$size" -lt 20000 ]; then
  bad "only $size bytes - that is not the real page"
elif ! grep -q 'Break-even sale price' "$TMP/$PAGE"; then
  bad "downloaded but does not contain the calculator"
elif ! grep -q 'NOT investment advice' "$TMP/$PAGE"; then
  bad "downloaded but the disclaimer is missing - refusing to publish it"
else
  ok "$PAGE ($size bytes, calculator and disclaimer both present)"
fi
[ "$FAILED" -eq 0 ] || { say "Stopping. Nothing has been installed."; exit 1; }

# ── 3. install ──────────────────────────────────────────────────────────────
say "Installing"
if [ -f "$PREVIEW/$PAGE" ]; then
  BK="/var/backups/foothills-market-$(date +%Y%m%d-%H%M%S).html"
  cp -p "$PREVIEW/$PAGE" "$BK" && note "previous version saved to $BK"
fi
cp "$TMP/$PAGE" "$PREVIEW/$PAGE" && ok "written" || bad "could not write the page"
chown --reference="$PREVIEW" "$PREVIEW/$PAGE" 2>/dev/null
chmod 644 "$PREVIEW/$PAGE" 2>/dev/null

# ── 4. prove the real page is locked too ────────────────────────────────────
say "Checking the page itself"
URL="http://127.0.0.1/preview/$PAGE"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "$URL" 2>/dev/null)
[ "$code" = "401" ] && ok "without a password it returns 401" \
                    || bad "without a password it returned $code - IT SHOULD BE 401"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" \
       -u "foothills:definitely-not-the-password" "$URL" 2>/dev/null)
[ "$code" = "401" ] && ok "with a wrong password it returns 401" \
                    || bad "a wrong password returned $code - IT SHOULD BE 401"

# the rest of the site must be untouched
code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/" 2>/dev/null)
[ "$code" = "200" ] && ok "the public home page is still 200" \
                    || bad "the home page returned $code"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/forms.html" 2>/dev/null)
[ "$code" = "200" ] && ok "forms.html is still public" || bad "forms.html returned $code"

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    The page is live and locked.\n\n'
  printf '      https://%s/preview/%s\n\n' "$HOST" "$PAGE"
  printf '    It uses the SAME username and password as the loan calculator.\n'
  printf '    If you cannot remember it, tell me and I will send a one-line\n'
  printf '    command to set a fresh one.\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To remove the page entirely:  sudo rm -f %s/%s\n\n' "$PREVIEW" "$PAGE"
fi
exit 0
