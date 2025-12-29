.PHONY: help init up add-secret add-gh-pat rotate-keys reconcile status logs down clean preflight

SCRIPTS_DIR := ./scripts

help:
	@$(SCRIPTS_DIR)/help.sh

preflight:
	@$(SCRIPTS_DIR)/preflight.sh

init:
	@$(SCRIPTS_DIR)/init.sh

add-gh-pat:
	@$(SCRIPTS_DIR)/add-gh-pat.sh

up:
	@$(SCRIPTS_DIR)/bootstrap.sh

add-secret:
	@$(SCRIPTS_DIR)/add-secret.sh

rotate-keys:
	@$(SCRIPTS_DIR)/rotate-keys.sh

reconcile:
	@$(SCRIPTS_DIR)/reconcile.sh

status:
	@$(SCRIPTS_DIR)/status.sh

logs:
	@$(SCRIPTS_DIR)/logs.sh

down:
	@$(SCRIPTS_DIR)/down.sh

clean:
	@$(SCRIPTS_DIR)/clean.sh
