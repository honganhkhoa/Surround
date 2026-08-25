# Testing Surround

Surround's automated tests are split into three groups:

- `SurroundTests` contains deterministic unit and service tests. These run for every push and pull request and must not contact OGS.
- `SurroundUITests` contains deterministic, offline journeys shared by iPadOS and
  Mac Catalyst. Each test launches independently with bundled fixtures and the
  Debug-only `--surround-ui-testing` argument.
- `SurroundBetaTests` contains live integration scenarios against the isolated OGS beta service. Its separate shared scheme keeps it out of normal test runs; run it only by explicitly selecting that scheme locally or manually dispatching the **OGS beta integration tests** workflow.

The offline UI-test runtime uses a dedicated preferences suite, rejecting HTTP
transport, and a no-op WebSocket. It does not use the production or Beta
account data and cannot contact OGS.

## Deterministic unit tests

Run `SurroundTests` from Xcode, or select an installed iOS 26 iPhone simulator
and run the unit target from the command line:

```sh
simulator_id="$(.github/ci-tools/select-ios-simulator.sh 26 iPhone)"
xcodebuild test \
  -scheme Surround \
  -project Surround.xcodeproj \
  -destination "platform=iOS Simulator,id=${simulator_id}" \
  -only-testing:SurroundTests
```

The simulator helper accepts an iOS major version and an optional exact family of `iPhone` or `iPad`; it defaults to `iPhone`. CI runs the unit target on both the current iOS 26 simulator and the latest installed simulator in the minimum supported iOS 18 major release.

## Offline iPad UI tests

The shared journeys cover top-level navigation, opening the bundled fixture
game, and entering and leaving Zen mode. The suite selects landscape orientation
itself:

```sh
simulator_id="$(.github/ci-tools/select-ios-simulator.sh 26 iPad)"
xcodebuild test \
  -scheme Surround \
  -project Surround.xcodeproj \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${simulator_id}" \
  -only-testing:SurroundUITests
```

CI runs these journeys on both iPadOS 26 and the latest installed iPadOS 18 runtime. To reproduce the minimum-OS lane locally, substitute `18` in the two simulator selection commands above. The `minimum-ios-18` CI job runs on `macos-15`, explicitly selects Xcode 26.2, and retains both result bundles in the `surround-ios-18-test-results` artifact.

## Deployment target validation

The iPhone and iPad app, widget, and notification extensions support iOS 18.0. The Mac Catalyst app and its embedded widget continue to require macOS 26. The project expresses the latter as an SDK-qualified iPhone deployment-target override, so validate the generated bundle metadata instead of adding a manual Info.plist key.

Build both iOS configurations into a new derived-data directory:

```sh
validation_path=".build/DeploymentTargetValidation-$(date +%Y%m%d-%H%M%S)"
xcodebuild build \
  -scheme Surround \
  -project Surround.xcodeproj \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$validation_path" \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -scheme 'Surround Beta' \
  -project Surround.xcodeproj \
  -configuration 'Beta Debug' \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$validation_path" \
  CODE_SIGNING_ALLOWED=NO
```

Every generated iOS `.app` and `.appex` bundle must report `MinimumOSVersion` as `18.0`:

```sh
find "$validation_path/Build/Products" -type d \
  \( -name '*.app' -o -name '*.appex' \) -print0 |
while IFS= read -r -d '' bundle; do
  minimum_version="$(plutil -extract MinimumOSVersion raw "$bundle/Info.plist")"
  printf '%s\t%s\n' "$minimum_version" "$bundle"
done
```

Run the unsigned Catalyst build into a separate new directory:

```sh
catalyst_validation_path=".build/CatalystTargetValidation-$(date +%Y%m%d-%H%M%S)"
xcodebuild build \
  -scheme Surround \
  -project Surround.xcodeproj \
  -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$catalyst_validation_path" \
  CODE_SIGNING_ALLOWED=NO
```

The generated Catalyst app and widget must report `LSMinimumSystemVersion` as `26.0`:

```sh
find "$catalyst_validation_path/Build/Products" -type d \
  \( -name '*.app' -o -name '*.appex' \) -print0 |
while IFS= read -r -d '' bundle; do
  info_plist="$bundle/Contents/Info.plist"
  minimum_version="$(plutil -extract LSMinimumSystemVersion raw "$info_plist")"
  printf '%s\t%s\n' "$minimum_version" "$bundle"
done
```

## App Store screenshot capture

The `AppStoreScreenshots` scheme and test plan capture submission-ready, localized screenshots from deterministic offline fixtures without contacting OGS.

