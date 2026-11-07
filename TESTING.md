# Cortexa — Testing Guide

Two layers of testing apply here: automated/headless checks you can run after any edit (catch syntax and binding errors before you even open the app), and a manual click-through checklist (catch anything that only shows up when actually rendered and used — headless PowerShell cannot render a WPF window or verify visual layout).

## 1. Automated checks (run after every edit)

### Syntax check (every `.ps1`/`.psm1` you touched)

```powershell
foreach ($f in @(
    "C:\Users\Charm\PCGuard\PCGuard-GUI.ps1",
    "C:\Users\Charm\PCGuard\PCGuardCore.psm1",
    "C:\Users\Charm\PCGuard\PCGuard.ps1"
)) {
    $content = Get-Content $f -Raw
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$errors) | Out-Null
    if ($errors.Count -eq 0) { "OK: $f" } else { "ERRORS in $f :"; $errors | ForEach-Object { $_.Message } }
}
```

This catches typos, unbalanced braces/parens, bad string escaping — but **not** XAML errors (the XAML lives inside a string literal, invisible to the PowerShell parser) and **not** runtime logic errors.

### Headless XAML validation (after any XAML edit)

The XAML is a string until `XamlReader.Load` parses it at runtime, so a malformed `<Grid>` or an unresolved `{StaticResource ...}` only shows up when you actually try to load it. Validate without opening a visible window:

```powershell
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$content = Get-Content 'C:\Users\Charm\PCGuard\PCGuard-GUI.ps1' -Raw
if ($content -match '(?s)\[xml\]\$xaml = @"(.*?)"@') {
    [xml]$x = $matches[1]
    $reader = New-Object System.Xml.XmlNodeReader $x
    $win = [Windows.Markup.XamlReader]::Load($reader)   # throws on any XAML error
    "XAML LOAD OK: $($win.GetType().Name)"

    # Confirm every control the code-behind references by name actually exists.
    # Keep this list in sync with the FindName loop in PCGuard-GUI.ps1.
    $names = @('RamText', 'BtnScan', '...')   # see PCGuard-GUI.ps1's FindName list for the full set
    $missing = $names | Where-Object { -not $win.FindName($_) }
    if ($missing.Count -eq 0) { "ALL NAMED ELEMENTS FOUND" } else { "MISSING: $($missing -join ', ')" }
}
```

This catches: malformed XAML, unresolved `StaticResource`/`DynamicResource` keys, and — critically — any control referenced in code-behind (`$BtnFoo = $window.FindName('BtnFoo')`) that doesn't actually exist in the XAML (a very easy mistake when adding a button and forgetting to add it to the FindName list, which fails *silently* at runtime as a null reference rather than at load time).

Note: this only builds the WPF object tree in memory — it does **not** render, so it cannot catch visual issues like a tab header strip overflowing the window width, or content taller than its container. See the manual checklist below for that.

### Function-level smoke tests (after any `PCGuardCore.psm1` change)

Test new/changed functions directly, against the real system, before wiring them into the GUI:

```powershell
Import-Module "C:\Users\Charm\PCGuard\PCGuardCore.psm1" -Force
Your-NewOrChangedFunction -SomeParam value   # inspect the real output
```

Do this **before** touching XAML/code-behind — it's much faster to iterate on a bare function call than through the full GUI, and isolates whether a bug is in the core logic or the UI wiring.

Caveats specific to this app:
- **Admin-only functions** (`Invoke-CreateRestorePoint`, `Get-BatteryHealthReport`'s `powercfg` calls) will fail with "Access denied" if your test shell isn't elevated — check with:
  ```powershell
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  ```
  The shipped app always runs elevated (self-elevates via UAC), so this is only a concern for ad-hoc testing in a non-elevated shell — don't mistake it for a real bug.
- **Ollama-dependent functions** need Ollama actually running: `Test-OllamaAvailable` first; if `$false`, start it with `Start-OllamaServer` (or `Start-Process "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe" -ArgumentList "serve" -WindowStyle Hidden` and wait a few seconds for the port to come up).
- **Single-item results**: when testing any function that returns a list, deliberately test with a filter/input that narrows the result to exactly one item — this is exactly the scenario that triggers the array-unwrap bug (see `DEVELOPMENT.md`). If you're testing a GUI-bound function, confirm the GUI's `ItemsSource` assignment is wrapped in `@(...)`.

### Watchdog smoke test

Run it directly (don't wait for the 15-minute scheduled task) and check the log:

```powershell
& "C:\Users\Charm\PCGuard\PCGuard.ps1" -AutoClean:$false   # avoid triggering real cleanup during a test
Get-Content "C:\Users\Charm\PCGuard\logs\pcguard_$(Get-Date -Format 'yyyy-MM').log" -Tail 10
```

Should complete with no console output (errors are suppressed to the log via `$ErrorActionPreference = 'SilentlyContinue'` + explicit `Write-Log` calls — if something is silently failing, check the log, not the console).

## 2. Manual click-through checklist

Run this after any change that could plausibly affect layout or interaction — headless checks can't catch these:

- [ ] App launches, UAC prompt appears, badge shows "Administrator" (green) after accepting
- [ ] Every tab header is visible and clickable (watch for tab-strip overflow if you add more tabs — see `DEVELOPMENT.md`'s window-sizing note; re-measure with the `FormattedText` approach from the session history if tabs are added)
- [ ] Every tab's content is fully visible or scrollable — nothing cut off at the bottom (the `TabControl` template wraps content in a `ScrollViewer`; confirm it's still there if you touch that template)
- [ ] Dashboard: stat tiles show real numbers, sparklines animate after ~2s, Quick Actions buttons each show the right confirm dialog (where applicable) and succeed
- [ ] Processes: multi-select works, End Task / End Task Tree / Open File Location / Set Priority all work on a real (non-critical) process, filter box narrows results including down to exactly one match
- [ ] Disk Analysis: folder scan and file scan both complete without freezing the UI (background job pattern), WSL/Docker buttons work
- [ ] Network: Download/Upload populate within ~1s of opening the tab (not stuck on "sampling..."), connections list populates, filter works
- [ ] Tasks / Startup: filter works, Enable/Disable work and are reflected immediately on refresh
- [ ] Security: Defender/Firewall/BitLocker lines show real status (not "unavailable" unless genuinely unavailable), disk health table populates, PnP error list shows real data or "No devices reporting errors"
- [ ] History: chart renders once there's at least 2 watchdog-logged data points (won't show anything useful on a fresh install until the watchdog has run at least twice)
- [ ] AI Agent: status reflects real Ollama state, model dropdown populates, Analyze produces real text + any action chips that appear actually work when clicked, chat responds and scrolls
- [ ] Settings: Save Settings persists (reopen the app or re-run Load-ConfigIntoUI to confirm), Export/Import Settings round-trip correctly

## What cannot be tested headlessly at all

- Actual rendered visual appearance (colors, spacing, whether something *looks* right) — requires a human looking at the real window.
- Window resize behavior, DPI scaling correctness.
- Real UAC prompt interaction (headless automation can construct the elevation-check code path but can't click "Yes" on a real consent dialog).
- AI response *quality* (only that the call succeeds and the parsing contract is followed) — judge usefulness by actually reading the AI's output against what you know about your own system.

When in doubt: run the automated checks first (fast, catches most mechanical errors), then do a real click-through for anything structural before calling a change done.
