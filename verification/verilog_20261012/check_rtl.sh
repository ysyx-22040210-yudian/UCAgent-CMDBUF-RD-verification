#!/bin/bash
# Strict Verilog compilation, synthesis-front-end equivalence and existing simulation regression.
set -euo pipefail
cd /root/cmdbuf_rd/verilog_20261012
mkdir -p validation
iverilog -g2001 -s cmdbuf_rd -o validation/verilog2001.vvp rtl/cmdbuf_rd.v rtl/cmdbuf_rd_cmd.v rtl/cmdbuf_rd_otb.v >validation/iverilog.log 2>&1
iverilog -g2001 -DSYNTHESIS -s cmdbuf_rd -o validation/verilog2001_synthesis.vvp rtl/cmdbuf_rd.v rtl/cmdbuf_rd_cmd.v rtl/cmdbuf_rd_otb.v >validation/iverilog_synthesis.log 2>&1
verilator --lint-only --Wall --assert --language 1364-2001 --top-module cmdbuf_rd rtl/cmdbuf_rd.v rtl/cmdbuf_rd_cmd.v rtl/cmdbuf_rd_otb.v >validation/lint.log 2>&1
printf '%s\n' 'STRICT VERILOG COMPILE AND LINT: PASSED'
/home/ucagent-lab/portable-distributions/UCAgent-Studio-0.3.1-linux-x86_64/oss-cad-suite/bin/yosys -Q -T -s equivalence.ys >validation/equivalence.log 2>&1
tail -6 validation/equivalence.log
make -f /root/env_base/env/Makefile PROJECT_CONFIG=/root/cmdbuf_rd/verilog_20261012/cmdbuf_rd.mk RTL_ROOT=/root/cmdbuf_rd/verilog_20261012 RESULT_DIR=/root/cmdbuf_rd/verilog_20261012/validation/simulation validate
make -f /root/env_base/env/Makefile PROJECT_CONFIG=/root/cmdbuf_rd/verilog_20261012/cmdbuf_rd.mk RTL_ROOT=/root/cmdbuf_rd/verilog_20261012 RESULT_DIR=/root/cmdbuf_rd/verilog_20261012/validation/simulation run-all >validation/simulation.log 2>&1
tail -4 validation/simulation.log
printf '%s\n' 'RTL MIGRATION CHECKS: PASSED'
