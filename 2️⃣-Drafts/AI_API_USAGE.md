# AI API Usage Report

## Summary & Configuration Matrix

| Service            | Priority 1 (Primary)                                                                  | Priority 2 (Fallback)                                                                                 | Priority 3 (Fallback)                                                                                | Configuration Context & Failsafe                                                                                        |
| :----------------- | :------------------------------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------- |
| **Branch Gen**     | **OpenAI** `gpt-5-nano`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Google** `gemini-2.5-flash`<br>Key: `GEMINI_API_KEY`<br>Url: Standard                               | **Anthropic** `claude-3-5-haiku`<br>Key: `ANTHROPIC_API_KEY`<br>Url: `CLOUDFLARE_ANTHROPIC_BASE_URL` | **FAILSAFE:** Returns deterministic string (e.g., "feature-update") if NO keys are present. **Safe to run without AI.** |
| **Commit Msg Gen** | **OpenAI** `gpt-5-nano`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Google** `gemini-2.5-flash`<br>Key: `GEMINI_API_KEY`<br>Url: Standard                               | **Anthropic** `claude-3-5-haiku`<br>Key: `ANTHROPIC_API_KEY`<br>Url: Standard                        | **FAILSAFE:** Logs "No API keys available, skipping AI generation" and returns `null`. **Safe to run without AI.**      |
| **Convex Crown**   | **OpenAI** `gpt-5-mini`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Anthropic** `claude-3-5-sonnet`<br>Key: `ANTHROPIC_API_KEY`<br>Url: Standard                        | —                                                                                                    | **CRITICAL:** Throws Error if no keys found. AI required.                                                               |
| **PR Narratives**  | **OpenAI** `gpt-5-mini`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Anthropic** `claude-3-5-sonnet`<br>Key: `ANTHROPIC_API_KEY`<br>Url: Standard                        | —                                                                                                    | **CRITICAL:** Throws Error if no keys found. AI required.                                                               |
| **Heatmap Review** | **Anthropic (Bedrock)** `opus-4.5`<br>Key: `AWS_BEARER_TOKEN_BEDROCK`<br>Url: AWS SDK | **OpenAI (Fine-tunes)** `ft:gpt-4.1...`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Anthropic (Bedrock)** `opus-4.1`<br>Key: `AWS_BEARER_TOKEN_BEDROCK`<br>Url: AWS SDK                | **CRITICAL:** Throws Error if configured key is missing. AI required.                                                   |
| **Context7**       | **Context7** (MCP)<br>Key: `CONTEXT7_API_KEY`                                         | —                                                                                                     | —                                                                                                    | **CRITICAL:** AI required for MCP tool execution.                                                                       |

---

## 1) Convex Crown (Evaluation & Summarization)
**Location:** `packages/convex/convex/crown/actions.ts`

Performs technical evaluation of AI-generated code and summarizes changes.

- **Providers:** OpenAI (Preferred) or Anthropic.
- **Models:**
  - OpenAI: `gpt-5-mini`
  - Anthropic: `claude-3-5-sonnet-20241022`
- **Functions:**
  - `performCrownEvaluation`: Selects the best code candidate based on quality, completeness, and best practices.
  - `performCrownSummarization`: Generates PR summaries (What Changed, Review Focus, Test Plan) from git diffs.
- **Configuration Details:**
  - **OpenAI:** Uses **`CLOUDFLARE_OPENAI_BASE_URL`**. Requires `OPENAI_API_KEY`.
  - **Anthropic:** Standard endpoint. Requires `ANTHROPIC_API_KEY`.
- **Failsafe Status:** **None.** Throws `ConvexError("Crown evaluation is not configured...")` if keys are missing.

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
**Location:** `packages/shared/src/utils/openai.ts`, `packages/shared/src/utils/anthropic.ts`

Reference of constants imported across the codebase:

- **`CLOUDFLARE_OPENAI_BASE_URL`**: The primary gateway for all OpenAI-compatible requests (Crown, Heatmap FT, Branch Gen).
- **`CLOUDFLARE_ANTHROPIC_BASE_URL`**: Specific gateway used for Anthropic in Branch Generation.
- **`ANTHROPIC_BASE_URL`**: Used in `host-screenshot-collector` (`https://www.cmux.dev/api/anthropic`).
