# OBI Peripherals

This repository contains a collection of peripheral IPs using the Open Bus Interface (OBI), which can be used together with our OBI [interconnect IPs](https://github.com/pulp-platform/obi).

These peripherals were developed as part of the PULP project, a joint effort between ETH Zurich and the University of Bologna.

## Hardware Layout

Each peripheral keeps its RTL and peripheral-specific files together:

```text
<ip>/rtl/          synthesizable RTL
<ip>/dv/           IP-specific testbenches and simulation drivers
<ip>/formal/       IP-specific formal and equivalence checks
<ip>/doc/          IP-specific notes and test plans
```

Shared tool wrappers live under `flow/`, and generated outputs go to `build/`.

Useful entry points:

```sh
scripts/enter_container.sh
scripts/run_checks.sh --slang obi_uart
flow/yosys/run_yosys.sh obi_uart --elab
flow/verilator/run_verilator.sh obi_uart --build --run
```

## License

This repository is licensed under the Solderpad Hardware License, Version 0.51 (see `LICENSE`).
