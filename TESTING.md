# Testing Surround

Surround's automated tests are split into three groups:

- `SurroundTests` contains deterministic unit and service tests. These run for every push and pull request and must not contact OGS.
- `SurroundUITests` contains deterministic, offline journeys for iPhone, iPadOS, and Mac Catalyst. Each test launches independently with bundled fixtures and the Debug-only `--surround-ui-testing` argument.
- `SurroundBetaTests` contains live integration scenarios against the isolated OGS beta service. Its separate shared scheme keeps it out of normal test runs; run it only by explicitly selecting that scheme locally or manually dispatching the **OGS beta integration tests** workflow.

The offline UI-test runtime uses a dedicated preferences suite, rejecting HTTP transport, and a no-op WebSocket. It does not use the production or Beta account data and cannot contact OGS.

Profile journeys opt into `--surround-profile-content` for populated ratings, active games, and paginated history without changing the screenshot scenes. They cover profile-owner history results, viewer-relative head-to-head results, game/profile route reuse, missing and provisional rating categories, persisted Rank/Rating display, hidden ratings, and dark appearance at the largest text size. `--surround-profile-sections-unavailable` exercises independent section retries while keeping the profile identity, selected rating, and actions available. `--surround-profile-short-history` verifies that a complete history preview does not offer a redundant “See all games” action.

Friendship journeys opt into `--surround-friendship` for three incoming requests and a short action delay. Home's avatar menu and the signed-in user's Profile do not list incoming requests; Messages lists them under Friend requests and counts them in its tab badge. Compact navigation pushes Profile from the avatar menu and returns to Home with Back; sidebar navigation retains a Profile tab. The journeys open request senders through opponent search to cover acceptance, opponent-picker synchronization, both rejection choices and cancellation, removing a friend with confirmation, a sent request surviving profile navigation without enabling duplicate submissions, and incoming-request controls in dark appearance at the largest text size. `--surround-friendship-fails-once` makes the first action for each fixture player fail, exercising retained state and Retry without contacting OGS. Combined with `--surround-friendship-gated-response`, the first response waits for an explicit test-only release. The two failure journeys verify that delivery occurs while the sender profile is closed or after it has reopened with the action still pending, then verify the retained failure and Retry. Existing profile and screenshot fixtures keep their original friends and have no incoming requests unless the friendship flag is present. `--surround-empty-messages` clears the fixture conversations to verify that signed-in users can still open Messages without any threads. The signed-out `welcome` scene verifies that Messages is absent.

`OGSFriendshipTests` uses stubbed HTTP responses to cover independent friend/invitation loading, malformed entries, partial failures, cached membership preservation, and stale responses arriving across mutations or account changes. An injected monotonic clock verifies the five-second automatic refresh window without sleeping; explicit retries, overlapping subscribers, cancellation, and notification invalidation have separate coverage.

Navigation content layout is centralized in `AppNavigationStack`, `AppNavigationLink` for direct-view pushes, and `appNavigationDestination` for Boolean pushes. Use these shared entry points instead of applying layout modifiers in individual screens; value links using `StackRoute` are already covered by the stack’s destination builder. The content hosts publish `isVerticalToolbar` synchronously for game controls and backgrounds. Keep SDK-specific toolbar presentation in the shared navigation helpers; `AppNavigationLayout.reclaimsEmptyVerticalBarTopInset` remains the single switch for the optional top-inset reclamation. The Preferred Settings editor journey exercises Boolean editor presentation, a nested rules link, retained edits after Back, and the Create route.

## Opt-in Beta simulator authentication

Debug Beta simulator builds include a local login bridge for preparing a real test account before a UI journey. It is compiled only with `DEBUG`, `OGS_BETA`, `MAIN_APP`, and `targetEnvironment(simulator)`. It is inactive without explicit launch arguments and rejects production origins and offline fixture mode. Release, physical-device, Catalyst, and production app builds omit the bridge. This prepares native authentication; it does not exercise the embedded sign-in form. Use a dedicated simulator and a correctly signed Beta installation.

A host companion launches the app with `--surround-beta-login-bridge <UUID>` and `--surround-beta-login-account <username>`. The app creates a private `tmp/surround-beta-login-bridge/<UUID>/` directory containing `ready.json` with the protocol version, run/account, exact Beta origin/bundle, expiry, and an ephemeral Curve25519 public key. The private key stays in app memory. The host reads a locally provisioned credential internally and atomically writes a mode-0600 `request.json` with version `1`, its base64 raw Curve25519 public key, and a base64 AES-GCM combined ciphertext. The encrypted JSON contains `username` and `password`. Derive the 32-byte key with X25519 and HKDF-SHA256 using the run UUID's UTF-8 bytes as salt and `surround-beta-simulator-login-v1` as shared info; authenticate the UTF-8 string `<UUID>:<username>` as additional data. Passwords are limited to 4,096 UTF-8 bytes; the complete encrypted request is limited to 128 KiB, allowing JSON escaping, AES-GCM, and base64 overhead even for a maximum-length password and a 64-character account name. Both the host and app enforce these limits.

The app accepts one request within 90 seconds, deletes its ciphertext before decrypting, and uses the normal native login path. A fresh HTTP UI configuration and the WebSocket server's `authenticate` identity callback must match the expected account. `result.json` contains only version, run/account, status (`authenticated`, `rejected`, `failed`, or `timeout`), and the booleans `httpAuthenticated`, `webSocketAuthenticated`, and `persistedSession`. A local socket readiness flag alone is insufficient. The host must remove its exact handoff directory after consuming the result. Passwords and tokens must never enter launch arguments, environment variables, logs, attachments, or plaintext handoff files. Plaintext exists transiently in host/app memory; zeroization is not guaranteed.

`--surround-beta-login-probe` verifies a persisted session without a password request. A different existing account is preserved unless the host explicitly passes `--surround-beta-login-replace-account`. Login clears the prior identity before attempting authentication. After timeout or interruption, session state is uncertain: cancelling the existing Combine login subscription does not cancel its underlying HTTP request. Inspect or probe the session before retrying.

The standalone synthetic checks use no Keychain, simulator, or network:

```sh
mkdir -p .build/beta-login-checks/module-cache
xcrun swiftc -D BETA_SIMULATOR_LOGIN_BRIDGE_TESTS \
  -module-cache-path .build/beta-login-checks/module-cache \
  Surround/UITesting/BetaSimulatorLoginBridge.swift \
  .github/ci-tools/tests/BetaSimulatorLoginBridgeChecks.swift \
  -o .build/beta-login-checks/checks
.build/beta-login-checks/checks
```

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

`StonePlacementSoundTests` checks theme placement/capture assets, prisoner deltas (including legal self-capture), capture-count tiers, separate placement and capture voices, voices that outlast the next move and their cache bank, a clip that comes round while it sounds stopped before it restarts, ended voices that stay ended when the audio clock restarts, a bound on overlapping voices, cancellation when muting, switching theme or leaving the board, the user's committed stone played once with its echo skipped, a stone played in another window only expected, a window one move behind still expecting it, overlapping requests settled each on its own, two requests for the same stone and many for one turn each waiting, a stone that a snapshot showed and an undo took back no longer expected, a stone a snapshot already showed keeping its capture, a withdrawn commit's capture stopped if still due, no stale match after a withdrawn commit, and bounded lazy caching without playing audio. `GameReplayTests` verifies that only successful incremental main-line moves emit `Game.moveApplied`; initial loads, reconnect snapshots, analysis, undo, and scoring stay silent. It also checks that a committed stone follows the game's rules, captures, self-capture and free handicap included, without being registered. `GameControlStateTests` covers the submit path: a stone sent on a connected socket sounds once and its echo plays nothing, a refusal withdraws it, in every window's model of the game, even once the sending screen has moved on, but leaving the game or an answer lost with the connection or timed out does not, so a late echo stays silent, and a pass, a move sent while offline or a game without data commits nothing. A commit in one window reaches another window's model, whose board then skips its own echo, and the table of those models is swept as games come and go. Through an injected recorder it also checks the haptics: a commit plays one impact with its click, the echo plays none, a refusal plays an error after that impact, and a pending stone only prepares the impact. The Simulator plays no haptics, so judge their feel on an iPhone. The same tests drive the voice countdown's announcer through `Game.$clock`, as the game screen does: it says the user's own last seconds but nothing for the clock that ends their turn, skips a byo-yomi period's top number at turn start but says each lost period, one-second ones included, counts a reconnect snapshot's or an overview's clock from now, holds for a second after a commit until the board moves on, even when another window's request is refused, resumes after a refusal, and stays quiet once the move is applied, before the clock starts and after the game ends. `SurroundThemeTests/testOnlyReleasedThemesShipTheirArt` keeps both sound families in their theme's shipping or Debug-only asset catalog. For listening, enable Stone sounds in Settings and use its demo board or a game: your own stone sounds when you submit it, or on release with auto-submit, rather than when OGS echoes it; captures follow placement by about 250 ms and finish even when the next move or a pass comes first, while muting, leaving the board, or switching theme or game stops them.

App Store review tests use isolated preferences, an injected clock and delay, and a fake presenter. `AppReviewPolicyTests` covers eligibility, session lifecycle, cancellation, and requests from multiple windows; `AppReviewGameActivityTests` covers authoritative move and game-finish evidence. Automatic review requests are disabled in OGS Beta, previews, offline UI tests, and screenshot captures. The offline navigation journey verifies the About review link using the root's discarded URL action, without opening the App Store.

## Offline iPhone UI tests

The `iphone-navigation-ui-tests` CI matrix runs targeted journeys on iOS 26 and the minimum supported iOS 18, in two test steps. The first runs three. The compact account journey checks the avatar menu’s Profile push and Back navigation without an extra tab, removal of Friend requests from the menu and own Profile, Settings, and logout. It intentionally skips iPad and Mac Catalyst, where account navigation uses the sidebar. The other two journeys check that Messages stays available with an empty inbox and disappears when signed out. Each test selects portrait orientation on iPhone. The second, "Run game control and own-game freeze tests", runs the own-game freeze regression below at four cycles and three journeys of the in-game control in a phone's bars: `SurroundUITests/testCompactBottomBarKeepsActiveGamesBeforeTheModes`, `GameControlUITests/testTheControlNeverHidesAnalyzeOrChat` and `GameControlUITests/testAtTheLargestTextSizeAHoldOpensThePopover` (see `GameControlUITests` below).

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

The game control step selects its journeys the same way:

```sh
TEST_RUNNER_SURROUND_UI_OWN_GAME_NAVIGATION_CYCLES=4 xcodebuild test \
  -scheme Surround \
  -project Surround.xcodeproj \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${simulator_id}" \
  -parallel-testing-enabled NO \
  -only-testing:SurroundUITests/SurroundUITests/testCompactBottomBarKeepsActiveGamesBeforeTheModes \
  -only-testing:SurroundUITests/SurroundUITests/testOwnGameNavigationAndSwitchingRemainResponsive \
  -only-testing:SurroundUITests/GameControlUITests/testTheControlNeverHidesAnalyzeOrChat \
  -only-testing:SurroundUITests/GameControlUITests/testAtTheLargestTextSizeAHoldOpensThePopover \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 900 \
  -maximum-test-execution-time-allowance 900 \
  -resultBundlePath "TestResults/SurroundUITests-iPhone-${result_label}-GameControl.xcresult"
```

Substitute `18` in the simulator selection to reproduce the minimum-OS selection. CI uses `macos-26` for iOS 26 and `macos-15` with Xcode 26.2 for iOS 18. Each job builds once, validates each step's selected test declarations, and runs without retries or parallel test workers. The navigation step allows five minutes per test and twenty for the step. The game control step allows fifteen minutes per test and thirty for the step, and runs whether or not the navigation step passed; its journeys take about six to eight minutes on a local iPhone simulator. On November 18 hosted runners took 14 minutes on iOS 18 and 16 on iOS 26, of which the own-game freeze regression took 6 and 9. The build step has fifteen minutes and the job seventy. Each step writes its own result bundle, retained for fourteen days in `surround-iphone-26-navigation-test-results` and `surround-iphone-18-navigation-test-results`. This targeted lane does not run the full iPad journey suite or test Duo device poses.

Select `-only-testing:SurroundUITests/SurroundUITests/testOwnGameNavigationAndSwitchingRemainResponsive` for the native iOS regression of the own-game layout freeze fixed in `8f18885`. It keeps the normal offline navigation shell mounted, with the live-game banner fixture, while the tab bar hides and shows again and again. Each cycle opens own correspondence game 26268398 from Home, opens the in-game control's popover with `openGameControlPopover` and switches in place to 26268399, goes Back, opens the live game 26268404 from Home and goes Back, then opens finished game 26268397 from Home's Game history and goes Back twice: three opens, each a hide, a switch, and four Backs. Twenty cycles run by default, split between native portrait and landscape orientations. Every step has a ten-second wait, and Back must leave Game Detail with a real Home transition. Home's rows are reached by slow, bounded drags of Home's own content that start below the root notices, and are tapped at their centre by position: on an iPad in landscape, XCTest sends an element tap on a row that crosses the window's edge unrotated, and it lands elsewhere. A failed check keeps a screenshot and the accessibility hierarchy. Progress markers identify the last completed cycle and phase, and the state the control should show, for host-side hang triage.

