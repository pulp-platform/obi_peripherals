#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${script_dir}/../../scripts/common.sh"

usage() {
  cat <<'EOF'
Usage: flow/verilator/run_verilator.sh IP [OPTIONS]

Options:
  --help, -h       Show this help
  --dry-run, -n    Print commands without running them
  --verbose, -v    Print commands before running them
  --top TOP        Testbench top module
  --flist          Regenerate the file list
  --build          Build the Verilator simulation
  --run            Run the built simulation
EOF
}

run_logged() {
  local log=$1
  shift
  if [ "${DRYRUN:-0}" = 1 ]; then
    run_cmd "$@"
  else
    mkdir -p "$(dirname "${log}")"
    if [ "${VERBOSE:-0}" = 1 ]; then
      printf '+ '
      printf ' %s' "$@"
      printf '\n'
    fi
    "$@" 2>&1 | tee "${log}"
  fi
}

[ "$#" -gt 0 ] || { usage; exit 1; }
ip=$1
shift
[ -d "${OBI_PERIPHERALS_ROOT}/${ip}" ] || {
  echo "Unknown IP directory: ${OBI_PERIPHERALS_ROOT}/${ip}" >&2
  exit 1
}
top=tb_${ip}
do_flist=0
do_build=0
do_run=0
DRYRUN=${DRYRUN:-0}
VERBOSE=${VERBOSE:-0}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --top)
      [ "$#" -ge 2 ] || { echo "Missing argument for --top" >&2; exit 1; }
      top=$2
      shift 2
      ;;
    --flist)
      do_flist=1
      shift
      ;;
    --build)
      do_build=1
      shift
      ;;
    --run)
      do_run=1
      shift
      ;;
    --dry-run|-n)
      DRYRUN=1
      shift
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[ "${do_flist}${do_build}${do_run}" != "000" ] || { usage; exit 1; }
case "${VERILATOR_JOBS:-4}" in
  ''|*[!0-9]*|0)
    echo "VERILATOR_JOBS must be a positive integer" >&2
    exit 1
    ;;
esac
export DRYRUN VERBOSE

build_dir=$(make_build_dir verilator "${ip}")
flist="${build_dir}/${ip}.f"
top_build_dir="${build_dir}/${top}"
build_log="${top_build_dir}/build.log"
run_log="${top_build_dir}/run.log"

if [ "${do_flist}" = 1 ] || [ "${do_build}" = 1 ]; then
  (
    cd "${OBI_PERIPHERALS_ROOT}"
    generate_flist "${flist}" --top "${top}" -t rtl -t simulation -t verilator \
      -D VERILATOR=1 -D COMMON_CELLS_ASSERTS_OFF=1
  )
  echo "[INFO][Bender] File list: ${flist}"
fi

if [ "${do_build}" = 1 ]; then
  echo "[INFO][Verilator] Building ${top}"
  verilator_cmd=(verilator)
  if [ "${DRYRUN}" != 1 ]; then
    if verilator --version >/dev/null 2>&1; then
      verilator_cmd=(verilator)
    elif verilator verilator --version >/dev/null 2>&1; then
      verilator_cmd=(verilator verilator)
    else
      echo "Verilator is not available" >&2
      exit 1
    fi
  fi
  verilator_args=(
    -Wno-fatal
    -Wno-style
    --binary
    --timing
    --autoflush
    --x-assign fast
    --x-initial fast
    -O3
    -j "${VERILATOR_JOBS:-4}"
    --top "${top}"
    --Mdir "${top_build_dir}"
    -f "${flist}"
  )
  if [ "${DRYRUN}" != 1 ]; then
    mkdir -p "${top_build_dir}"
  fi
  (
    cd "${OBI_PERIPHERALS_ROOT}"
    run_logged "${build_log}" "${verilator_cmd[@]}" "${verilator_args[@]}"
  )
fi

if [ "${do_run}" = 1 ]; then
  echo "[INFO][Verilator] Running ${top}"
  if [ "${DRYRUN}" != 1 ] && [ ! -x "${top_build_dir}/V${top}" ]; then
    echo "Simulation binary not found: ${top_build_dir}/V${top}" >&2
    echo "Build it first with --build" >&2
    exit 1
  fi
  run_logged "${run_log}" "${top_build_dir}/V${top}"
fi
