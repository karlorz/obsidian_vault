# AI API Usage Report

## 1) Convex Crown
**Location:** `packages/convex/convex/crown/actions.ts`

Evaluates AI-generated code and summarizes PRs.

- **Providers:** OpenAI or Anthropic via Vercel AI SDK, picked by available key.
- **Models:** OpenAI `gpt-5-mini`; Anthropic `claude-3-5-sonnet-20241022` (hardcoded).
- **Functions:**
  - `performCrownEvaluation`: chooses best candidate across diffs; prefers quality/completeness/best practices.
  - `performCrownSummarization`: PR summary (What Changed, Review Focus, Test Plan) from git diff.
- **Config:** requires `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` (OpenAI wins if both set).

## 2) Heatmap Review
**Location:** `apps/www/lib/services/code-review/run-heatmap-review.ts`

Automated diff review that streams line-by-line importance to Convex (table `automatedCodeReviewFileOutputs`). No Morph VM (`heatmap-no-vm`).

- **Providers:** OpenAI or Anthropic based on `model-config.ts`.
- **Default model:** Anthropic Opus 4.5 from `getDefaultHeatmapModelConfig()`; OpenAI fine-tunes optional.
- **Data:** Uses pre-fetched diffs when provided; otherwise pulls PR/compare diffs via GitHub API.
- **Validation:** Throws if needed API key missing for chosen provider.

## 3) Branch/PR Generation (missing before)
**Location:** `apps/www/lib/utils/branch-name-generator.ts`

Generates branch names and PR titles for new tasks with provider fallback.

- **Provider order:** OpenAI `gpt-5-nano` (via Cloudflare OpenAI base URL) -> Gemini `gemini-2.5-flash` -> Anthropic `claude-3-5-haiku-20241022`; otherwise deterministic fallback.
- **Output:** Very short hyphenated branch slug + concise PR title. Branches are prefixed `cmux/` and suffixed with a random 5-char id.
- **Environment merge:** Uses passed-in keys; merges with `env` for missing ones. Logs provider used; falls back silently on errors.

## 4) Context7 & DeepWiki

- **Context7:** Integrated as an MCP server inside OpenCode (`dev-docs/opencode`). Tools `context7_resolve_library_id` and `context7_get_library_docs`. Not used in crown/heatmap code paths.
- **DeepWiki:** Only documentation links (e.g., `dev-docs/hono/README.md` badge). No runtime API usage.

## 5) Other AI Usage

- **Scripts:** `scripts/local-preview-to-pr.ts`, `scripts/docker-trigger-screenshot.sh` use `ANTHROPIC_API_KEY` for visual/screenshot flows.
- **Gemini telemetry:** `scripts/watch-gemini-telemetry.js` monitors Gemini CLI events.

## 6) Latest provider notes (Vercel AI SDK v6)

- Use dedicated providers: `@ai-sdk/openai`, `@ai-sdk/anthropic`, `@ai-sdk/google`; or `createOpenAICompatible` for OpenAI-style APIs (e.g., Groq).
- Model selection examples: `openai("gpt-4-turbo")`, `anthropic("claude-3-5-sonnet-20241022")`, `google("gemini-2.5-flash")`. Multi-modal streaming via `streamText` with model strings like `anthropic/claude-sonnet-4-20250514` or `google/gemini-2.5-flash`.
- Streaming/text generation: `generateText`/`streamText` accept `model` instances; set API keys in env and install provider packages. Gateway routing supports `model: "openai/gpt-4-turbo"` if using Vercel AI Gateway.
