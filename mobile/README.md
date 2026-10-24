# Crompton PMS mobile

Run from `mobile/`:

```powershell
flutter run --dart-define-from-file=../firebase/development.mobile.json
flutter run --release --dart-define-from-file=../firebase/development.mobile.json
flutter build apk --release --dart-define-from-file=../firebase/development.mobile.json
```

The development configuration selects cloud Firebase and the hosted HTTPS API.
Flutter does not load the backend `.env` file. A bare `flutter run --release`
omits the required cloud configuration.

Release builds also require private `android/key.properties`, or
`PMS_ANDROID_KEY_PROPERTIES` pointing to your private properties file:

```properties
storeFile=D:/private/crompton-pms-upload.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=crompton-pms-upload
keyPassword=YOUR_KEY_PASSWORD
```

Use forward slashes for Windows keystore paths. Back up the keystore and
properties securely; future app updates need the same signing identity.
Both are excluded from Git. The local signing setup generated on 2026-10-24
uses `.local/android-signing/crompton-pms-upload.jks` at the repository root
and `mobile/android/key.properties`.

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
Release uses Play Integrity for Firebase App Check; a successful build alone
does not verify App Check enrollment or on-device cloud access.

See the [project README](../README.md) for backend setup and emulator commands.
