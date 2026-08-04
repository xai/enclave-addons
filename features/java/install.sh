#!/bin/bash
# Install a current Eclipse Temurin JDK together with Gradle, Maven, and the
# Eclipse JDT language server.
#
# Nothing here comes from apt: Debian trixie's default-jdk is OpenJDK 21 and
# its gradle package predates Gradle 5. The JDK is a Temurin tarball from
# api.adoptium.net, Gradle comes from services.gradle.org, Maven from the
# Apache CDN, jdtls from download.eclipse.org -- each checksum-verified
# against the digest its publisher ships. Everything lands under ~/.local,
# whose bin/ precedes /usr/bin in the container PATH.
set -euo pipefail

# Temurin feature release. 25 is the current LTS, 21 the previous one; a
# non-LTS release such as 26 works as long as Adoptium publishes GA builds
# for it. Changing any version in this file requires re-running the
# repository install.sh and `enclave --rebuild`.
JAVA_VERSION="25"

# "latest" resolves the current release at build time; pin like "9.1.0".
GRADLE_VERSION="latest"

# "latest" is the newest 3.9.x on the Apache CDN. Pin like "3.9.11", or
# "4.0.0" for the Maven 4 line -- the maven-<major> path is derived from the
# version, so a 4.x pin needs no other change.
MAVEN_VERSION="latest"

# "latest" is the current jdtls snapshot; pin a milestone like "1.49.0".
# jdtls is the one optional piece here: a failure installing it warns rather
# than failing the image build.
JDTLS_VERSION="latest"

# Heap ceiling for Gradle. A short-lived sandbox is no place for a JVM that
# sizes itself against the whole host's RAM. Maven reads MAVEN_OPTS from the
# environment instead, so its counterpart lives in feature-entrypoint.d.
JVM_HEAP="2g"

PREFIX="$HOME/.local"
BIN_DIR="$PREFIX/bin"
OPT_DIR="$PREFIX/opt"
JVM_DIR="$PREFIX/lib/jvm"
mkdir -p "$BIN_DIR" "$OPT_DIR" "$JVM_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$(uname -m)" in
    x86_64)  TEMURIN_ARCH="x64" ;;
    aarch64) TEMURIN_ARCH="aarch64" ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

# Download $1 to $2 and check it against the expected digest $3 ($4: sha256
# or sha512).
fetch_verified() {
    local url="$1" dest="$2" expected="$3" algo="$4" actual
    curl -fsSL --retry 3 "$url" -o "$dest"
    actual="$("${algo}sum" "$dest" | cut -d' ' -f1)"
    if [ "$actual" != "$expected" ]; then
        echo "Checksum mismatch for $url" >&2
        echo "  expected $expected" >&2
        echo "  actual   $actual" >&2
        return 1
    fi
}

# --- JDK ---------------------------------------------------------------------

echo "Resolving Temurin $JAVA_VERSION (linux/$TEMURIN_ARCH) from Adoptium"
curl -fsSL --retry 3 -o "$WORK/asset.json" \
    "https://api.adoptium.net/v3/assets/latest/$JAVA_VERSION/hotspot?os=linux&architecture=$TEMURIN_ARCH&image_type=jdk&vendor=eclipse"

JDK_INFO="$(jq -r 'map(select(.binary.image_type == "jdk"))[0] // empty
    | "\(.binary.package.link) \(.binary.package.checksum) \(.release_name)"' \
    "$WORK/asset.json")"
read -r JDK_URL JDK_SHA JDK_RELEASE <<<"$JDK_INFO"
if [ -z "${JDK_URL:-}" ]; then
    echo "Adoptium has no GA linux/$TEMURIN_ARCH JDK build for Java $JAVA_VERSION" >&2
    exit 1
fi

