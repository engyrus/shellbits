# shellbits -- by Jerry Kindall

Small, practical shell tools with strong opinions. A work in progress.

I have set up shells to my liking at three different companies: AWS, Snowflake, and Fiserv. At the last two companies
I left unexpectedly, so lost those setups and had to rebuild.

In addition to making sure I don't lose my shell setup again, these commands and tweaks may be useful to others.
They are also rather more robust than my original versions (better error handling, help, filename completion).
Thanks, Google Antigravity!

Most of the capabilities in shellbits work in bash or zsh. (The dynamic git branch prompt requires zsh.)

---

## Navigation Bits (`shell/navbits.sh`)

Sourced functions for directory navigation in **Bash** and **Zsh**. Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
source /path/to/shellbits/shell/navbits.sh
```

### `up [n]`

Navigates up `n` parent directories (defaults to 1 if omitted).

* Stops at `/` or `~`, whichever it hits first.
* When started inside `~`, you can `up` toward `/`.
* Rejects non-positive integer arguments.

```bash
# In ~/repos/shellbits/test
up        # Moves to ~/repos/shellbits
up 2      # Moves to ~/repos
up 10     # Stops at ~ (home directory)

# When already in ~
up        # Moves to /home
up 5      # Stops at /
```

### `updir [OPTIONS] PATTERN...`

Finds a parent directory matching the specified criteria. By default, it prints the matching directory path to stdout; with `--cd`, it navigates to that directory.

* **Default mode**: Finds the nearest directory containing the specified file, directory, or pattern.
* **`--name`**: Checks the name of the directory itself (not items inside it). Wildcards are supported.
* **`--cd`**: Changes to the found directory instead of printing its path.
* **`--any`**: Finds the nearest directory containing **any** of the named files or directories.
* **`--all`**: Finds the nearest directory containing **all** of the named files or directories.
* `--name`, `--any`, and `--all` are mutually exclusive.

> **Quoting Wildcards**: Always quote wildcard patterns (e.g. `'myproj*'`, `'*.json'`, `'*.toml'`, `'./.*/bin/activate'`) when using `--name`, `--any`, or `--all`. If unquoted, the calling shell will attempt to expand the wildcard in the *current* working directory before `updir` ever receives it, preventing it from matching parent directories.

```bash
# Find nearest parent directory containing package.json (default mode)
updir package.json

# Find nearest parent directory containing any .toml file (quoted)
updir '*.toml'

# Find and cd to nearest parent directory containing package.json
updir --cd package.json

# Find parent directory whose own name is "repos"
updir --name repos

# Find parent directory matching a name wildcard
updir --name 'repo*'

# Find and cd to parent directory matching a name wildcard
updir --cd --name 'repo*'

# Find nearest parent directory containing any of multiple files
updir --any package.json Cargo.toml

# Find nearest parent directory containing all of multiple files
updir --all Cargo.toml Cargo.lock
```

### `venv [OPTIONS]`

Finds the nearest parent directory containing a Python virtual environment (looking for `./.*/bin/activate`). By default, it prints the directory path to stdout; with `--cd`, it navigates to that directory. If no virtual environment is found, it prints nothing and returns nonzero.

* **`--cd`**: Changes to the virtual environment directory instead of printing its path.

```bash
# Deep inside a Python project (e.g. src/app/controllers)
venv
# Prints: /path/to/project

# Navigate to the project root where .venv is located
venv --cd
```

### `repo [NAME]`

Lists repositories in `~/repos` (or the directory specified by the `$SHELLBITS_GIT_REPOS` environment variable) and `cd`s into the selected repository, or jumps directly to a repository by name.

* **Direct jump**: If `NAME` is specified and matches a repository directory, `repo` changes into it immediately without prompting.
* **Interactive selection**: If `NAME` is omitted or does not match an existing directory, `repo` displays a selection menu:
  * In **Zsh** on an interactive terminal, displays a native arrow-key menu (Up/Down or `j`/`k` to navigate, Enter to select, `q` or Esc to cancel). Tab completion is also automatically configured for repository names.
  * In **Bash** (or when `fzf` is installed), uses **`fzf`** for fuzzy visual selection (pre-populated with `NAME` as the search query if one was entered).
  * If `fzf` is not installed or the session is non-interactive, falls back to a clean numbered menu.
* Entering `q` or pressing Esc cancels selection without changing directories.

```bash
# Jump directly to a repository by name
repo myproject

