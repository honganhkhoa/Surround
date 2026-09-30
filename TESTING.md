# Testing Surround

Surround's automated tests are split into three groups:

- `SurroundTests` contains deterministic unit and service tests. These run for every push and pull request and must not contact OGS.
- `SurroundUITests` contains deterministic, offline journeys for iPhone, iPadOS, and Mac Catalyst. Each test launches independently with bundled fixtures and the Debug-only `--surround-ui-testing` argument.
- `SurroundBetaTests` contains live integration scenarios against the isolated OGS beta service. Its separate shared scheme keeps it out of normal test runs; run it only by explicitly selecting that scheme locally or manually dispatching the **OGS beta integration tests** workflow.

The offline UI-test runtime uses a dedicated preferences suite, rejecting HTTP transport, and a no-op WebSocket. It does not use the production or Beta account data and cannot contact OGS.

Profile journeys opt into `--surround-profile-content` for populated ratings, active games, and paginated history without changing the screenshot scenes. They cover profile-owner history results, viewer-relative head-to-head results, game/profile route reuse, missing and provisional rating categories, persisted Rank/Rating display, hidden ratings, and dark appearance at the largest text size. `--surround-profile-sections-unavailable` exercises independent section retries while keeping the profile identity, selected rating, and actions available. `--surround-profile-short-history` verifies that a complete history preview does not offer a redundant “See all games” action.

Friendship journeys opt into `--surround-friendship` for three incoming requests and a short action delay. Home's avatar menu and the signed-in user's Profile do not list incoming requests, and Messages does not badge them while it has no request list. Compact navigation pushes Profile from the avatar menu and returns to Home with Back; sidebar navigation retains a Profile tab. The journeys open request senders through opponent search to cover acceptance, opponent-picker synchronization, both rejection choices and cancellation, removing a friend with confirmation, a sent request surviving profile navigation without enabling duplicate submissions, and incoming-request controls in dark appearance at the largest text size. `--surround-friendship-fails-once` makes the first action for each fixture player fail, exercising retained state and Retry without contacting OGS. Combined with `--surround-friendship-gated-response`, the first response waits for an explicit test-only release. The two failure journeys verify that delivery occurs while the sender profile is closed or after it has reopened with the action still pending, then verify the retained failure and Retry. Existing profile and screenshot fixtures keep their original friends and have no incoming requests unless the friendship flag is present. `--surround-empty-messages` clears the fixture conversations to verify that signed-in users can still open Messages without any threads. The signed-out `welcome` scene verifies that Messages is absent.

`OGSFriendshipTests` uses stubbed HTTP responses to cover independent friend/invitation loading, malformed entries, partial failures, cached membership preservation, and stale responses arriving across mutations or account changes. An injected monotonic clock verifies the five-second automatic refresh window without sleeping; explicit retries, overlapping subscribers, cancellation, and notification invalidation have separate coverage.

Navigation content layout is centralized in `AppNavigationStack`, `AppNavigationLink` for direct-view pushes, and `appNavigationDestination` for Boolean pushes. Use these shared entry points instead of applying layout modifiers in individual screens; value links using `StackRoute` are already covered by the stack’s destination builder. The content hosts publish `isVerticalToolbar` synchronously for game controls and backgrounds. Keep SDK-specific toolbar presentation in the shared navigation helpers; `AppNavigationLayout.reclaimsEmptyVerticalBarTopInset` remains the single switch for the optional top-inset reclamation. The Preferred Settings editor journey exercises Boolean editor presentation, a nested rules link, retained edits after Back, and the Create route.

## Deterministic unit tests

Run `SurroundTests` from Xcode, or select an installed iOS 26 iPhone simulator and run the unit target from the command line:

```sh
simulator_id="$(.github/ci-tools/select-ios-simulator.sh 26 iPhone)"
xcodebuild test \
  -scheme Surround \
  -project Surround.xcodeproj \
  -destination "platform=iOS Simulator,id=${simulator_id}" \
  -only-testing:SurroundTests
```

