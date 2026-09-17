# shellcheck shell=bash
# Amp CLI extension setup
mkdir -p "$HOME/.local/share/amp/skills" "$HOME/.config/amp" "$HOME/.cache/amp"

# Managed skills are composed into the config store, because enclave requires
# skillsDir below configDir. amp looks for global skills in ~/.config/amp/skills
# instead, so link that at the store and leave amp.skills.path free for whoever
# wants to add directories of their own. Anything real already sitting there is
# left alone.
if [ ! -e "$HOME/.config/amp/skills" ] || [ -L "$HOME/.config/amp/skills" ]; then
    ln -sfn "$HOME/.local/share/amp/skills" "$HOME/.config/amp/skills"
fi

# amp reads ~/.config/amp/settings.json, but the directory enclave persists is
# ~/.local/share/amp -- the one holding the login token. AMP_SETTINGS_FILE is
# amp's own documented override, so point it at the copy inside the store
# rather than leaving the settings file outside it.
AMP_SETTINGS_FILE="${ENCLAVE_TOOL_SETTINGS_TARGET:-$HOME/.local/share/amp/settings.json}"
export AMP_SETTINGS_FILE

# Two settings are re-asserted on every start, overriding whatever the file
# carries, because amp offers no flag for either and the file persists between
# sessions:
#
#   amp.updates.mode        `amp update` would replace the binary the image was
#                           built with. static.ampcode.com is denied as well, so
#                           this only saves a failed download per session.
#   amp.dangerouslyAllowAll what used to be --dangerously-allow-all. It has to
#                           track ENCLAVE_YOLO in both directions: a file left
#                           behind by a yolo session would otherwise keep a
#                           --no-yolo session permissive.
if command -v jq >/dev/null 2>&1; then
    [ -s "$AMP_SETTINGS_FILE" ] || echo '{}' > "$AMP_SETTINGS_FILE"
    _yolo=false
    if [ "${ENCLAVE_YOLO:-}" = "1" ]; then
        _yolo=true
    fi
    _tmp="$(mktemp)"
    if jq --argjson yolo "$_yolo" '. + {
            "amp.updates.mode": "disabled",
            "amp.dangerouslyAllowAll": $yolo
        }' "$AMP_SETTINGS_FILE" > "$_tmp" 2>/dev/null; then
        mv "$_tmp" "$AMP_SETTINGS_FILE"
    else
        # A settings file amp itself refuses to parse is repaired by hand, not
        # by this script: overwriting it here would discard the broken file.
        # jq also rejects the JSONC comments amp accepts.
        rm -f "$_tmp"
        echo "Warning: could not parse $AMP_SETTINGS_FILE; update and permission defaults not applied" >&2
    fi
    unset _tmp _yolo
fi
