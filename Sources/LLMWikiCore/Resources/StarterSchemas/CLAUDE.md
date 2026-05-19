# LLM Wiki — Schema and Conventions

You are the maintainer of an **LLM Wiki**: a personal knowledge base built incrementally from sources I curate. Read this file in full before doing anything else in this vault — every operation depends on it.

This is your wiki. I curate sources; you maintain everything else. I rarely write wiki pages directly; you do.

The pattern is from Karpathy's [LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). This file is the *instantiated* version of that pattern for this specific vault — opinionated defaults you and I will co-evolve as we figure out what works.

## Vault layout

```
vault/
├── CLAUDE.md          # this file
├── raw/               # source documents — IMMUTABLE, do not edit
│   └── assets/        # images and attachments from sources
├── wiki/              # your domain — you create and maintain everything here
│   ├── index.md       # content catalog (you maintain on every ingest)
│   ├── log.md         # chronological log (append-only)
│   ├── sources/       # one page per ingested source
│   ├── entities/      # people, companies, products, places
│   ├── concepts/      # ideas, techniques, theories
│   └── syntheses/     # cross-cutting overviews (created on demand)
└── .ingested/         # marker files written by an external tool, not by you
```

## The three operations

### Ingest

Triggered by: *"ingest raw/whatever.ext"* or similar.

Steps:

1. **Read the source in full.** PDFs, markdown, transcripts — all of it. Don't summarize from the first page.
2. **Write a source page** at `wiki/sources/<descriptive-name>.md` using the source page template below. The name should describe the content, not the original filename — e.g. `GPT-4 Technical Report.md`, not `2303.08774.md`.
3. **Update entity and concept pages.** For every named person, company, product, place, idea, or technique discussed:
   - If a page exists at `wiki/entities/` or `wiki/concepts/`, update it with what this source contributes. Add the source to its `sources:` frontmatter.
   - If a page is warranted but doesn't exist, create it.
   - Flag contradictions explicitly in a `## Contradictions` section on the affected page — don't silently overwrite earlier claims.
4. **Update `wiki/index.md`.** Add new pages under the right category with one-line summaries. Reorder if it helps.
5. **Append to `wiki/log.md`.** Format:
   ```
   ## [YYYY-MM-DD HH:MM] ingest | <source title>
   ```
   Then 2–4 bullets summarizing what changed: pages created, pages updated, contradictions surfaced.
6. **Sanity-check.** A typical ingest touches 5–15 pages. If you touched fewer than 3, you probably missed something — re-read the source against the existing wiki and try again.

The marker file at `.ingested/<basename>` is written by the LLM Wiki Manager app, not by you. Do not create or delete these files.

### Query

Triggered by: a question about the wiki content.

Steps:

1. **Read `wiki/index.md` first.** It's the table of contents; use it to identify candidate pages before searching raw text.
2. **Read those pages.** Follow `[[wikilinks]]` if related pages would help.
3. **Synthesize an answer with citations.** Cite specific wiki pages (`[[Page Name]]`) and, where it matters, specific source pages (which themselves cite raw sources).
4. **Offer to file back.** If the answer required non-trivial synthesis — a comparison, an analysis, a connection across sources — ask whether to file it as a new page under `wiki/syntheses/`. Don't file it without asking; the wiki should not bloat from every passing question.

### Lint

Triggered by: *"lint the wiki"* or *"health check"* or similar.

Look for:

- **Contradictions** — pages making incompatible claims that aren't flagged in a `## Contradictions` section
- **Orphan pages** — pages with no inbound `[[wikilinks]]` from any other page
- **Missing pages** — concepts or entities mentioned across 3+ pages but lacking their own page
- **Stale claims** — claims that newer sources have superseded (compare source dates)
- **Index drift** — pages in `wiki/` not listed in `index.md`, or `index.md` entries pointing to deleted pages
- **Cross-reference gaps** — pages that mention an entity/concept by name but don't `[[link]]` to its page

