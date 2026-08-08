#!/bin/sh
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set -eu

RUNDIR=${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}
mkdir -p "${RUNDIR}"

env UID=$(id -u) GID=$(id -g) docker compose pull eda-tools
env UID=$(id -u) GID=$(id -g) docker compose run --rm \
  -e PS1='eda:\w $ ' \
  -e XDG_RUNTIME_DIR="${RUNDIR}" \
  -v "${RUNDIR}:${RUNDIR}" \
  eda-tools
