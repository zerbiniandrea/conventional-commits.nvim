.PHONY: lint format check

lint: ## Run luacheck
	@luacheck .

format: ## Format code with stylua
	@stylua .

check: lint format ## Lint and format code
	@echo "✓ All checks passed!"

.DEFAULT_GOAL := check