# Browse and select via interactive menu
repo

# Or configure a custom repositories base directory in your shell profile:
export SHELLBITS_GIT_REPOS="$HOME/src"
```

---

## yeet (`bin/yeet`)

> If `rm` had a `--with-extreme-prejudice` flag. Deletes files asynchronously after moving them to a hidden directory so you don't have to wait. No backsies.

`yeet` deletes specified files and directories instantaneously from the user's perspective by moving them into a hidden temporary directory (`.yeet-XXXXXX`) within their respective origin directories, and then removing those temporary directories asynchronously in the background.

Deletion is **immediate and unrecoverable**. There is no trash can or undo step.

### Usage

```bash
yeet [OPTIONS] [FILE|DIR]...
```

#### Examples

```bash
# Delete a single file
yeet unwanted.txt

# Delete multiple files in one go
yeet file1.txt file2.txt

# Delete an entire directory tree (no -r needed)
yeet old_build/

# Delete files across multiple directories in one invocation
yeet src/temp.o /tmp/junk.log tests/scratch/

# Test what would be done without touching anything
yeet --dry-run file1.txt old_build/
```

### Options

* **`-n`**, **`--dry-run`**: Print the actions that would be performed without creating temporary directories, moving files, or deleting anything.
* **`-h`**, **`--help`**: Display usage help and exit.
* **`--`**: Stop option parsing; all subsequent arguments are treated as file paths (useful for paths starting with a dash, e.g. `yeet -- -weirdname`).

### Compatibility Flags

For muscle-memory compatibility with `rm`, flags such as `-r`, `-R`, `-f`, and `-rf` are accepted as no-op flags. Recursive removal is already the default behavior of `yeet`.

### Portability & Requirements

* **Shell**: Compatible with **Bash 3.2+** (including macOS default `/bin/bash` and Linux Bash 4/5) and **Zsh**.
* **Platform**: macOS and Linux. Uses `mktemp -d` with explicit templates for portable temporary directory creation.

---

## hunt (`bin/hunt`)

Performs both a **filename search** and a **content search** for a query string. Both searches are **case-insensitive** and **literal** (no regular expressions or wildcard expansion), with the matched search term highlighted in color.

* Results are output in two sections:
  1. Paths of files/directories whose names contain the search string.
  2. Matching lines from file contents (`filepath:matched_line`).
* A blank line is printed after the first section if any filename matches were found.
* Skips all hidden directories by default; pass `--all` (`-a`) to include hidden directories (`.git` directories are always skipped).
* Ignores binary files during content searches.
* Searches in `DIR` if specified; otherwise uses `$SHELLBITS_HUNT_HOME` if set, or the current directory (`.`).

### Usage

```bash
hunt [OPTIONS] QUERY [DIR]
```

#### Examples

```bash
# Search filenames and file contents in the current directory (or $SHELLBITS_HUNT_HOME)
hunt config

# Include hidden directories (except .git)
hunt --all env

# Print results and open all matched files in the default editor
hunt --edit "TODO"

# Search inside a specific directory
hunt "connection string" ~/repos/myproject

# Search for a literal string starting with a dash (here "-v" is the search term)
hunt -- -v src/

# Configure a default starting directory or editor in your shell profile:
export SHELLBITS_HUNT_HOME="$HOME/repos"
export SHELLBITS_HUNT_EDITOR="code"
```

### Options

* **`-a`**, **`--all`**: Include hidden directories in the search (still skips `.git` directories).
* **`-e`**, **`--edit`**: Open all found files in the editor after printing results. Uses the first set variable from `$SHELLBITS_HUNT_EDITOR`, `$SHELLBITS_EDITOR`, or `$EDITOR`, falling back to `nano`, `pico`, or `vi`.
* **`-h`**, **`--help`**: Display usage help and exit.
* **`--`**: Stop option parsing; treat all subsequent arguments as positional arguments.



