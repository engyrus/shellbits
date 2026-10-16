#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    # shellcheck source=shell/navbits.sh
    source "$REPO_ROOT/shell/navbits.sh"
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- up tests ---

@test "up default moves up 1 directory" {
    mkdir -p "$TEST_DIR/a/b"
    cd "$TEST_DIR/a/b"
    up
    [ "$PWD" = "$TEST_DIR/a" ]
}

@test "up N moves up N directories" {
    mkdir -p "$TEST_DIR/a/b/c/d"
    cd "$TEST_DIR/a/b/c/d"
    up 3
    [ "$PWD" = "$TEST_DIR/a" ]
}

@test "up stops at ~ when started in a subdirectory of ~" {
    FAKE_HOME="$(mktemp -d)"
    mkdir -p "$FAKE_HOME/sub1/sub2/sub3"
    cd "$FAKE_HOME/sub1/sub2/sub3"
    HOME="$FAKE_HOME" up 10
    [ "$PWD" = "$FAKE_HOME" ]
    rm -rf "$FAKE_HOME"
}

@test "up in ~ navigates toward /" {
    FAKE_HOME="$(mktemp -d)"
    cd "$FAKE_HOME"
    HOME="$FAKE_HOME" up 1
    [ "$PWD" = "$(dirname "$FAKE_HOME")" ]
    rm -rf "$FAKE_HOME"
}

@test "up stops at /" {
    cd "/tmp"
    up 50
    [ "$PWD" = "/" ]
}

@test "up rejects invalid arguments" {
    run up 0
    [ "$status" -ne 0 ]

    run up -1
    [ "$status" -ne 0 ]

    run up abc
    [ "$status" -ne 0 ]
}

# --- updir tests ---

@test "updir finds parent directory containing specified file or directory" {
    mkdir -p "$TEST_DIR/app/nested/deep"
    touch "$TEST_DIR/app/package.json"
    cd "$TEST_DIR/app/nested/deep"

    run updir package.json
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR/app" ]
    [ "$PWD" = "$TEST_DIR/app/nested/deep" ]

    run updir "*.json"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR/app" ]

    run updir nonexistent_file
    [ "$status" -ne 0 ]
}

@test "updir --name finds parent directory by name and supports wildcards" {
    mkdir -p "$TEST_DIR/myproject/src/components"
    cd "$TEST_DIR/myproject/src/components"

    run updir --name myproject
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR/myproject" ]

    run updir --name 'myproj*'
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR/myproject" ]
}

@test "updir --name errors when combined with --any or --all" {
    run updir --name proj --any file.txt
    [ "$status" -ne 0 ]
    [[ "$output" =~ "cannot combine --name with --any or --all" ]]

    run updir --any file.txt --name proj
    [ "$status" -ne 0 ]
    [[ "$output" =~ "cannot combine --name with --any or --all" ]]

    run updir --name proj --all file.txt
    [ "$status" -ne 0 ]
    [[ "$output" =~ "cannot combine --name with --any or --all" ]]

    run updir --all file.txt --name proj
    [ "$status" -ne 0 ]
    [[ "$output" =~ "cannot combine --name with --any or --all" ]]
}

@test "updir --any finds directory containing any named file or directory" {
    mkdir -p "$TEST_DIR/app/nested/deep"
    touch "$TEST_DIR/app/package.json"
    cd "$TEST_DIR/app/nested/deep"

    run updir --any Cargo.toml package.json
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR/app" ]

    run updir --any "*.json"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR/app" ]

    run updir --any Cargo.toml Makefile
    [ "$status" -ne 0 ]
}

@test "updir --all finds directory containing all named files" {
    mkdir -p "$TEST_DIR/app/src"
    touch "$TEST_DIR/app/Cargo.toml" "$TEST_DIR/app/Cargo.lock"
    touch "$TEST_DIR/app/src/Cargo.lock"
    cd "$TEST_DIR/app/src"

    run updir --all Cargo.toml Cargo.lock
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR/app" ]

    run updir --all Cargo.toml Missing.txt
    [ "$status" -ne 0 ]
}

@test "updir errors when both --any and --all are specified" {
    run updir --any --all something
    [ "$status" -ne 0 ]
    [[ "$output" =~ "cannot specify both" ]]
}

