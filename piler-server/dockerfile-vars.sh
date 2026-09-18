# SPDX-License-Identifier: GPL-3.0-or-later
#
# Read version info from the Dockerfile ARGs. Source this, don't execute it -
# it sets base_image_tag, piler_version and piler_server_tag in the caller's
# shell.

# shellcheck shell=bash      # sourced fragment, no shebang of its own
# shellcheck disable=SC2034  # all three are consumed by the sourcing script

# Stop at '@' so a Renovate-added pinDigests suffix never leaks into piler_server_tag.
base_image_tag=$(grep -oP -m1 '^ARG BASE_IMAGE=ubuntu:\K[^@[:space:]]+' Dockerfile)
piler_version=$(grep -oP -m1 '^ARG PILER_VERSION=\K.*' Dockerfile)
piler_server_tag="${piler_version}-${base_image_tag#*-}"
