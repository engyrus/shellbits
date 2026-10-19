#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export PATH="$REPO_ROOT/bin:$PATH"
    unset SHELLBITS_HUNT_HOME
    unset SHELLBITS_HUNT_EDITOR
    unset SHELLBITS_EDITOR
    unset EDITOR
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

strip_ansi() {
    sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g'
}

@test "hunt finds both filename and content matches (with matched line) separated by a blank line" {
    mkdir -p "$TEST_DIR/sub"
    echo "this file mentions TARGET_TERM inside" > "$TEST_DIR/sub/other.txt"
    touch "$TEST_DIR/target_term_two.log"

    run hunt "target_term" "$TEST_DIR"
    [ "$status" -eq 0 ]

    clean_output="$(printf '%s' "$output" | strip_ansi)"
    expected="$TEST_DIR/target_term_two.log

$TEST_DIR/sub/other.txt:this file mentions TARGET_TERM inside"
    [ "$clean_output" = "$expected" ]
}

@test "hunt colors the search term in both filename and content sections" {
    mkdir -p "$TEST_DIR/sub"
    echo "line with needle here" > "$TEST_DIR/sub/other.txt"
    touch "$TEST_DIR/my_needle_file.txt"

    run hunt "needle" "$TEST_DIR"
    [ "$status" -eq 0 ]

    # Line 1 is filename result, Line 2 is blank, Line 3 is content result
    line1="$(printf '%s\n' "$output" | sed -n '1p')"
    line2="$(printf '%s\n' "$output" | sed -n '2p')"
    line3="$(printf '%s\n' "$output" | sed -n '3p')"

    [ "$line2" = "" ]
    # Verify both line1 (filename) and line3 (content) contain ANSI color escape sequences
    [[ "$line1" == *$'\x1b['* ]]
    [[ "$line3" == *$'\x1b['* ]]
}

@test "hunt searches case-insensitively for both filenames and contents" {
    echo "nothing" > "$TEST_DIR/MixedCaseNeedle.txt"
    echo "Contains mIxEdCaSeNeEdLe here" > "$TEST_DIR/notes.txt"

    run hunt "mixedcaseneedle" "$TEST_DIR"
    [ "$status" -eq 0 ]

    clean_output="$(printf '%s' "$output" | strip_ansi)"
    expected="$TEST_DIR/MixedCaseNeedle.txt

$TEST_DIR/notes.txt:Contains mIxEdCaSeNeEdLe here"
    [ "$clean_output" = "$expected" ]
}

@test "hunt performs literal search without regex or glob expansion" {
    echo "plain text" > "$TEST_DIR/file_[a-z]*.txt"
    echo "plain text" > "$TEST_DIR/file_abc.txt"
    echo "literal [a-z]* match" > "$TEST_DIR/content_literal.txt"
    echo "regex a123 match" > "$TEST_DIR/content_regex.txt"

    run hunt "[a-z]*" "$TEST_DIR"
    [ "$status" -eq 0 ]

    clean_output="$(printf '%s' "$output" | strip_ansi)"
    expected="$TEST_DIR/file_[a-z]*.txt

$TEST_DIR/content_literal.txt:literal [a-z]* match"
    [ "$clean_output" = "$expected" ]
}

@test "hunt prints trailing blank line after filename section even when content section is empty" {
    mkdir -p "$TEST_DIR/sub"
    echo "unrelated" > "$TEST_DIR/sub/only_name_match.txt"

    out_file="$TEST_DIR/out.txt"
    hunt "only_name_match" "$TEST_DIR/sub" > "$out_file"

    # File should have the matched path on line 1 and an empty line 2 (2 lines total)
    line_count="$(wc -l < "$out_file" | tr -d ' ')"
    [ "$line_count" -eq 2 ]
    [ "$(sed -n '1p' "$out_file" | strip_ansi)" = "$TEST_DIR/sub/only_name_match.txt" ]
    [ "$(sed -n '2p' "$out_file")" = "" ]
}

