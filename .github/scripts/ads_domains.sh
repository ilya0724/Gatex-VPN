#!/usr/bin/env bash
# Builds app/assets/routing/ads.txt from v2fly/domain-list-community
# (category-ads-all plus its direct include: lists). Run before flutter build/test.
set -euo pipefail

base="https://raw.githubusercontent.com/v2fly/domain-list-community/master/data"
out="$(cd "$(dirname "$0")/../.." && pwd)/app/assets/routing/ads.txt"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() { curl -fsSL --retry 3 --retry-delay 2 "$base/$1"; }

# include: lists are followed up to 3 levels deep (category-ads-all -> category-ads
# -> category-ads-<region>); one level alone yields too few domains.
# "include:name @attr" takes only the entries of that list carrying @attr, so
# ordinary domains of big vendors (google.com, 126.com) are not blocked.
seen=" "
collect() { # name attr depth
  local name="$1" attr="$2" depth="$3" body inc iattr rest
  case "$seen" in *" $name@$attr "*) return ;; esac
  seen="$seen$name@$attr "
  body="$(fetch "$name")" || { echo "warn: cannot fetch $name" >&2; return 0; }
  if [ -n "$attr" ]; then
    printf '%s\n' "$body" | grep -E "^[^#]*@$attr([[:space:]]|\$)" | grep -v '^include:' || true
  else
    printf '%s\n' "$body"
  fi
  [ "$depth" -lt 3 ] || return 0
  printf '%s\n' "$body" | sed -n 's/^include:\([^[:space:]]*\)[[:space:]]*\(@\([^[:space:]]*\)\)\{0,1\}.*/\1 \3/p' |
  while read -r inc iattr; do
    [ -n "$inc" ] || continue
    collect "$inc" "${iattr:-$attr}" $((depth + 1))
  done
}

{
  collect category-ads-all "" 1
} | sed 's/\r$//' \
  | sed 's/[[:space:]]*#.*$//' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | grep -v '^$' \
  | grep -v '^include:' \
  | grep -v '^regexp:' \
  | grep -v '^keyword:' \
  | sed 's/^domain://; s/^full://' \
  | sed 's/[[:space:]]*@.*$//' \
  | tr 'A-Z' 'a-z' \
  | sort -u > "$tmp/ads.txt"

lines=$(wc -l < "$tmp/ads.txt")
if [ "$lines" -lt 500 ]; then
  echo "ads_domains: only $lines domains, expected at least 500" >&2
  exit 1
fi
mkdir -p "$(dirname "$out")"
cp "$tmp/ads.txt" "$out"
echo "ads_domains: $lines domains -> $out"
