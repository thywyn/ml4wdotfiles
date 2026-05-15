#!/usr/bin/env bash
# Launch an app, wrapping it in `uwsm app --` when the Hyprland session
# was started by uwsm. Outside uwsm sessions it execs the command directly.
# Usage: app.sh <command> [args...]

if [ $# -eq 0 ]; then
    echo "usage: app.sh <command> [args...]" >&2
    exit 2
fi

if [ -n "$UWSM_ID" ] \
   || [ "$XDG_SESSION_DESKTOP" = "hyprland-uwsm" ] \
   || systemctl --user is-active --quiet wayland-wm@Hyprland.service 2>/dev/null \
   || systemctl --user is-active --quiet wayland-wm@hyprland.service 2>/dev/null; then
    if command -v uwsm >/dev/null 2>&1; then
        exec uwsm app -- "$@"
    fi
fi

exec "$@"
