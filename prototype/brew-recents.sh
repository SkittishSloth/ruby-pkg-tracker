#! /usr/bin/env bash

set -euo pipefail

start=$EPOCHREALTIME
last_dbg_time=$start

if ! command -v brew >/dev/null 2>&1; then
    echo "Error: Homebrew is not installed." >&2
    exit 1
fi

# Default configuration
DAYS=7
SHOW_FORMULA=true
SHOW_CASKS=true
SHOW_NEW=true
SHOW_UPDATED=false

DIM_LOOKED_UP=true
HIDE_LOOKED_UP=false

TRUNCATE_CHARS=25

BOLD='\033[1m'
ITALICS='\033[3m'
GREEN='\033[32m'
CYAN='\033[36m'

DIM='\033[2m'
RESET='\033[0m'

PLAIN_OUTPUT=false

INSTALLED_INDICATOR='•'

# Cache installed packages
declare -A INSTALLED_PKGS_MAP

# Cache looked-up packages
declare -A LOOKED_UP_PKGS_MAP
LOOKED_UP_PKGS=()

declare -A dbg_blocks
DBG_BLOCK_LOGS=()

DBG_LOGS=()

dbg() {
    local now=$EPOCHREALTIME
    local since_last=$(echo "scale=3; $now - $last_dbg_time" | bc)
    printf -v since_last_fmt "%.3f" "$since_last"

    local total=$(echo "scale=3; $now - $start" | bc)
    printf -v total_fmt "%.3f" "$total"
    local msg="DEBUG (+${since_last_fmt}s, ${total_fmt}s): $*"
    DBG_LOGS+=("$msg")
    last_dbg_time=$now
}

dbg_block_start() {
    local block_name="$1"
    dbg "Starting block '$block_name'."
    dbg_blocks["$block_name"]=$EPOCHREALTIME
}

dbg_block_end() {
    local block_name="$1"
    dbg "Ending block '$block_name'."
    if [[ -n "${dbg_blocks[$block_name]:-}" ]]; then
        local start_time=${dbg_blocks[$block_name]}
        local now=$EPOCHREALTIME
        local duration=$(echo "scale=3; $now - $start_time" | bc)
        printf -v duration_fmt "%.3f" "$duration"
        DBG_BLOCK_LOGS+=("BLOCK [$block_name]: ${duration_fmt}s")
        dbg "Block '$block_name' took ${duration_fmt}s."
        unset dbg_blocks["$block_name"]
    else
        dbg "Block '$block_name' not found."
    fi
}

is_installed() {
    [[ -n "${INSTALLED_PKGS_MAP[$1]:-}" ]]
}

is_looked_up() {
    [[ -n "${LOOKED_UP_PKGS_MAP[$1]:-}" ]]
}

print_usage() {
    cat <<EOF
Usage: brew recents [options]

Options:
  --days N              Show packages added/updated in the last N days (default: 7)
  --only-formula        Show only formulae
  --only-cask           Show only casks
  --only-new            Show only new packages
  --only-updated        Show only updated packages
  --dim-looked-up       Dim packages you've already looked up (default: on)
  --no-dim-looked-up    Do not dim packages you've already looked up
  --hide-looked-up      Hide packages you've already looked up
  --no-color            Disable colored output
  --plain               Output without formatting
  -h, --help            Show this help message

Examples:
  brew recents --days 5 --only-cask
  brew recents --hide-looked-up
EOF
}

# -- Extract and format entries --
format_package() {
    local name="$1"
    local block_name="format_package_$name"

    dbg_block_start "$block_name"

    if is_looked_up "$name" && $HIDE_LOOKED_UP; then
        dbg_block_end "$block_name"
        return 1  # Skip this package
    fi

    if $PLAIN_OUTPUT; then
        # Plain output, no formatting
        printf "%s" "$name"
        dbg_block_end "$block_name"
        return 0
    fi

    if is_installed "$name"; then
        # Always highlight installed packages
        printf "${BOLD}${ITALICS}${GREEN}${INSTALLED_INDICATOR}%s${RESET}" "$name"
        dbg_block_end "$block_name"
        return 0
    fi

    if is_looked_up "$name" && $DIM_LOOKED_UP; then
        printf "${DIM}%s${RESET}" "$name"
    else
        printf "%s" "$name"
    fi

    dbg_block_end "$block_name"
    return 0
}

get_terminal_cols() {
    dbg_block_start "get_terminal_cols"
    local maxlen="${1:-0}"
    local width="${TERMINAL_WIDTH:-80}"
    local colwidth=$((maxlen + 4))
    local cols=$(( width / colwidth ))
    (( cols < 1 )) && cols=1
    dbg_block_end "get_terminal_cols"
    echo "$cols"
}