@test "hunt does not print a leading blank line when only content matches exist" {
    mkdir -p "$TEST_DIR/sub"
    echo "secret_content_token" > "$TEST_DIR/sub/plain.txt"

    out_file="$TEST_DIR/out.txt"
    hunt "secret_content_token" "$TEST_DIR/sub" > "$out_file"

    line_count="$(wc -l < "$out_file" | tr -d ' ')"
    [ "$line_count" -eq 1 ]
    [ "$(sed -n '1p' "$out_file" | strip_ansi)" = "$TEST_DIR/sub/plain.txt:secret_content_token" ]
}

@test "hunt defaults to current directory when no directory arg and SHELLBITS_HUNT_HOME is unset" {
    mkdir -p "$TEST_DIR/work"
    echo "hello needle" > "$TEST_DIR/work/doc.txt"
    cd "$TEST_DIR/work"

    run hunt "needle"
    [ "$status" -eq 0 ]
    clean_output="$(printf '%s' "$output" | strip_ansi)"
    [ "$clean_output" = "./doc.txt:hello needle" ]
}

@test "hunt uses SHELLBITS_HUNT_HOME when directory argument is omitted" {
    mkdir -p "$TEST_DIR/hunt_home" "$TEST_DIR/other"
    echo "found in hunt home" > "$TEST_DIR/hunt_home/item.txt"
    cd "$TEST_DIR/other"

    export SHELLBITS_HUNT_HOME="$TEST_DIR/hunt_home"
    run hunt "found in hunt home"
    [ "$status" -eq 0 ]
    clean_output="$(printf '%s' "$output" | strip_ansi)"
    [ "$clean_output" = "$TEST_DIR/hunt_home/item.txt:found in hunt home" ]
}

@test "hunt explicit directory argument overrides SHELLBITS_HUNT_HOME" {
    mkdir -p "$TEST_DIR/hunt_home" "$TEST_DIR/explicit"
    echo "shared_token" > "$TEST_DIR/hunt_home/home_file.txt"
    echo "shared_token" > "$TEST_DIR/explicit/explicit_file.txt"

    export SHELLBITS_HUNT_HOME="$TEST_DIR/hunt_home"
    run hunt "shared_token" "$TEST_DIR/explicit"
    [ "$status" -eq 0 ]
    clean_output="$(printf '%s' "$output" | strip_ansi)"
    [ "$clean_output" = "$TEST_DIR/explicit/explicit_file.txt:shared_token" ]
}

@test "hunt skips all hidden directories by default and ignores binary files" {
    mkdir -p "$TEST_DIR/.hidden" "$TEST_DIR/.git" "$TEST_DIR/visible"
    echo "needle_token" > "$TEST_DIR/.hidden/needle_token_hidden.txt"
    echo "needle_token" > "$TEST_DIR/.git/needle_token_git.txt"
    printf 'binary\x00needle_token\n' > "$TEST_DIR/visible/binary.bin"
    echo "needle_token" > "$TEST_DIR/visible/clean.txt"

    run hunt "needle_token" "$TEST_DIR"
    [ "$status" -eq 0 ]
    clean_output="$(printf '%s' "$output" | strip_ansi)"
    [ "$clean_output" = "$TEST_DIR/visible/clean.txt:needle_token" ]
}

@test "hunt --all searches hidden directories but still skips .git directories" {
    mkdir -p "$TEST_DIR/.hidden" "$TEST_DIR/.git" "$TEST_DIR/visible"
    echo "needle_token" > "$TEST_DIR/.hidden/needle_token_hidden.txt"
    echo "needle_token" > "$TEST_DIR/.git/needle_token_git.txt"
    echo "needle_token" > "$TEST_DIR/visible/clean.txt"

    run hunt --all "needle_token" "$TEST_DIR"
    [ "$status" -eq 0 ]
    clean_output="$(printf '%s' "$output" | strip_ansi)"
    expected="$TEST_DIR/.hidden/needle_token_hidden.txt

$TEST_DIR/.hidden/needle_token_hidden.txt:needle_token
$TEST_DIR/visible/clean.txt:needle_token"
    [ "$clean_output" = "$expected" ]
}

