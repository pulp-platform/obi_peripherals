#!/bin/sh
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${script_dir}/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/run_checks.sh [OPTIONS]

Options:
  --help, -h     Show this help
  --dry-run, -n  Print commands without running them
  --slang IP     Run slang lint/elaboration for IP
  --yosys IP     Run yosys-slang elaboration for IP
  --verilator IP Build and run Verilator tests for IP
  --all IP       Run the lightweight checks for IP
EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 0
fi

DRYRUN=0
for arg in "$@"; do
  [ "${arg}" = "--dry-run" ] || [ "${arg}" = "-n" ] && DRYRUN=1
done
export DRYRUN

run_verilator_tests() {
  ip=$1
  tops=
  if [ -f "${OBI_PERIPHERALS_ROOT}/${ip}/flow.env" ]; then
    # shellcheck disable=SC1090
    . "${OBI_PERIPHERALS_ROOT}/${ip}/flow.env"
    tops=${VERILATOR_TOPS:-${VERILATOR_TOP:-}}
  fi
  [ -n "${tops}" ] || tops="tb_${ip}_rx_smoke"

  for top in ${tops}; do
    run_cmd "${OBI_PERIPHERALS_ROOT}/flow/verilator/run_verilator.sh" "$ip" --top "$top" --build
    run_cmd "${OBI_PERIPHERALS_ROOT}/flow/verilator/run_verilator.sh" "$ip" --top "$top" --run
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --dry-run|-n)
      shift
      ;;
    --slang)
      run_cmd "${OBI_PERIPHERALS_ROOT}/flow/slang/run_slang.sh" "$2"
      shift 2
      ;;
    --yosys)
      run_cmd "${OBI_PERIPHERALS_ROOT}/flow/yosys/run_yosys.sh" "$2" --elab
      shift 2
      ;;
    --verilator)
      run_verilator_tests "$2"
      shift 2
      ;;
    --all)
      run_cmd "${OBI_PERIPHERALS_ROOT}/flow/slang/run_slang.sh" "$2"
      run_cmd "${OBI_PERIPHERALS_ROOT}/flow/yosys/run_yosys.sh" "$2" --elab
      run_verilator_tests "$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done
