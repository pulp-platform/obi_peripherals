#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if [ -z "${OBI_PERIPHERALS_ROOT:-}" ]; then
  common_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  OBI_PERIPHERALS_ROOT=$(CDPATH= cd -- "${common_dir}/.." && pwd)
  export OBI_PERIPHERALS_ROOT
fi

if [ -z "${OBI_PERIPHERALS_BUILD_DIR:-}" ]; then
  OBI_PERIPHERALS_BUILD_DIR="${OBI_PERIPHERALS_ROOT}/build"
  export OBI_PERIPHERALS_BUILD_DIR
fi

run_cmd() {
  if [ "${VERBOSE:-0}" = 1 ] || [ "${DRYRUN:-0}" = 1 ]; then
    printf '+ '
    printf ' %s' "$@"
    printf '\n'
  fi
  if [ "${DRYRUN:-0}" = 1 ]; then
    return 0
  else
    "$@"
  fi
}

make_build_dir() {
  tool=$1
  ip=$2
  dir="${OBI_PERIPHERALS_BUILD_DIR}/${tool}/${ip}"
  if [ "${DRYRUN:-0}" != 1 ]; then
    mkdir -p "${dir}"
  fi
  printf '%s\n' "${dir}"
}

generate_flist() {
  out=$1
  shift
  if [ "${DRYRUN:-0}" = 1 ]; then
    printf '+  bender script flist-plus'
    printf ' %s' "$@"
    printf ' > %s\n' "${out}"
  else
    mkdir -p "$(dirname "${out}")"
    bender script flist-plus "$@" > "${out}"
  fi
}
