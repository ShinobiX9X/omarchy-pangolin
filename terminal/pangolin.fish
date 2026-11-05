# Keeps the client ID and secret off the process list when you run
# `pangolin up` in a terminal (see "Terminal use" in the plugin README).
# Install: cp pangolin.fish ~/.config/fish/functions/
function pangolin --wraps pangolin --description 'Pangolin CLI, with credentials kept out of ps on up'
    set -l shim ~/.config/omarchy/plugins/io.github.shinobix9x.pangolin/elevate
    if test "$argv[1]" = up; and test -x $shim/sudo
        PANGOLIN_ELEVATE=sudo PATH="$shim:$PATH" command pangolin $argv
    else
        command pangolin $argv
    end
end
