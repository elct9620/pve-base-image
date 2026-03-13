.PHONY: version release

DATE := $(shell date +%Y.%m.%d)
LAST_SEQ := $(shell git tag -l "v$(DATE).*" | sed 's/.*\.//' | sort -n | tail -1)
NEXT_SEQ := $(if $(LAST_SEQ),$(shell echo $$(( $(LAST_SEQ) + 1 ))),1)
VERSION := v$(DATE).$(NEXT_SEQ)

version:
	@echo $(VERSION)

release:
	git tag $(VERSION)
	git push origin $(VERSION)
