#!/bin/sh
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set -eu

if [ -z "${OBI_PERIPHERALS_ROOT:-}" ]; then
  OBI_PERIPHERALS_ROOT=$(git rev-parse --show-toplevel)
  export OBI_PERIPHERALS_ROOT
fi

if [ -z "${OBI_PERIPHERALS_BUILD_DIR:-}" ]; then
  OBI_PERIPHERALS_BUILD_DIR="${OBI_PERIPHERALS_ROOT}/build"
  export OBI_PERIPHERALS_BUILD_DIR
fi

run_cmd() {
  if [ "${DRYRUN:-0}" = 1 ]; then
    printf '%s\n' "$*"
  else
    "$@"
  fi
}

make_build_dir() {
  tool=$1
  ip=$2
  dir="${OBI_PERIPHERALS_BUILD_DIR}/${tool}/${ip}"
  mkdir -p "${dir}"
  printf '%s\n' "${dir}"
}

generate_flist() {
  out=$1
  shift
  mkdir -p "$(dirname "${out}")"
  bender script flist-plus --assume-rtl "$@" > "${out}"
}
