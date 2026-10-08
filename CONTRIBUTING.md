# Contributing

1. Fork, create a branch, and keep the change focused on one thing.
2. Run `pnpm check` before opening a pull request; CI runs the same gates.
3. Commit messages follow Conventional Commits, one line, no body:
   `type: short title` (for example `feat: capture bills from shared PDFs`).

## Architecture rules

- Ports and adapters. The domain has no I/O and no npm dependencies; the
  application depends on the domain and `zod` only; adapters live in
  `packages/infrastructure` and reach the API only through
  `apps/api/src/server/container.ts`.
- Every port ships with a fake in `packages/application/src/testing`. Use cases
  are tested against fakes; unit tests never touch the network.
- Money is integer cents plus an ISO currency. Dates are stored in UTC and
  computed in `America/Sao_Paulo`.
- Every outbound side effect carries an idempotency key and writes an audit
  event.

## Code style

- Code and documentation in English.
- Guard clauses and early returns; no `if` inside `if`, no `else` after
  `return`, no nested ternaries. Three or more branches on the same value become
  a `switch` or a lookup table.
- Comments explain a non-obvious why, in at most two lines. No comments that
  narrate what the code does.
- No personal data in code, fixtures or docs: use fictional names and public
  test tax ids.
