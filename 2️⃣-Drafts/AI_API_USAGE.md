# AI API Usage Report

## Summary & Configuration Matrix

| Service            | Priority 1 (Primary)                                                                  | Priority 2 (Fallback)                                                                                 | Priority 3 (Fallback)                                                                                | Configuration Context & Failsafe                                                                                        |
| :----------------- | :------------------------------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------- |
| **Branch Gen**     | **OpenAI** `gpt-5-nano`<br>Key: `OPENAI_API_KEY`<br>Url: `AIGATEWAY_OPENAI_BASE_URL` or `CLOUDFLARE_OPENAI_BASE_URL` | **Google** `gemini-2.5-flash`<br>Key: `GEMINI_API_KEY`<br>Url: Standard                               | **Anthropic** `claude-3-5-haiku`<br>Key: `ANTHROPIC_API_KEY`<br>Url: `CLOUDFLARE_ANTHROPIC_BASE_URL` | **FAILSAFE:** Returns deterministic string (e.g., "feature-update") if NO keys are present. **Safe to run without AI.** |
| **Commit Msg Gen** | **OpenAI** `gpt-5-nano`<br>Key: `OPENAI_API_KEY`<br>Url: `AIGATEWAY_OPENAI_BASE_URL` or `CLOUDFLARE_OPENAI_BASE_URL` | **Google** `gemini-2.5-flash`<br>Key: `GEMINI_API_KEY`<br>Url: Standard                               | **Anthropic** `claude-3-5-haiku`<br>Key: `ANTHROPIC_API_KEY`<br>Url: Standard                        | **FAILSAFE:** Logs "No API keys available, skipping AI generation" and returns `null`. **Safe to run without AI.**      |
| **Convex Crown**   | **OpenAI** `gpt-5-mini`<br>Key: `OPENAI_API_KEY`<br>Url: `AIGATEWAY_OPENAI_BASE_URL` or `CLOUDFLARE_OPENAI_BASE_URL` | **Anthropic** `claude-3-5-sonnet`<br>Key: `ANTHROPIC_API_KEY`<br>Url: `AIGATEWAY_ANTHROPIC_BASE_URL` or `CLOUDFLARE_ANTHROPIC_BASE_URL` | **Google** `gemini-3-flash-preview`<br>Key: `GEMINI_API_KEY`<br>Url: `AIGATEWAY_GEMINI_BASE_URL` or Standard | **CRITICAL:** Throws Error if no keys found. AI required.                                                               |
| **PR Narratives**  | **OpenAI** `gpt-5-mini`<br>Key: `OPENAI_API_KEY`<br>Url: `AIGATEWAY_OPENAI_BASE_URL` or `CLOUDFLARE_OPENAI_BASE_URL` | **Anthropic** `claude-3-5-sonnet`<br>Key: `ANTHROPIC_API_KEY`<br>Url: `AIGATEWAY_ANTHROPIC_BASE_URL` or `CLOUDFLARE_ANTHROPIC_BASE_URL` | **Google** `gemini-3-flash-preview`<br>Key: `GEMINI_API_KEY`<br>Url: `AIGATEWAY_GEMINI_BASE_URL` or Standard | **CRITICAL:** Throws Error if no keys found. AI required.                                                               |
| **Heatmap Review** | **Anthropic (Bedrock)** `opus-4.5`<br>Key: `AWS_BEARER_TOKEN_BEDROCK`<br>Url: AWS SDK | **OpenAI (Fine-tunes)** `ft:gpt-4.1...`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Anthropic (Bedrock)** `opus-4.1`<br>Key: `AWS_BEARER_TOKEN_BEDROCK`<br>Url: AWS SDK                | **CRITICAL:** Throws Error if configured key is missing. AI required.                                                   |
| **Context7**       | **Context7** (MCP)<br>Key: `CONTEXT7_API_KEY`                                         | —                                                                                                     | —                                                                                                    | **CRITICAL:** AI required for MCP tool execution.                                                                       |

