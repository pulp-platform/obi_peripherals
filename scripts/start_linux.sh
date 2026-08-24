#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

RUNDIR=${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}
mkdir -p "${RUNDIR}"

env UID=$(id -u) GID=$(id -g) docker compose pull eda-tools
env UID=$(id -u) GID=$(id -g) docker compose run --rm \
  -e PS1='eda:\w $ ' \
  -e XDG_RUNTIME_DIR="${RUNDIR}" \
  -v "${RUNDIR}:${RUNDIR}" \
  eda-tools
