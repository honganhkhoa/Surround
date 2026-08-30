#!/usr/bin/env bash

set -euo pipefail

readonly exit_usage=64
readonly shipping_configuration="Release"
readonly tool_product="app-store-connect-tool"

usage() {
  cat <<'EOF'
Prepare and publish a reviewed App Store Connect metadata release.

Usage:
  app-store-release.sh init --version VERSION --output DIRECTORY
  app-store-release.sh validate --release FILE [--output FILE]
  app-store-release.sh prepare --release FILE
  app-store-release.sh prepare-metadata-only --release FILE --source-version VERSION
  app-store-release.sh publish --manifest FILE --confirm-version VERSION
  app-store-release.sh publish-metadata-only --manifest FILE \
    --confirm-source-version VERSION --confirm-version VERSION \
    --confirm-manifest-digest SHA256
  app-store-release.sh help

Commands:
  init      Create a private release package with one release-note file for
            each supported App Store localization.
  validate  Validate a release package and the shipping targets' Release
            MARKETING_VERSION without contacting App Store Connect.
  prepare   Validate the package, take a read-only App Store Connect snapshot,
            preflight localized metadata (including required fields for newly
            added languages), capture all localized screenshots, and build a
            review manifest.
  prepare-metadata-only
            Validate a What's-New-only package, snapshot the exact released
            source version, and build a zero-screenshot review manifest.
  publish   Apply one reviewed screenshot-and-metadata manifest.
  publish-metadata-only
            Create or reuse the reviewed target version, verify that metadata
            and screenshots inherit unchanged from the confirmed source, and
            patch only localized What's New fields.

Options:
  --version VERSION          App Store version used by init.
  --output PATH              New init directory, or normalized JSON output for
                             validate. The validate output is optional.
  --release FILE             Path to the private release.json input.
  --manifest FILE            Path to prepare's publish-manifest.json.
  --source-version VERSION   Exact released version to inherit during
                             prepare-metadata-only.
  --confirm-source-version VERSION
                             Exact reviewed source-version confirmation.
  --confirm-version VERSION  Required exact version confirmation for publish.
  --confirm-manifest-digest SHA256
                             Required exact reviewed manifest confirmation for
                             publish-metadata-only.
  -h, --help                 Show this help.

Authentication for both prepare and publish modes:
  ASC_KEY_ID
  ASC_ISSUER_ID
  ASC_PRIVATE_KEY_PATH

Screenshot runtime for prepare (not prepare-metadata-only):
  Captures default to the checked-in iOS 26.5 submission runtime. Set
  APP_STORE_IOS_RUNTIME only when deliberately changing that runtime.

The private key and unpublished release package must remain outside this
public repository. Generated build products, snapshots, screenshots, reviews,
and journals stay under the repository's gitignored .build directory.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

usage_error() {
  echo "error: $*" >&2
  echo >&2
  usage >&2
  exit "$exit_usage"
}

require_command() {
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 \
    || fail "Required command was not found: ${command_name}"
}

absolute_path() {
  local path="$1"

  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$invocation_directory" "$path"
  fi
}

strip_trailing_slashes() {
  local path="$1"

  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done

  printf '%s\n' "$path"
}

validate_non_broad_path() {
  local label="$1"
  local path

  path="$(strip_trailing_slashes "$2")"
  [[ -n "$path" ]] || usage_error "${label} must not be empty."

  case "$path" in
    /|.|..)
      usage_error "${label} must identify a dedicated path, not '${path}'."
      ;;
  esac
}

validate_version_string() {
  local version="$1"

  [[ "$version" =~ ^[0-9]+([.][0-9]+){1,2}$ ]] \
    || usage_error "Version '${version}' must contain two or three dot-separated integer components."
}

validate_sha256_string() {
  local digest="$1"

  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] \
    || usage_error "Manifest digest must be exactly 64 lowercase hexadecimal characters."
}

canonicalize_path_with_existing_parent() {
  local path="$1"
  local parent_path

  parent_path="$(cd "$(dirname "$path")" && pwd -P)" \
    || fail "Could not resolve the parent directory for ${path}."
  printf '%s/%s\n' "$parent_path" "$(basename "$path")"
}

