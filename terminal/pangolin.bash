# Keeps the client ID and secret off the process list when you run
# `pangolin up` in a terminal (see "Terminal use" in the plugin README).
# Install: source this file from ~/.bashrc
pangolin() {
  local ctl="$HOME/.config/omarchy/plugins/io.github.shinobix9x.pangolin/pangolin-ctl.sh"
  local args=("$@")
  [[ "${args[0]:-}" == up && "${args[1]:-}" == client ]] && args=(up "${args[@]:2}")
  if [[ "${args[0]:-}" == up && -x "$ctl" && " ${args[*]} " != *" site "* \
        && " ${args[*]} " != *" -h "* && " ${args[*]} " != *" --help "* ]]; then
    PANGOLIN_ELEVATE=sudo "$ctl" up "${args[@]:1}" && command pangolin status
  else
    command pangolin "$@"
  fi
}
