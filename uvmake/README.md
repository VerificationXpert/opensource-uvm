# uvmake

A reusable build system for UVM testbenches on Verilator.

It is self-contained: copy this directory into your project, add it as a git
submodule, or install it once and point at it. Nothing inside `uvmake/` knows
anything about any particular project.

```
make lint                     elaborate and lint          ~13s
make build                    build the simulation binary
make run TEST=my_test         build and run
make regress                  run a regression list in parallel
```

## What you get

- **Upstream Accellera UVM, unpatched.** Fetched and cached automatically, or
  point `UVM_HOME` at the install you already have.
- **DPI enabled, including the `uvm_reg` backdoor.** UVM ships HDL backdoor
  backends for VCS, Questa and Xcelium only; `uvmake/dpi/` supplies the
  missing one over Verilator's VPI, so you do not have to fall back to
  `+define+UVM_NO_DPI` and lose regular expressions and the command-line
  processor along with it.
- **Filelists.** `.f` files with `-f` recursion, `+incdir+`, `+define+`,
  `-y`, `+libext+` and `$VAR` expansion.
- **An incremental build that works.** See
  [../docs/COMPILE_TIME.md](../docs/COMPILE_TIME.md); the short version is
  that editing one test method recompiles one file instead of two thousand.
- **Precompiled shared libraries** for the Verilator runtime and the UVM DPI
  layer, built once per toolchain rather than into every binary.
- **Lint that stays on for your code.** UVM's own warnings are waived by path,
  so your RTL and testbench keep full lint coverage.
- **A regression runner** with parallel jobs, seed sweeps and JUnit XML.

## Adding it to a project

### 1. Vendor it

```sh
git submodule add <url> uvmake      # or: cp -r uvmake /path/to/project/
```

### 2. Project settings, `uvmake.local.mk` at your project root

```make
UVMAKE ?= $(PROJECT_ROOT)/uvmake
# UVM_HOME ?= /tools/uvm/1800.2-2020-3.1     # to use an existing UVM install
```

Every makefile includes this first, so a testbench works whether you invoke
it from the project root or from its own directory.

### 3. Project makefile

```make
PROJECT_ROOT := $(CURDIR)
include $(PROJECT_ROOT)/uvmake.local.mk
include $(UVMAKE)/uvmake.mk

TB_DIRS := $(PROJECT_ROOT)/verif       # default is $(PROJECT_ROOT)/tb

$(uvmake-project)
```

### 4. A testbench makefile, `verif/<name>/Makefile`

```make
PROJECT_ROOT ?= $(abspath $(CURDIR)/../..)
include $(PROJECT_ROOT)/uvmake.local.mk
include $(UVMAKE)/uvmake.mk

TB_NAME     := fifo_tb
TB_TOP      := fifo_tb_top
TB_FILELIST := $(CURDIR)/fifo_tb.f

TEST ?= fifo_smoke_test

$(uvmake-testbench)
```

`$(uvmake-testbench)` is called *after* the declarations because a testbench
usually needs `UVM_HOME` and `PROJECT_ROOT` to build its paths from, and
those come from the include.

### 5. A filelist

```
-f $PROJECT_ROOT/rtl/rtl.f        // reuse the design team's list

+incdir+$TB_DIR

$TB_DIR/fifo_if.sv
$TB_DIR/fifo_pkg.sv
$TB_DIR/fifo_tb_top.sv
```

`uvm_pkg.sv` is added automatically (`UVM_AUTO_COMPILE=0` to opt out).
`$PROJECT_ROOT`, `$TB_DIR` and `$UVM_HOME` are predefined; any other `$VAR`
comes from the environment. Relative paths resolve against the directory of
the filelist naming them, so filelists stay movable.

## Testbench variables

| Variable | Meaning |
|---|---|
| `TB_NAME` | required; names the testbench and its build directory |
| `TB_TOP` | top module (default `$(TB_NAME)_tb_top`) |
| `TB_FILELIST` | one or more `.f` files |
| `TB_SRCS` | explicit sources, if you would rather not use a filelist |
| `TB_INCDIRS` | extra include directories |
| `TB_DEFINES` | extra `+define+` values |
| `TB_VLT_ARGS` | extra Verilator arguments |
| `TB_LDFLAGS` / `TB_LDLIBS` | extra link flags, e.g. for your own DPI |
| `TEST` | default test for `make run` |

## Knobs

All settable per-invocation (`make run BUILD_MODE=opt`), in
`uvmake.local.mk`, or in the environment.

