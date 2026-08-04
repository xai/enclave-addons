# shellcheck shell=bash
# Make matplotlib behave in a container with no display.
#
# Without a backend pinned, matplotlib probes for a GUI toolkit at import time
# and a plt.show() somewhere in a generated script either warns or blocks.
# Agg renders straight to a file, which is the only useful thing here anyway.
# Both variables are only set when the caller has not: a session that does
# have a display should keep it.
if [ -z "${MPLBACKEND:-}" ]; then
    export MPLBACKEND=Agg
fi

# install.sh warmed the font cache in this directory. Leaving it to the default
# would mean rebuilding the cache on first plot, and matplotlib prints a
# several-second warning while it does.
if [ -z "${MPLCONFIGDIR:-}" ] && [ -d "$HOME/.cache/matplotlib" ]; then
    export MPLCONFIGDIR="$HOME/.cache/matplotlib"
fi
