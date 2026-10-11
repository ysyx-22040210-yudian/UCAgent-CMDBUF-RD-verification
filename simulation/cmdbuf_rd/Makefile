ENV_BASE ?= /root/env_base
CONFIG := $(ENV_BASE)/projects/cmdbuf_rd.mk
.PHONY: all build lint test validate clean-info
all: lint test
build lint validate:
	$(MAKE) -f $(ENV_BASE)/env/Makefile PROJECT_CONFIG=$(CONFIG) $@
test:
	$(MAKE) -f $(ENV_BASE)/env/Makefile PROJECT_CONFIG=$(CONFIG) run-all
clean-info:
	@echo 'Build artifacts: /root/cmdbuf_rd/build; results: /root/cmdbuf_rd/results'
