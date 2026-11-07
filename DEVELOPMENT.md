# Cortexa — Development Guide

How the app is put together, and the patterns to follow when extending it.

## File roles

- **`PCGuardCore.psm1`** — the only place real work happens. Every function that touches the OS (process list, disk scan, registry, Ollama HTTP calls, etc.) lives here, and is explicitly listed in the `Export-ModuleMember` line at the end of the file. Both the GUI and the watchdog import this module; neither duplicates its logic.
- **`PCGuard-GUI.ps1`** — a single script: a `[xml]$xaml` here-string defining the whole UI, loaded via `[Windows.Markup.XamlReader]::Load`, followed by code-behind that wires named controls (`x:Name`) to event handlers. There is no XAML compilation step — this is "loose XAML" loaded at runtime.
- **`PCGuard.ps1`** — the watchdog. Runs standalone via the `PCGuard-Watchdog` scheduled task every 15 minutes. Imports the same core module, logs to `logs/pcguard_YYYY-MM.log`, and is the only place that writes to that log (the GUI only reads it, e.g. for History/Alerts).
- **`Install-PCGuard.ps1`** — thin wrapper around `Install-Watchdog` for CLI use; the GUI's Dashboard button does the same thing via the module function directly.

## How the GUI is structured

1. Elevation check + self-relaunch via UAC (top of file, before anything else loads).
2. One big `[xml]$xaml = @"..."@` here-string — all 10 tabs, all styles/templates, in one `<Window>`.
3. `XamlReader.Load` builds the live object tree.
4. A single `foreach ($n in @('ControlName1', 'ControlName2', ...))` loop calls `$window.FindName($n)` for every control the code-behind needs, binding each to a `$ControlName` variable via `Set-Variable`. **Any new named control must be added to this list or `$BtnFoo` etc. will be `$null`.**
5. Code-behind: one section per tab, each with a `Refresh-XxxTab`/`Refresh-XxxList` function and the relevant `.Add_Click({...})` handlers.
6. Initial load block at the bottom calls every tab's refresh function once, then `$window.ShowDialog()`.

Function definition order mostly doesn't matter for code *inside* event handler scriptblocks (they only execute after the whole script has loaded once), but it does matter for any top-level statement that runs immediately (like the initial-load block, which must come after every function it calls).

## Critical gotcha: the array-unwrap bug

