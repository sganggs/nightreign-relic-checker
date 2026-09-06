#!/usr/bin/env bash
# Repository bootstrap for the Nightreign Relic Checker monorepo.
#
# Runs after the source tree is checked out. Toolchains (Go, Node, JDK, Android
# SDK) come from the Docker image; this script only warms source-dependent
# dependency caches so later builds/tests are fast and offline-friendly.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

echo "==> Toolchain versions"
go version
node --version
java -version 2>&1 | head -n 1
echo "ANDROID_HOME=${ANDROID_HOME:-<unset>}"

echo "==> Warming Go module cache (windows/)"
( cd windows && go mod download )

echo "==> Warming Gradle + AndroidX dependency cache (android/)"
# assembleDebug pulls the Gradle distribution, AGP, Kotlin and AndroidX
# dependencies into the cache and validates the Android toolchain end-to-end.
( cd android && ./gradlew --no-daemon assembleDebug )

echo "==> Install complete"
