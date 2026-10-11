# DUT-specific paths; the common runner stays unchanged.
RTL_ROOT ?= /root/cmdbuf_rd
TOP := cmdbuf_rd
BUILD_DIR ?= $(RTL_ROOT)/build/verilator
RESULT_DIR ?= $(RTL_ROOT)/results/baseline
RTL_FILES := $(RTL_ROOT)/rtl/cmdbuf_rd.sv $(RTL_ROOT)/rtl/cmdbuf_rd_cmd.sv $(RTL_ROOT)/rtl/cmdbuf_rd_otb.sv
HARNESS_FILES := $(ENV_BASE)/adapters/cmdbuf_rd/cmdbuf_rd_harness.cpp
CASE_DIR ?= $(ENV_BASE)/cases/cmdbuf_rd
PARAM_ARGS :=
ADAPTER_CFLAGS :=
