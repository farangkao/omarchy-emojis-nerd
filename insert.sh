#!/bin/bash
# Opt-in custom insert helper: a sensitive clipboard offer (skipped by
# clipboard history), then Shift+Insert sent by Hyprland through the
# real keyboard. Not wtype: browsers don't handle its throwaway keymap
# reliably (atx/wtype #31, #52, #58). The offer stays up long enough
# for browsers, which read it a bit later than GTK apps.
glyph="${1:-}"
[[ -n $glyph ]] || exit 0

printf '%s' "$glyph" | wl-copy --type text/plain --sensitive --foreground &
copy_pid=$!

key_up() {
  hyprctl dispatch 'hl.dsp.send_key_state({mods="SHIFT",key="Insert",state="up"})' >/dev/null
}

sleep 0.15
# A key left down would repeat, so the release also runs on HUP/INT/TERM.
trap key_up EXIT
trap exit HUP INT TERM
hyprctl dispatch 'hl.dsp.send_key_state({mods="SHIFT",key="Insert",state="down"})' >/dev/null
sleep 0.05
key_up
trap - EXIT HUP INT TERM
sleep 1.5

kill "$copy_pid" 2>/dev/null || true
