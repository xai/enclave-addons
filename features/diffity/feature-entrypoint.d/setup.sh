# shellcheck shell=bash
# Give diffity's review data a home that outlives the container
#
# Diffity keeps comment threads and tours in ~/.diffity/<repo-hash>/, where
# <repo-hash> is the first 12 hex characters of sha256 over the repository root
# path and reviews.db sits inside that directory. The container home is
# ephemeral, so that per-repository directory has to come from the host. Two
# locations, in order:
#
#   1. A host directory mounted with --add-dir. Enclave mounts it at the path
#      it has on the host, which is outside the container home and outside
#      every store enclave manages, so nothing rewrites it between sessions and
#      every tool sees the same reviews:
#
#        enclave --features "+diffity" --add-dir ~/.local/state/enclave-diffity
#
#      Mount it elsewhere by also setting ENCLAVE_DIFFITY_STORE to that path
#      (host env var plus --pass-env ENCLAVE_DIFFITY_STORE).
#
#   2. The tool config store, which is where this feature used to put the whole
#      directory. It is per project, per tool and per store key, and with
#      host_config=passthrough enclave's config-source overlay deletes every
#      entry in it that is not on its preserve list -- which has cost a review
#      database before. It is the fallback, not the recommendation.
#
# Every outcome below prints a line. Which of the three a session got is not
# otherwise observable until reviews go missing, and the fallback is the branch
# that already destroyed a database once.
#
# See README.md, "Persisting reviews".

# Enclave mounts --add-dir directories at their host path, so a store is a
# mount point. Test for that rather than comparing paths: when the host user is
# also named "agent" the store's host path is character-for-character
# $HOME/.local/state/enclave-diffity, and a path test rejects the real mount.
_diffity_is_mount() {
    [ -r /proc/self/mountinfo ] || return 1
    while read -r _ _ _ _ _diffity_mp _; do
        [ "$_diffity_mp" = "$1" ] && return 0
    done < /proc/self/mountinfo
    return 1
}

_diffity_store=""
if [ -n "${ENCLAVE_DIFFITY_STORE:-}" ]; then
    # An explicit store is intent, not a guess: never fall through to the scan
    # below and silently adopt some other directory.
    if [ ! -d "$ENCLAVE_DIFFITY_STORE" ]; then
        echo "Warning: diffity store $ENCLAVE_DIFFITY_STORE is not present in this session; mount it with --add-dir. Reviews will not persist"
    elif [ ! -w "$ENCLAVE_DIFFITY_STORE" ]; then
        echo "Warning: diffity store $ENCLAVE_DIFFITY_STORE is not writable by $(id -un 2>/dev/null || echo "$USER"); reviews will not persist"
    else
        _diffity_store="$ENCLAVE_DIFFITY_STORE"
    fi
else
    for _diffity_candidate in /home/*/.local/state/enclave-diffity \
                              /Users/*/.local/state/enclave-diffity; do
        [ -d "$_diffity_candidate" ] || continue
        _diffity_is_mount "$_diffity_candidate" || continue
        if [ ! -w "$_diffity_candidate" ]; then
            echo "Warning: diffity store $_diffity_candidate is not writable by $(id -un 2>/dev/null || echo "$USER"); reviews will not persist"
            continue
        fi
        _diffity_store="$_diffity_candidate"
        break
    done
fi