Run the complete matrix from the repository root with Xcode 26 or newer, the pinned iOS 26.5 simulator runtime unless deliberately overridden, `jq`, `plutil`, `uuidgen`, Swift, and `sips`:

```sh
output_path="/private/tmp/Surround-AppStore-$(date +%Y%m%d-%H%M%S)"
.github/ci-tools/capture-app-store-screenshots.sh \
  --output "$output_path"
```

For a quicker single-localization run, pass the exact test-plan configuration:

```sh
output_path=".build/AppStoreScreenshots-en-US-$(date +%Y%m%d-%H%M%S)"
.github/ci-tools/capture-app-store-screenshots.sh \
  --output "$output_path" \
  --locale en-US
```

`--locale` is repeatable. When it is omitted, the runner captures all thirteen supported localizations.

The output path must not already exist. Reusable build products default to the gitignored `.build/AppStoreScreenshotDerivedData` directory; pass `--derived-data` only to put that cache elsewhere. The runner:

- uses the pinned iOS 26.5 runtime by default and fails if it is unavailable unless `APP_STORE_IOS_RUNTIME` deliberately selects another installed runtime;
- selects an accepted 6.9-inch iPhone and 13-inch iPad from that runtime as device-type templates without booting or modifying them, then creates fresh disposable simulators for capture;
- pins the status bar for repeatable output;
- runs the selected test-plan configurations (`en-US`, `fr-FR`, `de-DE`, `ja-JP`, `vi-VN`, `th-TH`, `zh-Hans-CN`, `zh-Hant-TW`, `ko-KR`, `es-ES`, `es-MX`, `pt-BR`, and `pt-PT` by default);
- captures ten portrait iPhone scenes and ten landscape iPad scenes per locale;
- keeps the iPad app sidebar visible except in Zen mode (the Home Screen widget is captured from SpringBoard);
- exports named XCTest attachments and uses Image I/O to bake attachment orientation into the pixel raster;
- writes neutral orientation metadata (`1`) and current pixel dimensions;
- validates screenshot count, ordering, PNG format, dimensions, orientation metadata, and absence of an alpha channel; and
- deletes the disposable simulators during teardown, including after a failed capture, without changing the template simulators.

The complete thirteen-locale run produces 260 validated PNGs; an English-only run produces 20. Review `index.html` in the output directory before uploading. Final PNGs are in `screenshots/<locale>/iphone-6.9/` and `screenshots/<locale>/ipad-13/`; the result bundle, raw attachments, metadata, and `xcodebuild` log are retained beside them. The capture command remains useful on its own; the reviewed App Store Connect publishing workflow below invokes it automatically.

To deliberately choose a different installed runtime or device templates, set `APP_STORE_IOS_RUNTIME` to the runtime's exact identifier, version, or name and set `APP_STORE_IPHONE_DEVICE` and `APP_STORE_IPAD_DEVICE` to exact simulator names. The runner does not fall back to the latest runtime when the default iOS 26.5 runtime is unavailable. When adding a language, keep the localization catalog, project regions, `AppStoreScreenshots.xctestplan`, `.github/ci-tools/capture-app-store-screenshots.sh`, `.github/ci-tools/app-store-release-locales.json`, and this guide in sync. When adding a scene, keep `AppStoreScreenshotTests.swift` and the runner's scene arrays in sync.

## Reviewed App Store Connect publishing

`.github/ci-tools/app-store-release.sh` prepares and publishes screenshots and localized listing metadata through the App Store Connect API. The implementation, locale contract, tests, and this documentation belong in the public `Surround` repository because they are coupled to the Xcode project and deterministic screenshot fixtures. Unpublished release packages belong in the private umbrella repository's `AppStoreReleases/` directory. Keep the API private key outside both repositories.

The public locale contract maps these App Store locales to screenshot test-plan configurations:

| App Store locale | Screenshot configuration |
| --- | --- |
| `en-US` | `en-US` |
| `fr-FR` | `fr-FR` |
| `de-DE` | `de-DE` |
| `ja` | `ja-JP` |
| `vi` | `vi-VN` |
| `th` | `th-TH` |
| `zh-Hans` | `zh-Hans-CN` |
| `zh-Hant` | `zh-Hant-TW` |
| `ko` | `ko-KR` |
| `es-ES` | `es-ES` |
| `es-MX` | `es-MX` |
| `pt-BR` | `pt-BR` |
| `pt-PT` | `pt-PT` |

Initialize a private package for a version from the public repository root:

```sh
.github/ci-tools/app-store-release.sh init \
  --version 2.1 \
  --output ../AppStoreReleases/2.1
```

