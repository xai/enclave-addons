#!/usr/bin/env bash
# Install enclave add-ons from this repository onto the local machine.
#
# Usage: ./install.sh <add-on>...
#
# Extensions (features/, tools/) are copied into the enclave user extension
# root and, for opt-in features, enabled in the global enclave config; run
# `enclave --rebuild` afterwards to bake them into the image. Features whose
# spec carries an `# x-install-mode: per-run` comment are never enabled in
# the global config -- they are meant to be selected per run with
# `--features +<name>`. User commands (commands/) are copied into the
# enclave commands directory instead and are available immediately, no
# rebuild needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin) CONFIG_ROOT="$HOME/Library/Application Support/org.eclipse.enclave/config" ;;
    *)      CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/enclave" ;;
esac
EXT_ROOT="$CONFIG_ROOT/extensions"
CONFIG_FILE="$CONFIG_ROOT/config.json"

list_addons() {
    local kind_dir dir cmd
    for kind_dir in features tools; do
        for dir in "$SCRIPT_DIR/$kind_dir"/*/; do
            [ -f "${dir}spec.yaml" ] && printf '  %-20s (%s)\n' "$(basename "$dir")" "${kind_dir%s}"
        done
    done
    for kind_dir in host session; do
        for cmd in "$SCRIPT_DIR/commands/$kind_dir"/*; do
            [ -f "$cmd" ] && [ -x "$cmd" ] && printf '  %-20s (%s command)\n' "$(basename "$cmd")" "$kind_dir"
        done
    done
}

usage() {
    echo "Usage: $(basename "$0") <add-on>..."
    echo
    echo "Available add-ons:"
    list_addons
}

# Echo the kind directories (features|tools) containing the named extension,
# one per line. $1 may be qualified ("features/<name>" / "tools/<name>") to
# force a single kind; a bare name matches every kind it exists in (a feature
# and a tool may legitimately share a name, e.g. neovim).
find_extension() {
    local name="$1" kinds="features tools" kind_dir found=1
    case "$name" in
        features/*|tools/*) kinds=${name%%/*}; name=${name#*/} ;;
    esac
    for kind_dir in $kinds; do
        if [ -f "$SCRIPT_DIR/$kind_dir/$name/spec.yaml" ]; then
            echo "$kind_dir"
            found=0
        fi
    done
    return "$found"
}

# Echo the kind (host|session) of the named user command.
find_command() {
    local name="$1" kind
    for kind in host session; do
        if [ -f "$SCRIPT_DIR/commands/$kind/$name" ] && [ -x "$SCRIPT_DIR/commands/$kind/$name" ]; then
            echo "$kind"
            return 0
        fi
    done
    return 1
}

