# Monorepo Migration Plan: data-labeling

> **Goal**: Migrate `data-labeling` project to a monorepo structure that includes `@karlorz/react-image-annotate` as a workspace package.

## Overview

### Current State
```
data-labeling/           # Main repo
├── web/                 # React frontend
├── svc/                 # Python backend
└── package.json         # Minimal root config

react-image-annotate/    # SEPARATE repo (external)
└── ...                  # Linked via `bun link`
```

### Target State
```
data-labeling/
├── apps/
│   └── web/             # React frontend (moved)
├── packages/
│   └── react-image-annotate/  # Library (merged)
├── svc/                 # Python backend (unchanged)
├── package.json         # Workspace root config
├── bun.lock             # Single lockfile
└── makefile             # Updated paths
```

---

## Migration Steps

### Phase 1: Prepare Directory Structure

#### Step 1.1: Create new directories
```bash
cd /Users/karlchow/Desktop/code/data-labeling
mkdir -p apps packages
```

#### Step 1.2: Move web app to apps/
```bash
# Move the web directory
mv web apps/web

# Update any hardcoded paths in configs
```

#### Step 1.3: Copy react-image-annotate into packages/
```bash
# Option A: Copy from existing local path
cp -r /path/to/react-image-annotate packages/react-image-annotate

# Option B: Clone fresh (preserves git history as subtree)
git subtree add --prefix=packages/react-image-annotate \
  git@github.com:karlorz/react-image-annotate.git main --squash
```

> **Note**: Using `git subtree` allows you to push changes back to the original repo if needed.

---

### Phase 2: Configure Workspace

#### Step 2.1: Update root package.json
Replace the current minimal `package.json` with:

```json
{
  "name": "data-labeling-monorepo",
  "private": true,
  "workspaces": [
    "apps/*",
    "packages/*"
  ],
  "scripts": {
    "dev": "bun run --cwd apps/web dev",
    "dev:lib": "bun run --cwd packages/react-image-annotate dev",
    "build": "bun run build:lib && bun run build:web",
    "build:web": "bun run --cwd apps/web build",
    "build:lib": "bun run --cwd packages/react-image-annotate build",
    "lint": "bun run --cwd apps/web lint",
    "type-check": "bun run --cwd apps/web type-check"
  },
  "devDependencies": {
    "typescript": "^5.9.3"
  }
}
```

#### Step 2.2: Update apps/web/package.json
Change the dependency from npm version to workspace:

```json
{
  "name": "@data-labeling/web",
  "private": true,
  "version": "0.2.6",
  "dependencies": {
    "@karlorz/react-image-annotate": "workspace:*"
  }
}
```

**Key change**: `"^4.0.7"` → `"workspace:*"`

#### Step 2.3: Verify packages/react-image-annotate/package.json
Ensure it has the correct name:

```json
{
  "name": "@karlorz/react-image-annotate",
  "version": "4.0.7",
  "main": "dist/index.js",
  "types": "dist/index.d.ts"
}
```

---

### Phase 3: Update Build Configuration

#### Step 3.1: Update makefile paths

**Changes needed:**

```makefile
# OLD
FRONTEND_DIR = ./web

# NEW
FRONTEND_DIR = ./apps/web
LIB_DIR = ./packages/react-image-annotate
```

**Updated targets:**

```makefile
FRONTEND_DIR = ./apps/web
LIB_DIR = ./packages/react-image-annotate
BACKEND_DIR = .
VERSION_FILE = ./VERSION

.PHONY: all install build-frontend build-lib start-frontend start-backend

# Install all workspace dependencies
install:
	@echo "Installing all workspace dependencies..."
	@bun install

# Build library first, then frontend
build-all: build-lib build-frontend

build-lib:
	@echo "Building react-image-annotate library..."
	@cd $(LIB_DIR) && bun run build

build-frontend:
	@echo "Building frontend..."
	@cd $(FRONTEND_DIR) && bun run build

# Local development
all: build-lib build-frontend start-backend

# Start frontend dev with HMR
start-frontend:
	@echo "Starting frontend dev server..."
	@cd $(FRONTEND_DIR) && bun run dev

# Watch mode for library development
dev-lib:
	@echo "Starting library in watch mode..."
	@cd $(LIB_DIR) && bun run dev

# Parallel development (lib watch + frontend dev)
dev-all:
	@echo "Starting parallel development..."
	@(cd $(LIB_DIR) && bun run dev) & \
	 (cd $(FRONTEND_DIR) && bun run dev)
```

