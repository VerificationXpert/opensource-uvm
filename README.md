# Open-Source UVM with Verilator

A production-shaped UVM verification flow built entirely on open-source
tooling: **Verilator 5.050** and **unpatched Accellera UVM 2020.3.1
(IEEE 1800.2-2020)**.

The goal is to close the gap between "UVM elaborates under Verilator" and
"you could run a project on this" — full DPI including register backdoor
access, a real testbench structure, a regression runner, and build times that
make iteration practical.

## Quick start

```sh
# Verilator 5.04x+ is required; distribution packages are usually too old.
sudo ./uvmake/scripts/setup_verilator.sh
export PATH=/opt/verilator-5.050/bin:$PATH

make libs                              # fetch UVM, build libvltrt.so + libuvmdpi.so
make run TB=minimal TEST=base_test     # smoke test
make run TB=apb TEST=apb_rw_test       # the APB testbench
make regress                           # run regress/smoke.list
make help                              # every target and knob
```

## What is here

| Path | Contents |
|---|---|
| `uvmake/` | **The build system.** Self-contained and project-agnostic - copy it, submodule it, or install it once. See [uvmake/README.md](uvmake/README.md) |
| `uvmake/dpi/` | Verilator VPI backend for UVM's HDL backdoor, and the DPI translation unit that replaces upstream `uvm_dpi.cc` |
| `uvmake/vlt/` | Lint waivers scoped to the UVM tree, so user code keeps full lint |
| `tb/minimal/` | Toolchain smoke test and the compile-time benchmark |
| `tb/apb/` | APB3 slave with agent, scoreboard, coverage, RAL, and five tests |
| `regress/` | Regression lists |
| `uvmake/scripts/` | Filelist expander, parallel regression runner, Verilator installer, the incremental-build mtime fix, UVM log pass/fail, and self-tests for all of it |
| `docs/` | [Analysis](docs/ANALYSIS.md) and [compile-time measurements](docs/COMPILE_TIME.md) |

## The three things this changes

### 1. Upstream UVM 2020.3.1, unpatched

Open-source UVM flows have generally used `antmicro/uvm-verilator`, a patched
fork of the 2017 standard, because Verilator could not handle the library as
shipped. As of Verilator 5.050 it can. This flow builds
`accellera-official/uvm-core` 2020.3.1 directly, gaining the compiled-regex
cache, `uvm_phase_hopper` and the resource-pool rework along the way. The
fork stays available as `UVM_FLAVOR=antmicro` for comparison.

### 2. DPI on, including the register backdoor

UVM ships HDL backdoor backends for VCS, Questa and Xcelium and
`#error "hdl vendor backend is missing"` for everything else — which is why
open-source flows compile with `+define+UVM_NO_DPI` and lose *regular
expressions* and the *command-line processor* as collateral damage, neither
of which needs a simulator API at all.

`uvmake/dpi/uvm_hdl_verilator.c` supplies the missing backend over Verilator's
VPI. DPI is on by default; `tb/apb`'s `apb_backdoor_test` does a frontdoor
write / backdoor read and a backdoor write / frontdoor read against the RTL.
The one real limitation is that Verilator has no force/release, so
`uvm_hdl_force` deposits and warns once. See
[docs/ANALYSIS.md §2.2](docs/ANALYSIS.md).

### 3. Builds that finish

On `tb/minimal` (an empty `uvm_test`, so the cost is essentially all UVM):

| | Cold build | After editing one test method |
|---|---:|---:|
| Files compiled | 2008 | **1** |
| Wall time | 19m 44s | **1m 18s** |

The incremental case used to be a full 2008-file rebuild at a **0% ccache hit
rate**, every time, because Verilator rewrites its whole output directory on
each run even when the contents are byte-identical — which invalidates the
288 MB precompiled header that `verilated.mk` makes a prerequisite of every
object. `uvmake/scripts/preserve_mtimes.sh` fixes that; the details, and an honest
account of why UVM itself *cannot* be precompiled into a `.so` the way a
commercial simulator does it, are in
[docs/COMPILE_TIME.md](docs/COMPILE_TIME.md).

Tracing is also opt-in rather than always-on, the model builds in parallel at
`-O0` by default, and the Verilator runtime and UVM DPI layer are precompiled
into shared objects once per toolchain.

## Knobs

All of these work on any target and are documented in
`uvmake/core/config.mk`:

| Knob | Values | Default | |
|---|---|---|---|
| `BUILD_MODE` | `fast` / `opt` / `debug` | `fast` | compile time vs simulation speed |
| `TRACE` | `none` / `vcd` / `fst` | `none` | waveform back end |
| `UVM_FLAVOR` | `accellera` / `antmicro` | `accellera` | which UVM |
| `UVM_DPI` | `0` / `1` | `1` | DPI layer |
| `USE_SHARED_LIBS` | `0` / `1` | `1` | link prebuilt `.so`s |
| `PCH` | `0` / `1` | `1` | Verilator's precompiled header |
| `SEED` | integer | `1` | randomisation seed |
| `UVM_VERBOSITY` | `UVM_LOW` … | `UVM_MEDIUM` | |
| `JOBS` | integer | `nproc` | build parallelism |

```sh
make run TB=apb TEST=apb_random_test SEED=42 TRACE=fst BUILD_MODE=opt
make regress LIST=regress/smoke.list UVM_FLAVOR=antmicro UVM_DPI=0
```

## Adding a testbench

`tb/<name>/Makefile`:

```make
PROJECT_ROOT ?= $(abspath $(CURDIR)/../..)
include $(PROJECT_ROOT)/uvmake.local.mk
include $(UVMAKE)/uvmake.mk

TB_NAME     := mytb
TB_TOP      := mytb_top
TB_FILELIST := $(CURDIR)/mytb.f

$(uvmake-testbench)
```

and `tb/<name>/mytb.f`:

```
-f $PROJECT_ROOT/rtl/rtl.f     // reuse the design's own filelist
+incdir+$TB_DIR
$TB_DIR/mytb_pkg.sv
$TB_DIR/mytb_top.sv
```

It is picked up by `make list`, `make <name>`, and regression lists
automatically. Skeletons are in `uvmake/templates/`.

## Using it in another project

`uvmake/` has no dependency on this repository. Copy it or add it as a
submodule, drop in `uvmake/templates/uvmake.local.mk` and the two makefile
templates, and you have the same flow. The full variable reference is in
[uvmake/README.md](uvmake/README.md).

## Requirements

- Verilator 5.04x or newer (5.050 is what this is developed and measured against)
- **`z3`** (or another SMT solver via `VERILATOR_SOLVER`). Verilator does not
  solve SystemVerilog constraints itself. Without a solver every constrained
  `randomize()` returns 0 and constrained-random tests are meaningless — so
  `uvmake` checks for it and warns.
- A C++20 compiler (GCC 13 or newer)
- `ccache` — strongly recommended; the incremental-build numbers depend on it
- `liblz4-dev`, `libzstd-dev`, `zlib1g-dev` for FST tracing

`uvmake/scripts/setup_verilator.sh` installs all of these, and
`make check-env` reports what was found.

## Licence

MIT for this repository. UVM is Apache-2.0 (Accellera); Verilator is
LGPL-3.0/Artistic-2.0.