normalize_absolute_path() {
  local path="$1"
  local component
  local normalized=""
  local index
  local -a components=()
  local -a stack=()

  [[ "$path" == /* ]] || fail "Expected an absolute path: ${path}"
  IFS='/' read -r -a components <<<"$path"
  for component in "${components[@]}"; do
    case "$component" in
      ''|.)
        ;;
      ..)
        if (( ${#stack[@]} > 0 )); then
          index=$((${#stack[@]} - 1))
          unset 'stack[index]'
        fi
        ;;
      *)
        stack+=("$component")
        ;;
    esac
  done
  for component in "${stack[@]}"; do
    normalized="${normalized}/${component}"
  done
  printf '%s\n' "${normalized:-/}"
}

require_private_release_path() {
  local label="$1"
  local path="$2"

  case "$path" in
    "$repository_root"|"$repository_root"/*)
      fail "${label} must stay outside the public Surround repository: ${path}"
      ;;
  esac
}

require_new_path() {
  local label="$1"
  local path="$2"

  validate_non_broad_path "$label" "$path"
  if [[ -e "$path" || -L "$path" ]]; then
    usage_error "${label} already exists; choose a new path: ${path}"
  fi
}

require_readable_file() {
  local label="$1"
  local path="$2"

  [[ -f "$path" && -r "$path" ]] \
    || usage_error "${label} is not a readable file: ${path}"
}

validate_locale_configuration() {
  require_readable_file "Locale configuration" "$locale_configuration_path"
  require_readable_file "Screenshot test plan" "$screenshot_test_plan_path"

  jq -e --slurpfile test_plan "$screenshot_test_plan_path" '
    .schemaVersion == 1
    and .bundleId == "com.honganhkhoa.Surround"
    and .platform == "IOS"
    and (.localizations | type == "array" and length > 0)
    and ([.localizations[].appStoreLocale]
      | all(type == "string" and length > 0))
    and ([.localizations[].screenshotConfiguration]
      | all(type == "string" and length > 0))
    and (([.localizations[].appStoreLocale] | unique | length)
      == (.localizations | length))
    and (([.localizations[].screenshotConfiguration] | unique | length)
      == (.localizations | length))
    and (([.localizations[].screenshotConfiguration] | sort)
      == ([$test_plan[0].configurations[].name] | sort))
    and ([.screenshotFamilies[] | {
      name, directory, displayType, expectedCount, pixelWidth, pixelHeight,
      additionalPixelSizes
    }] == [
      {
        name: "iphone-6.9",
        directory: "iphone-6.9",
        displayType: "APP_IPHONE_67",
        expectedCount: 10,
        pixelWidth: 1320,
        pixelHeight: 2868,
        additionalPixelSizes: [
          {pixelWidth: 1260, pixelHeight: 2736},
          {pixelWidth: 1290, pixelHeight: 2796}
        ]
      },
      {
        name: "ipad-13",
        directory: "ipad-13",
        displayType: "APP_IPAD_PRO_3GEN_129",
        expectedCount: 10,
        pixelWidth: 2752,
        pixelHeight: 2064,
        additionalPixelSizes: [
          {pixelWidth: 2732, pixelHeight: 2048}
        ]
      }
    ])
  ' "$locale_configuration_path" >/dev/null \
    || fail "Locale configuration does not match the screenshot test plan and exact-ten device contract: ${locale_configuration_path}"
}

require_app_store_credentials() {
  local variable_name
  local resolved_key_path
  local key_repository

  for variable_name in ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_PATH; do
    [[ -n "${!variable_name:-}" ]] \
      || fail "${variable_name} must be set for App Store Connect access."
  done

  [[ -f "$ASC_PRIVATE_KEY_PATH" && -r "$ASC_PRIVATE_KEY_PATH" ]] \
    || fail "ASC_PRIVATE_KEY_PATH must identify a readable private-key file."

  resolved_key_path="$(realpath "$ASC_PRIVATE_KEY_PATH")" \
    || fail "ASC_PRIVATE_KEY_PATH could not be resolved."
  require_private_release_path "App Store Connect private key" "$resolved_key_path"
  if key_repository="$(
    git -C "$(dirname "$resolved_key_path")" rev-parse --show-toplevel 2>/dev/null
  )"; then
    fail "App Store Connect private key must stay outside Git repositories: ${key_repository}"
  fi
}

run_app_store_connect_tool() {
  mkdir -p \
    "$tool_scratch_path" \
    "$tool_module_cache_path" \
    "$tool_cache_path" \
    "$tool_config_path" \
    "$tool_security_path"

  CLANG_MODULE_CACHE_PATH="$tool_module_cache_path" \
  SWIFT_MODULECACHE_PATH="$tool_module_cache_path" \
    swift run \
      --package-path "$tool_package_path" \
      --scratch-path "$tool_scratch_path" \
      --cache-path "$tool_cache_path" \
      --config-path "$tool_config_path" \
      --security-path "$tool_security_path" \
      "$tool_product" \
      "$@"
}

normalized_release_version() {
  local normalized_release_path="$1"
  local version

  version="$(
    jq -er '.version | select(type == "string" and length > 0)' \
      "$normalized_release_path"
  )" || fail "The normalized release does not contain a version string."

  validate_version_string "$version"
  printf '%s\n' "$version"
}

validate_shipping_marketing_versions() {
  local expected_version="$1"
  local target_build_settings
  local target
  local expected_bundle_identifier
  local entry_count
  local actual_version
  local actual_bundle_identifier
  local index
  local source_packages_path="${screenshot_derived_data_path}/SourcePackages"
  local package_cache_path="${screenshot_derived_data_path}/PackageCache"
  local swift_module_cache_path="${screenshot_derived_data_path}/SwiftModuleCache.noindex"
  local release_tool_user_home="${screenshot_derived_data_path}/ReleaseToolUserHome"
  local -a targets=(
    "Surround"
    "SurroundWidgetsExtension"
    "SurroundNotificationContent"
    "SurroundNotificationService"
  )
  local -a bundle_identifiers=(
    "com.honganhkhoa.Surround"
    "com.honganhkhoa.Surround.SurroundWidgets"
    "com.honganhkhoa.Surround.SurroundNotificationContent"
    "com.honganhkhoa.Surround.SurroundNotificationService"
  )

  mkdir -p \
    "$source_packages_path" \
    "$package_cache_path" \
    "$swift_module_cache_path" \
    "${release_tool_user_home}/Library/Caches" \
    "${release_tool_user_home}/.cache"

  echo "Validating Release MARKETING_VERSION ${expected_version} for the shipping app and extensions..."
  index=0
  while (( index < ${#targets[@]} )); do
    target="${targets[$index]}"
    expected_bundle_identifier="${bundle_identifiers[$index]}"
    if ! target_build_settings="$(
      CFFIXED_USER_HOME="$release_tool_user_home" \
      XDG_CACHE_HOME="${release_tool_user_home}/.cache" \
      CLANG_MODULE_CACHE_PATH="${screenshot_derived_data_path}/ModuleCache.noindex" \
      SWIFTPM_MODULECACHE_OVERRIDE="$swift_module_cache_path" \
      xcodebuild \
        -project "$project_path" \
        -target "$target" \
        -configuration "$shipping_configuration" \
        -clonedSourcePackagesDirPath "$source_packages_path" \
        -packageCachePath "$package_cache_path" \
        -disableAutomaticPackageResolution \
        -onlyUsePackageVersionsFromResolvedFile \
        -skipPackageUpdates \
        -disablePackageRepositoryCache \
        -showBuildSettings \
        -json \
        OBJROOT="${screenshot_derived_data_path}/Build/Intermediates.noindex" \
        SYMROOT="${screenshot_derived_data_path}/Build/Products" \
        SHARED_PRECOMPS_DIR="${screenshot_derived_data_path}/Build/SharedPrecompiledHeaders" \
        CLANG_MODULE_CACHE_PATH="${screenshot_derived_data_path}/ModuleCache.noindex"
    )"; then
      fail "Could not read ${target}'s Release build settings."
    fi

    entry_count="$(
      jq -r --arg target "$target" \
        '[.[] | select(.target == $target)] | length' \
        <<<"$target_build_settings"
    )"
    [[ "$entry_count" == "1" ]] \
      || fail "Expected one Release build-settings entry for ${target}; found ${entry_count}."

    actual_version="$(
      jq -r --arg target "$target" \
        '.[] | select(.target == $target) | .buildSettings.MARKETING_VERSION // empty' \
        <<<"$target_build_settings"
    )"
    actual_bundle_identifier="$(
      jq -r --arg target "$target" \
        '.[] | select(.target == $target) | .buildSettings.PRODUCT_BUNDLE_IDENTIFIER // empty' \
        <<<"$target_build_settings"
    )"

    [[ "$actual_bundle_identifier" == "$expected_bundle_identifier" ]] \
      || fail "${target} resolved to unexpected bundle identifier '${actual_bundle_identifier}'."
    [[ "$actual_version" == "$expected_version" ]] \
      || fail "${target} MARKETING_VERSION is '${actual_version}', expected '${expected_version}'."

    index=$((index + 1))
  done
}

create_unique_artifact_path() {
  local version="$1"
  local timestamp
  local base_path
  local candidate_path
  local suffix

  timestamp="$(date +%Y%m%d-%H%M%S)"
  base_path="${repository_root}/.build/AppStoreRelease-${version}-${timestamp}"
  candidate_path="$base_path"
  suffix=2

  while [[ -e "$candidate_path" || -L "$candidate_path" ]]; do
    candidate_path="${base_path}-${suffix}"
    suffix=$((suffix + 1))
  done

  printf '%s\n' "$candidate_path"
}

create_unique_metadata_only_artifact_path() {
  local version="$1"
  local timestamp
  local base_path
  local candidate_path
  local suffix

  timestamp="$(date +%Y%m%d-%H%M%S)"
  base_path="${repository_root}/.build/AppStoreRelease-MetadataOnly-${version}-${timestamp}"
  candidate_path="$base_path"
  suffix=2

  while [[ -e "$candidate_path" || -L "$candidate_path" ]]; do
    candidate_path="${base_path}-${suffix}"
    suffix=$((suffix + 1))
  done

  printf '%s\n' "$candidate_path"
}

command_init() {
  local version=""
  local output_path=""

  while (( $# > 0 )); do
    case "$1" in
      --version)
        (( $# >= 2 )) || usage_error "--version requires a value."
        version="$2"
        shift 2
        ;;
      --output)
        (( $# >= 2 )) || usage_error "--output requires a value."
        output_path="$(absolute_path "$2")"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage_error "Unknown init option: $1"
        ;;
    esac
  done

  [[ -n "$version" ]] || usage_error "init requires --version."
  [[ -n "$output_path" ]] || usage_error "init requires --output."
  validate_version_string "$version"
  output_path="$(normalize_absolute_path "$output_path")"
  require_new_path "Release package output" "$output_path"
  require_private_release_path "Release package output" "$output_path"
  mkdir -p "$(dirname "$output_path")"
  output_path="$(canonicalize_path_with_existing_parent "$output_path")"
  require_private_release_path "Release package output" "$output_path"

  run_app_store_connect_tool init \
    --version "$version" \
    --output "$output_path" \
    --locales-config "$locale_configuration_path"

  echo "Private release package created: ${output_path}"
  echo "Fill every whats-new.txt file before running prepare."
}

command_validate() {
  local release_path=""
  local output_path=""
  local normalized_version

  while (( $# > 0 )); do
    case "$1" in
      --release)
        (( $# >= 2 )) || usage_error "--release requires a value."
        release_path="$(absolute_path "$2")"
        shift 2
        ;;
      --output)
        (( $# >= 2 )) || usage_error "--output requires a value."
        output_path="$(absolute_path "$2")"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage_error "Unknown validate option: $1"
        ;;
    esac
  done

  [[ -n "$release_path" ]] || usage_error "validate requires --release."
  require_readable_file "Release input" "$release_path"
  release_path="$(realpath "$release_path")" \
    || fail "Release input could not be resolved: ${release_path}"
  require_private_release_path "Release input" "$release_path"

  if [[ -z "$output_path" ]]; then
    output_path="${repository_root}/.build/AppStoreReleaseValidation-$(date +%Y%m%d-%H%M%S)-$$.json"
  fi
  require_new_path "Normalized release output" "$output_path"
  mkdir -p "$(dirname "$output_path")"

  run_app_store_connect_tool validate-release \
    --release "$release_path" \
    --locales-config "$locale_configuration_path" \
    --output "$output_path"

  normalized_version="$(normalized_release_version "$output_path")"
  validate_shipping_marketing_versions "$normalized_version"

  echo "Release package is valid: ${output_path}"
  echo "No App Store Connect request was made."
}

command_prepare() {
  local release_path=""
  local requested_version
  local normalized_version
  local artifact_path
  local normalized_release_path
  local remote_snapshot_path
  local capture_path
  local manifest_path
  local review_html_path
  local screenshot_configuration
  local -a capture_arguments=()

  while (( $# > 0 )); do
    case "$1" in
      --release)
        (( $# >= 2 )) || usage_error "--release requires a value."
        release_path="$(absolute_path "$2")"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage_error "Unknown prepare option: $1"
        ;;
    esac
  done

  [[ -n "$release_path" ]] || usage_error "prepare requires --release."
  require_readable_file "Release input" "$release_path"
  release_path="$(realpath "$release_path")" \
    || fail "Release input could not be resolved: ${release_path}"
  require_private_release_path "Release input" "$release_path"

  requested_version="$(
    jq -er '.version | select(type == "string" and length > 0)' "$release_path"
  )" || fail "The release input does not contain a version string."
  validate_version_string "$requested_version"

  artifact_path="$(create_unique_artifact_path "$requested_version")"
  normalized_release_path="${artifact_path}/normalized-release.json"
  mkdir -p "$artifact_path"

  run_app_store_connect_tool validate-release \
    --release "$release_path" \
    --locales-config "$locale_configuration_path" \
    --output "$normalized_release_path"

  normalized_version="$(normalized_release_version "$normalized_release_path")"
  [[ "$normalized_version" == "$requested_version" ]] \
    || fail "Normalized release version '${normalized_version}' does not match '${requested_version}'."
  validate_shipping_marketing_versions "$normalized_version"
  require_app_store_credentials

  remote_snapshot_path="${artifact_path}/remote-snapshot.json"
  echo "Taking a read-only App Store Connect snapshot before screenshot capture..."
  run_app_store_connect_tool snapshot \
    --release "$normalized_release_path" \
    --output "$remote_snapshot_path"

  echo "Preflighting the target version and all localized metadata before screenshot capture..."
  run_app_store_connect_tool validate-snapshot \
    --release "$normalized_release_path" \
    --snapshot "$remote_snapshot_path"

  capture_path="${artifact_path}/capture"
  while IFS= read -r screenshot_configuration; do
    [[ -n "$screenshot_configuration" ]] \
      || fail "Locale configuration contains an empty screenshot configuration."
    capture_arguments+=(--locale "$screenshot_configuration")
  done < <(jq -r '.localizations[].screenshotConfiguration' "$locale_configuration_path")

  echo "Capturing the configured App Store localization matrix..."
  "$screenshot_capture_script" \
    --output "$capture_path" \
    --derived-data "$screenshot_derived_data_path" \
    "${capture_arguments[@]}"

  manifest_path="${artifact_path}/publish-manifest.json"
  review_html_path="${artifact_path}/review.html"
  run_app_store_connect_tool build-manifest \
    --release "$normalized_release_path" \
    --locales-config "$locale_configuration_path" \
    --screenshots-root "${capture_path}/screenshots" \
    --capture-metadata "${capture_path}/run-metadata.json" \
    --remote-snapshot "$remote_snapshot_path" \
    --output "$manifest_path" \
    --review-html "$review_html_path"

  echo "App Store release ${normalized_version} is prepared for review."
  echo "Artifact:        ${artifact_path}"
  echo "Screenshot view: ${capture_path}/index.html"
  echo "Metadata review: ${review_html_path}"
  echo "Publish manifest: ${manifest_path}"
}

command_prepare_metadata_only() {
  local release_path=""
  local source_version=""
  local requested_version
  local normalized_version
  local artifact_path
  local normalized_release_path
  local remote_snapshot_path
  local manifest_path
  local review_html_path
  local manifest_digest

  while (( $# > 0 )); do
    case "$1" in
      --release)
        (( $# >= 2 )) || usage_error "--release requires a value."
        release_path="$(absolute_path "$2")"
        shift 2
        ;;
      --source-version)
        (( $# >= 2 )) || usage_error "--source-version requires a value."
        source_version="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage_error "Unknown prepare-metadata-only option: $1"
        ;;
    esac
  done

  [[ -n "$release_path" ]] || usage_error "prepare-metadata-only requires --release."
  [[ -n "$source_version" ]] \
    || usage_error "prepare-metadata-only requires --source-version."
  validate_version_string "$source_version"
  require_readable_file "Release input" "$release_path"
  release_path="$(realpath "$release_path")" \
    || fail "Release input could not be resolved: ${release_path}"
  require_private_release_path "Release input" "$release_path"

  requested_version="$(
    jq -er '.version | select(type == "string" and length > 0)' "$release_path"
  )" || fail "The release input does not contain a version string."
  validate_version_string "$requested_version"
  [[ "$requested_version" != "$source_version" ]] \
    || usage_error "Target version and source version must differ."

  artifact_path="$(create_unique_metadata_only_artifact_path "$requested_version")"
  normalized_release_path="${artifact_path}/normalized-release.json"
  mkdir -p "$artifact_path"

  run_app_store_connect_tool validate-release \
    --release "$release_path" \
    --locales-config "$locale_configuration_path" \
    --output "$normalized_release_path"

  normalized_version="$(normalized_release_version "$normalized_release_path")"
  [[ "$normalized_version" == "$requested_version" ]] \
    || fail "Normalized release version '${normalized_version}' does not match '${requested_version}'."
  validate_shipping_marketing_versions "$normalized_version"
  require_app_store_credentials

  remote_snapshot_path="${artifact_path}/remote-snapshot.json"
  echo "Taking a read-only App Store Connect snapshot for metadata-only review..."
  run_app_store_connect_tool snapshot \
    --release "$normalized_release_path" \
    --output "$remote_snapshot_path"

  echo "Preflighting inherited metadata and screenshots without rendering captures..."
  run_app_store_connect_tool validate-snapshot \
    --release "$normalized_release_path" \
    --snapshot "$remote_snapshot_path"

  manifest_path="${artifact_path}/publish-manifest.json"
  review_html_path="${artifact_path}/review.html"
  run_app_store_connect_tool build-metadata-only-manifest \
    --release "$normalized_release_path" \
    --locales-config "$locale_configuration_path" \
    --remote-snapshot "$remote_snapshot_path" \
    --expected-source-version "$source_version" \
    --output "$manifest_path" \
    --review-html "$review_html_path"

  manifest_digest="$(
    jq -er '.manifestDigest | select(type == "string" and length == 64)' "$manifest_path"
  )" || fail "The metadata-only manifest does not contain a SHA-256 digest."
  validate_sha256_string "$manifest_digest"

  echo "Metadata-only App Store release ${normalized_version} is prepared for review."
  echo "Artifact:        ${artifact_path}"
  echo "Metadata review: ${review_html_path}"
  echo "Publish manifest: ${manifest_path}"
  echo "Source version:  ${source_version}"
  echo "Manifest digest: ${manifest_digest}"
  echo "No screenshots were rendered or placed under management."
}

command_publish() {
  local manifest_path=""
  local confirmed_version=""
  local manifest_version
  local journal_path

  while (( $# > 0 )); do
    case "$1" in
      --manifest)
        (( $# >= 2 )) || usage_error "--manifest requires a value."
        manifest_path="$(absolute_path "$2")"
        shift 2
        ;;
      --confirm-version)
        (( $# >= 2 )) || usage_error "--confirm-version requires a value."
        confirmed_version="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage_error "Unknown publish option: $1"
        ;;
    esac
  done

  [[ -n "$manifest_path" ]] || usage_error "publish requires --manifest."
  [[ -n "$confirmed_version" ]] || usage_error "publish requires --confirm-version."
  validate_version_string "$confirmed_version"
  require_readable_file "Publish manifest" "$manifest_path"
  manifest_path="$(realpath "$manifest_path")" \
    || fail "Publish manifest could not be resolved: ${manifest_path}"
  case "$manifest_path" in
    "${repository_root}/.build/AppStoreRelease-"*/publish-manifest.json)
      ;;
    *)
      fail "Publish requires a reviewed manifest from .build/AppStoreRelease-*: ${manifest_path}"
      ;;
  esac
  if [[ "$(jq -r '.captureMetadata.mode // empty' "$manifest_path")" == "metadata-only" ]]; then
    fail "Metadata-only manifests require publish-metadata-only."
  fi
  manifest_version="$(
    jq -er '.release.version | select(type == "string" and length > 0)' "$manifest_path"
  )" || fail "The publish manifest does not contain a release version."
  [[ "$manifest_version" == "$confirmed_version" ]] \
    || fail "Confirmed version '${confirmed_version}' does not match manifest version '${manifest_version}'."
  validate_shipping_marketing_versions "$confirmed_version"
  require_app_store_credentials

  journal_path="$(dirname "$manifest_path")/publish-journal.json"
  run_app_store_connect_tool publish \
    --manifest "$manifest_path" \
    --confirm-version "$confirmed_version" \
    --journal "$journal_path"

  echo "App Store release ${confirmed_version} was published and verified."
  echo "Publish journal: ${journal_path}"
}

