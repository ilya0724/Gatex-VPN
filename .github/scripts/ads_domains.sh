#!/usr/bin/env bash
# Builds app/assets/routing/ads.txt from v2fly/domain-list-community
# (category-ads-all and its include: lists). Run before flutter build/test.
# If any list cannot be fetched, the committed ads.txt is kept (exit 0 when it
# holds at least 500 domains). ADS_BASE_URL overrides the source, for tests.
set -euo pipefail

base="${ADS_BASE_URL:-https://raw.githubusercontent.com/v2fly/domain-list-community/master/data}"
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
  local name="$1" attr="$2" depth="$3" body inc iattr
  case "$seen" in *" $name@$attr "*) return ;; esac
  seen="$seen$name@$attr "
  # collect runs in pipe subshells, so a failure is recorded in a file, not a variable.
  body="$(fetch "$name")" || { echo "warn: cannot fetch $name" >&2; : > "$tmp/failed"; return 0; }
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

# Lines are dropped with sed, not grep -v: grep -v exits 1 on empty input (a
# failed fetch) and pipefail would stop the script before the fallback below.
{
  collect category-ads-all "" 1
} | sed 's/\r$//' \
  | sed 's/[[:space:]]*#.*$//' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | sed '/^$/d; /^include:/d; /^regexp:/d; /^keyword:/d' \
  | sed 's/^domain://; s/^full://' \
  | sed 's/[[:space:]]*@.*$//' \
  | tr 'A-Z' 'a-z' \
  | sort -u > "$tmp/ads.txt"

# A partial download must not replace the committed list, and CI must not fail
# only because GitHub raw is unreachable while a usable list is committed.
if [ -e "$tmp/failed" ]; then
  echo "warn: cannot reach v2fly list, keeping committed ads.txt" >&2
  kept=0
  [ -f "$out" ] && kept=$(wc -l < "$out")
  if [ "$kept" -lt 500 ]; then
    echo "ads_domains: committed $out has $kept domains, expected at least 500" >&2
    exit 1
  fi
  exit 0
fi

lines=$(wc -l < "$tmp/ads.txt")
if [ "$lines" -lt 500 ]; then
  echo "ads_domains: only $lines domains, expected at least 500" >&2
  exit 1
fi
mkdir -p "$(dirname "$out")"
cp "$tmp/ads.txt" "$out"
echo "ads_domains: $lines domains -> $out"
