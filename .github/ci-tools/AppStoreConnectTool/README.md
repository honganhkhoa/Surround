# App Store Connect Tool

`app-store-connect-tool` is the dependency-free Swift component behind
`../app-store-release.sh`. It validates release packages, records a read-only App Store
Connect snapshot, builds a review manifest, and publishes an explicitly confirmed manifest.

It does **not** upload a build, select a build, submit for review, or translate text. Release
notes and any optional localized metadata must already be present in the release package.

## Commands

```sh
swift run --package-path .github/ci-tools/AppStoreConnectTool app-store-connect-tool \
  init --version 2.1 --output ../AppStoreReleases/2.1 \
  --locales-config .github/ci-tools/app-store-release-locales.json

swift run --package-path .github/ci-tools/AppStoreConnectTool app-store-connect-tool \
  validate-release --release ../AppStoreReleases/2.1/release.json \
  --locales-config .github/ci-tools/app-store-release-locales.json \
  --output .build/AppStoreRelease-2.1/normalized-release.json
```

Run `app-store-connect-tool --help` for all interfaces. `snapshot` is read-only; immediately
after it, run the metadata-only gate before spending time on screenshot capture:

```sh
app-store-connect-tool validate-snapshot \
  --release .build/AppStoreRelease-2.1/normalized-release.json \
  --snapshot .build/AppStoreRelease-2.1/remote-snapshot.json
```

Only `publish` and `publish-metadata-only` mutate App Store Connect. The former requires an exact
`--confirm-version`; the latter also requires the reviewed source version and manifest digest.

`inspect-duo-placement` is a separate GET-only diagnostic. Build the tool before
loading credentials, then run the built executable in the documented local
credential process:

```sh
app-store-connect-tool inspect-duo-placement \
  --bundle-id com.honganhkhoa.Surround --version 3.0 \
  --output /absolute/new/path/duo-placement-inspection.json
```

It discovers the ordinary iPhone Duo Asset Library group and image specifications
from Apple's returned catalog, then reads the app's library and any existing
version-localized placements in group order. Outer and inner displays share the
returned per-localization group limit. `IPHONE_DUO` is a display class, not a
legacy screenshot display-type enum. The command creates no remote resources,
does not implement Asset Library publication, and explicitly leaves upload
acceptance and storefront behavior unverified. Missing/ambiguous groups, malformed
specifications and unsafe resource identifiers fail closed. Credentials and key
contents are never included in diagnostic output.

The separate `build-duo-placement-plan` command is offline:

```sh
app-store-connect-tool build-duo-placement-plan \
  --inspection /reviewed/duo-inspection.json \
  --expected-inspection-sha256 REVIEWED_INSPECTION_SHA256 \
  --selected-import /reviewed/import/selected-import.json \
  --expected-import-sha256 REVIEWED_IMPORT_SHA256 \
  --expected-selection-sha256 REVIEWED_SELECTION_SHA256 \
  --output /absolute/new/path/duo-plan.json
```

Run the full private selected-import verifier before planning. The builder also
checks every retained source-binding hash, exact import/selection/inspection
pins, app/locale identity and every framed Duo PNG against the returned opaque
size, MIME and file-size specification. It retains all ten ordered cards per
locale, their original origins and distinct locale/slot/hash reservation keys.
Absent target versions cannot supply localization IDs. Future image/placement
IDs stay unresolved until an authorized executor obtains them.

`DuoAssetLibraryAdapter` only serializes image reservation, `uploaded:true`
commit, processed-image placement and ten-ID ordering bodies. It has no client
or network executor. Commit omits legacy MD5/sourceFileChecksum fields; specId
is processing readback evidence, not a reservation field. Placement eligibility
requires `PREPARE_FOR_SUBMISSION` and the intended specification. Ordering uses
one `orderedPlacements` array for the entire group/localization, with no numeric
position attribute. Upload operations must come from an actual reservation.
Local plans remain unpublishable and do not change capture/widget qualification
or prove Apple write acceptance. An existing placement's `ACTIVE` state does
not prove its image processing metadata; that needs separate image readback.

The separate `DuoPublishingExecutor` component implements per-localization
execution and recovery for a future qualified handoff. It has no CLI entry point
and cannot decode the unqualified offline plan as a `DuoPublishSet`. The caller
must supply actual editable target/localization IDs, the reviewed target baseline
and exact version/set-digest confirmations. Version creation and listing metadata
remain in the parent publishing workflow.

It seals full-size PNG backups and image identities, stages and processes all ten
replacement images, then replaces and orders placements. Its recovery strategy
is fixed in the journal: reupload verified backup PNG content, create new
placements and restore the original whole-group order. Existing image assets are
never deleted or archived. Original placement/image IDs are not claimed to survive
restoration. An empty baseline is restored to verified emptiness; smaller
baselines are ordered using their complete backed-up count.

