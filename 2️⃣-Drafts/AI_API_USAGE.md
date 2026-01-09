# AI API Usage Report

## 1) Convex Crown & PR Narratives
**Location:** `packages/convex/convex/crown/actions.ts`, `packages/convex/convex/github_pr_comments.ts`

Evaluates AI-generated code, summarizes PRs, and generates "Preview Stories" for PR screenshots.

- **Providers:** OpenAI or Anthropic via Vercel AI SDK, picked by available key.
- **Models:**
  - OpenAI: `gpt-5-mini` (Default for evaluation/narratives)
  - Anthropic: `claude-3-5-sonnet-20241022` (Fallback)
- **Functions:**
  - `performCrownEvaluation`: chooses best candidate across diffs; prefers quality/completeness/best practices.
  - `performCrownSummarization`: PR summary (What Changed, Review Focus, Test Plan) from git diff.
  - `generatePreviewNarrative`: Generates a structured JSON "story" for PR screenshot previews (Headline, Story bullets, Review Focus).
- **Config:** requires `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` (OpenAI wins if both set). Uses `CLOUDFLARE_OPENAI_BASE_URL` for OpenAI.

## 2) Heatmap & Simple Review
**Location:** `apps/www/lib/services/code-review/run-heatmap-review.ts`, `model-config.ts`

Automated diff review that streams line-by-line importance to Convex. Supports multiple fine-tuned variants.

- **Providers:** OpenAI or Anthropic based on selection (Defaults to Anthropic via Bedrock).
- **Anthropic Models (via AWS Bedrock):**
  - `global.anthropic.claude-opus-4-5-20251101-v1:0` (Default "Opus 4.5")
  - `global.anthropic.claude-opus-4-1-20250807-v1:0` ("Opus 4.1")
- **OpenAI Models (Fine-tuned):**
  - Heatmap SFT: `ft:gpt-4.1-mini-2025-04-14:lawrence:cmux-heatmap-sft:CZW6Lc77`
  - Heatmap Dense: `ft:gpt-4.1-mini-2025-04-14:lawrence:cmux-heatmap-dense:CaaqvYVO`
  - Heatmap Dense V2: `ft:gpt-4.1-2025-04-14:lawrence:cmux-heatmap-dense-4-1:CahKn54r`
- **Validation:** requires `OPENAI_API_KEY` for OpenAI models or `AWS_BEARER_TOKEN_BEDROCK` for Anthropic Bedrock models.

## 3) Branch & Commit Message Generation
**Location:** `apps/www/lib/utils/branch-name-generator.ts`, `apps/server/src/utils/commitMessageGenerator.ts`

Generates semantic branch names and commit messages for tasks with provider fallback.

- **Provider Priority:**
  1. OpenAI: `gpt-5-nano` (via `CLOUDFLARE_OPENAI_BASE_URL`)
  2. Google: `gemini-2.5-flash`
  3. Anthropic: `claude-3-5-haiku-20241022`
- **Environment merge:** Uses passed-in keys; merges with `env` for missing ones. Falls back deterministicly if no keys found.

## 4) Context7 (MCP)
**Location:** Integrated as an MCP server for documentation searching.

- **URL:** `https://mcp.context7.com/mcp`
- **Key Var:** `CONTEXT7_API_KEY`
- **Capabilities:** `context7_resolve_library_id`, `context7_get_library_docs`.

## 5) Agent CLI Configurations
**Location:** `packages/shared/src/agentConfig.ts`, `packages/shared/src/providers/*`

The following models are available within the cmux terminal environment via their respective CLIs:

| Provider | Key Models / Versions |
| :--- | :--- |
| **Claude Code** | `claude-opus-4.5`, `claude-sonnet-4.5`, `claude-haiku-4.5`, `claude-sonnet-4` |
| **Codex** | `gpt-5.2-codex` (reasoning variants), `gpt-5.1-codex-max`, `o3`, `o4-mini` |
| **Gemini** | `gemini-3-pro-preview`, `gemini-2.5-flash`, `gemini-2.5-pro` |
| **OpenCode** | `gpt-5`, `o3-pro`, `grok-4-1-fast`, `kimi-k2`, `qwen3-coder` |
| **Qwen** | `qwen3-coder:free` (OpenRouter), `qwen3-coder-plus` (ModelStudio) |
| **Amp** | `amp` (default), `amp/gpt-5` |

## 6) Latest provider notes (Vercel AI SDK v6)

- Use dedicated providers: `@ai-sdk/openai`, `@ai-sdk/anthropic`, `@ai-sdk/google`; or `createOpenAICompatible` for OpenAI-style APIs.
- Model selection examples: `openai("gpt-4-turbo")`, `anthropic("claude-3-5-sonnet-20241022")`, `google("gemini-2.5-flash")`.
- Multi-modal streaming via `streamText` with model strings like `anthropic/claude-sonnet-4-20250514` or `google/gemini-2.5-flash`.
