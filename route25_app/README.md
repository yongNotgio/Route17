# Route25 Flutter App (MVP)

This folder contains the initial Flutter app for Route25.

Included in this MVP:
- Loads `assets/data/prd_routes_dataset.json`
- Origin/destination input with stop suggestions
- Direct route matching (single-route)
- Route detail map with OSM tiles, polylines, and stop markers
- Route and stop list display

## Important
Flutter SDK is not installed in this environment, so platform folders were not generated yet.

After installing Flutter, run:

```powershell
cd route25_app
flutter create .
flutter pub get
flutter run
```

`flutter create .` will generate `android/ios/web/windows/...` while keeping existing app code.

