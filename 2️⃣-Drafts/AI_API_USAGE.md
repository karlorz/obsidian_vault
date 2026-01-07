# AI API Usage Report

## 1. Convex Crown
**Location:** `packages/convex/convex/crown/actions.ts`

This feature evaluates AI-generated code and summarizes Pull Requests.

*   **Providers:** OpenAI and Anthropic (via Vercel AI SDK).
*   **Models:**
    *   **OpenAI:** `gpt-5-mini` (hardcoded).
    *   **Anthropic:** `claude-3-5-sonnet-20241022` (hardcoded).
*   **Functionality:**
    *   `performCrownEvaluation`: Selects the best code implementation from multiple candidates based on code quality, completeness, and best practices.
    *   `performCrownSummarization`: Generates a concise PR summary (What Changed, Review Focus, Test Plan) based on git diffs.
*   **Configuration:** Requires `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`.

## 2. Heatmap Review
**Location:** `apps/www/lib/services/code-review/run-heatmap-review.ts`

This runs automated code reviews to generate "heatmap" analysis (likely for UI visualization of code hotspots).

*   **Providers:** OpenAI and Anthropic.
*   **Models:** Configurable (via `modelConfig`), typically defaults to high-reasoning models like Anthropic Opus 4.5.
*   **Execution:** Runs directly in the backend (Node.js) without spawning a Morph VM (uses placeholder `heatmap-no-vm`).
*   **Data Source:** Fetches diffs from GitHub API or uses pre-fetched diffs from the client.
*   **Output:** Streams line-by-line analysis to Convex (`automatedCodeReviewFileOutputs` table).

## 3. Context7 & DeepWiki Usage

*   **Context7:**
    *   **Found in:** `dev-docs/opencode` (OpenCode agent implementation).
    *   **Usage:** Integrated as an **MCP (Model Context Protocol) Server**. The OpenCode agent has tool definitions for `context7_resolve_library_id` and `context7_get_library_docs` to search documentation.
    *   **Status:** Active integration in the OpenCode sub-project, but **not present** in the core `cmux` (Convex/Heatmap) logic.

*   **DeepWiki:**
    *   **Found in:** `dev-docs/hono/README.md`.
    *   **Usage:** Appears only as a documentation badge/link (`Ask DeepWiki`).
    *   **Status:** No functional code integration or API usage found in the codebase.

## 4. Other AI Usage
*   **Scripts:** Various scripts (`scripts/local-preview-to-pr.ts`, `scripts/docker-trigger-screenshot.sh`) use `ANTHROPIC_API_KEY`, primarily for visual analysis/screenshot capabilities via Claude.
*   **Gemini:** `scripts/watch-gemini-telemetry.js` monitors Gemini CLI events.
