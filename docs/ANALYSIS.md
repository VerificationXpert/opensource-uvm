# Analysis: open-source UVM on Verilator

This document records what the repository looked like before this work, what
was actually limiting it, and what changed. The compile-time measurements
live separately in [COMPILE_TIME.md](COMPILE_TIME.md).

## 1. Starting point

The repository contained a single experiment, `minimal_uvm/`: a Makefile, a
README, and a `top.sv` holding an empty `uvm_test`. The Makefile did four
things:

```make
git clone https://github.com/antmicro/uvm-verilator -b current-patches uvm
verilator --cc --exe --main --timing -Mdir uvm_tb-sim \
    --top-module top -DUVM_NO_DPI --prefix uvm_tb -o uvm_tb ... \
    -Wno-lint -Wno-style ... --timescale 1ns/1ps --error-limit 0 \
    --trace --trace-structs
make -C uvm_tb-sim -f uvm_tb.mk
uvm_tb-sim/uvm_tb +UVM_TESTNAME=basic_test
```

It works, and as a proof that UVM elaborates under Verilator at all it did
its job. But essentially every decision in it is one that a production
verification flow would have to revisit.

## 2. What was actually wrong

### 2.1 The UVM library was pinned to a fork of a 2017 standard

`antmicro/uvm-verilator` is a patched copy of Accellera's **1800.2-2017 1.0**
release. The patches existed because Verilator's SystemVerilog class support
was not, at the time, good enough for the unmodified library.

That is no longer true. Upstream **`accellera-official/uvm-core` 2020.3.1
(IEEE 1800.2-2020) verilates cleanly under Verilator 5.050 with no source
patches at all.** This flow now defaults to it.

Moving forward three years of UVM releases is not just a version bump. The
2020.3.x line adds, among other things:

| Addition | Why it matters |
|---|---|
| `uvm_regex_cache` / `uvm_lru_cache` | Compiled regexes are cached instead of recompiled on every `uvm_is_match`. Config-DB and factory lookups are regex-heavy. |
| `uvm_phase_hopper` | Reworked phase scheduling; less process churn per phase transition. |
| `uvm_resource_pool` | Resource database rework, replacing the older linear structures. |
| `uvm_process_guard` | Deterministic cleanup of forked processes. |
| `uvm_hdl_polling` | Passive value-change observation of HDL signals. |

Being on a fork also means being on someone else's release cadence. Building
against upstream means UVM updates are a version bump in
`uvmake/core/config.mk`, and the fork remains selectable
(`UVM_FLAVOR=antmicro`) for comparison.

This is not a bet that upstream will never need fixing. `uvmake/patches/`
carries a local patch series applied to the fetched kit, so a future
Verilator or UVM incompatibility can be handled with a patch against a
pinned revision rather than by forking the library again — which is the trap
the antmicro fork represents. There are no patches today.

### 2.2 `-DUVM_NO_DPI` disabled a large part of UVM

This was the single biggest functional gap. `UVM_NO_DPI` is not a
compatibility switch — it turns off three separate subsystems:

```
`ifdef UVM_NO_DPI
  `define UVM_HDL_NO_DPI       // no uvm_reg backdoor access at all
  `define UVM_REGEX_NO_DPI     // regular expressions degrade to glob matching
  `define UVM_CMDLINE_NO_DPI   // uvm_cmdline_processor loses +uvm_set_* etc.
`endif
```

Concretely, with `UVM_NO_DPI` set:

- **No regular expressions.** `uvm_re_match` falls back to a hand-written
  glob matcher. `uvm_config_db::set("/^env\.agent[0-9]+$/", ...)`,
  regex type overrides, and regex-based verbosity control all silently stop
  behaving as written. UVM's own component name checking disables itself and
  says so: *"Because UVM_REGEX_NO_DPI is defined, no uvm component name
  constraints will be checked"*.
- **No command-line processor.** `+uvm_set_config_int`,
  `+uvm_set_verbosity`, `+uvm_set_type_override` and friends stop working.
  UVM 2020.3 prints a banner: `!!! UVM_CMDLINE_NO_DPI IS DEFINED !!!`.
- **No register backdoor.** `UVM_BACKDOOR` accesses cannot work, so the
  entire backdoor half of a RAL environment is unavailable.

Upstream UVM's own view of the switch, in `uvm_root.svh`:

> `We are thinking of removing support for UVM_NO_DPI. Please try this test
> without it and evaluate the impact`

So why was it there? Because of `src/dpi/uvm_hdl.c`:

```c
// hdl vendor backends are defined for VCS,QUESTA,XCELIUM
#if defined(VCS) || defined(VCSMX)
...
#else
#error "hdl vendor backend is missing"
#endif
```

UVM ships HDL backdoor backends for three commercial simulators and nothing
else. Any open-source flow hits the `#error` and has no option but to switch
the whole DPI layer off — losing the regex and command-line layers as
collateral damage, even though **neither of those needs any simulator API**.
`uvm_regex.cc` is POSIX `<regex.h>`; `uvm_svcmd_dpi.c` needs only
`vpi_get_vlog_info`, which Verilator implements.

