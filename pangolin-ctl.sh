#!/usr/bin/env bash
# Small wrapper around the Pangolin CLI for the bar widget.
#
#   pangolin-ctl.sh status   one line of JSON: the client status, or {"running":false}
#   pangolin-ctl.sh up       start the client in the background (asks for the
#                            password through polkit)
#   pangolin-ctl.sh down     stop the client (no password needed)
#
# The CLI path can be overridden with PANGOLIN_BIN.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_pangolin() {
  if [[ -n "${PANGOLIN_BIN:-}" ]]; then
    [[ -x "$PANGOLIN_BIN" ]] && printf '%s\n' "$PANGOLIN_BIN" && return 0
    return 1
  fi
  local candidate
  for candidate in "$(command -v pangolin 2>/dev/null)" "$HOME/.local/bin/pangolin" /usr/local/bin/pangolin /usr/bin/pangolin; do
    [[ -n "$candidate" && -x "$candidate" ]] && printf '%s\n' "$candidate" && return 0
  done
  return 1
}

bin="$(find_pangolin)" || {
  [[ "${1:-}" == status ]] && { echo '{"running":false,"installed":false}'; exit 0; }
  echo "Pangolin CLI not found" >&2
  exit 127
}

case "${1:-}" in
  status)
    out="$("$bin" status --json 2>/dev/null)"
    if [[ "$out" == \{* ]]; then
      # Collapse to one line so the widget can parse it in one go.
      printf '%s\n' "$out" | tr -d '\n'
      echo
    else
      echo '{"running":false,"installed":true}'
    fi
    ;;
  up)
    # `pangolin up` re-runs itself through `sudo sh -c ...`, which needs a
    # terminal. Put our sudo shim first in PATH so that step goes through
    # pkexec and the shell's polkit dialog instead.
    PANGOLIN_ELEVATE=pkexec PATH="$here/elevate:$PATH" exec "$bin" up --silent
    ;;
  down)
    exec "$bin" down
    ;;
  *)
    echo "usage: $0 status|up|down" >&2
    exit 2
    ;;
esac
