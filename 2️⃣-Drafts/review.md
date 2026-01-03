  ---
  PR #27 Review: PVE LXC Sandbox Provider

  Executive Summary

  PR #27 adds Proxmox VE (PVE) LXC containers as an alternative sandbox provider with good architectural design that aligns with the upstream cmux pattern of "configurable sandbox providers." The implementation follows the core principle: cmux spawns an isolated openvscode instance via Docker or a configurable sandbox provider.

  Overall Assessment: ✅ Well-designed, ready for merge with minor improvements

  ---
  1. Architecture Alignment with Upstream

  ✅ Strengths - Core Design Preserved

  | Aspect               | Upstream Pattern                                       | PR #27 Implementation                                            |
  |----------------------|--------------------------------------------------------|------------------------------------------------------------------|
  | Provider Abstraction | SandboxService trait (Rust), VSCodeInstance class (TS) | SandboxInstance interface + wrapMorphInstance/wrapPveLxcInstance |
  | Detection Pattern    | CLI prefix (l_, c_) for local/cloud                    | Env-based (SANDBOX_PROVIDER) + auto-detection                    |
  | Unified API          | /api/sandboxes/start abstracts provider                | Same endpoint handles both Morph and PVE                         |
  | Instance Isolation   | Each sandbox has independent runtime                   | Each LXC container runs apps/server embedded                     |

  ✅ Code Style Conformance

  The implementation follows the codebase conventions correctly:

  // ✅ Correct: Zod validation with required body
  createRoute({
    method: "post" as const,
    path: "/sandboxes/start",
    request: {
      body: {
        content: { "application/json": { schema: StartSandboxBody } },
        required: true,  // ✅ Required per CLAUDE.md
      },
    },
  })

  // ✅ Correct: node: prefix imports
  import { Agent, fetch as undiciFetch } from "undici";

  // ✅ Correct: No `any` type, using proper interfaces
  export interface SandboxInstance {
    id: string;
    status: string;
    metadata: Record<string, string | undefined>;
    // ...
  }

  ---
  2. Provider Abstraction Quality

  ✅ Clean Interface Design (sandbox-instance.ts:39-72)

  export interface SandboxInstance {
    id: string;
    status: string;
    metadata: Record<string, string | undefined>;
    networking: SandboxNetworking;
    exec(command: string): Promise<ExecResult>;
    stop(): Promise<void>;
    pause(): Promise<void>;
    resume(): Promise<void>;
    exposeHttpService(name: string, port: number): Promise<void>;
    hideHttpService(name: string): Promise<void>;
    setWakeOn(http: boolean, ssh: boolean): Promise<void>;
  }

  This interface enables:
  - Seamless provider switching - Routes use SandboxInstance without provider-specific code
  - Future provider extensibility - New providers only need to implement this interface
  - Wrapper pattern - wrapMorphInstance() and wrapPveLxcInstance() adapt provider-specific types

  ✅ Unified Snapshot ID Format (sandbox-presets.ts:147-209)

  // Format: {provider}_{presetId}_v{version}
  // Examples:
  //   morph_4vcpu_16gb_48gb_v1
  //   pvelxc_4vcpu_6gb_32gb_v1
  //   pvevm_4vcpu_6gb_32gb_v1 (future)

  export function parseSnapshotId(id: string): {
    provider: SandboxProviderType;
    presetId: string;
    version: number;
  } | null

  This enables version-tracked snapshots across all providers with a consistent format.

  ---
  3. Resilience for Future Providers

  ✅ Type-Safe Extension Points

  Adding a new provider (e.g., AWS EC2, GCP VMs) requires:

  1. Add provider type (sandbox-presets.ts:22):
  export type SandboxProviderType = "morph" | "pve-lxc" | "pve-vm" | "aws-ec2";
  2. Define capabilities (sandbox-presets.ts:53-75):
  SANDBOX_PROVIDER_CAPABILITIES["aws-ec2"] = {
    supportsHibernate: true,
    supportsSnapshots: true,
    // ...
  };
  3. Implement client - Create aws-ec2-client.ts with methods returning SandboxInstance
  4. Add wrapper - Create wrapAwsEc2Instance() in sandbox-instance.ts
  5. Update snapshot resolution (sandbox-presets.ts:252-311) - Add case in resolveSnapshotId()

  ✅ Exhaustive Switch Pattern

  The code uses TypeScript's exhaustive checking:

  switch (parsed.provider) {
    case "morph": { /* ... */ }
    case "pve-lxc": { /* ... */ }
    case "pve-vm": { throw new Error("PVE VM provider not yet implemented"); }
    default: {
      const _exhaustive: never = parsed.provider;  // ✅ Compile-time safety
      throw new Error(`Unknown provider: ${_exhaustive}`);
    }
  }

  ---
  4. Issues & Recommendations

  High Priority

  | Issue                  | Location                  | Impact                              | Recommendation                                       |
  |------------------------|---------------------------|-------------------------------------|------------------------------------------------------|
  | In-memory metadata     | pve-lxc-client.ts:234     | Lost on server restart              | Store in Convex or PVE description field             |
  | No container GC        | Missing                   | Resource leaks                      | Add pruneContainers() with TTL check                 |
  | Error rollback missing | pve-lxc-client.ts:754-811 | Orphaned containers on failed start | Delete container if startContainer fails after clone |

  Medium Priority

  | Issue                     | Location                                 | Impact                    | Recommendation                         |
  |---------------------------|------------------------------------------|---------------------------|----------------------------------------|
  | CRIU hibernation unused   | pve-criu.sh exists, pause() calls stop() | No RAM state preservation | Integrate CRIU for true pause/resume   |
  | SSH not supported for PVE | sandboxes.route.ts:1385-1549             | Limited debugging         | Add PVE LXC SSH via exec or direct SSH |
  | Rate limiting absent      | All routes                               | DoS risk                  | Add per-team rate limits               |

  Low Priority (Future Work)

  | Issue                                  | Recommendation                        |
  |----------------------------------------|---------------------------------------|
  | pve-vm stub declared but unimplemented | Defer to future PR                    |
  | Snapshot version UI missing            | Frontend only shows latest version    |
  | Tunnel setup manual                    | Consider Ansible/Terraform automation |

  ---
  5. Code Quality Assessment

  ✅ Follows Project Conventions

  - No any types - Uses proper interfaces and type assertions
  - Zod validation - All API routes use @hono/zod-openapi
  - Error handling - console.error on all caught errors (per CLAUDE.md)
  - node: prefixes - Correctly used for Node imports
  - No dynamic imports except necessary - Only for circular dependency avoidance

  ✅ Test Coverage

  scripts/pve/test-pve-lxc-client.ts  - 11/11 tests passing
  scripts/pve/test-pve-cf-tunnel.ts   - 11/11 tests passing
  packages/shared/src/pve-lxc-snapshots.test.ts - Schema tests

  ✅ Documentation Quality

  - docs/PR27-PVE-LXC-REVIEW.md - Comprehensive architecture doc
  - scripts/pve/README.md - Shell script documentation
  - Inline JSDoc comments throughout

  ---
  6. Summary Verdict

  | Category      | Rating     | Notes                                             |
  |---------------|------------|---------------------------------------------------|
  | Architecture  | ⭐⭐⭐⭐⭐ | Clean provider abstraction, extensible design     |
  | Code Style    | ⭐⭐⭐⭐⭐ | Follows all CLAUDE.md conventions                 |
  | Resilience    | ⭐⭐⭐⭐   | Good extension points, needs metadata persistence |
  | Testing       | ⭐⭐⭐⭐   | Good integration tests, could add unit tests      |
  | Documentation | ⭐⭐⭐⭐⭐ | Comprehensive review doc and READMEs              |

  Recommended Actions Before Merge

  1. Must Fix: Add metadata persistence to Convex (high priority)
  2. Should Fix: Add container cleanup/GC mechanism
  3. Nice to Have: Unit tests for parseSnapshotId() edge cases

  Merge Recommendation

  ✅ Approve with minor changes - The PR demonstrates good architectural alignment with upstream cmux while enabling self-hosted deployment via PVE LXC. The provider abstraction is well-designed for future extensibility.