**What this repository now does:** `uvmake/dpi/uvm_hdl_verilator.c` supplies the
missing backend on top of Verilator's VPI, and
`uvmake/dpi/uvm_dpi_verilator.cpp` replaces upstream's `uvm_dpi.cc` to pull it
in instead of `uvm_hdl.c`. The UVM tree stays unpatched — everything
Verilator-specific lives in `uvmake/dpi/`. DPI is on by default, and
`tb/minimal` includes a `dpi_smoke_test` that fails if a build has quietly
regressed to the glob-only path.

The one genuine limitation is that **Verilator's VPI has no force/release**.
`uvm_hdl_force` therefore deposits and warns once rather than failing
outright, and `uvm_hdl_release` is a no-op. Backdoor reads and deposits —
which is what `uvm_reg` backdoor sequences overwhelmingly use — are exact.
`tb/apb`'s `apb_backdoor_test` exercises both directions against the RTL.

### 2.3 Waveform tracing was unconditional

`--trace --trace-structs` was always on. For a UVM build this is expensive in
a way it is not for a plain RTL build: Verilator emits trace-registration
code for the class hierarchy as well as the design, across a library that
already generates over a thousand translation units. It is also usually
unwanted — most regression runs never open a waveform.

Tracing is now opt-in (`TRACE=none|vcd|fst`, default `none`), and FST is
offered alongside VCD because VCD dumps from long UVM runs get large quickly.
The top module also gates dumping on a `+wave` plusarg, so a trace-enabled
binary can still run at full speed.

### 2.4 The build was serial and unoptimised

`make -C uvm_tb-sim -f uvm_tb.mk` passes no `-j`. On a 4-core machine that
leaves three quarters of the machine idle for the duration — and the duration
is long, because Verilator's default `OPT_FAST` is `-Os`. Spending `-Os` on
1500+ files of UVM class methods, most of which execute a handful of times
per simulation, is a poor trade during development.

The flow now runs the model build at `-j$(nproc)`, and `BUILD_MODE` picks the
trade-off explicitly: `fast` (`-O0`, `--no-decoration`) for turnaround,
`opt` (`-O2`) for long regressions, `debug` for stepping through the model.
Measured per translation unit on the generated UVM sources, `-O0` with the
precompiled header costs 2.4 s against 6.4 s without it, so the PCH stays
on — see [COMPILE_TIME.md](COMPILE_TIME.md).

### 2.5 Nothing was reused between builds

Every testbench recompiled everything, including the parts that could not
possibly differ. Two categories are shared by construction:

- **Verilator's runtime.** `VM_GLOBAL_FAST` lists `verilated.cpp`,
  `verilated_timing.cpp`, `verilated_threads.cpp`, `verilated_random.cpp`
  and the trace back ends. These depend only on the Verilator version.
- **The UVM DPI layer.** Pure C/C++, depends only on the UVM version.

Both are now built once into
`.lib/<verilator-version>-<uvm-flavor>-w<width>/` as `libvltrt.so` and
`libuvmdpi.so`, and linked by every testbench.

The third category is the generated UVM C++ itself, which is byte-identical
across rebuilds whenever the library sources and the set of used
specialisations have not changed. `ccache` is what is supposed to cover it —
but as shipped it could not, because Verilator rewrites every output file on
each run even when the contents are unchanged, which invalidates the 288 MB
precompiled header that `verilated.mk` makes a prerequisite of every object.
The measured result was a full 2000-file rebuild at a 0% cache hit rate after
a one-line edit. That is the single largest finding of this work and it has
its own write-up in [COMPILE_TIME.md](COMPILE_TIME.md).

