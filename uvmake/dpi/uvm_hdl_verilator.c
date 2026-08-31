//----------------------------------------------------------------------
// UVM HDL backdoor access backend for Verilator.
//
// Upstream uvm_hdl.c only ships backends for VCS, Questa and Xcelium and
// ends in `#error "hdl vendor backend is missing"` for every other tool,
// which is why open-source UVM flows are normally forced to compile with
// +define+UVM_HDL_NO_DPI (or the blanket UVM_NO_DPI) and lose uvm_reg
// backdoor access entirely.
//
// This file provides the missing backend on top of Verilator's VPI.  It is
// selected by defining VERILATOR before including uvm_hdl.c (see
// uvm_dpi_verilator.cpp), and implements the six entry points UVM imports
// in src/dpi/uvm_hdl.svh:
//
//   uvm_hdl_check_path, uvm_hdl_read, uvm_hdl_deposit,
//   uvm_hdl_force, uvm_hdl_release, uvm_hdl_release_and_read
//
// Capability notes for Verilator's VPI (as of 5.050):
//   * vpi_handle_by_name / vpi_get_value / vpi_put_value on scalars and
//     packed vectors work, but ONLY for signals Verilator was told to make
//     public (`--public-flat-rw`, or a /*verilator public_flat_rw*/
//     attribute, or a .vlt `public_flat_rw` rule).  Signals that are not
//     public simply do not resolve, exactly like a missing PLI/ACC
//     visibility in a commercial tool.
//   * Verilator has no force/release semantics.  uvm_hdl_force therefore
//     degrades to a deposit and uvm_hdl_release is a no-op read-back; both
//     report once through the normal UVM messaging path so the user is not
//     silently given the wrong behaviour.  This matches how uvm_reg
//     backdoor sequences actually use the API, which is dominated by
//     read/deposit.
//----------------------------------------------------------------------

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// UVM_HDL_MAX_WIDTH sizes the uvm_hdl_data_t arrays UVM passes across the
// DPI boundary.  The vendor backends read it back at run time from the
// uvm_pkg parameter via vpi_handle_by_name("uvm_pkg::UVM_HDL_MAX_WIDTH"),
// but Verilator does not expose package parameters over VPI, so it has to be
// agreed at compile time instead.
//
// This MUST match the value the SystemVerilog side was compiled with, or
// uvm_hdl_read below will clear past the end of UVM's array.  mk/uvm.mk and
// mk/verilator.mk both derive it from the single UVM_HDL_MAX_WIDTH variable
// in mk/config.mk and pass it to the C and the SV compile respectively; the
// default here matches UVM's own default and is only a fallback for someone
// compiling this file by hand.
#ifndef UVM_HDL_MAX_WIDTH
#define UVM_HDL_MAX_WIDTH 1024
#endif

#define UVM_HDL_MAX_CHUNKS (((UVM_HDL_MAX_WIDTH) - 1) / 32 + 1)

static int uvm_hdl_max_width(void) { return UVM_HDL_MAX_WIDTH; }

//----------------------------------------------------------------------
// Report helpers.  m_uvm_report_dpi is the exported UVM task that routes a
// message back through uvm_report_* so backdoor failures show up in the UVM
// log with the right severity, id and file/line - the same behaviour the
// vendor backends give.
//----------------------------------------------------------------------

static void uvm_vlt_hdl_report(int severity, const char *id, const char *fmt,
                               const char *path, const char *file, int line) {
    // The longest format below adds well under 256 characters of prose to the
    // caller-supplied path.
    size_t len = strlen(fmt) + (path ? strlen(path) : 0) + 256;
    char *buffer = (char *)malloc(len);
    if (!buffer) return;
    snprintf(buffer, len, fmt, path ? path : "(null)");
    m_uvm_report_dpi(severity, (char *)id, buffer, M_UVM_NONE, (char *)file, line);
    free(buffer);
}

// Resolve an HDL path to a VPI handle.
//
// Two spellings have to be accepted so that hdl_paths written for a
// commercial simulator work here unchanged:
//
//   * A leading "$root." is stripped, as the vendor backends do.
//   * Verilator roots its VPI name space at an implicit "TOP" scope above
//     the --top-module, so a design signal that a commercial tool calls
//     "tb_top.dut.reg_q" is "TOP.tb_top.dut.reg_q" here.  Try the path as
//     given first, then again with the prefix, so a register model does not
//     have to know which simulator it is running on.  Paths that already
//     start with "TOP." simply succeed on the first attempt.
static vpiHandle uvm_vlt_handle(const char *path) {
    vpiHandle r;
    char *prefixed;
    size_t len;

    if (!path) return 0;
    if (!strncmp(path, "$root.", 6)) path += 6;

    r = vpi_handle_by_name((PLI_BYTE8 *)path, 0);
    if (r) return r;

    len = strlen(path) + sizeof("TOP.");
    prefixed = (char *)malloc(len);
    if (!prefixed) return 0;
    snprintf(prefixed, len, "TOP.%s", path);
    r = vpi_handle_by_name((PLI_BYTE8 *)prefixed, 0);
    free(prefixed);
    return r;
}

