# Cashdeck mobile

The Flutter app of Cashdeck. Start with [AGENTS.md](AGENTS.md).

```bash
flutter pub get
flutter run                                   # fake backend, no server needed
flutter run --dart-define=BACKEND=api \
  --dart-define=API_BASE_URL=https://your-api.example
tool/check.sh                                 # the gate
```
