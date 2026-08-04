# shellcheck shell=bash
# Put the Temurin JDK installed by the java feature on PATH. gradle and mvn
# are symlinked into ~/.local/bin, which is already on PATH; the JDK is not,
# because javac/jar/jshell/keytool should not be scattered through it.
if [ -x "$HOME/.local/lib/jvm/current/bin/java" ]; then
    JAVA_HOME="$(cd "$HOME/.local/lib/jvm/current" && pwd -P)"
    export JAVA_HOME
    case ":$PATH:" in
        *":$JAVA_HOME/bin:"*) ;;
        *) PATH="$JAVA_HOME/bin:$PATH"; export PATH ;;
    esac

    # Gradle takes its ceiling from ~/.gradle/gradle.properties; Maven only
    # reads the environment. Don't override a value the caller passed in.
    if [ -z "${MAVEN_OPTS:-}" ]; then
        export MAVEN_OPTS="-Xmx2g"
    fi
fi
