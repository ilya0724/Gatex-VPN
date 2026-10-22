# GateX VPN app

Flutter client for Android, Windows and Linux. It imports a Remnawave
subscription, shows the tariff and expiry, and connects in one tap through
Xray-core (see `../core`).

## How it fits together

- `lib/subscription/` fetches the subscription (with `x-hwid` headers for
  the device limit) and turns share links or Xray JSON into outbounds.
- `lib/core/config_builder.dart` builds the Xray config: a TUN inbound, the
  chosen server, or every server behind a `leastPing` balancer for «Авто».
- `lib/core/android_core.dart` talks to `GatexVpnService.kt`, which owns the
  VpnService TUN and runs the core from `gatexcore.aar` in-process.
- `lib/core/desktop_core.dart` starts `gatex-core` next to the executable.
  It creates the TUN and system routes itself, and exits when its stdin
  closes, so routes never outlive the app. Windows runs elevated (runner
  manifest); the Linux .deb gives the core `cap_net_admin`.

Links from the bot: `gatex://import?url=<urlencoded subscription URL>`.

## Build

CI (`.github/workflows/app.yml`) builds everything. Locally:

```sh
(cd ../core && go build -o /tmp/gatex-core ./cmd/gatex-core)
GATEX_CORE=/tmp/gatex-core flutter test      # checks configs with the real core
flutter build linux && cp /tmp/gatex-core build/linux/x64/release/bundle/
```

Android needs `android/app/libs/gatexcore.aar` from
`gomobile bind -target=android ./gatexcore` in `../core`.

Release signing: add repository secrets `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
Without them the APK is signed with a debug key, fine for testing only.

## Updates

The app reads `https://gatexx.ru/app/version.json`:

```json
{"version": "1.0.1", "notes": "…",
 "android": {"url": "https://…/GateX-universal.apk"},
 "windows": {"url": "https://…/GateX-Setup-1.0.1.exe"},
 "linux": {"url": "https://…/gatex_1.0.1_amd64.deb"}}
```

Fonts Manrope and Unbounded are under the SIL Open Font License
(`assets/fonts/OFL-*.txt`).
