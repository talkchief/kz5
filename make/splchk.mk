.PHONY = splchk splchk-docs splchk-changed splchk-json splchk-code

KAZOO_DICT = .aspell.en.pws
KAZOO_REPL = .aspell.en.prepl

$(ROOT)/$(KAZOO_DICT):
	@$(file >$(ROOT)/$(KAZOO_DICT),personal_ws-1.1 en 0 utf-8)

$(ROOT)/$(KAZOO_REPL):
	@$(file >$(ROOT)/$(KAZOO_REPL),personal_repl-1.1 en 0 utf-8)

splchk-init: $(ROOT)/$(KAZOO_DICT) $(ROOT)/$(KAZOO_REPL)

splchk: splchk-changed

ifeq ($(wildcard $(CURDIR)/doc/*.md),)
splchk-docs:: splchk-init
else
DOCS := $(shell find doc -type f -name "*.md" -o -regex "doc/mkdocs/.+" -prune)
splchk-docs:: splchk-init $(addsuffix .chk,$(basename $(DOCS)))
endif

ifneq ($(wildcard $(CURDIR)/priv/templates/*),)
TEMPLATES := $(shell find $(CURDIR)/priv/templates -type f)
splchk-docs:: splchk-init $(addsuffix .chk,$(basename $(TEMPLATES)))
endif

ifneq ($(wildcard $(CURDIR)/test/rendered-templates/*),)
RENDERED_TEMPLATES := $(shell find $(CURDIR)/test/rendered-templates -type f)
splchk-docs:: splchk-init $(addsuffix .chk,$(basename $(RENDERED_TEMPLATES)))
endif

ifneq ($(wildcard $(CURDIR)/priv/*/templates/*),)
TEMPLATES := $(shell find $(CURDIR)/priv/*/templates/ -type f)
splchk-docs:: splchk-init $(addsuffix .chk,$(basename $(TEMPLATES)))
endif

JSON := $(wildcard $(CURDIR)/priv/couchdb/schemas/*.json)
ifeq ($(JSON),)
splchk-json: splchk-init
else
splchk-json: splchk-init $(addsuffix .chk,$(basename $(JSON)))
endif

ESCRIPTS := $(wildcard $(CURDIR)/scripts/*.escript)
SRC := $(wildcard $(CURDIR)/src/*.*rl) $(wildcard $(CURDIR)/src/*/*.erl) $(wildcard $(CURDIR)/include/*.hrl)
CODE := $(SRC) $(ESCRIPTS)
ifeq ($(CODE),)
splchk-code: splchk-init
else
splchk-code: splchk-init $(addsuffix .chk,$(basename $(CODE)))
endif

.PHONY: splchk-changed
splchk-changed: splchk-init $(addsuffix .chk,$(basename $(CHANGED)))

.PHONY: splchk-common
splchk-common: $(addsuffix .common,$(basename $(CHANGED_ERL)) $(basename $(CHANGED_JSON)) $(basename $(CHANGED_YML)) $(basename $(CHANGED_DOCS)))

%.common: %.mk
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.md
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.json
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.text
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.tmpl
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.erl
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.escript
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.hrl
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.html
	@$(ROOT)/scripts/check-spelling.bash $<
%.common: %.py
	@$(ROOT)/scripts/check-spelling.bash $<

%.chk: %.md
	@aspell --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<

%.chk: %.json
	@aspell --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<

%.chk: %.text
	@aspell --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<

%.chk: %.tmpl
	@aspell --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<

%.chk: %.erl
	@aspell --add-filter-path=$(ROOT) --mode=erlang --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<

%.chk: %.escript
	@aspell --add-filter-path=$(ROOT) --mode=erlang --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<

%.chk: %.hrl
	@aspell --add-filter-path=$(ROOT) --mode=erlang --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<

%.chk: %.html
	@aspell --add-filter-path=$(ROOT) --mode=html --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<

%.chk: Makefile
	@aspell --add-filter-path=$(ROOT) --mode=erlang --home-dir=$(ROOT) --personal=$(KAZOO_DICT) --repl=$(KAZOO_REPL) --lang=en -x check $<