The simulator helper accepts an iOS major version and an optional exact family of `iPhone` or `iPad`; it defaults to `iPhone`. CI runs the unit target on both the current iOS 26 simulator and the latest installed simulator in the minimum supported iOS 18 major release.

App Store review tests use isolated preferences, an injected clock and delay, and a fake presenter. `AppReviewPolicyTests` covers eligibility, session lifecycle, cancellation, and requests from multiple windows; `AppReviewGameActivityTests` covers authoritative move and game-finish evidence. Automatic review requests are disabled in OGS Beta, previews, offline UI tests, and screenshot captures. The offline navigation journey verifies the About review link using the root's discarded URL action, without opening the App Store.

## Offline iPhone UI tests

The `iphone-navigation-ui-tests` CI matrix runs three targeted journeys on iOS 26 and the minimum supported iOS 18. The compact account journey checks the avatar menu’s Profile push and Back navigation without an extra tab, removal of Friend requests from the menu and own Profile, Settings, and logout. It intentionally skips iPad and Mac Catalyst, where account navigation uses the sidebar. The other two journeys check that Messages stays available with an empty inbox and disappears when signed out. Each test selects portrait orientation on iPhone.

```sh
simulator_id="$(.github/ci-tools/select-ios-simulator.sh 26 iPhone)"
result_label="Local-$(date +%Y%m%d-%H%M%S)"
mkdir -p TestResults
xcodebuild test \
  -scheme Surround \
  -project Surround.xcodeproj \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${simulator_id}" \
  -parallel-testing-enabled NO \
  -only-testing:SurroundUITests/ProfileUITests/testCompactAccountMenuPushesOwnProfileAndOpensSettings \
  -only-testing:SurroundUITests/SurroundUITests/testMessagesNavigationIsHiddenWhenSignedOut \
  -only-testing:SurroundUITests/SurroundUITests/testMessagesNavigationRemainsAvailableWithoutThreads \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 300 \
  -maximum-test-execution-time-allowance 300 \
  -resultBundlePath "TestResults/SurroundUITests-iPhone-${result_label}-Navigation.xcresult"
```

Substitute `18` in the simulator selection to reproduce the minimum-OS selection. CI uses `macos-26` for iOS 26 and `macos-15` with Xcode 26.2 for iOS 18. Each job builds once, validates the three selected test declarations, and runs without retries or parallel test workers. The limits are five minutes per test, twenty minutes for the test step, fifteen minutes for the build step, and forty minutes for the job. Result bundles are retained for fourteen days in `surround-iphone-26-navigation-test-results` and `surround-iphone-18-navigation-test-results`. This targeted lane does not run the full iPad journey suite or test Duo device poses.

## Offline iPad UI tests

The shared iPadOS and Mac Catalyst journeys cover top-level sidebar navigation including the own Profile entry, an empty Messages inbox, signed-out navigation without Messages, opening the bundled fixture game, switching active games through the bottom-bar popover, and entering and leaving Zen mode. `--surround-empty-messages` clears only offline private-message threads for the empty-inbox regression. The suite selects landscape orientation itself:

```sh
simulator_id="$(.github/ci-tools/select-ios-simulator.sh 26 iPad)"
result_label="Local-$(date +%Y%m%d-%H%M%S)"
.github/ci-tools/configure-ios-simulator-hardware-keyboard.sh "$simulator_id"
.github/ci-tools/run-ipad-ui-tests.sh build "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh preflight "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh main "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh profile "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh composer "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh continuity "$simulator_id" "$result_label"
```

The keyboard helper stops the Simulator.app host, shuts down only the selected simulator, updates its device-specific preference, then boots the device in a new Simulator.app process. Hardware-keyboard attachment is a best-effort optimization that can reduce software-keyboard transitions, not a test prerequisite; Simulator can keep its software keyboard visible while reporting that a hardware keyboard is attached. The helper warns when the preference or guest attachment cannot be verified, while lifecycle failures that prevent the selected simulator from returning to a booted state remain fatal. The separate XCUI preflight is authoritative and functional: the specific chat field must gain focus and accept the complete typed value regardless of which keyboard presentation Simulator chooses. It then uses the chat-background gesture to dismiss focus and verifies that the keyboard disappears. The shared UI helpers use this same single app gesture, avoiding a separate tap on the system Hide keyboard control before dismissing app focus.