The journey always launches with two Debug drivers. `--surround-fixture-clock-ticks` gives both players of game 26268404 30 minutes at launch and then ticks every fixture clock each second, so in the chip state the chip's label, which speaks its countdown, differs between two reads 2 s apart. `--surround-game-control-cycle on-disappear` steps the fixture to the next of four states each time a Game Detail screen leaves: the chip (26268404 on your move), base (on the opponent's move), a dot (the opponent's move and a live challenge received) and an outage (your move, every window's socket `.reconnecting`). A cycle closes three screens, and three and four share no factor, so over any four cycles every open meets each state once, and the three games cross every form of the control and its absence: the correspondence games, which have the picker, show the chip or base, the live game base or the dot, and the finished game, which has no picker, the chip, the inbox or no control. Each open checks the state its control first drew, which Debug builds expose as the value of `game.control.firstState`. Before an open that meets the outage the journey waits 3 s on Home, so the game's title slot holds the status from its first frame, during the hide; the fixture ticker ignores the socket, so the outage doesn't check ticking. The driver counts screens, not their content: iOS 18's Back, in which a screen's content leaves and comes back, steps once, while a Game Detail pushed by mistake also closes, steps the state again and fails the next open's check. With `TEST_RUNNER_SURROUND_UI_GAME_CONTROL_CYCLE=on-appear` the state steps as each screen first shows its content instead, inside the hide itself, after the bar's first pass. Nothing is posted, so devices run the drivers as simulators do. Each step logs `GAME-CONTROL-CYCLE <state> services=<count>` under subsystem `com.honganhkhoa.Surround`, category `GameControlCycle`.

`TEST_RUNNER_SURROUND_UI_OWN_GAME_NAVIGATION_CYCLES` selects 2–100 cycles (default: 20). A cycle takes about a minute on a local simulator and twice that on a hosted runner, so CI's iPhone and iPad lanes run 4, which meet every state at every open once. `TEST_RUNNER_SURROUND_UI_MAIN_THREAD_WATCHDOG=1` adds `--surround-main-thread-watchdog`, which works in any Debug launch, on a device too: a timer on the main queue beats every 100 ms, a timer on a queue of its own checks the last beat every 100 ms, and each gap of 250 ms or more logs `MAIN-HANG <ms> ms at <s> s`, counting seconds from the watchdog's start, under category `MainThreadWatchdog`. A gap that lasts also logs `MAIN-HANG <ms> ms at <s> s, ongoing` once a second, so a freeze leaves a record even when the app never recovers; gaps in the first seconds after launch are usual. `TEST_RUNNER_SURROUND_UI_FORUM_224_CONTROL=<low>,<high>` adds `--surround-forum-224-control`, the regression's positive control: version 2.4's compact bottom bar comes back, alone in the bar in compact portrait outside Zen, and its item shows by the height Game Detail has spare, as 2.4's did. Hidden, it shows once `<low>` points are spare; shown, it stays while any are. Its last decision is what `onChange` recorded, which never runs inside the tab bar's animated hide, so a hide that starts hidden and leaves between `<low>` and `<high>` spare, `<high>` being `<low>` plus the bar's height, never finishes its layout and freezes the app. It logs each new reading in its first 200 passes, then every thousandth pass, as `FREEZE-CONTROL pass <n>: spare <pt> pt…` under category `FreezeControl`, saying when the reading lies between the two. A device's band comes from two runs: `9000,9052` keeps the item hidden and reads the spare with the tab bar still up and after it hides, and `0,52` keeps it shown, which after the hide reads the spare less the bar's height. A `<low>` between the first two readings, with `<high>` that plus the bar's height, should hang: on the iPhone 18 Pro simulator, iOS 27.2, the readings were 273, 322 and 270 pt, and `300,352` hung. A malformed band fails the journey before it launches. `TEST_RUNNER_SURROUND_UI_OWN_GAME_NAVIGATION_WINDOW=375x548` runs every cycle, in portrait, in an iPad window of that size, which the journey sets with the window's resize grabber and gives back full size in teardown. Without it an iPad run asks for a full-size window at launch: iPadOS 27 can open the app in a floating window whose edges take a drag near them as a resize. `TEST_RUNNER_SURROUND_UI_SUPERCHAT_MIDWAY=1` raises the moderator cover midway (see the cover's journeys below). The test uses only bundled fixtures and does not simulate Duo poses; native Closed/Book/Open continuity still needs its own audit.

## Offline Duo sidebar test

On iOS 27 phones, the root navigation uses an owned `UITabBarController` so the Duo sidebar can show native Surround/OGS groups and overlap every destination. Hosting controllers remain stable across compact and regular layouts. UIKit receives the full window, including the keyboard region, so its tab bar stays behind a software keyboard. Shared navigation content ignores horizontal container safe areas and restores horizontal padding measured from the enclosing window's safe-area guide. Titles and toolbars retain UIKit's layout; this modifier leaves vertical content insets and keyboard avoidance unchanged. Presented stacks keep their own layout. Padding must not depend on safe-area geometry measured from that same modified content, which can oscillate at pixel boundaries during native sidebar layout. Game screens forward tab-bar visibility through `appTabBarHidden(_:)`.

Start an iPhone Duo simulator in Open pose, then run the focused offline journey with its UUID:

```sh
TEST_RUNNER_SURROUND_EXPECT_DUO_SIDEBAR=1 xcodebuild test \
  -scheme Surround \
  -project Surround.xcodeproj \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${simulator_id}" \
  -parallel-testing-enabled NO \
  -only-testing:SurroundUITests/DuoSidebarUITests \
  -resultBundlePath "TestResults/SurroundUITests-DuoSidebar.xcresult"
```

The journey checks both group headings, a stationary Public games card while the sidebar opens, grouped Settings/About/Web destinations, and automatic dismissal after selection. It asserts the owned container exists. Without the expectation flag it skips unsupported devices and a collapsed Duo; an explicitly expected Open run fails when its sidebar toggle is missing. Xcode passes `TEST_RUNNER_SURROUND_EXPECT_DUO_SIDEBAR=1` to the test runner as `SURROUND_EXPECT_DUO_SIDEBAR=1`. Verify that the Open result contains an executed test. It does not change folding poses. Separately verify content space and board-edge taps beside the game's vertical toolbar, and exercise selected destinations and pushed game state through Closed, Book, Open, and rotation without relaunching. Debug launches with `SURROUND_DUO_SIDEBAR_DIAGNOSTICS=1` report hosting bounds, safe areas, the closed baseline, and the measured sidebar delta.

`AppReviewPresentationUITests` launches a production `AppReviewScene` around the offline MainView, with dictionary-backed review history and an empty marketing version that prevents system requests. It checks coordinator forwarding, Home visibility through a game push and Back, local pending presentation blocking, and inactive retained tabs. Run it on an iOS 27 phone to exercise the owned hosting boundary.

`DuoProfileSidebarUITests` exercises Home's sidebar selection of the own Profile tab and Home → game → opponent avatar → pushed Profile. Open runs check repeated native sidebar opening/closing over stationary profile content and a responsive return to Home or the originating game. The pushed route checks repeated entry/Back and retained board state in Closed as well. Add `-only-testing:SurroundUITests/DuoProfileSidebarUITests` to the command above; the same strict Open expectation flag applies. Back resolves the visible control, including the Duo's vertical toolbar.

`SidebarKeyboardUITests` opens a private conversation through the Messages inbox in MainView. It requires an actual docked software keyboard, records composer/container/tab-bar geometry and screenshots, and preserves an unsent draft. It records keyboard dismissal when the conversation gesture or system control supports it; otherwise it records `keyboard-dismissal-unavailable` without claiming dismissal coverage. Use `TEST_RUNNER_SURROUND_EXPECT_OWNED_TABS=1` for the owned shell and additionally `TEST_RUNNER_SURROUND_EXPECT_DUO_SIDEBAR=1` for Duo Open. `TEST_RUNNER_SURROUND_SIDEBAR_KEYBOARD_ORIENTATION=landscape` selects landscape; otherwise it uses portrait. Disable hardware keyboard attachment on the selected simulator before this diagnostic. Compare the same journey against clean HEAD; a standalone message-thread fixture does not exercise the main shell.

## Offline iPad UI tests

The shared iPadOS and Mac Catalyst journeys cover top-level sidebar navigation including the own Profile entry, an empty Messages inbox, signed-out navigation without Messages, opening the bundled fixture game, switching active games through the toolbar popover, and entering and leaving Zen mode. Game Detail uses native Analyze and Chat toolbar toggles. Chat and Analyze are mutually exclusive in every layout. Switching or closing a panel retains its draft, selected analysis position and tools; resizing never restores a second panel. Regular landscape keeps a fixed side column for the clock and the selected panel, while portrait panels open above the board. iPad games hide the app tab bar, and the native sidebar overlays the unchanged content. On iPad, the in-game control, in Active games' place, uses the top toolbar between Chat and Zen mode, and Mac Catalyst keeps it in the top toolbar too. iPhone portrait and narrow iPad windows place it in the bottom bar, and the shared navigation container adapts it to the Duo’s vertical toolbar. `--surround-empty-messages` clears only offline private-message threads for the empty-inbox regression. The suite selects landscape orientation itself:

```sh
simulator_id="$(.github/ci-tools/select-ios-simulator.sh 26 iPad)"
result_label="Local-$(date +%Y%m%d-%H%M%S)"
.github/ci-tools/configure-ios-simulator-hardware-keyboard.sh "$simulator_id"
.github/ci-tools/run-ipad-ui-tests.sh build "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh preflight "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh main "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh profile "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh messages "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh activity "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh game-control "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh composer "$simulator_id" "$result_label"
.github/ci-tools/run-ipad-ui-tests.sh continuity "$simulator_id" "$result_label"
```

The keyboard helper stops the Simulator.app host, shuts down only the selected simulator, updates its device-specific preference, then boots the device in a new Simulator.app process. Hardware-keyboard attachment is a best-effort optimization that can reduce software-keyboard transitions, not a test prerequisite; Simulator can keep its software keyboard visible while reporting that a hardware keyboard is attached. The helper warns when the preference or guest attachment cannot be verified, while lifecycle failures that prevent the selected simulator from returning to a booted state remain fatal. The separate XCUI preflight is authoritative and functional: the specific chat field must gain focus and accept the complete typed value regardless of which keyboard presentation Simulator chooses. It then uses the chat-background gesture to dismiss focus and verifies that the keyboard disappears. The shared UI helpers use this same single app gesture, avoiding a separate tap on the system Hide keyboard control before dismissing app focus.

The runner builds once per job, then separates the main, Profile, Messages, Activity, game control, composer, and continuity journeys. The profile and friendship journeys live in the `ProfileUITests` class, which the `profile` phase runs and the `main` phase skips; add new profile journeys there. The entire `MessagesNavigationUITests` class runs in the `messages` phase and is excluded from `main`, including conversation-heading Profile navigation and exact draft restoration after Back. CI runs the main and Profile phases in three parts and the Messages phase in four instead. `messages-2`, `messages-3` and `messages-4` run every fourth test declaration in their class, starting with the second, the third and the fourth. `profile-2` and `profile-3` run every third declaration in theirs, starting with the second and the third, and `main-2` and `main-3` do the same in the `SurroundUITests` class, less the preflight and composer tests main skips. To balance the three parts, `main-2` also runs the whole, slow `LocalizationUITests` class; main's other classes, `ThemePickerUITests` and `ThemedScreensUITests` included, stay in part 1. `main-3` runs only its share of `SurroundUITests`, because that share holds the own-game navigation journey, which took 9 to 14 minutes on hosted iPads at four cycles on November 18. With the two theme classes still in `main-3`, a slow hosted iPadOS 26 run on November 16 reached its 46-minute deadline in that part, while part 1 had finished in 26 minutes. `main-1`, `profile-1`, and `messages-1` run the rest of their phase by skipping exactly what the later parts run, so a test the declaration scan misses still runs in part 1. Alternating declarations keeps the parts balanced as tests are added. `GameContinuityUITests` has its own `continuity` phase, `ActivityListUITests` and `ActivityConversationUITests` share the `activity` phase, and `GameControlUITests` has the `game-control` phase; `main` skips all three. The runner sets `TEST_RUNNER_SURROUND_UI_OWN_GAME_NAVIGATION_CYCLES` to 4 unless its caller sets it, so main runs the own-game freeze regression at four cycles. Every class the runner names inherits its shared launch, element-resolution, and navigation helpers from `SurroundJourneyUITestCase`. Each test phase writes its own `.xcresult` bundle under `TestResults`. CI runs each phase whenever its job's shared build succeeds and the job is not cancelled, even when the preflight or preceding UI phase fails, preserving complete app-test diagnostics while reporting each failure directly. The runner reruns no failed test except those, at most three, that a hosted simulator crash killed or a stalled UI query failed during a supervised step (see below), and does not disable XCTest quiescence. The preflight allows five minutes per test; other UI phases allow fifteen, and up to twenty to a test that asks for more. The own-game freeze regression asks for five minutes a cycle: at four cycles a hosted iPadOS 18 runner took nearly 14 of its former 15 on November 18.

In CI, each iPadOS version runs the UI suite in four parallel jobs: main, profile, messages, and composer/continuity. Main and Profile run as three steps and Messages as four, each part with an independent 50-minute limit and its own result bundle. After its four parts, each Messages job runs the `activity` phase as a 30-minute step, and after its three, each profile job runs the `game-control` phase as a 45-minute step. The independent `ipad-messages-ui-tests` and `minimum-ios-18-messages-ui-tests` jobs each have a 265-minute outer limit, build their own products, and retain results in `surround-ipad-messages-ui-test-results` and `surround-ios-18-messages-ui-test-results`. Composer gets a 50-minute step limit, like a part, and continuity an independent 45-minute one; adding continuity tests does not consume the composer's budget. The composer/continuity job runs its ten-minute keyboard preflight first and has a 130-minute outer limit, leaving 25 minutes beyond the combined UI step limits for setup, build, and upload. In seven hosted iPadOS 26 runs of November 15–19 the preflight step took 2.6 to 5.3 minutes, its test up to 163 seconds of its former three, and twice the test passed but `xcodebuild` was still finishing when the step's former five minutes ran out. Both main jobs have 185-minute outer limits, and the iPadOS 26 profile job 230. The `minimum-ios-18` job pairs the iOS 18 unit tests with the profile and game control UI tests, reuses the UI derived-data directory for that sequential unit step, and has a 250-minute outer limit. The game control phase takes about nine minutes on a local iPad simulator; on November 18 it took 16 minutes on a hosted iPadOS 26 runner and 13 on iPadOS 18, and the profile jobs, at 1 hour 45 minutes and 1 hour 19, still took less time than the main jobs, at 2 hours 11 minutes and 1 hour 58. Each job builds its own test products. Matrix fail-fast is disabled so a failure on one OS cannot cancel the other OS's composer/continuity coverage.

