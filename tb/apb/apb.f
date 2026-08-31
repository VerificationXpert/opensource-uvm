// APB testbench filelist.
//
// Order matters: packages must precede the modules that import them.

+incdir+$TB_DIR/tb
+incdir+$TB_DIR/tests

$TB_DIR/rtl/apb_slave_regs.sv
$TB_DIR/tb/apb_if.sv
$TB_DIR/tb/apb_pkg.sv
$TB_DIR/tb/apb_env_pkg.sv
$TB_DIR/tests/apb_test_pkg.sv
$TB_DIR/tb/apb_tb_top.sv
