# DocBase

Documentation-driven development system for Claude Code. Every piece of code must have a corresponding documentation file. Documentation describes intent, API contracts, field names, and behaviors — run consistency checks manually when ready to verify.

## Concept

DocBase enforces docs as the single source of truth. When docs and code diverge, you find out explicitly — on your terms, not mid-session.

## Frontmatter Conventions

DocBase identifies managed docs by their YAML frontmatter:

```yaml
---
layer: services          # logical layer (api, services, data, etc.)
status: stable           # draft | stable | deprecated
implementation:          # source files this doc describes
  - "[meals.ts](backend/src/services/meals.ts)"
related:                 # cross-references to other doc files
  - "[Meals API](docs/api/meals.md)"
updated: 2026-03-26
---
```

## How It Works

Two manual commands run on demand. No automatic triggers.

| Command | What it checks |
|---|---|
| `/docbase:check-docs` | Cross-references between docs: broken links, asymmetric `related:` entries, semantic conflicts |
| `/docbase:check-code` | Code↔doc conformance: missing implementations, API drift, undocumented source files |

Both commands write issue files to `issues_dir` and output a machine-readable JSON summary — ready for CI/CD consumption.

Typical workflow: write docs → run `/docbase:check-docs` → implement code → run `/docbase:check-code`.

## Installation

### 1. Install the plugin

```sh
/plugin install docbase@michelsciortino-marketplace
```

### 2. Initialize a project

In your project root:

```
/docbase:init
```

This creates `.docbase.json` and updates `.gitignore`.

## Slash Commands

| Command | Description |
|---|---|
| `/docbase:init` | Initialize a project for DocBase |
| `/docbase:check-docs` | Check doc cross-reference consistency |
| `/docbase:check-code` | Check code↔doc conformance |
| `/docbase:issues` | List and manage open issues |
| `/docbase:implement` | Implement docs that have no code yet |

## Requirements

- `jq` (`brew install jq`)
- `claude` CLI (Claude Code)
