list the cost for deployment:
- MORPH_API_KEY, Morph sandboxes for running Claude Code/Codex/other coding CLIs inside (costy for multiple agent swarms, https://cloud.morph.so/web/subscribe, plan for replacement self-hosted Proxmox VE lxc
- ANTHROPIC_API_KEY
- OPENAI_API_KEY
- CONVEX_DEPLOY_KEY, database, Convex Cloud, switch to self host convex code changes required
- apps/edge-router, Cloudflare Worker that handles the *.cmux.sh (and *.cmux.app) wildcard domain proxy
- NEXT_PUBLIC_SERVER_ORIGIN, apps/server, cmux hono backend hosting
- cmux-client, frontend bond to vercel host, free for low usage
- cmux-www, frontend bond to vercel host, free for low usage