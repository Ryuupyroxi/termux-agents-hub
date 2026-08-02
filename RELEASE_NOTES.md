# termux-agents-hub v3.0.2 — Release Notes

**Codename:** "TTY-Interactive Installer"

This release focuses on a smoother, safer one-line install path plus several
reliability fixes uncovered since v3.0.1.

## What's New
- **One-liner installer (`install.sh`)** — `bash -c "$(curl -fsSL https://raw.githubusercontent.com/Ryuupyroxi/termux-agents-hub/main/install.sh)"`
  - Auto-detects Termux, installs all deps (`nodejs python git curl termux-api`),
    downloads `termux-agents-hub.sh`, and launches it.
  - Validates the downloaded script (checks for a bash shebang) before executing.
  - Falls back to `apt` if `pkg` is unavailable.

## Bug Fixes
- **TTY stdin redirect fix (installer)** — When the installer is piped in
  (not run from a TTY), input is now redirected back to `/dev/tty` so the hub
  launches fully interactive instead of silently blocking on stdin.
- **Health monitor crash timestamp** — The crash timestamp logic in
  `health_monitor` wasn't executing; now recorded correctly on agent failure.
- **Startup function verification** — Added a startup check that catches silent
  script parse failures (a broken function definition) *before* the menu loads,
  instead of failing mid-session.
- **self_update URL correction** — Fixed the self-update GitHub URL
  (`your-org` → `Ryuupyroxi`) so updates resolve to the correct repository.

## Notes
- Carried over from v3.0.1: resolved `get_ip()` double-output and `ui_header()`
  printf argument mismatches.
- 56-tool device toolkit, health monitor, backup/restore, and session history
  remain unchanged from v3.0.x.

## Upgrade
Re-run the one-liner installer, or `git pull` and re-launch
`./termux-agents-hub.sh`.
