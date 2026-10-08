#!/usr/bin/env bash
#
# zbp-app-lint: run ESLint + PHP-CS-Fixer on a Z-BlogPHP app directory.
#
# Usage:
#   lint.sh --path <dir> --mode <check|fix> --eslint <true|false> \
#           --php <true|false> --fixer-version <tag> --changed-only <true|false>
#
# Incremental mode:
#   --changed-only true (default) restricts the tools to the files listed in
#   the ZBP_LINT_CHANGED_FILES environment variable (space separated, relative
#   to the workspace root, as produced by tj-actions/changed-files).
#   When that variable is set but no file survives filtering, every tool is
#   reported as "skipped" and the script exits 0 without installing anything.
#   Outside GitHub Actions an unset variable falls back to a full scan.
#
# Exit codes:
#   0 - check mode: no issues / fix mode: completed without tool errors
#   1 - check mode: issues found / fix mode: a tool failed to run
#   2 - invalid arguments or target path
#
set -uo pipefail

MODE="check"
TARGET_PATH="."
ENABLE_ESLINT="true"
ENABLE_PHP="true"
FIXER_VERSION="v3.7.0"
CHANGED_ONLY="true"

while [[ $# -gt 0 ]]; do
    if [[ $# -lt 2 ]]; then
        echo "::error::lint.sh: missing value for argument: $1" >&2
        exit 2
    fi
    case "$1" in
        --path) TARGET_PATH="$2" ; shift 2 ;;
        --mode) MODE="$2" ; shift 2 ;;
        --eslint) ENABLE_ESLINT="$2" ; shift 2 ;;
        --php) ENABLE_PHP="$2" ; shift 2 ;;
        --fixer-version) FIXER_VERSION="$2" ; shift 2 ;;
        --changed-only) CHANGED_ONLY="$2" ; shift 2 ;;
        *) echo "::error::lint.sh: unknown argument: $1" >&2 ; exit 2 ;;
    esac
done

if [[ "$MODE" != "check" && "$MODE" != "fix" ]]; then
    echo "::error::lint.sh: invalid mode '$MODE' (expected 'check' or 'fix')" >&2
    exit 2
fi

if [[ "$CHANGED_ONLY" != "true" && "$CHANGED_ONLY" != "false" ]]; then
    echo "::error::lint.sh: invalid --changed-only '$CHANGED_ONLY' (expected 'true' or 'false')" >&2
    exit 2
fi

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"

if [[ -d "$TARGET_PATH" ]]; then
    TARGET_DIR="$(cd "$TARGET_PATH" && pwd)"
elif [[ -d "$WORKSPACE/$TARGET_PATH" ]]; then
    TARGET_DIR="$(cd "$WORKSPACE/$TARGET_PATH" && pwd)"
else
    echo "::error::lint.sh: target path not found: $TARGET_PATH" >&2
    exit 2
fi

# --------------------------------------------------- incremental scope ------

# INCREMENTAL=1 means: only the files listed in ZBP_LINT_CHANGED_FILES
# (space separated, relative to the workspace root) are processed.
INCREMENTAL=0
CHANGED_FILES_RAW="${ZBP_LINT_CHANGED_FILES:-}"
ALL_CHANGED=()

