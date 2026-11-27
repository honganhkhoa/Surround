#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage:" >&2
  echo "  $0 derived-data-path <simulator UDID>" >&2
  echo "  $0 <build|preflight|main|main-1|main-2|main-3|profile|profile-1|profile-2|profile-3|messages|messages-1|messages-2|messages-3|messages-4|activity|activity-bar|game-control|composer|continuity|continuity-1|continuity-2> <simulator UDID> <result label>" >&2
}

if (( $# == 0 )); then
  usage
  exit 64
fi
phase="$1"
case "$phase" in
  derived-data-path)
    if (( $# != 2 )); then
      usage
      exit 64
    fi
    ;;
  build|preflight|main|main-1|main-2|main-3|profile|profile-1|profile-2|profile-3|messages|messages-1|messages-2|messages-3|messages-4|activity|activity-bar|game-control|composer|continuity|continuity-1|continuity-2)
    if (( $# != 3 )); then
      usage
      exit 64
    fi
    ;;
  *)
    echo "Expected phase derived-data-path, build, preflight, main, main-1, main-2, main-3, profile, profile-1, profile-2, profile-3, messages, messages-1, messages-2, messages-3, messages-4, activity, activity-bar, game-control, composer, continuity, continuity-1, or continuity-2; received: $phase" >&2
    exit 64
    ;;
esac

simulator_id="$2"
if ! [[ "$simulator_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
  echo "Expected a simulator UDID, received: $simulator_id" >&2
  exit 64
fi

# The own-game navigation journey's cycle opens three games, switches once and
# goes Back four times. It takes 65 to 80 seconds on a local iPad simulator, and
# hosted runners take about twice as long, so its default 20 cycles would far
# outlast the 15-minute test allowance below. In four cycles every open meets
# each of the in-game control's four states once; a caller can still set
# another count.
export TEST_RUNNER_SURROUND_UI_OWN_GAME_NAVIGATION_CYCLES="${TEST_RUNNER_SURROUND_UI_OWN_GAME_NAVIGATION_CYCLES:-4}"

if [[ -n "${RUNNER_TEMP:-}" ]]; then
  derived_data_root="$RUNNER_TEMP"
else
  derived_data_root="${TMPDIR:-/private/tmp}"
fi
derived_data_path="${derived_data_root%/}/Surround-iPadUITests-${simulator_id}"

if [[ "$phase" == "derived-data-path" ]]; then
  printf '%s\n' "$derived_data_path"
  exit 0
fi

result_label="$3"
if ! [[ "$result_label" =~ ^[[:alnum:]._-]+$ ]]; then
  echo "Expected an alphanumeric result label, received: $result_label" >&2
  exit 64
fi

readonly test_target="SurroundUITests"
readonly test_class="SurroundUITests"
readonly test_source="SurroundUITests/${test_class}.swift"
readonly test_case="${test_target}/${test_class}"
readonly profile_test_class="ProfileUITests"
readonly profile_test_source="SurroundUITests/${profile_test_class}.swift"
readonly profile_test_case="${test_target}/${profile_test_class}"
readonly messages_test_class="MessagesNavigationUITests"
readonly messages_test_source="SurroundUITests/${messages_test_class}.swift"
readonly messages_test_case="${test_target}/${messages_test_class}"
readonly continuity_test_class="GameContinuityUITests"
readonly continuity_test_source="SurroundUITests/${continuity_test_class}.swift"
readonly continuity_test_case="${test_target}/${continuity_test_class}"
# CI runs main in three parts (see below). Besides its share of the
# SurroundUITests class, part 2 runs these whole classes, so that the three
# parts take similar time; main's other classes stay in part 1. Part 3 runs
# only its share of SurroundUITests: that share holds the own-game navigation
# journey, which took 9 to 14 minutes on hosted iPads at four cycles.
readonly main_part_classes=(
  LocalizationUITests:2
)
readonly keyboard_preflight_test_name="testKeyboardPreflightSupportsComposerInput"

# These tests intentionally focus a chat composer or exercise layout while that
# composer owns keyboard focus. Isolate them from the main suite so an XCTest
# keyboard-animation quiescence failure cannot slow unrelated journeys. The
# Messages and continuity classes have their own phases and time budgets.
readonly composer_test_names=(
  testCompactChatCanHideAndShowMainBoard
  testTheZenCircleRestoresCompactChatBoard
  testCompactVariationSharingHidesMainBoardAndShowsComposerPreview
  testVariationSharingDraftSurvivesChatSelection
  testVariationSharingDraftSurvivesAnalyzeNavigation
  testVariationSharingDraftSurvivesZenModeRoundTrip
  testSharingAnotherVariationReplacesDraft
  testAnalyzeShareComposerAutomaticallyFocusesAndAcceptsName
  testShareVariationUsesSelectedChannelAndStaysInChatAfterSending
  testAnalyzeTrunkMarkersShareWithoutLeakingToLiveBoard
  testPrivateMessageProfileEntriesPreserveConversationDraft
)
# Whole classes that belong with them: the moderator cover focuses its reply
# field on every rise in regular height, so each of its journeys does.
readonly composer_test_classes=(
  SuperchatCoverUITests
)
# The Activity list's journeys, its conversations included, have their own
# phase, which main skips: the Messages and composer steps have no time left
# for them.
readonly activity_test_classes=(
  ActivityListUITests
  ActivityConversationUITests
)
# The Activity bar's journeys have their own phase too, which main skips. CI
# runs it in the Messages jobs after the Activity phase, under the game
# control and continuity phases' deadline. With the iPad sidebar journey the
# class takes about ten and a half minutes on a local iPadOS 26 simulator, so
# at a hosted runner's usual twice that it would need about 22.6 of the
# Activity phase's 26 minutes, leaving no room for the supervisor to rerun the
# sidebar journey, about nine and a half minutes there. 41 minutes hold the
# class and that rerun even at 2.3 times the local pace.
readonly activity_bar_test_classes=(
  ActivityBarUITests
)
# The in-game control's journeys have their own phase too, which main skips.
# CI runs it in the profile jobs, which finish well before the main jobs.
readonly game_control_test_classes=(
  GameControlUITests
)

# xcodebuild accepts an unknown -only-testing or -skip-testing selector and
# exits successfully after running zero tests. Keep the isolation manifest tied
# to its Swift declarations so a rename cannot silently move a composer test
# into main, leave the profile, Messages, Activity, Activity bar, game
# control, or continuity phase empty, or move a whole class between main's
# parts.
classes_and_sources=(
  "${test_class}:${test_source}"
  "${profile_test_class}:${profile_test_source}"
  "${messages_test_class}:${messages_test_source}"
  "${continuity_test_class}:${continuity_test_source}"
)
for class_and_part in "${main_part_classes[@]}"; do
  classes_and_sources+=("${class_and_part%%:*}:SurroundUITests/${class_and_part%%:*}.swift")
done
for whole_test_class in "${composer_test_classes[@]}" "${activity_test_classes[@]}" \
  "${activity_bar_test_classes[@]}" "${game_control_test_classes[@]}"; do
  classes_and_sources+=("${whole_test_class}:SurroundUITests/${whole_test_class}.swift")
done
for class_and_source in "${classes_and_sources[@]}"; do
  class_name="${class_and_source%%:*}"
  class_source="${class_and_source#*:}"
  test_class_count="$(
    grep -Ec \
      "^[[:space:]]*final[[:space:]]+class[[:space:]]+${class_name}[[:space:]]*:[[:space:]]*SurroundJourneyUITestCase[[:space:]]*\\{" \
      "$class_source" \
      || true
  )"
  if [[ "$test_class_count" != "1" ]]; then
    echo "Expected exactly one ${class_name} declaration in ${class_source}. Update the isolated UI-test manifest when renaming or moving it." >&2
    exit 1
  fi
  test_declaration_count="$(
    grep -Ec \
      "^[[:space:]]*func[[:space:]]+test[[:alnum:]_]*[[:space:]]*\\(" \
      "$class_source" \
      || true
  )"
  if [[ "$test_declaration_count" == "0" ]]; then
    echo "Expected test declarations in ${class_source}; ${class_name} cannot have an empty UI-test phase." >&2
    exit 1
  fi
done

for test_name in "$keyboard_preflight_test_name" "${composer_test_names[@]}"; do
  declaration_count="$(
    grep -Ec \
      "^[[:space:]]*func[[:space:]]+${test_name}[[:space:]]*\\([[:space:]]*\\)" \
      "$test_source" \
      || true
  )"
  if [[ "$declaration_count" != "1" ]]; then
    echo "Expected exactly one ${test_name} declaration in ${test_source}. Update the isolated UI-test manifest when renaming or moving it." >&2
    exit 1
  fi
done

# Each part, and the Activity, Activity bar, game control, composer and
# continuity phases, run under supervise-ipad-ui-test-part.py. CI gives each
# main, profile and Messages part step, and the composer step, 50 minutes; at
# 46 the supervisor interrupts xcodebuild, which then has time to write its
# result bundle and the supervisor its evidence: at most 1:45 of signal grace
# and under a minute of bounded collection. The game control and Activity bar
# steps, and each of continuity's two part steps, get 45 minutes, and the
# Activity step gets 30, with the same margin. A test that a simulator crash
# killed, or that failed only because XCTest timed out on a UI query, is rerun
# once, within the same deadline.
readonly part_deadline_seconds=$((46 * 60))
readonly isolated_phase_deadline_seconds=$((41 * 60))
readonly activity_phase_deadline_seconds=$((26 * 60))

# The main, profile, Messages and continuity phases each outgrew one CI step,
# so CI runs main and profile in three parts, Messages in four and continuity
# in two. Of N parts, part K > 1 runs every Nth test declaration of the
# phase's class, starting with the Kth (the SurroundUITests class for main,
# less the tests main skips), plus, for main, its whole classes listed above;
# part 1 runs the rest of the phase by skipping exactly those, so a test this
# scan misses still runs in part 1. Alternating declarations keeps the parts
# balanced as tests are added.
part_test_names() {
  local source="$1" part="$2" part_count="$3"
  grep -Eo "^[[:space:]]*func[[:space:]]+test[[:alnum:]_]*[[:space:]]*\\([[:space:]]*\\)" "$source" \
    | sed -E 's/^[[:space:]]*func[[:space:]]+//; s/[[:space:]]*\([[:space:]]*\)$//' \
    | awk -v part="$part" -v part_count="$part_count" 'NR % part_count == part % part_count'
}

is_excluded_from_main() {
  local excluded_name
  for excluded_name in "$keyboard_preflight_test_name" "${composer_test_names[@]}"; do
    if [[ "$1" == "$excluded_name" ]]; then
      return 0
    fi
  done
  return 1
}

select_main_tests() {
  selection_arguments=(
    "-only-testing:${test_target}"
    "-skip-testing:${test_case}/${keyboard_preflight_test_name}"
    "-skip-testing:${profile_test_case}"
    "-skip-testing:${messages_test_case}"
    "-skip-testing:${continuity_test_case}"
  )
  local composer_test_name whole_test_class
  for composer_test_name in "${composer_test_names[@]}"; do
    selection_arguments+=("-skip-testing:${test_case}/${composer_test_name}")
  done
  for whole_test_class in "${composer_test_classes[@]}" "${activity_test_classes[@]}" \
    "${activity_bar_test_classes[@]}" "${game_control_test_classes[@]}"; do
    selection_arguments+=("-skip-testing:${test_target}/${whole_test_class}")
  done
}

common_arguments=(
  -scheme Surround
  -project Surround.xcodeproj
  -configuration Debug
  -destination "platform=iOS Simulator,id=${simulator_id}"
  -derivedDataPath "$derived_data_path"
  -parallel-testing-enabled NO
)

# A UI test gets 15 minutes, and one that asks for more gets up to 20 in the
# main suite and the supervised phases: the own-game navigation journey asks
# for five minutes a cycle, and at four cycles took nearly 14 on a hosted
# iPadOS 18 runner.
readonly ui_test_allowance_seconds=900
readonly ui_test_maximum_allowance_seconds=1200

# Runs the selected tests under the supervisor into one result bundle; its
# failure evidence goes beside the bundle.
run_supervised_tests() {
  local deadline_seconds="$1" result_bundle="$2"
  shift 2
  python3 .github/ci-tools/supervise-ipad-ui-test-part.py \
    --simulator "$simulator_id" \
    --deadline-seconds "$deadline_seconds" \
    --diagnostics "${result_bundle%.xcresult}-Diagnostics" \
    -- \
    xcodebuild test-without-building \
    "${common_arguments[@]}" \
    "$@" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$ui_test_allowance_seconds" \
    -maximum-test-execution-time-allowance "$ui_test_maximum_allowance_seconds" \
    -resultBundlePath "$result_bundle"
}

# Two of the Activity bar's journeys need a docked software keyboard, and fail
# rather than pass when none shows. CI prefers a connected hardware keyboard
# (configure-ios-simulator-hardware-keyboard.sh), and iPadOS 18.6 keeps it
# through XCTest's typing, so no software keyboard shows there. The
# activity-bar phase therefore detaches the hardware keyboard for itself
# alone, on every iPadOS: it sets the booted simulator's
# GSEventHardwareKeyboardAttached notify state, whose low byte says that a
# hardware keyboard is attached, to 13369344, which clears that byte, and
# posts it. When the phase ends, whatever its tests did, it sets back the
# value it found and posts that. No preference changes, so the next boot
# starts from Simulator's own again, and a test the supervisor reruns after a
# simulator crash meets the keyboard of that boot. If the state can't be
# read, the phase warns and leaves the keyboard as it found it.
readonly hardware_keyboard_notification="GSEventHardwareKeyboardAttached"
readonly detached_hardware_keyboard_state=13369344
hardware_keyboard_found=""

hardware_keyboard_state() {
  xcrun simctl spawn "$simulator_id" notifyutil -g "$hardware_keyboard_notification" 2>/dev/null \
    | awk -v name="$hardware_keyboard_notification" '$1 == name && $2 ~ /^[0-9]+$/ { print $2 }'
}

set_hardware_keyboard_state() {
  xcrun simctl spawn "$simulator_id" notifyutil -s "$hardware_keyboard_notification" "$1" \
    && xcrun simctl spawn "$simulator_id" notifyutil -p "$hardware_keyboard_notification"
}

# The EXIT trap: it keeps the phase's exit status.
restore_hardware_keyboard() {
  [[ -n "$hardware_keyboard_found" ]] || return 0
  local after
  after="$(hardware_keyboard_state || true)"
  if set_hardware_keyboard_state "$hardware_keyboard_found" >/dev/null 2>&1; then
    echo "Put the hardware keyboard back: ${after:-unreadable} after the tests, set to ${hardware_keyboard_found}, now $(hardware_keyboard_state || true)."
  else
    echo "Warning: could not set the simulator's hardware keyboard state back to ${hardware_keyboard_found}; it reads ${after:-unreadable}." >&2
  fi
}

detach_hardware_keyboard() {
  local found
  found="$(hardware_keyboard_state || true)"
  if [[ -z "$found" ]]; then
    echo "Warning: could not read the simulator's hardware keyboard state, so it stays as found; the keyboard journeys fail if no docked software keyboard shows." >&2
    return 0
  fi
  hardware_keyboard_found="$found"
  trap restore_hardware_keyboard EXIT
  if set_hardware_keyboard_state "$detached_hardware_keyboard_state" >/dev/null 2>&1; then
    echo "Detached the hardware keyboard for the Activity bar journeys: found ${found}, set to ${detached_hardware_keyboard_state}, now $(hardware_keyboard_state || true)."
  else
    echo "Warning: could not detach the simulator's hardware keyboard (found ${found}); the keyboard journeys fail if no docked software keyboard shows." >&2
  fi
}

case "$phase" in
  build)
    echo "Building the shared iPad UI-test products."
    xcodebuild build-for-testing \
      "${common_arguments[@]}" \
      "-only-testing:${test_target}"
    ;;

  preflight)
    mkdir -p TestResults
    echo "Verifying that the selected iPad can focus the composer and accept complete keyboard input."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "-only-testing:${test_case}/${keyboard_preflight_test_name}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 300 \
      -maximum-test-execution-time-allowance 300 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-KeyboardPreflight.xcresult"
    ;;

  main)
    mkdir -p TestResults
    select_main_tests

    echo "Running the main iPad UI suite without profile, Messages, Activity, Activity bar, game control, composer, or continuity tests."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "${selection_arguments[@]}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance "$ui_test_allowance_seconds" \
      -maximum-test-execution-time-allowance "$ui_test_maximum_allowance_seconds" \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Main.xcresult"
    ;;

  profile)
    mkdir -p TestResults
    echo "Running the profile and friendship iPad UI journeys."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "-only-testing:${profile_test_case}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Profile.xcresult"
    ;;

  main-1|main-2|main-3|profile-1|profile-2|profile-3|messages-1|messages-2|messages-3|messages-4|continuity-1|continuity-2)
    mkdir -p TestResults
    part="${phase##*-}"
    part_deadline="$part_deadline_seconds"
    case "$phase" in
      main-*)
        part_count=3
        part_test_case="$test_case"
        part_test_source="$test_source"
        part_result_name="Main"
        ;;
      profile-*)
        part_count=3
        part_test_case="$profile_test_case"
        part_test_source="$profile_test_source"
        part_result_name="Profile"
        ;;
      continuity-*)
        # A continuity part keeps the whole phase's 45-minute step and its
        # 41-minute interrupt: half the tests leave room to rerun the
        # longest of them, about ten minutes on a hosted iPadOS 26 runner.
        part_count=2
        part_test_case="$continuity_test_case"
        part_test_source="$continuity_test_source"
        part_result_name="Continuity"
        part_deadline="$isolated_phase_deadline_seconds"
        ;;
      *)
        part_count=4
        part_test_case="$messages_test_case"
        part_test_source="$messages_test_source"
        part_result_name="Messages"
        ;;
    esac
    if [[ "$part" == "1" ]]; then
      if [[ "$phase" == main-* ]]; then
        select_main_tests
      else
        selection_arguments=("-only-testing:${part_test_case}")
      fi
      selector="-skip-testing"
      first_later_part=2
      last_later_part="$part_count"
    else
      selection_arguments=()
      selector="-only-testing"
      first_later_part="$part"
      last_later_part="$part"
    fi
    # Part 1 skips what every later part runs; a later part runs only its own.
    for (( later_part = first_later_part; later_part <= last_later_part; later_part++ )); do
      later_part_names=()
      while IFS= read -r test_name; do
        if [[ "$phase" == main-* ]] && is_excluded_from_main "$test_name"; then
          continue
        fi
        later_part_names+=("$test_name")
      done < <(part_test_names "$part_test_source" "$later_part" "$part_count")
      if (( ${#later_part_names[@]} == 0 )); then
        echo "Expected at least ${part_count} test declarations in ${part_test_source} to run it in ${part_count} parts." >&2
        exit 1
      fi
      for test_name in "${later_part_names[@]}"; do
        selection_arguments+=("${selector}:${part_test_case}/${test_name}")
      done
      if [[ "$phase" == main-* ]]; then
        for class_and_part in "${main_part_classes[@]}"; do
          if [[ "${class_and_part#*:}" == "$later_part" ]]; then
            selection_arguments+=("${selector}:${test_target}/${class_and_part%%:*}")
          fi
        done
      fi
    done

    echo "Running part ${part} of ${part_count} of the iPad ${part_result_name} UI tests."
    run_supervised_tests "$part_deadline" \
      "TestResults/SurroundUITests-${result_label}-${part_result_name}-${part}.xcresult" \
      "${selection_arguments[@]}"
    ;;

  messages)
    mkdir -p TestResults
    echo "Running the isolated iPad Messages navigation and conversation UI tests."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "-only-testing:${messages_test_case}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Messages.xcresult"
    ;;

  activity)
    mkdir -p TestResults
    selection_arguments=()
    for test_class_name in "${activity_test_classes[@]}"; do
      selection_arguments+=("-only-testing:${test_target}/${test_class_name}")
    done

    echo "Running the iPad Activity list and conversation UI tests."
    run_supervised_tests "$activity_phase_deadline_seconds" \
      "TestResults/SurroundUITests-${result_label}-Activity.xcresult" \
      "${selection_arguments[@]}"
    ;;

  activity-bar)
    mkdir -p TestResults
    selection_arguments=()
    for test_class_name in "${activity_bar_test_classes[@]}"; do
      selection_arguments+=("-only-testing:${test_target}/${test_class_name}")
    done

    detach_hardware_keyboard
    echo "Running the iPad Activity bar and root status UI tests."
    run_supervised_tests "$isolated_phase_deadline_seconds" \
      "TestResults/SurroundUITests-${result_label}-ActivityBar.xcresult" \
      "${selection_arguments[@]}"
    ;;

  game-control)
    mkdir -p TestResults
    selection_arguments=()
    for test_class_name in "${game_control_test_classes[@]}"; do
      selection_arguments+=("-only-testing:${test_target}/${test_class_name}")
    done

    echo "Running the iPad in-game control UI tests."
    run_supervised_tests "$isolated_phase_deadline_seconds" \
      "TestResults/SurroundUITests-${result_label}-GameControl.xcresult" \
      "${selection_arguments[@]}"
    ;;

  composer)
    mkdir -p TestResults
    selection_arguments=()
    for test_name in "${composer_test_names[@]}"; do
      selection_arguments+=("-only-testing:${test_case}/${test_name}")
    done
    for test_class_name in "${composer_test_classes[@]}"; do
      selection_arguments+=("-only-testing:${test_target}/${test_class_name}")
    done

    echo "Running the isolated iPad composer and keyboard UI tests."
    run_supervised_tests "$part_deadline_seconds" \
      "TestResults/SurroundUITests-${result_label}-Composer.xcresult" \
      "${selection_arguments[@]}"
    ;;

  continuity)
    mkdir -p TestResults
    echo "Running the iPad game layout and interaction continuity UI tests."
    run_supervised_tests "$isolated_phase_deadline_seconds" \
      "TestResults/SurroundUITests-${result_label}-Continuity.xcresult" \
      "-only-testing:${continuity_test_case}"
    ;;
esac
