# Contributing an IP

Keep each peripheral and its peripheral-specific files in one top-level directory:

```text
<ip>/
  README.md       interface, compatibility, limitations, and verification status
  rtl/            synthesizable RTL in compile order
  dv/             simulation testbenches and drivers
  formal/         formal properties and equivalence configurations
  doc/            design notes and verification plans
```

Add software or integration directories only when the IP has corresponding
maintained files. Put a file in `common/` only after it is reused by more
than one IP.

Add all synthesizable and verification sources to the root `Bender.yml`. Extend
the shared wrappers under `flow/` only when an IP needs a reusable tool action;
keep IP-specific configuration in `<ip>/flow.env`.

Before submitting a change, run:

```sh
scripts/run_checks.sh --all <ip>
```

Document compatibility decisions and remaining coverage gaps in the IP-local
documentation.
