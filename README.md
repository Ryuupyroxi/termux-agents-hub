# termux-agents-hub

**AI Agent Manager for Termux (Android)**

A single-file bash script that installs, configures, launches, and manages AI coding agents on any unrooted Android device via Termux. Zero-friction onboarding — get a free model running in under 2 minutes.

![Version](https://img.shields.io/badge/version-3.0.0-cyan)
![Platform](https://img.shields.io/badge/platform-Android%20(Termux)-green)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

### 🤖 Agent Management
- **Hermes** (Nous Research) — Dashboard, API Server, Chat TUI
- **Codex CLI** (OpenAI) — Terminal-based coding agent
- **OpenClaw Gateway** — Web UI for AI agents
- Launch multiple agents simultaneously in background sessions
- Auto-detect port conflicts and assign free ports

### 🛠 56-Tool Device Toolkit
- **33 Termux API** tools — clipboard, TTS, toast, camera, torch, location, calendar, WiFi, battery, vibrate, volume, and more
- **14 Shizuku** capabilities — package manager, app control, UI automation, system settings, contacts/SMS, storage access, screenshots
- **1 Intent Bridge** — launch apps, services, and broadcasts
- **8 curated dev tools** — system health, git intel, log tools, dependency scan, and more
- Category-level toggle switches to enable/disable tool groups

### 📊 Health Monitor
- Live-updating agent health display with PID, uptime, and heartbeat
- Crash detection with optional auto-restart
- TTS and notification alerts on agent failure

### 🔗 Quick Connect
- One-tap copy agent URLs to clipboard
- Open agent dashboards directly in Android browser
- CLI flags: `--copy-url dashboard`, `--open-url api`

### 📜 Session History
- Timestamped audit log of every agent start/stop/install/config change/crash
- Filter by agent, clear history, view last 50 entries

### 💾 Backup & Restore
- One-shot backup of all agent configs to `/sdcard/Download/`
- Standard tar.gz archive with manifest
- Restore with validation and post-restore health checks
- Follows the existing migration directory structure

### ⚙️ Settings
- Network binding and per-agent port configuration
- Model selection with free model quick-select
- API key management with seamless agent restart
- Theme selection (6 themes)
- Wake lock, notifications, and auto-restart toggles
- Health monitor poll interval

## Quick Start

```bash
# Install dependencies
pkg update && pkg install nodejs python git curl termux-api

# Download and run
curl -O https://raw.githubusercontent.com/Ryuupyroxi/termux-agents-hub/main/termux-agents-hub.sh
chmod +x termux-agents-hub.sh
./termux-agents-hub.sh
```

## CLI Flags

```bash
./termux-agents-hub.sh                  # Interactive menu
./termux-agents-hub.sh --install        # Install agents
./termux-agents-hub.sh --tools          # Browse 56 tools
./termux-agents-hub.sh --health         # Health monitor
./termux-agents-hub.sh --history        # Session history
./termux-agents-hub.sh --backup         # Backup/restore
./termux-agents-hub.sh --diagnostics    # System diagnostics
./termux-agents-hub.sh --doctor         # Health check
./termux-agents-hub.sh --stop-all       # Stop all agents
./termux-agents-hub.sh --help           # Full help
```

## Configuration

Config stored at `~/.config/termux-agents-hub/`:
- `config.env` — all settings (ports, model, features, tool toggles)
- `keys.env` — API keys (chmod 600)

## Requirements

- Android phone (any, tested on Moto Z4)
- [Termux](https://f-droid.org/en/packages/com.termux/) terminal
- [Termux:API](https://f-droid.org/en/packages/com.termux.api/) (optional, for device tools)
- [Shizuku](https://shizuku.rikka.app/) (optional, for privileged operations)

## License

MIT
