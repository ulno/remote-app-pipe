# remote-app-pipe

A polymorphic Waypipe orchestrator designed for CachyOS and KDE Plasma across private Nebula mesh networks. It streams remote Wayland applications with hardware acceleration, automates single-instance profile handovers (preventing SQLite lockouts in Thunderbird and Firefox), generates native `.desktop` launchers, and deploys itself across nodes.

---

## Key Features

* **Graceful Session Handover:** Detects when an app (e.g., Thunderbird) is already running on a physical or orphaned display, sends a `SIGTERM` to safely flush SQLite caches and remove `parent.lock`, and reclaims the session for the active Wayland context.
* **Polymorphic Host Detection:** Compares the local `hostname` against the required `--server-host` (`-H`). If executed on the target host, it runs locally without network overhead; otherwise, it establishes a Waypipe tunnel over Nebula.
* **Network-Optimized Waypipe:** Uses `zstd=3` compression over raw SSH to minimize latency across WAN/Nebula links without double-compression CPU overhead.
* **Built-in Self-Deployment:** Easily pushes itself to any workstation's binary directory via `scp`.
* **PATH-Independent Remote Launch:** Resolves the remote executable to an absolute path, so it works even though non-interactive SSH sessions usually do not include `~/.local/bin` in `PATH`.
* **KDE / XDG Desktop Generator:** Generates registered `.desktop` files so remote applications appear seamlessly in KRunner (Alt+Space) and the Kickoff Application Menu.
* **Remote Icon Fetching:** Reads the app's remote `.desktop` entry, finds its icon in the remote icon themes, and copies it into the local icon store, so launchers do not show a missing-image placeholder.

---

## Prerequisites

Ensure the following packages are installed on both client and host machines:

```bash
sudo pacman -S waypipe openssh

```

Ensure `~/.local/bin` is in your shell `$PATH` on the client machine (or call the script by its absolute path). Remote launches resolve the deployed binary to an absolute path and do not depend on the server's non-interactive SSH `PATH`.

---

## Installation & Deployment

1. **Save the script** locally on your primary workstation:
```bash
install -Dm755 remote-app-pipe ~/.local/bin/remote-app-pipe

```


2. **Deploy to your nodes** over Nebula using `--deploy`. A leading `~` in `--bin-dir` is expanded against the remote user's `$HOME` on the server:
```bash
# Push to university desktop
remote-app-pipe --deploy -t uni-desktop-nebula

# Push to home workstation
remote-app-pipe --deploy -t home-desktop-nebula

# Push to a custom system binary directory (if needed)
remote-app-pipe --deploy -t uni-desktop-nebula --bin-dir /usr/local/bin

```



---

## Generating Desktop Launchers

Run `--install-desktop` once to generate launchers on your roaming laptops or desktops. Because the script checks the local hostname at runtime, the same launcher runs natively when at the desk and connects over Waypipe when roaming.

`--install-desktop` also looks for the requested icon in the local icon themes. If it is not installed locally, it asks the remote host for the app's `.desktop` entry, resolves the icon named in its `Icon=` key, copies it to `~/.local/share/icons/remote-app-pipe/`, and stores that absolute path in the launcher. Use `--no-fetch-icon` to disable this, or `--fetch-icon` to force a refresh.

If you generated a launcher before the icon was available (or used a typo in `-i`), repair it without remembering all original parameters:

```bash
remote-app-pipe --refresh-icon ~/.local/share/applications/remote-thunderbird-uni-desktop-nebula.desktop
```

The target and app are read from the launcher's existing `Exec=` line. `--refresh-icon` only updates `Icon=`; re-run `--install-desktop` if you also want to regenerate `Exec=` with the new absolute-path handling.

### 1. Dedicated Email Client (University Desktop)

Safely handles Thunderbird's SQLite and Gloda indexes:

```bash
remote-app-pipe --install-desktop \
  -t uni-desktop-nebula \
  -H uni-desktop \
  -a thunderbird \
  -n "Thunderbird (Uni)" \
  -i thunderbird \
  -c "Centralized mail and calendar access" \
  --categories "Network;Email;"

```

### 2. Remote Code Editor (Home Workstation)

Runs Zed remotely with local Wayland GPU rendering:

