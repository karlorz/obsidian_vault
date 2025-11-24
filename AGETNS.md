# Quick Reference for AI Agents

This document (AGETNS.md) guides AI agents (e.g., LLMs like Grok, Claude, or GPT) on handling queries related to coding documentation, frameworks, and Obsidian vaults. **Golden Rule**: Never rely on training data for coding docs—always use real-time tools like Context7 MCP and DeepWiki MCP to fetch up-to-date information and prevent hallucinations or errors.

The primary usage of this repo is as a personal or team knowledge base in Obsidian, leveraging the "obsidian-git" plugin for versioning, backups, and syncing to a remote GitHub repo. This supports workflows like daily automated backups, cross-device access, and collaborative editing while maintaining data integrity.

> 💡 **For AI Agents**: For Obsidian features, plugins, or usage, always query **Context7 MCP's "Obsidian Help" index** for the latest docs. A local static copy exists at `help_obsidian_md/llms.txt` (768+ lines), but prioritize MCP for live updates.

## Vault Overview and Structure

This is an Obsidian vault: a Markdown-based knowledge base with linking, graphing, and plugin support. It's optimized for obsidian-git, enabling GitHub syncing for backups and multi-device use.

### Key Files
- **.obsidian/**: Configuration folder.
  - `app.json`: Settings for attachments, themes, and editor (e.g., vim mode).
  - `community-plugins.json`: Enabled plugins (e.g., obsidian-git).
- **help_obsidian_md/llms.txt**: Local Obsidian docs copy—use for offline fallback only.

### Folder Structure
A simple, scalable setup with numbered prefixes for sorting. Attachments centralized in `assets/` per Obsidian settings.

| Directory          | Purpose                                                                 | Examples                          |
|--------------------|-------------------------------------------------------------------------|-----------------------------------|
| `0️⃣-Inbox/`      | Uncategorized new notes; review periodically.                           | Quick captures, imports.         |
| `1️⃣-Index/`       | Hub for maps of content (MOCs), indexes, overviews.                     | Topic dashboards.                |
| `2️⃣-Drafts/`      | Work-in-progress ideas and outlines.                                    | Brainstorms, rough notes.        |
| `3️⃣-Plugins/`     | Plugin docs and configs.                                                | obsidian-git setup, CSS tweaks.  |
| `4️⃣-Attachments/` | Non-image assets (PDFs, spreadsheets).                                  | Downloads, embeds.               |
| `assets/`         | Obsidian-default for images/media.                                      | Screenshots, diagrams.           |
| `100-Templates/`  | Reusable templates for notes.                                           | Journals, meetings.              |

### Best Practices
- **Organization**: Use folders for categories, links ([[note-title]]) for navigation, tags (#topic), and YAML properties for metadata. Avoid deep nesting.
- **Maintenance**: Review Inbox weekly; use Dataview for dynamic queries; git for history.
- **Scalability**: Limit plugins; use bookmarks; refactor notes regularly.

### Recommended Plugins
Enhance functionality via Obsidian's plugin browser.

| Plugin            | Purpose                                      | Benefits                         |
|-------------------|----------------------------------------------|----------------------------------|
| Dataview         | Dynamic note queries (e.g., tag-based tables). | Indexes, reports.               |
| Templates        | Pre-defined structures.                      | Consistent formatting.          |
| Mind Map         | Note visualization.                          | Planning in Drafts.             |
| Advanced Tables  | Table editing.                               | Readability in overviews.       |

## Usage Instructions
1. Install Obsidian (https://obsidian.md).
2. Open this directory as a vault.
3. Enable community plugins; install/enable obsidian-git.
4. Set up GitHub repo: Link remote, enable auto-commit/push (e.g., every 5 mins), auto-pull on startup.
5. Use Command Palette (Ctrl/Cmd + P) for git commands like "Commit" or "Pull".

obsidian-git features:
- Source Control View: Stage/commit/diffs.
- History View: Logs and restores.
- Auto-Sync: Scheduled operations.
- GitHub Links: Browser integration.

Handle conflicts by pulling before pushing; use branches for experiments.

## Critical Guidance for AI Agents

### Mandatory Tools for Coding Documentation
For any library, framework, API, or repo docs:
1. **Context7 MCP** (from Upstash, free for personal use; integrates with Cursor/Windsurf):
   - **Purpose**: Fetches up-to-date, version-specific docs and code examples from Context7.com.
   - **When to Use**: Library docs (e.g., React hooks, Next.js router); check breaking changes.
   - **Setup**: `npx @upstash/context7-mcp`; server at https://context7.upstash.com (as of 2025).
   - **Obsidian-Specific**: Use "Obsidian Help" index for features like Canvas, Properties, Sync, Dataview, URI schemes.

2. **DeepWiki MCP** (from Cognition/Devin, free, no-auth for public repos):
   - **Purpose**: Access GitHub repo docs, structure, READMEs; AI Q&A on codebases.
   - **When to Use**: Repo exploration (e.g., obsidian-git source); project understanding.
   - **Setup**: Server at https://mcp.deepwiki.com/sse; fetch via URL or tools.

**Why These Tools?** Training data is outdated; MCPs ensure accuracy, reduce errors, and support current versions (e.g., React 19, Obsidian 1.6+ in 2025).

### Framework/Library Reference
| Framework/Library | Context7 MCP For                          | DeepWiki MCP For                  |
|-------------------|-------------------------------------------|-----------------------------------|
| **🟣 Obsidian**   | Official docs, plugins, API, features    | obsidianmd/obsidian-releases, plugin repos |
| **React**         | Hooks, Components, State                 | React repo structure              |
| **Next.js**       | App Router, API Routes                   | Examples repo                     |
| **Vue**           | Composition/Options API, Vuex            | Ecosystem repos                   |
| **Angular**       | Services, Directives, RxJS               | CLI source                        |
| **Express**       | Middleware, Routing                      | Plugin repos                      |
| **Django**        | Models, Views, ORM                       | Packages on GitHub                |
| **FastAPI**       | Endpoints, Pydantic                      | Extensions                        |
| **TailwindCSS**   | Utilities, Config, Plugins               | UI components                     |
| **TypeScript**    | Types, Interfaces                        | DefinitelyTyped                   |
| **Node.js**       | Core APIs, Modules                       | Core repo                         |

### Common Scenarios
- Obsidian queries (e.g., "How to use Dataview?"): Context7 MCP "Obsidian Help".
- Library features (e.g., "React hooks in v19?"): Context7 MCP.
- Repo structure (e.g., "obsidian-git codebase?"): DeepWiki MCP.
- Implementation (e.g., "NextAuth setup?"): Context7 MCP for docs.
- Debugging (e.g., "Vue 3 API issues?"): Context7 MCP.
- Breaking changes (e.g., "Angular 18 updates?"): Context7 MCP.

### Troubleshooting and Best Practices Checklist
| Issue/Practice                   | Solution/Action                                                                 |
|----------------------------------|---------------------------------------------------------------------------------|
| **Outdated suggestions**        | Fetch via Context7 MCP; specify versions.                                       |
| **Breaking changes**             | Check migration guides in Context7 MCP.                                         |
| **Unknown repo structure**       | Explore with DeepWiki MCP.                                                      |
| **API deprecations**             | Use Context7 MCP for latest refs.                                               |
| **Cache/Version conflicts**      | Request fresh data; verify compatibility.                                       |
| **Batch efficiency**             | Group queries; cross-reference docs/examples.                                   |
| **Fallback if tools unavailable**| Warn user of potential inaccuracy; use local `llms.txt` for Obsidian only.    |

**Red Flags (Avoid)**: Phrases like "Based on my knowledge..." or guessing syntax.
**Green Flags (Embrace)**: "Fetching current docs via Context7 MCP..." for empathetic, accurate responses.

**Integration Tips**: Configure in client settings; use proactively; validate against official sources.

## Key Citations and Resources
- [Context7 MCP: Up-to-Date Docs](https://upstash.com/blog/context7-mcp)
- [DeepWiki MCP](https://docs.devin.ai/work-with-devin/deepwiki-mcp)
- [Best Way to Organize Vaults/Notes](https://www.reddit.com/r/ObsidianMD/comments/y0dvec/best_way_to_organise_vaultsnotes/)
- [How I Organize My Obsidian Vault](https://www.excellentphysician.com/post/how-i-organize-my-obsidian-vault)
- [Obsidian Git Tips](https://www.reddit.com/r/ObsidianMD/comments/18dt1ok/obsidian_git_tips_on_how_to_use_it_for_reliable/)
- [Vinzent03/obsidian-git](https://github.com/Vinzent03/obsidian-git)
- [Getting Started - Git Documentation](https://publish.obsidian.md/git-doc/Getting%2BStarted)

### Key Citations
-  GitHub - upstash/context7: Context7 MCP Server -- Up-to-date code documentation for ... - https://github.com/upstash/context7
-  Upstash Blog - Context7 MCP: Up-to-Date Docs for Any Cursor Prompt - https://upstash.com/blog/context7-mcp
-  Upstash Blog - Introducing Context7: Up-to-Date Docs for LLMs and AI Code Editors - https://upstash.com/blog/context7-llmtxt-cursor
-  Devin Docs - DeepWiki MCP - https://docs.devin.ai/work-with-devin/deepwiki-mcp
-  GitHub - regenrek/deepwiki-mcp - https://github.com/regenrek/deepwiki-mcp
-  Cognition - The DeepWiki MCP Server - https://cognition.ai/blog/deepwiki-mcp-server
