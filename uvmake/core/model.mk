# ---------------------------------------------------------------------------
# mk/model.mk - PCH-free compile rules for the Verilated model.
#
# Run from inside the object directory:
#     make -C <objdir> -f mk/model.mk GEN_MK=V<top>.mk VM_DEFAULT_RULES=0 ...
#
# Why this exists
# ---------------
# This is the PCH=0 escape hatch. Verilator's generated build compiles every
# translation unit against a precompiled header (V<top>__pch.h.gch) that
# pulls in verilated.h, V<top>__Syms.h and V<top>.h. For a UVM build that
# .gch is around 290 MB, and verilated.mk makes it a prerequisite of every
# object:
#
#     $(VK_OBJS_FAST): %.o: %.cpp $(VK_PCH_H).fast.gch
#
# The PCH is worth having: measured on tb/minimal it compiles a translation
# unit in 2.4s against 6.4s without, a 2.7x saving across ~2000 files. So it
# is on by default, and this file is not normally used.
#
# What makes it dangerous is that anything which rebuilds the .gch rebuilds
# every object and, because the compile line carries -include <the .gch>,
# also changes every ccache key. Verilator rewrites its whole output
# directory on each run even when the contents are byte-identical, so
# without scripts/preserve_mtimes.sh a one-line edit does exactly that: a
# full rebuild at a 0% cache hit rate.
#
# With the mtime fix in place the PCH is stable across edits and this file
# is only needed when the default rules have to be bypassed - a compiler
# whose PCH support is unreliable, or a machine short of the memory and disk
# a 290 MB header costs. PCH=0 in mk/config.mk selects it.
#
# The four rules below mirror verilated.mk's own, minus the PCH. The
# FAST/SLOW rules deliberately use `-c $<` with no `-o`, exactly as
# verilated.mk does, because the sources are reached through VPATH and the
# object belongs in the current directory.
# ---------------------------------------------------------------------------

ifndef GEN_MK
  $(error GEN_MK must name the Verilator-generated makefile)
endif

# Must be set before including the generated makefile, which would otherwise
# make its own `default` target the goal.
.DEFAULT_GOAL := model

include $(GEN_MK)

model: $(VM_PREFIX)

.PHONY: model

# VK_OBJS_FAST / VK_OBJS_SLOW / VK_GLOBAL_OBJS are defined by verilated.mk,
# so these rules have to come after the include.
%.o: %.cpp
	$(OBJCACHE) $(CXX) $(OPT_FAST) $(CXXFLAGS) $(CPPFLAGS) -c -o $@ $<

$(VK_OBJS_FAST): %.o: %.cpp
	$(OBJCACHE) $(CXX) $(OPT_FAST) $(CXXFLAGS) $(CPPFLAGS) -c $<

$(VK_OBJS_SLOW): %.o: %.cpp
	$(OBJCACHE) $(CXX) $(OPT_SLOW) $(CXXFLAGS) $(CPPFLAGS) -c $<

$(VK_GLOBAL_OBJS): %.o: %.cpp
	$(OBJCACHE) $(CXX) $(OPT_GLOBAL) $(CXXFLAGS) $(CPPFLAGS) -c -o $@ $<