if [ -n "$_diffity_store" ]; then
    # Only the per-repository directories are shared. registry.json lists
    # running instances by PID and port, and both are container-local: sessions
    # sharing one registry would reuse each other's dead entries, and a
    # starting session would drop a running one's.
    mkdir -p "$HOME/.diffity" 2>/dev/null || true

    # Repositories this store has seen before, so a session working on more
    # than one of them keeps them all.
    for _diffity_dir in "$_diffity_store"/*/; do
        _diffity_dir="${_diffity_dir%/}"
        [ -d "$_diffity_dir" ] || continue
        _diffity_name="${_diffity_dir##*/}"
        if [ -e "$HOME/.diffity/$_diffity_name" ] || [ -L "$HOME/.diffity/$_diffity_name" ]; then
            continue
        fi
        ln -s "$_diffity_dir" "$HOME/.diffity/$_diffity_name" 2>/dev/null || true
    done

    # And this session's repository, which the store has not seen yet on first
    # use. The hash mirrors diffity's own: sha256 of the repository root, first
    # 12 hex characters. That couples this feature to a layout diffity can
    # change under it -- an earlier version of this file linked
    # ~/.diffity/reviews.db, a path diffity had already stopped using, and
    # every review died with its container. Compare the directory named below
    # against repoHash in `diffity list --json` after a version bump; if they
    # differ, the layout moved again.
    _diffity_repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    _diffity_hash=""
    if [ -n "$_diffity_repo" ]; then
        _diffity_hash="$(printf %s "$_diffity_repo" | sha256sum 2>/dev/null | cut -c1-12)"
    fi
    case "$_diffity_hash" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
        *) _diffity_hash="" ;;
    esac

    if [ -z "$_diffity_hash" ]; then
        echo "Warning: diffity could not identify this repository (no git checkout at $PWD, or sha256sum missing); reviews for it will not persist"
    elif ! mkdir -p "$_diffity_store/$_diffity_hash" 2>/dev/null; then
        echo "Warning: diffity could not create $_diffity_store/$_diffity_hash; reviews for $_diffity_repo will not persist"
    else
        if [ ! -e "$HOME/.diffity/$_diffity_hash" ] && [ ! -L "$HOME/.diffity/$_diffity_hash" ]; then
            ln -s "$_diffity_store/$_diffity_hash" "$HOME/.diffity/$_diffity_hash" 2>/dev/null || true
        fi
        # Claim persistence only when the entry resolves into the store. A real
        # directory sitting at that path -- left by an image, another
        # entrypoint fragment, or a diffity that stopped following this layout
        # -- satisfies a -d test while every review still dies with the
        # container, and this line is what the user is asked to trust.
        _diffity_target="$(readlink -f "$HOME/.diffity/$_diffity_hash" 2>/dev/null || true)"
        if [ -L "$HOME/.diffity/$_diffity_hash" ] &&
            [ -n "$_diffity_target" ] &&
            [ "$_diffity_target" = "$(readlink -f "$_diffity_store/$_diffity_hash" 2>/dev/null)" ]; then
            echo "Diffity: reviews for $_diffity_repo persist in $_diffity_store/$_diffity_hash"
        else
            echo "Warning: $HOME/.diffity/$_diffity_hash is not linked to the store; reviews for $_diffity_repo will not persist"
        fi
    fi
elif [ -n "${ENCLAVE_TOOL_CONFIG_DIR:-}" ] && [ ! -e "$HOME/.diffity" ]; then
    if mkdir -p "$ENCLAVE_TOOL_CONFIG_DIR/diffity" 2>/dev/null &&
        ln -s "$ENCLAVE_TOOL_CONFIG_DIR/diffity" "$HOME/.diffity" 2>/dev/null; then
        echo "Warning: no diffity store is mounted; reviews go to the tool config store, which enclave's config overlay can delete at session start. See the Diffity feature README, \"Persisting reviews\""
    fi
fi
unset _diffity_store _diffity_candidate _diffity_dir _diffity_name _diffity_repo _diffity_hash _diffity_target _diffity_mp
unset -f _diffity_is_mount 2>/dev/null || true

# The registry tracks running instances by PID. PIDs are per-container and get
# recycled, so an entry left behind by an earlier session can point the skills
# at a port nothing is listening on. Only the config-store fallback can carry
# one across sessions, but removing it is right either way.
rm -f "$HOME/.diffity/registry.json" "$HOME/.diffity/registry.lock" 2>/dev/null || true
