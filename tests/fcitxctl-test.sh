#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Unit tests for scripts/fcitxctl.
# All external commands (fcitx5-remote, busctl, systemctl, pacman) are stubbed
# through FCITXCTL_* overrides + a prepended PATH, so the suite runs without
# fcitx5, D-Bus, or root — including on CI.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/scripts/fcitxctl"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
STUB_LOG="$TMP/stub.log"
PROFILE="$TMP/profile"
RIME_DIR="$TMP/rime"
IM_DIR="$TMP/im"
export STUB_LOG

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; }

assert_eq() {
  local want="$1" got="$2" msg="$3"
  if [[ $want == "$got" ]]; then pass; else fail "$msg (want='$want' got='$got')"; fi
}

assert_ne() {
  local notwant="$1" got="$2" msg="$3"
  if [[ $notwant != "$got" ]]; then pass; else fail "$msg (got='$got')"; fi
}

assert_rc() {
  local want_rc="$1" got_rc="$2" msg="$3"
  if [[ $want_rc == "$got_rc" ]]; then pass; else fail "$msg (want_rc=$want_rc got_rc=$got_rc)"; fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ $haystack == *"$needle"* ]]; then pass; else fail "$msg (missing '$needle')"; fi
}

assert_log() {
  local needle="$1" msg="$2"
  if grep -qxF -- "$needle" "$STUB_LOG"; then pass; else fail "$msg (log missing '$needle': $(tr '\n' '|' <"$STUB_LOG"))"; fi
}

assert_log_absent() {
  local needle="$1" msg="$2"
  if grep -qxF -- "$needle" "$STUB_LOG"; then fail "$msg (log has '$needle')"; else pass; fi
}

# ----------------------------------------------------------------- stub bins

cat > "$TMP/bin/fcitx5-remote" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
case "${1:-}" in
  --check) [[ "${STUB_RUNNING:-1}" == "1" ]]; exit $? ;;
  -n) echo "${STUB_IM:-}"; exit 0 ;;
  "") echo "${STUB_STATE:-0}"; exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$TMP/bin/busctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
# Master failure switch: with STUB_BUSCTL_RC!=0 the whole bus is down, so
# every call (Restart, group queries, ...) fails like a missing name would.
if [[ ${STUB_BUSCTL_RC:-0} != 0 ]]; then exit "${STUB_BUSCTL_RC}"; fi
case "$*" in
  *AvailableInputMethods*)
    printf '%s\n' "${STUB_AVAIL_RAW}"
    exit 0
    ;;
  *InputMethodGroupInfo*)
    printf '%s\n' "${STUB_GROUP_INFO}"
    exit 0
    ;;
esac
exit 0
EOF

cat > "$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
if [[ ${2:-} == "cat" ]]; then exit "${STUB_CAT_RC:-0}"; fi
exit 0
EOF

cat > "$TMP/bin/pacman" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
if [[ ${1:-} == "-Q" && ${2:-} == "fcitx5-rime" ]]; then
  [[ "${STUB_RIME_PKG:-1}" == "1" ]]; exit $?
fi
exit 0
EOF

chmod +x "$TMP/bin/"*

# ----------------------------------------------------------------- fixtures

BASE_PROFILE='[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=pinyin

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
# Layout=

[Groups/0/Items/1]
# Name
Name=pinyin

[GroupOrder]
0=Default
'

THREE_ITEM_PROFILE='[Groups/0]
Name=Default
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=keyboard-us

[Groups/0/Items/1]
Name=pinyin

[Groups/0/Items/2]
Name=wubi-pinyin

[GroupOrder]
0=Default
'

write_profile() { printf '%s' "$1" > "$PROFILE"; }
write_base() { write_profile "$BASE_PROFILE"; }

# What fcitx5 itself reports as loadable, a(ssssssb) tuples of
# (code, name, generic, addon, layout, locale, enabled). cangjie is
# deliberately absent: its table data is missing on this machine, so fcitx5
# prunes it from the group on the next start.
DEFAULT_AVAIL='a(ssssssb) "keyboard-us" "Keyboard - US" "" "keyboard" "us" "en" true "pinyin" "Pinyin" "" "pinyin" "" "zh_CN" true "shuangpin" "Shuangpin" "" "pinyin" "" "zh_CN" true'
DEFAULT_GROUP_INFO='sa(ss) "us" 2 "keyboard-us" "" "pinyin" ""'

reset_stubs() {
  T_RUNNING=1
  T_STATE=0
  T_IM=""
  T_BUSCTL_RC=0
  T_CAT_RC=0
  T_RIME_PKG=1
  T_AVAIL_RAW="$DEFAULT_AVAIL"
  T_GROUP_INFO="$DEFAULT_GROUP_INFO"
  : > "$STUB_LOG"
}

