# OBI UART

`obi_uart` is an OBI peripheral implementing the programming interface of a
classic 8250/16550A UART. Linux 8250 driver behavior is the compatibility tie
breaker where historical UART documentation is ambiguous.

The synthesizable implementation is under `rtl/`. Directed Verilator tests are
under `dv/`, and the compatibility notes and coverage matrix are under `doc/`.
Formal and equivalence checks are deferred until they cover behavior beyond the
current simulation regression.

Run the lightweight verification suite from the repository root:

```sh
scripts/run_checks.sh --all obi_uart
```

See [`doc/verification_matrix.md`](doc/verification_matrix.md) for covered
behavior, remaining gaps, and open compatibility decisions.