Each part step, and the Activity, game control, composer and continuity steps, run `xcodebuild` under `.github/ci-tools/supervise-ipad-ui-test-part.py`. At 46 minutes the supervisor interrupts `xcodebuild`'s process group, as Ctrl-C would, so `xcodebuild` can still finish its result bundle inside the 50-minute step. The 50-minute composer step is interrupted at 46 minutes, as the parts are, the 45-minute game control and continuity steps at 41, and the 30-minute Activity step at 26. In four hosted iPadOS 26 runs of November 18–19 the composer step took 32 to 41 minutes, and in one a stalled query left 140 seconds of its former 41, too few to rerun the 300-second test. Those four phases run under the supervisor wherever they run, so a local run also stops at its deadline and can rerun a test; a recovered run says so in its output and keeps the first attempt in `TestResults/<bundle>-Diagnostics`. Interrupting `xcodebuild` alone is not enough: it waits on its app-launch workers and never writes the bundle. A group still running 90 seconds later receives SIGTERM, then SIGKILL 15 seconds after that. A step stopped this way fails with status 124, and the interrupted test is recorded as "Testing was canceled". The deadline counts from the start of the step. In thirteen runs of October 26–28, main's former two parts reached it on both iPadOS versions, which is why main now runs in three (see below). Profile and Messages parts took up to 44 minutes, apart from steps in which a test exceeded its 15-minute allowance; in 7296e1b's run, iPadOS 26 `profile-2` reached the deadline without one, so Profile now runs in three parts too. In November, Messages' two parts reached it with no test failing: iPadOS 26 `messages-1` on November 17, while `xcodebuild` was finishing, and in three attempts of one run on November 19, the last with `messages-2` too, and iPadOS 18 `messages-1` on November 17. On November 16 an iPadOS 26 `messages-1` that had failed a test kept 26 seconds, too few to rerun it. Replayed over eleven Messages jobs of November 16–19, three parts would have put three of the four slowest journeys, all at wide layouts, in part 3, at up to 41 of its 46 minutes, so Messages runs in four: each part's tests take 12–30 minutes at the median and at most 32. A cancelled workflow signals only the step's shell, so the runner's process cleanup, not the supervisor, ends `xcodebuild` then.

When the first attempt fails, `TestResults/<bundle>-Diagnostics/` keeps:

- its console;
- the crash reports written during it (each is described in `status.json`; reports beyond 32 MB in total are listed without being copied);
- the `CoreSimulator.log` lines written during it: every rendering-service recovery line, up to 1 MB of other rendering-service and device-state lines, and the last 4 MB of the rest, without the repeated device-identity errors that make up nearly all of CI's log (`status.json` counts what it leaves out);
- the simulator list;
- a screenshot taken at the deadline;
- `status.json`, with the VM's uptime and the rerun decision.

A rerun that does not pass adds its own console, crash reports and `CoreSimulator.log` lines under a `rerun-` prefix.

The supervisor reruns once, into `<bundle>-Rerun.xcresult`, and only after a hosted simulator crash or a UI query timeout. It needs all of the following:

- every failure is either "Test crashed with signal term" (or kill), or XCTest timing out on one accessibility query: "Failed to resolve query", "Failed to get matching snapshot" or "Failed to get matching snapshots", followed by "Timed out while evaluating UI query.";
- for a crash, a `SimRenderServer` crash report or CoreSimulator's SimRenderingServices recovery appeared during the run;
- no Surround or test-runner crash report did;
- no test exceeded its execution time allowance;
- no more than three tests failed;
- for a query timeout, the app's last idle wait before the failure did not end with XCTest noting that the app never went idle ("App animations complete notification not received" or "App event loop idle notification not received"). In CI, the one query timeout that matched a hang, a continuity test whose same step failed elsewhere with "process main thread busy", came right after such a note; none of ten stall timeouts did. The note also appears in tests that recover, so a later idle wait of the app clears it. The composer phase's keyboard-animation stall prints it too, so a composer timeout right after that stall stays red;
- enough time remains before the deadline, both when the supervisor decides and again once the simulator is ready. A crash, or a test whose duration the console did not report, needs at least five minutes. Query timeouts alone need about 100 seconds of `xcodebuild` overhead plus the time the failed tests ran in the first attempt, until they failed, so a short test can still be rerun near the end of a step. A rerun that overruns is stopped at the deadline, and the step fails as it would have without one.

On hosted runners, accessibility queries sometimes stall in episodes late in a job, and the stall fails whichever test is running. Before a rerun, the supervisor polls `simctl` until the simulator reads Booted, boots it if `xcodebuild` left it Shutdown after a crash, and then waits for `simctl bootstatus` to report that the boot finished. Reading Booted is not enough: after a crash, SpringBoard once refused to launch the test runner ("Busy", "Application failed preflight checks") for a rerun started at Booted. The wait is limited to three minutes and to the time the rerun can spare. A listing or command can run a little past that limit; the supervisor then checks the time again and does not rerun. `boot.log` in the diagnostics folder records the simulator's states and `simctl`'s output during the wait.

Only the failed tests, at most three, run again under the same deadline. The step turns green only when the rerun bundle shows those tests ran and passed. Its warning annotation names the SimRenderServer exception when a crash report was written, CoreSimulator's recovery otherwise, or the query timeout; the first bundle still records the failure. Assertion failures, including those that follow a crash in a slowed simulator, test timeouts, an app main thread that XCTest reports busy ("process main thread busy"), and a query timeout right after the app never went idle are never rerun. An app hang that only makes a query time out, without such a note, cannot be told from a stall, so the warning annotation is worth reading. After changing the supervisor, run `python3 .github/ci-tools/tests/test_supervise_ipad_ui_test_part.py`, which uses fake tools only.

The slow episodes behind the iPadOS 18 Profile overruns hit hardest on screens that keep redrawing. In every compatibility scene but Quick Match's, the fixtures keep at least one Quick Match search and a hosted challenge waiting, so wherever Home is on screen its searching card, and in the New Game scenes New Game's waiting banner, each show a spinner. A spinner redraws the screen about 20 times a second, and the recording Xcode makes of each UI test takes a frame for every redraw. In three iPadOS 18 runs of October 26–28, the custom-game picker test (`testPickerProfileSelectsOpponentWithoutReplacingEditedChallenge`, and the longer test it was split from) ran past its 15-minute allowance. In the two runs whose result bundles were examined, it and the Rengo open-challenges test, both with two spinners on screen, answered queries an order of magnitude more slowly than the tests around them. These screens ran at normal speed in most runs, so the spinners seem to add load to a slow runner rather than cause the slowdown alone. UI tests show these spinners, and Quick Match's, stopped (`SearchSpinner`).

The composer phase retains eleven selected methods, and runs the whole `SuperchatCoverUITests` class too: the moderator cover focuses its reply field on every rise in regular height, so each of its journeys does. Mandatory `testKeyboardPreflightSupportsComposerInput` covers the compact Chat automatic-focus path, exact typed input, and keyboard dismissal; `testCompactChatCanHideAndShowMainBoard` retains the board hide/show journey. The redundant `testCompactChatAutomaticallyFocusesComposer` method is removed. `testPrivateMessageProfileEntriesPreserveConversationDraft` checks that Back from a conversation opened by Profile first returns to Profile, then Profile Back restores the original Messages peer and exact unsent draft.

The two incoming-message journeys set `SURROUND_UI_MESSAGES_REPLAY_HELD=1` and release their offline replies through the test-only Replay incoming toolbar control after recording the exact pre-append reading position and `delivered:0/2` checkpoint. This keeps slow accessibility queries from consuming the fixture's setup window. Unflagged replay timing and screenshot fixtures are unchanged.

The split follows a review of six September 21–25, 2026 CI runs: iPadOS 26 composer reached its old 30-minute step cap twice, before the twelve continuity tests were added. Completed main phases took about 18–37 minutes and profile phases 30–48 minutes, leaving headroom under their existing limits. Composer logs also showed repeated XCTest animation-completion waits, including one passing test lasting over fourteen minutes. The larger budget preserves coverage during those stalls; it does not resolve the underlying stall or assertion failures. In October 2026 hosted runs, composer took about 15–27 minutes and continuity about 13–24, well inside their 41-minute deadline.

The main, Profile, and Messages parts follow a review of October 17–24, 2026 CI runs. Their single 60-minute steps were full or nearly full: the iPadOS 26 Messages suite needed about 63 minutes, and Profile steps took 36–60 minutes. By October 24 the main suite had grown to 183 tests: 58 minutes of test time on iPadOS 26 and 50 on iPadOS 18. Most Messages steps and that day's iPadOS 26 main step reached the limit, and three times xcodebuild was stopped while it was still writing its result bundle, so the artifact upload failed. Without a simulator crash, hosted runs on October 24–25 took 17–34 minutes per part, except iPadOS 26 `main-1` and `main-2`: 39–41 minutes for `main-1` once 3ddae84 added the theme-picker journeys, and up to 42 for `main-2` in a run with failures. Those two leave little room under the 46-minute deadline described above. Their jobs bound the simulator keyboard setup to 10 minutes and each build or unit-test step to 20, and each job limit exceeds the sum of its step limits by five minutes for checkout and upload, so setup cannot cut a test part short.

Main moved to three parts after thirteen CI runs of October 26–28. Its tests took 64–90 minutes on iPadOS 26 and 52–64 on iPadOS 18, apart from one slower iPadOS 18 run whose part 2 reached the deadline with tests left to run. In two parts, that left too little time before the deadline to rerun a failed test: in 6fc5bde's run, iPadOS 26 `main-2` could not rerun a query timeout because 256 seconds remained and the rerun needed 314. In the main and Profile parts of October 26–28, up to 90 seconds passed before a part's first test, and, in parts with a failure, up to 148 seconds after its last before the supervisor decided on a rerun; in that longest case, `xcodebuild` spent 109 seconds writing its result bundle. Replayed over those thirteen runs, the tests of each of main's three parts take 18–26 minutes at the median, so a median part leaves about 17 minutes for a rerun. The slowest replayed part is part 2 of the slow iPadOS 18 run, with at least 35.5 minutes of tests, counting the test still running at the deadline for as long as the log shows it running and the tests the run never reached at its pace; it would leave about six and a half minutes.

Profile moved to three parts after 7296e1b's run, in which iPadOS 26 `profile-1` could not rerun a 626-second query timeout, because 446 seconds remained and the rerun needed 726, and `profile-2` reached the deadline without a hung test. In sixteen runs of October 26–28, Profile's tests took 40–66 minutes on iPadOS 26 and 32–46 on iPadOS 18, apart from three runs in which a test exceeded its allowance, one slower iPadOS 18 run, and 7296e1b's iPadOS 26 run, which needed more than 80. Replayed over the runs without such a test, counting each first attempt and a test that crashed or was still running at the deadline for as long as the log shows it running, the tests of each of Profile's three parts take 12–24 minutes at the median. `profile-2`, which has two of the three slowest tests, is the longest: 23.7 minutes on iPadOS 26 at the median, leaving more than 18 minutes for a rerun, and 35.4 in 7296e1b's run, leaving about six and a half. That run's failed test falls in `profile-3`, which would have left about 15 minutes, enough to rerun it.

The phase selection is centralized in `.github/ci-tools/run-ipad-ui-tests.sh` so the iPadOS 26 and iPadOS 18 lanes cannot drift. Before invoking Xcode, the runner validates each journey class and a nonempty test source, plus every individually selected preflight/composer method. A renamed class or selected method cannot silently execute in the wrong phase or leave a phase empty.

`GameContinuityUITests` runs in the isolated `continuity` phase, after composer tests in CI. Only checks that need compact/regular transitions opt into the Debug-only `--surround-game-layout-transitions` harness, which changes the existing game route between regular width and a 430-point compact layout without changing its identity. These checks cover chat variation and move-preview exits, an ordinary draft and selected channel with active or dismissed keyboard focus, a frozen sharing draft and marked analysis session, and the preferred Forward branch after backing up. The harness changes the production layout inputs while retaining the board and composer in stable layout slots. Its compact top-leading control overlay leaves the native mode buttons exposed; it does not simulate a physical fold or establish system sheet/toolbar adaptation. Rematch sheet retention and native device-pose behavior still require a Device Hub transition check. For that manual check, `--surround-rengo-game` adds generated teammates to the primary offline compatibility game, allowing team details and panel continuity to be exercised without a live game. Normal screenshots are unchanged unless the flag is supplied.

Other continuity checks use the native offline game or Home fixture without the layout harness. They verify that profile/tab navigation and an ordinary-chat Zen round trip retain drafts without automatically reopening the keyboard. The largest Dynamic Type check rotates the native fixture through both regular orientations, verifies that the preview action and square board fit, then uses Return to game and confirms the current board is restored. Explicit Analyze exits are checked in the native regular layout and the harness's compact layout, separately from state-preserving layout transitions.

