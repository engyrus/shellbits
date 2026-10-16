#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export PATH="$REPO_ROOT/bin:$PATH"
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "yeet a normal file" {
    touch "$TEST_DIR/normal.txt"
    run yeet "$TEST_DIR/normal.txt"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_DIR/normal.txt" ]
}

@test "yeet multiple files" {
    touch "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt" "$TEST_DIR/file3.txt"
    run yeet "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt" "$TEST_DIR/file3.txt"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_DIR/file1.txt" ]
    [ ! -e "$TEST_DIR/file2.txt" ]
    [ ! -e "$TEST_DIR/file3.txt" ]
}

@test "yeet a directory" {
    mkdir -p "$TEST_DIR/somedir/nested"
    touch "$TEST_DIR/somedir/nested/file.txt"
    run yeet "$TEST_DIR/somedir"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_DIR/somedir" ]
}

@test "yeet a filename with spaces" {
    touch "$TEST_DIR/file with spaces.txt"
    run yeet "$TEST_DIR/file with spaces.txt"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_DIR/file with spaces.txt" ]
}

@test "yeet a nonexistent file reports error and exits nonzero" {
    run yeet "$TEST_DIR/nonexistent.txt"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "cannot yeet" ]]
}

@test "yeet a dangling symlink" {
    ln -s "$TEST_DIR/nonexistent_target" "$TEST_DIR/dangling_link"
    run yeet "$TEST_DIR/dangling_link"
    [ "$status" -eq 0 ]
    [ ! -L "$TEST_DIR/dangling_link" ]
}

@test "yeet refuses to delete ., .., and /" {
    cd "$TEST_DIR"
    run yeet .
    [ "$status" -ne 0 ]
    [[ "$output" =~ "refusing to delete" ]]

    run yeet ..
    [ "$status" -ne 0 ]
    [[ "$output" =~ "refusing to delete" ]]

    run yeet /
    [ "$status" -ne 0 ]
    [[ "$output" =~ "refusing to delete" ]]
}

@test "yeet --dry-run prints actions without creating or deleting anything" {
    mkdir -p "$TEST_DIR/dry_dir"
    touch "$TEST_DIR/dry_file.txt" "$TEST_DIR/dry_dir/subfile.txt"

    run yeet --dry-run "$TEST_DIR/dry_file.txt" "$TEST_DIR/dry_dir"
    [ "$status" -eq 0 ]

    # Verify nothing was moved or deleted
    [ -f "$TEST_DIR/dry_file.txt" ]
    [ -d "$TEST_DIR/dry_dir" ]
    [ -f "$TEST_DIR/dry_dir/subfile.txt" ]

    # Verify no temporary .yeet-* directory was created
    hidden_count=$(find "$TEST_DIR" -name '.yeet-*' | wc -l)
    [ "$hidden_count" -eq 0 ]

    # Verify action output describes what would occu
    [[ "$output" =~ "would move" ]]
    [[ "$output" =~ "would delete" ]]

    # Verify -n flag works identically
    run yeet -n "$TEST_DIR/dry_file.txt"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/dry_file.txt" ]
    [[ "$output" =~ "would move" ]]
}

@test "yeet reports partial failure exit status when some files exist and some do not" {
    touch "$TEST_DIR/valid.txt"
    run yeet "$TEST_DIR/valid.txt" "$TEST_DIR/missing.txt"
    [ "$status" -ne 0 ]
    [ ! -e "$TEST_DIR/valid.txt" ]
    [[ "$output" =~ "cannot yeet" ]]
}
