#!/bin/sh
set -eu

# Writes registry credentials into a Docker config so the Supabase CLI pulls
# the local stack's images authenticated.
#
# Usage: REGISTRY_USERNAME=... REGISTRY_TOKEN=... DOCKER_CONFIG=<dir> \
#          docker-registry-auth.sh <registry>
#
# Why not `docker login`: the Supabase CLI looks credentials up by the literal
# registry string it pulls from (SUPABASE_INTERNAL_IMAGE_REGISTRY, for example
# `docker.io`), and the Docker config store matches that key exactly. A Docker
# Hub `docker login` stores the key `https://index.docker.io/v1/`, which the CLI
# does not find, so its pulls would stay anonymous. This script writes the key
# `<registry>` itself.
#
# DOCKER_CONFIG must be set explicitly: the script never writes to the default
# ~/.docker, so a developer's own config is never clobbered. The directory is
# expected to be fresh; an existing config.json in it is overwritten.
#
# Missing credentials are not an error (for example fork PRs without secrets):
# the script says so on stderr and pulls stay anonymous. The token and the
# derived auth string are never printed.

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "usage: docker-registry-auth.sh <registry>" >&2
  exit 2
fi
registry="$1"

if [ -z "${DOCKER_CONFIG:-}" ]; then
  echo "docker-registry-auth.sh: DOCKER_CONFIG must be set (refusing to write to the default Docker config)" >&2
  exit 2
fi

if [ -z "${REGISTRY_USERNAME:-}" ] || [ -z "${REGISTRY_TOKEN:-}" ]; then
  echo "docker-registry-auth.sh: no credentials for $registry; image pulls stay anonymous" >&2
  exit 0
fi

auth="$(printf '%s:%s' "$REGISTRY_USERNAME" "$REGISTRY_TOKEN" | base64 | tr -d '\n')"

umask 077
mkdir -p "$DOCKER_CONFIG"
chmod 700 "$DOCKER_CONFIG"
printf '{"auths":{"%s":{"auth":"%s"}}}' "$registry" "$auth" >"$DOCKER_CONFIG/config.json"
chmod 600 "$DOCKER_CONFIG/config.json"
