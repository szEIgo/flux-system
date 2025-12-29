.PHONY: help init up add-secret add-gh-pat rotate-keys reconcile status logs down clean

SCRIPTS_DIR := ./scripts
ARGS ?=

help:
	@$(SCRIPTS_DIR)/help.sh

init:
	@$(SCRIPTS_DIR)/init.sh $(ARGS)

add-gh-pat:
	@$(SCRIPTS_DIR)/add-gh-pat.sh $(ARGS)

up:
	@$(SCRIPTS_DIR)/bootstrap.sh $(ARGS)

add-secret:
	@$(SCRIPTS_DIR)/add-secret.sh $(ARGS)

rotate-keys:
	@$(SCRIPTS_DIR)/rotate-keys.sh $(ARGS)

reconcile:
	@$(SCRIPTS_DIR)/reconcile.sh $(ARGS)

status:
	@$(SCRIPTS_DIR)/status.sh $(ARGS)

logs:
	@$(SCRIPTS_DIR)/logs.sh $(ARGS)

down:
	@$(SCRIPTS_DIR)/down.sh $(ARGS)

clean:
	@$(SCRIPTS_DIR)/clean.sh $(ARGS)

