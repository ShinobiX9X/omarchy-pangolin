# Loads the `pangolin` wrapper from the Pangolin plugin, so it always matches
# the installed plugin version (see "Terminal use" in the plugin README).
# Install: cp pangolin-loader.fish ~/.config/fish/functions/pangolin.fish
set -l wrapper ~/.config/omarchy/plugins/io.github.shinobix9x.pangolin/terminal/pangolin.fish
if test -f $wrapper
    source $wrapper
else
    # Plugin removed: plain CLI.
    function pangolin --wraps pangolin
        command pangolin $argv
    end
end
