# depools

Depools.ai: an AI-assisted inventory app for small businesses and households.
One Flutter app for iOS, Android and web on a Laravel API, Turkey first. A user
photographs a receipt, scans a barcode, or types "1 adet süt aldım", and the
item lands in stock with the right quantity, unit, location and expiry date.
From then on the app knows what is running low, what is about to expire, and
what to buy next.

Built on `magic`, `magic_starter` and the Wind design-first component system,
and bootstrapped from the `magic_example` starter. `docs/depools-system/` is the
product specification; `AGENTS.md` is the canonical guidance for working here.

The committed `pubspec.yaml` is a clean hosted dependency set: every sibling
package (`magic`, `magic_deeplink`, `magic_notifications`, `magic_social_auth`,
`magic_starter`, `magic_devtools`, `fluttersdk_dusk`, `fluttersdk_telescope`,
`fluttersdk_artisan`) is a normal `^` caret constraint pointing at pub.dev, not
a path dependency. That is deliberate: a fork copied outside this workspace
must resolve on its own. Local, in-workspace development instead uses the
gitignored `pubspec_overrides.yaml`, which redirects those same packages to
the sibling checkouts under `../magic`, `../magic_starter`, and so on; it
never ships, and `bin/check` copies it into a fresh worktree on first run.

## Setup

`.env` is COMMITTED here and bundled as a Flutter asset in `pubspec.yaml`, which
is deliberate on both counts: `flutter_dotenv` can only load it on web when it is
a bundled asset, and a bundled asset that does not exist fails `flutter build`,
so gitignoring it would leave every fresh clone unbuildable. It holds public
client values only. A Flutter bundle ships to every user's device and can be read
out of it, so real secrets belong on the backend, never here. `.env.example`
stays as the key list.

The platform identifier is `ai.depools.app`, in `android/app/build.gradle.kts`
(`namespace` and `applicationId`) and in the `PRODUCT_BUNDLE_IDENTIFIER` entries
in `ios/Runner.xcodeproj/project.pbxproj`.

The theme is generated: edit `DESIGN.md`, then run
`dart run bin/dispatcher.dart design:sync`, which rewrites
`lib/config/wind_theme.g.dart`. Never hand-edit that file.

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
