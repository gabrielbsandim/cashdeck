# Cashdeck mobile

The Flutter app of Cashdeck (Android first; iOS builds but push is not wired
yet). It talks to the Cashdeck API in `apps/api` and owns no business rule the
server decides. Contributors start with [AGENTS.md](AGENTS.md) and the
[docs index](docs/README.md).

## Run

```bash
flutter pub get
flutter run                                   # fake backend, no server needed
flutter run --dart-define=BACKEND=api \
  --dart-define=API_BASE_URL=https://your-api.example
```

| Define         | Values               | Default                 |
| -------------- | -------------------- | ----------------------- |
| `BACKEND`      | `fake` or `api`      | `fake`                  |
| `API_BASE_URL` | the API origin       | `http://localhost:3000` |

The API dev server listens on port 3100, so pass `API_BASE_URL` explicitly; an
Android emulator reaches the host machine at `http://10.0.2.2:3100`.

## Build and install

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --dart-define=BACKEND=api --dart-define=API_BASE_URL=https://<api domain>
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Push notifications need `android/app/google-services.json`, which is git
ignored; see [docs/deploy.md](../../docs/deploy.md#push-notifications).

## Gate

```bash
tool/check.sh   # format, analyze, tests with coverage, coverage thresholds
```
