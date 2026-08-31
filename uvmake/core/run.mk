# ---------------------------------------------------------------------------
# uvmake/core/run.mk - running tests, waves and coverage.
# ---------------------------------------------------------------------------

SIM_BIN := $(OBJ_DIR)/V$(TB_TOP)
LOG_DIR := $(BUILD_ROOT)/logs
RUN_TAG  = $(TEST)-$(SEED)
RUN_DIR  = $(LOG_DIR)/$(RUN_TAG)

# +verilator+seed+ seeds Verilator's generator, which is what $urandom and
# the constraint solver draw from. +UVM_NO_RELNOTES silences the release
# banner on every run (it is a plusarg, not a compile-time define).
SIM_PLUSARGS = +UVM_TESTNAME=$(TEST) \
               +UVM_VERBOSITY=$(UVM_VERBOSITY) \
               +verilator+seed+$(SEED) \
               $(if $(RELNOTES),,+UVM_NO_RELNOTES) \
               $(if $(WAVE_EXT),+wave +wave_file=$(RUN_TAG).$(WAVE_EXT)) \
               $(if $(filter 1,$(COVERAGE)),+verilator+coverage+file+coverage.dat) \
               $(PLUSARGS)

.PHONY: run waves coverage coverage-report

# Each run gets its own directory, so waves, coverage and the log from one
# seed never overwrite another's - which is what makes a seed sweep usable.
run: build
ifeq ($(strip $(TEST)),)
	$(error TEST is not set. Try: make run TEST=<uvm_test_name>)
endif
	@mkdir -p $(RUN_DIR)
	@echo "[run]      $(TEST) seed=$(SEED)"
	@cd $(RUN_DIR) && $(abspath $(SIM_BIN)) $(SIM_PLUSARGS) $(SIM_ARGS) 2>&1 \
	  | tee sim.log
	@printf '[run]      %s\n' \
	  "$$($(UVMAKE_ROOT)/scripts/check_log.sh $(RUN_DIR)/sim.log)"
	@$(UVMAKE_ROOT)/scripts/check_log.sh $(RUN_DIR)/sim.log >/dev/null \
	  || (echo "[run]      see $(RUN_DIR)/sim.log"; false)

# Convenience: run with tracing on even if the build defaulted to none.
waves:
	@$(MAKE) run TRACE=$(if $(filter none,$(TRACE)),fst,$(TRACE))

# ---------------------------------------------------------------------------
# Coverage
#
# Verilator writes one coverage.dat per run. verilator_coverage merges them
# and can annotate the sources, which is the closest open-source equivalent
# of a commercial coverage report.
# ---------------------------------------------------------------------------
COV_DAT   := $(BUILD_ROOT)/coverage.dat
COV_INFO  := $(BUILD_ROOT)/coverage.info
COV_ANNOT := $(BUILD_ROOT)/coverage-annotated

coverage:
	@$(MAKE) run COVERAGE=1

coverage-report:
	@dats=$$(find $(LOG_DIR) -name coverage.dat 2>/dev/null); \
	if [ -z "$$dats" ]; then \
	  echo "[coverage] no coverage.dat found - run with COVERAGE=1 first"; exit 1; \
	fi; \
	echo "[coverage] merging $$(echo "$$dats" | wc -l) run(s)"; \
	$(VERILATOR_COVERAGE) --write $(COV_DAT) $$dats && \
	$(VERILATOR_COVERAGE) --write-info $(COV_INFO) $(COV_DAT) && \
	$(VERILATOR_COVERAGE) --annotate $(COV_ANNOT) --annotate-min 1 $(COV_DAT) && \
	echo "[coverage] merged:    $(COV_DAT)" && \
	echo "[coverage] lcov:      $(COV_INFO)   (genhtml, Codecov, ...)" && \
	echo "[coverage] annotated: $(COV_ANNOT)"

# ---------------------------------------------------------------------------
.PHONY: clean print-objdir print-config
clean:
	rm -rf $(BUILD_ROOT)

print-objdir:
	@echo $(OBJ_DIR)

print-config:
	@echo "tb        : $(TB_NAME) (top=$(TB_TOP))"
	@echo "uvm       : $(UVM_ID) at $(UVM_SRC)  dpi=$(UVM_DPI)"
	@echo "mode      : $(BUILD_MODE)  trace=$(TRACE)  coverage=$(COVERAGE)"
	@echo "shared    : $(USE_SHARED_LIBS)  pch=$(PCH)"
	@echo "objdir    : $(OBJ_DIR)"
	@echo "sources   : $(words $(UVMAKE_SOURCES)) file(s)"
	@echo "objcache  : $(if $(OBJCACHE),$(OBJCACHE),none)  jobs=$(BUILD_JOBS)"