The runner builds once per job, then separates the main journeys from the tests that intentionally focus a composer or exercise layout while it owns keyboard focus. The profile and friendship journeys live in the `ProfileUITests` class, which the `profile` phase runs and the `main` phase skips; add new profile journeys there. `GameContinuityUITests` has its own `continuity` phase. All three journey classes inherit their shared launch, element-resolution, and navigation helpers from `SurroundJourneyUITestCase`. Each test phase writes its own `.xcresult` bundle under `TestResults`. CI runs the main, profile, composer, and continuity phases whenever their job's shared build succeeds and the job is not cancelled, even when the preflight or preceding UI phase fails, preserving complete app-test diagnostics while reporting each failure directly. The runner does not retry failed tests or disable XCTest quiescence. Isolation prevents a lost XCTest keyboard-animation completion notification from slowing unrelated main/profile journeys. The preflight allows three minutes per test; other UI phases allow fifteen.

In CI, each iPadOS version runs the UI suite in three parallel jobs: main, profile, and composer/continuity. Main and profile retain 60-minute step limits. Composer and continuity each get an independent 45-minute step limit; adding continuity tests does not consume the existing composer's budget. The composer/continuity job runs its five-minute keyboard preflight first and has a 120-minute outer limit, leaving 25 minutes beyond the combined UI step limits for setup, build, and upload. Both main jobs and the iPadOS 26 profile job have 80-minute outer limits. The `minimum-ios-18` job pairs the iOS 18 unit tests with profile UI tests, reuses the UI derived-data directory for that sequential unit step, and retains its 90-minute outer limit. Each job builds its own test products; the extra job per OS trades another build for independent execution and budget. Matrix fail-fast is disabled so a failure on one OS cannot cancel the other OS's composer/continuity coverage.

The split follows a review of six September 21–25, 2026 CI runs: iPadOS 26 composer reached its old 30-minute step cap twice, before the twelve continuity tests were added. Completed main phases took about 18–37 minutes and profile phases 30–48 minutes, leaving headroom under their existing limits. Composer logs also showed repeated XCTest animation-completion waits, including one passing test lasting over fourteen minutes. The larger budget preserves coverage during those stalls; it does not resolve the underlying stall or assertion failures. Reassess the new continuity phase using hosted-run timings once available.

The phase selection is centralized in `.github/ci-tools/run-ipad-ui-tests.sh` so the iPadOS 26 and iPadOS 18 lanes cannot drift. Before invoking Xcode, the runner validates the journey class declarations and every isolated test declaration, so a renamed class or test cannot silently execute in the wrong phase or leave a phase empty.

`GameContinuityUITests` runs in the isolated `continuity` phase, after composer tests in CI. Only checks that need compact/regular transitions opt into the Debug-only `--surround-game-layout-transitions` harness, which changes the existing game route between regular width and a 430-point compact layout without changing its identity. These checks cover chat variation and move-preview exits, an ordinary draft and selected channel with active or dismissed keyboard focus, a frozen sharing draft and marked analysis session, and the preferred Forward branch after backing up. The harness exercises replacement of the real compact/regular view subtrees on the supported iPad runtimes; it does not simulate a physical fold or establish system sheet/toolbar adaptation. Rematch sheet retention and native device-pose behavior still require a Device Hub transition check. For that manual check, `--surround-rengo-game` adds generated teammates to the primary offline compatibility game, allowing expansion and mode-picker continuity to be exercised without a live game. Normal screenshots are unchanged unless the flag is supplied.