@test "hunt --edit prints results and opens all found files in editor" {
    mkdir -p "$TEST_DIR/search"
    echo "unrelated" > "$TEST_DIR/search/alpha_name.txt"
    echo "contains alpha line 1" > "$TEST_DIR/search/content_only.txt"
    echo "contains alpha line 2" >> "$TEST_DIR/search/content_only.txt"
    echo "alpha in both" > "$TEST_DIR/search/alpha_both.txt"

    editor_log="$TEST_DIR/editor_args.log"
    mock_editor="$TEST_DIR/mock_editor.sh"
    cat <<EOF > "$mock_editor"
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$editor_log"
EOF
    chmod +x "$mock_editor"

    export SHELLBITS_HUNT_EDITOR="$mock_editor"
    run hunt --edit "alpha" "$TEST_DIR/search"
    [ "$status" -eq 0 ]

    # Verify results were still printed
    clean_output="$(printf '%s' "$output" | strip_ansi)"
    expected_output="$TEST_DIR/search/alpha_both.txt
$TEST_DIR/search/alpha_name.txt

$TEST_DIR/search/alpha_both.txt:alpha in both
$TEST_DIR/search/content_only.txt:contains alpha line 1
$TEST_DIR/search/content_only.txt:contains alpha line 2"
    [ "$clean_output" = "$expected_output" ]

    # Verify all unique found files were passed to the editor
    expected_files="$TEST_DIR/search/alpha_both.txt
$TEST_DIR/search/alpha_name.txt
$TEST_DIR/search/content_only.txt"
    [ "$(cat "$editor_log")" = "$expected_files" ]
}

@test "hunt --edit respects editor variable precedence and defaults to pico" {
    mkdir -p "$TEST_DIR/search" "$TEST_DIR/bin"
    echo "match_me" > "$TEST_DIR/search/file.txt"

    which_log="$TEST_DIR/which_editor.log"

    for name in hunt_ed sb_ed std_ed pico; do
        cat <<EOF > "$TEST_DIR/bin/$name"
#!/usr/bin/env bash
echo "$name:\$*" > "$which_log"
EOF
        chmod +x "$TEST_DIR/bin/$name"
    done

    export PATH="$TEST_DIR/bin:$PATH"

    # 1. None set -> defaults to pico
    unset SHELLBITS_HUNT_EDITOR SHELLBITS_EDITOR EDITOR
    run hunt --edit "match_me" "$TEST_DIR/search"
    [ "$status" -eq 0 ]
    [ "$(cat "$which_log")" = "pico:$TEST_DIR/search/file.txt" ]

    # 2. EDITOR set -> uses EDITOR
    export EDITOR="std_ed"
    run hunt --edit "match_me" "$TEST_DIR/search"
    [ "$status" -eq 0 ]
    [ "$(cat "$which_log")" = "std_ed:$TEST_DIR/search/file.txt" ]

    # 3. SHELLBITS_EDITOR set -> overrides EDITOR
    export SHELLBITS_EDITOR="sb_ed"
    run hunt --edit "match_me" "$TEST_DIR/search"
    [ "$status" -eq 0 ]
    [ "$(cat "$which_log")" = "sb_ed:$TEST_DIR/search/file.txt" ]

    # 4. SHELLBITS_HUNT_EDITOR set -> overrides SHELLBITS_EDITOR and EDITOR
    export SHELLBITS_HUNT_EDITOR="hunt_ed"
    run hunt --edit "match_me" "$TEST_DIR/search"
    [ "$status" -eq 0 ]
    [ "$(cat "$which_log")" = "hunt_ed:$TEST_DIR/search/file.txt" ]
}

@test "hunt supports -- to search for queries starting with a dash" {
    echo "has -v flag inside" > "$TEST_DIR/flags.txt"

    run hunt -- "-v" "$TEST_DIR"
    [ "$status" -eq 0 ]
    clean_output="$(printf '%s' "$output" | strip_ansi)"
    [ "$clean_output" = "$TEST_DIR/flags.txt:has -v flag inside" ]
}

@test "hunt reports error on nonexistent directory or invalid arguments" {
    run hunt
    [ "$status" -ne 0 ]

    run hunt "query" "$TEST_DIR/does_not_exist"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "No such file or directory" ]]

    run hunt "one" "two" "three"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "too many arguments" ]]
}