**Remove these targets** (no longer needed):
- `link-annotate`
- `unlink-annotate`

**Keep these targets** (still useful):
- `update-annotate` → modify to update workspace version
- `check-annotate` → modify to check local vs npm version

#### Step 3.2: Update Vite config (if needed)

In `apps/web/vite.config.ts`, ensure workspace packages are resolved:

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      // Optional: explicit alias for the workspace package
      '@karlorz/react-image-annotate': path.resolve(
        __dirname,
        '../../packages/react-image-annotate/src'
      )
    }
  },
  // Enable HMR for workspace packages
  optimizeDeps: {
    include: ['@karlorz/react-image-annotate']
  }
})
```

#### Step 3.3: Update TypeScript config

In `apps/web/tsconfig.json`, add path mapping:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@karlorz/react-image-annotate": [
        "../../packages/react-image-annotate/src"
      ]
    }
  },
  "references": [
    { "path": "../../packages/react-image-annotate" }
  ]
}
```

---

### Phase 4: Update CI/CD and Docker

#### Step 4.1: Update .dockerignore
```
# Ignore all node_modules
**/node_modules

# But include built files
!packages/react-image-annotate/dist
```

#### Step 4.2: Update Dockerfile (if applicable)
```dockerfile
# Copy workspace config
COPY package.json bun.lock ./
COPY apps/web/package.json ./apps/web/
COPY packages/react-image-annotate/package.json ./packages/react-image-annotate/

# Install dependencies
RUN bun install --frozen-lockfile

# Copy source and build
COPY apps/web ./apps/web
COPY packages/react-image-annotate ./packages/react-image-annotate

RUN bun run build
```

#### Step 4.3: Update GitHub Actions (if applicable)
```yaml
- name: Install dependencies
  run: bun install

- name: Build library
  run: bun run build:lib

- name: Build frontend
  run: bun run build:web
```

---

### Phase 5: Update Documentation

#### Step 5.1: Update CLAUDE.local.md / AGENTS.md

**Project Structure section:**
```markdown
## Project Structure
```
data-labeling/
├── apps/
│   └── web/                    # React frontend
├── packages/
│   └── react-image-annotate/   # Annotation library
├── svc/                        # Python backend
├── package.json                # Workspace root
└── makefile
```

**Development Commands section:**
```markdown
### Essential Commands
```bash
# Install all dependencies
bun install

# Development
make all                  # Build all + start backend
make start-frontend       # Frontend dev server
make dev-lib              # Library watch mode
make dev-all              # Parallel lib + frontend dev

# Build
make build-all            # Build lib then frontend
make build-lib            # Build library only
make build-frontend       # Build frontend only
```
```

#### Step 5.2: Update README.md
Add monorepo structure explanation and development workflow.

---

## Post-Migration Checklist

### Verification Steps
- [ ] `bun install` completes without errors
- [ ] `make build-lib` builds the library
- [ ] `make build-frontend` builds the frontend
- [ ] `make start-frontend` starts dev server
- [ ] Changes in `packages/react-image-annotate/` trigger HMR in frontend
- [ ] TypeScript can resolve imports from workspace package
- [ ] Docker build works
- [ ] CI/CD pipeline passes

### Clean Up
- [ ] Delete old `bun.lock` in `web/` directory
- [ ] Remove `link-annotate` and `unlink-annotate` from makefile
- [ ] Update any scripts referencing `./web` to `./apps/web`
- [ ] Archive or delete the separate react-image-annotate repository

---

## Rollback Plan

If issues arise, revert by:
1. Move `apps/web` back to `web/`
2. Remove `packages/` directory
3. Restore original `package.json`
4. Re-run `bun link` workflow

---

## Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| New developer setup | Clone 2 repos + bun link | Clone 1 repo + bun install |
| Atomic changes | 2 commits, 2 PRs | 1 commit, 1 PR |
| Dependency management | Manual sync | Automatic via workspace |
| CI/CD complexity | 2 pipelines | 1 pipeline |
| HMR for library | Requires manual link | Works automatically |

---

## References

- [Bun Workspaces Documentation](https://bun.sh/docs/install/workspaces)
- [Git Subtree Guide](https://www.atlassian.com/git/tutorials/git-subtree)
- [Turborepo (optional enhancement)](https://turbo.build/repo/docs)