Other continuity checks use the native offline game or Home fixture without the layout harness. They verify that profile/tab navigation and an ordinary-chat Zen round trip retain drafts without automatically reopening the keyboard. The largest Dynamic Type check rotates the native fixture through both regular orientations, verifies that the preview action and square board fit, then uses Return to game and confirms the current board is restored. Explicit Analyze exits are checked in the native regular layout and the harness's compact layout, separately from state-preserving layout transitions.

`GameControlStateTests` drives scoring deadlines, disconnections, and refresh responses without wall-clock waits or live commands. Recovery must never replay a scoring command or unlock from cached overview data; a fresh authoritative game snapshot or live scoring-phase exit unlocks controls, including updates delivered without a manual refresh. Explicit refresh retries start a new bounded recovery episode, while automatic recovery remains coalesced. Toggle confirmations match only the requested intersections so unrelated concurrent markings cannot leave controls waiting. `AppReviewPolicyTests` separately verifies that abandoning move observation releases its pending token without recording success or failure.

CI runs these journeys on both iPadOS 26 and the latest installed iPadOS 18 runtime. To reproduce the minimum-OS lane locally, substitute `18` in the simulator selection commands above. All minimum-OS CI jobs run on `macos-15` and explicitly select Xcode 26.2. The `minimum-ios-18` job retains its unit and profile UI result bundles in the `surround-ios-18-test-results` artifact; the `minimum-ios-18-ui-tests` job retains main UI results in `surround-ios-18-ui-test-results`. The `ipad-composer-ui-tests` matrix stores preflight, composer, and continuity bundles in separate `surround-ipad-26-composer-continuity-test-results` and `surround-ipad-18-composer-continuity-test-results` artifacts.

For keyboard layout failures, match the device model as well as the runtime reported in the result bundle. An 11-inch iPad in landscape can exhaust chat space that remains available on a 13-inch iPad. The variation-sharing Zen round trip verifies that leaving Zen restores the automatically focused composer with its exact draft name, sharing status, and frozen 120-point preview, retaining a screenshot and accessibility hierarchy in that state. Keyboard dismissal remains covered by the separate preflight and composer interaction journeys.

On iOS 27 a SwiftUI `Menu` item wrapped in a `Section` loses its accessibility identifier and value and keeps only its localized label. Separate the groups of such a menu with `Divider()` wherever a test has to resolve an item without knowing the running language: it draws the same separators in the same places and keeps the identifiers on every runtime. The Analyze actions menu does this because the App Store capture runs in thirteen languages and matches on identifiers alone. `SurroundUITests` pins itself to English and resolves a menu item by identifier or, failing that, by the title of an element that has none, which covers both Mac Catalyst's `NSMenuItem` titles and the still-sectioned game actions menu.

### Focused iPadOS 18 CI verification

The CI workflow's manual dispatch offers a `test_scope` choice. Its default, `all`, retains the complete matrix; pushes and pull requests also retain that coverage. Select `ipad18-focus` to run only one focused job on `macos-15` with Xcode 26.2 and the same iPadOS 18 simulator-selection and hardware-keyboard setup used by the normal lanes:

```sh
gh workflow run main.yml --ref your-branch -f test_scope=ipad18-focus
```

The focused selection contains these six offline journeys, and validates each class and method declaration before running them:

- `GameContinuityUITests/testMovePreviewKeepsAnExitAcrossLayouts`
- `ProfileUITests/testHomeGameMenusOpenOpponentProfilesWithoutOpeningGames`
- `ProfileUITests/testPickerProfilesSelectDifferentOpponentsWithoutReplacingEditedChallenge`
- `SurroundUITests/testLiveGameBannerUsesHomeNavigationStack`
- `SurroundUITests/testRestoredLiveAutomatchLocksQuickMatchForm`
- `SurroundUITests/testVariationSharingDraftSurvivesChatSelection`

