# Compile time

All numbers below were measured on the machine described at the end of this
document, against `tb/minimal` — an empty `uvm_test`, so essentially all of
the build cost is the UVM library itself.

## Summary

| | Cold build | After editing one test method |
|---|---:|---:|
| Files compiled | 2008 | **1** |
| Wall time | **19m 44s** | **1m 18s** |

`tb/apb` — a real agent with driver, monitor, sequencer, scoreboard,
coverage and a register model — is only modestly bigger: **2369 files, 24m
53s** cold. The UVM library dominates either way, which is exactly why the
empty test is a fair benchmark for it.

The cold build is what it is: Verilator is a whole-program compiler and UVM
2020.3.1 expands to a little over two thousand C++ translation units. The
number that matters day to day is the second one, and getting it from *a full
rebuild every time* down to one file is where most of the work went.

## The incremental build was completely broken, and not obviously so

This is the main finding, and it is not a tuning question — it is a bug in the
interaction between three things that are each individually reasonable.

1. Verilator's generated build compiles every translation unit against a
   precompiled header, `V<top>__pch.h.gch`. For a UVM build that file is
   **288 MB**. `verilated.mk` makes it a prerequisite of every object:

   ```make
   $(VK_OBJS_FAST): %.o: %.cpp $(VK_PCH_H).fast.gch
   ```

2. The PCH's generated dependency file lists `V<top>__Syms.h` and
   `V<top>.h` among its inputs.

3. **Verilator rewrites every file in its output directory on each run, even
   when the new contents are byte-for-byte identical to the old.**

Point 3 is the one that does the damage. Editing a single string inside a
single test method and re-verilating gives:

```
headers whose content changed:  0
headers whose mtime changed:    all of them
```

Zero content changes — and a new mtime on `V<top>__pch.h`. Make therefore
rebuilds the 288 MB PCH, and because the PCH is a prerequisite of everything,
it then rebuilds every object. Asking make directly how much work a touched
PCH implies:

```console
$ make -f Vminimal_tb_top.mk -n -W Vminimal_tb_top__pch.h | grep -c 'g++.* -c '
2014
```

A one-line edit costs a full 2014-file rebuild.

It is worse than that, because it also defeats `ccache`. Every compile line
carries `-include <the 288 MB .gch>`, so a regenerated PCH changes the hash of
every compilation. Measured over a rebuild after that same one-line edit:

```
Cacheable calls: 2224
  Hits:             0 (0.00%)
  Misses:        2224 (100.0%)
```

Not a low hit rate — *zero*. The cache can never help, so every one of those
2014 files is compiled at full price.

### The fix

`scripts/preserve_mtimes.sh` records each generated file's content hash and
mtime before verilation and puts the old mtime back afterwards on every file
whose content did not actually change. Make then sees only the files that
genuinely differ, the PCH survives untouched, and the ~2000 unaffected objects
are left alone.

Hashing the output directory costs a fraction of a second against a build
measured in tens of minutes.

There was a second, related bug on our own side worth recording, because it
is the kind that silently produces wrong results rather than slow ones. The
build target was originally written the obvious way:

```make
$(SIM_BIN): $(OBJ_DIR)/V$(TB_TOP).mk $(SHARED_LIBS)
	$(MAKE) -C $(OBJ_DIR) -f V$(TB_TOP).mk ...
```

Once mtimes were being preserved, the generated makefile no longer changed on
a rebuild — so make decided the binary was up to date and never ran the
sub-make at all. The edit compiled cleanly, reported success, and **did not
take effect**. `build` is now phony and always delegates to the sub-make,
which is the thing that actually knows which of the 2000 files changed.

### Not every edit is cheap, and that part is inherent

The 1-file figure is for editing the *body* of a method — changing what code
does without changing any class's shape. That is the overwhelmingly common
case while debugging a testbench, and it is the one that used to cost a full
rebuild for no reason.

Editing a class *declaration* is a different matter. Adding a virtual method
to `apb_base_test` changes the class layout, so `V<top>__Syms.h` and the
generated class headers genuinely change and everything that includes them
genuinely has to be recompiled — measured at ~1000 of `tb/apb`'s 2369 files.
No amount of build-system work avoids that: Verilator compiles the whole
elaborated program as one unit, and a layout change really does reach
everything.

The distinction worth internalising is:

| Edit | Rebuild |
|---|---|
| Method body, string, constant | a handful of files |
| Add/remove/reorder a class member or virtual method | large fraction of the build |
| Add or remove a class | large fraction of the build |

So the practical advice on this flow is the same as on any whole-program
compiler: get the class structure settled, then iterate on bodies.

## Keep the precompiled header

Having found the PCH at the centre of the problem, the tempting conclusion is
to switch it off. That is the wrong call. Compiling a fixed 25-file sample of
generated UVM sources, serially, with and without it:

| | per translation unit |
|---|---:|
| With PCH | **2.37 s** |
| Without PCH | 6.37 s |

2.7× per file, across ~2000 files. Building the PCH itself costs 16 s once.
So the PCH stays on (`PCH=1`, the default) and the mtime fix is what makes it
safe. `PCH=0` selects the rules in `mk/model.mk` if it ever needs to be
bypassed — a compiler with unreliable PCH support, or a machine that cannot
spare the memory and disk a 288 MB header wants.

## The other levers

Applied in the default configuration, in rough order of size:

**Tracing off by default.** The original flow passed `--trace
--trace-structs` unconditionally. For a UVM build Verilator emits trace
registration for the class hierarchy as well as the design, over a library
that already generates 2000 translation units — and most regression runs
never open a waveform. `TRACE=none|vcd|fst`, defaulting to `none`.

