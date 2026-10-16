# shell/navbits.sh - Directory navigation functions for shellbits
# Compatible with both Bash and Zsh.
# Source this file in your ~/.bashrc or ~/.zshrc.

# shellcheck shell=bash

# up: Navigate up N parent directories (default 1).
# Stops at / or ~ (whichever is hit first). When started in ~, allows navigating up to /.
up() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        cat <<'EOF' >&2
Usage: up [N]

Navigates up N parent directories (default 1).
Stops at / or ~ (whichever is hit first). When in ~, navigates up toward /.
EOF
        return 0
    fi

    local count="${1:-1}"
    if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
        echo "up: argument must be a positive integer" >&2
        return 1
    fi

    local home_dir="${HOME:-}"
    local home_real=""
    if [ -n "$home_dir" ] && [ -d "$home_dir" ]; then
        home_real="$(cd -P -- "$home_dir" 2>/dev/null && pwd -P)"
    fi

    local start_dir="$PWD"
    local started_at_home=0
    if [ -n "$home_dir" ] && [ "$start_dir" = "$home_dir" ]; then
        started_at_home=1
    elif [ -n "$home_real" ]; then
        local start_real
        start_real="$(cd -P -- "$start_dir" 2>/dev/null && pwd -P)"
        if [ -n "$start_real" ] && [ "$start_real" = "$home_real" ]; then
            started_at_home=1
        fi
    fi

    local target_dir="$start_dir"
    local target_real=""
    local i
    for ((i=0; i<count; i++)); do
        if [ "$target_dir" = "/" ]; then
            break
        fi

        target_dir="$(dirname -- "$target_dir")"

        if [ "$started_at_home" -eq 0 ]; then
            if [ -n "$home_dir" ] && [ "$target_dir" = "$home_dir" ]; then
                break
            elif [ -n "$home_real" ]; then
                target_real="$(cd -P -- "$target_dir" 2>/dev/null && pwd -P)"
                if [ -n "$target_real" ] && [ "$target_real" = "$home_real" ]; then
                    break
                fi
            fi
        fi
    done

    cd -- "$target_dir" || return $?
}

# updir: Finds a parent directory (and prints it, or cd's to it if --cd is given).
# Default mode: finds a parent directory whose name matches PATTERN.
# --any: finds a directory containing ANY of the specified files/patterns/dirs.
# --all: finds a directory containing ALL of the specified files/patterns/dirs.
# --cd: changes to the found directory instead of printing it.
updir() {
    local do_cd=0
    local args=()
    local parsing_opts=1
    local arg

    for arg in "$@"; do
        if [ "$parsing_opts" -eq 1 ]; then
            if [ "$arg" = "--" ]; then
                parsing_opts=0
                args+=("$arg")
            elif [ "$arg" = "--cd" ]; then
                do_cd=1
            else
                args+=("$arg")
            fi
        else
            args+=("$arg")
        fi
    done

    if [ "$do_cd" -eq 1 ]; then
        local target
        if [ "${#args[@]}" -gt 0 ]; then
            target="$(updir "${args[@]}")" || return $?
        else
            target="$(updir)" || return $?
        fi
        if [ -n "$target" ]; then
            cd -- "$target" || return $?
        fi
        return 0
    fi

    (
        if [ -n "${ZSH_VERSION:-}" ]; then
            setopt GLOBSUBST 2>/dev/null
        fi

        local mode=""
        local patterns=()

        while [ "$#" -gt 0 ]; do
            case "$1" in
                --name)
                    if [ "$mode" = "any" ] || [ "$mode" = "all" ]; then
                        echo "updir: cannot combine --name with --any or --all" >&2
                        return 1
                    fi
                    mode="name"
                    shift
                    ;;
                --name=*)
                    if [ "$mode" = "any" ] || [ "$mode" = "all" ]; then
                        echo "updir: cannot combine --name with --any or --all" >&2
                        return 1
                    fi
                    mode="name"
                    patterns+=("${1#*=}")
                    shift
                    ;;
                --any|--anyfile|--anyfiles)
                    if [ "$mode" = "name" ]; then
                        echo "updir: cannot combine --name with --any or --all" >&2
                        return 1
                    fi
                    if [ "$mode" = "all" ]; then
                        echo "updir: cannot specify both --any and --all" >&2
                        return 1
                    fi
                    mode="any"
                    shift
                    ;;
                --all|--allfiles)
                    if [ "$mode" = "name" ]; then
                        echo "updir: cannot combine --name with --any or --all" >&2
                        return 1
                    fi
                    if [ "$mode" = "any" ]; then
                        echo "updir: cannot specify both --any and --all" >&2
                        return 1
                    fi
                    mode="all"
                    shift
                    ;;
                --)
                    shift
                    while [ "$#" -gt 0 ]; do
                        patterns+=("$1")
                        shift
                    done
                    break
                    ;;
                -h|--help)
                    cat <<'EOF' >&2