`GameContinuityUITests/testOwnGameSwitchingKeepsIndependentChatDrafts` opens two generated own correspondence games through Home and the in-game control's popover. It checks exact, independent Chat and Personal drafts across game switches, the main-channel selection and dismissed keyboard on return, and continued editing of a restored draft. The test uses offline fixtures and never submits a message.

`GameContinuityUITests/testBackToHomeAndReopeningOwnGameKeepsChannelDrafts` uses the normal Home route to enter an own game, prepare distinct Chat and Personal drafts, return with Back, and reopen the same game. It checks the exact drafts, main-channel privacy, dismissed focus, and a continued edit across a second Back/reopen. It exercises in-memory draft ownership above the game route while the app stays running, using offline fixtures without submitting a message.

`GameContinuityUITests/testNativePhoneLandscapeLargestTextKeepsBoardAndActionsResponsive` uses a native phone window without the layout harness. It rotates the offline game into landscape at the largest accessibility text size in dark appearance, requires a usable square board and visible action controls, then verifies a responsive Zen round trip with the same board position. Successful and failed geometry checks retain scoped screenshots and accessibility evidence. `GameDetailLayoutTests` also rejects empty board/action slots for the corresponding landscape proposals.

`GameContinuityUITests/testGameDetailFitsAResizedWindowAfterAKeyboardInAnotherTab` turns an iPad from landscape to portrait, raises and dismisses a docked software keyboard on Messages, resizes the window to 375 × 548 and opens the live game from Home's banner. Game Detail's layout frame must end inside the window. During that push, iPadOS 26.5 and 27.0 give the navigation stack's hosts a stale keyboard region taller than the window. Game Detail ignores keyboard regions, so until its host stopped tracking one it was laid out 541 points tall in the 549-point window, with its bottom actions below it. iPadOS 26.1 lays it out normally. The test skips before iPadOS 26, whose app windows do not resize, and when no docked software keyboard appears. On iPadOS 26.5, XCTest's typing raises a docked keyboard even with the simulator's hardware keyboard attached; iOS 27 simulators keep the hardware keyboard, so disable hardware keyboard attachment there first.

`GameDetailLayoutTests` checks square board bounds, active Duo division avoidance, clock pairing, measured action-label fit, portrait Analyze bottom spacing, and compact/regular keyboard composer placement. Native rotation coverage in `GameContinuityUITests` checks retained marked analysis and chat drafts through the toolbar toggles. Geometry tests do not establish Liquid Glass appearance; verify that visually on an iOS 26+ simulator or device.

`GameDetailClockStateTests` checks the read-only display projection for the supported time systems, pre-start and first-move clocks, pauses, sudden death, disconnection snapshots, confirmed scoring marks, and finished results. For native visual review, add `--surround-game-detail-clock-state <state>` to an offline `active-game-board` compatibility launch. Supported states are `byoyomi-main`, `byoyomi-overtime`, `sudden-death`, `fischer`, `canadian-main`, `canadian-overtime`, `simple`, `absolute`, `untimed`, `not-started`, `first-move`, `paused`, `disconnected` (opponent auto-resign countdown), `stone-removal`, `finished-points`, `finished-resignation`, `finished-timeout`, `draw`, `annulled`, and `canceled`, plus `estimate-white`, `estimate-black`, and `estimate-even` for deterministic +3.5 White, +0.5 Black, and tied estimates. These estimate fixtures keep Black’s clock running and leave the authoritative score untouched. This opt-in flag leaves the default screenshot scenes unchanged. `GameContinuityUITests/testEstimateLeadSurvivesChatAndClearsBackToTurn` checks the full clock, the portrait Chat title chip, and restoring the turn status after Clear estimates; its screenshots retain each state for visual review.

The pending-move/pass journey verifies the confirmation can be dismissed without changing the game and that a tentative move survives native rotation with Submit still available. The offline UI transport does not acknowledge game commands; authoritative submission and scoring-recovery behavior is covered by the service/state tests, not inferred from these visual journeys. Playback coverage includes Back to live while checking that editing and sharing controls remain absent.


`GameControlStateTests` drives scoring deadlines, disconnections, and refresh responses without wall-clock waits or live commands. Recovery must never replay a scoring command or unlock from cached overview data; a fresh authoritative game snapshot or live scoring-phase exit unlocks controls, including updates delivered without a manual refresh. Explicit refresh retries start a new bounded recovery episode, while automatic recovery remains coalesced. Toggle confirmations match only the requested intersections so unrelated concurrent markings cannot leave controls waiting. `AppReviewPolicyTests` separately verifies that abandoning move observation releases its pending token without recording success or failure.

CI runs these journeys on both iPadOS 26 and the latest installed iPadOS 18 runtime. To reproduce the minimum-OS lane locally, substitute `18` in the simulator selection commands above. All minimum-OS CI jobs run on `macos-15` and explicitly select Xcode 26.2. The `minimum-ios-18` job retains its unit and profile UI result bundles in the `surround-ios-18-test-results` artifact; the `minimum-ios-18-ui-tests` job retains main UI results in `surround-ios-18-ui-test-results`. The `ipad-composer-ui-tests` matrix stores preflight, composer, and continuity bundles in separate `surround-ipad-26-composer-continuity-test-results` and `surround-ipad-18-composer-continuity-test-results` artifacts.

For keyboard layout failures, match the device model as well as the runtime reported in the result bundle. An 11-inch iPad in landscape can exhaust chat space that remains available on a 13-inch iPad. The variation-sharing Zen round trip verifies that leaving Zen restores the automatically focused composer with its exact draft name, sharing status, and frozen 120-point preview, retaining a screenshot and accessibility hierarchy in that state. Keyboard dismissal remains covered by the separate preflight and composer interaction journeys.

On iOS 27 a SwiftUI `Menu` item wrapped in a `Section` loses its accessibility identifier and value and keeps only its localized label. Separate the groups of such a menu with `Divider()` wherever a test has to resolve an item without knowing the running language: it draws the same separators in the same places and keeps the identifiers on every runtime. The Analyze actions menu does this because the App Store capture runs in fifteen languages and matches on identifiers alone. `SurroundUITests` pins itself to English and resolves a menu item by identifier or, failing that, by the title of an element that has none, which covers both Mac Catalyst's `NSMenuItem` titles and the still-sectioned game actions menu.

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

The wrapper preserves Xcode's exit status and writes raw console output, a bounded simulator log stream, and collector status into a fresh output directory. The first animation-completion warning in any test, or the first app-idle wait exceeding 15 seconds after a Share action, triggers one early screenshot and stack samples of the selected simulator's app and UI-test runner. Collection errors are retained in the status files. When the command finishes, `status.json` also pairs XCTest's in-app animation-idle requests with their replies from the simulator log, per app process, and lists each unanswered request with the UIKit input transitions just before it and the delay until XCTest's next in-app activity; compare that list with the console's animation-completion warning count. Collection does not query the accessibility hierarchy, dismiss the keyboard, or stop the app or runner. The diagnostic example limits each test to four minutes; normal CI allowances remain unchanged.

Use a dedicated simulator when comparing traces, and record its runtime, Xcode version, and keyboard setup. Run at most three isolated attempts initially; if they all pass, run the existing eleven-test composer selection once to check suite-state dependence. The runner's composer phase reruns a crash or query-timeout victim, so look for its `[SurroundCI]` lines or a `-Diagnostics` folder before trusting a pass. Inspect the first captured stall before expanding the run. Passing traces help establish the normal event order but do not demonstrate that an intermittent stall is fixed. Tracing itself can affect timing, so any resulting behavioral fix also needs verification with diagnostics disabled.

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
  --locale en-US \
  --keep-simulators
```

`--locale` is repeatable. When it is omitted, the runner captures all fifteen supported localizations.

The output path must not already exist. Reusable build products default to the gitignored `.build/AppStoreScreenshotDerivedData` directory; pass `--derived-data` only to put that cache elsewhere. The runner:

- uses the pinned iOS 27.0 runtime by default and fails if it is unavailable unless `APP_STORE_IOS_RUNTIME` deliberately selects another installed runtime;
- selects an accepted 6.9-inch iPhone and 13-inch iPad from that runtime as device-type templates without booting or modifying them, then creates fresh disposable simulators for capture;
- pins the status bar for repeatable output;
- runs the selected test-plan configurations (`en-US`, `fr-FR`, `de-DE`, `ja-JP`, `vi-VN`, `th-TH`, `zh-Hans-CN`, `zh-Hant-TW`, `ko-KR`, `es-ES`, `es-MX`, `pt-BR`, and `pt-PT` by default);
- captures nine portrait iPhone scenes, one landscape iPhone themes scene, and ten landscape iPad scenes per locale;
- features Raked Garden in Game Detail for `06-themes` on iPhone (landscape, Zen mode) and `04-themes` on iPad (landscape, default mode, no Chat or Analyze panel, collapsed app sidebar), replacing the former Zen screenshots;
- selects the theme in a separate isolated app launch and returns subsequent scenes to the standard theme;
- captures the approved five-message English conversation and native composer in `11-messages`, replacing iPhone Preferred Settings and iPad Open Challenges while preserving ten sources per family;
- keeps the iPad app sidebar visible except in the themes scene (the Home Screen widget is captured from SpringBoard);
- exports named XCTest attachments and uses Image I/O to bake attachment orientation into the pixel raster;
- writes neutral orientation metadata (`1`) and current pixel dimensions;
- validates screenshot count, ordering, PNG format, dimensions, orientation metadata, and absence of an alpha channel; and
- deletes the disposable simulators during teardown, including after a failed capture, without changing the template simulators, unless `--keep-simulators` retains them for separately reviewed cleanup. The retained devices are shut down, and `simulators.tsv` records their exact UUIDs and names even if capture fails.

The complete fifteen-locale run produces 300 validated PNGs; an English-only run produces 20. Review `index.html` in the output directory before uploading. Final PNGs are in `screenshots/<locale>/iphone-6.9/` and `screenshots/<locale>/ipad-13/`; the result bundle, raw attachments, metadata, and `xcodebuild` log are retained beside them. Promotional framing may use a landscape canvas for the iPhone theme card. The public iPhone family explicitly allows its approved base size and exact transpose in one set; opted-in manifests record and verify dimensions for each image. Other families retain uniform dimensions. Duo publishing uses the separate admitted selected-handoff route; size support alone does not qualify operator-observed captures. See the [tool contract](.github/ci-tools/AppStoreConnectTool/README.md) for its GET-only inspection, offline dry run and exact-digest publishing boundaries.

For a prospective Duo widget diagnostic, explicitly select `AppStoreScreenshotTests/testDuoWidgetQualification` on the owned Closed outer portrait device and opt in with `TEST_RUNNER_SURROUND_DUO_WIDGET_QUALIFICATION=1`. It is separate from the standard capture plan. After seeding the offline fixture, it terminates the app and waits for `.notRunning` before querying SpringBoard; a global Home press can leave Duo's SDK screenshot on an inactive app display. It records all current, stale and unready widget identifiers, checks the current token/locale/expiry, and emits separate Home-transition and readiness signals for independently enumerated native-display diagnostics. These observations can establish prospective fixture readiness, but do not join an AX element to physical native pixels or qualify historical marketing captures. No widget layout or production preferences are changed by the diagnostic.

Selected Duo publishing qualification uses one Asset Library writer and content-based readback of both API views. The GET-only compatibility inspector compares native-size decoded PNG pixels and records a target-specific proof; the source version’s proof cannot supply a new target’s IDs. Focused tool fixtures cover owned partial progress, read-only completed resume, stale views, foreign content and resource drift, partial rollback with surviving originals, and both-view completion before metadata writes. The public publisher’s offline dry run creates no journal or requests. Local fixture success does not establish Apple write propagation or alter historical capture evidence.

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

The new capture has `mode: "scene-refresh"` and a hashed `screenshot-provenance.json`; it explicitly identifies both original result bundles and both iPhone destinations. Every one of its 260 source images is bound to its original device, locale, test attachment and bytes. The full base and fresh aggregate result bundles, raw attachments, source images and source contexts are copied under `origins/`; the base run is never modified. The historical refresh contract retains the former Zen scenes and refreshes one iPhone Quick Match scene per locale: exactly 247 sources must remain byte-identical, and only the thirteen declared replacements may change. The Raked Garden replacement changes both families and the iPhone source orientation, so it requires a new full capture. Arbitrary screenshot mixing is rejected. Source context records permit only the bounded screenshot test/tool and testing guide changes; shipping source changes require a new complete capture instead.

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
| `ms` | `ms-MY` |
| `id` | `id-ID` |

Initialize a private package for a version from the public repository root:

```sh
.github/ci-tools/app-store-release.sh init \
  --version 2.1 \
  --output ../AppStoreReleases/2.1
