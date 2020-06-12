DOCS_ROOT ?= $(ROOT)/doc
MKDOCS_DIR ?= $(DOCS_ROOT)/mkdocs
DEV_YML ?= $(MKDOCS_DIR)/mkdocs.yml
DEV_HEADER_YML ?= $(MKDOCS_DIR)/dev_header_yml

.PHONY: docs
docs: docs-collect docs-validate docs-setup docs-build

.PHONY: admonitions
admonitions:
	@ERL_LIBS=$(DEPS_DIR):$(CORE_DIR):$(APPS_DIR) $(ROOT)/scripts/check-admonitions.escript $(shell grep -rlE '^!!! ' scripts $(APPS_DIR) $(CORE_DIR) $(DOCS_ROOT))

.PHONY: docs-validate
docs-validate:
	@$(ROOT)/scripts/check-scripts-readme.bash
	@$(ROOT)/scripts/empty_schema_descriptions.bash
	@$(ROOT)/scripts/check-ref-docs.bash
	@ERL_LIBS=$(DEPS_DIR):$(CORE_DIR):$(APPS_DIR) $(ROOT)/scripts/check-admonitions.escript $(CHANGED)

.PHONY: docs-collect
docs-collect:
	@cp $(DEV_HEADER_YML) $(DEV_YML)
	@$(ROOT)/scripts/collect-dev-yml.bash $(DEV_YML) $(APPS_DIR) $(CORE_DIR) $(DOCS_ROOT)

.PHONY: docs-setup
docs-setup:
	@$(ROOT)/scripts/validate_mkdocs.py
	@$(ROOT)/scripts/setup_docs.bash

.PHONY: docs-build
docs-build:
	@$(MAKE) -C $(MKDOCS_DIR) DOCS_ROOT=$(MKDOCS_DIR) docs-build

.PHONY: docs-clean
docs-clean:
	@$(MAKE) -C $(MKDOCS_DIR) MKDOCS_DIR=$(MKDOCS_DIR) clean

.PHONY: docs-serve
docs-serve: docs-setup docs-build
	@$(MAKE) -C $(MKDOCS_DIR) YML=$(YML) MKDOCS_DIR=$(MKDOCS_DIR) docs-serve
