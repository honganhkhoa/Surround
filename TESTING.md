# Testing Surround

Surround's automated tests are split into two groups:

- `SurroundTests` contains deterministic unit and service tests. These run for every push and pull request and must not contact OGS.
- `SurroundBetaTests` contains live integration scenarios against the isolated OGS beta service. Its separate shared scheme keeps it out of normal test runs; run it only by explicitly selecting that scheme locally or manually dispatching the **OGS beta integration tests** workflow.

## Deterministic tests

Run the normal suite from Xcode, or select an installed iOS 26 simulator and run it from the command line:

```sh
simulator_id="$(.github/ci-tools/select-ios-simulator.sh 26)"
xcodebuild test \
  -scheme Surround \
  -project Surround.xcodeproj \
  -destination "platform=iOS Simulator,id=${simulator_id}"
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