```

The generated `release.json` references one `localizations/<locale>/whats-new.txt` file for each locale. Fill all fifteen release-note files. A localization may also patch version-scoped `description`, `keywords`, `promotionalText`, `supportUrl`, and `marketingUrl`, or app-wide `name`, `subtitle`, and `privacyPolicyUrl`. Long descriptions and promotional text can use `descriptionFile` and `promotionalTextFile`. The top-level optional `copyright` patches the version-wide value. Omitted fields remain unchanged; an explicit `null` clears only fields whose schema permits clearing. For a locale absent from the released source version, `prepare` requires effective non-empty values for `description`, `keywords`, `supportUrl`, `name`, `subtitle`, and `privacyPolicyUrl`; explicit release-package values take precedence, while values already present in the reviewed target draft are accepted as fallback. The localized name must contain 2–30 characters, and the privacy policy URL must be an absolute HTTP(S) URL. Validation applies Apple's field limits, including the 100-character keyword limit measured conservatively with Swift's UTF-16 view so localized combining marks count the same way as App Store Connect.

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

## Game Detail design fixtures

The manual Game Detail artboard suites opt in with `TEST_RUNNER_SURROUND_ARTBOARD_AUDIT=1`. Their compatibility-mode launches use `--surround-game-detail-design-artboard <1...91>` to select matching players, turns, board positions, clocks, chat, teams, and scoring data. These fixtures use the ordinary Home-to-game navigation route so native navigation controls appear in the captures. The design flag requires both offline UI-testing and compatibility-screenshot mode; App Store screenshot launches reject it and retain their original fixture contract.

`--surround-ui-theme rakedGarden` selects the Raked Garden theme in the isolated offline preferences suite; `nebulaPearl` selects Nebula & Pearl, `surroundStudio` selects Surround Studio, and the Debug-only `frostPine` and `feltMeadow` select Frost & Pine and Felt Meadow. Release builds offer Classic, Studio, Garden and Nebula; a stored Debug-only theme falls back to Classic there. Garden, Studio and Meadow follow the device appearance; Nebula remains dark. Pass `--surround-ui-appearance light` or `--surround-ui-appearance dark` for deterministic adaptive-theme fixtures, or omit it to test live device-appearance changes. Their daytime phone and iPad audits explicitly select light appearance. Focused theme audits keep the same artboard fixtures and Home-to-game route:

- `GameDetailIPadArtboardAuditTests/testRakedGardenThemeOrientations` captures Play through native landscape/portrait rotation and Home after Back; `testRakedGardenThemePanels` captures Chat, Analyze and Zen in both orientations.
- `ArtboardPhoneAuditTests/testRakedGardenThemeStates` captures Play, Chat, Analyze and Zen in both full-size phone orientations; `testRakedGardenThemeScoring` captures stone removal and score details. Run `testRakedGardenThemeSmallPhone` on an SE-size simulator for the smaller Play, Analyze and scoring fixtures.
- `GameDetailDuoArtboardAuditTests/testRakedGardenThemeStates` checks the pose selected with `TEST_RUNNER_SURROUND_DUO_POSE=closed-portrait|closed-landscape|book-wide|open-wide|book-tall`. Set the physical Simulator pose first. The test uses the existing geometry and selected-branch assertions and does not change the fold pose; verify the active-display host captures for Book/Open.

Each Raked Garden audit above also has `testSurroundStudioTheme…` and `testFeltMeadowTheme…` counterparts that reuse the same geometry and continuity checks. Theme attachments have a `raked-garden`, `surround-studio` or `felt-meadow` suffix so visual review can distinguish them from standard-theme artboards. A passing geometry audit still requires visual inspection of textures, controls, stones, small board marks and score overlays.

People choose the theme in Settings › Appearance, a game's Options sheet, or Home's Appearance popover, which also holds the Compact/Large display mode. Settings also chooses where it applies: Whole app (the default), where Home, Settings, Public games and Game history wear it as well, or Games only, where they stay Classic. On the whole app a dark-only theme such as Nebula & Pearl also holds the window dark, so screens that do not wear themes yet, sheets and bars turn dark too. `ThemedScreensUITests` captures Public games and Game history in Raked Garden, Nebula & Pearl and Classic for review, and measures Messages dark with Nebula & Pearl on the whole app and light with Games only; it sets the Simulator to Light Mode and restores it. Add `--surround-ui-theme-games-only` to start on Games only. `ThemePickerUITests` covers the three pickers, Debug-only themes and the scope choice on the compact iPhone layout. Each tile's preview square is hidden from VoiceOver but carries a `theme.preview.<theme>` identifier, which XCTest still lists; the tests check that every preview fills its column, so a host shorter than the picker must scroll it rather than squeeze some tiles more than others. `--surround-ui-appearance-popover-height 360` (Debug offline launches only) caps Home's Appearance popover near the height an iPhone in landscape gives it, about 370 pt; `testHomeAppearanceKeepsTileSizeInShortPopover` checks that the options scroll there. A real landscape run is still worth doing by hand. At xxLarge text and above the picker uses three columns, and two at accessibility sizes. The iPad case opens the popover in landscape, at xxxLarge and accessibility text sizes, and in portrait. The popover hangs from the Appearance button itself. On iOS 26 and later it grows from the button without an arrow; earlier systems point an arrow at it. Every opening checks that it sits across from the button and starts between 20 pt above the button's top and 12 pt below its bottom, which a popover hanging below the large title fails, and that the bar shows Appearance and no More menu. The popover depends on that: a bar that folded Appearance into a More menu would open it at the top left. Home's bar holds only the account menu and Appearance, and `testHomeBarNeverFoldsAppearance` checks that it shows the button and no More menu: at the largest text size, right to left, at the top of Home and, where it has more than fits, scrolled, and on iPad in both orientations and in the native 375 × 548 window. Run it with `TEST_RUNNER_SURROUND_UI_LANGUAGE` set to a long language such as `de` after changing Home's bar or tab labels. Keep other actions out of Home's bar. The iPhone and iPad landscape cases reopen the popover after visiting a game and coming Back, and the iPad case turns to portrait and back while the app runs, and once more with the popover open. It first restores a full-size window if an earlier run left one resized.

The pickers show thumbnails from `Assets.xcassets/ThemePreviews`, rendered from the app's own `ThemeLivePreview`, so opening one never decodes every theme's full-size art. After changing a theme's scene, board or stones, or adding a theme, regenerate them: launch a Debug build on an iOS Simulator with `--surround-ui-testing --surround-theme-preview-export`, wait for `Documents/ThemePreviews/done` in the app's data container, then run `.github/ci-tools/update-theme-previews.py` with that folder. A theme without a thumbnail falls back to the live preview, and `SurroundThemeTests/testEveryThemeHasPickerThumbnails` fails until it has one. After changing the script, run `python3 .github/ci-tools/tests/test_update_theme_previews.py`.

Debug-only themes keep their art and thumbnails in `Surround/DebugThemes.xcassets`, which the Release and Beta Release configurations exclude, so shipping builds carry only the released themes' art. Debug builds and `SurroundTests` compile both catalogs. The script puts a Debug-only theme's thumbnail there, following the `themes.json` the export writes. To release a theme, add it to `SurroundTheme.released` and move its art folder and thumbnail imageset into `Assets.xcassets`; `SurroundThemeTests/testOnlyReleasedThemesShipTheirArt` fails while any theme's art is in the wrong catalog.

Flowing Ink is a Debug-only family with one picker tile and four stored mode IDs: `flowingInk` (monochrome with background), `flowingInkJade` (color with background), `flowingInkJadePlain` (color without background), and `flowingInkPlain` (monochrome without background). The Game Detail `paintbrush.pointed` button appears only while Flowing Ink is selected and animates the cycle in that order (without animation when Reduce Motion is enabled). Choosing the picker tile from another theme enters at `flowingInk`. The modes follow the selected system/app appearance. Light uses white boards for monochrome, pale jade with the color landscape, and wooden yellow for color without background. The wooden mode also uses warm paper, brown controls and matching panels. Dark uses charcoal landscapes and subdued gray, jade or warm wood boards, with coordinated surfaces. Stones, clocks, player chips and action controls retain flat fills. Each mode accepts `--surround-ui-theme`; `--surround-ui-appearance light|dark` explicitly overrides the fixture appearance. `ThemePickerUITests/testFlowingInkToolbarCyclesAndRetainsTheSelectedVariant` checks family-only toolbar visibility, cycling and navigation continuity. For a short host-recorded transition clip, set `TEST_RUNNER_SURROUND_FLOWING_INK_TRANSITION_RECORDING=1` and record between its `[RecordStart] flowing-ink-cycle` and `[RecordStop] flowing-ink-cycle` markers. `ArtboardPhoneAuditTests/testFlowingInkThemeStates` captures Light Play, Chat, Analyze and Zen in both orientations; `testFlowingInkNightThemeStates` repeats them in jade using the device's Dark appearance, without a fixture override, and restores the device afterward. The phone `testFlowingInkControlStates` and `testFlowingInkJadeControlStates` selectors, plus their `Night` counterparts, capture urgent, disconnected, undo, agreement, estimated-score and header clocks and scoring details in both palettes. `testFlowingInkBoardMarkerGallery` and `testFlowingInkJadeNightBoardMarkerGallery` capture the four core/interaction panels at 20, 13 and 7 pt. Use the native marker export below with all four stored IDs to cover both plain and artwork variants at both display scales. Plain modes keep the app-wide card surfaces; only the painting is hidden. `ThemePickerUITests/testFlowingInkPlainModesKeepTheWholeAppTheme` checks both plain modes in Light/Dark through Home, History, Public and Settings.

`GameDetailIPadArtboardAuditTests/testFlowingInkJadeThemeOrientations` and `testFlowingInkJadeThemePanels` cover Light iPad layouts; `testFlowingInkNightThemeOrientations` and `testFlowingInkNightThemePanels` cover Dark monochrome. Run `testFlowingInkThemeNarrowWindow` (375 × 548) and `testFlowingInkThemeTallWindow` (375 × 1000) separately; both restore the native full-size window afterward. `testFlowingInkDarkHomeIconSurfaces` checks that the conditional-move control is visible and hittable in both Dark palettes, then captures its icon on the white clock surface for contrast review. `GameDetailDuoArtboardAuditTests/testFlowingInkThemeStates` and `testFlowingInkJadeNightThemeStates` use the same operator-selected physical pose contract as the other Duo audits. `testFlowingInkPhysicalFoldRetainsAnalysis` starts in Closed portrait, steps back from the fixture seed to a nondefault variation, then the host selects Open, Partially Open and Closed on its `[FlowingInkFoldReady]` markers without relaunching. It checks the exact retained variation and working Previous → Next after each physical transition. This focused journey does not claim a twelve-pose/rotation sweep. Artwork uses uniformly scaled corner plates, so review the waterfall and pine on phone portrait/landscape, a square picker tile, narrow iPad windows and Duo poses. The theme tests check all modes' small-board contrast, plain-mode surface semantics, adaptive surface readability, native flat stones and the actual clock outline at header/compact/full sizes and 2×/3×, an explicit Light override inside a dark environment, and scene proportions/landmark retention. For the native Increase Contrast check, record the current `simctl ui <device> increase_contrast` value, enable it for representative ordinary/header/score clocks, then restore the original value. The single family preview includes Light and Dark thumbnails.

With Whole app, Home wears the same theme as Game Detail. For a visual check of Home's rows, add `--surround-home-states` to a plain offline launch (`--surround-ui-testing`, without compatibility mode). It adds games on low time, paused for the weekend, in stone removal, without an OGS speed tag, and with an unknown clock system, one of them awaiting the user's acceptance of stone removal. `--surround-home-finished-only` shows Home with no active games and one finished game. Compare them in Compact and Large display modes, with and without a theme. At 120 pt, boards draw the theme's flat colors; Large tiles keep boards at 266 pt or more, so they draw detailed stones and theme art.

For Activity and notices work, add `--surround-activity-state <state>` to a plain offline launch (`--surround-ui-testing`, without compatibility or App Store mode). Game 26268404 stays the user's own game. Around it, the launch shows one fixed set of games, challenges, searches and conversations: `nothing-waiting`, `live-your-move`, `live-their-move`, `low-time`, `low-time-crossing`, `stone-removal`, `game-started`, `game-started-correspondence`, `challenge-received`, `unusual-challenge`, `searching`, `waiting`, `correspondence-your-move`, `nothing-leads`, `several`, `superchat`, `rematch-offered`, `rematch-both-asked` or `unusual-rematch`. Every time is a fixed offset from the launch second, and nothing ticks. `--surround-activity-clock running` lets time pass from there, and `--surround-fixture-clock-ticks` then moves the clocks too. `low-time-crossing` leaves the user 0:12 in the last period of a live game, so their clock falls below 10 seconds 2 s after launch; it needs both flags, and the app stops at launch without them. In `stone-removal` the opponent has accepted a removal of no stones and the user hasn't, so the game offers Accept. `game-started-correspondence` is `game-started` with game 26268404 a correspondence game. Captures and the App Review presentation ignore the state. The app stops at launch if the state is combined with a flag that rewrites the same data (Home states, finished-only, the live-game banner and widget routing journeys, or the Messages content flags), or with `--surround-fixture-clock-ticks` on a frozen clock. `ActivityFixturesTests` lists what each state shows.

`--surround-activity-open sheet` (Debug) opens the Activity list once at launch, as a sheet over the offline root, on iPad too; `game-popover` opens game 26268404 and then its in-game control's popover, which Game Detail presents from the control. `--surround-activity-actions succeed` (Debug) makes the offline service answer Accept, Reject and Withdraw itself, 0.35 s after each is sent, instead of failing at once: an accepted challenge starts an active game whose id is the challenge's plus 900000, live or correspondence as the challenge is, and a rejected or withdrawn challenge leaves its list. With `fail-once`, each challenge's first action fails and later ones succeed. A Quick Match withdraw still goes to the offline socket, which never confirms it, so it fails after 8 s. Both flags need an Activity state, and the app stops at launch without one or with a malformed value. `ActivityListUITests` holds the list's journeys: each opener, the rows' actions and their results in place, offline dimming, and popovers that stay when their opener goes. At regular width every real opener shows a popover, so the journeys find the list by `activity.list` and check the style only where it is the point; the Searching card's popover journey runs on iPad only. `ActivityConversationUITests` holds the Messages button's journeys, a draft typed in the list that Messages keeps, and friend request results that keep their place in Messages' inbox until it goes off screen. The simulator has no VoiceOver, so neither class checks where focus moves. CI runs both classes in the `activity` phase, a step of its own in each Messages job. Together they take about six and a half minutes on a local iPad simulator, and hosted runners take about twice as long; in seven runs of November 5–10, iPadOS 26 `messages-2` already took 33–45 minutes of its 46, and on November 9–10 the composer step took 19–27 of its 41, before the moderator cover's journeys joined it.

`--surround-activity-state superchat` starts covered by the moderator cover in every window. The state starts WardenKestrel's superchat once per launch, so a window opened after Done stays uncovered. With an Activity state, `--surround-activity-connection offline` starts its socket down (`.reconnecting`); `online` is the default. In every offline run except captures and the App Review presentation, with or without an Activity state, Debug commands stand in for OGS, and every window's service hears each one. Post them with `xcrun simctl spawn <device> notifyutil -p com.honganhkhoa.Surround.debug.superchat.<command>`, from a UI test through the Darwin notify center, or from the Superchat (Debug) menu on the Mac and in the iPadOS menu bar, whose disabled Covered or Not covered line reads the app's superchat store. The commands are `start` and `end` for WardenKestrel; `start-second` and `end-second` for SentinelHeron, a second moderator with no profile or history; `echo`, the moderator's own copy, which never covers; and `reconnect`, after which every window's socket authenticates again and OGS confirms it without a re-send, so the cover lifts once the 10 s re-send window passes. Two connection commands, `com.honganhkhoa.Surround.debug.connection.drop` and `com.honganhkhoa.Surround.debug.connection.restore`, are posted the same way: every window's socket goes to `.reconnecting`, as when the connection is lost, which freezes its games' clocks, and back; each logs `CONNECTION-DEBUG <name> services=<count>`. For a device or the Mac, where `notifyutil` may not reach the app, `--surround-superchat-debug-script start@0,end@30,…` runs the commands at those seconds after launch; a malformed script stops the launch. Each command logs a `SUPERCHAT-DEBUG` line, and the cover's window logs lines that start with `NOTICES-COVER`, under subsystem `com.honganhkhoa.Surround`, categories `SuperchatDebug` and `NoticesCover`. XCTest still lists the elements under the cover, so UI tests assert that they aren't hittable. `SuperchatCoverUITests` holds the cover's journeys; on the Mac, those that post commands, turn the device or open links skip. Its link journeys hand a link to the running app with `XCUIDevice.shared.system.open`: `XCUIApplication.open` terminates the app and launches it again with the link, so the link would reach a fresh process. Its seven presentation journeys raise the cover over a sheet, a popover, an alert, a confirmation dialog, a context menu, the share sheet and a Safari view, and run only with `TEST_RUNNER_SURROUND_UI_SUPERCHAT_PRESENTATIONS=1`, because the share sheet and the Safari view are system UI that hosted simulators may draw differently. `testLargestTextLandscapeFits` launches offline at the largest text size and measures the cover by frames in landscape and portrait: the header with Reconnecting… under its title, and the end card with Done under its line. After changing the cover's wording, run that journey alone with `TEST_RUNNER_SURROUND_UI_LANGUAGE` set to a long language such as `fr`; the class's other journeys check English text. With `TEST_RUNNER_SURROUND_UI_SUPERCHAT_MIDWAY=1`, `testOwnGameNavigationAndSwitchingRemainResponsive` raises the cover over the open game after half its cycles, checks that the board underneath isn't hittable, ends the superchat, taps Done and finishes the remaining cycles; without it the journey is unchanged.

The in-game control's journeys use the live-game banner fixture (`--surround-live-game-banner-navigation`), in which game 26268404 is a live game on your move, so Home's correspondence games 26268398 and 26268399 show it as the control's chip, with its mini board and clock, and finished game 26268397 is in Game history. With the fixture, `--surround-fixture-clock-ticks` also gives both players of 26268404 30 minutes before the clocks tick. `--surround-game-control-cycle` (see the own-game freeze regression) and `--surround-live-game-banner-conditional-moves` need the fixture in a UI-testing launch, and the app stops at launch without it or with a malformed value. The conditional-moves flag adds the capture fixture's game 62050416, a correspondence game on the opponent's move with three conditional branches, so its bar has the chip beside three modes. In `SurroundJourneyUITestCase`, `openGameControlPopover(in:)` opens the control's popover as a person does: with `holdGameControl(_:)`, a one-second press at the control's centre that doesn't wait for the control to be hittable, since iOS 27 can leave the hidden tab bar's frame over a bottom-bar item; with a click on the Mac's native item; or with the control's item in the bar's More menu. A hold that opens nothing is tried once more, and each retry is kept as an attachment named "Game control hold retried", so a run's retries can be counted. `windowFrame(in:)` is the app's window where the screen has it, the space every element's frame is in: in a resized iPad window the application element keeps the window's size at the screen's origin, so checks that something is on screen measure the window. `launchApp(…, language:)` gives a journey its own language, such as `fr`, in place of English or `SURROUND_UI_LANGUAGE`'s.

`GameControlUITests` holds the control's journeys: the form it takes in a game's bars and in Zen, what a tap and a touch and hold do, where a switch goes, what the popover holds, and where a game says that its connection is down. The chip's tap switches games, so journeys that want the popover from it hold it, and the forms whose tap opens the popover are tapped. A game hides the tab bar, so `testTheChipSwitchesInPlaceOnHomesRoute` reaches Home from the public game's popover: Activity's correspondence row opens the most urgent correspondence game on Home's route and resets no stack, the chip there switches in place, and Public games still shows its game. `testTheIPadProfileSheetsChipClosesTheSheet` opens the finished game from the own profile's Game history in the iPad's account sheet, since an own profile lists no active games; its chip goes through Home, which closes the sheet. `testTheControlNeverHidesAnalyzeOrChat` opens the conditional-moves game in French, at the largest text size, with Flowing Ink, which adds an item of its own to the bars. At that size the chip in a phone's portrait bottom bar is 160 points from 402 points wide, 120 from 375 to 402 beside three modes and 44 below, and 96 in top bars; the journey checks that frame, that nothing folds into More, and that Analyze and Chat each open their panel from the bar, then repeats it in the landscape top bar. `testCantReachOGSOffersRetry` waits up to 40 s for the capsule's words to change, 30 s into the outage. `testADropAndRestoreMovesTheStatus` posts the connection commands with `post(_:)`, as the cover's journeys post the superchat commands, and times what follows: the capsule must not show before 1.5 s, as the window's status waits 2 s, and the to-move clock's mark must show within 2 s; both delays are kept as attachments. Phones run 17 of the 19 journeys, skipping the account sheet's and the Mac's; iPads run 17, skipping the rotation journey, since an iPad keeps its bar when it turns, and the Mac's. The Mac, signed and under Automation Mode, runs only `testTheMacsControlOpensThePopover` and the Zen journey; the others skip with a reason. The class takes about nine minutes on a local iPhone or iPad simulator, and took 13 to 16 minutes on hosted iPads on November 18. CI runs it in each profile job's `game-control` phase, and two of its journeys, with the bottom bar's order and the own-game freeze regression, in the iPhone lane's game control step.

Felt Meadow's clocks and player chips share an opaque wool surface in Home and Game Detail. `ArtboardPhoneAuditTests/testFeltMeadowHomeCompact`, `testFeltMeadowHomeLarge`, and their `testFeltMeadowNightHome…` counterparts capture low-time, paused, scoring, and unknown-clock fixtures through the display mode in Home's real Appearance popover. Inspect the fibers, names, warning colors, and turn outlines alongside the Game Detail theme audits. `SurroundThemeTests/testFeltControlMaterialKeepsTextReadableAcrossSizesAndAppearances` checks native rendered pixel extremes under the text at Home/header/full-card sizes, plus the broad light/dark fiber contrast so the texture stays noticeable. It also checks the solid material used with Reduce Transparency or Increase Contrast. Loose edge fibers follow the original stone alpha and each control’s rounded outline. `testFeltStoneFibersFollowSourceAlphaAndStayStableWhileResizing` checks attached, bounded strands; `testFeltControlFringeIsVisibleOutsideTheBodyAndAbsentInFallback` and `testFeltStoneFringeDisappearsBelowDetailThresholdAndWithoutShadows` verify native fringe pixels and their solid fallbacks. Inspect sparse tufts along the silhouette, with no floating hairs, uniform halo, clipping, or shifted markers.

Frost & Pine uses the same opt-in audits with `--surround-ui-theme frostPine`: `ArtboardPhoneAuditTests/testFrostPineThemeStates`, `testFrostPineThemeScoring`, and `testFrostPineThemeSmallPhone`, plus their `testFrostPineNightTheme…` counterparts. `testFrostPineBoardMarkerGallery` captures 20, 13 and 7 pt cells in both appearances. iPad has `testFrostPineThemeOrientations`, `testFrostPineThemePanels`, their night counterparts, and `testFrostPineThemeNarrowWindow`. Duo has `testFrostPineThemeStates` using the same operator-selected physical pose contract. Attachments use `frost-pine` suffixes. Inspect pale ice boundaries, native markers and fixed scene anchors as well as geometry and retained state. `SurroundUITests/testFrostPineBoardDepthKeepsMovesAligned` uses the shared board-depth interaction audit for Frost & Pine in both appearances.

`ArtboardPhoneAuditTests/testFrostPineControlInteractions` checks full and inline Frost clock details plus avatar and name profile navigation, retaining the board position after returning. Its four screenshots supplement the day/night material audits; passing taps alone do not establish snow or text readability.

Garden additionally has these night/appearance selectors (prefix with `SurroundUITests/` for `-only-testing:`):

- `ArtboardPhoneAuditTests/testRakedGardenNightThemeStates`: fixed dark Play, Chat, Analyze and Zen in both full-size phone orientations.
- `ArtboardPhoneAuditTests/testRakedGardenNightThemeScoring`: fixed dark stone removal and score details.
- `ArtboardPhoneAuditTests/testRakedGardenNightThemeSmallPhone`: fixed dark SE-size Play, Analyze and scoring.
- `GameDetailIPadArtboardAuditTests/testRakedGardenThemeAppearanceContinuity`: no fixed appearance override. Keeps Play mounted through day-to-night and native rotation, then retains the selected Analyze branch through night-to-day and returns to Home. It first confirms that Home follows a live appearance change, then checks rendered board brightness as well as position, clocks, selection and board geometry, and restores the original device appearance/orientation even after a failure. `XCUIDevice.appearance` reports a requested style even when the Simulator does not apply it: throughout a newly created device's first boot (seen on iOS 26.5 and 27.2), every request times out and Home stays unchanged. Boot such a device once and restart it before running this audit.

Studio uses the same bounded fixture routes, with these additional selectors:

- `ArtboardPhoneAuditTests/testSurroundStudioNightThemeStates`: eight fixed-dark captures covering Play, Chat, Analyze and Zen in both full-size phone orientations.
- `ArtboardPhoneAuditTests/testSurroundStudioNightThemeScoring`: two fixed-dark captures for stone removal and score details.
- `ArtboardPhoneAuditTests/testSurroundStudioNightThemeSmallPhone`: three fixed-dark SE-size captures for Play, Analyze and scoring.
- `ArtboardPhoneAuditTests/testSurroundStudioNightThemeControlStates`: three fixed-dark captures for both urgent clocks and disconnected scoring with disabled Accept.
- `ArtboardPhoneAuditTests/testSurroundStudioNightBoardMarkerGallery`: twelve fixed-dark offline gallery captures (four core/interaction panels at each of 20, 13 and 7 pt cells) on a full-size phone in portrait. The same marker samples cover detailed stones and both compact solid-board sizes. Pixel assertions verify that both page and board actually use the dark palette.
- `GameDetailIPadArtboardAuditTests/testSurroundStudioThemeAppearanceContinuity`: no fixed appearance override. Reuses the Garden device getter, Home, rendered-brightness and game-state checks. Keeps one Play game mounted through five panel states in day and five in night, rotates it in night, then retains a selected Analyze branch through night-to-day and returns to Home. Fourteen captures cover the sequence. The app must be foreground for the rendered-board checks; teardown restores the original device appearance and orientation.

Night phone attachments use `raked-garden-night` or `surround-studio-night`; iPad continuity attachments identify day/night explicitly. Inspect the actual rendered transition after caches are warm, not only attachment names or state assertions. Nominal palette tests do not measure composited glass, every texture pixel, or native antialiasing. Night selectors do not change the physical Duo pose.

Check the executed test count as well as the exit status. On the iOS 18.6 SE runtime, the Studio small-phone selector without parentheses returned success with zero tests. The quoted argument `'-only-testing:SurroundUITests/ArtboardPhoneAuditTests/testSurroundStudioNightThemeSmallPhone()'` selected and passed the test.

Felt Meadow uses the same fixture helpers. Its phone selectors are `testFeltMeadowThemeStates`, `testFeltMeadowThemeScoring`, `testFeltMeadowThemeSmallPhone`, and `testFeltMeadowThemeControlStates`; each also has a `testFeltMeadowNight…` counterpart. `testFeltMeadowBoardMarkerGallery` and `testFeltMeadowNightBoardMarkerGallery` capture 20, 13 and 7 pt cells and check the rendered page/board palette. The iPad suite adds day/night `testFeltMeadowThemeOrientations` and `testFeltMeadowThemePanels`, plus `testFeltMeadowThemeNarrowWindow` for the native 375 × 548 window. Both phone and iPad expose `testFeltMeadowThemePanelTransitions`; Duo exposes day/night `testFeltMeadowThemeStates` for the selected physical pose. Day/night unit coverage in `SurroundThemeTests` checks compact marker contrast, control roles, artwork alpha footprints and stitched-grid bounds; the stitch overlay is detailed-only at cells of 14 pt and above.

For a focused full-size phone run, add these selectors to the normal UI-test command with `TEST_RUNNER_SURROUND_ARTBOARD_AUDIT=1`:

```sh
'-only-testing:SurroundUITests/ArtboardPhoneAuditTests/testFeltMeadowThemeStates()' \
'-only-testing:SurroundUITests/ArtboardPhoneAuditTests/testFeltMeadowThemeScoring()' \
'-only-testing:SurroundUITests/ArtboardPhoneAuditTests/testFeltMeadowNightThemeStates()' \
'-only-testing:SurroundUITests/ArtboardPhoneAuditTests/testFeltMeadowBoardMarkerGallery()' \
'-only-testing:SurroundUITests/ArtboardPhoneAuditTests/testFeltMeadowNightBoardMarkerGallery()'
```

Night Garden follows system appearance with `--surround-ui-theme nightGarden`. Use `--surround-ui-appearance light` or `dark` for deterministic captures. The Light board is finely etched sage glass with a thin bronze edge; Dark reduces the same scene, board and crystal lighting without changing their geometry. Its phone selectors are `testNightGardenThemeStates`, `testNightGardenThemeScoring`, `testNightGardenThemeControlStates`, `testNightGardenThemePanelTransitions`, and `testNightGardenBoardMarkerGallery` in `ArtboardPhoneAuditTests`. The scoring, transition and marker selectors also have `testNightGardenNight…` counterparts. The marker audit captures native 20, 13 and 7 pt cells in both appearances. Both phone panel-transition tests use the real device appearance, omit the fixture appearance override, and restore the previous appearance afterward. Run `testNightGardenThemeSmallPhone` separately on an SE-size simulator. `GameDetailIPadArtboardAuditTests` adds `testNightGardenThemeOrientations`, `testNightGardenThemePanels`, `testNightGardenThemePanelTransitions` and `testNightGardenThemeNarrowWindow`, plus Dark panel and transition counterparts. Run the narrow-window selector last, in a separate invocation, because iPadOS remembers window bounds. If restoration fails, restore Full Screen through the native window controls and rerun. `GameDetailDuoArtboardAuditTests/testNightGardenThemeStates` and `testNightGardenNightThemeStates` use the operator-selected physical pose, with the same prerequisite above. Attachments use `night-garden` and `night-garden-night` suffixes. Inspect scene anchors during panel transitions, crystal silhouettes, the thin edge, marker casings and solid compact boards. `SurroundThemeTests` covers both palettes, readable controls and role colors, Light/Dark scene grading, opaque scene/board assets, equal centered stone alpha footprints, and compact marker contrast for every registered theme.

Christmas Keepsakes is Debug-only and follows system appearance with `--surround-ui-theme christmasKeepsakes`; use `--surround-ui-appearance light` or `dark` for deterministic captures. In `ArtboardPhoneAuditTests`, `testChristmasKeepsakesThemeStates` covers Play, Chat, Analyze and Zen in portrait and landscape, `testChristmasKeepsakesThemeScoring` covers scoring, and `testChristmasKeepsakesThemeControlStates` covers urgent and disconnected clocks. Each has a `testChristmasKeepsakesNightTheme…` counterpart. `testChristmasKeepsakesThemePanelTransitions` and `testChristmasKeepsakesNightThemePanelTransitions` retain one game through Play → Chat → Play → Analyze → Play in both orientations, using real device appearance with no fixture override and restoring it afterward. `testChristmasKeepsakesBoardMarkerGallery` and `testChristmasKeepsakesNightBoardMarkerGallery` capture the four native marker panels at 20, 13 and 7 pt; inspect cranberry/ivory silhouettes, restrained glass reflections, the fine dark-pine grid and every marker casing. Run `testChristmasKeepsakesThemeSmallPhone` separately on an SE-size simulator. In `GameDetailIPadArtboardAuditTests`, use `testChristmasKeepsakesThemeOrientations` and `testChristmasKeepsakesNightThemeOrientations`, both `testChristmasKeepsakesThemePanels` and `testChristmasKeepsakesNightThemePanels`, then `testChristmasKeepsakesThemeNarrowWindow` in a separate final invocation. In `GameDetailDuoArtboardAuditTests`, run `testChristmasKeepsakesThemeStates` and `testChristmasKeepsakesNightThemeStates` once per operator-selected pose using the same prerequisite above. `testChristmasKeepsakesNightBackgroundComposition` keeps the selected Analyze variation through native sidebar opening/closing and portrait rotation, checking the stationary landscape board and capturing all four states. The Winter Window scene integrates evergreen branches, berries and burgundy ribbon along the frosted upper-left window sill, with contact shadows baked into the room background and quiet wood grain around the board. Larger viewports reveal more of that scene at its established material scale. Gifts, their contact/cast shadows and the window are integrated into four opaque room photographs. The selected photograph depends only on viewport shape/size, with compact compositions for a short side at most 560 pt or width at least 1.8 times height. Bottom-leading cropping and a reference-height cap preserve the window on short screens; larger viewports reveal additional art at the established scale until coverage requires enlargement. Game Detail on an undivided phone opts into a wide compact-landscape crop that reveals more frosted glass by moving the photograph down by up to 12% of the viewport height, capped to retain full coverage. The reveal eases in between aspect ratios 1.5 and 1.75; narrower landscape poses such as closed Duo keep their crop even when no division intersects the viewport. Its scale and material-light coordinates stay fixed; gift bases may be partly cut off. Portrait, divided displays, iPad, Home and picker previews retain the default crop. Panels, board geometry, toolbar visibility and Zen never reposition or resize the room. Rotation may select another composition. Inspect recognizable default Play gifts, a clear tabletop gap from the landscape window, matching focus/light, and continuous edge fading across wood and gifts. Partial content coverage or viewport cropping is acceptable. Compare exposed artwork across retained-game panel transitions and normal/Zen captures, plus short portrait and wide windows. The native board remains muted pine enamel with a dark-pine grid and slim champagne edge in both appearances. Focused room tests cover composition selection, finite full coverage, bottom-left anchoring, stable scale, short/wide window retention, and four distinct opaque square assets. `SurroundThemeTests` covers both palettes, control and role contrast, centered glass assets, opaque board/room assets; the shared compact-board and sound tests include this theme automatically. Its artwork, thumbnails and sound banks stay in `DebugThemes.xcassets`.

A standing Christmas tree peeks through the right scene edge, with tiered boughs and vertically hanging ornaments; its trunk and lower cut edge remain offscreen. The transparent portrait artwork preserves its aspect ratio, caps its physical size on larger screens and uses only viewport geometry, so panels and Zen do not move it. It shares the room's appearance grade and sits below the existing light, edge fades and all game content, with no tabletop contact shadow. Inspect its upright silhouette, narrow reach and readable ornaments at logical phone size, after rotation and on iPad; it must not read as a branch lying on the table. `testChristmasKeepsakesTreeKeepsBoundedAspectAndViewportEdge` covers proportions, bounded reach, rotation, larger windows and invalid geometry. `testChristmasKeepsakesTreeAssetIsCachedAndTransparent` checks cached portrait artwork, transparent room openings and visible boughs within the native crop. Refresh native theme-picker thumbnails when this scene artwork changes.

Winter Window uses one stationary upper-left daylight field across the tabletop, gifts and material surfaces. Inspect the directional transition and deeper lower/right wood at native scale in both appearances, including Play, Chat, Analyze and Zen. Sparse, partial frost-crystal shadows should be discernible within the light without becoming crisp decorative stamps. The room field keeps its established square scene coordinates independently of the photograph crop and fades beneath top chrome. Clock, identity, Chat and Analyze backgrounds sample the same scene coordinates beneath their labels; stronger room shading never washes over text. Cranberry and ivory glass have separate shade caps, and legacy pigment cards use a lower light cap. Main and miniature boards naturally occlude this background lighting, so compact boards retain solid rendering. Increase Contrast and Reduce Transparency suppress both room and material illumination. The focused lighting regressions compare differently positioned surface crops across all profiles and both appearances, verify opaque board/stone preservation with a wrong-layer positive control, and test the accessibility policy. Board pigment, stone centers, compact stones and alpha remain exact. Detailed stone shoulders allow at most two RGB byte levels with a weighted error budget of 0.005 per shoulder pixel; any changed slab also requires an exact untinted control, and the wrong-layer control must exceed that local allowance. Check visual continuity and readability separately in native captures. The original background safe-area behavior is retained; card illumination requires the Game Detail context, while native theme previews include the illuminated room.

Paper Blossoms is Debug-only (`--surround-ui-theme paperBlossoms`) and follows the selected appearance. Its rice-paper board keeps a straight native vermilion grid and image-based ink/ivory folded stones at detailed sizes; boards below 14 pt cells use solid colors. `ArtboardPhoneAuditTests/testPaperBlossomsThemeStates` and its `Night` counterpart capture Play, Chat, Analyze and Zen in both orientations; the same suite has scoring, control-state, small-phone, panel-transition and day/night marker-gallery selectors. iPad offers `testPaperBlossomsThemeOrientations`, day/night `testPaperBlossomsThemePanels`, and native narrow/tall-window selectors that restore the full window. Duo offers day/night `testPaperBlossomsThemeStates` using the physical-pose contract above. Inspect the paper garden at phone, tablet and divided-display sizes: decorations stay behind the playing surface and controls, lanterns and buildings preserve their proportions, and dense stones, move labels and scoring marks remain distinct. Theme tests cover compact contrast, control roles, opaque paper, transparent stone padding and scene proportions; the native marker export also accepts `paperBlossoms`.

Whittled Woodland is available in Debug with `--surround-ui-theme whittledWoodland`. It follows the system appearance. The native grid, whittled maple edge and walnut/birch stones switch to solid rendering below 14 pt per cell. The phone, iPad and Duo artboard audit classes each have `testWhittledWoodlandTheme…` selectors. Use the phone states and scoring selectors for Play, Chat, Analyze, Zen and scoring, the iPad selectors for both orientations and the narrow window, and the Duo states selector for the configured physical pose.

The clock blocks have a deeper bevel than the player chips. Only a running clock carries the turn inlay. In sudden death the inlay uses the warning color. The Woodland control tests in `SurroundThemeTests` check the inset contour at 2× and 3× and measure text contrast against the rendered walnut and birch grain.

Sakura Stream is Debug-only (`--surround-ui-theme sakuraStream`) and follows the selected appearance. Its ivory ceramic board has an exact native dark-plum grid and opaque oxblood/pale-pink stone artwork; cells below 14 pt stay solid. Small pink and lilac phlox grow between moss and wet gravel along the bank. Larger cherry blossoms cluster on four overhead boughs. A uniform, viewport-only crop keeps water at the top in portrait and the left in landscape, clear of the default Play board; the enlarged iPad portrait Zen board can reach the shoreline. `ArtboardPhoneAuditTests/testSakuraStreamThemeStates` and `testSakuraStreamNightThemeStates` capture Play, Chat, Analyze and Zen in both orientations; the suite also offers scoring, control-state, small-phone and panel-transition selectors. iPad offers `testSakuraStreamThemeOrientations`, day/night `testSakuraStreamThemePanels`, and native narrow/tall-window selectors. Duo offers day/night `testSakuraStreamThemeStates` using the physical-pose contract above. Inspect the stream and blossoms behind the controls, side-colored player identities, dense pink/oxblood groups, and every marker at 20, 13 and 7 pt in Light/Dark. The native marker export accepts `sakuraStream`. Unit tests cover compact contrast, role/control contrast, matching opaque stone footprints, ceramic board opacity, finite full-viewport scene coverage, default-board water clearance and native scene rendering.

Night Garden clocks and player chips use generated amethyst/champagne satin-glass
panes. Check broad peripheral facets, quiet text centers and the thin lower edge
at logical phone size. Regular and compact versions share their artwork; fixed
corner slices keep compact Home clocks, toolbar chips and constrained columns
from stretching the facets. All artwork and state rings stay inside existing
control bounds. Inspect the gold running cue, red urgent cue, paused clocks,
scoring, long names and large text in both appearances. Increase Contrast and
Reduce Transparency use solid faces. Native pane tests cover text-reserve
opacity/contrast, accessibility fallbacks, bounded geometry and cached assets.

### Board marker matrix

Night Garden uses one pair of satin-cut glass stone images at every detailed
size. The broad asymmetric planes, soft upper-left reflection and natural
shoulder shading should read as the same material on phone and tablet boards.
Check clustered amethyst and champagne stones using
`--surround-board-marker-export-themes nightGarden` and
`--surround-board-marker-export-groups stone-groups,dense-position`.
The `glass-group` and `glass-group-artwork` samples share their position, images,
spacing and shadows. Both use artwork-only shading for this theme, so their
rendered boards should match; compare retained builds for artwork revisions.
Inspect 14, 20, 30, 40 and 64 pt cells in Light and Dark for clear boundaries,
opaque faces, legible markers and correctly faded removed stones. There is no
size-dependent artwork blend or added bright contour. Below the 14 pt detail
threshold, the board and stones remain solid; include 7 and 13 pt to check that
fallback. Refresh the native picker previews after changing either stone image.

Christmas Keepsakes uses painted wooden ornament clocks (including Home clocks) and player chips, with no ropes, drilled holes or attachment tabs. Inspect their fine horizontal paint/grain, clipped corners and exposed natural-wood bevels at logical phone size. Regular clocks and row player chips retain their lower thickness and contact shadow within the existing 7 pt allowance. Explicit compact profiles keep the wood inside the original bounds in Home/inline clocks, constrained clock columns, and vertical/header/avatar-only player chips. Painted text reservations remain unchanged; fine grain should match the selected painted finish rather than rough bare stock. Native text reservations, hit targets and semantic clock rings remain unchanged. Increase Contrast or Reduce Transparency uses exact solid faces without texture or bevels. `testChristmasKeepsakeOrnamentTextRegionsStayOpaqueAndReadable` covers actual text reserves, role/status contrast, opacity and solid fallbacks. `testChristmasKeepsakeOrnamentsKeepVisibleWoodAndBoundedDepth` checks visible wood material, paint grain, bounded depth and compact suppression; `testChristmasKeepsakeOrnamentAssetsLoadOpaqueCachedTextures` covers packaged texture integrity and reuse. The two material sources are in the Debug catalog; cookie textures are not packaged.

The Christmas board uses a shallow biscuit-tin sidewall with a rolled metal lip around the existing pine enamel. It shares the shipping board-depth geometry, grows continuously above the detailed-cell threshold and caps thickness at 7 pt. Geometry tests include both appearances, phone/tablet/rectangular slots, corner stones, shadow containment, zero compact depth and equal Light/Dark placement. `SurroundUITests/testChristmasKeepsakesBoardDepthKeepsMovesAligned` reuses the established depth gesture audit for A19/K10/T1 taps and drag-outside cancellation in both orientations and appearances. Compare native 7/13 pt compact panels with a retained pre-depth build; all compact rendering must remain solid. Refresh board-only picker previews when the board material changes.

Christmas Keepsakes uses authored cranberry cabochon and warm ivory glass artwork. Cranberry has a broad upper-left window reflection and transmitted red through its lower face. Ivory keeps a cream center, a clearer upper-left window highlight and a modest warm-gray lower-right shoulder. Both appearances share the source bitmaps before the appearance tint, without an additional gamma adjustment or procedural contour. `testChristmasKeepsakesGlassPreservesAuthoredColorsAndFootprints` checks exact source color/alpha, extent and cached image identity for both colors. Compare dense groups at logical phone size and larger cells, including marks and removed stones; the broad reflections must remain visible without washing out game marks. Use `dense-position` as well as `stone-groups` to inspect clustered ivory stones, and ensure their shoulder shading does not become a dark ring.

Christmas Keepsakes separates phone-size glass stones with a small centered inset and tighter, lighter cast/contact shadows. At a 20 pt cell, the nominal gap grows from 2 to 2.9 pt. Both colors share the spacing; compact solid stones keep their original footprints, and spacing returns to its original footprint and shadows reach their full-size profile by 32 pt. Use the opt-in `--surround-board-marker-export-groups stone-groups` for a dense black group, two one-point eyes, an empty corridor, white neighbors, marks and removed stones. `--surround-board-marker-sample glass-group` selects this on a native screen; `glass-group-artwork` forces artwork-only shading while retaining spacing/shadows. Both glass colors already use artwork-only shading, so these two samples match for this theme. Christmas alone opts into a stronger ivory contact shadow (0.48 opacity at phone size, easing to 0.60 by a 32 pt cell); its ellipse, blur, offset and broader cast are unchanged. Cranberry retains its prior contact, and removed stones still cast no shadow. Check the lower ivory edge at logical phone size without darkening its cream face or joining neighboring shadows. `testChristmasKeepsakesIvoryContactPreservesOtherStoneShadows` covers the explicit opt-in, unchanged cranberry policy, compact suppression and continuous size response. For a material comparison, retain exports from both builds and present them at matching logical point sizes: enlarged 3× images can overstate a small highlight's visibility. Requested export sizes define board slots; use the manifest's fitted cell size when labeling comparisons, since board depth can reduce it. Inspect Light/Dark at phone and tablet cell sizes. Focused tests check real theme resource loading, unchanged marker centers, spacing continuity, compact/large footprints and authored color/alpha preservation.

The Debug-only offline marker gallery launches with `--surround-ui-testing --surround-board-marker-audit 20`. Combine it with the theme and appearance arguments above. Use `--surround-board-marker-panel core-1` to show one export panel on the device, or `--surround-board-marker-sample variation-empty` for one board. These selectors preserve the device's native display scale; oversized boards should be checked on an iPad rather than scaled to fit a phone.

`--surround-ui-testing --surround-board-marker-export` renders the same board views with SwiftUI `ImageRenderer`, covering every supported theme/appearance at 2× and 3× and cell sizes 7, 10, 13, 14, 17, 20, 24, 30, 40 and 64 pt. The samples include both stone colors, empty and removed points, all artwork variants, last/pending/undo indicators, chat highlights, legal/illegal/removal crosshairs, removal/restore marks, scoring/estimates/dame, all annotation shapes, one-to-three-digit labels, overlaps, corners and coordinate labels. Filter a run with comma-separated values:

```text
--surround-board-marker-export-sizes 13,14,20,40
--surround-board-marker-export-scales 2,3
--surround-board-marker-export-themes standard,nebulaPearl,rakedGarden,surroundStudio,feltMeadow,nightGarden,christmasKeepsakes
--surround-board-marker-export-groups core,interaction,estimate,labels,overlap,edges,variants,widget
```

Exports live in the app's `Documents/BoardMarkerAudit/` directory. Each export deletes the previous run folders before it starts, so copy a run out of the app container to keep it. `progress.json` reports completion or failure; `manifest.json` records the exact samples, requested and pixel-aligned cell sizes, appearance, scale, artwork variants, PNG dimensions and run folder. Schema 2 adds `sampleGeometries`: each sample's inset face bounds, actual cell size and depth. Use these for mixed panels; the panel's `actualCellSize` represents its first sample. Keep the manifest with the PNGs. Inspect native phone and tablet screenshots as well: offscreen fixtures exercise drawing, not gesture behavior, every continuous board size, or the system's final widget compositing. At thumbnail sizes, long labels cannot retain full-size legibility within one intersection.

Opt in to `--surround-board-marker-export-groups board-sizes` for 9×9, 13×13, 19×19, 25×25, 9×19 and 19×9 boards, each with coordinates on/off. Each panel contains one board with corner stones, a centered last-move stone and marks on white/empty points. Use sizes `13,14,40` to compare compact, threshold and large detailed rendering. These samples are excluded from the default gallery/export; `--surround-board-marker-sample board-19x9-coordinates` selects one on screen. The separate `dense-position` group (sample `dense-19x19`) is a near-full synthetic 19×19 material stress fixture with clustered stones, gaps, a last-move marker and labels. It draws directly from an isolated board model and is not a legal game or a gameplay test. Schema 3 adds explicit `boardWidth` and `boardHeight` and retains `boardSize` for square samples. The manifest's actual cell size remains authoritative.

Felt Meadow's padded cells, recessed seams, running stitches and textile rim follow the existing grid and face bounds without changing tap coordinates. `SurroundThemeTests` covers all width/height combinations from 2 through 25, normalized resize geometry and the 14 pt detail cutoff. Native phone/iPad/Duo artboard audits above check the shared rendering in Play, Analyze, Chat, Zen and scoring layouts; inspect their screenshots as well as their geometry assertions.

`SurroundThemeTests` checks compact-board contrast, status/score casing, marker proportions and artwork centering. `BoardPositionTests` checks annotation/automatic-indicator priority and restoration after transient pending/undo states. These complement visual inspection; palette contrast alone does not test detailed reflections or pixel rasterization.

Studio and Nebula fit their board face, softly rounded lower edge, and shadow fade inside the existing board slot. `SurroundThemeTests` also checks containment of the slab plus three blur radii and the shadow offset, and the continuous 14 pt cutoff, including rectangular boards and coordinate gutters. `SurroundUITests/testThemedBoardDepthKeepsMovesAligned` exercises corner/center taps, Previous and drag cancellation in Nebula and Studio day/night, in portrait and landscape on phone and tablet. Its captures complement the marker gallery: Game Detail clips its board slot, so external shadows or edges can look correct in an unclipped gallery while disappearing in the game.

The slot keeps its frame, but clocks, player chips, action rows and panels that line up with the board follow the board as drawn: its face and the sidewall below, from `BoardDepthPlacement`, which takes BoardView's own inputs. Gaps to the board are still measured from the slot. The board-depth cases in `GameDetailLayoutTests` check the iPad, phone landscape, Duo and Book layouts with Studio's depth, the row heights reserved at the drawn width, and that flat themes keep their frames. Home's Large tiles and Public games' cards lay out their players' rows the same way, with `BoardColumnLayout`; `SurroundThemeTests/testBoardColumnRowsMeetTheDrawnBoard` checks its column. The Debug layout diagnostic (`game.layout.geometry`) reports `drawnBoard` beside `board`, so a UI test that pins a position against the board's edge can follow the drawn edge, as the Duo Zen action-line checks do. To compare by eye, run the Studio and Frost & Pine artboard audits above (and `GameDetailIPadArtboardAuditTests/testNebulaPearlThemeOrientations`) and check that chip edges meet the face's straight edges.

`ArtboardPhoneAuditTests/testSurroundStudioThemeControlStates` captures sudden-death clock text and disconnected scoring with a disabled Accept button. Inspect urgency text against tinted controls and the disabled action alongside the enabled scoring audit.

`ArtboardPhoneAuditTests/testSurroundStudioThemePanelTransitions` and `GameDetailIPadArtboardAuditTests/testSurroundStudioThemePanelTransitions` keep one Studio game open while toggling Play → Chat → Play → Analyze → Play in each orientation. They check panel visibility and board continuity and retain ten captures per device. Compare the decorations across each sequence: their size and position must remain fixed while panels pass over the background artwork.

`GameDetailIPadArtboardAuditTests/testSurroundStudioThemeNarrowWindow` additionally resizes the real iPad window to the design's 375 × 548 minimum and checks its native dimensions. The next iPad audit restores the full window before opening its fixture.

`--surround-game-detail-socket-down` (Debug, same compatibility-mode requirement) opens the design fixture with the WebSocket status `.reconnecting` and ticks the design game's clock locally each second, as the service's timer can while disconnected. Unlike other captures, such a launch gets the window's connection source, so the game says its status as a person sees it. The connection tests use it to check where a game says it: the running clock's Reconnecting… mark, the title slot's capsule where no clock is in play, the relabelled action where the layout has no title slot, and that every clock keeps the value from the disconnect.

`--surround-ui-hides-rank` (Debug, offline UI testing only) starts the isolated UI-test preferences suite with **Hide ranks and ratings** on; it never changes a signed-in app's preferences. `testHiddenRanksAndRatings` uses it on iPhone and, with `TEST_RUNNER_SURROUND_EXPECT_CLOSED_DUO_LANDSCAPE=1`, on Duo Closed landscape. `testLocalizedClockFit` accepts `TEST_RUNNER_SURROUND_HIDES_RANK=1` and `TEST_RUNNER_SURROUND_FIT_ZEN=1`; on Duo Closed landscape it also checks that no column card line truncates and that the column chips drop their rank line exactly when the cards grow for a wrapped line.

`--surround-activity-hidden-log` (Debug; any run, including on a device) logs each settled change to the window-level signal that hides Activity's bar: for each tab, the Game Detail or conversation on top of its stack. Each change is one `ACTIVITY-HIDDEN #<n>` line that lists `<tab>=<place>` for every tab it hides, or `none`. Stream them with `xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.honganhkhoa.Surround" AND category == "ActivityHidden"'`, or read them in Console on a device.

