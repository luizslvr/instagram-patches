#!/usr/bin/env bash
# dump_json_keys.sh — find the JSON field names an APK's parser actually handles.
#
# HideCountsPatch works by swapping JSON keys for a bogus one, so the keys it names must be the
# keys Instagram's parser really switches on. This lists the candidate names present in the dex,
# so the lists in HideCountsPatch.kt can be confirmed rather than assumed.
#
# Usage:
#   tools/dump_json_keys.sh Instagram.apk                # the count keys, by category
#   tools/dump_json_keys.sh Instagram.apk badge          # the unread message badge keys
#   tools/dump_json_keys.sh Instagram.apk "follower"     # anything matching a substring
#   tools/dump_json_keys.sh Instagram.apk --all-counts   # every *_count key in the app
#
# Requires: unzip, strings (binutils), sort.
set -euo pipefail

APK="${1:?usage: dump_json_keys.sh <apk> [substring|--all-counts]}"
MODE="${2:-counts}"

command -v unzip   >/dev/null || { echo "need unzip"   >&2; exit 1; }
command -v strings >/dev/null || { echo "need strings (binutils)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unzip -q -o "$APK" 'classes*.dex' -d "$TMP" || {
    echo "!! no classes*.dex inside $APK" >&2; exit 1; }

echo "== scanning $(find "$TMP" -name 'classes*.dex' | wc -l) dex file(s) from $APK =="

# Every snake_case token is a candidate JSON key. Split on the length-prefix bytes the dex string
# pool uses (non-printable, so `strings` already separates them) and keep identifier-shaped tokens.
strings -n 4 "$TMP"/classes*.dex \
    | grep -oE '\b[a-z][a-z0-9_]{3,40}\b' \
    | sort -u \
    > "$TMP/tokens.txt"

echo "== $(wc -l < "$TMP/tokens.txt") distinct snake_case tokens =="
echo

if [[ "$MODE" == "--all-counts" ]]; then
    echo "== every token ending in _count =="
    grep -E '_count$' "$TMP/tokens.txt" || echo "(none)"
    exit 0
fi

if [[ "$MODE" == "badge" ]]; then
    echo "== HideMessageBadgePatch keys: which are present? =="
    for key in unseen_count unread_count pending_requests_total; do
        if grep -qx -- "$key" "$TMP/tokens.txt"; then
            printf '  [ok]   %s\n' "$key"
        else
            printf '  [MISS] %s\n' "$key"
        fi
    done
    echo
    echo "== every other unseen/unread token (candidates the patch may not cover yet) =="
    grep -iE 'unseen|unread|pending_request' "$TMP/tokens.txt" \
        | grep -vE '^(unseen_count|unread_count|pending_requests_total)$' \
        || echo "(none)"
    exit 0
fi

if [[ "$MODE" == "counts" ]]; then
    echo "== HideCountsPatch key lists: which are present? =="
    for key in like_count comment_count repost_count reshare_count share_count \
               play_count view_count save_count \
               follower_count following_count media_count; do
        if grep -qx -- "$key" "$TMP/tokens.txt"; then
            printf '  [ok]   %s\n' "$key"
        else
            printf '  [MISS] %s\n' "$key"
        fi
    done
    echo
    echo "== every other *_count token (candidates the patch may not cover yet) =="
    # The unread/unseen keys are covered too, by HideMessageBadgePatch, so they are excluded here
    # as well. What is left is genuinely uncovered.
    grep -E '_count$' "$TMP/tokens.txt" \
        | grep -vE '^(like_count|comment_count|repost_count|reshare_count|share_count|play_count|view_count|save_count|follower_count|following_count|media_count|unseen_count|unread_count)$' \
        || echo "(none)"
else
    echo "== tokens matching '$MODE' =="
    grep -i -- "$MODE" "$TMP/tokens.txt" || echo "(nothing matches '$MODE')"
fi
