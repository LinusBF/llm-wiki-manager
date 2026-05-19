# LLM Wiki Manager

A lightweight macOS menu bar app that watches an LLM Wiki vault’s `raw/` folder and runs a coding-agent ingest prompt when new top-level source files appear.

The app supports Claude Code and OpenAI Codex as interchangeable backends. It uses the same `.ingested/` marker convention as the bash workflow, so you can switch between this app, a shell loop, and manual agent runs without changing vault layout.

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

Claude Code:

```bash
claude -p "<prompt>" --permission-mode acceptEdits
```

Codex:

```bash
codex exec --skip-git-repo-check --sandbox workspace-write "<prompt>"
```

The app sets the subprocess working directory to the vault root so each agent finds its own schema file automatically.
