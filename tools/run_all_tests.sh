#!/usr/bin/env sh
## Runs every test suite, sequentially, and reports one line each.
##
##   sh tools/run_all_tests.sh            # run everything
##   sh tools/run_all_tests.sh mimic      # run suites whose name matches "mimic"
##   GODOT=/path/to/godot sh tools/run_all_tests.sh
##
## Sequential on purpose. These suites each start their own headless Godot and
## some drive a physics tree; running them concurrently made output interleave
## and starved runs until the batch was cut off mid-suite.
##
## ROBUSTNESS. Each suite runs as its own process with a timeout, writing to a
## file in a temp directory, and is only parsed AFTER it finishes. The earlier
## version captured each suite's output in a shell variable, which meant a run
## killed part-way through (or a hung Godot) silently reduced the printed summary
## - a truncated file read as a suite that simply did not exist. Here a timeout
## is reported as a FAIL, and every suite always produces exactly one line.
##
## Exits non-zero if any suite fails, so this is safe to gate a commit on.

set -u

GODOT="${GODOT:-godot}"
FILTER="${1:-}"

SUITES="check_layout test_monster_db test_enemy_core test_mimic test_smoke \
test_player_damage test_trap_slow test_trap_cycle test_chest_slash"

# Seconds before a suite is declared hung and failed.
TIMEOUT="${TIMEOUT:-300}"

# Temp dir, cleaned up on exit so a crashed run does not leave logs behind.
TMP=$(mktemp -d 2>/dev/null || echo ".testlogs")
mkdir -p "$TMP"
cleanup() { rm -rf "$TMP" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

total=0
failed=0
ran=0
timed_out=0

for suite in $SUITES; do
    if [ -n "$FILTER" ]; then
        case "$suite" in
            *"$FILTER"*) ;;
            *) continue ;;
        esac
    fi
    if [ ! -f "tools/$suite.gd" ]; then
        printf '%-5s %-20s %6s  %s\n' "SKIP" "$suite" "n/a" "tools/$suite.gd not found"
        continue
    fi

    log="$TMP/$suite.log"
    # Own process, own timeout, own file. Nothing is captured in a variable,
    # so a suite that dies cannot corrupt the rest of the summary.
    if command -v timeout >/dev/null 2>&1; then
        timeout "$TIMEOUT" "$GODOT" --headless --path . \
            --script "res://tools/$suite.gd" >"$log" 2>&1
        code=$?
    else
        "$GODOT" --headless --path . --script "res://tools/$suite.gd" \
            >"$log" 2>&1
        code=$?
    fi
    out=$(cat "$log" 2>/dev/null)

    result=$(printf '%s' "$out" | grep -o 'RESULT:.*' | head -1)

    # A suite that never ran must never read as a pass. Godot prints a compile
    # or parse error and exits without printing RESULT; without this check a
    # broken build looked identical to a green one.
    broken=$(printf '%s' "$out" | grep -c \
        'SCRIPT ERROR\|Parse Error\|Failed to load script')
    if [ "$broken" -gt 0 ]; then
        result="RESULT: compile error ($broken error lines)"
    elif [ "$code" -eq 124 ]; then
        result="RESULT: timed out after ${TIMEOUT}s"
    elif [ -z "$result" ]; then
        result="RESULT: no result line (exit $code)"
    fi

    n=$(printf '%s' "$out" | grep -o 'assertions *: [0-9]*' | head -1 \
        | grep -o '[0-9]*')
    if [ -z "$n" ]; then
        # No assertion counter at all. "0" would make a suite that measured
        # nothing look identical to one that measured nothing on purpose.
        count="n/a"
    else
        count=$n
        total=$((total + n))
    fi

    case "$result" in
        "RESULT: OK"*) status=PASS ;;
        *)
            status=FAIL
            failed=$((failed + 1))
            case "$result" in
                *timed*) timed_out=$((timed_out + 1)) ;;
            esac
            ;;
    esac
    ran=$((ran + 1))
    printf '%-5s %-20s %6s  %s\n' \
        "$status" "$suite" "$count" "${result#RESULT: }"

    if [ "$status" = "FAIL" ]; then
        printf '%s' "$out" | grep 'FAIL:' | sed 's/^/        /'
    fi
done

echo ""
echo "suites: $ran   passed: $((ran - failed))   failed: $failed (timeouts: $timed_out)"
echo "assertions: $total"
[ "$failed" -eq 0 ] || exit 1
exit 0