if [[ "$CHANGED_ONLY" == "true" ]]; then
    if [[ -n "${ZBP_LINT_CHANGED_FILES+x}" ]]; then
        INCREMENTAL=1
    elif [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        # On GitHub Actions without a file list: nothing changed in this event.
        INCREMENTAL=1
    else
        echo "==> changed-only=true but ZBP_LINT_CHANGED_FILES is unset, falling back to a full scan"
    fi
fi

is_ignored_path() {
    [[ "$1" == */node_modules/* || "$1" == */vendor/* || "$1" == */.history/* \
        || "$1" == */.git/* || "$1" == */dist/* ]]
}

# Resolve the raw list into absolute paths that live inside TARGET_DIR.
collect_changed_files() {
    ALL_CHANGED=()
    local rel abs
    for rel in $CHANGED_FILES_RAW; do
        [[ -n "$rel" ]] || continue
        rel="${rel#./}"
        abs="$WORKSPACE/$rel"
        # Drop deleted files, files outside the target directory and files
        # that live in an ignored directory.
        [[ -f "$abs" ]] || continue
        [[ "$abs" == "$TARGET_DIR"/* ]] || continue
        is_ignored_path "$abs" && continue
        ALL_CHANGED+=("$abs")
    done
}

# Fill TARGETS with the collected files matching an extension pattern
# (e.g. 'php' or 'js|mjs|cjs').
filter_by_extension() {
    TARGETS=()
    local file
    for file in ${ALL_CHANGED[@]+"${ALL_CHANGED[@]}"}; do
        [[ "$file" =~ \.($1)$ ]] && TARGETS+=("$file")
    done
}

log_changed_files() {
    local total=$1 i=0 file rel
    echo "==> Incremental mode: $total changed file(s) inside $TARGET_DIR"
    for file in ${ALL_CHANGED[@]+"${ALL_CHANGED[@]}"}; do
        if [[ $i -ge 20 ]]; then
            echo "    ... ($((total - i)) more)"
            break
        fi
        rel="${file#"$WORKSPACE"/}"
        echo "    $rel"
        i=$((i + 1))
    done
}

GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-}"

ESLINT_STATUS="skipped"
ESLINT_FATAL=0
PHP_STATUS="skipped"
PHP_FATAL=0

set_output() {
    if [[ -n "$GITHUB_OUTPUT" ]]; then
        printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
    else
        printf '%s=%s\n' "$1" "$2"
    fi
}

summary() {
    printf '%s\n' "$1"
    if [[ -n "$GITHUB_STEP_SUMMARY" ]]; then
        printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
    fi
}

summary_to_tail() {
    # Append the last 100 lines of a tool's output to the step summary.
    printf '%s\n' "$1" | tail -n 100 >> "$GITHUB_STEP_SUMMARY"
}

# ------------------------------------------------------------------ helpers --

eslint_files_exist() {
    [[ -n "$(find "$TARGET_DIR" \
        \( -name node_modules -o -name vendor -o -name .history -o -name .git \) -prune -o \
        -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print -quit 2>/dev/null)" ]]
}

php_files_exist() {
    [[ -n "$(find "$TARGET_DIR" \
        \( -name node_modules -o -name vendor -o -name .history -o -name .git \) -prune -o \
        -type f -name '*.php' -print -quit 2>/dev/null)" ]]
}

# ------------------------------------------------------------------ eslint --

run_eslint() {
    if [[ "$ENABLE_ESLINT" != "true" ]]; then
        echo "==> ESLint: disabled by input, skipping"
        ESLINT_STATUS="skipped"
        return 0
    fi

    if ! command -v node >/dev/null 2>&1; then
        echo "::error::ESLint: node is not available on the runner" >&2
        ESLINT_STATUS="failed"
        ESLINT_FATAL=1
        return 0
    fi

    local targets=()
    if [[ "$INCREMENTAL" == "1" ]]; then
        filter_by_extension 'js|mjs|cjs'
        targets=(${TARGETS[@]+"${TARGETS[@]}"})
        if [[ ${#targets[@]} -eq 0 ]]; then
            echo "==> ESLint: no changed JS files inside $TARGET_DIR, skipping"
            ESLINT_STATUS="skipped"
            return 0
        fi
    else
        if ! eslint_files_exist; then
            echo "==> ESLint: no JS files found under $TARGET_DIR, skipping"
            ESLINT_STATUS="skipped"
            return 0
        fi
        targets=("$TARGET_DIR")
    fi

    echo "==> ESLint: installing dependencies in action directory"
    if ! (cd "$ACTION_DIR" && npm install --no-audit --no-fund --prefer-offline); then
        echo "::error::ESLint: npm install failed" >&2
        ESLINT_STATUS="failed"
        ESLINT_FATAL=1
        return 0
    fi

    local eslint_bin="$ACTION_DIR/node_modules/.bin/eslint"

    # Prefer the caller's own flat config when present.
    # Note: pass it explicitly via --config, because ESLint 9 resolves
    # flat configs from the working directory, not from the linted files.
    local caller_cfg=""
    local f
    for f in eslint.config.mjs eslint.config.js eslint.config.cjs; do
        if [[ -f "$TARGET_DIR/$f" ]]; then
            caller_cfg="$TARGET_DIR/$f"
            break
        fi
        if [[ -f "$WORKSPACE/$f" ]]; then
            caller_cfg="$WORKSPACE/$f"
            break
        fi
    done

    local args=()
    if [[ -n "$caller_cfg" ]]; then
        echo "==> ESLint: using caller config ($caller_cfg)"
        args+=(--config "$caller_cfg")
    else
        echo "==> ESLint: using built-in config"
        args+=(--config "$ACTION_DIR/config/eslint.config.mjs")
    fi
    if [[ "$MODE" == "fix" ]]; then
        args+=(--fix)
    fi

    echo "==> ESLint: running in $MODE mode on ${#targets[@]} target(s)"
    local out rc
    out="$(cd "$WORKSPACE" && "$eslint_bin" ${args[@]+"${args[@]}"} ${targets[@]+"${targets[@]}"} 2>&1)"
    rc=$?
    if [[ -n "$out" ]]; then
        echo "$out"
    fi

    if [[ $rc -eq 0 ]]; then
        ESLINT_STATUS="passed"
    elif [[ $rc -eq 1 && "$MODE" == "fix" ]]; then
        # Everything fixable was fixed; remaining issues are reported but not fatal.
        ESLINT_STATUS="fixed-with-issues"
        echo "::warning::ESLint: some issues could not be auto-fixed (see log above)"
    else
        ESLINT_STATUS="failed"
        if [[ -n "$GITHUB_STEP_SUMMARY" && -n "$out" ]]; then
            summary ""
            summary "### ESLint issues"
            summary ""
            summary '```text'
            summary_to_tail "$out"
            summary '```'
        fi
        if [[ $rc -ge 2 ]]; then
            ESLINT_FATAL=1
        fi
    fi
}

# --------------------------------------------------------- php-cs-fixer ------

run_php() {
    if [[ "$ENABLE_PHP" != "true" ]]; then
        echo "==> PHP-CS-Fixer: disabled by input, skipping"
        PHP_STATUS="skipped"
        return 0
    fi

    if ! command -v php >/dev/null 2>&1; then
        echo "::error::PHP-CS-Fixer: php is not available on the runner" >&2
        PHP_STATUS="failed"
        PHP_FATAL=1
        return 0
    fi

    if ! php -r 'exit(PHP_VERSION_ID >= 70400 ? 0 : 1);' >/dev/null 2>&1; then
        echo "::error::PHP-CS-Fixer: requires PHP >= 7.4 to run (got $(php -r 'echo PHP_VERSION;'))" >&2
        PHP_STATUS="failed"
        PHP_FATAL=1
        return 0
    fi

    local targets=()
    if [[ "$INCREMENTAL" == "1" ]]; then
        filter_by_extension 'php'
        targets=(${TARGETS[@]+"${TARGETS[@]}"})
        if [[ ${#targets[@]} -eq 0 ]]; then
            echo "==> PHP-CS-Fixer: no changed PHP files inside $TARGET_DIR, skipping"
            PHP_STATUS="skipped"
            return 0
        fi
    else
        if ! php_files_exist; then
            echo "==> PHP-CS-Fixer: no PHP files found under $TARGET_DIR, skipping"
            PHP_STATUS="skipped"
            return 0
        fi
        targets=("$TARGET_DIR")
    fi

    local phar="$ACTION_DIR/php-cs-fixer.phar"
    if [[ ! -f "$phar" ]]; then
        local url="https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/releases/download/$FIXER_VERSION/php-cs-fixer.phar"
        echo "==> PHP-CS-Fixer: downloading $FIXER_VERSION | $url"
        if ! curl -fsSL -o "$phar" "$url"; then
            echo "::error::PHP-CS-Fixer: failed to download $url" >&2
            PHP_STATUS="failed"
            PHP_FATAL=1
            return 0
        fi
        chmod +x "$phar"
        if ! php "$phar" --version >/dev/null 2>&1; then
            echo "::error::PHP-CS-Fixer: downloaded phar failed to run" >&2
            PHP_STATUS="failed"
            PHP_FATAL=1
            return 0
        fi
    fi
    echo "==> PHP-CS-Fixer: $(php "$phar" --version 2>/dev/null | sed -n '1p')"

    # Prefer the caller's own config when present.
    local cfg=""
    local cfg_dir="$WORKSPACE"
    local f
    for f in .php-cs-fixer.dist.php .php-cs-fixer.php; do
        if [[ -f "$TARGET_DIR/$f" ]]; then
            cfg="$TARGET_DIR/$f"
            cfg_dir="$TARGET_DIR"
            break
        fi
        if [[ -f "$WORKSPACE/$f" && "$WORKSPACE" != "$TARGET_DIR" ]]; then
            cfg="$WORKSPACE/$f"
            cfg_dir="$WORKSPACE"
            break
        fi
    done

    local args=(--using-cache=no --show-progress=none)
    if [[ -n "$cfg" ]]; then
        echo "==> PHP-CS-Fixer: using caller config ($cfg)"
        args+=(--config "$cfg")
    else
        echo "==> PHP-CS-Fixer: using built-in config"
        export ZBP_LINT_PATH="$TARGET_DIR"
        args+=(--config "$ACTION_DIR/config/.php-cs-fixer.dist.php")
    fi
    if [[ "$MODE" == "check" ]]; then
        args+=(--dry-run --diff)
    fi

    echo "==> PHP-CS-Fixer: running in $MODE mode on ${#targets[@]} target(s)"
    local out rc
    out="$(cd "$cfg_dir" && php "$phar" fix ${args[@]+"${args[@]}"} ${targets[@]+"${targets[@]}"} 2>&1)"
    rc=$?
    if [[ -n "$out" ]]; then
        echo "$out"
    fi

    if [[ $rc -eq 0 ]]; then
        PHP_STATUS="passed"
    elif [[ "$MODE" == "fix" && $rc -eq 8 ]]; then
        PHP_STATUS="fixed-with-issues"
        echo "::warning::PHP-CS-Fixer: some issues could not be auto-fixed (see log above)"
    else
        PHP_STATUS="failed"
        if [[ -n "$GITHUB_STEP_SUMMARY" && -n "$out" ]]; then
            summary ""
            summary "### PHP-CS-Fixer issues"
            summary ""
            summary '```text'
            summary_to_tail "$out"
            summary '```'
        fi
        if [[ "$MODE" == "fix" ]]; then
            PHP_FATAL=1
        fi
    fi
}

# -------------------------------------------------------------------- main --

if [[ "$INCREMENTAL" == "1" ]]; then
    collect_changed_files
    log_changed_files "${#ALL_CHANGED[@]}"
    if [[ ${#ALL_CHANGED[@]} -eq 0 ]]; then
        echo "==> Nothing to lint: no changed file inside $TARGET_DIR, all tools will be skipped"
    fi
else
    echo "==> Full scan mode on $TARGET_DIR"
fi

run_eslint
run_php

set_output "eslint-status" "$ESLINT_STATUS"
set_output "php-status" "$PHP_STATUS"

if [[ "$INCREMENTAL" == "1" ]]; then
    SCOPE="incremental (${#ALL_CHANGED[@]} files)"
else
    SCOPE="full scan"
fi

summary ""
summary "## zbp-app-lint result"
summary ""
summary "- mode: \`${MODE}\`"
summary "- scope: \`${SCOPE}\`"
summary "- target: \`${TARGET_DIR}\`"
summary "- ESLint: **${ESLINT_STATUS}**"
summary "- PHP-CS-Fixer: **${PHP_STATUS}**"

if [[ "$MODE" == "check" ]]; then
    if [[ "$ESLINT_STATUS" == "failed" || "$PHP_STATUS" == "failed" ]]; then
        echo "::error::zbp-app-lint found problems (see log and step summary)"
        exit 1
    fi
else
    if [[ "$ESLINT_FATAL" == "1" || "$PHP_FATAL" == "1" ]]; then
        echo "::error::zbp-app-lint failed to run in fix mode (see log)"
        exit 1
    fi
fi

exit 0