The job builds once, runs the selection without retries or parallel workers, and allows five minutes per test within a 45-minute job limit. Build and test steps have 15- and 35-minute caps; the outer limit bounds their combined duration. The `surround-ipad-18-focused-test-results` artifact retains the result bundle, build log, raw test log, bounded simulator log, and collector status for fourteen days. The external diagnostic wrapper captures an early screenshot and process samples on an animation-completion warning, an event-loop-idle notification warning, or a long app-idle wait after Share. This job uses the normal app environment with app animation tracing disabled; its collector observes the running processes without accessibility queries or focus changes.

### Opt-in animation-stall diagnostics

For a focused reproduction, the Debug app can log draft creation, focus requests, keyboard notifications, and composer/Analyze-menu appearance and frame changes. Tracing requires both the offline UI-test launch argument and `--surround-animation-diagnostics`; the test runner forwards the latter only when its `SURROUND_UI_ANIMATION_DIAGNOSTICS` environment variable equals `1`. The logs contain event metadata rather than chat contents. Appearance callbacks and observation identifiers describe SwiftUI observations; they do not prove that a UIKit menu presenter was destroyed.

After the shared build above, prepare a separate test configuration alongside the generated `.xctestrun`, preserving its relative product paths:

```sh
diagnostic_products="$(.github/ci-tools/run-ipad-ui-tests.sh derived-data-path "$simulator_id")/Build/Products"
python3 - "$diagnostic_products" <<'PY'
import plistlib
import sys
from pathlib import Path
products = Path(sys.argv[1])
sources = list(products.glob("Surround_*.xctestrun"))
assert len(sources) == 1, "Expected one generated Surround test configuration"
configuration = plistlib.loads(sources[0].read_bytes())
configuration["SurroundUITests"].setdefault("EnvironmentVariables", {})[
    "SURROUND_UI_ANIMATION_DIAGNOSTICS"
] = "1"
(products / "AnimationDiagnostics.xctestrun").write_bytes(plistlib.dumps(configuration))
PY
diagnostic_output="TestResults/AnimationDiagnostics-$(date +%Y%m%d-%H%M%S)"
python3 .github/ci-tools/diagnose-ipad-animation-stalls.py \
  --simulator "$simulator_id" --output "$diagnostic_output" -- \
  xcodebuild test-without-building \
  -xctestrun "$diagnostic_products/AnimationDiagnostics.xctestrun" \
  -destination "platform=iOS Simulator,id=${simulator_id}" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 240 \
  -maximum-test-execution-time-allowance 240 \
  -only-testing:SurroundUITests/SurroundUITests/testShareVariationUsesSelectedChannelAndStaysInChatAfterSending \
  -resultBundlePath "${diagnostic_output}.xcresult"
```

The wrapper preserves Xcode's exit status and writes raw console output, a bounded simulator log stream, and collector status into a fresh output directory. The first animation-completion or event-loop-idle notification warning in any test, or the first app-idle wait exceeding 15 seconds after a Share action, triggers one early screenshot and stack samples of the selected simulator's app and UI-test runner. Collection errors are retained in the status files. When the command finishes, `status.json` also pairs XCTest's in-app animation-idle requests with their replies from the simulator log, per app process, and lists each unanswered request with the UIKit input transitions just before it and the delay until XCTest's next in-app activity; compare that list with the console's animation-completion warning count. Collection does not query the accessibility hierarchy, dismiss the keyboard, or stop the app or runner. The diagnostic example limits each test to four minutes; normal CI allowances remain unchanged.

Use a dedicated simulator when comparing traces, and record its runtime, Xcode version, and keyboard setup. Run at most three isolated attempts initially; if they all pass, run the existing twelve-test composer selection once to check suite-state dependence. Inspect the first captured stall before expanding the run. Passing traces help establish the normal event order but do not demonstrate that an intermittent stall is fixed. Tracing itself can affect timing, so any resulting behavioral fix also needs verification with diagnostics disabled.

## Deployment target validation

The iPhone and iPad app, widget, and notification extensions support iOS 18.0. The Mac Catalyst app and its embedded widget continue to require macOS 26. The project expresses the latter as an SDK-qualified iPhone deployment-target override, so validate the generated bundle metadata instead of adding a manual Info.plist key.

