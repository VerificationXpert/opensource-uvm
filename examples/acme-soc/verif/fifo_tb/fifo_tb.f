// Testbench filelist.
//
// It pulls in the design team's own RTL filelist rather than duplicating the
// file list - which is the normal arrangement, and the reason -f recursion
// matters.

-f $PROJECT_ROOT/rtl/rtl.f

+incdir+$TB_DIR

$TB_DIR/fifo_if.sv
$TB_DIR/fifo_pkg.sv
$TB_DIR/fifo_test_pkg.sv
$TB_DIR/fifo_tb_top.sv
