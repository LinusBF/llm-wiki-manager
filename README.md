# LLM Wiki Manager

A lightweight macOS menu bar app that watches an LLM Wiki vault’s `raw/` folder and runs a coding-agent ingest prompt when new top-level source files appear.

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

## Agent Invocations

Preferences → Ingestion lets you tune the active agent:

- Ingest mode: `Fast`, `Normal`, or `Deep`. This changes the workflow instruction appended to each ingest prompt.
- Model: optional model name passed to the active agent CLI.
- Reasoning effort: optional effort override. Claude Code uses `--effort`; Codex uses `-c model_reasoning_effort="..."`.

Claude Code:

```bash
claude -p "<prompt>" --permission-mode acceptEdits [--model sonnet] [--effort high]
```

Codex:

```bash
codex exec --skip-git-repo-check --sandbox workspace-write [--model gpt-5.4-mini] [-c 'model_reasoning_effort="low"'] "<prompt>"
```

The app sets the subprocess working directory to the vault root so each agent finds its own schema file automatically.

## Runtime Visibility

The agent process runs from a background utility task so ingestion work does not share the menu bar UI actor. The menu includes:

- `Agent messages` — last five stdout/stderr lines from the active agent.
- `Ingest stats` — current and recent ingest metadata, including agent, model, ingest mode, reasoning effort, queue time, run time, attempts, and wiki pages updated.

The same ingest stats are persisted in `.llm-wiki/state.json` for crash recovery and recent-history display.
