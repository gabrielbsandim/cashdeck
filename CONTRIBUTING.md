# Contributing

Thanks for helping. This guide covers the workflow, the rules every change
follows and the commands you need. The [README](README.md) has the quickstart
and [docs/architecture.md](docs/architecture.md) explains where code goes.

## Workflow

1. Fork, create a branch, and keep the change focused on one thing.
2. Install with `pnpm install`. Git hooks install themselves
   (`simple-git-hooks`): pre-commit formats and lints staged files, commit-msg
   checks the message, pre-push runs typecheck and tests.
3. Run `pnpm check` before opening a pull request; CI runs the same gates and
   builds every package. Touching the app also means `apps/mobile/tool/check.sh`.
4. Commit messages follow Conventional Commits in one line, no body:
   `type: short title` (for example `feat: capture bills from shared PDFs`).

## Commands

| Task                        | Command                                                               |
| --------------------------- | --------------------------------------------------------------------- |
| Every backend gate          | `pnpm check`                                                          |
| Build everything            | `pnpm build`                                                          |
| Tests of one package        | `pnpm -C packages/domain test` (or `test:coverage`)                   |
| API dev server              | `pnpm -C apps/api dev` (port 3100)                                    |
| New migration               | `pnpm -C packages/infrastructure db:migrate`                          |
| Apply migrations            | `pnpm -C packages/infrastructure db:deploy`                           |
| Prisma integration tests    | `pnpm -C packages/infrastructure test:integration`                    |
| Regenerate the API client   | `pnpm -C apps/api openapi:export && pnpm -C packages/client generate` |
| Mobile gate                 | `apps/mobile/tool/check.sh`                                           |

## Architecture rules

- Ports and adapters. The domain has no I/O and no npm dependencies; the
  application depends on the domain and `zod` only; adapters live in
  `packages/infrastructure` and reach the API only through
  `apps/api/src/server/container.ts`. dependency-cruiser fails the build
  otherwise.
- Every port ships with a fake in `packages/application/src/testing`. Use cases
  are tested against fakes; unit tests never touch the network.
- Money is integer cents plus an ISO currency. Dates are stored in UTC and
  computed in `America/Sao_Paulo`.
- Every outbound side effect carries an idempotency key and writes an audit
  event.
- A route, request or response change updates [docs/api.md](docs/api.md) and
  the generated client in the same change.

## Code style

- Code and documentation in English. Never use the em dash character.
- Guard clauses and early returns; no `if` inside `if`, no `else` after
  `return`, no nested ternaries. Three or more branches on the same value become
  a `switch` or a lookup table.
- Comments explain a non-obvious why, in at most two lines. No comments that
  narrate what the code does.
- No personal data in code, fixtures or docs: use fictional names, round or
  made-up amounts and public test tax ids (CPF `529.982.247-25` or
  `111.444.777-35`, CNPJ `11.222.333/0001-81` or `11.444.777/0001-61`).

## Coverage

100% on `packages/domain` and `packages/application`, 95% on every other
package and the API. The mobile thresholds are in
[apps/mobile/docs/testing.md](apps/mobile/docs/testing.md).
