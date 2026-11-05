# Keeps the client ID and secret off the process list when you run
# `pangolin up` in a terminal (see "Terminal use" in the plugin README).
# Install: source this file from ~/.bashrc
pangolin() {
  local shim="$HOME/.config/omarchy/plugins/io.github.shinobix9x.pangolin/elevate"
  if [[ "${1:-}" == up && -x "$shim/sudo" ]]; then
    PANGOLIN_ELEVATE=sudo PATH="$shim:$PATH" command pangolin "$@"
  else
    command pangolin "$@"
  fi
}