Both test bundles carry the same SDK-qualified override. The `Surround` scheme's test action builds every testable for whichever destination is selected, and `-only-testing` narrows what runs rather than what builds, so a Mac Catalyst destination always compiles `SurroundTests` and `SurroundUITests` against the macOS 26 `Surround` module. Without the override those targets compile for iOS 18.0 and the build fails with `compiling for iOS 18.0, but module 'Surround' has a minimum deployment target of iOS 26.0`. Marking a test target as unsupported on Mac Catalyst does not exclude it: the scheme still builds it, against the iOS SDK, where it then fails to resolve the `Surround` module. Keep the override on both test targets.

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

Run the complete matrix from the repository root with Xcode 27 or newer, the pinned iOS 27.0 simulator runtime unless deliberately overridden, `jq`, `plutil`, `uuidgen`, Swift, and `sips`:

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

- uses the pinned iOS 27.0 runtime by default and fails if it is unavailable unless `APP_STORE_IOS_RUNTIME` deliberately selects another installed runtime;
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

To deliberately choose a different installed runtime or device templates, set `APP_STORE_IOS_RUNTIME` to the runtime's exact identifier, version, or name and set `APP_STORE_IPHONE_DEVICE` and `APP_STORE_IPAD_DEVICE` to exact simulator names. The runner does not fall back to the latest runtime when the default iOS 27.0 runtime is unavailable. When adding a language, keep the localization catalog, project regions, `AppStoreScreenshots.xctestplan`, `.github/ci-tools/capture-app-store-screenshots.sh`, `.github/ci-tools/app-store-release-locales.json`, and this guide in sync. When adding a scene, keep `AppStoreScreenshotTests.swift` and the runner's scene arrays in sync.

### Scene-refresh

When the shipping app and fixtures are unchanged, a supported scene replacement can reuse the remaining capture evidence. Review an English pilot first, then run:

```sh
.github/ci-tools/refresh-app-store-screenshots.sh \
  --base-capture /absolute/path/to/complete-original-capture \
  --base-input-context /absolute/path/to/original-input-context.json \
  --base-input-verification /absolute/path/to/verified-original-inputs.json \
  --output /absolute/path/to/new-scene-refresh-capture
```

This command requires Python 3.9+, Xcode, the original runtime and Xcode version, and a complete original thirteen-locale, two-family capture with its aggregate XCTest result, raw attachment manifest, source PNGs, log, and recorded source context. The currently supported replacement is defined by the scene contract in `.github/ci-tools/app-store-screenshot-provenance.py`; it is not an arbitrary scene selector. `--derived-data` selects a reusable build cache; `--device-name` selects an accepted iPhone template. It creates one disposable iPhone, builds the actual test products, selects the explicitly guarded scene-refresh test in a copied generated test plan, and captures all thirteen locales. It does not prepare or alter a Home Screen widget. Failure retains the sibling `<output>.refresh-work` evidence directory and deletes only its disposable device.

The new capture has `mode: "scene-refresh"` and a hashed `screenshot-provenance.json`; it explicitly identifies both original result bundles and both iPhone destinations. Every one of its 260 source images is bound to its original device, locale, test attachment and bytes. The full base and fresh aggregate result bundles, raw attachments, source images and source contexts are copied under `origins/`; the base run is never modified. The current contract refreshes one iPhone scene per locale: exactly 247 sources must remain byte-identical, and only the thirteen declared replacements may change. Arbitrary screenshot mixing is rejected. Source context records permit only the bounded screenshot test/tool and testing guide changes; shipping source changes require a new complete capture instead.

The offline verifier checks every evidence inventory and image hash and can be called by preparation and staging before their existing full matrix, decoded PNG, framing and manifest gates:

```sh
python3 .github/ci-tools/app-store-screenshot-provenance.py verify \
  --capture-root /absolute/path/to/new-scene-refresh-capture
python3 .github/ci-tools/tests/test_app_store_screenshot_provenance.py
```