**`-O0` on the model by default.** Verilator's `OPT_FAST` defaults to `-Os`.
Almost all of the generated code is UVM class methods that execute a handful
of times per simulation, so `-Os` across 2000 files buys very little
simulation speed for a great deal of compile time. `BUILD_MODE=fast` (`-O0`,
`--no-decoration`) is the default; `BUILD_MODE=opt` (`-O2`) is there for long
regressions where simulation wall time dominates.

**A parallel build.** The original `make -C uvm_tb-sim -f uvm_tb.mk` passed no
`-j` at all, leaving three of four cores idle for the entire build. Now
`-j$(nproc)`, with `--verilate-jobs` for the verilation stage too.

**Precompiled shared libraries.** See below.

**`ccache`.** Now that the PCH is stable, it actually functions. It is the
mechanism that makes the "generated UVM C++ that did not change" case free.

## The shared libraries

Splitting the DPI layer out has a practical payoff beyond build time. While
bringing up the backdoor backend, `lib/dpi/uvm_hdl_verilator.c` needed a
change to how it resolves HDL paths. Rebuilding it was:

```console
$ make libs
[uvmdpi] compile
[uvmdpi] link libuvmdpi.so
```

— a couple of seconds, and the already-built 46 MB simulation binary picked
the change up on its next run with no relink, because it resolves the library
through an rpath. Had the DPI layer been compiled into the model, that would
have been a relink at best and, in the general case, a rebuild.


Two things in every build are genuinely independent of the testbench, and are
built once into `.lib/<verilator-version>-<uvm-flavor>-w<width>/`:

- **`libvltrt.so`** — Verilator's runtime. `verilated.cpp`,
  `verilated_timing.cpp`, `verilated_threads.cpp`, `verilated_random.cpp`,
  the VCD/FST/SAIF trace back ends, the VPI and DPI entry points. Verilator
  lists these in `VM_GLOBAL_FAST` and recompiles them into every simulation
  binary; they depend only on the Verilator version.
- **`libuvmdpi.so`** — the UVM DPI layer, including the Verilator VPI
  backdoor backend from `lib/dpi/`. Depends only on the UVM version.

`USE_SHARED_LIBS=0` reverts to compiling both into each binary.

One wrinkle worth recording. Verilator emits each `export "DPI-C"` function
as a method on the model class *plus* a C-linkage wrapper, and puts both in
`V<top>__Dpi.o` inside `V<top>__ALL.a`. Nothing in the model itself calls
those wrappers — only the DPI library does — and a static archive only yields
the members that resolve an already-outstanding symbol. Since the archive is
linked before `libuvmdpi.so`, `m__uvm_report_dpi` is still unreferenced when
the archive is read, `__Dpi.o` is dropped, and the link fails on it. The flow
passes `-u m__uvm_report_dpi` through `USER_LDFLAGS` (which lands *before* the
archive on the link line) to force it in.

## What is left

At 78 s, the incremental build is no longer dominated by compilation — one
file compiles in about two seconds. The rest is Verilator re-elaborating the
whole design (~11 s, unavoidable: it has no separate compilation) and then
re-archiving 2000 objects into `V<top>__ALL.a` and relinking a 41 MB binary.
Linking against a prebuilt `.a` per subsystem, or an incremental linker such
as `mold`, is the obvious next step.

## Why UVM cannot simply be precompiled into a `.so`

This is the thing a commercial simulator does that Verilator structurally
cannot, and it is worth being explicit about because it is the first idea
anyone has.

Commercial simulators compile UVM once into a library and link it against
every testbench, because they compile SystemVerilog into their own runtime
representation where `uvm_pkg` is a self-contained unit. Verilator translates
the entire elaborated design — UVM included — into C++, specialising as it
goes. Two consequences:

1. **Parameterised classes are specialised per testbench.**
   `uvm_sequencer#(apb_item)` and `uvm_analysis_port#(apb_item)` exist only
   because a particular testbench asked for them. There is no fixed set of
   UVM objects to precompile.
2. **Even the non-parameterised parts are not shareable.** Every generated
   translation unit includes `V<top>__Syms.h`, the symbol table for the whole
   design. That file differs between any two testbenches, so the
   `uvm_component` object built for one is not the `uvm_component` object the
   other needs — and `ccache` cannot bridge them either, for the same reason.

Verilator's `--lib-create` and `--hierarchical` do produce separately
compiled libraries, but both operate on *modules*. UVM is classes in a
package, so they apply to the DUT, not to UVM.

So "precompile UVM into a `.so`" resolves, on Verilator, into three things —
all of which this flow does:

- Precompile what genuinely is testbench-independent: the Verilator runtime
  and the UVM DPI layer, as real shared objects.
- Make sure the generated UVM C++ that *is* unchanged between builds is never
  compiled twice. That is the mtime fix plus `ccache`, and it is where the
  15× incremental improvement comes from.
- Stop paying for work nobody asked for: tracing that will not be viewed,
  `-Os` on code that runs a handful of times, and a serial build on a
  parallel machine.

## Reproducing

```sh
./scripts/benchmark.sh -t minimal      # full configuration sweep
./scripts/benchmark.sh -t minimal -c default
```

Results are appended to `build/benchmark.csv`.

## Measurement setup

- Verilator 5.050, built from source
- GCC 13.3.0, `-std=gnu++20`
- 4 cores, 15 GB RAM, Ubuntu 24.04
- `ccache` 4.9.1, cleared before every cold measurement
- UVM: Accellera `uvm-core` 2020.3.1, DPI enabled
- `tb/minimal`, `BUILD_MODE=fast`, `TRACE=none`, `USE_SHARED_LIBS=1`

Cold numbers are from an empty object directory with an empty ccache. The
incremental number is from editing one string inside one test method and
re-running `make build`.