command_publish_metadata_only() {
  local manifest_path=""
  local confirmed_source_version=""
  local confirmed_version=""
  local confirmed_manifest_digest=""
  local manifest_version
  local manifest_source_version
  local manifest_digest
  local journal_path

  while (( $# > 0 )); do
    case "$1" in
      --manifest)
        (( $# >= 2 )) || usage_error "--manifest requires a value."
        manifest_path="$(absolute_path "$2")"
        shift 2
        ;;
      --confirm-source-version)
        (( $# >= 2 )) || usage_error "--confirm-source-version requires a value."
        confirmed_source_version="$2"
        shift 2
        ;;
      --confirm-version)
        (( $# >= 2 )) || usage_error "--confirm-version requires a value."
        confirmed_version="$2"
        shift 2
        ;;
      --confirm-manifest-digest)
        (( $# >= 2 )) || usage_error "--confirm-manifest-digest requires a value."
        confirmed_manifest_digest="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage_error "Unknown publish-metadata-only option: $1"
        ;;
    esac
  done

  [[ -n "$manifest_path" ]] || usage_error "publish-metadata-only requires --manifest."
  [[ -n "$confirmed_source_version" ]] \
    || usage_error "publish-metadata-only requires --confirm-source-version."
  [[ -n "$confirmed_version" ]] \
    || usage_error "publish-metadata-only requires --confirm-version."
  [[ -n "$confirmed_manifest_digest" ]] \
    || usage_error "publish-metadata-only requires --confirm-manifest-digest."
  validate_version_string "$confirmed_source_version"
  validate_version_string "$confirmed_version"
  validate_sha256_string "$confirmed_manifest_digest"
  [[ "$confirmed_source_version" != "$confirmed_version" ]] \
    || usage_error "Confirmed source and target versions must differ."

  require_readable_file "Publish manifest" "$manifest_path"
  manifest_path="$(realpath "$manifest_path")" \
    || fail "Publish manifest could not be resolved: ${manifest_path}"
  case "$manifest_path" in
    "${repository_root}/.build/AppStoreRelease-MetadataOnly-"*/publish-manifest.json)
      ;;
    *)
      fail "Metadata-only publish requires a reviewed manifest from .build/AppStoreRelease-MetadataOnly-*: ${manifest_path}"
      ;;
  esac
  [[ "$(jq -r '.captureMetadata.mode // empty' "$manifest_path")" == "metadata-only" ]] \
    || fail "publish-metadata-only requires a metadata-only manifest."

  manifest_version="$(
    jq -er '.release.version | select(type == "string" and length > 0)' "$manifest_path"
  )" || fail "The publish manifest does not contain a release version."
  manifest_source_version="$(
    jq -er '.captureMetadata.expectedSourceVersion | select(type == "string" and length > 0)' \
      "$manifest_path"
  )" || fail "The metadata-only manifest does not contain its reviewed source version."
  manifest_digest="$(
    jq -er '.manifestDigest | select(type == "string" and length == 64)' "$manifest_path"
  )" || fail "The publish manifest does not contain its reviewed digest."
  [[ "$manifest_version" == "$confirmed_version" ]] \
    || fail "Confirmed version '${confirmed_version}' does not match manifest version '${manifest_version}'."
  [[ "$manifest_source_version" == "$confirmed_source_version" ]] \
    || fail "Confirmed source '${confirmed_source_version}' does not match manifest source '${manifest_source_version}'."
  [[ "$manifest_digest" == "$confirmed_manifest_digest" ]] \
    || fail "Confirmed digest does not match manifest digest '${manifest_digest}'."

  validate_shipping_marketing_versions "$confirmed_version"
  require_app_store_credentials

  journal_path="$(dirname "$manifest_path")/metadata-only-publish-journal.json"
  run_app_store_connect_tool publish-metadata-only \
    --manifest "$manifest_path" \
    --locales-config "$locale_configuration_path" \
    --expected-source-version "$confirmed_source_version" \
    --confirm-version "$confirmed_version" \
    --confirm-manifest-digest "$confirmed_manifest_digest" \
    --journal "$journal_path"

  echo "Metadata-only App Store release ${confirmed_version} was published and verified."
  echo "Inherited source: ${confirmed_source_version}"
  echo "Publish journal: ${journal_path}"
  echo "Screenshots, App Info, builds, and review submission were not mutated."
}

invocation_directory="$PWD"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "${script_directory}/../.." && pwd -P)"
locale_configuration_path="${script_directory}/app-store-release-locales.json"
screenshot_capture_script="${script_directory}/capture-app-store-screenshots.sh"
screenshot_test_plan_path="${repository_root}/AppStoreScreenshots.xctestplan"
tool_package_path="${script_directory}/AppStoreConnectTool"
tool_scratch_path="${repository_root}/.build/AppStoreConnectTool"
tool_module_cache_path="${tool_scratch_path}/ModuleCache"
tool_cache_path="${tool_scratch_path}/Cache"
tool_config_path="${tool_scratch_path}/Configuration"
tool_security_path="${tool_scratch_path}/Security"
screenshot_derived_data_path="${repository_root}/.build/AppStoreScreenshotDerivedData"
project_path="${repository_root}/Surround.xcodeproj"

