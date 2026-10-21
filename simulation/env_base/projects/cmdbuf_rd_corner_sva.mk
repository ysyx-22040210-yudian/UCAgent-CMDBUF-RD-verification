# Same unchanged SV DUT and existing native scenarios, with Corner SVA enabled.
include $(ENV_BASE)/projects/cmdbuf_rd_sva.mk
PARAM_ARGS += -DCMDBUF_CORNER_SUITE -I$(RTL_ROOT)/formal/corner_20261021 -Wno-UNUSEDSIGNAL
CORNER_INCLUDES := $(wildcard $(RTL_ROOT)/formal/corner_20261021/*.svh)
$(BUILD_DIR)/sim: $(CORNER_INCLUDES)