---

## 1) Convex Crown (Evaluation & Summarization)
**Location:** `packages/convex/convex/crown/actions.ts`

Performs technical evaluation of AI-generated code and summarizes changes.

- **Providers:** OpenAI (Preferred), Anthropic (Fallback), or Gemini (Fallback).
- **Models:**
  - OpenAI: `gpt-5-mini` (defined as `OPENAI_CROWN_MODEL`)
  - Anthropic: `claude-sonnet-4-5-20250929` (defined as `ANTHROPIC_CROWN_MODEL`)
  - Gemini: `gemini-3-flash-preview` (defined as `GEMINI_CROWN_MODEL`)
- **Functions:**
  - `performCrownEvaluation`: Selects the best code candidate based on quality, completeness, and best practices.
  - `performCrownSummarization`: Generates PR summaries (What Changed, Review Focus, Test Plan) from git diffs.
- **Configuration Details:**
  - **OpenAI:** Uses `AIGATEWAY_OPENAI_BASE_URL` (if set) or `CLOUDFLARE_OPENAI_BASE_URL`. Requires `OPENAI_API_KEY`.
  - **Anthropic:** Uses `AIGATEWAY_ANTHROPIC_BASE_URL` (if set) or `CLOUDFLARE_ANTHROPIC_BASE_URL`. Requires `ANTHROPIC_API_KEY`.
  - **Gemini:** Uses `AIGATEWAY_GEMINI_BASE_URL` (if set) or `CLOUDFLARE_GEMINI_BASE_URL` (standard Google endpoint). Requires `GEMINI_API_KEY`.