The generated `release.json` references one `localizations/<locale>/whats-new.txt` file for each locale. Fill all thirteen release-note files. A localization may also patch version-scoped `description`, `keywords`, `promotionalText`, `supportUrl`, and `marketingUrl`, or app-wide `name`, `subtitle`, and `privacyPolicyUrl`. Long descriptions and promotional text can use `descriptionFile` and `promotionalTextFile`. The top-level optional `copyright` patches the version-wide value. Omitted fields remain unchanged; an explicit `null` clears only fields whose schema permits clearing. For a locale absent from the released source version, `prepare` requires effective non-empty values for `description`, `keywords`, `supportUrl`, `name`, `subtitle`, and `privacyPolicyUrl`; explicit release-package values take precedence, while values already present in the reviewed target draft are accepted as fallback. The localized name must contain 2–30 characters, and the privacy policy URL must be an absolute HTTP(S) URL. Validation applies Apple's field limits, including the 100-character keyword limit measured conservatively with Swift's UTF-16 view so localized combining marks count the same way as App Store Connect.

Run the offline validation before using API credentials:

```sh
.github/ci-tools/app-store-release.sh validate \
  --release ../AppStoreReleases/2.1/release.json
```

This validates the release package and checks that the shipping app, widget, notification-content extension, and notification-service extension all resolve to `MARKETING_VERSION = 2.1` in the Release configuration. It does not contact App Store Connect. Reusable Xcode and Swift build data stays under `.build`.

Create an App Store Connect API key with the minimum role needed to manage the app, store its downloaded `.p8` file outside Git, and export only its identifiers and path:

```sh
export ASC_KEY_ID='YOUR_KEY_ID'
export ASC_ISSUER_ID='YOUR_ISSUER_ID'
export ASC_PRIVATE_KEY_PATH='/absolute/private/path/AuthKey_YOUR_KEY_ID.p8'
```

Prepare the release:

```sh
.github/ci-tools/app-store-release.sh prepare \
  --release ../AppStoreReleases/2.1/release.json
```

Preparation validates locally, takes a read-only snapshot of the target listing, preflights version state and first-time-localization metadata, then captures and validates all 260 screenshots. It creates a unique gitignored `.build/AppStoreRelease-*` artifact with the source snapshot, normalized release, screenshot gallery, metadata diff, and `publish-manifest.json`. Inspect both the capture's `index.html` and the artifact's `review.html` before publishing.

Publishing is deliberately a separate, explicit command:

```sh
.github/ci-tools/app-store-release.sh publish \
  --manifest .build/AppStoreRelease-2.1-<timestamp>/publish-manifest.json \
  --confirm-version 2.1
```

Only `publish` mutates App Store Connect. It verifies the exact version, manifest checksums, and unchanged remote snapshot; uploads and orders exactly ten iPhone and ten iPad screenshots per locale; applies only reviewed metadata; and reads the result back. Its sibling `publish-journal.json` supports a reconciled rerun after a journaled interruption; an ambiguous create or upload-reservation outcome stops for inspection instead of being replayed blindly. The workflow does not upload or select an app build and does not submit the version for App Review.

Validate the public wrapper and tool without production requests:

```sh
bash -n .github/ci-tools/app-store-release.sh
swift test \
  --package-path .github/ci-tools/AppStoreConnectTool \
  --scratch-path .build/AppStoreConnectToolTests
```

Tool tests use mocked HTTP responses. Never supply production credentials to an automated test process.

## iOS 18 and iOS 26 screenshot comparison

The compatibility screenshot runner compares the minimum and current system rendering without changing the exact-ten App Store screenshot contract. It uses deterministic offline fixtures, en-US, system-light/full-color appearance, a pinned 9:41 status bar, and matching simulator hardware:

- iPhone 16 Pro Max in portrait on iOS 18.0 and iOS 26.0;
- iPad Pro 13-inch (M4) in landscape on iPadOS 18.0 and iPadOS 26.0; and
- small, medium, and large home-screen widgets on both device families.

Run the complete 63-pair matrix from the repository root:

```sh
.github/ci-tools/capture-ios-version-comparison.sh \
  --output .build/iOS18-vs-iOS26-route-comparison
```

The output path must not already exist. The gitignored artifact contains:

- `originals/ios-18/<iphone|ipad>/` and `originals/ios-26/<iphone|ipad>/`, holding 126 full-resolution captures;
- `comparisons/<iphone|ipad>/`, holding 63 labelled, lossless side-by-side PNGs;
- `comparison.md`, a responsive `index.html`, and `run-metadata.json`; and
- `runs/<ios-18|ios-26>/`, retaining each run's result bundles, logs, and attachment manifests.

