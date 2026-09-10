#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - install the loan calculator BEHIND A PASSWORD
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-calculator.sh -o /tmp/fh-calc.sh && sudo sh /tmp/fh-calc.sh
#
#  It will ask you to choose a password. Type it into the terminal - do not
#  send it to me in chat.
#
#  ORDER MATTERS HERE. The first version of this script installed the page and
#  THEN set up the lock, which meant that aborting anywhere in between - or just
#  pressing Ctrl-C at the password prompt - left the page publicly readable.
#  That is exactly the thing this script exists to prevent, so it now does it the
#  other way round: build the lock, prove it works on a throwaway file, and only
#  then put the real page behind it. If anything fails at any point, the preview
#  folder is emptied on the way out.
#
#  It also edits the nginx config, which is the one thing here that could take
#  the site down. So it backs the config up, runs nginx's own syntax check
#  BEFORE reloading, puts the original straight back if that check fails, and
#  finishes by proving the public site still answers.
# ─────────────────────────────────────────────────────────────────────────────
set -u

RAW="https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main"
SITE="/var/www/foothills/site"
PAGE="livestock-loan-calculator.html"
PROBE=".lock-probe.html"
PWFILE="/etc/nginx/foothills-preview.htpasswd"
MARKER="# foothills-preview-auth"
HOST="foothillslivestock.ca"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
note() { printf '    %s\n' "$1"; }
FAILED=0
INSTALLED=no