The journal requires an existing handoff directory, exclusive ownership, synced
backup files/directories and synced intent writes before mutation. Response-known
and readback-verified states are separate. Unknown reservations or uploads stop
without blind replay; filename/size alone never establish ownership. Known image
IDs can reconcile lost placement responses, and exact whole-order readback can
reconcile lost forward or rollback ordering responses. Foreign IDs, image changes,
external reordering or persistence failure stop further writes. Verified rollback
creates a checkpoint for resuming the same reviewed set in a new epoch; completed
groups are read back before reuse. Upload URLs, headers and credentials are not
journaled. Mutation requests and upload operations use a single attempt.

This component is tested with injected fixtures, including recovery and existing
legacy retry/rollback compatibility. The current selected capture remains gated;
local execution tests do not establish server write acceptance, storefront
presentation or historical capture qualification. No publishing command invokes
the new component yet.

For a patch release that changes only localized What's New text, use the dedicated
metadata-only manifest and publisher instead of capturing screenshots:

```sh
app-store-connect-tool build-metadata-only-manifest \
  --release .build/AppStoreRelease-MetadataOnly-2.2.1/normalized-release.json \
  --locales-config .github/ci-tools/app-store-release-locales.json \
  --remote-snapshot .build/AppStoreRelease-MetadataOnly-2.2.1/remote-snapshot.json \
  --expected-source-version 2.2 \
  --output .build/AppStoreRelease-MetadataOnly-2.2.1/publish-manifest.json \
  --review-html .build/AppStoreRelease-MetadataOnly-2.2.1/review.html

app-store-connect-tool publish-metadata-only \
  --manifest .build/AppStoreRelease-MetadataOnly-2.2.1/publish-manifest.json \
  --locales-config .github/ci-tools/app-store-release-locales.json \
  --expected-source-version 2.2 \
  --confirm-version 2.2.1 \
  --confirm-manifest-digest REVIEWED_SHA256 \
  --journal .build/AppStoreRelease-MetadataOnly-2.2.1/metadata-only-publish-journal.json
```

The public wrapper described below is the supported user-facing entry point. These core
commands document and test its exact contract.

## Locale configuration

The preferred configuration shape is:

```json
{
  "schemaVersion": 1,
  "bundleId": "com.example.App",
  "platform": "IOS",
  "localizations": [
    { "appStoreLocale": "en-US", "screenshotConfiguration": "en-US" },
    { "appStoreLocale": "zh-Hant", "screenshotConfiguration": "zh-Hant-TW" }
  ],
  "screenshotFamilies": [
    {
      "name": "iphone-6.9",
      "directory": "iphone-6.9",
      "displayType": "APP_IPHONE_67",
      "expectedCount": 10,
      "pixelWidth": 1320,
      "pixelHeight": 2868,
      "allowsMixedOrientations": true,
      "additionalPixelSizes": [
        { "pixelWidth": 1260, "pixelHeight": 2736 },
        { "pixelWidth": 1290, "pixelHeight": 2796 }
      ]
    },
    {
      "name": "ipad-13",
      "directory": "ipad-13",
      "displayType": "APP_IPAD_PRO_3GEN_129",
      "expectedCount": 10,
      "pixelWidth": 2752,
      "pixelHeight": 2064,
      "additionalPixelSizes": [
        { "pixelWidth": 2732, "pixelHeight": 2048 }
      ]
    }
  ]
}
```

`allowsMixedOrientations` is an optional Boolean, enabled only for the public
iPhone family. The first image must match an approved family base size; later
images may use that base or its exact transpose, without mixing hardware
resolutions. Opted-in manifests record `pixelWidth` and `pixelHeight` on every
image and retain a set-level base size. Verification fully decodes each PNG
against its own recorded dimensions. Omitted optional fields preserve the
encoded shape and digest of legacy uniform sets, including rollback manifests.

## Release package

`init` creates the required files for every configured locale:

```json
{
  "schemaVersion": 1,
  "version": "2.1",
  "localizations": {
    "en-US": {
      "whatsNewFile": "localizations/en-US/whats-new.txt"
    }
  }
}
```

Optional version-localized fields are `description`, `keywords`, `promotionalText`,
`supportUrl`, and `marketingUrl`. Optional app-wide localized fields are `name`, `subtitle`,
and `privacyPolicyUrl`. They may be direct keys or
members of `versionMetadata` and `appMetadata`, respectively. `descriptionFile` and
`promotionalTextFile` are also accepted. Top-level `copyright` is optional.