//----------------------------------------------------------------------
// Public entry points
//----------------------------------------------------------------------

int uvm_hdl_check_path(char *path) {
    vpiHandle r = uvm_vlt_handle(path);
    if (r == 0) return 0;
    vpi_release_handle(r);
    return 1;
}

int uvm_hdl_read(char *path, p_vpi_vecval value) {
    vpiHandle r = uvm_vlt_handle(path);
    s_vpi_value value_s;
    int i, size, chunks;

    if (r == 0) {
        uvm_vlt_hdl_report(
            M_UVM_ERROR, "UVM/DPI/HDL_GET",
            "uvm_hdl_read: unable to locate hdl path (%s)\n"
            "  The name may be wrong, or the signal may not be public to VPI.\n"
            "  Verilate with --public-flat-rw, or mark the signal with\n"
            "  /*verilator public_flat_rw*/ or a .vlt public_flat_rw rule.",
            path, __FILE__, __LINE__);
        return 0;
    }

    size = vpi_get(vpiSize, r);
    if (size > uvm_hdl_max_width()) {
        uvm_vlt_hdl_report(M_UVM_ERROR, "UVM/DPI/HDL_SET",
                           "uvm_hdl_read: hdl path (%s) is wider than "
                           "UVM_HDL_MAX_WIDTH; cannot read it.",
                           path, __FILE__, __LINE__);
        vpi_release_handle(r);
        return 0;
    }

    value_s.format = vpiVectorVal;
    vpi_get_value(r, &value_s);

    // vpi_get_value hands back a buffer owned by the VPI implementation and
    // only valid until the next call, so copy it into UVM's array.  UVM sizes
    // that array to UVM_HDL_MAX_WIDTH bits; clear the tail so stale data from
    // a previous, wider read cannot leak through.
    chunks = (size - 1) / 32 + 1;
    for (i = 0; i < chunks; ++i) {
        value[i].aval = value_s.value.vector[i].aval;
        value[i].bval = value_s.value.vector[i].bval;
    }
    for (i = chunks; i < UVM_HDL_MAX_CHUNKS; ++i) {
        value[i].aval = 0;
        value[i].bval = 0;
    }

    vpi_release_handle(r);
    return 1;
}

int uvm_hdl_deposit(char *path, p_vpi_vecval value) {
    vpiHandle r = uvm_vlt_handle(path);
    s_vpi_value value_s;
    s_vpi_time time_s = {vpiSimTime, 0, 0, 0.0};

    if (r == 0) {
        uvm_vlt_hdl_report(
            M_UVM_ERROR, "UVM/DPI/HDL_SET",
            "uvm_hdl_deposit: unable to locate hdl path (%s)\n"
            "  The name may be wrong, or the signal may not be public to VPI.\n"
            "  Verilate with --public-flat-rw, or mark the signal with\n"
            "  /*verilator public_flat_rw*/ or a .vlt public_flat_rw rule.",
            path, __FILE__, __LINE__);
        return 0;
    }

    if (vpi_get(vpiSize, r) > uvm_hdl_max_width()) {
        uvm_vlt_hdl_report(M_UVM_ERROR, "UVM/DPI/HDL_SET",
                           "uvm_hdl_deposit: hdl path (%s) is wider than "
                           "UVM_HDL_MAX_WIDTH; cannot write it.",
                           path, __FILE__, __LINE__);
        vpi_release_handle(r);
        return 0;
    }

    value_s.format = vpiVectorVal;
    value_s.value.vector = value;
    vpi_put_value(r, &value_s, &time_s, vpiNoDelay);

    vpi_release_handle(r);
    return 1;
}

// Verilator has no force/release.  Deposit instead and say so exactly once,
// so a testbench ported from a commercial tool keeps running with the closest
// available behaviour rather than failing outright - but the user is told
// that the value can be overwritten by the design on the next evaluation.
int uvm_hdl_force(char *path, p_vpi_vecval value) {
    static int warned = 0;
    if (!warned) {
        warned = 1;
        uvm_vlt_hdl_report(
            M_UVM_WARNING, "UVM/DPI/HDL_FORCE",
            "uvm_hdl_force: Verilator's VPI has no force/release; the value "
            "for (%s) is being deposited instead.  The design may overwrite it "
            "on the next evaluation.  This warning is issued once.",
            path, __FILE__, __LINE__);
    }
    return uvm_hdl_deposit(path, value);
}

int uvm_hdl_release_and_read(char *path, p_vpi_vecval value) {
    // Nothing was ever forced (see uvm_hdl_force), so releasing reduces to
    // reading back whatever the signal currently holds.
    return uvm_hdl_read(path, value);
}

int uvm_hdl_release(char *path) {
    // No-op: uvm_hdl_force deposited rather than forced, so there is no
    // force to undo.  Still validate the path so a typo is reported.
    return uvm_hdl_check_path(path);
}
