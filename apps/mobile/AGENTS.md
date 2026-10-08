# Start here

Cashdeck mobile, the Flutter app. It talks to the Cashdeck API (`apps/api` in
this monorepo, Next.js) and owns no business rule the server decides. Product
context is in [`../../docs/plan.md`](../../docs/plan.md).

[`docs/README.md`](docs/README.md) is the documentation index.

# Before writing any code, read these

- [`docs/architecture.md`](docs/architecture.md): layers, folder layout, the
  dependency rule and the composition root
- [`docs/conventions.md`](docs/conventions.md): Dart style, naming, errors,
  money, UI language
- [`docs/testing.md`](docs/testing.md): what to test, where, and the coverage
  gate
- [`docs/design.md`](docs/design.md): tokens, themes and components

Violating a rule in these documents is a defect. The layer rule is enforced by
`test/architecture/layer_rules_test.dart`.

Touching anything that talks to the server also means reading
[`docs/api-contract.md`](docs/api-contract.md).

# The gate

```bash
tool/check.sh   # format, analyze, tests with coverage, coverage thresholds
```

A task is done when `tool/check.sh` is green. CI runs the same script
(`.github/workflows/mobile.yml` at the repository root).

The Flutter SDK may live outside `PATH`; prefix the call, for example
`PATH=<flutter>/bin:$PATH apps/mobile/tool/check.sh`.

# Rules that are easy to miss

- Code, comments and docs are English. Every string a user reads lives in
  `lib/l10n/app_pt.arb` (default) and `lib/l10n/app_en.arb`, never inline.
- Generic by design: no real people, companies or documents in code, fakes or
  tests. Sample data is fictional.
- Never use the em dash character (U+2014) anywhere.
- No nested `if`. Guard clauses and early return. Three or more branches on the
  same value become a `switch`.
- No comment that narrates what a line does. A comment only says why a
  non-obvious decision exists, in at most two lines.
- Colors come only from `context.palette`; never a raw `Color` in a screen.
- Do not commit or push unless explicitly asked.