Omitted fields are unchanged for languages already present in the released source listing.
Explicit JSON `null` is conservatively accepted only for `keywords`, `promotionalText`,
`marketingUrl`, and `subtitle`.

For a newly added language, `prepare` requires effective nonempty values for `description`,
`keywords`, `supportUrl`, `name`, `subtitle`, and `privacyPolicyUrl`. Explicit release-package
values take precedence; otherwise, values already present in the reviewed draft are accepted.
For a repeatable release package, specify the first three under `versionMetadata` and the last
three under `appMetadata`. The localized name must contain 2–30 characters, and the privacy
policy must be an absolute HTTP(S) URL.

Validation includes Apple field limits, including the 100-character keyword limit measured
conservatively with Swift's UTF-16 view. This matches App Store Connect's treatment of combining
marks in localized keywords. The capture metadata must list exactly the configured screenshot
locales, devices, scenes, and expected total count. PNG count and dimensions are independently
checked before a manifest can be built. ImageIO must fully decode every single-frame PNG at
the family's approved base size, or its exact transpose when that family explicitly opts in,
with no alpha channel and neutral orientation metadata (`1`). Other hardware sizes cannot be
mixed within a set.
Manifest verification repeats these checks so a file or metadata-only rotation cannot change
after review.

## Credentials and safety

Credentials are read locally from the following environment references and the referenced
private-key file; no credentials or private-key contents are written into an artifact:

```text
ASC_KEY_ID
ASC_ISSUER_ID
ASC_PRIVATE_KEY_PATH
```

The key must be a team API key because JWTs include an issuer ID. Use an app-restricted App
Manager key where available, and keep the `.p8` file outside Git.

Publishing requires `PREPARE_FOR_SUBMISSION` resources. Initial and resumed runs reconcile live
resource IDs, metadata, locale sets, screenshot checksums/processing states, and ordering against
the reviewed baseline, desired manifest, and every journaled operation; unknown drift aborts.
Completed journal entries are never trusted without live read-back.

Before the first DELETE in each screenshot set, every existing image must download and fully
decode. The tool writes and re-verifies a structured backup manifest containing file hashes,
dimensions, alpha/orientation state, original IDs, and order. If any item cannot be backed up,
the replacement stops before deleting anything. If deletion, upload, processing, or ordering
later fails, the tool deletes the partial replacement and re-uploads/reorders the entire verified
backup. If restoration also fails, the error reports both the original failure and rollback
failure. Apple supplies processed PNG renditions rather than original uploads, so a successful
rollback preserves the reviewed visual/order but may produce new resource IDs and file checksums.
A successful rollback records those verified replacement IDs, checksums, and order as a new
journal epoch. A later run can retry from that checkpoint, while any unjournaled or post-checkpoint
asset drift still aborts.

Uploads use Apple's exact byte ranges without a JWT, commit lowercase whole-file MD5 values, and
must read back with `assetDeliveryState` `COMPLETE`. Ambiguous POST failures are never replayed
automatically; inspect App Store Connect and prepare again as directed by the error.

The metadata-only publisher has a deliberately narrower API surface. Its manifest must contain
exactly one `whatsNew` field for every configured locale, no App Info or version-wide changes,
and zero managed screenshot sets. It requires exact source-version, target-version, and manifest-
digest confirmations. When it creates the target version, it sends `versionString`, `platform`,
and the reviewed inherited copyright but deliberately omits `releaseType`. It then waits for
App Store Connect to finish inheriting the source listing and proves that every locale, non-
What's-New field, screenshot family, ordered file name, checksum, and `COMPLETE` state matches
the reviewed source. Inherited resource IDs are intentionally excluded from that comparison
because Apple creates new resources for the copied assets.

Metadata-only snapshots separately capture the live and draft App Info resources. The gate
compares all localized App Info fields, non-state App Info attributes, six category linkages,
and the complete age-rating declaration while ignoring copied App Info/localization/age-rating
resource IDs. Older handoffs without this evidence must be prepared again.

Its only post-creation write is a sparse PATCH whose attributes object contains exactly
`whatsNew` for one existing version localization. There are no screenshot, preview, App Info,
build, submission, or DELETE write routes in this publisher. Each mutation is single-attempt;
an ambiguous result remains pending until a later confirmed run reconciles fresh live state.
A bundle/platform/version-scoped advisory lock serializes distinct handoffs and releases safely
if a process exits. A possibly successful version-creation POST is never replayed automatically;
an exact inherited target may be adopted under its existing journal, otherwise prepare again.

## Tests

```sh
swift test --package-path .github/ci-tools/AppStoreConnectTool
```

Tests use temporary files and mocked HTTP transport. They never call or mutate App Store Connect.
