# remote-app-pipe

A single-file Bash orchestrator for running Wayland applications on a remote Linux host and displaying them locally through [Waypipe](https://gitlab.freedesktop.org/mstoeckl/waypipe) over SSH.

It works over any SSH connection — a LAN, a private mesh such as Nebula, Tailscale, or WireGuard, or a plain VPN — and generates standard XDG `.desktop` entries that integrate remote apps into any XDG-compliant desktop environment.

---

## Key Features

* **Generic Session Handover:** Detects an existing instance of the launched executable and its descendant process tree, sends `SIGTERM`, waits for it to exit, and then starts a fresh instance in the active Wayland/Waypipe context. Shells, interpreters, and session tools are excluded for safety; `--no-handover` disables the behavior.
* **Polymorphic Host Detection:** Compares the local node name (`uname -n`) against `--server-host` (`-H`). If executed on the target host, it runs locally without network overhead; otherwise, it establishes a Waypipe tunnel over SSH. `-H` defaults to the first DNS label of `-t`.
* **Network-Optimized Waypipe:** Uses `zstd=3` compression over raw SSH to reduce latency across WAN, VPN, and mesh links without double-compression CPU overhead.
* **Built-in Self-Deployment:** Pushes itself to any workstation's binary directory via `scp`.
* **PATH-Independent Remote Launch:** Resolves the remote executable to an absolute path, so it works even though non-interactive SSH sessions usually do not include `~/.local/bin` in `PATH`.
* **XDG Desktop Generator:** Generates registered `.desktop` launchers so remote applications appear in application menus and launchers.
* **Remote Icon Fetching:** Reads the app's remote `.desktop` entry, finds its icon in the remote icon themes, and copies it into the local icon store, so launchers do not show a missing-image placeholder.
* **No Build Step:** One portable Bash script; no compiler, runtime, or service to install.

---

## Prerequisites

* Linux with Wayland on the client.
* `waypipe` and OpenSSH on both client and server.
* Bash 4 or newer.
* Optional: an XDG-compliant desktop environment for the generated launchers.

Install the packages with your distribution's package manager, for example:

```bash
# Debian / Ubuntu
sudo apt install waypipe openssh-client

# Fedora
sudo dnf install waypipe openssh-clients

# Arch / Manjaro
sudo pacman -S waypipe openssh
```

Ensure `~/.local/bin` is in your shell `$PATH` on the client (or call the script by its absolute path). Remote launches resolve the deployed binary to an absolute path and do not depend on the server's non-interactive SSH `PATH`.

---

## Installation & Deployment

1. **Save the script** locally on your primary workstation:

```bash
install -Dm755 remote-app-pipe ~/.local/bin/remote-app-pipe
```

2. **Deploy to your nodes** over SSH using `--deploy`. A leading `~` in `--bin-dir` is expanded against the remote user's `$HOME` on the server:

```bash
# Push to the home desktop
remote-app-pipe --deploy -t home-desktop

# Push to the work workstation
remote-app-pipe --deploy -t work-desktop

# Push to a custom system binary directory (if needed)
remote-app-pipe --deploy -t work-desktop --bin-dir /usr/local/bin
```

The target can be any SSH destination: a hostname, an SSH alias, an IP address, or a mesh/VPN name.

### `-t` vs. `-H`

`-t` is the SSH destination. `-H` is the physical hostname the remote machine reports through `uname -n`, used to detect when the script is already running on the target.

`-H` is optional. By default it is derived from `-t` by taking the first DNS label:

```text
-t remote-host.mydomain.mesh   ->   -H remote-host
-t work-desktop                ->   -H work-desktop
```

Override `-H` when your SSH alias or IP does not match the machine's hostname:

```bash
remote-app-pipe -t work-alias -H work-workstation zed
```

In `--server` mode, `-H` defaults to the local `uname -n`.

---

## Default Workflow: Test First, Then Install

The intended workflow is to try the app ad hoc first and install a desktop launcher only after it works.

### 1. Test the app

```bash
remote-app-pipe -t home-desktop betterbird
```

If the window appears, you are done testing. Some apps print environment warnings, for example:

```text
Betterbird: Detected desktop environment no-DE.
```

That line comes from the app, not from `remote-app-pipe`. Waypipe does not provide the same desktop-environment identity as a local session, so the app may report `no-DE` even though it works normally. If the app does not appear, or you want to see the handover and launch decisions, rerun with:

```bash
remote-app-pipe --debug -t home-desktop betterbird
```

### 2. Install the launcher

Once the ad-hoc launch works, create the menu entry:

```bash
remote-app-pipe --install-desktop -t home-desktop betterbird
```

Typical output:

```text
Looking up icon for 'betterbird' on home-desktop...
Fetched icon: /home/you/.local/share/icons/remote-app-pipe/betterbird-betterbird.png
Installed desktop file: /home/you/.local/share/applications/remote-betterbird-home-desktop.desktop
Icon: /home/you/.local/share/icons/remote-app-pipe/betterbird-betterbird.png
```

This short form uses the app name positionally, fetches the remote icon automatically, and writes an XDG launcher. Add `-n`, `-i`, `-c`, or `--categories` for customization; `-a <app>` is an equivalent explicit form.

---

## Session Handover

Before launching a remote app, `remote-app-pipe` looks for an existing instance owned by the same user. The match is generic:

* the executable basename (`betterbird`, `firefox`, `zed`, ...),
* the `${app}-bin` variant used by some Thunderbird/Betterbird builds,
* the `/proc/<pid>/exe` basename,
* the first command-line argument, and
* all descendants of any matching process.

If an existing instance is on a different `WAYLAND_DISPLAY`, it and its process tree are sent `SIGTERM`. The script waits up to 10 seconds for them to stop. If everything stops, the new instance is launched. If the app is already on the target Wayland display, it is left running.

Shells (`sh`, `bash`, `zsh`, ...), interpreters (`python`, `node`, `java`, ...), and session tools (`ssh`, `sudo`, `tmux`, `waypipe`, ...) are never handed over. Use `--no-handover` to disable handover entirely for an app; `--install-desktop --no-handover` records that choice in the generated launcher.

If `SIGTERM` is not enough, the remote script exits with status 75 and prints the PIDs, process names, and `WAYLAND_DISPLAY` values that are still alive. The client then shows a local error window through `zenity`, `kdialog`, `xmessage`, a terminal emulator, or `notify-send` — whichever is available — so it is visible even when the launcher has `Terminal=false`. If none is available, the details go to stderr.

The handover timeout can be changed on the server with the `REMOTE_APP_PIPE_HANDOVER_TIMEOUT` environment variable (default: `10` seconds).

---

## Generating Desktop Launchers

After the ad-hoc test works, run `--install-desktop` once on each client machine to generate launchers. Because the script checks the local node name at runtime, the same launcher runs natively when you are at the host and connects over Waypipe when you are roaming.

`--install-desktop` also looks for the requested icon in the local icon themes. If it is not installed locally, it asks the remote host for the app's `.desktop` entry, resolves the icon named in its `Icon=` key, copies it to `~/.local/share/icons/remote-app-pipe/`, and stores that absolute path in the launcher. Use `--no-fetch-icon` to disable this, or `--fetch-icon` to force a refresh.

If you generated a launcher before the icon was available (or used a typo in `-i`), repair it without remembering all original parameters:

```bash
remote-app-pipe --refresh-icon ~/.local/share/applications/remote-thunderbird-home-desktop.desktop
```

The target and app are read from the launcher's existing `Exec=` line. `--refresh-icon` only updates `Icon=`; re-run `--install-desktop` if you also want to regenerate `Exec=` with the new absolute-path handling.

### 1. Mail Client on the Home Desktop

Access a centralized mail profile from a laptop while travelling:

```bash
remote-app-pipe --install-desktop \
  -t home-desktop \
  -a thunderbird \
  -n "Thunderbird (Home)" \
  -i thunderbird \
  -c "Centralized mail and calendar access" \
  --categories "Network;Email;"
```

### 2. Code Editor on the Work Workstation

Run an editor remotely while keeping GPU-accelerated local rendering:

```bash
remote-app-pipe --install-desktop \
  -t work-desktop \
  -a zed \
  -n "Zed (Work)" \
  -i zed \
  -c "Editor running on the work workstation" \
  --categories "Development;IDE;"
```

### 3. Work-Only Browser

Access services that are only reachable from the work network:

```bash
remote-app-pipe --install-desktop \
  -t work-desktop \
  -a firefox \
  -n "Firefox (Work)" \
  -i firefox \
  -c "Access to work-restricted networks" \
  --categories "Network;WebBrowser;"
```

The same pattern works for a home server, a workstation in the office, or any other SSH-reachable machine. Use `-i` only if you need a specific icon; otherwise the app name is used and the remote icon is fetched when necessary.

---

## CLI Usage

These are the ad-hoc commands used in step 1 of the default workflow. They accept files, URLs, and arbitrary command-line arguments:

```bash
# Open a remote project folder in Zed on the home desktop:
remote-app-pipe -t home-desktop zed ~/projects/research

# Open a work-restricted URL through the work workstation:
remote-app-pipe -t work-desktop firefox https://intranet.example.com

# Run an isolated Firefox profile without killing the main desktop instance:
remote-app-pipe -t work-desktop firefox -P WorkRemote --no-remote

# Open a remote file manager:
remote-app-pipe -t home-desktop dolphin ~/Documents

# Show local and remote handover/launch debugging information:
remote-app-pipe --debug -t home-desktop thunderbird
```

> Note: paths such as `~/projects` are expanded by your local shell before the command is sent. Use paths that exist on the remote host.

---

## Parameter Reference

| Parameter | Type | Description |
| --- | --- | --- |
| `-t`, `--target` | Required* | SSH hostname, alias, IP, or mesh/VPN name of the target machine. |
| `-H`, `--server-host` | Optional | Physical hostname of the server (as reported by `uname -n`). Default: derived from `-t` by taking its first DNS label. |
| `<app>` / `-a` | Required | Binary executable name to invoke (`thunderbird`, `zed`, etc.). |
| `--deploy` | Flag | Copies `remote-app-pipe` to the target host via `scp`. |
| `--bin-dir <path>` | Optional | Remote directory for `--deploy` and for locating the remote binary at launch (Default: `~/.local/bin`). A leading `~` is expanded against the remote `$HOME`. |
| `--install-desktop` | Flag | Creates and registers an XDG `.desktop` launcher. |
| `-n`, `--name` | Optional | Application menu entry name. |
| `-i`, `--icon` | Optional | Icon name or absolute icon path for the `.desktop` launcher (Default: `<app>`). |
| `-c`, `--comment` | Optional | Description string in the `.desktop` file. |
| `--categories` | Optional | XDG category string (Default: `Network;`). |
| `--fetch-icon` | Flag | Always pull the app icon from the remote host. |
| `--no-fetch-icon` | Flag | Never pull icons automatically. |
| `--refresh-icon <file>` | Optional | Re-fetch the icon for an existing `.desktop` file. |
| `-d`, `--debug` | Flag | Print local and remote debugging information. Also enables waypipe debug logging. |
| `--no-handover` | Flag | Do not stop an existing instance before launching. Recorded in `--install-desktop` launchers. |

** `--target` is only optional when running directly on the server in `--server` mode.*

---

## Tests

The test suite is self-contained. It uses fake `ssh`, `scp`, and `waypipe` commands, so it does not contact the network or modify your real desktop entries:

```bash
./tests/run-tests.sh
```

or:

```bash
make test
```

The tests cover desktop generation, icon fetching and refresh, deployment path handling, `-H` derivation, absolute remote binary resolution, argument quoting, debug output, generic process-tree handover, `--no-handover`, handover failure reporting/dialogs, server-mode execution, and validation errors.

---

## Troubleshooting

### Nothing appears, or the command returns immediately

Single-instance applications hand a new launch to an already-running process. If that process is on the server's physical display, the new window may appear there — or the launch may simply exit.

`remote-app-pipe` handles this generically: it finds the launched executable, its `${app}-bin` variant, and descendants, then terminates them with `SIGTERM` if they are on a different Wayland display. If they do not stop within the timeout, the client shows an error dialog with the remaining PIDs and displays. To see exactly what happens remotely, add `--debug`:

```bash
remote-app-pipe --debug -t home-desktop betterbird
```

The debug flag is forwarded to the remote side (and enables waypipe's own debug output), so you can see the handover search, the detected `WAYLAND_DISPLAY`, and whether the old process was stopped. For very noisy output, redirect it:

```bash
remote-app-pipe --debug -t home-desktop betterbird 2>remote-app-pipe-debug.log
```

If the application is already on the same Waypipe display, handover deliberately leaves it running. If it is still running after `SIGTERM`, the debug output says so and the client dialog reports the remaining processes; close them manually or use `--no-handover` for that app.

### The app prints "Detected desktop environment no-DE"

That message comes from the application (Betterbird in the example), not from `remote-app-pipe`. Waypipe does not expose the same desktop-environment identity as a local session, so apps can report `no-DE` while still working normally. Ignore it if the window works; if it does not, rerun with `--debug`.

### `Failed to run program "remote-app-pipe": No such file or directory`

This error is emitted by **waypipe's server**, not by `remote-app-pipe`. The remote waypipe process tries to execute the command it was given, and non-interactive SSH sessions normally do not source `.bashrc`/`.profile`. As a result, `~/.local/bin` is usually not in the remote `PATH`.

The launcher asks the server for its `$HOME`, resolves `~/.local/bin/remote-app-pipe` to an absolute path, verifies that it is executable, and passes that absolute path to waypipe. If the check fails, you get an explicit error telling you to run `--deploy` instead of a cryptic waypipe failure.

`--deploy` also uses the resolved remote home directory, so `mkdir -p '~/.local/bin'` no longer creates a literal directory named `~` on the server.

### The launcher shows a missing-image icon

Desktop entries do not automatically copy icons between machines. Check that `Icon=` names an icon that exists locally, or let the script fetch it:

```bash
remote-app-pipe --refresh-icon ~/.local/share/applications/remote-betterbird-home-desktop.desktop
```

If you passed a typo such as `-i bettrbird`, re-run `--install-desktop` with `-i betterbird`, or simply run `--refresh-icon` — the script resolves the icon from the remote app's own `.desktop` entry rather than trusting the typo.

---

## Author

[ulno](https://ulno.net) (Ulrich Norbisrath)

## License

MIT — see [LICENSE](LICENSE).
