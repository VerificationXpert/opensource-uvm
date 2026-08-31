# acme-soc

A worked example of a project consuming `uvmake`. It is deliberately *not*
part of this repository's own build: it has its own root makefile, its own
directory layout, and its own regression list, exactly as a separate project
would.

```sh
cd examples/acme-soc
make lint                              # ~10s
make regress                           # build and run everything
make run TB=fifo_tb TEST=fifo_smoke_test
```

## What it demonstrates

| | |
|---|---|
| **A different layout** | testbenches live under `verif/`, not the default `tb/`. One line: `TB_DIRS := $(PROJECT_ROOT)/verif` |
| **A design-owned filelist** | `verif/fifo_tb/fifo_tb.f` pulls in `rtl/rtl.f` with `-f` rather than duplicating the RTL file list |
| **uvmake by reference** | `uvmake.local.mk` names where uvmake lives; nothing else knows |
| **Standalone testbenches** | `make -C verif/fifo_tb run TEST=...` works without going through the project root |
| **Bootstrapping** | with no UVM installed it fetches one and builds its shared libraries on first use |

## Layout

```
uvmake.local.mk            where uvmake lives, plus project-wide settings
Makefile                   project root: discovery, regress, lint
rtl/sync_fifo.sv           the DUT
rtl/rtl.f                  the design team's filelist
verif/fifo_tb/Makefile     testbench declaration
verif/fifo_tb/fifo_tb.f    testbench filelist, includes rtl/rtl.f
verif/fifo_tb/*.sv         interface, agent, scoreboard, tests, top
regress/smoke.list         regression list
```

The UVM environment itself (`fifo_pkg.sv`) is an ordinary agent - sequence
item, driver, monitor, sequencer, an analysis-port scoreboard that checks
FIFO ordering - and contains nothing that knows about the build system.