run_ctl() {
  env \
    STUB_RUNNING="${T_RUNNING:-1}" \
    STUB_STATE="${T_STATE:-0}" \
    STUB_IM="${T_IM:-}" \
    STUB_BUSCTL_RC="${T_BUSCTL_RC:-0}" \
    STUB_CAT_RC="${T_CAT_RC:-0}" \
    STUB_RIME_PKG="${T_RIME_PKG:-1}" \
    STUB_AVAIL_RAW="${T_AVAIL_RAW:-$DEFAULT_AVAIL}" \
    STUB_GROUP_INFO="${T_GROUP_INFO:-$DEFAULT_GROUP_INFO}" \
    FCITXCTL_FCITX_REMOTE="$TMP/bin/fcitx5-remote" \
    FCITXCTL_BUSCTL="$TMP/bin/busctl" \
    FCITXCTL_SYSTEMCTL="$TMP/bin/systemctl" \
    FCITXCTL_FCITX5="$TMP/bin/fcitx5" \
    FCITXCTL_PROFILE="$PROFILE" \
    FCITXCTL_RIME_DIR="$RIME_DIR" \
    FCITXCTL_IM_DIR="$IM_DIR" \
    STUB_LOG="$STUB_LOG" \
    PATH="$TMP/bin:$PATH" \
    "$CTL" "$@"
}

# =========================================================== status mapping

reset_stubs; write_base
T_RUNNING=1 T_STATE=2 T_IM=pinyin
out="$(run_ctl status)"
assert_eq "cn" "$(jq -r .mode <<<"$out")" "status: state=2 pinyin -> cn"
assert_eq "true" "$(jq -r .ready <<<"$out")" "status: cn ready"
assert_eq "pinyin" "$(jq -r .inputMethod <<<"$out")" "status: inputMethod passthrough"

reset_stubs; write_base
T_RUNNING=1 T_STATE=1 T_IM=keyboard-us
out="$(run_ctl status)"
assert_eq "en" "$(jq -r .mode <<<"$out")" "status: state=1 keyboard-us -> en"
assert_eq "true" "$(jq -r .ready <<<"$out")" "status: en ready"

reset_stubs; write_base
T_RUNNING=0
out="$(run_ctl status)"
assert_eq "false" "$(jq -r .ready <<<"$out")" "status: not running -> !ready"
assert_eq "false" "$(jq -r .fcitxRunning <<<"$out")" "status: fcitxRunning false"
assert_contains "$(jq -r .message <<<"$out")" "未运行" "status: not-running message"

reset_stubs; write_base
T_RUNNING=1 T_STATE=2 T_IM=keyboard-us
out="$(run_ctl status)"
assert_eq "en" "$(jq -r .mode <<<"$out")" "status: keyboard-* wins over state=2"

reset_stubs; write_base
T_RUNNING=1 T_STATE=0 T_IM=pinyin
out="$(run_ctl status)"
assert_eq "unknown" "$(jq -r .mode <<<"$out")" "status: state=0 -> unknown"
assert_eq "false" "$(jq -r .ready <<<"$out")" "status: state=0 -> !ready"

# =========================================================== set-cn / set-en

reset_stubs; write_base
run_ctl set-cn >/dev/null 2>&1
assert_rc 0 $? "set-cn exits 0"
assert_log "-s pinyin" "set-cn selects profile DefaultIM"
assert_log "-o" "set-cn activates fcitx"

reset_stubs; write_base
run_ctl set-en >/dev/null 2>&1
assert_rc 0 $? "set-en exits 0"
assert_log "-s keyboard-us" "set-en selects keyboard layout"
assert_log "-c" "set-en deactivates fcitx"

reset_stubs
write_profile '[Groups/0]
Name=Default
Default Layout=us

[Groups/0/Items/0]
Name=keyboard-us

[GroupOrder]
0=Default
'
run_ctl set-cn >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "set-cn without a Chinese IM fails"

# =========================================================== toggle

reset_stubs; write_base
T_RUNNING=1 T_STATE=2 T_IM=pinyin
run_ctl toggle >/dev/null 2>&1
assert_rc 0 $? "toggle from cn exits 0"
assert_log "-s keyboard-us" "toggle cn -> en selects keyboard"
assert_log "-c" "toggle cn -> en deactivates"
assert_log_absent "-o" "toggle cn -> en does not activate"

reset_stubs; write_base
T_RUNNING=1 T_STATE=1 T_IM=keyboard-us
run_ctl toggle >/dev/null 2>&1
assert_log "-s pinyin" "toggle en -> cn selects chinese IM"
assert_log "-o" "toggle en -> cn activates"

