# AI API Usage Report

## Summary & Configuration Matrix

| Service                   | Priority 1 (Primary)                                                                  | Priority 2 (Fallback)                                                                                 | Priority 3 (Fallback)                                                                                | Configuration Context                                                                                                     |
| :------------------------ | :------------------------------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------ |
| **Branch & Commit Gen**   | **OpenAI** `gpt-5-nano`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Google** `gemini-2.5-flash`<br>Key: `GOOGLE_GENERATIVE_AI_API_KEY`<br>Url: Standard                 | **Anthropic** `claude-3-5-haiku`<br>Key: `ANTHROPIC_API_KEY`<br>Url: `CLOUDFLARE_ANTHROPIC_BASE_URL` | **Multi-provider fallback:** Tries OpenAI (via Cloudflare) -> Google (Direct) -> Anthropic (via Cloudflare).              |
| **Crown & PR Narratives** | **OpenAI** `gpt-5-mini`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Anthropic** `claude-3-5-sonnet`<br>Key: `ANTHROPIC_API_KEY`<br>Url: Standard                        | —                                                                                                    | **Logic:** Uses OpenAI if key exists (routed via Cloudflare); otherwise falls back to standard Anthropic client.          |
| **Heatmap Review**        | **Anthropic (Bedrock)** `opus-4.5`<br>Key: `AWS_BEARER_TOKEN_BEDROCK`<br>Url: AWS SDK | **OpenAI (Fine-tunes)** `ft:gpt-4.1...`<br>Key: `OPENAI_API_KEY`<br>Url: `CLOUDFLARE_OPENAI_BASE_URL` | **Anthropic (Bedrock)** `opus-4.1`<br>Key: `AWS_BEARER_TOKEN_BEDROCK`<br>Url: AWS SDK                | **Selection:** Default is Bedrock Opus 4.5. Users can explicitly select fine-tuned OpenAI models (routed via Cloudflare). |
| **Context7**              | **Context7** (MCP)<br>Key: `CONTEXT7_API_KEY`                                         | —                                                                                                     | —                                                                                                    | **MCP Tool:** `https://mcp.context7.com/mcp`                                                                              |

---

## 1) Convex Crown & PR Narratives
**Location:** `packages/convex/convex/crown/actions.ts`, `packages/convex/convex/github_pr_comments.ts`

Evaluates AI-generated code, summarizes PRs, and generates "Preview Stories" for screenshots.

- **Providers:** OpenAI (Preferred) or Anthropic.
- **Models:**
  - OpenAI: `gpt-5-mini`
  - Anthropic: `claude-3-5-sonnet-20241022`
- **Configuration Details:**
  - **OpenAI:** Uses **`CLOUDFLARE_OPENAI_BASE_URL`** as the `baseURL`. Requires `OPENAI_API_KEY`.
  - **Anthropic:** Standard endpoint. Requires `ANTHROPIC_API_KEY`.
  - *Logic:* Checks `OPENAI_API_KEY` first; if present, constructs OpenAI client with Cloudflare Base URL. Else falls back to Anthropic.

## 2) Heatmap & Simple Review
**Location:** `apps/www/lib/services/code-review/run-heatmap-review.ts`, `model-config.ts`

Automated diff review streaming importance scores to Convex.

- **Anthropic (Default via Bedrock):**
  - **Model:** `global.anthropic.claude-opus-4-5-20251101-v1:0`
  - **Config:** Uses AWS SDK directly. Requires **`AWS_BEARER_TOKEN_BEDROCK`**. Does **NOT** use a custom Base URL constant.
- **OpenAI (Fine-tuned Alternatives):**
  - **Models:** `ft:gpt-4.1-mini...heatmap-sft`, `ft:gpt-4.1...heatmap-dense-4-1`
  - **Config:** Uses **`CLOUDFLARE_OPENAI_BASE_URL`**. Requires `OPENAI_API_KEY`.

## 3) Branch & Commit Message Generation
**Location:** `apps/www/lib/utils/branch-name-generator.ts`, `apps/server/src/utils/commitMessageGenerator.ts`

Generates semantic branch names and commit messages.

- **Provider Priority & Config:**
  1.  **OpenAI** (`gpt-5-nano`):
      - Config: Uses **`CLOUDFLARE_OPENAI_BASE_URL`**.
      - Key: `OPENAI_API_KEY`.
  2.  **Google** (`gemini-2.5-flash`):
      - Config: Standard Google AI endpoint.
      - Key: `GOOGLE_GENERATIVE_AI_API_KEY`.
  3.  **Anthropic** (`claude-3-5-haiku-20241022`):
      - Config: Uses **`CLOUDFLARE_ANTHROPIC_BASE_URL`**.
      - Key: `ANTHROPIC_API_KEY`.

## 4) Context7 (MCP)
**Location:** `dev-docs/opencode` (Integrated as MCP server)

- **Config:**
  - **Base URL:** `https://mcp.context7.com/mcp` (MCP Endpoint)
  - **Key:** `CONTEXT7_API_KEY`

## 5) Agent CLI Configurations
**Location:** `packages/shared/src/agentConfig.ts`

CLI Agents running in the terminal environment.

| Provider | Config / Auth | Key Models |
| :--- | :--- | :--- |
| **Claude Code** | Standard Anthropic Auth | `claude-opus-4.5`, `claude-sonnet-4.5` |
| **Codex** | OpenAI Auth | `gpt-5.2-codex`, `o3`, `o4-mini` |
| **Gemini** | Google Auth | `gemini-3-pro-preview`, `gemini-2.5-flash` |
| **OpenCode** | OpenAI Compatible | `gpt-5`, `grok-4-1-fast`, `qwen3-coder` |

## 6) Shared Configuration Constants
**Location:** `packages/shared/src/utils/openai.ts`, `packages/shared/src/utils/anthropic.ts`

Reference of constants imported across the codebase:

- **`CLOUDFLARE_OPENAI_BASE_URL`**: The primary gateway for all OpenAI-compatible requests (Crown, Heatmap FT, Branch Gen).
- **`CLOUDFLARE_ANTHROPIC_BASE_URL`**: Specific gateway used for Anthropic in Branch Generation.
- **`ANTHROPIC_BASE_URL`**: Used in `host-screenshot-collector` (`https://www.cmux.dev/api/anthropic`).
