# depools

The batteries-included reference app for the `fluttersdk` `magic` ecosystem: a
working Flutter application built on `magic`, `magic_starter`, and the
Wind design-first component system, meant to be forked into a new product
rather than read as a tutorial.

The committed `pubspec.yaml` is a clean hosted dependency set: every sibling
package (`magic`, `magic_deeplink`, `magic_notifications`, `magic_social_auth`,
`magic_starter`, `magic_devtools`, `fluttersdk_dusk`, `fluttersdk_telescope`,
`fluttersdk_artisan`) is a normal `^` caret constraint pointing at pub.dev, not
a path dependency. That is deliberate: a fork copied outside this workspace
must resolve on its own. Local, in-workspace development instead uses the
gitignored `pubspec_overrides.yaml`, which redirects those same packages to
the sibling checkouts under `../magic`, `../magic_starter`, and so on; it
never ships and is not part of the fork.

## Forking this app

Follow these steps in order; each one depends on the previous.

1. **Rename the package.** Update `name:` in `pubspec.yaml`, then rename every
   Dart `import 'package:depools/...'` under `lib/` and `test/` to the
   new package name. Update the platform bundle identifiers too:
   `android/app/build.gradle.kts` (`namespace` and `applicationId`, currently
   `ai.depools.app`) and the iOS
   `PRODUCT_BUNDLE_IDENTIFIER` entries in
   `ios/Runner.xcodeproj/project.pbxproj` (currently `ai.depools.app`).
2. **Edit `.env`.** Set `APP_NAME` and point `API_URL` at the new backend, then
   run `magic key:generate` if the app uses the `Crypt` facade. `.env` is
   COMMITTED here and bundled as a Flutter asset in `pubspec.yaml`, which is
   deliberate on both counts: `flutter_dotenv` can only load it on web when it is
   a bundled asset, and a bundled asset that does not exist fails
   `flutter build`, so gitignoring it would make every fresh clone of this
   template unbuildable. It holds public client values only. A Flutter bundle
   ships to every user's device and can be read out of it, so real secrets
   belong on the backend, never here. `.env.example` stays as the key list.
3. **Set bundle ids and app icons.** Reuse the identifiers you set in step 1
   for the platform bundle/app ids, then replace the launcher icons under
   `android/app/src/main/res/mipmap-*` and `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.
4. **Edit `DESIGN.md`**, then regenerate the theme:
   `dart run bin/dispatcher.dart design:sync`. This rewrites
   `lib/config/wind_theme.g.dart`; never hand-edit that file.
5. **Delete `pubspec_overrides.yaml`.** It exists only to wire this app to
   sibling packages under active development inside the `fluttersdk`
   workspace; a fork living outside that workspace has no sibling checkouts
   to point at and must resolve every `magic` package from pub.dev via the
   plain `pubspec.yaml` constraints. Deleting it (it is gitignored, so it was
   never committed) is what makes `flutter pub get` resolve purely hosted.
6. **Refresh the preview catalog:** `dart run bin/dispatcher.dart previews:refresh`.

After these six steps, `flutter pub get` should resolve against pub.dev alone,
`flutter analyze` and `flutter test` should stay clean, and `/preview` in a
debug build should reflect the new `DESIGN.md`.

## Running it

- `flutter run -d chrome`, or drive it through `fluttersdk_dusk` for
  agent/CI-style E2E.
- Component and design tooling runs through `bin/dispatcher.dart`: `make:component`,
  `design:sync`, `design:lint`, `previews:refresh`. See `CLAUDE.md` for the
  full command list and `.claude/rules/design.md` for the component contract.

## Learn more about Flutter

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
