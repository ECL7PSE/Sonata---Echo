#!/usr/bin/env sh
## Runs every test suite, sequentially, and reports one line each.
##
##   sh tools/run_all_tests.sh            # run everything
##   sh tools/run_all_tests.sh mimic      # run suites whose name matches "mimic"
##
## Sequential on purpose. These suites each start their own headless Godot and
## some drive a physics tree; running them concurrently made output interleave
## and, on this machine, starved runs until the batch was cut off mid-suite.
## A truncated file would otherwise be read as a FAIL that never happened.
##
## Exits non-zero if any suite fails, so this is safe to gate a commit on.

set -u

GODOT="${GODOT:-godot}"
FILTER="${1:-}"

# Godot's own output goes to stdout alongside ours; the script filters for the
# RESULT and assertion lines so the summary stays one line per suite.
SUITES="check_layout test_monster_db test_enemy_core test_mimic test_smoke \
test_player_damage test_trap_slow test_trap_cycle test_chest_slash"

total=0
failed=0
ran=0

for suite in $SUITES; do
    if [ -n "$FILTER" ]; then
        case "$suite" in
            *"$FILTER"*) ;;
            *) continue ;;
        esac
    fi
    if [ ! -f "tools/$suite.gd" ]; then
        echo "SKIP  $suite (tools/$suite.gd not found)"
        continue
    fi

    out="$("$GODOT" --headless --path . --script "res://tools/$suite.gd" 2>&1)"
    printf '%s' "$out" > "tools/.last_$suite.log"

    result=$(printf '%s' "$out" | grep -o 'RESULT:.*' | head -1)

    # A suite that never ran must never read as a pass. Godot prints a compile
    # or parse error and exits without printing RESULT; without this check the
    # summary showed "PASS" for a suite whose script had not loaded at all, and
    # a broken build looked identical to a green one.
    broken=$(printf '%s' "$out" | grep -c 'SCRIPT ERROR\|Parse Error\|Failed to load script')
    if [ "$broken" -gt 0 ]; then
        result="RESULT: compile error ($broken error lines)"
    elif [ -z "$result" ]; then
        result="RESULT: no result line (the run was cut off, not a failure)"
    fi
    n=$(printf '%s' "$out" | grep -o 'assertions *: [0-9]*' | head -1 \
        | grep -o '[0-9]*')
    if [ -z "$n" ]; then
        # No assertion counter at all. Printing "0" would make a suite that
        # measured nothing look identical to one that measured nothing AND
        # passed on purpose. "n/a" says the truth: this suite does not count.
        count="n/a"
    else
        count=$n
        total=$((total + n))
    fi
    ran=$((ran + 1))

    case "$result" in
        "RESULT: OK"*) status=PASS ;;
        *) status=FAIL; failed=$((failed + 1)) ;;
    esac
    printf '%-5s %-20s %6s  %s\n' \
        "$status" "$suite" "$count" "${result#RESULT: }"

    if [ "$status" = "FAIL" ]; then
        printf '%s' "$out" | grep 'FAIL:' | sed 's/^/        /'
    fi
done

echo ""
echo "suites: $ran   passed: $((ran - failed))   failed: $failed"
echo "assertions: $total"
[ "$failed" -eq 0 ] || exit 1
exit 0