#!/usr/bin/env bash
# Small wrapper around the Pangolin CLI for the bar widget (and the optional
# terminal wrappers in terminal/).
#
#   pangolin-ctl.sh status       one line of JSON: the client status, or {"running":false}
#   pangolin-ctl.sh up [flags]   start the client in the background as root
#   pangolin-ctl.sh down         stop the client (no password needed)
#
# PANGOLIN_ELEVATE=pkexec  ask for the password with polkit (the bar widget, default)
# PANGOLIN_ELEVATE=sudo    ask with sudo in the terminal (terminal wrappers)
# PANGOLIN_BIN             use a CLI at another path
set -uo pipefail

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

# Quote one word for the POSIX root shell.
shell_quote() {
  local s=${1//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

# The client status as JSON, or nothing. The CLI can print other text first
# (such as "A new version is available"), so start at the first `{` line.
status_json() {
  "$bin" status --json 2>/dev/null | sed -n '/^{/,$p'
}

is_running() {
  [[ -n "$(status_json)" ]]
}

bin="$(find_pangolin)" || {
  [[ "${1:-}" == status ]] && { echo '{"running":false,"installed":false}'; exit 0; }
  echo "Pangolin CLI not found" >&2
  exit 127
}

case "${1:-}" in
  status)
    out="$(status_json)"
    if [[ -n "$out" ]]; then
      # Collapse to one line so the widget can parse it in one go.
      printf '%s\n' "$out" | tr -d '\n'
      echo
    else
      echo '{"running":false,"installed":true}'
    fi
    ;;

  up)
    shift
    extra=()
    # Plain `pangolin up` starts its root helper with the client ID and secret
    # as command-line arguments (`sudo sh -c "… --id … --secret …"`), which
    # any local account can read with `ps`, even if only for a moment.
    #
    # Instead, start the root client ourselves, the way `sudo pangolin up
    # --attach` runs: as root, with SUDO_USER set, the CLI reads this user's
    # login and client credentials from their own config. No credentials are
    # ever passed to any process, on a command line or otherwise, and the
    # script goes to the root shell on stdin.
    for arg in "$@"; do
      case $arg in
        --id|--id=*|--secret|--secret=*)
          echo "Pass the client ID and secret through PANGOLIN_CLIENT_ID / PANGOLIN_CLIENT_SECRET in the root environment, not as flags." >&2
          exit 2 ;;
        --silent|--attach) ;; # always attached in the background here
        *) extra+=("$arg") ;;
      esac
    done

    if is_running; then
      echo "A Pangolin client is already running." >&2
      exit 1
    fi

    user=$(id -un)
    log_dir="${XDG_CONFIG_HOME:-$HOME/.config}/pangolin/logs"
    log="$log_dir/client.log"
    # With --log-level debug the client logs its secret and session tokens,
    # and root writes these files with its own umask. Keep the whole log
    # folder private to this user, or don't start.
    mkdir -p "$log_dir"
    if ! chmod 700 "$log_dir"; then
      echo "Can't make $log_dir private; not starting the client." >&2
      exit 1
    fi
    [[ -e $log ]] || (umask 077 && : >>"$log")
    # Only this attempt's log lines count when reporting why it failed.
    log_start=$(( $(stat -c %s "$log" 2>/dev/null || echo 0) + 1 ))

    # The client's control socket is created world-writable (0666) and
    # doesn't check who connects, so any local account could stop or
    # reconfigure the root client. As soon as the new socket appears, make
    # it this user's alone (root still has access); if that fails, stop the
    # client rather than leave it open.
    sock=/var/run/olm.sock
    q_user=$(shell_quote "$user")
    script="sock=$sock
old=\$(stat -c %i \"\$sock\" 2>/dev/null)
export SUDO_USER=$q_user
nohup $(shell_quote "$bin") up client --attach"
    for arg in "${extra[@]}"; do script+=" $(shell_quote "$arg")"; done
    script+=" >>$(shell_quote "$log") 2>&1 </dev/null &
pid=\$!
i=0
while [ \$i -lt 1500 ] && kill -0 \$pid 2>/dev/null; do
  if [ -S \"\$sock\" ] && [ \"\$(stat -c %i \"\$sock\" 2>/dev/null)\" != \"\$old\" ]; then
    chown $q_user \"\$sock\" && chmod 600 \"\$sock\" && exit 0
    kill \$pid; echo 'Could not make the client socket private; client stopped.' >&2; exit 3
  fi
  sleep 0.02; i=\$((i + 1))
done
kill -0 \$pid 2>/dev/null || exit 0
kill \$pid; echo 'The client socket did not appear; client stopped.' >&2; exit 3
"

    case ${PANGOLIN_ELEVATE:-pkexec} in
      pkexec) pkexec /bin/sh -s <<<"$script" ;;
      sudo) sudo /bin/sh -s <<<"$script" ;;
      *) echo "PANGOLIN_ELEVATE must be pkexec or sudo" >&2; exit 2 ;;
    esac
    rc=$?
    # 126/127: the password prompt was cancelled or refused.
    (( rc == 0 )) || exit "$rc"

    # The client runs in the background, so its errors only reach the log.
    # Wait for it to answer, else report its last log line.
    for _ in $(seq 1 30); do
      is_running && exit 0
      sleep 0.5
    done
    # Log lines look like "ERROR: <date> <time> msg"; the CLI itself prints
    # "Error: msg" before it exits.
    last=$(tail -c "+$log_start" "$log" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
      | grep -E '^(ERROR|FATAL|Error):' | tail -n 1 \
      | sed -E 's/^(ERROR|FATAL): [0-9/]+ [0-9:]+ /\1: /')
    echo "The Pangolin client didn't start${last:+: $last}" >&2
    exit 1
    ;;

  down)
    # In a terminal, let the CLI show its own progress.
    [[ -t 1 ]] && exec "$bin" down
    # Without a terminal, `pangolin down` sends the stop request and then
    # fails to draw its progress spinner ("could not open a new TTY"), so its
    # exit code says nothing. Check that the client actually stopped.
    is_running || { echo "No Pangolin client is running." >&2; exit 1; }
    out=$("$bin" down </dev/null 2>&1)
    for _ in $(seq 1 20); do
      is_running || exit 0
      sleep 0.5
    done
    echo "The Pangolin client didn't stop: $(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -v '^[[:space:]]*$' | tail -n 1)" >&2
    exit 1
    ;;

  *)
    echo "usage: $0 status|up [flags]|down" >&2
    exit 2
    ;;
esac