Retained screenshots can retain their previous visual review only when their final framed bytes also match the reviewed hashes. Review every new localized output. The refresh never publishes metadata or screenshots.

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

For a patch release that changes only What's New and deliberately reuses every listing field and screenshot from an exact released version, use the metadata-only preparation path:

```sh
.github/ci-tools/app-store-release.sh prepare-metadata-only \
  --release ../AppStoreReleases/2.2.1/release.json \
  --source-version 2.2
```

This performs the same local release and shipping-version validation and takes a read-only App Store Connect snapshot, but it never launches screenshot capture. It requires the private release package to contain exactly `whatsNew` for all configured locales: version-wide, other version-localized, and App Info fields are rejected. It separately captures live and draft App Info and requires their localized fields, non-state attributes, categories, and age-rating declaration to match ID-free. It also verifies that the confirmed source has the exact locale/screenshot-family/count contract and that every screenshot has a file name, checksum, and `COMPLETE` processing state. The resulting artifact is named `.build/AppStoreRelease-MetadataOnly-<version>-<timestamp>` and contains the snapshot, normalized release, zero-screenshot manifest, and focused `review.html`.

After reviewing the exact source version, target version, notes, and manifest digest shown there, publish with all three confirmations:

```sh
.github/ci-tools/app-store-release.sh publish-metadata-only \
  --manifest .build/AppStoreRelease-MetadataOnly-2.2.1-<timestamp>/publish-manifest.json \
  --confirm-source-version 2.2 \
  --confirm-version 2.2.1 \
  --confirm-manifest-digest <reviewed-sha256>
```

The metadata-only publisher may create the confirmed target version. It omits `releaseType` from that POST, waits for Apple's inheritance to settle, and compares the target with the source by locale, non-What's-New metadata, screenshot family, order, file name, checksum, and processing state. Resource IDs are excluded from the inheritance comparison because copied resources receive new IDs. After that gate, the only permitted writes are sparse version-localization PATCHes whose attributes contain exactly `whatsNew`. It has no screenshot, preview, App Info, build, submission, or DELETE write route. Mutations are single-attempt, and a stable bundle/platform/version advisory lock prevents distinct handoffs from racing. Its `metadata-only-publish-journal.json`, post-create snapshot, and final snapshot support bounded reconciliation; an ambiguous target-version POST is never replayed automatically.

Publishing is deliberately a separate, explicit command:

```sh
.github/ci-tools/app-store-release.sh publish \
  --manifest .build/AppStoreRelease-2.1-<timestamp>/publish-manifest.json \
  --confirm-version 2.1
```

Only the two explicit publishing commands mutate App Store Connect. The full `publish` path verifies the exact version, manifest checksums, and unchanged remote snapshot; uploads and orders exactly ten iPhone and ten iPad screenshots per locale; applies only reviewed metadata; and reads the result back. Its sibling `publish-journal.json` supports a reconciled rerun after a journaled interruption; an ambiguous create or upload-reservation outcome stops for inspection instead of being replayed blindly. Neither workflow uploads or selects an app build or submits the version for App Review.

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
- the existing full-capacity small, medium, and large home-screen widgets on both device families;
- one-game small plus one- and three-game large adaptive-layout regressions on both device families; and
- one-, four-, and six-game extra-large widgets on iPad.

Run the complete 72-pair matrix from the repository root:

```sh
.github/ci-tools/capture-ios-version-comparison.sh \
  --output .build/iOS18-vs-iOS26-route-comparison
```

The output path must not already exist. The gitignored artifact contains:

- `originals/ios-18/<iphone|ipad>/` and `originals/ios-26/<iphone|ipad>/`, holding 144 full-resolution captures;
- `comparisons/<iphone|ipad>/`, holding 72 labelled, lossless side-by-side PNGs;
- `comparison.md`, a responsive `index.html`, and `run-metadata.json`; and
- `runs/<ios-18|ios-26>/`, retaining each run's result bundles, logs, and attachment manifests.

