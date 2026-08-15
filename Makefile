.PHONY: test smoke

test:
	sh tests/run.sh

smoke:
	@if [ -z "$(HERDR_BIN)" ]; then echo "usage: make smoke HERDR_BIN=/path/to/herdr" >&2; exit 2; fi
	HERDR_BIN="$(HERDR_BIN)" sh tests/smoke-herdr-link.sh
