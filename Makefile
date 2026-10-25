# Makefile
#
# The tasks of commit-checks; `make help` lists them.

SHELL := bash
# inherit_errexit keeps errexit on inside each $(...) of a recipe.
.SHELLFLAGS := -O inherit_errexit -o errexit -o nounset -o pipefail -c
.DEFAULT_GOAL := help

SCRIPT := commit-checks.py
INSTALL_DIR ?= $(HOME)/.local/bin
INSTALL_NAME ?= commit-checks

# ruff and mypy come from the group dev of pyproject.toml, at the versions of uv.lock.
# --quiet hides the note of uv that a repository without a package has no requires-python.
UV ?= uv
RUFF ?= $(UV) run --locked --quiet ruff
MYPY ?= $(UV) run --locked --quiet mypy
PRE_COMMIT ?= pre-commit

SHELL_FILES := tests/support/test-helper.bash
BATS_FILES := $(wildcard tests/*/*.bats)
# bats runs the tests at the same time where GNU parallel is,
# since each test keeps its repository in BATS_TEST_TMPDIR;
# BATS_JOBS='--jobs 1' on the command line runs them one by one.
BATS_JOBS := $(if $(shell command -v parallel),--jobs $(shell nproc))

# A hook runs under the python3 that PATH finds on each machine that commits,
# so test-floor runs the tests again with python3 as the oldest Python they support,
# which uv brings.
PYTHON_FLOOR := 3.10

help: ## List the tasks
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) \
	  | awk -F ':.*## ' '{ printf "  %-14s %s\n", $$1, $$2 }'

lint: lint-python lint-shell lint-md ## Run every linter

lint-python: ## ruff and mypy, as pyproject.toml sets them
	$(RUFF) check .
	$(MYPY) $(SCRIPT)

lint-shell: ## shellcheck, on the tests
	shellcheck $(SHELL_FILES) $(BATS_FILES)

lint-md: ## rumdl, on every Markdown file, as .rumdl.toml says
	rumdl check .

format: ## Format the Python and the shell code
	$(RUFF) format .
	shfmt -w $(SHELL_FILES) $(BATS_FILES)

format-check: ## Check the format of the Python and the shell code
	$(RUFF) format --check .
	shfmt -d $(SHELL_FILES) $(BATS_FILES)

test: ## Run every test
	bats $(BATS_JOBS) $(BATS_FILES)

test-floor: ## Run every test with python3 as the oldest Python that the hooks support
	$(UV) python install --quiet $(PYTHON_FLOOR)
	floor_directory="$$(mktemp -d)"; \
	  trap "rm -rf -- $${floor_directory@Q}" EXIT; \
	  python_path="$$($(UV) python find $(PYTHON_FLOOR))"; \
	  ln -s -- "$${python_path}" "$${floor_directory}/python3"; \
	  python_version="$$("$${floor_directory}/python3" --version)"; \
	  printf 'python3 is %s\n' "$${python_version}"; \
	  PATH="$${floor_directory}:$${PATH}" bats $(BATS_JOBS) $(BATS_FILES)

check: lint format-check test test-floor ## Run everything a change must pass

install: ## Link the script into INSTALL_DIR as commit-checks
	mkdir -p -- '$(INSTALL_DIR)'
	ln -sfn -- '$(CURDIR)/$(SCRIPT)' '$(INSTALL_DIR)/$(INSTALL_NAME)'

# Only a link into this checkout goes, so a commit-checks of another source stays;
# a missing link is no failure, since there is nothing to remove.
uninstall: ## Remove the link that install made
	link_target="$$(readlink -- '$(INSTALL_DIR)/$(INSTALL_NAME)' || true)"; \
	  if [[ "$${link_target}" == '$(CURDIR)/$(SCRIPT)' ]]; then \
	    rm -- '$(INSTALL_DIR)/$(INSTALL_NAME)'; \
	  fi

hooks: ## Install the git hooks of .pre-commit-config.yaml, for commits and their messages
	$(PRE_COMMIT) install --install-hooks

.PHONY: help lint lint-python lint-shell lint-md format format-check test test-floor check install uninstall hooks
