# agy-high-auto

A guard for running **Antigravity CLI (`agy`)** in high-autonomy mode on the homelab,
successor to [`gemini-high-auto`](https://github.com/hexcodex-cyber/gemini-high-auto).

**Status: scaffold + discovery probe. The guard is not yet proven to fire.** Do not rely on
it to block anything until the probe step below has been run and the real guard written.

## Why this is a rewrite, not a port

`gemini-high-auto` worked by setting `GEMINI_GUARD_SHELL`, which the Gemini CLI honoured by
routing every shell command through a wrapper script. Two things killed that design:

1. **Gemini CLI is gone** — transitioned to Antigravity CLI on 2026-05-19.
2. **`agy` has no guard-shell hook.** Every `AGY_*` / `ANTIGRAVITY_*` environment variable in
   the 1.2.2 binary was enumerated; none wraps, replaces or intercepts the shell. A
   find-and-replace port would appear to work and silently guard nothing — the same failure
   already recorded for Grok, which ignores `$SHELL` and execs directly.

What `agy` has instead is **better**: a first-class hooks system with `PreToolUse` /
`PostToolUse` / `SessionStart` / `Stop` events, `allow` / `deny` / `ask` verdicts, and both
`command` and `prompt` hook modes. A pre-tool hook can return **ask**, which the old
deny/confirm rules file could not express.

## Most of the original is now redundant

`agy` already ships what `destructive_matchers.rules` was hand-rolling:

- `--sandbox` — terminal restrictions
- a **PolicyGuardian** layer (SafeBrowsing, `unquoted_shell_operators`, `globalPermissionGrants`,
  `PERMISSIONS_V2_ENABLED`)
- built-in persistence detection — the binary explicitly reasons about *"commands writing or
  appending to startup or auto-execution files (`~/.bashrc`, crontab, systemd units,
  `.git/hooks/*`)"*
- per-script permission grants, ask-by-default URL fetches

The old rules file also targets **Windows** (`diskpart`, `Format-Volume`, `Remove-Item -Recurse`,
`reg delete`). On a Linux host none of those patterns can ever match.

So this repo deliberately does **not** reimplement generic destructive-command detection. It
encodes only what `agy` cannot know: **homelab-specific** invariants.

## What the guard should eventually cover

Rules worth encoding here, none of which `agy` can infer:

- the **do-not-disturb AI-stack ports** — 11434, 11435, 5080, 5173, 19000, 15000, 18080
- `/home/hexcodex/projects` (live trading code) and `~/tiger-live-quarantine`
- the cmdb ansible-vault on kymforge
- kidblock / OPNsense / UniFi control endpoints
- `/models` — multi-GB model weights, expensive to re-download

## Layout

| Path | What it is |
|---|---|
| `agy-high-auto` | Launcher. Installs the hook config, then runs `agy`. Refuses `--dangerously-skip-permissions` until `AGY_HIGH_AUTO_CONFIRMED=1`. |
| `hooks/hooks.json` | Hook wiring. **Candidate schema — unverified.** |
| `guard/probe.sh` | Discovery hook: records what `agy` passes it, then always allows. |

## Step 1 — discovery (do this first)

The hook schema was reverse-engineered from strings in the `agy` binary
(`jsonhook.JSONHookSpec`, `ParseHooksFile`, `MatchesToolName`, `expandHome`) and has **not**
been confirmed against a running session. Rather than guess, find out:

```bash
./agy-high-auto                  # installs hooks/hooks.json, runs agy with prompts ON
# ...ask it to run any shell command...
cat ~/.agy-hook-probe.jsonl | python3 -m json.tool
```

Each record holds the hook's `argv`, its `stdin` (raw and parsed), and the `AGY_*`
environment. That tells you the real payload shape — tool name, arguments, event name —
and what a verdict must look like.

If the log is **empty** after a session that ran a command, the hook did not fire: the
config path or the schema is wrong. Try `~/.gemini/config/hooks.json` as the alternate
location (the binary references both) before assuming the mechanism is unavailable.

## Step 2 — write the real guard

Only once Step 1 produces evidence. Replace `probe.sh` with `agy-guard.sh`, reading a rules
file in the spirit of the original but scoped to the homelab list above, and emitting whatever
verdict shape the probe revealed.

## Step 3 — then, and only then, enable autonomy

```bash
AGY_HIGH_AUTO_CONFIRMED=1 ./agy-high-auto
```

## Install notes for this box (hexcodex-r620)

`agy` exists under **two** accounts, which are different users:

| User | uid | Path |
|---|---|---|
| `hexcodex-r620` | 1000 | `/home/hexcodex-r620/.local/bin/agy` |
| `hexcodex` | 1001 | `/home/hexcodex/.local/bin/agy` |

Both are byte-identical official Google builds (sha256 `e8f90ef6…`). Authentication and
config are **per-user** under `~/.gemini/`; signing in as one does nothing for the other.
Do not `snap install antigravity-cli` — that adds a third, separate copy.

## Decisions on record

| Decision | Value | Date |
|---|---|---|
| agy account for `hexcodex-r620` | **`hexcodex@kymbob.com`** (Google AI Pro) | 2026-09-14 |
| Repo home | **`hexcodex-cyber/agy-high-auto`** — new repo; `gemini-high-auto` left intact for history | 2026-09-14 |

Note the account is shared with `agy` on securemind-agent and the MineOS Genie, so this box
draws on the **same Google AI Pro quota pool** as those. If that turns into contention, the
fix is a dedicated account for this host, not a second install.

## Public repo — where the real rules live

This repository is **public**. It therefore ships the **mechanism** plus *example* rules only.

The actual rule values for a given host — internal ports, service paths, credential store
locations — are a map of that network and do not belong here. Keep them in a private location
(`~/cmdb` on this fleet) and have the guard read them at runtime, the same way the rest of the
homelab code reads credentials from the vault rather than embedding them.
