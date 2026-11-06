# Pangolin for Omarchy

An Omarchy bar widget for the [Pangolin](https://pangolin.net) client: see at a
glance whether you're connected, turn the client on or off, and check which
sites are reachable (direct or relayed, with latency).

*Unofficial: not made by or affiliated with Fossorial / Pangolin.*

![Pangolin popup](preview.png)

## Requirements

- The [Pangolin CLI](https://docs.pangolin.net/manage/clients/install-client)
  (`pangolin`), on your `PATH` or in `~/.local/bin`.
- Logged in once from a terminal: `pangolin login`, then `sudo pangolin up`
  the first time (the CLI needs root once to cache the device fingerprint).

## Install

```bash
omarchy plugin add https://github.com/ShinobiX9X/omarchy-pangolin.git --enable
```

## Remove

```bash
omarchy plugin remove io.github.shinobix9x.pangolin
```

The plugin writes no files of its own.

## Use

| Action | Result |
|--------|--------|
| Click the icon | Open the popup |
| Middle-click the icon | Connect / disconnect |
| Right-click the icon | Refresh now |
| Switch in the popup, `Enter`, `Space` or `T` | Connect / disconnect |
| `R` in the popup | Refresh now |

The icon is dimmed while disconnected, pulses while connecting, and turns the
theme's urgent color when the client reports an error.

Connecting asks for your password in the Omarchy polkit dialog, because
`pangolin up` creates a network interface as root. Disconnecting needs no
password.

From a script or a keybinding:

```bash
omarchy-shell io.github.shinobix9x.pangolin toggleClient   # or up / down
omarchy-shell io.github.shinobix9x.pangolin status         # on, off, connecting, error, ...
```

### Settings

In the bar settings, or in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|-----|---------|---------|
| `refreshIntervalSec` | `10` | How often the status is read while the popup is closed |
| `hideWhenOff` | `false` | Hide the icon while the client is off |

## How it works

- Status: `pangolin status --json`, which reads the client's local socket.
  Nothing is sent over the network by the widget itself.
- Disconnect: `pangolin down`.
- Connect: the widget starts the root client itself, the way
  `sudo pangolin up --attach` runs. [`pangolin-ctl.sh`](pangolin-ctl.sh)
  passes a short script on stdin to `pkexec /bin/sh -s` (the normal polkit
  password prompt) that sets `SUDO_USER` to you and starts
  `pangolin up client --attach` in the background. Running as root with
  `SUDO_USER` set, the CLI reads your login and client credentials from your
  own Pangolin config. Nothing is installed system-wide and no sudoers or
  polkit rules are changed.
- Why not plain `pangolin up`: it starts its root helper with the client ID
  and secret as command-line arguments (`sudo sh -c "… --id … --secret …"`),
  which any local account can read with `ps`, even if only for a moment. On
  the path above, no credentials are passed to any process at all; the widget
  never reads or shows process command lines.
- If the client doesn't come up within a few seconds, the popup shows the last
  error from the client's log (`~/.config/pangolin/logs/client.log`).

Set `PANGOLIN_BIN` in the shell's environment to use a CLI at another path.

## Terminal use

Running `pangolin up` yourself still briefly puts the secret on the process
list. To connect the same way as the widget from a terminal, install the small
wrapper from `terminal/`. It asks for your password with `sudo`:

```bash
# fish
cp ~/.config/omarchy/plugins/io.github.shinobix9x.pangolin/terminal/pangolin.fish ~/.config/fish/functions/

# bash: add to ~/.bashrc
source ~/.config/omarchy/plugins/io.github.shinobix9x.pangolin/terminal/pangolin.bash
```

Only `pangolin up` / `pangolin up client` (with any of its flags) is changed;
`up site`, `--help` and every other subcommand run as is. If the plugin is
removed, the wrapper falls back to the plain CLI.

## License

MIT
