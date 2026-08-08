#!/bin/sh
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${script_dir}/../../scripts/common.sh"

usage() {
  cat <<'EOF'
Usage: flow/slang/run_slang.sh IP [--top TOP]
EOF
}

[ "$#" -gt 0 ] || { usage; exit 1; }
ip=$1
shift
top=${ip}

if [ -f "${OBI_PERIPHERALS_ROOT}/${ip}/flow.env" ]; then
  # shellcheck disable=SC1090
  . "${OBI_PERIPHERALS_ROOT}/${ip}/flow.env"
  top=${SLANG_TOP:-${top}}
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --top)
      top=$2
      shift 2
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

build_dir=$(make_build_dir slang "${ip}")
flist="${build_dir}/${ip}.f"
generate_flist "${flist}" -t rtl -t lint -t simulation -e common_verification -e tech_cells_generic

echo "[INFO][slang] Elaborating ${top}"
if slang --version >/dev/null 2>&1; then
  slang_cmd=slang
else
  slang_cmd="slang slang"
fi

$slang_cmd --top "${top}" -F "${flist}"
