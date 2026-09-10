#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
#  Foothills Livestock - finish the Google Analytics rollout
#
#  Run on the Foothills VM as:
#      curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-analytics.sh -o /tmp/fh-ga.sh && sudo sh /tmp/fh-ga.sh
#
#  Two things:
#    1. the GA4 tag is in the repo on every page but is only LIVE on the eight
#       new ones - this puts it on the rest
#    2. installs event tracking for phone clicks and application form opens,
#       which is what actually converts on this site, and is measured nowhere
#       at present
#
#  Does not touch the in-house tracker in fh-analytics.js.
#  Safe to run more than once - every edit is guarded.
# ─────────────────────────────────────────────────────────────────────────────
set -u

RAW="https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main"
SITE="/var/www/foothills/site"
GA_ID="G-N7LCB63SMC"
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
BK="/var/backups/foothills-ga-$STAMP"
say "Backing up the current pages to $BK"
mkdir -p "$BK" || exit 1
cp -p "$SITE"/*.html "$BK"/ 2>/dev/null
note "$(ls -1 "$BK" | wc -l) files copied. To undo everything:"
note "  sudo cp -p $BK/*.html $SITE/"

# ── 2. the event script ─────────────────────────────────────────────────────
say "Installing the event tracker"
code=$(curl -sSL -m 60 -o "$TMP/fh-events.js" -w '%{http_code}' "$RAW/site/assets/fh-events.js" 2>/dev/null)
size=$(wc -c < "$TMP/fh-events.js" 2>/dev/null || echo 0)
if [ "$code" != "200" ] || [ "$size" -lt 1500 ] || ! grep -q 'phone_click' "$TMP/fh-events.js"; then
  echo "    Download failed (HTTP $code, $size bytes). Nothing has been changed."
  exit 1
fi
cp "$TMP/fh-events.js" "$SITE/assets/fh-events.js" || exit 1
chown --reference="$SITE/assets" "$SITE/assets/fh-events.js" 2>/dev/null
chmod 644 "$SITE/assets/fh-events.js"
ok "fh-events.js ($size bytes)"

# ── 3. the GA4 tag on every page that is missing it ─────────────────────────
# Written to a file rather than inline so the sed cannot be mangled by quoting.
cat > "$TMP/ga.html" <<'GAEOF'
  <!-- Google tag (gtag.js) -->
  <script async src="https://www.googletagmanager.com/gtag/js?id=G-N7LCB63SMC"></script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-N7LCB63SMC');
  </script>
GAEOF

say "Adding the Google Analytics tag where it is missing"
ADDED=0; HAD=0; SKIP=0
for f in "$SITE"/*.html; do
  if grep -q "$GA_ID" "$f"; then HAD=$((HAD+1)); continue; fi
  if ! grep -q '</head>' "$f"; then SKIP=$((SKIP+1)); note "no </head> in $(basename "$f") - left alone"; continue; fi
  # awk, not sed - a sed replacement holding a multi-line HTML block means
  # escaping newlines, ampersands and the delimiter all at once, and one page
  # with an odd character silently gets no tag.
  #
  # And the line has to be SPLIT at </head>, not inserted before. On these
  # pages the head ends `...}</style></head><body>` all on ONE line, so
  # inserting before the line puts the whole tag INSIDE the stylesheet, where
  # the browser reads it as CSS and never runs it. The file would contain the
  # tag and `gtag` would still be undefined - checked in a browser, which is
  # how this was found.
  awk -v gaf="$TMP/ga.html" '
    !done && index($0, "</head>") {
      n = index($0, "</head>")
      printf "%s", substr($0, 1, n - 1)
      while ((getline line < gaf) > 0) print line
      close(gaf)
      printf "%s\n", substr($0, n)
      done = 1
      next
    }
    { print }
  ' "$f" > "$TMP/page.out" && cp "$TMP/page.out" "$f"

  # Presence of the string is not proof it will run. The block ends with
  # `</script>` and must sit immediately before `</head>`; if it landed inside
  # the <style> that sequence cannot appear.
  # Flattened, because awk leaves a newline between the block's closing
  # </script> and the </head> it was inserted before, so a plain grep for the
  # two adjacent would fail on a file that is actually correct.
  if grep -q "$GA_ID" "$f" && tr -d '\n' < "$f" | grep -q "</script></head>"; then
    ADDED=$((ADDED+1))
  elif grep -q "$GA_ID" "$f"; then
    bad "the tag went into $(basename "$f") but not where it will run - restore from $BK"
  else
    bad "could not add the tag to $(basename "$f")"
  fi
done
ok "$ADDED page(s) gained the tag, $HAD already had it, $SKIP skipped"

# ── 4. load the event script next to the existing tracker ──────────────────
say "Loading the event tracker on every page"
EADD=0; EHAD=0
for f in "$SITE"/*.html "$SITE"/preview/*.html; do
  [ -f "$f" ] || continue
  if grep -q 'fh-events.js' "$f"; then EHAD=$((EHAD+1)); continue; fi
  grep -q 'fh-analytics.js' "$f" || continue
  sed -i 's#<script src="/assets/fh-analytics.js" defer></script>#&\n<script src="/assets/fh-events.js" defer></script>#' "$f" \
    && EADD=$((EADD+1))
done
ok "$EADD page(s) updated, $EHAD already had it"

# ── 5. prove it from the server ─────────────────────────────────────────────
say "Checking the server"
MISSING=0; TOTAL=0
for f in "$SITE"/*.html; do
  n=$(basename "$f"); TOTAL=$((TOTAL+1))
  curl -sS -m 20 -o "$TMP/c" -H "Host: $HOST" "http://127.0.0.1/$n" 2>/dev/null
  grep -q "$GA_ID" "$TMP/c" || { MISSING=$((MISSING+1)); note "no GA tag served on $n"; }
done
[ "$MISSING" -eq 0 ] && ok "all $TOTAL public pages serve the GA tag" || bad "$MISSING of $TOTAL pages still missing it"

code=$(curl -sS -m 20 -o "$TMP/ev" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/assets/fh-events.js" 2>/dev/null)
if [ "$code" = "200" ] && grep -q 'phone_click' "$TMP/ev"; then ok "fh-events.js is served"; else bad "fh-events.js returned $code"; fi

# The site itself has to still work. A tag that breaks a page is worse than no tag.
code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/" 2>/dev/null)
[ "$code" = "200" ] && ok "home page still 200" || bad "HOME PAGE IS $code - undo with the copy command above"

code=$(curl -sS -m 20 -o "$TMP/h" -w '%{http_code}' -H "Host: $HOST" "http://127.0.0.1/forms.html" 2>/dev/null)
if [ "$code" = "200" ] && grep -q '</html>' "$TMP/h"; then ok "forms page still complete"; else bad "forms.html returned $code"; fi

say "Done"
if [ "$FAILED" -eq 0 ]; then
  printf '    Every page now reports to Google Analytics, and phone clicks and\n'
  printf '    application form opens are tracked as events.\n\n'
  printf '    In Google Analytics, mark these as key events so they show up as\n'
  printf '    conversions - Admin, then Events:\n'
  printf '        phone_click      somebody tapped the phone number\n'
  printf '        form_open        somebody opened an application or claim form\n'
  printf '        chat_open        somebody opened the chat widget\n'
  printf '        calculator_use   somebody used the loan calculator\n\n'
  printf '    They appear in the events list within about 24 hours of the first one.\n\n'
else
  printf '    %d check(s) failed. Send me this output.\n' "$FAILED"
  printf '    To undo:  sudo cp -p %s/*.html %s/\n\n' "$BK" "$SITE"
fi
exit 0
