# Java (Temurin)

A Java toolchain for the container: the current LTS [Eclipse Temurin](https://adoptium.net/)
JDK, [Gradle](https://gradle.org/), [Maven](https://maven.apache.org/), and the
[Eclipse JDT language server](https://github.com/eclipse-jdtls/eclipse.jdt.ls).

Debian trixie's `default-jdk` is OpenJDK 21 and its `gradle` package predates
Gradle 5, so nothing here comes from apt. Each piece is fetched from its
publisher at image build time and verified against the digest that publisher
ships.

## What it does

- Installs Temurin **Java 25** (current LTS) into `~/.local/lib/jvm/temurin-25`,
  for x86_64 and aarch64, resolved through the Adoptium API so the build always
  gets the newest patch of that feature release
- Installs the current **Gradle** and **Maven 3.9.x** into `~/.local/opt`, with
  their launchers symlinked into `~/.local/bin` (which precedes `/usr/bin` in
  the container `PATH`)
- Installs **jdtls** and, when the [neovim](../neovim/) feature is selected too,
  drops an [nvim-jdtls](https://github.com/mfussenegger/nvim-jdtls) spec into
  its config so java buffers get completion and diagnostics with no network
- Exports `JAVA_HOME` and prepends `$JAVA_HOME/bin` to `PATH` at container
  start, and sets `MAVEN_OPTS=-Xmx2g` unless the caller passed one
- Writes sandbox build defaults — `~/.gradle/gradle.properties` (no daemon,
  2 GB heap, plain console) and a minimal `~/.m2/settings.xml` — but only when
  those files don't already exist
- Installs `java-repo-check`, which reports whether the repositories a build
  needs are reachable and prints the flag that unblocks them

Together this adds roughly 600 MB to the image (JDK ~340 MB, Gradle ~130 MB,
jdtls ~80 MB, Maven ~10 MB).

## Dependency downloads need an allowlist entry

Installation happens at build time, where the network is open. **Builds run
later, behind the gateway, and Maven Central is not on the default allowlist.**
A feature cannot extend that allowlist — `gateway-allowlist.conf` belongs to
tools — so the domains have to come from the host:

```bash
enclave run --allow-domain repo.maven.apache.org \
            --allow-domain repo1.maven.org \
            --allow-domain plugins.gradle.org
```

or, permanently, in `"allow_domains"` in `~/.config/enclave/config.json`.
Inside the container, `java-repo-check` tells you where you stand:

```
$ java-repo-check
ok       repo.maven.apache.org
ok       repo1.maven.org
BLOCKED  plugins.gradle.org
BLOCKED  services.gradle.org
```

Add what your projects actually resolve from — a repository manager,
`jitpack.io`, `dl.google.com` for Android — and nothing else.

`services.gradle.org` is only needed for `./gradlew`: the wrapper downloads its
own Gradle distribution on first run. Running the installed `gradle` instead
avoids that download entirely, at the cost of ignoring the version the project
pinned. Once dependencies are in `~/.m2/repository` or the Gradle cache, an
offline build (`mvn -o`, `gradle --offline`) needs no network at all.

## Configuration

Versions are variables at the top of `install.sh`; edit, re-run the repository
`install.sh`, and `enclave --rebuild`:

| Variable | Default | Notes |
| --- | --- | --- |
| `JAVA_VERSION` | `25` | Temurin feature release: `21` for the previous LTS, `26` for the current non-LTS |
| `GRADLE_VERSION` | `latest` | Or a pin like `9.1.0` |
| `MAVEN_VERSION` | `latest` | Newest 3.9.x. A pin like `4.0.0` also works — the `maven-<major>` path is derived from it |
| `JDTLS_VERSION` | `latest` | Snapshot channel, or a milestone like `1.49.0` |
| `JVM_HEAP` | `2g` | Gradle's ceiling; Maven's is in `feature-entrypoint.d/setup.sh` |

A Gradle release only supports Java versions it knows about, so an old
`GRADLE_VERSION` pinned against a new `JAVA_VERSION` fails at startup with an
unsupported-class-file error. Move both or neither.

Per-project Java versions are better handled by Gradle/Maven toolchains than by
this feature — but toolchain auto-provisioning downloads a JDK at build time,
which the gateway blocks. Set `JAVA_VERSION` to the release your projects need,
or add a second JDK to `install.sh` and point the toolchain at it.

## Failure behaviour

The spec sets `failOnInstallError: true`: a container that reports a Java
feature but has no working `javac` is worse than a failed build. jdtls is the
exception — if its download fails the build continues with a warning, since the
JDK, Gradle, and Maven are all still there.

## Enablement

Opt-in (`defaultEnabled: false`). The repository install script enables it in
your global enclave config; see the [repository README](../../README.md).

```bash
./install.sh java
enclave --rebuild
```

For the editor integration, install and select neovim alongside it:

```bash
./install.sh java neovim
enclave --tool neovim --features "+neovim,+java" --rebuild
```
