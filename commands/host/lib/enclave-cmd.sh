# shellcheck shell=sh
#
# Shared helpers for the user commands in the parent directory.
#
# Not a command itself: enclave's discovery only considers regular files
# directly inside commands/host and skips subdirectories silently, so nothing
# here shows up in `enclave --help`. (A non-executable file placed directly in
# commands/host would instead be reported as a warning.)
#
# Usage from a command:
#   . "${0%/*}/lib/enclave-cmd.sh"
#   enclave_cmd_summary="What this command does."
#   enclave_cmd_synopsis="[<target>]"          # only if it takes a positional
#   prompt=$(cat <<'EOF'
#   ...
#   EOF
#   )
#   enclave_run "$prompt" "$@"
#
# A command that wants a specific tool declares both the tool and its flags,
# since tool flags rarely transfer between tools:
#   enclave_cmd_tool=claude
#   enclave_cmd_args="--model opus --effort high"
#
# This library declares no tool of its own: a command that declares none runs
# whatever `enclave run` defaults to. Machine-local preferences belong in
# lib/enclave-cmd.local.sh, which the add-ons installer never writes; see
# lib/enclave-cmd.local.sh.example for the variables it can set.
#
# Per invocation, the env vars override all of the above:
#   ENCLAVE_CMD_TOOL=codex enclave triage        # tool flags are dropped with it
#   ENCLAVE_CMD_ARGS= enclave rebase             # keep the tool's own defaults
#   ENCLAVE_CMD_TOOL=claude ENCLAVE_CMD_ARGS="--model sonnet" enclave check-pr
#
# Run any command with -h to see all of this with its resolved values.

# Resolved from the calling command's own path, so an in-tree checkout and an
# installed copy both find their neighbouring lib. enclave invokes user
# commands by absolute path.
enclave_cmd_dir=${0%/*}
enclave_cmd_lib=$enclave_cmd_dir/lib/enclave-cmd.sh
enclave_cmd_config=${ENCLAVE_CMD_CONFIG:-$enclave_cmd_dir/lib/enclave-cmd.local.sh}

enclave_cmd_tool=
enclave_cmd_args=
enclave_cmd_summary=
enclave_cmd_synopsis=

# Sourced before the calling command's declarations, so the tool and flags set
# here are defaults that a command still overrides. The same file's per-command
# variables are applied later, in enclave_run, and do win.
if [ -r "$enclave_cmd_config" ]; then
    # shellcheck source=/dev/null
    . "$enclave_cmd_config"
fi

# Snapshot to distinguish "the command declared this" from "inherited from the
# local config" once the command has had its say.
enclave_cmd_inherited_tool=$enclave_cmd_tool
enclave_cmd_inherited_args=$enclave_cmd_args

# enclave_cmd_help — usage for the calling command, with resolved defaults.
enclave_cmd_help() {
    enclave_cmd_name=${0##*/}
    if [ -n "$enclave_cmd_synopsis" ]; then
        printf 'Usage: enclave %s %s [enclave flags] [-- tool flags]\n' \
            "$enclave_cmd_name" "$enclave_cmd_synopsis"
    else
        printf 'Usage: enclave %s [enclave flags] [-- tool flags]\n' "$enclave_cmd_name"
    fi
    if [ -n "$enclave_cmd_summary" ]; then
        printf '\n%s\n' "$enclave_cmd_summary"
    fi

    printf '\nRuns: enclave run'
    if [ -n "$enclave_cmd_tool" ]; then
        printf ' --tool %s' "$enclave_cmd_tool"
    fi
    if [ -n "$enclave_cmd_args" ]; then
        printf ' -- %s' "$enclave_cmd_args"
    fi
    printf ' <prompt>\n'
    if [ -z "$enclave_cmd_tool" ]; then
        printf '(no tool declared, so enclave run picks its own default)\n'
    fi

    printf '\nOverrides:\n'
    printf '  --tool <tool>               another tool; drops the tool flags above\n'
    printf '  -- <flags>                  extra tool flags, appended after the defaults\n'
    printf '  ENCLAVE_CMD_TOOL=<tool>     same as --tool, as an env var\n'
    printf '  ENCLAVE_CMD_ARGS=<flags>    replace the tool flags; empty keeps the\n'
    printf '                              tool'"'"'s own defaults\n'
    printf '\nDefined in: %s\n' "$0"
    printf 'Defaults in: %s\n' "$enclave_cmd_lib"
    if [ -r "$enclave_cmd_config" ]; then
        printf 'Local defaults: %s\n' "$enclave_cmd_config"
    else
        printf 'Local defaults: %s (not present)\n' "$enclave_cmd_config"
    fi
    printf 'Enclave run flags: enclave run --help\n'
}