### 2.6 Lint was disabled globally

`-Wno-lint -Wno-style` silences UVM's warnings, and also the DUT's and the
testbench's. Verilator's `.vlt` configuration files can scope waivers by
file, so `uvmake/vlt/uvm_waivers.vlt` waives them for the UVM tree by path and
leaves lint fully enabled on user code.

### 2.7 Constrained randomisation needs an SMT solver, and says so quietly

Not a defect in the original repository — its one test never randomised
anything, so it could not have hit this — but it is the first thing a real
testbench runs into, and it deserves recording.

**Verilator does not solve SystemVerilog constraints itself.** It hands them
to an external SMT solver, `z3` by default (`VERILATOR_SOLVER` overrides).
Verilator builds and runs perfectly well without one; the only sign is a
warning on the first `randomize()`:

```
%Warning: Subprocess command `z3 --in' failed: exit status 127
%Warning: Unable to communicate with SAT solver, please check its
          installation or specify a different one in VERILATOR_SOLVER
```

after which **every constrained `randomize()` returns 0**. This is a bad
failure mode. A sequence that randomises its items generates nothing; a test
either fails with an unhelpful message or, worse, passes having randomised
nothing at all. In this repository it showed up as `apb_random_test` failing
on every seed while every other test passed — which looks like a testbench
bug, not a missing package.

`uvmake/core/config.mk` now checks for the solver at parse time and says plainly what
is wrong, and `uvmake/scripts/setup_verilator.sh` installs it.

### 2.8 There was no verification flow

One empty test, invoked by a hardcoded `+UVM_TESTNAME=basic_test` inside a
make recipe. No test library, no seeds, no logging, no regression runner, no
pass/fail determination. That is addressed by the structure in section 4.

## 3. What is genuinely not achievable

Being straight about the limits matters as much as the wins.

**UVM cannot be precompiled into a shared object the way a commercial
simulator precompiles it.** This is worth stating clearly because it is the
obvious thing to reach for.

Commercial simulators compile UVM once into a library and link it against
every testbench because they compile SystemVerilog to their own runtime
representation, where `uvm_pkg` is a self-contained unit. Verilator is a
whole-program compiler: it translates the entire elaborated design, UVM
included, into C++ and specialises as it goes. Two consequences:

1. **Parameterised classes are specialised per testbench.**
   `uvm_sequencer#(apb_item)` and `uvm_analysis_port#(apb_item)` only exist
   because the testbench asked for them. A different testbench produces a
   different set of specialisations, so there is no fixed set of UVM objects
   to precompile.
2. **Code generation depends on reachability.** Verilator emits and optimises
   based on what the whole program can reach, so even the non-parameterised
   parts of UVM are not guaranteed to be emitted identically between two
   different testbenches.

Verilator does have `--lib-create` and `--hierarchical`, which produce
separately-compiled libraries — but both operate on *modules*, and UVM is
classes in a package. They apply to the DUT, not to UVM.

So the honest version of "precompile UVM into a `.so`" on Verilator is three
things, and this flow does all three:

- Precompile everything that genuinely *is* testbench-independent — the
  Verilator runtime and the UVM DPI layer — into real shared objects.
- Use `ccache` so the generated UVM C++ that *is* identical between builds is
  never compiled twice, which covers the overwhelming majority of the
  incremental case.
- Stop paying for work nobody asked for: tracing that will not be viewed,
  `-Os` on code that runs a few times, and a serial build on a parallel
  machine.

The measured effect of each is in [COMPILE_TIME.md](COMPILE_TIME.md).

## 4. Structure

```
uvmake/             the build system, self-contained and project-agnostic
  uvmake.mk         the single entry point a project includes
  core/             knobs, toolchain checks, UVM + .so libraries, filelist
                    expansion, verilate/build/lint, run/waves/coverage
  dpi/              Verilator VPI backdoor backend + the DPI translation unit
  vlt/              lint waivers scoped to the UVM tree
  scripts/          filelist expander, regression runner, log checker,
                    the incremental-build mtime fix, and self-tests
  templates/        skeletons for a new project or testbench

tb/minimal/         toolchain smoke test and compile-time benchmark
tb/apb/             APB3 slave with a full agent, scoreboard, RAL and tests

regress/            regression lists
scripts/            Verilator installation, compile-time benchmarks
```

A testbench makefile is now six lines of declaration plus an include; see
`tb/apb/Makefile`.