reset_stubs; write_base
T_RUNNING=1 T_STATE=0 T_IM=""
run_ctl toggle >/dev/null 2>&1
assert_log "-s pinyin" "toggle with no IC defaults to cn attempt"

reset_stubs; write_base
T_RUNNING=0
run_ctl toggle >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "toggle without fcitx fails"

# =========================================================== restart fallback

reset_stubs; write_base
T_BUSCTL_RC=1
run_ctl restart >/dev/null 2>&1
assert_rc 0 $? "restart falls back to systemd"
assert_log "--user restart omarchy-fcitx5.service" "restart uses omarchy unit"

reset_stubs; write_base
run_ctl restart >/dev/null 2>&1
assert_log "--user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Restart" "restart uses D-Bus first"
assert_log_absent "--user restart omarchy-fcitx5.service" "no systemd fallback when D-Bus works"

# =========================================================== profile-list

reset_stubs; write_base
out="$(run_ctl profile-list)"
assert_eq "Default" "$(jq -r .group <<<"$out")" "profile-list group"
assert_eq "pinyin" "$(jq -r .defaultIM <<<"$out")" "profile-list defaultIM"
assert_eq "pinyin" "$(jq -r .cnIM <<<"$out")" "profile-list cnIM"
assert_eq "keyboard-us" "$(jq -r .enIM <<<"$out")" "profile-list enIM"
assert_eq '["keyboard-us","pinyin"]' "$(jq -c .items <<<"$out")" "profile-list items"

# =========================================================== profile-add

reset_stubs; write_base
# Success path: fcitx5 must confirm the new IM in its group after start.
T_GROUP_INFO='sa(ss) "us" 2 "keyboard-us" "" "pinyin" "" "wubi-pinyin" ""'
run_ctl profile-add wubi-pinyin >/dev/null 2>&1
assert_rc 0 $? "profile-add exits 0"
grep -q '^\[Groups/0/Items/2\]$' "$PROFILE" && pass || fail "profile-add appends Items/2"
grep -q '^Name=wubi-pinyin$' "$PROFILE" && pass || fail "profile-add writes Name="
awk '/^\[Groups\/0\/Items\/2\]$/{f=NR} /^\[GroupOrder\]$/{g=NR} END{exit !(f && g && f < g)}' "$PROFILE" \
  && pass || fail "profile-add inserts before [GroupOrder]"
ls "$PROFILE".bak.* >/dev/null 2>&1 && pass || fail "profile-add creates a backup"
# Profile edits must stop fcitx5 first: its shutdown path serializes the
# in-memory profile and would overwrite the edit (verified live on this box).
assert_log "--user stop omarchy-fcitx5.service" "profile-add stops fcitx before editing"
assert_log "--user start omarchy-fcitx5.service" "profile-add starts fcitx after editing"
assert_log_absent "--user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Restart" \
  "profile-add must not restart fcitx5 (stale in-memory overwrite)"

T_GROUP_INFO='sa(ss) "us" 2 "keyboard-us" "" "pinyin" "" "wubi-pinyin" ""'
run_ctl profile-add wubi-pinyin >/dev/null 2>&1
assert_rc 0 $? "profile-add is idempotent"
assert_eq "1" "$(grep -c '^Name=wubi-pinyin$' "$PROFILE")" "profile-add idempotent -> single entry"

run_ctl profile-add 'pinyin; rm -rf ~' >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "profile-add rejects injection-shaped IDs"

# fcitx5 answers D-Bus but pruned the entry (missing data): roll back.
reset_stubs; write_base
run_ctl profile-add cangjie >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "profile-add fails when fcitx5 rejects the IM"
grep -q '^Name=cangjie$' "$PROFILE" && fail "rejected add must roll back the profile" || pass
grep -q '^Name=pinyin$' "$PROFILE" && pass || pass2 "rollback keeps original entries"
assert_contains "$(run_ctl profile-add cangjie 2>&1 || true)" "回滚" "rejection message mentions the rollback"

# fcitx5 never answers D-Bus: keep the edit, fail loudly.
reset_stubs; write_base
T_BUSCTL_RC=1
run_ctl profile-add shuangpin >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "unverifiable add fails"
grep -q '^Name=shuangpin$' "$PROFILE" && pass || fail "unverifiable add keeps the edit"

# add while fcitx is down: file edit only, no stop/start/verify
reset_stubs; write_base
T_RUNNING=0 T_BUSCTL_RC=1
run_ctl profile-add cangjie >/dev/null 2>&1
assert_rc 0 $? "profile-add works while fcitx is down"
grep -q '^Name=cangjie$' "$PROFILE" && pass || fail "profile-add while down writes file"
assert_log_absent "--user stop omarchy-fcitx5.service" "no stop when fcitx is already down"
assert_log_absent "InputMethodGroupInfo" "no D-Bus verify when fcitx is down"