# enclave_run <prompt> [caller args...]
#
# Execs enclave as:
#   run [--tool <tool>] [caller enclave flags] -- [default tool flags] [caller tool flags] <prompt>
#
# Call-site flags land after the defaults and therefore win. A --tool at the
# call site replaces the tool and drops the default tool flags along with it.
# -h or --help before the -- prints usage instead of starting a session.
enclave_run() {
    enclave_cmd_prompt=$1
    shift

    # A command that declared a tool but no flags must not inherit flags aimed
    # at the local config's tool: tool flags rarely transfer between tools.
    if [ "$enclave_cmd_tool" != "$enclave_cmd_inherited_tool" ] &&
        [ "$enclave_cmd_args" = "$enclave_cmd_inherited_args" ]; then
        enclave_cmd_args=
    fi

    # Per-command overrides from the local config, e.g. enclave_cmd_tool_rebase
    # or enclave_cmd_args_check_pr (non-alphanumerics in the name become '_').
    enclave_cmd_key=$(printf '%s' "${0##*/}" | tr -c '[:alnum:]' '[_*]')
    eval "enclave_cmd_override_tool=\${enclave_cmd_tool_$enclave_cmd_key-}"
    eval "enclave_cmd_override_args=\${enclave_cmd_args_$enclave_cmd_key+set}"
    if [ -n "$enclave_cmd_override_tool" ] &&
        [ "$enclave_cmd_override_tool" != "$enclave_cmd_tool" ]; then
        enclave_cmd_tool=$enclave_cmd_override_tool
        enclave_cmd_args=
    fi
    if [ -n "$enclave_cmd_override_args" ]; then
        eval "enclave_cmd_args=\$enclave_cmd_args_$enclave_cmd_key"
    fi

    if [ -n "${ENCLAVE_CMD_TOOL:-}" ] && [ "$ENCLAVE_CMD_TOOL" != "$enclave_cmd_tool" ]; then
        enclave_cmd_tool=$ENCLAVE_CMD_TOOL
        enclave_cmd_args=
    fi
    if [ -n "${ENCLAVE_CMD_ARGS+set}" ]; then
        enclave_cmd_args=$ENCLAVE_CMD_ARGS
    fi

    enclave_cmd_sep=0
    enclave_cmd_tool_given=0
    enclave_cmd_help_given=0
    enclave_cmd_want_tool=0
    for enclave_cmd_arg in "$@"; do
        if [ "$enclave_cmd_arg" = "--" ]; then
            enclave_cmd_sep=1
            break
        fi
        # Track the call-site tool so -h reports the effective one.
        if [ "$enclave_cmd_want_tool" -eq 1 ]; then
            enclave_cmd_tool=$enclave_cmd_arg
            enclave_cmd_want_tool=0
            continue
        fi
        case "$enclave_cmd_arg" in
            --tool)
                enclave_cmd_tool_given=1
                enclave_cmd_want_tool=1
                ;;
            --tool=*)
                enclave_cmd_tool_given=1
                enclave_cmd_tool=${enclave_cmd_arg#--tool=}
                ;;
            -h|--help) enclave_cmd_help_given=1 ;;
        esac
    done
    if [ "$enclave_cmd_tool_given" -eq 1 ]; then
        enclave_cmd_args=
    fi
    if [ "$enclave_cmd_help_given" -eq 1 ]; then
        enclave_cmd_help
        exit 0
    fi

    # Give the defaults a single fixed insertion point. With no defaults to
    # splice, the caller's arguments are passed through untouched.
    if [ "$enclave_cmd_sep" -eq 0 ] && [ -n "$enclave_cmd_args" ]; then
        set -- "$@" --
        enclave_cmd_sep=1
    fi

    # Arguments are consumed from the front and re-appended at the back, so the
    # defaults appended before the loop end up ahead of the caller's own flags.
    # set -- inside a function only touches the function's own parameters.
    enclave_cmd_argc=$#
    set -- "$@" run
    if [ "$enclave_cmd_tool_given" -eq 0 ] && [ -n "$enclave_cmd_tool" ]; then
        set -- "$@" --tool "$enclave_cmd_tool"
    fi
    enclave_cmd_i=0
    enclave_cmd_spliced=0
    while [ "$enclave_cmd_i" -lt "$enclave_cmd_argc" ]; do
        enclave_cmd_arg=$1
        shift
        enclave_cmd_i=$((enclave_cmd_i + 1))
        if [ "$enclave_cmd_spliced" -eq 0 ] && [ "$enclave_cmd_arg" = "--" ]; then
            enclave_cmd_spliced=1
            set -- "$@" --
            # Word-split the declared tool flags; -f keeps them unglobbed.
            set -f
            # shellcheck disable=SC2086
            set -- "$@" $enclave_cmd_args
            set +f
            continue
        fi
        set -- "$@" "$enclave_cmd_arg"
    done

    exec "${ENCLAVE_BIN:-enclave}" "$@" "$enclave_cmd_prompt"
}
