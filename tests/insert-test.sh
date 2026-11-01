#!/usr/bin/env bash
# Behavior tests for insert.sh through fake wl-copy/hyprctl/sleep on PATH:
# call order, the sensitive clipboard offer, and the guaranteed key-up
# when the script is killed between key down and up.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
cleanup() {
  pkill -f "$work/bin" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/bin"

# Fake sleep: never waits; the Nth call TERMs the script (2 = the 0.05s
# between key down and up) when KILL_SLEEP asks for it.
cat > "$work/bin/sleep" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$work/sleep-count" 2>/dev/null || echo 0) + 1 ))
echo \$n > "$work/sleep-count"
if [ "\$n" -eq "\${KILL_SLEEP:--1}" ]; then kill -TERM \$PPID; fi
exit 0
EOF

# Fake hyprctl: logs its dispatch arguments.
cat > "$work/bin/hyprctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$work/hyprctl.log"
exit 0
EOF

# Fake wl-copy: logs arguments, captures stdin, idles until killed.
cat > "$work/bin/wl-copy" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$work/wl-copy.log"
cat > "$work/clipboard.txt"
trap 'echo terminated > "$work/wl-copy-state"; exit 0' TERM INT
echo running > "$work/wl-copy-state"
while :; do :; done
EOF

chmod +x "$work/bin/sleep" "$work/bin/hyprctl" "$work/bin/wl-copy"

reset_state() {
  rm -f "$work/sleep-count" "$work/hyprctl.log" "$work/wl-copy.log" \
        "$work/clipboard.txt" "$work/wl-copy-state"
}

expected_keys="$work/expected-keys.log"
cat > "$expected_keys" <<'EOF'
dispatch hl.dsp.send_key_state({mods="SHIFT",key="Insert",state="down"})
dispatch hl.dsp.send_key_state({mods="SHIFT",key="Insert",state="up"})
EOF

# Syntax check first.
bash -n insert.sh

# No glyph: nothing happens at all.
reset_state
PATH="$work/bin:$PATH" bash insert.sh ""
PATH="$work/bin:$PATH" bash insert.sh
[ ! -e "$work/hyprctl.log" ]
[ ! -e "$work/wl-copy.log" ]

# Happy path: sensitive foreground offer, key down then up, offer killed.
reset_state
PATH="$work/bin:$PATH" bash insert.sh "😀"
grep -q -- "--type text/plain --sensitive --foreground" "$work/wl-copy.log"
[ "$(cat "$work/clipboard.txt")" = "😀" ]
diff -u "$expected_keys" "$work/hyprctl.log"
[ "$(cat "$work/wl-copy-state")" = "terminated" ]

# Killed between key down and up: the EXIT trap still releases the key
# (down+up in the log, third sleep never reached), but the never-finished
# script cannot kill its clipboard offer. The fake sleep exits 0 before
# bash runs its deferred TERM handler, so the handler's bare `exit`
# preserves $? = 0 — the key-up is the guarantee, not the status.
reset_state
set +e
PATH="$work/bin:$PATH" KILL_SLEEP=2 bash insert.sh "🔥"
rc=$?
set -e
[ "$rc" -eq 0 ]
[ "$(cat "$work/sleep-count")" -eq 2 ]
diff -u "$expected_keys" "$work/hyprctl.log"
[ "$(cat "$work/wl-copy-state")" = "running" ]

echo "insert-test: all assertions passed"