get_global_maxlen() {
    local max_display_len=$TRUNCATE_CHARS
    local maxlen=0
    local name display_pkg plain vislen

    dbg_block_start "get_global_maxlen"

    while read -r name; do
        [[ -z "$name" ]] && continue
        name=$(basename "${name%.rb}")
        display_pkg="$name"
        if (( ${#display_pkg} > max_display_len )); then
            display_pkg="${display_pkg:0:max_display_len-1}…"
        fi
        local formatted
        formatted=$(format_package "$display_pkg")
        plain=$(printf "%s" "$formatted" | sed 's/\x1b\[[0-9;]*m//g')
        vislen=${#plain}
        (( vislen > maxlen )) && maxlen=$vislen
    done

    dbg_block_end "get_global_maxlen"

    echo "$maxlen"
}

strip_ansi() {
    # Removes ANSI escape codes from input
    sed 's/\x1b\[[0-9;]*m//g'
}

extract_names() {
    dbg_block_start "extract_names"
    local maxlen="$1"
    shift

    local names=()
    local formatted_names=()
    local vis_lengths=()
    local pkg

    local max_display_len=$TRUNCATE_CHARS  # Truncate names longer than this

    # Read package names from stdin and process
    dbg_block_start "read_packages"
    while read -r pkg; do
        [[ -z "$pkg" ]] && continue
        pkg=$(basename "${pkg%.rb}")
        # Truncate if needed
        local display_pkg="$pkg"
        if (( ${#display_pkg} > max_display_len )); then
            display_pkg="${display_pkg:0:max_display_len-1}…"
        fi
        # Format and store
        local formatted
        if ! formatted=$(format_package "$display_pkg"); then
            continue  # skip hidden packages
        fi
        formatted_names+=("$formatted")
        # Calculate visible length
        local plain
        plain=$(printf "%s" "$formatted" | sed 's/\x1b\[[0-9;]*m//g')
        vis_lengths+=(${#plain})
    done
    dbg_block_end "read_packages"

    local cols # Number of columns
    cols=$(get_terminal_cols "$maxlen")

    local colwidth=$(($maxlen + 4))

    # Print in columns with formatting
    local i=0
    local n=${#formatted_names[@]}
    dbg_block_start "print_columns"
    while (( i < n )); do
        for (( j=0; j<cols && i<n; ++j, ++i )); do
            local formatted="${formatted_names[i]}"
            local vislen="${vis_lengths[i]}"
            local padlen=$((colwidth - vislen))
            printf "%s" "$formatted"
            # Only pad if not the last column in the row
            if (( j < cols - 1 )) && (( padlen > 0 )); then
                printf "%*s" "$padlen" ""
            fi
        done
        printf "\n"
    done
    dbg_block_end "print_columns"
    dbg_block_end "extract_names"
}

dbg "Script started."

while getopts ":d:t:fFcCnNuUh" arg; do
    case "$arg" in
        d) DAYS="$OPTARG" ;;
        t) TRUNCATE_CHARS="$OPTARG" ;;
        f) SHOW_FORMULA=true ;;
        F) SHOW_FORMULA=false ;;
        c) SHOW_CASKS=true ;;
        C) SHOW_CASKS=false ;;
        n) SHOW_NEW=true ;;
        N) SHOW_NEW=false ;;
        u) SHOW_UPDATED=true ;;
        U) SHOW_UPDATED=false ;;
        h) print_usage; exit 0 ;;
        *) echo "❌ Unknown argument: -$OPTARG" >&2; print_usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

dbg "Parsed short options."

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --days)
            if [[ -n "${2:-}" && ! "${2:-}" =~ ^-- ]]; then
                DAYS="$2"
                shift 2
            else
                echo "Error: --days requires a value." >&2
                exit 1
            fi
            ;;
        --truncate-chars)
            if [[ -n "${2:-}" && ! "${2:-}" =~ ^-- ]]; then
                TRUNCATE_CHARS="$2"
                shift 2
            else
                echo "Error: --truncate-chars requires a value." >&2
                exit 1
            fi
            ;;
        --formula)
            SHOW_FORMULA=true
            shift
            ;;
        --no-formula)
            SHOW_FORMULA=false
            shift
            ;;
        --only-formula)
            SHOW_FORMULA=true
            SHOW_CASKS=false
            shift
            ;;
        --cask)
            SHOW_CASKS=true
            shift
            ;;
        --no-cask)
            SHOW_CASKS=false
            shift
            ;;
        --only-cask)
            SHOW_FORMULA=false
            SHOW_CASKS=true
            shift
            ;;
        --new)
            SHOW_NEW=true
            shift
            ;;
        --no-new)
            SHOW_NEW=false
            shift
            ;;
        --only-new)
            SHOW_NEW=true
            SHOW_UPDATED=false
            shift
            ;;
        --updated)
            SHOW_UPDATED=true
            shift
            ;;
        --no-updated)
            SHOW_UPDATED=false
            shift
            ;;
        --only-updated)
            SHOW_NEW=false
            SHOW_UPDATED=true
            shift
            ;;
        --dim-looked-up)
            DIM_LOOKED_UP=true
            shift
            ;;
        --no-dim-looked-up)
            DIM_LOOKED_UP=false
            shift
            ;;
        --hide-looked-up)
            HIDE_LOOKED_UP=true
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        --no-color)
            BOLD=''
            ITALICS=''
            GREEN=''
            CYAN=''
            DIM=''
            RESET=''
            shift
            ;;
        --plain)
            PLAIN_OUTPUT=true
            shift
            ;;
        *)
            echo "❌ Unknown argument: $arg" >&2
            print_usage
            exit 1
            ;;
    esac
