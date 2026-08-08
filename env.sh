#!/bin/sh
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

export OBI_PERIPHERALS_ROOT="${OBI_PERIPHERALS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
export OBI_PERIPHERALS_BUILD_DIR="${OBI_PERIPHERALS_BUILD_DIR:-${OBI_PERIPHERALS_ROOT}/build}"
