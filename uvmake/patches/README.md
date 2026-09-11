# Local UVM patches

Patches placed here are applied to the UVM checkout after it is fetched.

**There are none today, and that is the point worth keeping.** Upstream
Accellera UVM 2020.3.1 compiles under Verilator 5.050 unmodified — the
Verilator-specific work (the VPI backdoor backend that upstream `uvm_hdl.c`
lacks) lives outside the UVM tree in `uvmake/dpi/`, precisely so the library
stays pristine and a UVM version bump is a one-line change.

This directory exists for when that stops being true: a Verilator
regression, a UVM release using a construct Verilator cannot yet handle, or
a site-specific fix. Carrying that as a patch against a pinned upstream
revision is much cheaper than forking UVM and inheriting a fork's
maintenance — which is the trap the antmicro fork represents.

## Using it

```
uvmake/patches/accellera/0010-short-description.patch
uvmake/patches/antmicro/...
```

Applied in lexicographic order with `git apply -p1` from the root of the UVM
kit, so paths in the diff start with `src/`. Cut one by editing the fetched
tree and running `git diff` inside it:

```sh
cd .uvmake/uvm/accellera
# edit src/...
git diff > /path/to/repo/uvmake/patches/accellera/0010-fix-thing.patch
```

A project can keep its own series instead of or alongside these — the
default `UVM_PATCH_DIRS` also picks up `$(PROJECT_ROOT)/uvm-patches`.

## How it behaves

- **The patch series is part of the checkout's identity.** Its content hash
  goes into the stamp filename, into `UVM_ID`, and therefore into the
  shared-library cache tag. Editing, adding or removing a patch re-fetches a
  clean tree and re-applies the whole series; nothing is ever applied on top
  of an already-patched tree, and a patched and unpatched UVM never share a
  `libuvmdpi.so`.
- **A patch that does not apply fails the build**, naming the patch and
  showing what `git apply` objected to. It is checked before anything is
  written, so a bad series cannot half-apply.
- **A UVM install you supplied via `UVM_HOME` is never modified.** It is
  usually a shared, read-only site install, so it is copied into the cache
  and the copy is patched.

## When to delete one

When upstream fixes the issue. Bumping `UVM_ACCELLERA_REV` with a stale
patch in place fails loudly rather than silently skipping it, which is the
prompt to check whether it is still needed.