Usage: updir [OPTIONS] PATTERN...

Finds a parent directory and prints it, or cd's to it if --cd is specified.

Modes:
  (default)     Finds a directory containing the specified file, directory, or pattern.
  --name        Finds a directory whose name matches PATTERN.
  --any         Finds a directory containing ANY of the specified files/patterns/dirs.
  --all         Finds a directory containing ALL of the specified files/patterns/dirs.

Options:
  --cd          Change to the found directory instead of just printing it
  -h, --help    Display this help and exit

Note: Always quote wildcard patterns (e.g. '*.json', 'myproj*') so the calling shell does
      not expand them in the current directory before updir can search parents.
EOF
                    return 0
                    ;;
                *)
                    patterns+=("$1")
                    shift
                    ;;
            esac
        done

        if [ -z "$mode" ]; then
            mode="any"
        fi

        if [ "${#patterns[@]}" -eq 0 ]; then
            echo "updir: missing required pattern" >&2
            return 1
        fi

        _pattern_exists() {
            local pat="$1"
            if [ -e "$pat" ] || [ -L "$pat" ]; then
                return 0
            fi
            case "$pat" in
                *[\*\?\[]*)
                    local matches=()
                    if [ -n "${ZSH_VERSION:-}" ]; then
                        setopt NULL_GLOB 2>/dev/null
                        # shellcheck disable=SC2296
                        matches=( $~pat )
                    else
                        local old_ifs="$IFS"
                        IFS=""
                        shopt -s nullglob 2>/dev/null
                        # shellcheck disable=SC2206
                        matches=( $pat )
                        IFS="$old_ifs"
                    fi
                    if [ "${#matches[@]}" -gt 0 ]; then
                        return 0
                    fi
                    ;;
            esac
            return 1
        }

        local current_name=""
        local pat=""
        local all_matched=1

        while :; do
            case "$mode" in
                name|dirname)
                    current_name="$(basename -- "$PWD")"
                    for pat in "${patterns[@]}"; do
                        # shellcheck disable=SC2053
                        if [[ "$current_name" == $pat ]]; then
                            echo "$PWD"
                            return 0
                        fi
                    done
                    ;;
                any)
                    for pat in "${patterns[@]}"; do
                        if _pattern_exists "$pat"; then
                            echo "$PWD"
                            return 0
                        fi
                    done
                    ;;
                all)
                    all_matched=1
                    for pat in "${patterns[@]}"; do
                        if ! _pattern_exists "$pat"; then
                            all_matched=0
                            break
                        fi
                    done
                    if [ "$all_matched" -eq 1 ]; then
                        echo "$PWD"
                        return 0
                    fi
                    ;;
            esac

            if [ "$PWD" = "/" ]; then
                break
            fi

            cd .. || break
        done

        echo "updir: no matching directory found" >&2
        return 1
    )
}


# venv: Finds Python venv by looking for ./*/bin/activate using updir.
# Prints the directory path, or cd's to it if --cd is specified.
venv() {
    local do_cd=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                cat <<'EOF' >&2
Usage: venv [OPTIONS]

Finds the nearest parent directory containing a Python virtual environment.
Looks for ./*/bin/activate.

Options:
  --cd          Change to the virtualenv directory instead of printing it
  -h, --help    Display this help and exit
EOF
                return 0
                ;;
            --cd)
                do_cd=1
                shift
                ;;
            *)
                echo "venv: unrecognized option '$1'" >&2
                return 1
                ;;
        esac
    done

    if [ "$do_cd" -eq 1 ]; then
        updir --cd './.*/bin/activate' 2>/dev/null
    else
        updir './.*/bin/activate' 2>/dev/null
    fi
}