| Knob | Values | Default | |
|---|---|---|---|
| `BUILD_MODE` | `fast` / `opt` / `debug` | `fast` | compile time vs sim speed |
| `TRACE` | `none` / `vcd` / `fst` | `none` | waveforms |
| `COVERAGE` | `0` / `1` | `0` | coverage collection |
| `UVM_FLAVOR` | `accellera` / `antmicro` / `custom` | `accellera` | which UVM |
| `UVM_HOME` | path | fetched | your own UVM install (selects `custom`) |
| `UVM_DPI` | `0` / `1` | `1` | DPI layer |
| `UVM_HDL_MAX_WIDTH` | integer | `1024` | widest backdoor field |
| `USE_SHARED_LIBS` | `0` / `1` | `1` | link prebuilt `.so`s |
| `PCH` | `0` / `1` | `1` | Verilator's precompiled header |
| `SEED` | integer | `1` | |
| `UVM_VERBOSITY` | `UVM_LOW`… | `UVM_MEDIUM` | |
| `JOBS` | integer | `nproc` | build parallelism |
| `LINT_STRICT` | `0` / `1` | `0` | make warnings fatal |
| `UVMAKE_CACHE` | path | `$(PROJECT_ROOT)/.uvmake` | shared UVM + `.so` cache |

Point several projects at one `UVMAKE_CACHE` and they share the UVM checkout
and the prebuilt libraries.

## Regressions

`regress/smoke.list`:

```
# <testbench> <test> [seed|range|*] [VAR=VALUE ...]
fifo_tb  fifo_smoke_test   1
fifo_tb  fifo_stress_test  1-10                  # ten seeds
fifo_tb  fifo_soak_test    *      TRACE=fst      # random seed, reported
```

```sh
make regress
make regress REGRESS_JOBS=16 REGRESS_ARGS='--seeds 20 --junit results.xml'
```

Runs execute in parallel; each gets its own directory under
`build/logs/<test>-<seed>/`, so waves and coverage from one seed never
overwrite another's. Pass/fail comes from UVM's own report counts, not from
grepping for `UVM_ERROR` — a clean run prints the line `UVM_ERROR :    0`,
which naive greps flag as a failure.

## In CI

`.github/workflows/ci.yml` in this repository is a working example. It is
staged so the cheap checks fail fast:

| Job | What | Typical |
|---|---|---|
| `selftest` | `uvmake/scripts/selftest.sh` - no Verilator needed | seconds |
| `lint` | `make lint LINT_STRICT=1` on every testbench | ~1 min warm |
| `regress` | build and run the regression, JUnit uploaded | minutes warm |

The regression only starts once the first two pass, so a typo costs seconds
rather than an hour.

Three things make it affordable:

- **`make lint` as the gate.** It elaborates the whole testbench without
  generating or compiling any C++, so it catches most breakage in seconds.
- **Cache Verilator.** Building it from source is about ten minutes; cached
  on its version tag it restores in seconds.
- **Cache `UVMAKE_CACHE` and ccache.** The former holds the UVM checkout and
  the prebuilt shared libraries; the latter is what stops every run
  recompiling ~2000 translation units from cold. Budget ~4 GB for ccache
  (a built testbench is ~1.5 GB of objects).

Be aware that the **first** run is the expensive one - it builds Verilator
and everything else from nothing, which on a 2-vCPU runner can approach two
hours. Later runs reuse all three caches.

The workflow triggers on pull requests and on pushes to `master`/`main`, not
on every push to a feature branch. Widen the `push:` branches if you would
rather have everything checked, or use the *Run workflow* button, which also
accepts a seed count for a deeper sweep.

## Requirements## Requirements

- Verilator 5.040+ (5.050 is what this is developed against)
- **`z3`**, or another SMT solver via `VERILATOR_SOLVER`. Verilator does not
  solve SystemVerilog constraints itself; without a solver every constrained
  `randomize()` returns 0 and constrained-random tests are meaningless.
- A C++20 compiler, `ccache`, and `liblz4-dev`/`libzstd-dev`/`zlib1g-dev`
  for FST tracing.

`uvmake/scripts/setup_verilator.sh` installs all of it. `make check-env`
reports what was found.

## Layout

```
uvmake.mk              the entry point you include
core/config.mk         every knob and its default
core/toolchain.mk      tool discovery and preflight checks
core/uvm.mk            UVM checkout, libvltrt.so, libuvmdpi.so
core/filelist.mk       .f expansion
core/verilate.mk       verilate / build / lint
core/run.mk            run / waves / coverage
core/testbench.mk      testbench mode
core/project.mk        project mode
core/model.mk          PCH-free compile rules (PCH=0)
dpi/                   Verilator VPI backdoor backend for uvm_reg
vlt/                   lint waivers scoped to the UVM tree
scripts/               filelist expander, regression runner, log checker,
                       the incremental-build mtime fix, Verilator installer
templates/             skeletons for a new project or testbench
```
