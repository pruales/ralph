.PHONY: install session-init session-list session-codex session-claude

install:
	bash ./install.sh

session-init:
	@if [ -z "$(NAME)" ]; then echo "Usage: make session-init NAME=feature-x"; exit 1; fi
	./ralph.sh init "$(NAME)"

session-list:
	./ralph.sh list

session-codex:
	@if [ -z "$(NAME)" ]; then echo "Usage: make session-codex NAME=feature-x"; exit 1; fi
	./ralph.sh --session "$(NAME)" codex

session-claude:
	@if [ -z "$(NAME)" ]; then echo "Usage: make session-claude NAME=feature-x"; exit 1; fi
	./ralph.sh --session "$(NAME)" claude
