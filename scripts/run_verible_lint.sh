#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

mapfile -d '' -t source_files < <(git ls-files -z -- '*.sv' '*.svh' '*.v')

if (( ${#source_files[@]} == 0 )); then
  echo "No Verilog or SystemVerilog sources found" >&2
  exit 1
fi

verible-verilog-lint \
  --lint_fatal \
  --parse_fatal \
  "${source_files[@]}"