echo "Installing $JDK_RELEASE"
fetch_verified "$JDK_URL" "$WORK/jdk.tar.gz" "$JDK_SHA" sha256
JAVA_HOME="$JVM_DIR/temurin-$JAVA_VERSION"
rm -rf "$JAVA_HOME"
mkdir -p "$JAVA_HOME"
tar -xzf "$WORK/jdk.tar.gz" -C "$JAVA_HOME" --strip-components=1
# The entrypoint resolves JAVA_HOME through this symlink, so it needs no
# knowledge of the version installed here.
ln -sfn "temurin-$JAVA_VERSION" "$JVM_DIR/current"

export JAVA_HOME
export PATH="$JAVA_HOME/bin:$BIN_DIR:$PATH"
java -version 2>&1 | head -n 1

# --- Gradle ------------------------------------------------------------------

if [ "$GRADLE_VERSION" = "latest" ]; then
    curl -fsSL --retry 3 -o "$WORK/gradle-current.json" \
        https://services.gradle.org/versions/current
    GRADLE_VER="$(jq -r '.version // empty' "$WORK/gradle-current.json")"
    GRADLE_URL="$(jq -r '.downloadUrl // empty' "$WORK/gradle-current.json")"
    if [ -z "$GRADLE_VER" ] || [ -z "$GRADLE_URL" ]; then
        echo "Could not determine the current Gradle release" >&2
        exit 1
    fi
else
    GRADLE_VER="$GRADLE_VERSION"
    GRADLE_URL="https://services.gradle.org/distributions/gradle-$GRADLE_VER-bin.zip"
fi

echo "Installing Gradle $GRADLE_VER"
GRADLE_SHA="$(curl -fsSL --retry 3 "$GRADLE_URL.sha256")"
fetch_verified "$GRADLE_URL" "$WORK/gradle.zip" "$GRADLE_SHA" sha256
rm -rf "$OPT_DIR/gradle-$GRADLE_VER"
unzip -q "$WORK/gradle.zip" -d "$OPT_DIR"
ln -sfn "gradle-$GRADLE_VER" "$OPT_DIR/gradle"
# bin/gradle resolves its own distribution through the symlink, so linking
# the launcher alone is enough.
ln -sfn "../opt/gradle/bin/gradle" "$BIN_DIR/gradle"

# --- Maven -------------------------------------------------------------------

MAVEN_CDN="https://dlcdn.apache.org/maven"
MAVEN_ARCHIVE="https://archive.apache.org/dist/maven"

if [ "$MAVEN_VERSION" = "latest" ]; then
    MAVEN_VER="$(curl -fsSL --retry 3 "$MAVEN_CDN/maven-3/" \
        | grep -oE '3\.[0-9]+\.[0-9]+/' | tr -d '/' | sort -Vu | tail -n 1)"
    if [ -z "$MAVEN_VER" ]; then
        echo "Could not determine the latest Maven 3 release from $MAVEN_CDN" >&2
        exit 1
    fi
else
    MAVEN_VER="$MAVEN_VERSION"
fi

MAVEN_PATH="maven-${MAVEN_VER%%.*}/$MAVEN_VER/binaries/apache-maven-$MAVEN_VER-bin.tar.gz"
MAVEN_URL=""
# The CDN carries current releases only; archive.apache.org has every one.
# The digest and the tarball are published together, so finding one locates
# the other.
for base in "$MAVEN_CDN" "$MAVEN_ARCHIVE"; do
    if curl -fsSL --retry 2 "$base/$MAVEN_PATH.sha512" -o "$WORK/maven.sha512"; then
        MAVEN_URL="$base/$MAVEN_PATH"
        break
    fi
done
if [ -z "$MAVEN_URL" ]; then
    echo "No Maven $MAVEN_VER binaries on the Apache CDN or archive" >&2
    exit 1
fi

echo "Installing Maven $MAVEN_VER"
fetch_verified "$MAVEN_URL" "$WORK/maven.tar.gz" \
    "$(awk '{print $1}' "$WORK/maven.sha512")" sha512
