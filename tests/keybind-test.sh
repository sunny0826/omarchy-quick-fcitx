#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Unit tests for scripts/install-keybind (bindings.lua managed block).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KB="$ROOT/scripts/install-keybind"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BINDINGS="$TMP/bindings.lua"
export QUICK_FCITX_BINDINGS="$BINDINGS"
export QUICK_FCITX_SKIP_RELOAD=1

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; }

assert_eq() {
  if [[ $1 == "$2" ]]; then pass; else fail "$3 (want='$1' got='$2')"; fi
}

assert_rc() {
  if [[ $1 == "$2" ]]; then pass; else fail "$3 (want_rc=$1 got_rc=$2)"; fi
}

ORIG='-- user config
o.bind("SUPER + B", nil, "something")
-- <<< vokie hotkeys <<<'

printf '%s\n' "$ORIG" > "$BINDINGS"

# status on a clean file
out="$("$KB" --status)"
assert_eq "disabled" "$out" "status without block"

# enable
"$KB" --enable >/dev/null 2>&1
assert_rc 0 $? "enable exits 0"
begins="$(grep -cF -- '>>> sunny0826.quick-fcitx (managed) >>>' "$BINDINGS")"
ends="$(grep -cF -- '<<< sunny0826.quick-fcitx <<<' "$BINDINGS")"
assert_eq "1" "$begins" "single BEGIN after enable"
assert_eq "1" "$ends" "single END after enable"
grep -q 'scripts/fcitxctl. toggle\|/fcitxctl. toggle' "$BINDINGS" \
  && pass || fail "block embeds fcitxctl path"
grep -q 'hl.on("input.keyboard.key"' "$BINDINGS" && pass || fail "block registers key hook"
grep -q 'o.bind("SUPER + B"' "$BINDINGS" && pass || fail "user content preserved"
grep -q 'vokie' "$BINDINGS" && pass || fail "vokie marker preserved"

out="$("$KB" --status)"
assert_eq "enabled" "$out" "status after enable"

# idempotency
"$KB" --enable >/dev/null 2>&1
assert_rc 0 $? "second enable exits 0"
begins="$(grep -cF -- '>>> sunny0826.quick-fcitx (managed) >>>' "$BINDINGS")"
assert_eq "1" "$begins" "single BEGIN after double enable"

# backups exist
ls "$BINDINGS".bak.* >/dev/null 2>&1 && pass || fail "enable creates backups"

# remove
"$KB" --remove >/dev/null 2>&1
assert_rc 0 $? "remove exits 0"
grep -qF -- 'sunny0826.quick-fcitx' "$BINDINGS" && fail "block fully removed" || pass
grep -q 'o.bind("SUPER + B"' "$BINDINGS" && pass || fail "user content preserved after remove"

out="$("$KB" --status)"
assert_eq "disabled" "$out" "status after remove"

# remove again is a no-op
"$KB" --remove >/dev/null 2>&1
assert_rc 0 $? "second remove is a no-op"

# corrupt marker handling: BEGIN without END must not run the strip
printf 'garbage\n%s\ntrailing content\n' '-- >>> sunny0826.quick-fcitx (managed) >>>' > "$BINDINGS"
"$KB" --enable >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne_checked=1
if [[ $rc != 0 ]]; then pass; else fail "enable refuses corrupt markers"; fi
grep -q 'trailing content' "$BINDINGS" && pass || fail "corrupt file left untouched"

echo "----"
echo "passed: $PASS  failed: $FAIL"
(( FAIL == 0 ))
