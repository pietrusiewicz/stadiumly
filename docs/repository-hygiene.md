# Repository hygiene

This project can stay public while it is developed for Google Play, but secret
and release-only files must stay out of git.

## Safe to show publicly

- Flutter source code in `lib/`
- Android project scaffolding in `android/`
- Web preview files in `web/`
- Tests in `test/`
- Public screenshots and docs in `docs/`
- `README.md`, `pubspec.yaml`, `pubspec.lock`, and analysis config
- Placeholder icons and generated launcher assets, as long as they are owned or
  properly licensed

## Keep private

- Google Play signing keystores: `*.jks`, `*.keystore`
- Signing config files: `key.properties`, `android/key.properties`
- API keys, tokens, service credentials, and `.env` files
- Production backend URLs or keys that allow writes/admin access
- Private user data, logs, exports, analytics dumps, or crash reports
- Paid or restricted assets that cannot be redistributed publicly

## Before a Play Store release

- Confirm the release keystore is ignored and backed up privately.
- Move provider keys and environment-specific values out of source code.
- Use a production-safe map tile provider instead of public OSM demo tiles.
- Review app permissions and explain them clearly in the Play Store listing.
- Run `flutter analyze`, `flutter test`, and a release build check.