@test "updir errors when no pattern is provided" {
    run updir
    [ "$status" -ne 0 ]
    [[ "$output" =~ "missing required pattern" ]]
}

@test "updir --cd navigates to parent directory containing specified file" {
    mkdir -p "$TEST_DIR/repo/deep/nested"
    touch "$TEST_DIR/repo/package.json"
    cd "$TEST_DIR/repo/deep/nested"

    updir --cd package.json
    [ "$PWD" = "$TEST_DIR/repo" ]
}

@test "updir --cd --name navigates to parent directory by name with wildcards" {
    mkdir -p "$TEST_DIR/project_alpha/nested"
    cd "$TEST_DIR/project_alpha/nested"

    updir --cd --name 'project_*'
    [ "$PWD" = "$TEST_DIR/project_alpha" ]
}

@test "updir --cd --any navigates to directory containing matching file" {
    mkdir -p "$TEST_DIR/repo/deep/nested"
    touch "$TEST_DIR/repo/package.json"
    cd "$TEST_DIR/repo/deep/nested"

    updir --cd --any Cargo.toml package.json
    [ "$PWD" = "$TEST_DIR/repo" ]
}

@test "updir --cd --all navigates to directory containing all matching files" {
    mkdir -p "$TEST_DIR/monorepo/sub/deep"
    touch "$TEST_DIR/monorepo/package.json" "$TEST_DIR/monorepo/pnpm-lock.yaml"
    cd "$TEST_DIR/monorepo/sub/deep"

    updir --cd --all package.json pnpm-lock.yaml
    [ "$PWD" = "$TEST_DIR/monorepo" ]
}

@test "updir --cd returns nonzero and stays in place if directory not found" {
    mkdir -p "$TEST_DIR/some_folder"
    cd "$TEST_DIR/some_folder"

    run updir --cd nonexistent_di
    [ "$status" -ne 0 ]
    [ "$PWD" = "$TEST_DIR/some_folder" ]
}

# --- venv tests ---

@test "venv prints directory containing .venv/bin/activate without changing directory" {
    mkdir -p "$TEST_DIR/pyapp/.venv/bin" "$TEST_DIR/pyapp/src/core"
    touch "$TEST_DIR/pyapp/.venv/bin/activate"
    cd "$TEST_DIR/pyapp/src/core"

    run venv
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR/pyapp" ]
    [ "$PWD" = "$TEST_DIR/pyapp/src/core" ]
}

@test "venv --cd navigates to directory containing .venv/bin/activate" {
    mkdir -p "$TEST_DIR/pyapp/.venv/bin" "$TEST_DIR/pyapp/src/core"
    touch "$TEST_DIR/pyapp/.venv/bin/activate"
    cd "$TEST_DIR/pyapp/src/core"

    venv --cd
    [ "$PWD" = "$TEST_DIR/pyapp" ]
}

@test "venv --cd navigates to directory containing custom venv name like .custom-env/bin/activate" {
    mkdir -p "$TEST_DIR/customapp/.custom-env/bin" "$TEST_DIR/customapp/pkg"
    touch "$TEST_DIR/customapp/.custom-env/bin/activate"
    cd "$TEST_DIR/customapp/pkg"

    venv --cd
    [ "$PWD" = "$TEST_DIR/customapp" ]
}