done

dbg "Parsed long options. DAYS=$DAYS, TRUNCATE_CHARS=$TRUNCATE_CHARS, SHOW_FORMULA=$SHOW_FORMULA, SHOW_CASKS=$SHOW_CASKS, SHOW_NEW=$SHOW_NEW, SHOW_UPDATED=$SHOW_UPDATED, DIM_LOOKED_UP=$DIM_LOOKED_UP, HIDE_LOOKED_UP=$HIDE_LOOKED_UP, PLAIN_OUTPUT=$PLAIN_OUTPUT"

dbg_block_start "calculate_terminal_width"
TERMINAL_WIDTH=""
if [[ -n "${COLUMNS:-}" ]]; then
    TERMINAL_WIDTH="$COLUMNS"
elif TERMINAL_WIDTH=$(stty size 2>/dev/null | awk '{print $2}'); then
    :
else
    TERMINAL_WIDTH=80
fi
dbg_block_end "calculate_terminal_width"

dbg "Terminal width: $TERMINAL_WIDTH"

if ! $PLAIN_OUTPUT; then
    dbg "Setting up color output."
    dbg_block_start "setup_color_output"
    if INSTALLED_RAW=$(brew list 2>/dev/null); then
        dbg_block_start "cache_installed_packages"
        while read -r pkg; do
            INSTALLED_PKGS_MAP["$pkg"]=1
        done <<< "$INSTALLED_RAW"
        dbg_block_end "cache_installed_packages"
        dbg "Cached installed packages."
    fi

    if [[ -f ~/.zsh_history ]]; then
        dbg_block_start "cache_looked_up_packages"
        while read -r pkg; do
            LOOKED_UP_PKGS_MAP["$pkg"]=1
        done <<< "$(grep -oE 'bi [^ ]+|brew info [^ ]+' ~/.zsh_history | awk '{print $2}' | sort -u)"
        dbg_block_end "cache_looked_up_packages"
        dbg "Cached looked-up packages."
    fi
    dbg_block_end "setup_color_output"
    dbg "Color output enabled."
fi

# Gather lists for both sections as arrays
NEW_FORMULAE_LIST=()
UPDATED_FORMULAE_LIST=()
NEW_CASKS_LIST=()
UPDATED_CASKS_LIST=()

TMP_NEW_FORMULAE=$(mktemp)
TMP_UPDATED_FORMULAE=$(mktemp)
TMP_NEW_CASKS=$(mktemp)
TMP_UPDATED_CASKS=$(mktemp)
trap 'rm -f "$TMP_NEW_FORMULAE" "$TMP_UPDATED_FORMULAE" "$TMP_NEW_CASKS" "$TMP_UPDATED_CASKS"' EXIT

dbg_block_start "gather_lists"
if [[ "$SHOW_FORMULA" == true ]]; then
    dbg "Checking Homebrew core formulae."
    CORE_DIR="$(brew --repo homebrew/core)"
    if [[ "$SHOW_NEW" == true ]]; then
        dbg "Gathering new formulae."
        git -C "$CORE_DIR" log --diff-filter=A --since="$DAYS days ago" --name-only --pretty=format: | \
            grep '^Formula/.*\.rb$' | sort -u > "$TMP_NEW_FORMULAE" &
    fi
    if [[ "$SHOW_UPDATED" == true ]]; then
        dbg "Gathering updated formulae."
        git -C "$CORE_DIR" log --diff-filter=M --since="$DAYS days ago" --name-only --pretty=format: | \
            grep '^Formula/.*\.rb$' | sort -u > "$TMP_UPDATED_FORMULAE" &
    fi
fi

