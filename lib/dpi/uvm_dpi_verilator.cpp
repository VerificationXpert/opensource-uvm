//----------------------------------------------------------------------
// UVM DPI translation unit for Verilator.
//
// This is a drop-in replacement for the upstream src/dpi/uvm_dpi.cc.  It
// pulls in exactly the same UVM DPI sources, except that the HDL backdoor
// backend comes from uvm_hdl_verilator.c instead of uvm_hdl.c - the latter
// only knows about VCS/Questa/Xcelium and ends in
// `#error "hdl vendor backend is missing"` on any other tool.
//
// Building the UVM DPI layer separately (rather than letting each testbench
// re-compile it) is what lets the whole thing be shipped as libuvmdpi.so and
// linked into every simulation binary.
//
// The upstream UVM tree is used completely unpatched; everything
// Verilator-specific lives in this directory.
//----------------------------------------------------------------------

#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

// These have to sit inside the extern "C" block: uvm_dpi.h declares the
// shared DPI helpers (m_uvm_report_dpi, int_str_max, ...) without linkage
// markup of its own, and the UVM .c files that define them are pulled in
// below with C linkage.  Declaring them as C++ first makes the definitions
// conflict.  Upstream uvm_dpi.cc does the same thing.
#include "svdpi.h"
#include "vpi_user.h"
#include "uvm_dpi.h"

// Forward declarations, mirroring upstream uvm_dpi.cc, to avoid
// -Wmissing-declarations on the definitions that follow.
int uvm_hdl_check_path(char *path);
int uvm_hdl_read(char *path, p_vpi_vecval value);
int uvm_hdl_deposit(char *path, p_vpi_vecval value);
int uvm_hdl_force(char *path, p_vpi_vecval value);
int uvm_hdl_release_and_read(char *path, p_vpi_vecval value);
int uvm_hdl_release(char *path);
void push_data(int lvl, char *entry, int cmd);
void walk_level(int lvl, int argc, char **argv, int cmd);
const char *uvm_dpi_get_next_arg_c(int init);
extern char *uvm_dpi_get_tool_name_c();
extern char *uvm_dpi_get_tool_version_c();

extern char *uvm_re_buffer();
extern const char *uvm_re_deglobbed(const char *glob, unsigned char with_brackets);
extern void uvm_re_free(regex_t *handle);
extern regex_t *uvm_re_comp(const char *re, unsigned char deglob);
extern int uvm_re_exec(regex_t *rexp, const char *str);
extern regex_t *uvm_re_compexec(const char *re, const char *str, unsigned char deglob,
                                int *exec_ret);

// Shared helpers (m_uvm_report_dpi and friends).
#include "uvm_common.c"

// POSIX-regex implementation of uvm_re_*.  Pure C, no simulator API at all,
// so it works on Verilator unchanged.  Having it means UVM gets real regular
// expressions (and, in 2020.3.x, the compiled-regex LRU cache in
// uvm_regex_cache.svh) instead of the glob-only fallback that
// UVM_REGEX_NO_DPI leaves you with.
#include "uvm_regex.cc"

// Verilator VPI backdoor backend, in place of upstream uvm_hdl.c.
#include "uvm_hdl_verilator.c"

// Command-line access (+UVM_TESTNAME, +uvm_set_config_*, +UVM_VERBOSITY, ...)
// through vpi_get_vlog_info, which Verilator implements.
#include "uvm_svcmd_dpi.c"

#ifdef __cplusplus
}
#endif

// uvm_hdl_polling.c (new in UVM 2020.3) drives value-change callbacks for
// the passive polling API.  It is included when the build has been told
// Verilator's VPI can support it; otherwise the stubs below keep the DPI
// symbols resolvable and report cleanly if a testbench actually calls them.
#ifdef UVM_VLT_POLLING_SUPPORTED
extern "C" {
#include "uvm_hdl_polling.c"
}
#else
#include <cstdio>
extern "C" {

static void uvm_vlt_polling_unsupported(const char *fn) {
    static int reported = 0;
    if (reported) return;
    reported = 1;
    char buffer[512];
    snprintf(buffer, sizeof(buffer),
             "%s: the UVM passive polling API is not enabled in this Verilator "
             "build.  Rebuild the UVM DPI library with "
             "UVM_VLT_POLLING=1 to include uvm_hdl_polling.c.  "
             "This message is issued once.",
             fn);
    m_uvm_report_dpi(M_UVM_ERROR, (char *)"UVM/DPI/POLLING_UNSUPPORTED", buffer, M_UVM_NONE,
                     (char *)__FILE__, __LINE__);
}

void *uvm_polling_create(const char *name, int sv_key) {
    (void)name;
    (void)sv_key;
    uvm_vlt_polling_unsupported("uvm_polling_create");
    return NULL;
}

void uvm_polling_set_enable_callback(void *hnd, int enable) {
    (void)hnd;
    (void)enable;
    uvm_vlt_polling_unsupported("uvm_polling_set_enable_callback");
}

int uvm_polling_get_callback_enable(void *hnd) {
    (void)hnd;
    uvm_vlt_polling_unsupported("uvm_polling_get_callback_enable");
    return 0;
}

int uvm_polling_setup_notifier(const char *fullname) {
    (void)fullname;
    uvm_vlt_polling_unsupported("uvm_polling_setup_notifier");
    return 0;
}

void uvm_polling_process_changelist(void) {
    uvm_vlt_polling_unsupported("uvm_polling_process_changelist");
}

// Not polling-specific, but it lives in uvm_hdl_polling.c upstream, so it has
// to be provided alongside the stubs.  vpi_get(vpiSize) is well supported by
// Verilator, so give the real answer rather than a stub.
int uvm_hdl_signal_size(const char *path) {
    vpiHandle r = uvm_vlt_handle(path);
    int size;
    if (r == 0) return 0;
    size = vpi_get(vpiSize, r);
    vpi_release_handle(r);
    return size;
}

}  // extern "C"
#endif  // UVM_VLT_POLLING_SUPPORTED
