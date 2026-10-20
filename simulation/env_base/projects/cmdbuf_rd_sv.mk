# Revised SV DUT; all paths are relative to this checkout by default.
RTL_ROOT ?= $(abspath $(ENV_BASE)/../..)
TOP := cmdbuf_rd
BUILD_DIR ?= $(RTL_ROOT)/build/protocol_20261021/verilator
RESULT_DIR ?= $(RTL_ROOT)/build/protocol_20261021/simulation
RTL_FILES := $(RTL_ROOT)/rtl/cmdbuf_rd.sv $(RTL_ROOT)/rtl/cmdbuf_rd_cmd.sv $(RTL_ROOT)/rtl/cmdbuf_rd_otb.sv
HARNESS_FILES := $(ENV_BASE)/adapters/cmdbuf_rd_sv/cmdbuf_rd_sv_harness.cpp
CASE_DIR ?= $(ENV_BASE)/cases/cmdbuf_rd_sv
PARAM_ARGS := --language 1800-2017
ADAPTER_CFLAGS :=
