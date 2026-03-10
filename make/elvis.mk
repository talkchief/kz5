DEPS = elvis

dep_elvis = git $(FETCH_AS)2600hz/erlang-elvis a482801f953523d6678a550a184079e2818e5c68
# used by all to check formatting

ELVIS_DEP_DIR = $(DEPS_DIR)/elvis
ELVIS = $(ROOT)/elvis

FETCH_AS ?= https://github.com/

$(ELVIS_DEP_DIR):
	@echo creating elvis dir $(ELVIS_DEP_DIR)
	@mkdir -p $(shell dirname $(ELVIS_DEP_DIR))
	ROOT=$(ROOT) DEPS_MK="$(ROOT)/make/elvis.mk" $(MAKE) -C $(DEPS_DIR)/ all

.PHONY: elvis-escript
elvis-escript: $(ELVIS_DEP_DIR)
	@ERLANG_MK_FILENAME=$(ROOT)/erlang.mk DEPS_DIR=$(ROOT)/deps ESCRIPT_NAME=elvis ESCRIPT_FILE=$(ROOT)/elvis make -C $(ELVIS_DEP_DIR) escript

$(ELVIS): $(ELVIS_DEP_DIR)
	@ERLANG_MK_FILENAME=$(ROOT)/erlang.mk DEPS_DIR=$(ROOT)/deps ESCRIPT_NAME=elvis ESCRIPT_FILE=$(ROOT)/elvis make -C $(ELVIS_DEP_DIR) escript

.PHONY: elvis
elvis: $(ELVIS)
# need $(CHANGED_ERL) absolute paths to be relative to $(ROOT)
	@ERL_LIBS=$(DEPS_DIR):$(CORE_DIR) $(ELVIS) --config $(ROOT)/make/elvis.config --verbose -k --parallel auto rock $(subst $(ROOT)/,,$(filter %.erl,$(CHANGED_ERL)))

.PHONY: clean-elvis
clean-elvis:
	@rm -f $(ELVIS)
	@rm -rf $(ELVIS_DEP_DIR)
