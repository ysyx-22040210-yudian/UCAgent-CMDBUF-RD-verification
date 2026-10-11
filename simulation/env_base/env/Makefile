SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
ENV_BASE := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
PROJECT_CONFIG ?= $(ENV_BASE)/projects/dmac.mk
include $(PROJECT_CONFIG)
VERILATOR ?= verilator
TOOLCHAIN_ENABLE ?= /opt/rh/devtoolset-11/enable
SETUP = if [ -f "$(TOOLCHAIN_ENABLE)" ]; then source "$(TOOLCHAIN_ENABLE)"; fi
JOBS ?= 2
SIM := $(BUILD_DIR)/sim
.PHONY: build lint run-all run-case validate
build: $(SIM)
$(SIM): $(RTL_FILES) $(HARNESS_FILES) $(PROJECT_CONFIG) $(ENV_BASE)/env/Makefile
	@mkdir -p "$(BUILD_DIR)" "$(RESULT_DIR)"
	@$(SETUP); $(VERILATOR) --cc --exe --build --Wall --assert --trace --x-initial unique --x-assign unique --top-module $(TOP) --Mdir "$(BUILD_DIR)" -o sim -j $(JOBS) $(PARAM_ARGS) -CFLAGS "-std=c++17 -O2 $(ADAPTER_CFLAGS)" $(RTL_FILES) $(HARNESS_FILES)
lint:
	@mkdir -p "$(RESULT_DIR)"
	@$(SETUP); $(VERILATOR) --lint-only --Wall --assert --top-module $(TOP) $(PARAM_ARGS) $(RTL_FILES) 2>&1 | tee "$(RESULT_DIR)/lint.log"
validate:
	@python3 "$(ENV_BASE)/scripts/validate_env.py" "$(ENV_BASE)"
run-all: build
	@$(SETUP); python3 "$(ENV_BASE)/scripts/run_cases.py" --sim "$(SIM)" --cases "$(CASE_DIR)" --results "$(RESULT_DIR)"
run-case: build
	@mkdir -p "$(RESULT_DIR)"
	@$(SETUP); "$(SIM)" --case "$(CASE)" --result-dir "$(RESULT_DIR)" $(EXTRA_ARGS)
