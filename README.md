# quicktui-herdr

Herdr plugin that discovers QuickTUI Server and opens the official pairing
flow. It is an ecosystem entry point, not a second QuickTUI server.

Supported hosts: macOS and Linux. Minimum Herdr version: **0.8.0**.

## What this plugin does

- Runs a bounded, idempotent health check from Herdr `[[startup]]` and exits
- Shows a Setup action / popup when you want to pair a device
- Reuses `quicktui-server pairing welcome` and `pairing qrcode`
- Uses Herdr-injected `HERDR_BIN_PATH` and `HERDR_SOCKET_PATH`
- Prints official install instructions when QuickTUI is missing

## What it does not do

- It does not download or execute `q.sh` or any other remote installer
- It does not start `quicktui-server` or any unsupervised daemon
- It does not save pairing codes, tokens, or identity material
- It does not take over a Herdr controller
- It does not support Windows

QuickTUI Server remains the only long-running service.

## Install (local link)

This repository is currently local-only. Publishing to GitHub / Marketplace
is documented in [docs/publish.md](docs/publish.md) and is not authorized yet.

```sh
herdr plugin link /absolute/path/to/quicktui-herdr
herdr plugin list --plugin ai.quicktui
herdr plugin action invoke ai.quicktui.setup
herdr plugin pane open --plugin ai.quicktui --entrypoint setup
```

Unlink leaves the files in place:

```sh
herdr plugin unlink ai.quicktui
```

## Usage

| Entry | When | Behavior |
| --- | --- | --- |
| `[[startup]]` | After Herdr restore / live handoff | Discover install + readiness, write local status, exit |
| Setup action / pane | User invoked | Missing: install guide. Not ready: start-service guide. Ready + TTY: `pairing welcome` |
| Pairing QR action | User invoked | Same discovery, then `pairing qrcode` only if the daemon is ready |

Custom QuickTUI installs can set:

- `QUICKTUI_SERVER_BIN`: absolute `quicktui-server` path
- `QUICKTUI_CONFIG`: absolute `config.toml` path

Default discovery uses `$PATH`, `~/.local/bin/quicktui-server`, and
`~/.config/quicktui-server-v2/config.toml`.

## Official QuickTUI install

The plugin never runs these commands. If QuickTUI is not installed, run one
yourself:

```sh
# Global
curl -fsSL https://quicktui.ai/q.sh | sh

# China
curl -fsSL https://dl.quicktui.cn/q.sh | sh
```

## Development

```sh
sh tests/run.sh
```

Optional smoke against a real Herdr v0.8.0 binary:

```sh
HERDR_BIN=/path/to/herdr sh tests/smoke-herdr-link.sh
```

Scripts are POSIX `sh`. Commands use argv. There is no `eval`.

## License

MIT. See [LICENSE](LICENSE).