# Anything that leaves this script early must not leave a readable page behind.
cleanup() {
  rm -rf "$TMP" 2>/dev/null
  if [ "$INSTALLED" != "yes" ] && [ -d "$SITE/preview" ]; then
    rm -f "$SITE/preview/$PAGE" "$SITE/preview/$PROBE" 2>/dev/null
    rmdir "$SITE/preview" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM HUP

[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
[ -d "$SITE" ] || { echo "Cannot find $SITE - is this the right machine?"; exit 1; }
command -v nginx >/dev/null 2>&1 || { echo "nginx is not on this machine."; exit 1; }

TMP=$(mktemp -d) || exit 1

# ── 0. clear anything an earlier run left exposed ───────────────────────────
if [ -f "$SITE/preview/$PAGE" ]; then
  say "Found a calculator already sitting in $SITE/preview"
  code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/preview/$PAGE" 2>/dev/null)
  if [ "$code" = "401" ]; then
    note "it is already password protected - it will be replaced with the current version"
  else
    note "it answers $code, so it is NOT protected. Removing it now, before anything else."
    rm -f "$SITE/preview/$PAGE"
    ok "removed - that URL is a 404 again"
  fi
fi

# ── 1. fetch, but do NOT install yet ────────────────────────────────────────
say "Downloading the calculator (to a temp folder, not to the website)"
code=$(curl -sSL -m 90 -o "$TMP/$PAGE" -w '%{http_code}' "$RAW/site/preview/$PAGE" 2>/dev/null)
size=$(wc -c < "$TMP/$PAGE" 2>/dev/null || echo 0)
if [ "$code" != "200" ] || [ "$size" -lt 20000 ] || ! grep -q 'calcForm' "$TMP/$PAGE"; then
  echo "    Download failed (HTTP $code, $size bytes). Nothing has been changed."
  exit 1
fi
ok "$PAGE ($size bytes) - held in $TMP for now"

# ── 2. the password ─────────────────────────────────────────────────────────
say "Setting the password"
printf '    Username will be: foothills\n'
printf '    Password (it will not appear as you type): '
stty -echo 2>/dev/null; read -r PASS; stty echo 2>/dev/null; printf '\n'
printf '    Again: '
stty -echo 2>/dev/null; read -r PASS2; stty echo 2>/dev/null; printf '\n'

[ -n "$PASS" ] || { echo "    Empty password - stopping. Nothing has been published."; exit 1; }
[ "$PASS" = "$PASS2" ] || { echo "    They did not match - stopping. Nothing has been published."; exit 1; }

# htpasswd is not installed everywhere, so fall back through two other ways of
# producing a hash nginx understands.
HASH=""
if command -v htpasswd >/dev/null 2>&1; then
  HASH=$(printf '%s' "$PASS" | htpasswd -niB foothills 2>/dev/null | head -1)
  [ -n "$HASH" ] && note "hash made with htpasswd (bcrypt)"
fi
if [ -z "$HASH" ] && command -v openssl >/dev/null 2>&1; then
  H=$(openssl passwd -apr1 "$PASS" 2>/dev/null)
  [ -n "$H" ] && HASH="foothills:$H" && note "hash made with openssl (apr1)"
fi
if [ -z "$HASH" ] && command -v python3 >/dev/null 2>&1; then
  H=$(PASS="$PASS" python3 -c 'import crypt,os;print(crypt.crypt(os.environ["PASS"],crypt.mksalt(crypt.METHOD_SHA512)))' 2>/dev/null)
  [ -n "$H" ] && HASH="foothills:$H" && note "hash made with python3 (sha512-crypt)"
fi
[ -n "$HASH" ] || { echo "    Could not create a password hash on this machine. Send me this output."; exit 1; }

printf '%s\n' "$HASH" > "$PWFILE" || exit 1
# The nginx WORKER reads this file, not the master, so it has to be readable by
# the worker user. A bad mode here is a 500 on the page, not an obvious error.
NGX_USER=$(nginx -T 2>/dev/null | sed -n 's/^ *user  *\([a-z_][a-z_0-9-]*\).*;/\1/p' | head -1)
[ -n "$NGX_USER" ] || NGX_USER=www-data
if id -u "$NGX_USER" >/dev/null 2>&1; then
  chown root:"$(id -gn "$NGX_USER")" "$PWFILE" && chmod 640 "$PWFILE"
  note "readable by root and by $NGX_USER (mode 640)"
else
  chmod 644 "$PWFILE"
  note "could not identify the nginx user, so the file is mode 644"
fi
ok "password file written to $PWFILE"
PASS=""; PASS2=""

# ── 3. the nginx location block ─────────────────────────────────────────────
say "Finding the nginx config for this site"
CONFS=$(grep -rl -- "$SITE" /etc/nginx/ 2>/dev/null | grep -v htpasswd)
COUNT=$(printf '%s\n' "$CONFS" | grep -c . )
if [ "$COUNT" -ne 1 ]; then
  echo "    Expected exactly one config mentioning $SITE, found $COUNT:"
  printf '%s\n' "$CONFS" | sed 's/^/      /'
  echo "    Not going to guess. Send me this list and I will tell you which one."
  exit 1
fi
CONF="$CONFS"
ok "$CONF"

if grep -q "$MARKER" "$CONF"; then
  note "the protected block is already in there - leaving the config alone"
else
  ROOTS=$(grep -cE "^[[:space:]]*root[[:space:]]+${SITE}/?[[:space:]]*;" "$CONF")
  if [ "$ROOTS" -ne 1 ]; then
    echo "    Expected one 'root $SITE;' line in that file, found $ROOTS."
    echo "    Stopping rather than editing the wrong server block."
    exit 1
  fi
  CBK="$CONF.before-preview-$(date +%Y%m%d-%H%M%S)"
  cp -p "$CONF" "$CBK" || exit 1
  ok "config backed up to $CBK"

  # Inserted immediately after the root line, which is inside the right server
  # block by definition. Hunting for the block's closing brace with sed is the
  # fragile way to do this.
  awk -v marker="$MARKER" -v site="$SITE" '
    { print }
    !done && $0 ~ ("^[ \t]*root[ \t]+" site "/?[ \t]*;") {
      print ""
      print "    " marker " - preview pages, password protected. Remove this block to unpublish."
      print "    location ^~ /preview/ {"
      print "        auth_basic \"Foothills preview\";"
      print "        auth_basic_user_file /etc/nginx/foothills-preview.htpasswd;"
      print "        add_header X-Robots-Tag \"noindex, nofollow\" always;"
      print "        try_files $uri $uri/ =404;"
      print "    }"
      done = 1
    }
  ' "$CBK" > "$TMP/newconf" || exit 1

  cp "$TMP/newconf" "$CONF" || exit 1

  # nginx's own opinion, before anything is reloaded.
  if nginx -t 2>"$TMP/nginxt"; then
    ok "nginx -t passed"
  else
    cp -p "$CBK" "$CONF"
    echo "    nginx rejected the new config, so the ORIGINAL HAS BEEN PUT BACK."
    echo "    Nothing was reloaded and the site is untouched. nginx said:"
    sed 's/^/      /' "$TMP/nginxt"
    exit 1
  fi

  if nginx -s reload 2>/dev/null || systemctl reload nginx 2>/dev/null; then
    ok "nginx reloaded"
  else
    echo "    Could not reload nginx. The config is valid but the lock is not live,"
    echo "    so the calculator has NOT been published. Send me this output."
    exit 1
  fi
  sleep 2
fi

# ── 4. prove the lock works BEFORE the real page goes anywhere near it ──────
# A throwaway file with nothing in it. If this is not refused, the real page
# never gets written.
say "Testing the lock with a throwaway file first"
mkdir -p "$SITE/preview" || exit 1
chown --reference="$SITE" "$SITE/preview" 2>/dev/null
chmod 755 "$SITE/preview"
printf 'lock probe\n' > "$SITE/preview/$PROBE"
chmod 644 "$SITE/preview/$PROBE"
sleep 1

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/preview/$PROBE" 2>/dev/null)
rm -f "$SITE/preview/$PROBE"
if [ "$code" = "401" ]; then
  ok "the throwaway file was refused with 401 - the lock is working"
else
  echo "    The throwaway file answered $code instead of 401."
  echo "    The lock is NOT working, so the calculator has NOT been published."
  echo "    Nothing is exposed. Send me this output."
  exit 1
fi

# ── 5. now, and only now, install the real page ─────────────────────────────
say "Installing the calculator behind the lock"
cp "$TMP/$PAGE" "$SITE/preview/$PAGE" || exit 1
chown --reference="$SITE" "$SITE/preview/$PAGE" 2>/dev/null
chmod 644 "$SITE/preview/$PAGE"
INSTALLED=yes
ok "installed to $SITE/preview/"

# ── 6. prove it, including that the public site is unharmed ────────────────
say "Final checks"
URL="http://127.0.0.1/preview/$PAGE"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "$URL" 2>/dev/null)
[ "$code" = "401" ] && ok "without a password: 401, correctly refused" \
                    || bad "without a password it returned $code - it should be 401"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" -u "foothills:definitely-not-the-password" "$URL" 2>/dev/null)
[ "$code" = "401" ] && ok "with a WRONG password: 401, correctly refused" \
                    || bad "a wrong password returned $code - it should be 401"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/" 2>/dev/null)
[ "$code" = "200" ] && ok "public home page still 200" \
                    || bad "HOME PAGE IS $code - restore the config backup listed above"

code=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/livestock-financing-alberta.html" 2>/dev/null)
[ "$code" = "200" ] && ok "public Alberta page still 200" || bad "Alberta page is $code"

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    The calculator is installed and locked.\n\n'
  printf '      https://foothillslivestock.ca/preview/%s\n' "$PAGE"
  printf '      username: foothills\n'
  printf '      password: the one you just typed\n\n'
  printf '    It is not in the sitemap and it carries a noindex header, so Google\n'
  printf '    will not list it. To take the lock off later, delete the block marked\n'
  printf '    "%s" in %s and reload nginx.\n\n' "$MARKER" "$CONF"
else
  printf '    %d check(s) failed - send me this output.\n\n' "$FAILED"
fi
exit 0