The notices host probes (Debug; any run, with or without `--surround-ui-testing`) draw dashed magenta PLACEHOLDER views where the window's host policy, `ActivityHostPolicy`, would put Activity. `--surround-notices-placeholder-bar` shows the bar in SwiftUI's bottom accessory, UIKit's accessory or a custom bar under root screens. `--surround-notices-force-custom-bar` replaces any floating bar with the custom bar. `--surround-notices-placeholder-bar-order before|after|deferred` sets when a UIKit container sets or clears its accessory around hiding the tab bar; it needs one of the bar flags. `--surround-notices-placeholder-bar-keyboard standard|ignore|hide` sets how the custom bar meets a docked software keyboard; it needs one of the bar flags. `--surround-notices-tab-bar-minimize automatic|never|on-scroll-down|on-scroll-up|on-scroll-down-after-launch` sets the iPhone tab bar's minimize behavior from iOS 26. `--surround-notices-placeholder-now` adds a Now section to the iPad and Mac sidebars. `--surround-notices-placeholder-subtitle status|retry|cycle` puts connection status under root titles, and on the Mac under every title. `--surround-notices-navigation-bar-minimize automatic|never` sets whether the navigation bar minimizes on iOS 27; it needs the subtitle flag. A malformed value, or a flag without the one it needs, stops the launch. Stream what the placeholders and their hosts do with `xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.honganhkhoa.Surround" AND category == "NoticesHostProbe"'`, or read it in Console on a device. Journeys launched through `SurroundJourneyUITestCase.launchApp`, and every App Store capture except `11-messages`, append the flags in `TEST_RUNNER_SURROUND_UI_NOTICES_HOST_PROBE`, split on whitespace. Tests that build their own launch, such as `LocalizationUITests`, `GameDetailDuoArtboardAuditTests` and `CompatibilityScreenshotTests`, ignore it. Without the variable, every launch is unchanged.

`--surround-connection-status-probe` (Debug; the normal app root only, so not with `--surround-ui-testing`) shows each window's connection status from its real socket and the device's network path in a yellow caption at the top of the window, retries when the caption is tapped while it offers Retry, and logs each status and announcement under subsystem `com.honganhkhoa.Surround`, category `ConnectionStatusProbe`.

`--surround-announcer-diagnostics` (Debug; any run, including on a device) logs each VoiceOver announcement or haptic request with its key, its outcome (`posted`, `duplicate`, `notFrontmost`, `noWindowInFront` or `windowClosed`) and short window IDs, each window's activation report, and each change of a window's active appearance (the focused window on Mac, and on iPad in Stage Manager and Windowed Apps), under subsystem `com.honganhkhoa.Surround`, category `AppAnnouncer`, never the spoken text.

Keep the result bundle and exported screenshot attachments with each visual review. Device geometry, native safe areas, and move-tree styling can differ intentionally from a drawing; document those separately from fixture data.

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
