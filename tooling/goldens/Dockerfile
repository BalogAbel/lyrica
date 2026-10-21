# Linux/amd64 Flutter toolchain for widget goldens.
#
# CI compares goldens on ubuntu-latest (amd64) with Flutter 3.44.9 from the
# official stable tarball (subosito/flutter-action). Goldens are generated in
# this image so they match that renderer; see scripts/update-goldens.sh and
# docs/testing/testing-strategy.md. Keep FLUTTER_VERSION equal to the
# flutter-version in .github/workflows/ci.yml.
FROM --platform=linux/amd64 ubuntu:24.04

ARG FLUTTER_VERSION=3.44.9

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
  | tar -xJ -C /opt \
  && git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:${PATH}"

RUN flutter config --no-analytics >/dev/null \
  && flutter --version
