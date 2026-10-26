# quicktui-herdr

Independent Herdr plugin. It is not QuickTUI Server and must not vendor
closed-source server, auth, Relay, or AgentBridge2 code.

## Branches

- `main`: stable local branch
- `develop`: local integration branch
- Task branches start from `develop`

`origin` is the public repository `quicktui/quicktui-herdr`, listed in the
Herdr Marketplace through the `herdr-plugin` topic. Pushing still needs the
maintainer's authorization for each version sync.

## Scripts

- Unix entries use POSIX `sh` in `scripts/`. Windows entries use PowerShell in
  `scripts/windows/`: compatible with Windows PowerShell 5.1 and 7+, called by
  argv, no `Invoke-Expression`, pure ASCII with LF line endings (same rules as
  QuickTUI `q.ps1`)
- Commands use argv. Do not use `eval`, `sh -c`, `Invoke-Expression`, or string
  shell concatenation
- Windows action and pane ids carry a `-windows` suffix; Herdr rejects
  duplicate ids even when their `platforms` differ
- Call Herdr only through `HERDR_BIN_PATH`. On Windows its socket is a named
  pipe; never connect to it directly
- Run the official QuickTUI installer only after the user confirms each time
  on a TTY. Download it to a private temp file and run it with argv
  (`sh <file>`, or `powershell.exe -NoProfile -ExecutionPolicy Bypass -File
  <file.ps1>` on Windows); never pipe it into a shell or `iex`. Delete the file
  afterwards
- The plugin itself starts no daemon. After the user confirms, the official
  installer may install and start the QuickTUI service through its own flow
- Do not save pairing codes, tokens, or identity material

## Verification

```sh
sh tests/run.sh
```

`tests/run.sh` includes the Windows PowerShell fixture tests when `pwsh` is on
`PATH` (`QT_REQUIRE_PWSH=1` turns a missing `pwsh` into a failure). They do not
prove Windows PowerShell 5.1, Windows paths, or ConPTY behavior; test those on
a real Windows host.

Optional real Herdr smoke, after a v0.9.0 or newer `herdr` binary is available:

```sh
HERDR_BIN=/path/to/herdr sh tests/smoke-herdr-link.sh
```
