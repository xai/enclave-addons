# shellcheck shell=bash
# Amp CLI extension setup
# Derive approval mode from the final tool argv, not ENCLAVE_YOLO: project .env
# values are appended after Enclave's own container variables and could spoof
# that variable. The yolo flag in argv is inserted by Enclave itself. Export a
# fresh value after .env processing for the approval plugin subprocess.
_amp_yolo=false
for _arg in "$@"; do
    if [ "$_arg" = "--dangerously-allow-all" ]; then
        _amp_yolo=true
        break
    fi
done
ENCLAVE_AMP_APPROVALS=1
if [ "$_amp_yolo" = "true" ]; then
    ENCLAVE_AMP_APPROVALS=0
fi
export ENCLAVE_AMP_APPROVALS
unset _arg

# Keep Amp's system-plugin root outside the mounted project even if a passed
# environment value tries to redirect XDG configuration there.
XDG_CONFIG_HOME="$HOME/.config"
export XDG_CONFIG_HOME
_amp_config_dir="$XDG_CONFIG_HOME/amp"
mkdir -p \
    "$HOME/.local/share/amp/skills" \
    "$_amp_config_dir/plugins" \
    "$HOME/.cache/amp"

# Amp workspace settings override user settings, so dangerouslyAllowAll=false
# in the managed settings file cannot enforce --no-yolo by itself. A system
# plugin handles tool.call instead and asks before every call in no-yolo mode.
# Link it from the root-owned extension tree rather than copying it somewhere
# the agent can rewrite without first passing through that approval hook.
_approval_plugin_source="/opt/enclave/extensions/tools/amp/plugins/enclave-approvals.ts"
if [ ! -f "$_approval_plugin_source" ] && [ -n "${ENCLAVE_TOOLS_DIR:-}" ]; then
    # Test/development fallback. Production images always use the root-owned
    # path above, even if the container environment supplies another value.
    _approval_plugin_source="$ENCLAVE_TOOLS_DIR/amp/plugins/enclave-approvals.ts"
fi
_approval_plugin_target="$_amp_config_dir/plugins/enclave-approvals.ts"
if [ ! -f "$_approval_plugin_source" ]; then
    echo "Error: Amp approval plugin is missing: $_approval_plugin_source" >&2
    exit 1
fi
if [ -e "$_approval_plugin_target" ] && [ ! -L "$_approval_plugin_target" ]; then
    echo "Error: reserved Amp approval plugin path already exists: $_approval_plugin_target" >&2
    exit 1
fi

# A project plugin with the same name takes precedence over a system plugin.
# Refuse that collision in no-yolo mode; once the system plugin is active, any
# attempt to create a shadowing plugin is itself subject to approval.
_project_plugin_collision=""
if [ "$_amp_yolo" != "true" ] && [ -d "$PWD/.amp/plugins" ]; then
    _project_plugin_collision="$(find "$PWD/.amp/plugins" -maxdepth 1 \
        \( -name 'enclave-approvals' -o -name 'enclave-approvals.*' \) \
        -print -quit)"
fi
if [ -n "$_project_plugin_collision" ]; then
    echo "Error: project plugin shadows Enclave's approval policy: $_project_plugin_collision" >&2
    exit 1
fi
ln -sfn "$_approval_plugin_source" "$_approval_plugin_target"
unset _approval_plugin_source _approval_plugin_target _project_plugin_collision

# Managed skills are composed into the config store, because enclave requires
# skillsDir below configDir. amp looks for global skills in ~/.config/amp/skills
# instead, so link that at the store and leave amp.skills.path free for whoever
# wants to add directories of their own. Anything real already sitting there is
# left alone.
if [ ! -e "$_amp_config_dir/skills" ] || [ -L "$_amp_config_dir/skills" ]; then
    ln -sfn "$HOME/.local/share/amp/skills" "$_amp_config_dir/skills"
fi
unset _amp_config_dir

# amp reads ~/.config/amp/settings.json, but the directory enclave persists is
# ~/.local/share/amp (the one holding the login token). AMP_SETTINGS_FILE is
# amp's own documented override, so point it at the copy inside the store
# rather than leaving the settings file outside it.
AMP_SETTINGS_FILE="${ENCLAVE_TOOL_SETTINGS_TARGET:-$HOME/.local/share/amp/settings.json}"
export AMP_SETTINGS_FILE

# These settings are re-asserted on every start, overriding whatever the file
# carries, because the file persists between sessions:
#
#   amp.updates.mode                 `amp update` would replace the binary the
#                                    image was built with. static.ampcode.com is
#                                    denied as well, so this only saves a failed
#                                    download per session.
#   amp.remoteThreadCreation.enabled lets ampcode.com start a new thread in the
#                                    running TUI. Keep it off across restarts.
#   amp.dangerouslyAllowAll          persisted counterpart to the hidden
#                                    --dangerously-allow-all compatibility
#                                    flag. It has to track ENCLAVE_YOLO in both
#                                    directions so state from one mode cannot
#                                    leak into the next session.
# jq ships in the base image. Fail closed if it is ever absent: silently
# continuing could retain dangerouslyAllowAll=true in a --no-yolo session.
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required to apply Amp's update, remote-control, and permission defaults" >&2
    exit 1
fi

[ -s "$AMP_SETTINGS_FILE" ] || echo '{}' > "$AMP_SETTINGS_FILE"
_tmp="$(mktemp)"
if jq --argjson yolo "$_amp_yolo" '. + {
        "amp.updates.mode": "disabled",
        "amp.remoteThreadCreation.enabled": false,
        "amp.dangerouslyAllowAll": $yolo
    }' "$AMP_SETTINGS_FILE" > "$_tmp" 2>/dev/null; then
    mv "$_tmp" "$AMP_SETTINGS_FILE"
else
    # Amp accepts JSONC, but jq does not. Do not start with any of these safety
    # settings unenforced; the file can be converted to plain JSON by hand.
    rm -f "$_tmp"
    echo "Error: could not parse $AMP_SETTINGS_FILE as JSON; Amp defaults not applied" >&2
    exit 1
fi
unset _tmp _amp_yolo
