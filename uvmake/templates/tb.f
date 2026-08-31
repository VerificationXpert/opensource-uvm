// Testbench filelist.
//
// Predefined variables: $PROJECT_ROOT, $TB_DIR (this filelist's testbench
// directory) and $UVM_HOME. Any other $VAR comes from the environment.
// Relative paths resolve against the directory of the filelist naming them.
//
// uvm_pkg.sv is compiled automatically; do not list it here.

// Pull in the design's own filelist rather than duplicating it.
-f $PROJECT_ROOT/rtl/rtl.f

+incdir+$TB_DIR
// +define+MY_FLAG=1

// Order matters: packages before the modules that import them.
$TB_DIR/my_if.sv
$TB_DIR/my_pkg.sv
$TB_DIR/my_test_pkg.sv
$TB_DIR/my_tb_top.sv
