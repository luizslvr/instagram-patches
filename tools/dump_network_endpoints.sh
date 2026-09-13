#!/usr/bin/env bash
# dump_network_endpoints.sh — list the Instagram API paths compiled into an APK's dex.
#
# The network-layer patches (HideCommentsPatch, DisableLikePatch) block URIs by substring, so the
# substrings must be confirmed against the specific APK being patched. This extracts every
# /api/... path-shaped literal from classes*.dex so you can check the endpoints are still spelled
# the way the patch assumes.
#
# Usage:
#   tools/dump_network_endpoints.sh Instagram.apk [pattern]
#   tools/dump_network_endpoints.sh Instagram.apk comments
#
# Requires: unzip, strings (binutils), sort.
set -euo pipefail

APK="${1:?usage: dump_network_endpoints.sh <apk> [grep-pattern]}"
PATTERN="${2:-}"

command -v unzip   >/dev/null || { echo "need unzip"   >&2; exit 1; }
command -v strings >/dev/null || { echo "need strings (binutils)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unzip -q -o "$APK" 'classes*.dex' -d "$TMP" || {
    echo "!! no classes*.dex inside $APK" >&2; exit 1; }

echo "== scanning $(find "$TMP" -name 'classes*.dex' | wc -l) dex file(s) from $APK =="

# Instagram API paths are literals like /api/v1/media/{id}/like/. Pull every /api/... token and
# keep the ones that look like a path (at least two segments, no spaces).
# A dex string pool stores strings length-prefixed, so `strings` normally separates them. But be
# safe: if two path literals ever land on one line, split them before deduping so the greedy regex
# cannot merge them into a single nonsense token.
strings -n 6 "$TMP"/classes*.dex \
    | sed -E 's#(/(api|graphql)/)#\n\1#g' \
    | grep -oE '/(api|graphql|feed|media|direct_v2)[A-Za-z0-9_./{},-]*' \
    | awk 'length($0) > 4' \
    | sort -u \
    > "$TMP/paths.txt"

echo "== $(wc -l < "$TMP/paths.txt") distinct path literals =="
echo

if [[ -n "$PATTERN" ]]; then
    echo "== matching '$PATTERN' =="
    grep -i -- "$PATTERN" "$TMP/paths.txt" || echo "(no path literal contains '$PATTERN')"
else
    echo "== every media-scoped endpoint (where comments/likes live) =="
    grep -E '^/api/v[0-9]+/media/' "$TMP/paths.txt" || echo "(none found)"
    echo
    echo "== comment / like related =="
    grep -iE 'comment|/like|/unlike' "$TMP/paths.txt" || echo "(none found)"
fi