```bash
remote-app-pipe --install-desktop \
  -t home-desktop-nebula \
  -H home-desktop \
  -a zed \
  -n "Zed (Home Workstation)" \
  -i zed \
  -c "High-performance editor running on home desktop" \
  --categories "Development;IDE;"

```

### 3. Campus Intranet Browser (University Desktop)

Access internal campus services directly:

```bash
remote-app-pipe --install-desktop \
  -t uni-desktop-nebula \
  -H uni-desktop \
  -a firefox \
  -n "Firefox (Uni Intranet)" \
  -i firefox \
  -c "Direct access to campus-restricted networks" \
  --categories "Network;WebBrowser;"

```

---

## CLI Usage

Ad-hoc execution accepts files, URLs, and arbitrary command-line arguments:

```bash
# Open a remote project folder in Zed on your home desktop:
remote-app-pipe -t home-desktop-nebula -H home-desktop zed ~/projects/research

# Open a university-restricted URL through the university host:
remote-app-pipe -t uni-desktop-nebula -H uni-desktop firefox https://intranet.uni.edu

# Run an isolated Firefox profile without killing the main desktop instance:
remote-app-pipe -t uni-desktop-nebula -H uni-desktop firefox -P UniRemote --no-remote

# Open remote Dolphin file manager:
remote-app-pipe -t uni-desktop-nebula -H uni-desktop dolphin ~/Documents

```

---

## Parameter Reference

| Parameter | Type | Description |
| --- | --- | --- |
| `-t`, `--target` | Required* | Nebula hostname or SSH alias of the target server. |
| `-H`, `--server-host` | Required | Physical server hostname (output of `hostname` on the host). |
| `<app>` / `-a` | Required | Binary executable name to invoke (`thunderbird`, `zed`, etc.). |
| `--deploy` | Flag | Copies `remote-app-pipe` to target host via `scp`. |
| `--bin-dir <path>` | Optional | Remote directory for `--deploy` and for locating the remote binary at launch (Default: `~/.local/bin`). |
| `--install-desktop` | Flag | Creates and registers an XDG `.desktop` launcher. |
| `-n`, `--name` | Optional | Application menu entry name. |
| `-i`, `--icon` | Optional | Icon name or absolute icon path for the `.desktop` launcher (Default: `<app>`). |
| `-c`, `--comment` | Optional | Description string in the `.desktop` file. |
| `--categories` | Optional | XDG category string (Default: `Network;`). |
| `--fetch-icon` | Flag | Always pull the app icon from the remote host. |
| `--no-fetch-icon` | Flag | Never pull icons automatically. |
| `--refresh-icon <file>` | Optional | Re-fetch the icon for an existing `.desktop` file. |

** `--target` is only optional when running directly on the server in `--server` mode.*

---

## Troubleshooting

### `Failed to run program "remote-app-pipe": No such file or directory`

This error is emitted by **waypipe's server**, not by `remote-app-pipe`. The remote waypipe process tries to execute the command it was given, and non-interactive SSH sessions normally do not source `.bashrc`/`.profile`. As a result, `~/.local/bin` is usually not in the remote `PATH`.

The launcher now asks the server for its `$HOME`, resolves `~/.local/bin/remote-app-pipe` to an absolute path, verifies that it is executable, and passes that absolute path to waypipe. If the check fails, you get an explicit error telling you to run `--deploy` instead of a cryptic waypipe failure.

`--deploy` also uses the resolved remote home directory, so `mkdir -p '~/.local/bin'` no longer creates a literal directory named `~` on the server.

### The launcher shows a missing-image icon

Desktop entries do not automatically copy icons between machines. Check that `Icon=` names an icon that exists locally, or let the script fetch it:

```bash
remote-app-pipe --refresh-icon ~/.local/share/applications/remote-betterbird-ulno-framework.ulno.mesh.desktop
```

If you passed a typo such as `-i bettrbird`, re-run `--install-desktop` with `-i betterbird`, or simply run `--refresh-icon` — the script resolves the icon from the remote app's own `.desktop` entry rather than trusting the typo.

---

## Author

[ulno](https://ulno.net) (Ulrich Norbisrath)

## License

MIT — see [LICENSE](LICENSE).