@test "venv does not match Windows Scripts directory" {
    mkdir -p "$TEST_DIR/winapp/.venv/Scripts" "$TEST_DIR/winapp/pkg"
    touch "$TEST_DIR/winapp/.venv/Scripts/Activate.ps1"
    cd "$TEST_DIR/winapp/pkg"

    run venv
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

@test "venv returns nonzero and prints nothing when no virtualenv exists" {
    mkdir -p "$TEST_DIR/novenv"
    cd "$TEST_DIR/novenv"

    run venv
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

@test "venv --cd returns nonzero and stays in place when no virtualenv exists" {
    mkdir -p "$TEST_DIR/novenv_cd"
    cd "$TEST_DIR/novenv_cd"

    run venv --cd
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
    [ "$PWD" = "$TEST_DIR/novenv_cd" ]
}

# --- repo tests ---

@test "repo displays numbered menu and navigates to chosen repository without fzf" {
    mkdir -p "$TEST_DIR/myrepos/alpha" "$TEST_DIR/myrepos/beta" "$TEST_DIR/myrepos/gamma"
    touch "$TEST_DIR/myrepos/not_a_dir.txt"
    cd "$TEST_DIR"

    SHELLBITS_GIT_REPOS="$TEST_DIR/myrepos"
    PATH="/usr/bin:/bin"

    repo <<< "2"
    [ "$PWD" = "$TEST_DIR/myrepos/beta" ]
}

@test "repo uses fzf when available and navigates to selection" {
    mkdir -p "$TEST_DIR/myrepos/alpha" "$TEST_DIR/myrepos/beta"
    cd "$TEST_DIR"

    MOCK_BIN="$(mktemp -d)"
    cat <<'MOCK' > "$MOCK_BIN/fzf"
#!/bin/sh
echo "alpha"
MOCK
    chmod +x "$MOCK_BIN/fzf"

    SHELLBITS_GIT_REPOS="$TEST_DIR/myrepos"
    PATH="$MOCK_BIN:$PATH"

    repo
    [ "$PWD" = "$TEST_DIR/myrepos/alpha" ]
    rm -rf "$MOCK_BIN"
}

@test "repo defaults to ~/repos when SHELLBITS_GIT_REPOS is not set" {
    FAKE_HOME="$(mktemp -d)"
    mkdir -p "$FAKE_HOME/repos/repo_one" "$FAKE_HOME/repos/repo_two"
    cd "$TEST_DIR"

    HOME="$FAKE_HOME"
    unset SHELLBITS_GIT_REPOS
    PATH="/usr/bin:/bin"

    repo <<< "1"
    [ "$PWD" = "$FAKE_HOME/repos/repo_one" ]
    rm -rf "$FAKE_HOME"
}

@test "repo reports error when repos directory does not exist" {
    SHELLBITS_GIT_REPOS="$TEST_DIR/nonexistent_repos_dir"
    run repo
    [ "$status" -ne 0 ]
    [[ "$output" =~ "does not exist" ]]
}

@test "repo reports error when no repositories found in directory" {
    mkdir -p "$TEST_DIR/empty_repos"
    touch "$TEST_DIR/empty_repos/file.txt"
    SHELLBITS_GIT_REPOS="$TEST_DIR/empty_repos"
    run repo
    [ "$status" -ne 0 ]
    [[ "$output" =~ "no repositories found" ]]
}

@test "repo cancels cleanly without changing directory on q" {
    mkdir -p "$TEST_DIR/myrepos/alpha"
    cd "$TEST_DIR"
    SHELLBITS_GIT_REPOS="$TEST_DIR/myrepos"
    PATH="/usr/bin:/bin"

    repo <<< "q"
    [ "$PWD" = "$TEST_DIR" ]
}

@test "repo rejects invalid numeric selection" {
    mkdir -p "$TEST_DIR/myrepos/alpha"
    cd "$TEST_DIR"
    SHELLBITS_GIT_REPOS="$TEST_DIR/myrepos"
    PATH="/usr/bin:/bin"

    run repo <<< "99"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "invalid selection" ]]
}

@test "repo navigates directly when repository name is specified and exists" {
    mkdir -p "$TEST_DIR/myrepos/alpha" "$TEST_DIR/myrepos/beta"
    cd "$TEST_DIR"
    SHELLBITS_GIT_REPOS="$TEST_DIR/myrepos"

    repo beta
    [ "$PWD" = "$TEST_DIR/myrepos/beta" ]
}

@test "repo falls back to menu when specified repository name does not exist" {
    mkdir -p "$TEST_DIR/myrepos/alpha" "$TEST_DIR/myrepos/beta"
    cd "$TEST_DIR"
    SHELLBITS_GIT_REPOS="$TEST_DIR/myrepos"
    PATH="/usr/bin:/bin"

    repo nonexistent <<< "1"
    [ "$PWD" = "$TEST_DIR/myrepos/alpha" ]
}

@test "repo prints fzf hint after selection in fallback menu" {
    mkdir -p "$TEST_DIR/myrepos/alpha"
    cd "$TEST_DIR"
    SHELLBITS_GIT_REPOS="$TEST_DIR/myrepos"
    PATH="/usr/bin:/bin"

    run repo <<< "1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hint: install fzf for a nicer menu" ]]
}