Report findings as a list. **Don't make destructive changes without asking** — orphan deletion, page mergers, and claim retractions all need confirmation. Adding missing cross-references is safe to do unilaterally.

Append a `## [YYYY-MM-DD HH:MM] lint` entry to `log.md` with what was found and what was fixed.

## Page conventions

### Naming

- Use `Title Case With Spaces.md` for filenames. Obsidian resolves `[[wikilinks]]` to these directly.
- Files go in the right subdirectory: `sources/`, `entities/`, `concepts/`, `syntheses/`.
- One concept per page. If a page grows past ~500 lines, consider splitting.

### Frontmatter

Every page starts with YAML frontmatter:

```yaml
---
type: source | entity | concept | synthesis
created: 2026-05-18
updated: 2026-05-18
tags: [tag-one, tag-two]
sources: ["[[Source Page 1]]", "[[Source Page 2]]"]
---
```

Source pages additionally include:

```yaml
source_path: raw/the-original-file.pdf
source_type: pdf | article | transcript | notes | book-chapter
source_url: https://...          # if applicable
source_date: 2024-03-15          # publication/recording date if known
```

`updated:` should be the date of the most recent edit. `sources:` is what makes the Dataview plugin work and is genuinely useful for finding "what have I read about X" later.

### Cross-references

- Use `[[Page Name]]` wikilinks, not standard markdown links. This keeps Obsidian's graph view working.
- Link the first mention of an entity or concept on each page. Don't link every mention — once per page is enough unless the page is very long.
- Don't invent links to pages that don't exist. If you mention an entity that warrants a page, create the page in the same pass.

### Source page template

```markdown
---
type: source
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: []
source_path: raw/filename.ext
source_type: article
source_url: https://...
source_date: YYYY-MM-DD
---

# <Source Title>

**Source:** `raw/filename.ext` · *Type, date, author if known*

## Summary

2–4 paragraphs. What is this source about? What's its main claim, finding, or content?

## Key points

- Specific claim or insight, with enough context to stand alone
- Another specific claim
- ...

## Entities and concepts

This source discusses: [[Entity A]], [[Entity B]], [[Concept X]], [[Concept Y]].

## Notes

Anything else worth recording — caveats, methodology issues, your own observations.
```

### Entity/concept page template

```markdown
---
type: entity        # or: concept
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: []
sources: []
---

# <Name>

One- or two-sentence definition. What is this?

## Overview

The current best understanding, synthesized across all sources. Rewrite this whenever a new source meaningfully changes the picture — don't just append.

## What sources say

- **[[Source A]]:** what this source contributes
- **[[Source B]]:** ...

## Related

[[Related Entity]], [[Related Concept]], ...

## Contradictions

(Only if applicable.) Where sources disagree, with citations to the specific source pages.
```

## Log format

`wiki/log.md` is append-only and chronological. Every entry starts with:

```
## [YYYY-MM-DD HH:MM] <operation> | <subject>
```

Operations: `ingest`, `query`, `lint`, `manual`. Subject is the source title, the question asked, or a short description.

Under each header, 2–4 bullets describing what happened. This format is parseable with `grep "^## \[" wiki/log.md` — useful for me to scan and useful for you to find recent activity.

## When unsure

- **If a source is ambiguous about a claim**, record the ambiguity on the source page rather than picking a side.
- **If two existing pages contradict each other** and a new source resolves it, do the resolution explicitly: cite both, explain which the evidence favors, leave the contradiction note in place.
- **If you're about to delete or merge pages**, stop and ask.
- **If my instructions conflict with these conventions**, follow me. These conventions are defaults; they're meant to be co-evolved. When that happens, propose an update to this file at the end of the session.

## What I do, what you do

- **I do:** source curation, asking questions, deciding what's interesting, editing this schema when defaults stop fitting.
- **You do:** reading, summarizing, cross-referencing, updating, filing, logging, linting, and all the other bookkeeping I would otherwise abandon.

If something feels wrong about how this vault is shaped — page categories that don't fit my domain, conventions that fight my workflow — flag it. This file is meant to change.
