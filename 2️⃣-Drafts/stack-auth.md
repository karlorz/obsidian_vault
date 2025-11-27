  Option 1: Set up Stack Auth (Recommended - 10 mins)

  1. Create free account: https://stack-auth.com
  2. Create a new project
  3. Copy credentials to .env:
  STACK_SECRET_SERVER_KEY=<from Stack dashboard>
  STACK_SUPER_SECRET_ADMIN_KEY=<from Stack dashboard>
  NEXT_PUBLIC_STACK_PROJECT_ID=<from Stack dashboard>
  NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=<from Stack dashboard>
  4. Generate vault secret:
  openssl rand -hex 32
  # Add to STACK_DATA_VAULT_SECRET in .env
  5. Restart the dev server
  