# repo: Lists repositories in ~/repos or $SHELLBITS_GIT_REPOS and cd's into the chosen one.
# Supports directly switching to a repository by name if provided: repo [REPO_NAME].
# If in Zsh, uses native arrow-key menu selection. In Bash, uses fzf if installed,
# otherwise falls back to a numbered menu.
repo() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        cat <<'EOF' >&2
Usage: repo [NAME]

Navigates to a repository in ~/repos (or $SHELLBITS_GIT_REPOS).
If NAME is provided and matches an existing repository directory, navigates to it immediately.
Otherwise, displays a menu to select a repository.
In Zsh, uses an arrow-key menu. In Bash, uses fzf if available, or a numbered menu.

Options:
  -h, --help    Display this help and exit
EOF
        return 0
    fi

    local repos_dir="${SHELLBITS_GIT_REPOS:-}"
    local repos=()
    local d=""
    local name=""
    local selection=""
    local num=1
    local r=""
    local choice=""
    local selected_repo=""

    if [ -z "$repos_dir" ]; then
        repos_dir="${HOME:-}/repos"
    elif [ "${repos_dir#\~/}" != "$repos_dir" ]; then
        repos_dir="${HOME:-}/${repos_dir#\~/}"
    fi

    if [ ! -d "$repos_dir" ]; then
        echo "repo: directory '$repos_dir' does not exist" >&2
        return 1
    fi

    # Direct switch by name if specified and directory exists
    if [ -n "${1:-}" ] && [ -d "$repos_dir/$1" ]; then
        cd -- "$repos_dir/$1" || return $?
        return 0
    fi

    if [ -n "${ZSH_VERSION:-}" ]; then
        setopt LOCAL_OPTIONS NULL_GLOB 2>/dev/null
    fi

    for d in "$repos_dir"/*/; do
        if [ -d "$d" ]; then
            name="${d%/}"
            name="${name##*/}"
            repos+=("$name")
        fi
    done

    if [ "${#repos[@]}" -eq 0 ]; then
        echo "repo: no repositories found in '$repos_dir'" >&2
        return 1
    fi

    # If running in Zsh (check $ZSH_VERSION not $SHELL) and on interactive terminal, use native arrow-key menu
    if [ -n "${ZSH_VERSION:-}" ] && [ -t 0 ] && [ -t 2 ]; then
        local selected=1
        local total="${#repos[@]}"
        local key=""
        local rest=""
        local i=1

        # Hide cursor during menu
        printf '\e[?25l' >&2

        _repo_draw() {
            i=1
            for r in "${repos[@]}"; do
                if [ "$i" -eq "$selected" ]; then
                    printf '\e[1;32m> %s\e[0m\e[K\n' "$r" >&2
                else
                    printf '  %s\e[K\n' "$r" >&2
                fi
                i=$((i + 1))
            done
        }

        _repo_clear() {
            printf '\e[%dA' "$total" >&2
        }

        printf 'Select repository (Up/Down or j/k to move, Enter to select, q to cancel):\n' >&2
        _repo_draw

        while true; do
            # shellcheck disable=SC3045
            read -r -k 1 key < /dev/tty || break
            if [[ "$key" == $'\e' ]]; then
                # shellcheck disable=SC3045
                read -r -k 2 -t 0.1 rest < /dev/tty
                case "$rest" in
                    '[A'|'OA')
                        if [ "$selected" -gt 1 ]; then
                            selected=$((selected - 1))
                        else
                            selected="$total"
                        fi
                        _repo_clear
                        _repo_draw
                        ;;
                    '[B'|'OB')
                        if [ "$selected" -lt "$total" ]; then
                            selected=$((selected + 1))
                        else
                            selected=1
                        fi
                        _repo_clear
                        _repo_draw
                        ;;
                    *)
                        # Esc pressed alone
                        printf '\e[?25h' >&2
                        return 0
                        ;;
                esac
            elif [[ "$key" == 'k' || "$key" == 'K' ]]; then
                if [ "$selected" -gt 1 ]; then
                    selected=$((selected - 1))
                else
                    selected="$total"
                fi
                _repo_clear
                _repo_draw
            elif [[ "$key" == 'j' || "$key" == 'J' ]]; then
                if [ "$selected" -lt "$total" ]; then
                    selected=$((selected + 1))
                else
                    selected=1
                fi
                _repo_clear
                _repo_draw
            elif [[ "$key" == $'\n' || "$key" == $'\r' ]]; then
                printf '\e[?25h' >&2
                num=1
                for r in "${repos[@]}"; do
                    if [ "$num" -eq "$selected" ]; then
                        selected_repo="$r"
                        break
                    fi
                    num=$((num + 1))
                done
                if [ -n "$selected_repo" ]; then
                    cd -- "$repos_dir/$selected_repo" || return $?
                fi
                return 0
            elif [[ "$key" == 'q' || "$key" == 'Q' || "$key" == $'\x03' ]]; then
                printf '\e[?25h' >&2
                return 0
            fi
        done
        printf '\e[?25h' >&2
        return 0
    fi

    # If fzf is available (e.g. in Bash), use it
    if command -v fzf >/dev/null 2>&1; then
        local fzf_query=()
        if [ -n "${1:-}" ]; then
            fzf_query=(--query="$1")
        fi
        if [ "${#fzf_query[@]}" -gt 0 ]; then
            selection="$(printf '%s\n' "${repos[@]}" | fzf "${fzf_query[@]}")" || return 0
        else
            selection="$(printf '%s\n' "${repos[@]}" | fzf)" || return 0
        fi
        if [ -n "$selection" ]; then
            cd -- "$repos_dir/$selection" || return $?
        fi
        return 0
    fi

    # Fallback numbered menu (used when non-interactive or fzf is not installed)
    printf "Available repositories in %s:\n" "$repos_dir"
    num=1
    for r in "${repos[@]}"; do
        printf "  %2d) %s\n" "$num" "$r"
        num=$((num + 1))
    done

    printf "Select repository [1-%d] (q to cancel): " "${#repos[@]}"
    if ! read -r choice; then
        echo "" >&2
        return 0
    fi

    case "$choice" in
        q|Q|"")
            return 0
            ;;
    esac

    if ! [[ "$choice" =~ ^[1-9][0-9]*$ ]] || [ "$choice" -gt "${#repos[@]}" ]; then
        echo "repo: invalid selection: $choice" >&2
        return 1
    fi

    num=1
    for r in "${repos[@]}"; do
        if [ "$num" -eq "$choice" ]; then
            selected_repo="$r"
            break
        fi
        num=$((num + 1))
    done

    if [ -n "$selected_repo" ]; then
        cd -- "$repos_dir/$selected_repo" || return $?
        echo "Hint: install fzf for a nicer menu"
    fi
}

# Zsh completion: enables tab completion for repo in Zsh
if [ -n "${ZSH_VERSION:-}" ]; then
    _repo_completion() {
        local repos_dir="${SHELLBITS_GIT_REPOS:-}"
        if [ -z "$repos_dir" ]; then
            repos_dir="${HOME:-}/repos"
        elif [ "${repos_dir#\~/}" != "$repos_dir" ]; then
            repos_dir="${HOME:-}/${repos_dir#\~/}"
        fi
        if [ -d "$repos_dir" ]; then
            local repos=()
            local d=""
            setopt LOCAL_OPTIONS NULL_GLOB 2>/dev/null
            for d in "$repos_dir"/*/; do
                if [ -d "$d" ]; then
                    local name="${d%/}"
                    repos+=("${name##*/}")
                fi
            done
            if [ "${#repos[@]}" -gt 0 ]; then
                _describe 'repository' repos
            fi
        fi
    }
    compdef _repo_completion repo 2>/dev/null || true
fi


