# Changelog

All notable changes to Cortexa, in the order they were built.

## v1.1 — 2026-11-08

### AI Agent — agentic features
- Natural-language command bar (persistent, visible on every tab): type a request like "free up my ram" or "close spotify", the AI maps it to one action from a fixed whitelist, you confirm before anything runs
- Model Manager: pull/delete Ollama models from inside the app
- Multi-step plans: "Run All Suggested Steps" executes an AI-ordered sequence of whitelisted actions with one upfront confirmation
- Action audit log: every AI-suggested action and whether it was accepted or declined, viewable on the AI Agent tab

### Polish
- First-run welcome overlay (shown once, explains all tabs)
- `CHANGELOG.md`

## v1.0 — 2026-11-08

### Monitoring
- System health snapshot: RAM, CPU, disk free space (C:/D:), with live sparkline trend charts
- Network monitoring: live download/upload throughput, per-adapter totals, active connections (netstat-style), traffic history
- Disk I/O live throughput (read/write MB/s)
- System info: uptime, battery status + health report (wear %), GPU utilization
- Security status: Windows Defender, Firewall, BitLocker, disk health/SMART, devices with driver errors
- Recent Windows system/application errors (last 24h)
- WSL/Docker disk and memory footprint

### Task & process management
- Advanced task manager: multi-select, End Task, End Task Tree (kills child processes too), Open File Location, Set Priority, auto-refresh
- Windows Scheduled Tasks browser with Enable/Disable
- Startup items (registry Run keys + Startup folder) with reversible Enable/Disable (backs up before disabling)

### Cleanup & optimization
- Safe Temp/npm-cache cleanup
- Free Up RAM (working-set trimming via `EmptyWorkingSet`)
- Speed Boost (chains cleanup + WSL shutdown + RAM trim + unwanted-software stop, with before/after comparison)
- Stop Unwanted Software (user-defined list, confirm-gated)
- Docker prune, WSL shutdown
- Largest folders / largest individual files scanner
- System Restore point creation

### Background watchdog
- Scheduled task running every 15 minutes, independent of the GUI
- Configurable alert thresholds, Windows toast notifications
- Optional Slack/Discord webhook alerts
- Focus Mode (suppresses notifications without disabling monitoring)
- Auto-generated daily HTML health report (30-day retention)
- Auto-cleanup when disk space gets critical

### AI Agent (Ollama integration)
- Local LLM connection (auto-detects installed models, can start the Ollama server from the app)
- System analysis: diagnosis + prioritized recommendations from live system data
- Chat: ask questions about your system in plain language
- Clickable action chips: AI suggestions from a fixed, code-enforced whitelist, routed through the same buttons/confirmations a manual click would use — the AI never executes anything directly
- "Ask AI About Selected" — explains what a selected process is and whether it's safe to end
- "AI Review Startup Items" — flags startup programs as safe-to-disable / keep / unsure

### Branding & polish
- Renamed from PCGuard to Cortexa, custom-generated icon (hexagonal chip/node design)
- Modern dark UI: card-based layout, live sparklines, pill-style tabs
- Admin self-elevation via UAC with status badge
- Fixed: tab content clipping (added scroll containers), tab-strip overflow risk (widened window, added horizontal scroll fallback), array-unwrap bug affecting single-item list results (fixed in ~10 locations)

### Documentation
- `README.md`, `DEVELOPMENT.md`, `TESTING.md`
