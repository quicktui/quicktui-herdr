# quicktui-herdr

Independent Herdr plugin. It is not QuickTUI Server and must not vendor
closed-source server, auth, Relay, or AgentBridge2 code.

## Branches

- `main`: stable local branch
- `develop`: local integration branch
- Task branches start from `develop`

This repository has no `origin` until a later task explicitly authorizes
GitHub publishing. Do not invent a remote or treat Marketplace listing as done.

## Scripts

- POSIX `sh` only in `scripts/`
- Commands use argv. Do not use `eval`, `sh -c`, or string shell concatenation
- Do not download or execute remote installers
- Do not start `quicktui-server` or any other unsupervised daemon
- Do not save pairing codes, tokens, or identity material

## Verification

```sh
sh tests/run.sh
```

Optional real Herdr smoke, after a v0.8.0 `herdr` binary is available:

```sh
HERDR_BIN=/path/to/herdr sh tests/smoke-herdr-link.sh
```
