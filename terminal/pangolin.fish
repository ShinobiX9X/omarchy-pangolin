# Keeps the client ID and secret off the process list when you run
# `pangolin up` in a terminal (see "Terminal use" in the plugin README).
# Loaded by pangolin-loader.fish (install that one, see the README).
function pangolin --wraps pangolin --description 'Pangolin CLI, with credentials kept out of ps on up'
    set -l ctl ~/.config/omarchy/plugins/io.github.shinobix9x.pangolin/pangolin-ctl.sh
    set -l args $argv
    test "$args[1]" = up; and test "$args[2]" = client; and set -e args[2]
    if test "$args[1]" = up; and test -x $ctl; and not contains -- site $args; and not contains -- -h $args; and not contains -- --help $args
        PANGOLIN_ELEVATE=sudo $ctl up $args[2..-1]; and command pangolin status
    else
        command pangolin $argv
    end
end
