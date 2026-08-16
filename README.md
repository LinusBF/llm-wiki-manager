# LLM Wiki Manager

A lightweight watcher that runs a coding-agent ingest prompt when new top-level source files appear in an LLM Wiki vault’s `raw/` folder. It ships as a macOS menu bar app and a headless Linux daemon.

This project is an automation layer for Andrej Karpathy’s original [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern: keep raw sources immutable, let a coding agent incrementally maintain a persistent Markdown wiki, and use the wiki as the durable synthesis layer between you and your sources.

The app supports Claude Code and OpenAI Codex as interchangeable backends. It uses the same `.ingested/` marker convention as the bash workflow, so you can switch between this app, a shell loop, and manual agent runs without changing vault layout.

## References

- [LLM Wiki by Andrej Karpathy](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — the original post describing the workflow this app operationalizes.
- Starter vault schemas are bundled as [AGENTS.md](/Users/linus/Projects/llm-wiki-manager/Sources/LLMWikiCore/Resources/StarterSchemas/AGENTS.md) and [CLAUDE.md](/Users/linus/Projects/llm-wiki-manager/Sources/LLMWikiCore/Resources/StarterSchemas/CLAUDE.md), each adapted from the same LLM Wiki pattern for its agent.

## Vault Layout

```text
vault/
├── CLAUDE.md
├── AGENTS.md
├── raw/
├── wiki/
├── .ingested/
└── .llm-wiki/
    ├── log.jsonl
    ├── state.json
    └── prompts/
        └── ingest.txt
```

Only top-level regular files in `raw/` are enqueued. Subdirectories such as `raw/assets/` are watched for debounce purposes but are not ingested as standalone sources.

## Build

```bash
swift test
swift build
Scripts/build-app.sh
```

The bundling script creates `dist/LLM Wiki Manager.app` with `LSUIElement = true`, so it runs as a menu bar app without a Dock icon.

When the app initializes an empty vault, it creates `raw/`, `wiki/`, `.ingested/`, and starter `AGENTS.md` / `CLAUDE.md` schema files from the bundled templates. Existing schema files are never overwritten.

## Linux background service

The Linux daemon polls `raw/`, waits for each source's size and modification time to remain stable across two polls, processes sources sequentially, and uses the same prompts, markers, and JSONL operational log as the macOS app. It runs as a per-user `systemd` service, so the agent CLI uses that user's existing credentials.

Prerequisites are Swift 5.9 or newer, `systemd`, and an authenticated `claude` or `codex` CLI. On the Linux server:

```bash
git clone <this-repository-url>
cd llm-wiki-manager
Scripts/install-linux-service.sh /absolute/path/to/vault
```

The installer builds the release binary, installs it under `~/.local/bin`, writes the user unit, captures the current `PATH` for user-scoped agent installations, and starts it. It does not overwrite an existing configuration. Edit `~/.config/llm-wiki-manager/environment` to choose the agent or set model, reasoning, retry, polling, permission, and binary-path overrides; [the example](Packaging/llm-wiki-manager.env.example) lists every setting.

```bash
systemctl --user status llm-wiki-manager.service
journalctl --user -u llm-wiki-manager.service -f
systemctl --user restart llm-wiki-manager.service
```

To keep the user service running after logout, an administrator must enable lingering once:

```bash
sudo loginctl enable-linger "$USER"
```

For a foreground run or non-systemd supervisor:

```bash
swift run -c release llm-wiki-daemon --vault /absolute/path/to/vault --agent codex
```

The daemon exits on invalid configuration or a missing agent executable so `systemd` can report and restart the failure. After a source exhausts its configured retries, it is skipped until the service is restarted. On shutdown, `systemd` stops the daemon and active agent together; an interrupted source remains unmarked and is retried after restart.

## Agent Invocations

Preferences → Ingestion lets you tune the active agent:

- Ingest mode: `Fast`, `Normal`, or `Deep`. This changes the workflow instruction appended to each ingest prompt.
- Model: pick an exact model from the active agent's catalog (`Sources/LLMWikiCore/AgentModels.swift`), leave it on the agent default, or choose `Custom…` to type any model name the CLI accepts.
- Reasoning effort: effort override, limited to the levels the selected model actually supports. Claude Code uses `--effort`; Codex uses `-c model_reasoning_effort="..."`. Models without effort control (e.g. Claude Haiku 4.5) disable the picker, and the flag is omitted from the invocation.

Claude Code:

```bash
claude -p "<prompt>" --permission-mode acceptEdits [--model claude-opus-5] [--effort xhigh]
```

Codex:

```bash
codex exec --skip-git-repo-check --sandbox workspace-write [--model gpt-5.6-sol] [-c 'model_reasoning_effort="high"'] "<prompt>"
```

The model catalog is a curated snapshot, not a live query. To refresh Codex entries, read the slugs and `supported_reasoning_levels` out of `~/.codex/models_cache.json` (skip entries with `visibility: "hide"`); for Claude, check the current model list and which models support `--effort`.

The app sets the subprocess working directory to the vault root so each agent finds its own schema file automatically.

## Runtime Visibility

The agent process runs from a background utility task so ingestion work does not share the menu bar UI actor. The menu includes:

- `Agent messages` — last five stdout/stderr lines from the active agent.
- `Ingest stats` — current and recent ingest metadata, including agent, model, ingest mode, reasoning effort, queue time, run time, attempts, and wiki pages updated.

The same ingest stats are persisted in `.llm-wiki/state.json` for crash recovery and recent-history display.
