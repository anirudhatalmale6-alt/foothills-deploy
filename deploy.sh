#!/bin/sh
# Foothills Livestock - founding year 1996 everywhere, 30 years in business,
# logo artwork reading EST. 1996, and a fresh cache-buster on the logo.
# Safe to run more than once. Running it twice changes nothing.

set -e
BASE=https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main
TMP=/tmp/foothills-logo-new.png

echo "1/3  downloading the logo artwork ..."
curl -sSLf "$BASE/foothills-logo.png" -o "$TMP"

# refuse to install anything that is not a real, complete PNG
if ! head -c 4 "$TMP" | od -An -c | grep -q '211   P   N   G'; then
  echo "ABORTED - the downloaded file is not a PNG."; rm -f "$TMP"; exit 1
fi
SIZE=$(wc -c < "$TMP")
if [ "$SIZE" -lt 500000 ]; then
  echo "ABORTED - the downloaded PNG is only $SIZE bytes, that is truncated."; rm -f "$TMP"; exit 1
fi

echo "2/3  installing the logo ..."
for d in /var/www/foothills/site/assets /var/www/foothills/backend/site/assets; do
  if [ -d "$d" ]; then
    cp "$TMP" "$d/foothills-logo.png"
    echo "     updated $d/foothills-logo.png"
  fi
done
rm -f "$TMP"

echo "3/3  updating the page text ..."
find /var/www/foothills/site /var/www/foothills/backend/views -name '*.html' -exec sed -i \
 -e 's/"foundingDate": "1997"/"foundingDate": "1996"/g' \
 -e 's/1998/1996/g' \
 -e 's/Proudly serving Alberta producers/Proudly serving Western Canadian producers/g' \
 -e 's/Serving Alberta Producers Since/Serving Western Canadian Producers Since/g' \
 -e 's/Financing for Alberta Producers/Financing for Western Canadian Producers/g' \
 -e 's/Nearly 30 years/30 years/g' \
 -e 's/over 28 years/over 30 years/g' \
 -e 's/Over 28 Years/Over 30 Years/g' \
 -e 's/28+ years/30+ years/g' \
 -e 's/28+ Years/30+ Years/g' \
 -e 's/data-count="28"/data-count="30"/g' \
 -e 's/<strong>28+<\/strong>/<strong>30+<\/strong>/g' \
 -e 's/foothills-logo\.png\(?v=[0-9]*\)\?/foothills-logo.png?v=5/g' {} +

echo ""
echo "----- check -----"
echo "pages still saying 1998 (should be 0)  : $(grep -rl 1998 /var/www/foothills/site --include='*.html' 2>/dev/null | wc -l)"
echo "pages saying 1996                      : $(grep -rl 1996 /var/www/foothills/site --include='*.html' 2>/dev/null | wc -l)"
echo "pages still saying 28 years (should be 0): $(grep -rlE '28\+? ?[Yy]ears' /var/www/foothills/site --include='*.html' 2>/dev/null | wc -l)"
echo "logo cache-buster v=5 on pages          : $(grep -rl 'foothills-logo.png?v=5' /var/www/foothills/site --include='*.html' 2>/dev/null | wc -l)"
echo "-----------------"
echo "Done. Hard-refresh the site with Ctrl+Shift+R."
