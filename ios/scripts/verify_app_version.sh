#!/bin/sh
set -eu

project_root="${SRCROOT}/.."
pubspec_path="${project_root}/pubspec.yaml"
version_config_path="${SRCROOT}/Flutter/AppVersion.xcconfig"

pubspec_version=$(
  /usr/bin/sed -nE \
    's/^version:[[:space:]]*([^+[:space:]]+).*$/\1/p' \
    "${pubspec_path}" | /usr/bin/head -n 1
)
configured_version=$(
  /usr/bin/sed -nE \
    's/^APP_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*$/\1/p' \
    "${version_config_path}" | /usr/bin/head -n 1
)

if [ -z "${pubspec_version}" ] || [ -z "${configured_version}" ]; then
  echo "error: Unable to read the loader version from pubspec.yaml or AppVersion.xcconfig." >&2
  exit 1
fi

if [ "${configured_version}" != "${pubspec_version}" ]; then
  echo "error: iOS APP_VERSION ${configured_version} does not match pubspec.yaml ${pubspec_version}." >&2
  exit 1
fi