PowerShell silently collapses a 1-element collection into a bare scalar when it flows through certain expression forms (an `if/else` branch used as an expression, a bare pipeline assigned via `=`, a function's implicit return). WPF's `ItemsSource` then throws `Cannot convert ... to type 'System.Collections.IEnumerable'` because a scalar object isn't enumerable.

**Rule: every `.ItemsSource = <expr>` assignment must force-wrap its right-hand side in `@(...)`**, even when the source function already looks like it returns an array — the collapse can happen at any point in the chain, and `@()` wrapping at the *final* consumption point is what actually matters (it's idempotent on real arrays, so there's no downside to over-wrapping).

```powershell
# Wrong - will crash the moment exactly one item matches:
$SomeList.ItemsSource = $script:Items | Where-Object { $_.Name -like "*$f*" }

# Right:
$SomeList.ItemsSource = @($script:Items | Where-Object { $_.Name -like "*$f*" })
```

This bug was found and fixed in ~10 places across the app in one pass (Alerts, PnP errors, process/connection/task/startup filters, folder/file scan results, network adapters, disk health). If you add a new `ItemsSource` binding, wrap it from the start.

The same unwrap risk applies inside `PCGuardCore.psm1` functions that build a return value via a pipeline (e.g. `$x = Get-Thing | Where-Object {...}`) — prefer `$x = @(Get-Thing | Where-Object {...})` at the source too, for defense in depth.

## Async calls (background jobs)

Anything that can take more than ~100ms — Ollama generation, recursive folder/file scans — runs via `Start-Job`, polled by a `DispatcherTimer` (0.5–1s interval), never synchronously on the UI thread. See `Start-AiJob` (AI Agent tab section) for the generic pattern:

```powershell
Start-AiJob -ScriptBlock {
    param($mp, $m, $arg)
    Import-Module $mp -Force   # jobs run in a separate process - re-import explicitly
    Invoke-SomeCoreFunction -Model $m -Whatever $arg
} -ArgumentList @($modelPath, $model, $someArg) -OnComplete {
    param($result)
    # back on the UI thread here
}
```

Jobs don't inherit the already-imported module, so every job scriptblock must `Import-Module $mp -Force` itself using a path passed in via `-ArgumentList` (closures over `$RootDir` etc. don't cross into the job's separate process).

## Config

`config.json` (via `Get-PCGuardConfig`/`Save-PCGuardConfig`) is the single settings store, read by both the GUI and the watchdog. Current schema:

```json
{
  "RamFreePercentWarn": 15,
  "DiskFreePercentWarn": 10,
  "DiskFreePercentCritical": 8,
  "AutoClean": true,
  "UnwantedProcesses": [],
  "FocusMode": false,
  "WebhookUrl": "",
  "WebhookType": "Slack",
  "AiEnabled": false,
  "AiModel": "qwen2.5:3b"
}
```

`Get-PCGuardConfig` fills in defaults for any missing key, so it's always safe to add a new field: add it to the `$cfg = [ordered]@{...}` default block in `Get-PCGuardConfig`, and existing `config.json` files on disk will just pick up the default until explicitly saved.

## The AI agent's safety design

This is the one architectural rule that should **not** be relaxed without deliberate thought: **the AI only ever suggests; it never executes.**

Concretely:
- `Invoke-AiSystemAnalysis` prompts the model to end its reply with a `SUGGESTED_ACTIONS: Token1, Token2` line, using only tokens from a fixed vocabulary defined in the system prompt (`FreeRam`, `CleanTemp`, `StopUnwanted`, `SpeedBoost`, `ShutdownWsl`, `RestorePoint`).
- `Get-AiSuggestedActions` parses that line with a regex and **filters against the same whitelist again** in code (`$whitelist = @(...)` in the function itself) — a model hallucinating an unknown token is silently dropped, not executed.
- The GUI's `Build-AiActionChips` maps each surviving token to an actual existing Dashboard `Button` object (via a `switch`) and renders a chip whose click handler does nothing but `RaiseEvent(ClickEvent)` on that *real* button — i.e. the AI path and the manual-click path are provably the same code path, not a parallel "AI executes this" branch.
- If you add a new whitelisted action, it must: (1) already exist as a real button with its own handler, (2) be added to `$script:AiActionLabels` and the `switch` in `Build-AiActionChips`, (3) be added to the vocabulary list in `$script:AiSystemPrompt` and the `$whitelist` in `Get-AiSuggestedActions`.
- Never add a code path where parsed AI output results in a `Stop-Process`, registry write, or similar directly — always route it through a real button's existing confirm-dialog-gated handler.

**Extensions to this pattern (command bar, multi-step plans):**
- The command bar (`Invoke-AiParseCommand` / `Get-AiParsedCommand`) extends the whitelist with two parameterized tokens: `EndProcess:<name>` and `OpenTab:<name>`. Both are re-validated independently of the AI's output before anything happens — `EndProcess`'s target is looked up fresh against `Get-Process` (the AI naming something doesn't make it exist), and `OpenTab`'s target is matched against `$script:CommandBarTabWhitelist`, which is asserted to match the real tab headers exactly (see `TESTING.md`). `OpenTab` is the only action that runs without a confirm dialog, because it's pure navigation — no system state changes.
- "Run All Suggested Steps" (multi-step plans) shows **one** upfront confirmation listing the ordered steps, then raises each mapped button's click event in sequence. Some of those buttons (`BtnSpeedBoost`, `BtnStopUnwanted`, `BtnRestorePoint`) have their own internal confirm dialogs — this means the user may see a second confirmation for those specific steps. That's intentional redundancy, not a bug: a button's own safety gate is never bypassed just because a higher-level "run everything" flow already asked once.
- Every point where the user accepts or declines an AI-suggested action calls `Write-AiActionLog` (`Source`, `Action`, `Label`, `Decision`, optional `Detail`) — this is the audit trail on the AI Agent tab's "Action History" panel. If you add a new AI-triggered action path, log it the same way; don't let a new path go unaudited.

## Adding a new feature — the pattern to follow

1. Write the function in `PCGuardCore.psm1`. Add it to `Export-ModuleMember`.
2. Test it standalone first, against the real system, before touching the GUI:
   ```powershell
   Import-Module "C:\Users\Charm\PCGuard\PCGuardCore.psm1" -Force
   Your-NewFunction -SomeParam value
   ```
3. Add the XAML (inside the relevant `<TabItem>`, or a new one). Give every interactive element an `x:Name`.
4. Add every new name to the big `foreach ($n in @(...))` FindName list.
5. Write the code-behind handler. If it calls anything that touches the OS and might take >100ms, use the `Start-AiJob`-style background job pattern (or a dedicated one — see the folder/file scan jobs for a non-AI example).
6. If it populates a `ListView`/`ListBox`, wrap the assignment in `@(...)`.
7. Validate (see `TESTING.md`) before considering it done — syntax check + headless XAML load at minimum.

## Known limitations (intentional, not bugs)

- **No real packet capture.** Network tab is bandwidth/connection monitoring (`Get-NetAdapterStatistics`, `Get-NetTCPConnection`), not packet-level inspection. That would need Npcap and is a different class of tool.
- **No SMTP email alerting.** Only Slack/Discord webhooks — avoids needing to store an email password in `config.json`.
- **No per-process network attribution.** Windows doesn't expose this reliably without ETW tracing; rather than fake it, it's just not implemented.
- **AI judgment quality is bounded by the local model.** `qwen2.5:3b` (the model tested against during development) gives reasonable but imperfect verdicts, especially for `Invoke-AiReviewStartupItems`. This is expected — it's advisory, not authoritative, and the model is user-selectable in the AI Agent tab's dropdown.
