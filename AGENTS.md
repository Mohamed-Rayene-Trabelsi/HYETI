HYETI is a Flutter app for Android only. All data stays on the phone in SQLite; the only network calls are the Watch tab's lookups (AniList, TMDB, OMDb).

## Flutter has changed — check before you trust memory

- Material widgets come from the `material_ui` package, not the SDK: `import 'package:material_ui/material_ui.dart';`. Do not import `package:flutter/material.dart`.
- Read the Flutter version with `flutter --version` and check https://docs.flutter.dev before using an API you are not sure still exists.

## Commands

```bash
flutter pub add <package>   # add a dependency
flutter analyze             # lint and typecheck
flutter test                # unit and widget tests
flutter run                 # run on a connected phone or emulator
flutter build apk --release # installable APK in build/app/outputs/flutter-apk/
```

Run `flutter analyze` and `flutter test` before declaring any task done.

To see a screen without a phone, draw it to a PNG with real fonts and look at the file in `test/preview/`:

```bash
flutter test test/render_preview_test.dart --update-goldens
```

Do this after any layout or drawing change (the body figure in particular); add a `snap(...)` line for a new screen.

The toolchain lives in `C:\Users\TNT\develop` (`flutter`, `jdk-17`, `android-sdk`) and is on the user PATH.

## Layout

- `lib/main.dart` — app start, theme choice, the five-tab shell (a swipeable `PageView`; tabs stay alive off screen).
- `lib/screens/` — one file per tab: `calendar`, `body` (gym) with `nutrition`, `wallet`, `watch`, `notes`. `settings` is a pushed page, opened from the gear that `Screen` puts in every header.
- `lib/db.dart` — the database: schema and migrations, `appDb`, and the `Live` mixin.
- `lib/ui.dart` — shared widgets (`Screen`, `AppCard`, `AppButton`, `Field`, `showSheet`, …). Use these rather than raw Material widgets so screens stay consistent.
- `lib/theme.dart` — colour themes (`palettes`, `customPalette`), the colours in use (`context.colors`), spacing, calendar categories. Never hard-code a colour a theme should control; take it from `context.colors`.
- `lib/date.dart` — date helpers. Dates are `'YYYY-MM-DD'` strings; times are minutes since midnight.
- `lib/calendar_views.dart`, `lib/pickers.dart`, `lib/body_map.dart`, `lib/muscles.dart`, `lib/watch_api.dart` — feature pieces.

## Rules

- Data access is plain SQL through `appDb` (`query`, `run`, `insert`, `transaction`). Every write notifies listeners; a screen that shows rows mixes in `Live` and reads them in `load()`.
- Small preferences and single objects (theme, currency, savings goal, membership, nutrition plan, API keys) are JSON values in the `settings` table, read with `appDb.setting(key, fallback)` and written with `appDb.setSetting`.
- Schema changes: bump `_databaseVersion` in `lib/db.dart` and add an `if (from < N)` block. Never edit an existing block — installed apps have already run it.
- A screen's main action goes in `Screen`'s floating button (`fabLabel` / `onFab`), not in the content.
- Deleting something the user made goes through `deleteWithUndo` (or `showUndo`) so it can be taken back.
- Do not add widgets that capture horizontal drags (swipe-to-dismiss, horizontal lists): sideways swipes belong to tab switching.
- The formatter width is 120 (`analysis_options.yaml`). Run `dart format lib test` after edits.
- Android only. Do not add iOS, web or desktop platform folders.
- Widget tests use an in-memory database through `sqflite_common_ffi`; see `test/widget_test.dart` for the pattern.
