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

`publish` is the only mutating command and requires an exact `--confirm-version` value.

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
locales, devices, scenes, and expected total count. PNG count and portrait-iPhone/landscape-iPad
orientation are independently
checked before a manifest can be built. ImageIO must fully decode every single-frame PNG at one
of the family's configured pixel sizes, with no alpha channel and neutral orientation metadata (`1`).
Manifest verification repeats these checks so a file or metadata-only rotation cannot change
after review.

## Credentials and safety

Only environment variable names are read; no credentials are written into an artifact:

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

## Tests

```sh
swift test --package-path .github/ci-tools/AppStoreConnectTool
```

Tests use temporary files and mocked HTTP transport. They never call or mutate App Store Connect.
