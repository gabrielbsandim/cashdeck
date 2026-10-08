# Agent guide

Read [docs/plan.md](docs/plan.md) for the product scope and
[CONTRIBUTING.md](CONTRIBUTING.md) for the rules below in full.

## Rules

- Code, comments and docs in English. Never use the em dash character.
- Ports and adapters: domain is pure, application depends on domain and zod,
  infrastructure implements ports, routes go through the container. The
  dependency-cruiser config enforces it.
- Coverage gates: 100% on `packages/domain` and `packages/application`, 95%
  elsewhere. A new port needs a fake in `packages/application/src/testing`.
- Guard clauses, no `if` inside `if`, no `else` after `return`, no nested
  ternaries; three or more branches become a `switch` or a table.
- Comments only for a non-obvious why, at most two lines.
- No personal names, accounts or documents anywhere; fixtures use fictional
  data and public test tax ids.
- Commits: one line, `type: title`, no body.

## Commands

| Task | Command |
|---|---|
| All gates | `pnpm check` |
| Build | `pnpm build` |
| One package | `pnpm -C packages/domain test:coverage` |
| API dev server | `pnpm -C apps/api dev` |
| Regenerate the client | `pnpm -C apps/api openapi:export && pnpm -C packages/client generate` |
| Mobile gate | `apps/mobile/tool/check.sh` |
