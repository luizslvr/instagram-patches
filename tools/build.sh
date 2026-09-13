#!/usr/bin/env bash
# build.sh — pre-flight the Instagram patches against a real APK, then build only if they pass.
#
# The patches in this bundle were authored against published community sources, not against the
# APK you are about to patch. Every anchor below therefore has to be confirmed on the real file
# before a build is worth anything. This script runs all three checkers, stops on anything missing,
# and only then invokes Gradle.
#
# Usage:
#   tools/build.sh Instagram.apk                 # check, then build
#   tools/build.sh Instagram.apk --check-only    # checks only, no Gradle
#   tools/build.sh Instagram.apk --force         # build even if checks fail (you were warned)
#   tools/build.sh Instagram.apk --patch         # after a successful build, also patch the APK
#   tools/build.sh Instagram.apk --install       # patch and install to a connected device
#
# Exit codes: 0 ok, 1 checks failed, 2 bad invocation / missing prerequisite.
set -euo pipefail

# ---------------------------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------------------------
APK=""
CHECK_ONLY=0
FORCE=0
DO_PATCH=0
DO_INSTALL=0

for arg in "$@"; do
    case "$arg" in
        --check-only) CHECK_ONLY=1 ;;
        --force)      FORCE=1 ;;
        --patch)      DO_PATCH=1 ;;
        --install)    DO_PATCH=1; DO_INSTALL=1 ;;
        -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)           echo "unknown flag: $arg" >&2; exit 2 ;;
        *)            APK="$arg" ;;
    esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if [[ -z "$APK" ]]; then
    echo "usage: tools/build.sh <Instagram.apk> [--check-only|--force|--patch|--install]" >&2
    exit 2
fi
if [[ ! -f "$APK" ]]; then
    echo "!! not a file: $APK" >&2
    exit 2
fi
APK="$(cd "$(dirname "$APK")" && pwd)/$(basename "$APK")"

REPORT_DIR="$REPO/build-reports"
mkdir -p "$REPORT_DIR"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m[ok]\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; }

echo "repo : $REPO"
echo "apk  : $APK  ($(du -h "$APK" | cut -f1))"
echo "reports -> $REPORT_DIR"

FAILURES=0

# ---------------------------------------------------------------------------------------------
# Prerequisite: Java 21+, because the patcher plugin requires it.
# ---------------------------------------------------------------------------------------------
bold "0. prerequisites"
if command -v java >/dev/null; then
    JAVA_MAJOR="$(java -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -1)"
    if [[ -n "$JAVA_MAJOR" && "$JAVA_MAJOR" -ge 21 ]]; then
        ok "java $JAVA_MAJOR"
    else
        bad "java ${JAVA_MAJOR:-?} — the patcher plugin needs 21+"
        FAILURES=$((FAILURES+1))
    fi
else
    bad "java not found (need JDK 21+)"
    FAILURES=$((FAILURES+1))
fi