The metadata records the source fingerprint, Xcode version, runtime and device identities, locale, system appearance, verified full-color widget rendering mode, orientation, pixel dimensions, scene manifest, and widget family.

The runner requires Xcode 26 or newer, installed iOS 18.0 and iOS 26.0 simulator runtimes, matching simulator device types, `jq`, Swift, and `sips`. For each OS run, it creates fresh temporary simulators from the exact required device-type and runtime identifiers. It also verifies that the Surround app and UI-test runner are absent before testing, so old preferences, app data, and Home Screen placement cannot contaminate the captures. The temporary simulators are shut down and deleted during teardown, including after a failed capture. Each simulator boot has a three-minute bound and one clean retry so a wedged CoreSimulator display service fails deterministically instead of hanging the capture indefinitely.

Each per-OS run selects all three tests in the `CompatibilityScreenshots` test plan: the stable route/widget matrix, the adaptive widget regressions, and physical SpringBoard tap coverage. The tap test checks linked board and timer regions plus genuine grid-gap, outer-padding, and rail background. It produces no screenshot attachments. Before accepting any widget capture, the harness samples every expected board region and rejects a visually uniform board, which catches blank or solid-color rendering while keeping the screenshot artifact contract deterministic.

To run this widget coverage once on one installed runtime without producing the cross-version comparison, use the checked-in per-runtime command:

```sh
output_path=".build/CompatibilityWidgets-iOS26-$(date +%Y%m%d-%H%M%S)"
.github/ci-tools/capture-compatibility-screenshots.sh --output "$output_path" --runtime 26.0
```

These SpringBoard tests remain explicitly skipped by the normal `Surround` scheme, so the regular iPad UI lanes do not inherit their simulator setup cost. The dedicated compatibility test plan and runner are their supported entry point.

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

`-only-testing` selects which tests run, not which targets build, so this command also compiles `SurroundTests`; both test targets therefore need the Catalyst deployment-target override described under [Deployment target validation](#deployment-target-validation).

Hosted CI remains compile-only for Catalyst. The deterministic Catalyst UI journeys are run locally on an unlocked Mac.

## Unsigned Mac Catalyst builds

The main app and widget support the Mac-optimized Catalyst interface. The notification content and notification service extensions remain iOS-only, so the Catalyst app intentionally excludes them.

Build the production configuration with the same unsigned compile-only check as CI:

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

The production client keeps its historical shared dependencies, while tests construct `OGSService` with explicitly scoped collaborators. Their complete API contracts live beside the declarations in [`OGSService.swift`](Surround/Services/OGSService.swift) and [`OGSWebsocket.swift`](Surround/Services/OGSWebsocket.swift).

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

Choose the narrowest seam for the behavior under test. `OGSService` event tests normally use an `OGSWebsocketProtocol` fake. `OGSWebsocket` tests use the real protocol engine with fake transport and scheduler implementations.

Every simulated account must own all of the following for its full lifetime:

- a distinct `AlamofireOGSHTTPClient.isolated()` instance;
- a distinct `UserDefaults` suite, removed during teardown;
- an `OGSRemoteSetting` scoped to those preferences (the service initializer creates this automatically when none is supplied); and
- a distinct `OGSWebsocket` configured for the same `OGSEnvironment`.

Keep `usesSurroundOverviewService`, `enablesAppSideEffects`, and `startsTimers` disabled unless the test explicitly covers those production behaviors. A real `OGSWebsocket.close()` is terminal: teardown should close it, and a later session should create a new instance rather than attempting to restart it. Deterministic tests normally also set `connectsAutomatically` to false. Setting `installsObservers` to false additionally skips the initial login check and debounced model observers that can initiate follow-up requests.

## Live OGS beta tests

To explore the beta site interactively, select the shared **Surround Beta** scheme in Xcode and run the app normally. Its dedicated build configurations select `https://beta.online-go.com` for both REST and WebSocket traffic, use a separate bundle ID and app-group suite, and bypass the production-only Surround companion service. The scheme does not contain account names or credentials.

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
