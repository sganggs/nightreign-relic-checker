# Development environment for the Nightreign Relic Checker monorepo.
#
# Builds the two platform clients that are buildable on Linux:
#   - windows/  Go 1.25 WebView2 shell + JS renderer/core (cross-compiles the .exe,
#               runs the Go save-file parser tests and the Node core-audit tests)
#   - android/  Gradle + Android SDK 36 (JVM rule/catalog tests + debug APK)
#
# The macOS/ client (Swift + Apple-only CommonCrypto/CryptoKit) cannot be built
# on Linux and is intentionally not provisioned here.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling. The ubuntu:24.04 image already ships a non-root `ubuntu` user (uid 1000).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip zip xz-utils \
        openjdk-17-jdk-headless \
        python3 \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Go 1.25 (repo modules declare `go 1.25`; the Ubuntu apt Go is too old).
ARG GO_VERSION=1.25.0
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm /tmp/go.tgz

# Node.js 22 for the renderer / core-audit JS tests and the static preview server.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Android SDK: command-line tools + platform-tools + API 36 platform + build-tools 36.
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ARG ANDROID_CLI_TOOLS=commandlinetools-linux-11076708_latest.zip
RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl -fsSL "https://dl.google.com/android/repository/${ANDROID_CLI_TOOLS}" -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
    && mv /tmp/cmdline-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools \
    && yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null \
    && "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" \
        "platform-tools" "platforms;android-36" "build-tools;36.0.0" > /dev/null \
    && chown -R ubuntu:ubuntu "${ANDROID_HOME}"

ENV PATH="/usr/local/go/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

USER ubuntu
WORKDIR /home/ubuntu