rm -rf "$OPT_DIR/apache-maven-$MAVEN_VER"
tar -xzf "$WORK/maven.tar.gz" -C "$OPT_DIR"
ln -sfn "apache-maven-$MAVEN_VER" "$OPT_DIR/maven"
ln -sfn "../opt/maven/bin/mvn" "$BIN_DIR/mvn"

# --- Eclipse JDT language server ---------------------------------------------

# Optional: any LSP client in the container can drive `jdtls`, and the nvim
# integration below picks it up when the neovim feature is selected too.
install_jdtls() {
    local base name url sha
    if [ "$JDTLS_VERSION" = "latest" ]; then
        base="https://download.eclipse.org/jdtls/snapshots"
    else
        base="https://download.eclipse.org/jdtls/milestones/$JDTLS_VERSION"
    fi

    name="$(curl -fsSL --retry 2 "$base/latest.txt" 2>/dev/null || true)"
    [ -n "$name" ] || name="jdt-language-server-latest.tar.gz"
    url="$base/$name"

    sha="$(curl -fsSL --retry 2 "$url.sha256" 2>/dev/null | awk '{print $1}' || true)"
    if [ -n "$sha" ]; then
        fetch_verified "$url" "$WORK/jdtls.tar.gz" "$sha" sha256 || return 1
    else
        # The snapshot channel does not always publish a digest beside the
        # build it overwrites.
        echo "jdtls: no published sha256 for $name, taking it unverified" >&2
        curl -fsSL --retry 3 "$url" -o "$WORK/jdtls.tar.gz" || return 1
    fi

    rm -rf "$OPT_DIR/jdtls"
    mkdir -p "$OPT_DIR/jdtls"
    # The tarball has no top-level directory of its own.
    tar -xzf "$WORK/jdtls.tar.gz" -C "$OPT_DIR/jdtls"
    [ -x "$OPT_DIR/jdtls/bin/jdtls" ] || return 1
    ln -sfn "../opt/jdtls/bin/jdtls" "$BIN_DIR/jdtls"
}

# Drop an nvim-jdtls spec into the neovim feature's config when that feature
# is part of the same selection. Enclave has no dependency mechanism between
# features, so this is a plain probe: without neovim the JDK, Gradle, Maven,
# and the language server binary are installed all the same.
install_nvim_jdtls() {
    mkdir -p "$HOME/.config/nvim/lua/plugins"
    cat > "$HOME/.config/nvim/lua/plugins/java.lua" <<'JAVALUA'
-- java.lua -- nvim-jdtls against the jdtls installed by the java feature.
-- Loaded only for java buffers; a container with this feature baked in
-- behaves like plain neovim everywhere else.
local root_markers = {
  "gradlew", "mvnw", "settings.gradle", "settings.gradle.kts",
  "build.gradle", "build.gradle.kts", "pom.xml", ".git",
}

return {
  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    config = function()
      local function attach(bufnr)
        local root = vim.fs.root(bufnr, root_markers)
        if not root then return end
        require("jdtls").start_or_attach({
          -- bin/jdtls picks up JAVA_HOME from the environment; the feature
          -- entrypoint exports it.
          cmd = {
            "jdtls",
            "-data", vim.fn.stdpath("cache") .. "/jdtls/" .. vim.fn.fnamemodify(root, ":t"),
          },
          root_dir = root,
        })
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("jdtls_attach", { clear = true }),
        pattern = "java",
        callback = function(args) attach(args.buf) end,
      })
      -- The buffer that triggered this ft=java load already fired FileType.
      attach(0)
    end,
  },
}
JAVALUA

    # Bake the plugin into the image: the sandbox cannot reach github.com at
    # runtime unless the session network policy allows it.
    nvim --headless "+Lazy! sync" "+qa!" 2>&1 || true
    [ -d "$HOME/.local/share/nvim/lazy/nvim-jdtls" ]
}