The metadata records the source fingerprint, Xcode version, runtime and device identities, locale, system appearance, verified full-color widget rendering mode, orientation, pixel dimensions, scene manifest, and widget family.

The runner requires Xcode 26 or newer, installed iOS 18.0 and iOS 26.0 simulator runtimes, matching simulator device types, `jq`, Swift, and `sips`. For each OS run, it creates fresh temporary simulators from the exact required device-type and runtime identifiers. It also verifies that the Surround app and UI-test runner are absent before testing, so old preferences, app data, and Home Screen placement cannot contaminate the captures. The temporary simulators are shut down and deleted during teardown, including after a failed capture. Each simulator boot has a three-minute bound and one clean retry so a wedged CoreSimulator display service fails deterministically instead of hanging the capture indefinitely.

It rejects a changed source tree between captures, missing or duplicate scenes, mismatched dimensions, incorrect orientation, alpha channels, and widget screenshots whose frame geometry does not match the requested family. Review `index.html` for clipping, overlap, missing controls, unreadable content, broken navigation, and incorrect adaptive or widget layout; the images are intentionally not required to be pixel-identical across OS versions. The runner removes each isolated widget before adding the next family.

## Mac desktop layout screenshot capture

The shared `DesktopLayoutScreenshots` scheme and test plan capture a deterministic desktop layout matrix from a signed local Mac Catalyst session. Run it from an administrator account on an unlocked Mac UI session. When macOS asks to **Enable UI Automation**, authenticate locally before the prompt times out, then rerun the command if needed:

```sh
desktop_layout_output=".build/DesktopLayoutScreenshots-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$desktop_layout_output"
xcodebuild test \
  -scheme DesktopLayoutScreenshots \
  -project Surround.xcodeproj \
  -testPlan DesktopLayoutScreenshots \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' \
  -resultBundlePath "$desktop_layout_output/DesktopLayoutScreenshots.xcresult"
xcrun xcresulttool export attachments \
  --path "$desktop_layout_output/DesktopLayoutScreenshots.xcresult" \
  --output-path "$desktop_layout_output/attachments"
```

The four fixed profiles are logical UIKit root-content sizes: narrow `900x600`, default `1200x760`, wide `1440x760`, and tall `1000x900`. The test captures Home, Public Games, Messages, Settings, About, the browser, and the active game at each size, then captures Home and the active game in the Mac's native full screen. That produces 28 fixed-size and two full-screen screenshots. Fixed-size window attachments include normal Mac titlebar chrome, so their total raster dimensions are larger than the requested content size.

The plan also runs a focused sizing contract without adding an attachment. It replaces the restored launch scene with a fresh `WindowGroup` scene and leaves the Debug geometry override disabled. The contract requires the SwiftUI root to settle at exactly `1200x760`, while `UIWindow.bounds`, `UIWindowScene.effectiveGeometry.systemFrame`, and XCTest's outer application-window frame must report the same settled outer size. The test then requests `800x500` and requires the usable root content to clamp to exactly `900x600`.

Every launch uses the Debug-only offline fixture root, rejecting HTTP transport, and a no-op WebSocket, so the captures never contact OGS. The browser capture is intentionally the offline placeholder rather than live `WKWebView` content; verify the production browser separately during manual review. A passing run proves capture completeness, stable requested geometry and restoration, the fresh-window and minimum-size contracts, and the expected scene-specific window titles. It does not certify visual quality: review the exported images for clipping, excessive whitespace, weak hierarchy, and poor adaptive layout. Keep the result bundle and exported screenshot attachments together under the timestamped gitignored `.build/DesktopLayoutScreenshots-*` directory.

## Signed local Mac Catalyst UI tests

Mac Catalyst UI automation needs a signed build, an administrator account, an unlocked Mac UI session, and local authentication when macOS asks to **Enable UI Automation**. The authorization is cached for eight hours. Select the **Surround** scheme and **My Mac (Mac Catalyst)** in Xcode, then run `SurroundUITests`, or use:

```sh
xcodebuild test \
  -scheme Surround \
  -project Surround.xcodeproj \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' \
  -only-testing:SurroundUITests
```

Hosted CI remains compile-only for Catalyst. The deterministic Catalyst UI
journeys are run locally on an unlocked Mac.

## Unsigned Mac Catalyst builds

The main app and widget support the Mac-optimized Catalyst interface. The
notification content and notification service extensions remain iOS-only, so
the Catalyst app intentionally excludes them.

Build the production configuration with the same unsigned compile-only check as
CI:

```sh
xcodebuild build \
  -scheme Surround \
  -project Surround.xcodeproj \
  -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO
```

