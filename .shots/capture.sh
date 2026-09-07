#!/bin/bash
# Regenerate README/marketplace screenshots. Requires an active Hyprland
# session (grim, hyprctl) and the omarchy themes below installed locally.
#
# For each theme it pins the theme's palette into the state custom-zen.css
# (the live symlink target the browser reads), launches Zen on the real
# profile with -no-remote, focuses the new window, and captures that
# window's geometry with grim -g -- not the desktop, which is how the old
# shots ended up picturing the wallpaper instead of the browser.
#
# Composites (tools/make-preview.py) then pair each browser shot with the
# theme's wallpaper, side by side.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_CSS="$HOME/.local/state/omarchy/current/theme/custom-zen.css"
OUT=/tmp/oz-shot/log.txt
SHOT_DIR="$REPO/screenshots"
: > "$OUT"
log(){ echo "[$(date +%T)] $*" >> "$OUT"; }

mkdir -p "$SHOT_DIR"
if [[ -L $STATE_CSS ]] || [[ -f $STATE_CSS ]]; then
  cp "$STATE_CSS" /tmp/oz-shot/backup-custom-zen.css
  log "backed up $STATE_CSS"
else
  log "WARN no state custom-zen.css; nothing to restore"
fi

render_palette() {
  local theme=$1
  python3 "$REPO/tools/render-custom-zen.py" \
    "$HOME/.config/omarchy/themes/$theme/colors.toml" \
    "$STATE_CSS" \
    "$REPO/assets/omarchy/custom-zen.css.tpl" >> "$OUT" 2>&1 || return 1
}

# Wait for any zen window (the previous instance was pkilled before launch).
wait_zen_window() {
  for _ in $(seq 1 60); do
    local w
    w=$(hyprctl clients -j | python3 -c "
import json,sys
try: cs=[c for c in json.load(sys.stdin) if c.get('class')=='zen']
except: cs=[]
print(cs[-1]['address'] if cs else '')")
    [[ -n $w ]] && { echo "$w"; return 0; }
    sleep 1
  done
  return 1
}

shoot() {
  local theme=$1 out=$2
  render_palette "$theme" || { log "render failed $theme"; return 1; }
  pkill -f 'zen[-]bin' >/dev/null 2>&1 || true
  sleep 3
  # Bare launch, default profile, no session restore of the previous window.
  /opt/zen-browser-bin/zen -no-remote --new-instance about:newtab >/dev/null 2>&1 &
  local win win_geom
  win=$(wait_zen_window) || { log "no zen window for $theme"; return 1; }
  sleep 6
  hyprctl dispatch focuswindow "address:$win" >/dev/null 2>&1
  sleep 2
  # Bring it to a known geometry, top-left, roughly 2/3 screen for a crisp
  # capture without depending on the previous window layout.
  hyprctl dispatch movewindowpixel exact 0 0,"address:$win" >/dev/null 2>&1
  hyprctl dispatch resizewindowpixel exact 1700 1000,"address:$win" >/dev/null 2>&1
  sleep 2
  win_geom=$(hyprctl clients -j | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    if c.get('address')=='$win':
        x,y=c['at']; w,h=c['size']
        print('%d,%d %dx%d'%(x,y,w,h)); break")
  [[ -n $win_geom ]] || { log "no geometry for $theme"; return 1; }
  sleep 1
  grim -g "$win_geom" "$SHOT_DIR/$out" && log "captured $out @ $win_geom"
}

shoot osiris zen-osiris.png
shoot lavender zen-lavender.png
shoot woman-with-floral-composition-01-palette zen-floral.png

if [[ -f /tmp/oz-shot/backup-custom-zen.css ]]; then
  cp /tmp/oz-shot/backup-custom-zen.css "$STATE_CSS"
  log "restored palette: $STATE_CSS"
fi
pkill -f 'zen[-]bin' >/dev/null 2>&1 || true
log "ALL DONE"
cat "$OUT"