if install_jdtls; then
    echo "jdtls installed: $OPT_DIR/jdtls"
    if command -v nvim >/dev/null 2>&1 && [ -f "$HOME/.config/nvim/init.lua" ]; then
        if install_nvim_jdtls; then
            echo "nvim-jdtls wired into the neovim feature's config"
        else
            echo "Warning: nvim-jdtls not installed; jdtls still works for other clients" >&2
        fi
    fi
else
    echo "Warning: jdtls not installed; the JDK, Gradle, and Maven are unaffected" >&2
    rm -f "$BIN_DIR/jdtls"
fi

# --- Container-friendly build defaults ---------------------------------------

# Written only when absent, so a project or a persisted home keeps its own.
mkdir -p "$HOME/.gradle"
if [ ! -f "$HOME/.gradle/gradle.properties" ]; then
    cat > "$HOME/.gradle/gradle.properties" <<EOF
# Written by the enclave java feature. Sandbox defaults, not project policy:
# delete or edit this file to get Gradle's own.
#
# No daemon: a container this short-lived never reuses one, and a leftover
# daemon holding the heap is worse than a cold start.
org.gradle.daemon=false
org.gradle.jvmargs=-Xmx$JVM_HEAP -XX:MaxMetaspaceSize=512m
# Agents read logs, not terminals.
org.gradle.console=plain
org.gradle.welcome=never
EOF
fi

mkdir -p "$HOME/.m2"
if [ ! -f "$HOME/.m2/settings.xml" ]; then
    cat > "$HOME/.m2/settings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!--
  Written by the enclave java feature. Deliberately minimal: local repository
  stays at the default ~/.m2/repository, and no mirror is configured.

  Add a <mirrors> entry here if your builds must go through an internal
  repository manager, and remember to allow that host on the gateway with
  "enclave run" and its allow-domain flag; see the feature README.
  (XML comments cannot contain a double hyphen, hence no literal flag.)
-->
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                              https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <interactiveMode>false</interactiveMode>
</settings>
EOF
fi

# --- Repository reachability check -------------------------------------------

# A blocked repository surfaces as a dependency-resolution error deep in a
# build log. This turns it into one line plus the flag that fixes it.
cat > "$BIN_DIR/java-repo-check" <<'EOF'
#!/bin/sh
# Report whether the repositories a Java build needs are reachable through
# the enclave gateway. Installed by the java feature.
set -u

status=0
check() {
    if curl -fsS -m 5 -o /dev/null "https://$1$2" 2>/dev/null; then
        printf 'ok       %s\n' "$1"
    else
        printf 'BLOCKED  %s\n' "$1"
        status=1
    fi
}

check repo.maven.apache.org /maven2/
check repo1.maven.org /maven2/
check plugins.gradle.org /m2/
check services.gradle.org /versions/current

if [ "$status" -ne 0 ]; then
    cat <<'HINT'

Blocked hosts are not in this session's network allowlist. A feature cannot
extend it, so add them on the host:

  enclave run --allow-domain repo.maven.apache.org \
              --allow-domain repo1.maven.org \
              --allow-domain plugins.gradle.org

or put them in "allow_domains" in ~/.config/enclave/config.json. Add
services.gradle.org only if you run ./gradlew rather than the installed
gradle; add your own repository manager, jitpack.io, or dl.google.com as
your projects require.
HINT
fi

exit "$status"
EOF
chmod +x "$BIN_DIR/java-repo-check"

# --- Verify ------------------------------------------------------------------

for tool in java javac jar jshell gradle mvn; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "$tool not found in PATH after installation" >&2
        exit 1
    }
done

echo "$JDK_RELEASE installed to $JAVA_HOME"
echo "  $(gradle --version 2>/dev/null | grep -m 1 '^Gradle ')"
echo "  $(mvn -v 2>/dev/null | head -n 1)"