if [[ "$SHOW_CASKS" == true ]]; then
    dbg "Checking Homebrew Cask formulae."
    CASK_DIR="$(brew --repo homebrew/cask)"
    if [[ "$SHOW_NEW" == true ]]; then
        dbg "Gathering new casks."
        git -C "$CASK_DIR" log --diff-filter=A --since="$DAYS days ago" --name-only --pretty=format: | \
            grep '^Casks/.*\.rb$' | sort -u > "$TMP_NEW_CASKS" &
    fi
    if [[ "$SHOW_UPDATED" == true ]]; then
        dbg "Gathering updated casks."
        git -C "$CASK_DIR" log --diff-filter=M --since="$DAYS days ago" --name-only --pretty=format: | \
            grep '^Casks/.*\.rb$' | sort -u > "$TMP_UPDATED_CASKS" &
    fi
fi

wait
dbg_block_end "gather_lists"
dbg "Lists gathered."

dbg_block_start "load_files"
# Now read the files into arrays
if [[ "$SHOW_FORMULA" == true && "$SHOW_NEW" == true ]]; then
    dbg_block_start "load_new_formulae"
    mapfile -t NEW_FORMULAE_LIST < "$TMP_NEW_FORMULAE"
    dbg_block_end "load_new_formulae"
fi
if [[ "$SHOW_FORMULA" == true && "$SHOW_UPDATED" == true ]]; then
    dbg_block_start "load_updated_formulae"
    mapfile -t UPDATED_FORMULAE_LIST < "$TMP_UPDATED_FORMULAE"
    dbg_block_end "load_updated_formulae"
fi
if [[ "$SHOW_CASKS" == true && "$SHOW_NEW" == true ]]; then
    dbg_block_start "load_new_casks"
    mapfile -t NEW_CASKS_LIST < "$TMP_NEW_CASKS"
    dbg_block_end "load_new_casks"
fi
if [[ "$SHOW_CASKS" == true && "$SHOW_UPDATED" == true ]]; then
    dbg_block_start "load_updated_casks"
    mapfile -t UPDATED_CASKS_LIST < "$TMP_UPDATED_CASKS"
    dbg_block_end "load_updated_casks"
fi
dbg_block_end "load_files"
dbg "Lists loaded into arrays."

dbg "NEW_FORMULAE_LIST count: ${#NEW_FORMULAE_LIST[@]}"
dbg "UPDATED_FORMULAE_LIST count: ${#UPDATED_FORMULAE_LIST[@]}"
dbg "NEW_CASKS_LIST count: ${#NEW_CASKS_LIST[@]}"
dbg "UPDATED_CASKS_LIST count: ${#UPDATED_CASKS_LIST[@]}"

# Calculate global maxlen
dbg_block_start "calculate_global_maxlen"
ALL_PKGS=("${NEW_FORMULAE_LIST[@]}" "${UPDATED_FORMULAE_LIST[@]}" "${NEW_CASKS_LIST[@]}" "${UPDATED_CASKS_LIST[@]}")
maxlen=$(printf "%s\n" "${ALL_PKGS[@]}" | get_global_maxlen)
dbg_block_end "calculate_global_maxlen"

dbg "Global maxlen calculated: $maxlen"

# Print each section if enabled
dbg_block_start "print_sections"
if [[ "$SHOW_FORMULA" == true && "$SHOW_NEW" == true ]]; then
    dbg_block_start "print_new_formulae"
    echo -e "\n🆕 New formulae:"
    printf "%s\n" "${NEW_FORMULAE_LIST[@]}" | extract_names "$maxlen"
    dbg_block_end "print_new_formulae"
fi
if [[ "$SHOW_FORMULA" == true && "$SHOW_UPDATED" == true ]]; then
    dbg_block_start "print_updated_formulae"
    echo -e "\n✏️ Updated formulae:"
    printf "%s\n" "${UPDATED_FORMULAE_LIST[@]}" | extract_names "$maxlen"
    dbg_block_end "print_updated_formulae"
fi
if [[ "$SHOW_CASKS" == true && "$SHOW_NEW" == true ]]; then
    dbg_block_start "print_new_casks"
    echo -e "\n🆕 New casks:"
    printf "%s\n" "${NEW_CASKS_LIST[@]}" | extract_names "$maxlen"
    dbg_block_end "print_new_casks"
fi
if [[ "$SHOW_CASKS" == true && "$SHOW_UPDATED" == true ]]; then
    dbg_block_start "print_updated_casks"
    echo -e "\n✏️ Updated casks:"
    printf "%s\n" "${UPDATED_CASKS_LIST[@]}" | extract_names "$maxlen"
    dbg_block_end "print_updated_casks"
fi
dbg_block_end "print_sections"

dbg "All sections printed."

echo

# echo "DEBUG LOGS:"
# for log in "${DBG_LOGS[@]}"; do
#     printf "\t%s\n" "$log"
# done

# echo "DEBUG BLOCKS:"
# for block in "${DBG_BLOCK_LOGS[@]}"; do
#     printf "\t%s\n" "$block"
# done