# Install the shared command library next to the installed commands. Commands
# source it by relative path, so it has to travel with them. enclave-cmd.sh is
# overwritten on every install; enclave-cmd.local.sh belongs to the machine and
# is never touched.
install_command_lib() {
    local kind="$1" src_dir dest_dir file
    case " $installed_libs " in
        *" $kind "*) return 0 ;;
    esac
    src_dir="$SCRIPT_DIR/commands/$kind/lib"
    [ -d "$src_dir" ] || return 0
    dest_dir="$CONFIG_ROOT/commands/$kind/lib"
    mkdir -p "$dest_dir"
    for file in "$src_dir"/*; do
        [ -f "$file" ] || continue
        case "$(basename "$file")" in
            *.local.sh) continue ;;
        esac
        cp "$file" "$dest_dir/"
    done
    installed_libs="$installed_libs $kind"
    echo "Installed the shared command library to $dest_dir"
}

# Install a user command into the enclave commands directory. Enclave
# discovers it at CLI parse time, so it works immediately without a rebuild.
install_command() {
    local name="$1" kind="$2" dest
    dest="$CONFIG_ROOT/commands/$kind/$name"
    mkdir -p "$(dirname "$dest")"
    cp "$SCRIPT_DIR/commands/$kind/$name" "$dest"
    chmod +x "$dest"
    echo "Installed '$name' to $dest"
    install_command_lib "$kind"
    echo "'$name' is available immediately as: enclave $name"
}

# Add "+<name>" to the features array in the global config, creating the
# config file if needed. Only the features array is touched; all other keys
# are preserved. Idempotent.
enable_feature() {
    local name="$1" entry="+$1" tmp

    # enclave treats a missing or blank config file the same way: no config.
    if [ ! -f "$CONFIG_FILE" ] || ! grep -q '[^[:space:]]' "$CONFIG_FILE"; then
        printf '{ "features": ["%s"] }\n' "$entry" > "$CONFIG_FILE"
        echo "Enabled '$name' in $CONFIG_FILE (created)"
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        tmp="$(mktemp)"
        if ! jq --arg f "$entry" \
            '.features = ((.features // []) | if index($f) then . else . + [$f] end)' \
            "$CONFIG_FILE" > "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            manual_enable_hint "$entry"
            return 1
        fi
        mv "$tmp" "$CONFIG_FILE"
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 - "$CONFIG_FILE" "$entry" <<'PY'
import json, sys
path, entry = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        cfg = json.load(f)
except ValueError:
    sys.exit(1)
if not isinstance(cfg, dict):
    sys.exit(1)
features = cfg.setdefault("features", [])
if not isinstance(features, list):
    sys.exit(1)
if entry not in features:
    features.append(entry)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
        then
            manual_enable_hint "$entry"
            return 1
        fi
    else
        echo "Warning: neither jq nor python3 found; add \"$entry\" to the" >&2
        echo "\"features\" array in $CONFIG_FILE manually." >&2
        return 0
    fi
    echo "Enabled '$name' in $CONFIG_FILE"
}

manual_enable_hint() {
    echo "Error: could not update $CONFIG_FILE (invalid JSON, or \"features\"" >&2
    echo "is not an array). The file was left unchanged; add \"$1\" to its" >&2
    echo "\"features\" array manually." >&2
}

install_addon() {
    local arg="$1" name kinds kind_dir src dest spec

    name=$arg
    case "$arg" in
        features/*|tools/*) name=${arg#*/} ;;
    esac

    if ! kinds="$(find_extension "$arg")"; then
        if kind_dir="$(find_command "$name")"; then
            install_command "$name" "$kind_dir"
            return 0
        fi
        echo "Error: unknown add-on '$arg'" >&2
        echo >&2
        echo "Available add-ons:" >&2
        list_addons >&2
        return 1
    fi

    # A bare name installs every kind it matches; qualify as features/<name>
    # or tools/<name> to pick one.
    for kind_dir in $kinds; do
        src="$SCRIPT_DIR/$kind_dir/$name"
        dest="$EXT_ROOT/$kind_dir/$name"
        spec="$src/spec.yaml"

        mkdir -p "$(dirname "$dest")"
        rm -rf "$dest"
        cp -R "$src" "$dest"
        [ -f "$dest/install.sh" ] && chmod +x "$dest/install.sh"
        echo "Installed ${kind_dir%s} '$name' to $dest"
        needs_rebuild=1

        if grep -Eq '^kind:[[:space:]]*mixin' "$spec"; then
            if grep -Eq '^defaultEnabled:[[:space:]]*true' "$spec"; then
                echo "'$name' is enabled by default; no config change needed"
            elif grep -Eq '^#[[:space:]]*x-install-mode:[[:space:]]*per-run' "$spec"; then
                echo "'$name' is a per-run feature; NOT enabled in the global config."
                echo "Select it per run with: enclave --features +$name[,...]"
            else
                enable_feature "$name"
            fi
        else
            echo "'$name' is a tool; run it with: enclave --tool $name"
        fi
    done
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 1
fi

failed=0
needs_rebuild=0
installed_libs=
for name in "$@"; do
    install_addon "$name" || failed=1
done
[ "$failed" -eq 0 ] || exit 1

echo
if command -v enclave >/dev/null 2>&1; then
    enclave validate-extensions
fi
if [ "$needs_rebuild" -eq 1 ]; then
    echo "Done. Run 'enclave --rebuild' to bake the extensions into the image"
    echo "(or 'enclave update --rebuild' to rebuild without starting a session)."
else
    echo "Done."
fi