# ---------------------------------------------------------------------------------------------
# Prerequisite: the Gradle plugin lives on GitHub Packages and requires a read:packages token.
# A token without that scope produces a confusing "plugin not found" much later, so catch it now.
# ---------------------------------------------------------------------------------------------
if [[ "$CHECK_ONLY" -eq 0 ]]; then
    GP="$HOME/.gradle/gradle.properties"
    HAVE_PROP=0
    if [[ -f "$GP" ]] && grep -q '^gpr\.user=' "$GP" && grep -q '^gpr\.key=' "$GP"; then
        HAVE_PROP=1
    fi
    if [[ "$HAVE_PROP" -eq 1 ]]; then
        ok "GitHub Packages credentials found in ~/.gradle/gradle.properties"
    elif [[ -n "${GITHUB_ACTOR:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
        ok "GitHub Packages credentials found in the environment"
    else
        bad "no GitHub Packages credentials"
        echo "        the build cannot resolve app.morphe.patches without them."
        echo "        create a PAT with read:packages:"
        echo "          https://github.com/settings/tokens/new?scopes=read:packages"
        echo "        then either export GITHUB_ACTOR=<user> GITHUB_TOKEN=<pat>"
        echo "        or write both to ~/.gradle/gradle.properties as gpr.user / gpr.key"
        FAILURES=$((FAILURES+1))
    fi
fi

# ---------------------------------------------------------------------------------------------
# Check 1 — string anchors. Hard gate: a fingerprint with no anchor match throws at patch time.
# ---------------------------------------------------------------------------------------------
bold "1. string anchors (hard gate)"
if python3 tools/verify_anchors.py "$APK" > "$REPORT_DIR/anchors.txt" 2>&1; then
    ok "every anchor present"
else
    FAILURES=$((FAILURES+1))
    bad "anchors missing"
fi
# Show only the interesting lines from the report.
grep -E '\[(ok|MISS)\]|RESULT' "$REPORT_DIR/anchors.txt" || true

# ---------------------------------------------------------------------------------------------
# Check 2 — endpoint fragments the network patches block.
# ---------------------------------------------------------------------------------------------
bold "2. blocked endpoint fragments"
bash tools/dump_network_endpoints.sh "$APK" > "$REPORT_DIR/endpoints.txt" 2>&1 || true
MISSING_ENDPOINTS=0
for frag in '/comments/' '/comment_likes/' '/like/' '/unlike/'; do
    if grep -qF -- "$frag" "$REPORT_DIR/endpoints.txt"; then
        ok "present  $frag"
    else
        MISSING_ENDPOINTS=$((MISSING_ENDPOINTS+1))
        warn "absent   $frag   (that patch will not block it)"
    fi
done
if [[ "$MISSING_ENDPOINTS" -gt 0 ]]; then
    FAILURES=$((FAILURES+1))
    echo "        full listing: $REPORT_DIR/endpoints.txt"
fi

# ---------------------------------------------------------------------------------------------
# Check 3 — JSON keys the count patches rename. Same semantics: an absent key is silently a no-op.
# ---------------------------------------------------------------------------------------------
bold "3. JSON count keys"
bash tools/dump_json_keys.sh "$APK"            > "$REPORT_DIR/keys-counts.txt" 2>&1 || true
bash tools/dump_json_keys.sh "$APK" badge      > "$REPORT_DIR/keys-badge.txt"  2>&1 || true
bash tools/dump_json_keys.sh "$APK" --all-counts > "$REPORT_DIR/keys-all.txt" 2>&1 || true

MISSING_KEYS=$(cat "$REPORT_DIR/keys-counts.txt" "$REPORT_DIR/keys-badge.txt" 2>/dev/null \
    | grep -c '\[MISS\]' || true)
MISSING_KEYS="${MISSING_KEYS:-0}"
if [[ "$MISSING_KEYS" -eq 0 ]]; then
    ok "every key in the patch lists is present"
else
    FAILURES=$((FAILURES+1))
    warn "$MISSING_KEYS key(s) in the patch lists are absent from this APK"
    grep -h '\[MISS\]' "$REPORT_DIR/keys-counts.txt" "$REPORT_DIR/keys-badge.txt" || true
fi

echo
echo "  other *_count tokens in this APK that the patch does not cover:"
grep -A99 'candidates the patch may not cover' "$REPORT_DIR/keys-counts.txt" \
    | grep -vE 'candidates the patch may not cover|^--' | sed 's/^/    /' || true

# ---------------------------------------------------------------------------------------------
# Gate
# ---------------------------------------------------------------------------------------------
bold "verdict"
if [[ "$FAILURES" -eq 0 ]]; then
    ok "all checks passed"
elif [[ "$FORCE" -eq 1 ]]; then
    warn "$FAILURES check(s) failed, continuing because --force"
else
    bad "$FAILURES check(s) failed — not building"
    echo
    echo "  Fix the items above (adjust the key/anchor lists in the matching patch file),"
    echo "  or re-run with --force to build anyway, accepting that the affected number or"
    echo "  endpoint will not be hidden."
    exit 1
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo
    echo "  --check-only: stopping before Gradle."
    exit 0
fi

# ---------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------
bold "4. building patches"
./gradlew buildAndroid --console=plain

MPP="$(ls -t patches/build/libs/patches*.mpp 2>/dev/null | head -1 || true)"
if [[ -z "$MPP" ]]; then
    bad "build reported success but no .mpp was produced"
    exit 1
fi
ok "patches bundle: $MPP"

# ---------------------------------------------------------------------------------------------
# Optional: patch the APK
# ---------------------------------------------------------------------------------------------
if [[ "$DO_PATCH" -eq 1 ]]; then
    bold "5. patching"
    JAR="$(ls -t morphe-desktop/build/libs/morphe-desktop*-all.jar 2>/dev/null | head -1 || true)"
    if [[ -z "$JAR" ]]; then
        warn "morphe-desktop is not built; run this once:"
        echo "        git clone -b dev https://github.com/MorpheApp/morphe-desktop"
        echo "        (cd morphe-desktop && ./gradlew build)"
        exit 2
    fi
    OUT="$REPO/instagram-patched.apk"
    ARGS=(patch --patches "$MPP" --out "$OUT" "$APK")
    [[ "$DO_INSTALL" -eq 1 ]] && ARGS+=(--install)
    java -Xms1024m -jar "$JAR" "${ARGS[@]}"
    ok "patched apk: $OUT"
fi

bold "done"
