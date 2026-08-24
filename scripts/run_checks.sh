#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
set -f

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

require_ip_arg() {
  if [ "$#" -lt 2 ] || [ "${2#-}" != "$2" ]; then
    echo "Missing IP argument for $1" >&2
    usage >&2
    exit 1
  fi
}

DRYRUN=0
for arg in "$@"; do
  [ "${arg}" = "--dry-run" ] || [ "${arg}" = "-n" ] && DRYRUN=1
done
export DRYRUN

run_verilator_test() {
  ip=$1
  run_cmd "${OBI_PERIPHERALS_ROOT}/flow/verilator/run_verilator.sh" \
    "$ip" --build --run
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
      require_ip_arg "$@"
      run_cmd "${OBI_PERIPHERALS_ROOT}/flow/slang/run_slang.sh" "$2"
      shift 2
      ;;
    --yosys)
      require_ip_arg "$@"
      run_cmd "${OBI_PERIPHERALS_ROOT}/flow/yosys/run_yosys.sh" "$2" --elab
      shift 2
      ;;
    --verilator)
      require_ip_arg "$@"
      run_verilator_test "$2"
      shift 2
      ;;
    --all)
      require_ip_arg "$@"
      run_cmd "${OBI_PERIPHERALS_ROOT}/flow/slang/run_slang.sh" "$2"
      run_cmd "${OBI_PERIPHERALS_ROOT}/flow/yosys/run_yosys.sh" "$2" --elab
      run_verilator_test "$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done