readonly invocation_directory
readonly script_directory
readonly repository_root
readonly locale_configuration_path
readonly screenshot_capture_script
readonly screenshot_test_plan_path
readonly tool_package_path
readonly tool_scratch_path
readonly tool_module_cache_path
readonly tool_cache_path
readonly tool_config_path
readonly tool_security_path
readonly screenshot_derived_data_path
readonly project_path

require_command dirname
require_command git
require_command jq
require_command realpath
require_command swift
validate_locale_configuration
[[ -f "${tool_package_path}/Package.swift" ]] \
  || fail "App Store Connect tool package was not found: ${tool_package_path}"
[[ -x "$screenshot_capture_script" ]] \
  || fail "Screenshot capture script is not executable: ${screenshot_capture_script}"
[[ -d "$project_path" ]] \
  || fail "Xcode project was not found: ${project_path}"

(( $# > 0 )) || usage_error "A command is required."
command_name="$1"
shift

case "$command_name" in
  init)
    command_init "$@"
    ;;
  validate)
    require_command xcodebuild
    command_validate "$@"
    ;;
  prepare)
    require_command xcodebuild
    command_prepare "$@"
    ;;
  prepare-metadata-only)
    require_command xcodebuild
    command_prepare_metadata_only "$@"
    ;;
  publish)
    require_command xcodebuild
    command_publish "$@"
    ;;
  publish-metadata-only)
    require_command xcodebuild
    command_publish_metadata_only "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage_error "Unknown command: ${command_name}"
    ;;
esac