Build the Beta configuration independently:

```sh
xcodebuild build \
  -scheme 'Surround Beta' \
  -project Surround.xcodeproj \
  -configuration 'Beta Debug' \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO
```

## OGS service and WebSocket test seams

The production client keeps its historical shared dependencies, while tests
construct `OGSService` with explicitly scoped collaborators. Their complete
API contracts live beside the declarations in
[`OGSService.swift`](Surround/Services/OGSService.swift) and
[`OGSWebsocket.swift`](Surround/Services/OGSWebsocket.swift).

| Type | Responsibility in tests |
| --- | --- |
| `OGSEnvironment` | Keeps the REST and WebSocket destinations explicit. |
| `OGSHTTPClient` | Lets service tests replace or isolate Alamofire and its cookie jar. |
| `AlamofireOGSHTTPClient.isolated()` | Creates an ephemeral session for one live test player. |
| `OGSWebsocketProtocol` | Lets service tests inject server events and inspect emitted commands without networking. |
| `OGSWebsocketTransport` | Replaces only WebSocket I/O while testing the real protocol engine. |
| `OGSWebsocketScheduling` | Replaces wall-clock time for reconnect, watchdog, ping, and callback-timeout tests. |
| `OGSWebsocketFrameCodec` | Tests framing and credential-redacted diagnostics independently of transport. |
| `OGSAnonymousConfigLoader` | Prevents anonymous-config REST requests in offline socket tests. |

Choose the narrowest seam for the behavior under test. `OGSService` event
tests normally use an `OGSWebsocketProtocol` fake. `OGSWebsocket` tests use the
real protocol engine with fake transport and scheduler implementations.

Every simulated account must own all of the following for its full lifetime:

- a distinct `AlamofireOGSHTTPClient.isolated()` instance;
- a distinct `UserDefaults` suite, removed during teardown;
- an `OGSRemoteSetting` scoped to those preferences (the service initializer
  creates this automatically when none is supplied); and
- a distinct `OGSWebsocket` configured for the same `OGSEnvironment`.

Keep `usesSurroundOverviewService`, `enablesAppSideEffects`, and `startsTimers`
disabled unless the test explicitly covers those production behaviors. A real
`OGSWebsocket.close()` is terminal: teardown should close it, and a later
session should create a new instance rather than attempting to restart it.
Deterministic tests normally also set `connectsAutomatically` to false. Setting
`installsObservers` to false additionally skips the initial login check and
debounced model observers that can initiate follow-up requests.

## Live OGS beta tests

To explore the beta site interactively, select the shared **Surround Beta**
scheme in Xcode and run the app normally. Its dedicated build configurations
select `https://beta.online-go.com` for both REST and WebSocket traffic, use a
separate bundle ID and app-group suite, and bypass the production-only Surround
companion service. The scheme does not contain account names or credentials.

The beta workflow is intentionally absent from push, pull request, and scheduled triggers. Its concurrency group allows only one play-through to use the shared account pool at a time.

The workflow fixes the destination to `https://beta.online-go.com` and provides these dedicated account names:

- `hakhoa`
- `hakhoa2`
- `hakhoa3`
- `hakhoa4`

Configure their shared password as the GitHub Actions secret `OGS_BETA_PASSWORD`. The workflow exposes it only to environment validation and the live test process. Do not put the password, cookies, CSRF values, or authentication frames in source, workflow inputs, logs, or test attachments. On failure, the workflow exports only XCTest attachments explicitly created by the suite after sanitizing them; it never uploads the raw result bundle, which may contain launch-environment metadata.

For a local run, export `OGS_BETA_PASSWORD` without placing it in a checked-in file. Then provide the same non-secret environment values used by the workflow:

```sh
export OGS_BETA_HOST=https://beta.online-go.com
export OGS_BETA_USERNAMES=hakhoa,hakhoa2,hakhoa3,hakhoa4
.github/ci-tools/validate-ogs-beta-environment.sh
```

When invoking `xcodebuild`, prefix those values with `TEST_RUNNER_` so Xcode passes them to the XCTest process and strips the prefix. For example, pass the password as `TEST_RUNNER_OGS_BETA_PASSWORD="$OGS_BETA_PASSWORD"`; do not add it to the shared scheme.

Every automated challenge and game must use the `surround-e2e-` name prefix. The live suite establishes that cleanup scope before creating anything, cleans current-run artifacts even when the scenario throws, and recovers stale prefixed artifacts before starting. It polls until cleanup is visible on all four accounts, falls back from cancellation to resignation when necessary, and closes every socket session during teardown. Cleanup must never cancel or resign an untagged challenge or game.
