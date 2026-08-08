#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${script_dir}/../../scripts/common.sh"

usage() {
  cat <<'EOF'
Usage: flow/verilator/run_verilator.sh IP [OPTIONS]

Options:
  --help, -h    Show this help
  --top TOP     Testbench top module
  --flist       Regenerate only the file list
  --build       Build the Verilator simulation
  --run         Run the built simulation
EOF
}

[ "$#" -gt 0 ] || { usage; exit 1; }
ip=$1
shift
top=tb_${ip}_rx_smoke

if [ -f "${OBI_PERIPHERALS_ROOT}/${ip}/flow.env" ]; then
  # shellcheck disable=SC1090
  . "${OBI_PERIPHERALS_ROOT}/${ip}/flow.env"
  top=${VERILATOR_TOP:-${top}}
fi
do_flist=0
do_build=0
do_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --top)
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

build_dir=$(make_build_dir verilator "${ip}")
flist="${build_dir}/${ip}.f"
top_build_dir="${build_dir}/${top}"
generate_flist "${flist}" -t rtl -t simulation -t verilator \
  -e common_verification -e tech_cells_generic \
  -D VERILATOR=1 -D COMMON_CELLS_ASSERTS_OFF=1

if [ "${do_flist}" = 1 ]; then
  echo "[INFO][Bender] File list: ${flist}"
fi

if verilator --version >/dev/null 2>&1; then
  verilator_cmd=verilator
else
  verilator_cmd="verilator verilator"
fi

if [ "${do_build}" = 1 ]; then
  echo "[INFO][Verilator] Building ${top}"
  csrc="${OBI_PERIPHERALS_ROOT}/${ip}/dv/csrc/${top}.cpp"
  if [ -f "${csrc}" ]; then
    exe_args="--exe ${csrc}"
  else
    exe_args="--exe --main"
  fi
  $verilator_cmd \
    -Wno-fatal \
    -Wno-style \
    --cc \
    $exe_args \
    --build \
    -j "${VERILATOR_JOBS:-2}" \
    --top "${top}" \
    --Mdir "${top_build_dir}" \
    -f "${flist}" 2>&1 | tee "${build_dir}/build.log"
fi

if [ "${do_run}" = 1 ]; then
  echo "[INFO][Verilator] Running ${top}"
  "${top_build_dir}/V${top}" 2>&1 | tee "${build_dir}/run.log"
fi
