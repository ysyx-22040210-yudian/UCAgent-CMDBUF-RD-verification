# Exercise the current native SVA with invalid payload noise and disabled reset.
RTL_ROOT ?= $(abspath $(ENV_BASE)/../..)
TOP := cmdbuf_rd_checked
BUILD_DIR ?= $(RTL_ROOT)/build/sva_alignment/verilator
RESULT_DIR ?= $(RTL_ROOT)/build/sva_alignment/simulation
RTL_FILES := $(RTL_ROOT)/rtl/cmdbuf_rd.sv $(RTL_ROOT)/rtl/cmdbuf_rd_cmd.sv $(RTL_ROOT)/rtl/cmdbuf_rd_otb.sv $(RTL_ROOT)/formal/protocol_20261021/cmdbuf_rd_port_sva.sv $(RTL_ROOT)/formal/protocol_20261021/cmdbuf_rd_checked.sv
# Included model files are prerequisites, not separately compiled modules.
SVA_INCLUDES := $(RTL_ROOT)/formal/protocol_20261021/cmdbuf_rd_reference_model.svh $(RTL_ROOT)/formal/protocol_20261021/cmdbuf_rd_xau_order_model.svh
$(BUILD_DIR)/sim: $(SVA_INCLUDES)
HARNESS_FILES := $(ENV_BASE)/adapters/cmdbuf_rd_sv/cmdbuf_rd_sv_harness.cpp
CASE_DIR ?= $(ENV_BASE)/cases/cmdbuf_rd_sv
PARAM_ARGS := --language 1800-2017 --prefix Vcmdbuf_rd -I$(RTL_ROOT)/formal/protocol_20261021 -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-SYNCASYNCNET
ADAPTER_CFLAGS :=