- **Environment Variables:** Accessed via `process.env` directly (not `createEnv` schema) to allow proper deletion via `npx convex env remove`.
- **Temperature Settings:**
  - OpenAI: No temperature (GPT-5 models don't support temperature parameter)
  - Anthropic: `temperature: 0`
  - Gemini: `temperature: 0`
- **Failsafe Status:** **None.** Throws `ConvexError("Crown evaluation is not configured...")` if ALL keys are missing.

## 2) PR Narratives (Screenshot Stories)
**Location:** `packages/convex/convex/github_pr_comments.ts`

Generates "Preview Stories"—structured narratives describing UI changes based on screenshots captured during preview runs.

- **Providers:** OpenAI (Preferred) or Anthropic.
- **Models:**
  - OpenAI: `gpt-5-mini`
  - Anthropic: `claude-3-5-sonnet-20241022`
- **Functions:**
  - `generatePreviewNarrative`: Produces a JSON object containing a Headline, Story bullets, Review Focus, Risks, and Image Captions.
- **Configuration Details:**
  - Shares the same configuration logic as Crown.
  - **OpenAI:** Uses **`CLOUDFLARE_OPENAI_BASE_URL`**. Requires `OPENAI_API_KEY`.
  - **Anthropic:** Standard endpoint. Requires `ANTHROPIC_API_KEY`.
- **Failsafe Status:** **None.** Throws Error if keys are missing.

## 3) Heatmap & Simple Review
**Location:** `apps/www/lib/services/code-review/run-heatmap-review.ts`, `model-config.ts`

Automated diff review streaming importance scores to Convex.

- **Anthropic (Default via Bedrock):**
  - **Model:** `global.anthropic.claude-opus-4-5-20251101-v1:0`
  - **Config:** Uses AWS SDK directly. Requires **`AWS_BEARER_TOKEN_BEDROCK`**. Does **NOT** use a custom Base URL constant.
- **OpenAI (Fine-tuned Alternatives):**
  - **Models:** `ft:gpt-4.1-mini...heatmap-sft`, `ft:gpt-4.1...heatmap-dense-4-1`
  - **Config:** Uses **`CLOUDFLARE_OPENAI_BASE_URL`**. Requires `OPENAI_API_KEY`.
- **Failsafe Status:** **None.** Throws specific Errors (e.g., "OPENAI_API_KEY environment variable is required") if the selected provider's key is missing.

## 4) Branch & Commit Message Generation
**Location:** `apps/www/lib/utils/branch-name-generator.ts`, `apps/server/src/utils/commitMessageGenerator.ts`

Generates semantic branch names and commit messages.

- **Provider Priority & Config:**
  1.  **OpenAI** (`gpt-5-nano`):
      - Config: Uses **`CLOUDFLARE_OPENAI_BASE_URL`**.
      - Key: `OPENAI_API_KEY`.
  2.  **Google** (`gemini-2.5-flash`):
      - Config: Standard Google AI endpoint.
      - Key: **`GEMINI_API_KEY`**.
  3.  **Anthropic** (`claude-3-5-haiku-20241022`):
      - Config: Uses **`CLOUDFLARE_ANTHROPIC_BASE_URL`**.
      - Key: `ANTHROPIC_API_KEY`.

- **Failsafe Status:** **Robust.**
  - **Branch Gen:** If no keys are present, falls back to deterministic generation (e.g., "feature-update"). **Low Priority for Audit.**
  - **Commit Msg:** If no keys are present, logs "No API keys available, skipping AI generation" and returns `null` (allowing the user/system to handle it manually). **Low Priority for Audit.**

## 5) Context7 (MCP)
**Location:** `dev-docs/opencode` (Integrated as MCP server)

- **Config:**
  - **Base URL:** `https://mcp.context7.com/mcp` (MCP Endpoint)
  - **Key:** `CONTEXT7_API_KEY`

## 6) Agent CLI Configurations
**Location:** `packages/shared/src/agentConfig.ts`

CLI Agents running in the terminal environment.

| Provider | Config / Auth | Key Models |
| :--- | :--- | :--- |
| **Claude Code** | Standard Anthropic Auth | `claude-opus-4.5`, `claude-sonnet-4.5` |
| **Codex** | OpenAI Auth | `gpt-5.2-codex`, `o3`, `o4-mini` |
| **Gemini** | Google Auth | `gemini-3-pro-preview`, `gemini-2.5-flash` |
| **OpenCode** | OpenAI Compatible | `gpt-5`, `grok-4-1-fast`, `qwen3-coder` |

## 7) Shared Configuration Constants
**Location:** `packages/shared/src/utils/openai.ts`, `packages/shared/src/utils/anthropic.ts`, `packages/shared/src/utils/gemini.ts`

Reference of constants imported across the codebase:

- **`CLOUDFLARE_OPENAI_BASE_URL`**: Default gateway for OpenAI-compatible requests (Crown, Heatmap FT, Branch Gen).
- **`CLOUDFLARE_ANTHROPIC_BASE_URL`**: Default gateway for Anthropic requests (Crown, Branch Gen).
- **`CLOUDFLARE_GEMINI_BASE_URL`**: Default endpoint for Gemini requests (`https://generativelanguage.googleapis.com/v1beta`).
- **`ANTHROPIC_BASE_URL`**: Used in `host-screenshot-collector` (`https://www.cmux.dev/api/anthropic`).

### AI Gateway URL Override Environment Variables

These optional environment variables allow custom proxy/gateway URLs:

| Variable | Description | Default Fallback |
|----------|-------------|------------------|
| `AIGATEWAY_OPENAI_BASE_URL` | Custom OpenAI gateway URL | `CLOUDFLARE_OPENAI_BASE_URL` |
| `AIGATEWAY_ANTHROPIC_BASE_URL` | Custom Anthropic gateway URL | `CLOUDFLARE_ANTHROPIC_BASE_URL` |
| `AIGATEWAY_GEMINI_BASE_URL` | Custom Gemini gateway URL | `CLOUDFLARE_GEMINI_BASE_URL` |

**Note:** These are accessed via `process.env` directly in Convex to avoid schema validation issues when deleting environment variables.
