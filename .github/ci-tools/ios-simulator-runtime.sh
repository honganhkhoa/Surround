#!/usr/bin/env bash

# Resolve one available iOS Simulator runtime by its exact identifier, version,
# or display name. The selected record is emitted as tab-separated
# identifier/version/name fields.
resolve_available_ios_runtime() {
  local selector="$1"

  xcrun simctl list --json runtimes \
    | jq -r \
      --arg selector "$selector" '
        [
          .runtimes[]
          | select(.isAvailable == true)
          | select(.identifier | contains(".SimRuntime.iOS-"))
          | select(
              .identifier == $selector
              or .version == $selector
              or .name == $selector
            )
        ]
        | first
        | if . == null then
            empty
          else
            [.identifier, .version, .name] | @tsv
          end
      '
}
