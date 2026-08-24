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
Usage: flow/yosys/run_yosys.sh IP [OPTIONS]

Options:
  --help, -h        Show this help
  --top TOP         Override top module name
  --flist           Regenerate only the file list
  --elab            Parse, elaborate, check, and report
  --synth-generic   Run generic synthesis without technology mapping
EOF
}

[ "$#" -gt 0 ] || { usage; exit 1; }
ip=$1
shift
top=${ip}
do_flist=0
do_elab=0
do_synth=0

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
    --elab)
      do_elab=1
      shift
      ;;
    --synth-generic)
      do_synth=1
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

[ "${do_flist}${do_elab}${do_synth}" != "000" ] || { usage; exit 1; }

build_dir=$(make_build_dir yosys "${ip}")
flist="${build_dir}/${ip}.f"
(
  cd "${OBI_PERIPHERALS_ROOT}"
  generate_flist "${flist}" --top "${top}" -t rtl -t synthesis
)

if [ "${do_flist}" = 1 ]; then
  echo "[INFO][Bender] File list: ${flist}"
fi

if yosys -V >/dev/null 2>&1; then
  yosys_cmd=(yosys)
else
  yosys_cmd=(yosys yosys)
fi

if [ "${do_elab}" = 1 ]; then
  echo "[INFO][Yosys] Elaborating ${top}"
  (
    cd "${OBI_PERIPHERALS_ROOT}"
    TOP_DESIGN="${top}" FLIST="${flist}" OUT_DIR="${build_dir}" \
      "${yosys_cmd[@]}" -c "${script_dir}/scripts/elaborate.tcl" 2>&1 \
      | tee "${build_dir}/elaborate.log"
  )
fi

if [ "${do_synth}" = 1 ]; then
  echo "[INFO][Yosys] Generic synthesis for ${top}"
  (
    cd "${OBI_PERIPHERALS_ROOT}"
    TOP_DESIGN="${top}" FLIST="${flist}" OUT_DIR="${build_dir}" \
      "${yosys_cmd[@]}" -c "${script_dir}/scripts/synth_generic.tcl" 2>&1 \
      | tee "${build_dir}/synth_generic.log"
  )
fi