# =========================================================== profile-remove

reset_stubs
write_profile "$THREE_ITEM_PROFILE"
run_ctl profile-remove pinyin >/dev/null 2>&1
assert_rc 0 $? "profile-remove exits 0"
grep -q '^Name=pinyin$' "$PROFILE" && fail "profile-remove removed the section" || pass
grep -q '^DefaultIM=wubi-pinyin$' "$PROFILE" && pass || fail "profile-remove rewrote DefaultIM to a Chinese IM"
grep -q '^Name=wubi-pinyin$' "$PROFILE" && pass || fail "profile-remove kept other items"
ls "$PROFILE".bak.* >/dev/null 2>&1 && pass || fail "profile-remove creates a backup"
assert_log "--user stop omarchy-fcitx5.service" "profile-remove stops fcitx before editing"
assert_log "--user start omarchy-fcitx5.service" "profile-remove starts fcitx after editing"
assert_log_absent "--user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Restart" \
  "profile-remove must not restart fcitx5 (stale in-memory overwrite)"

run_ctl profile-remove not-there >/dev/null 2>&1
assert_rc 0 $? "profile-remove of absent IM is a no-op"

write_profile '[Groups/0]
Name=Default

[Groups/0/Items/0]
Name=keyboard-us

[GroupOrder]
0=Default
'
run_ctl profile-remove keyboard-us >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "profile-remove refuses to remove the last method"

# =========================================================== available

# fcitx down: descriptor-dir fallback lists everything found on disk.
reset_stubs; write_base
T_RUNNING=0
mkdir -p "$IM_DIR"
printf '[InputMethod]\nName=Rime\n' > "$IM_DIR/rime.conf"
printf '[InputMethod]\nName=Pinyin\n' > "$IM_DIR/pinyin.conf"
printf '[InputMethod]\nName=Cangjie\n' > "$IM_DIR/cangjie.conf"
out="$(run_ctl available)"
codes="$(jq -r '.available[].code' <<<"$out" | tr '\n' ' ')"
assert_contains "$codes" "keyboard-us" "available lists builtin keyboard"
assert_contains "$codes" "rime" "available lists installed engine (fallback)"
assert_contains "$codes" "cangjie" "fallback keeps entries it cannot validate"
assert_eq "false" "$(jq -r '.available[] | select(.code=="rime") | .installed' <<<"$out")" "available: rime not installed"
assert_eq "true" "$(jq -r '.available[] | select(.code=="pinyin") | .installed' <<<"$out")" "available: pinyin installed"

# fcitx up: entries it cannot load (cangjie; rime absent from its list) drop out.
reset_stubs; write_base
T_RUNNING=1
out="$(run_ctl available)"
codes="$(jq -r '.available[].code' <<<"$out" | tr '\n' ' ')"
assert_contains "$codes" "pinyin" "dbus-filtered available keeps loadable IM"
assert_contains "$codes" "keyboard-us" "dbus-filtered available keeps builtin keyboard"
if [[ $codes == *cangjie* ]]; then fail "dbus filter must drop cangjie"; else pass; fi
if [[ $codes == *rime* ]]; then fail "dbus filter must drop rime (not in fcitx list)"; else pass; fi

# =========================================================== import-rime

reset_stubs; write_base
mkdir -p "$RIME_DIR"
echo "schema-data" > "$TMP/rime_custom.yaml"
echo "text" > "$TMP/notes.txt"
run_ctl import-rime "$TMP/notes.txt" >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "import-rime rejects non-yaml files"

T_RIME_PKG=0
run_ctl import-rime "$TMP/rime_custom.yaml" >/dev/null 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "import-rime refuses when fcitx5-rime missing"
assert_contains "$(run_ctl import-rime "$TMP/rime_custom.yaml" 2>&1 || true)" "fcitx5-rime" "import-rime hints the package to install"

T_RIME_PKG=1
: > "$STUB_LOG"
run_ctl import-rime "$TMP/rime_custom.yaml" >/dev/null 2>&1
assert_rc 0 $? "import-rime succeeds when rime installed"
grep -q 'schema-data' "$RIME_DIR/rime_custom.yaml" && pass || fail "import-rime copied the file"
assert_log "--user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Restart" \
  "import-rime restarts fcitx to redeploy"

# overwriting an existing file keeps a backup
run_ctl import-rime "$TMP/rime_custom.yaml" >/dev/null 2>&1
ls "$RIME_DIR"/rime_custom.yaml.bak.* >/dev/null 2>&1 && pass || fail "import-rime backs up an existing target"

# =========================================================== summary

echo "----"
echo "passed: $PASS  failed: $FAIL"
(( FAIL == 0 ))
