SHELL := /bin/bash

BASE ?= ubuntu
AGENT ?= hermes

.PHONY: help build-base build-agent build-all validate new-agent test-agent test-all enable-agent disable-agent

help:
	@echo "Targets:"
	@echo "  make build-base BASE=ubuntu"
	@echo "  make build-agent AGENT=hermes"
	@echo "  make build-all"
	@echo "  make validate"
	@echo "  make new-agent AGENT=my-agent"
	@echo "  make test-agent AGENT=hermes"
	@echo "  make test-all"
	@echo "  make enable-agent AGENT=hermes"
	@echo "  make disable-agent AGENT=hermes"

build-base:
	./scripts/build-base.sh $(BASE)

build-agent:
	./scripts/build-agent.sh $(AGENT)

build-all:
	./scripts/build-all.sh

validate:
	./scripts/validate-registry.sh

new-agent:
	./scripts/new-agent.sh $(AGENT)

test-agent:
	./scripts/test-agent.sh $(AGENT)

test-all:
	./scripts/test-all.sh

enable-agent:
	./scripts/enable-agent.sh $(AGENT)

disable-agent:
	./scripts/disable-agent.sh $(AGENT)
