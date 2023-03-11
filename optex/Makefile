BUILD_DIR     := ./build
BASE_FILES    := $(wildcard base/*)
OTHER_FILES    := $(wildcard demo/*) $(wildcard doc/*) $(wildcard pkg/*) README
PDF_FILES = \
	$(BUILD_DIR)/doc/optex-doc.pdf \
	$(BUILD_DIR)/demo/op-demo.pdf \
	$(BUILD_DIR)/demo/op-slides.pdf \
	$(BUILD_DIR)/demo/op-letter-en.pdf \
	$(BUILD_DIR)/demo/op-letter-cs.pdf \
	$(BUILD_DIR)/demo/op-mathalign.pdf \
	$(BUILD_DIR)/pkg/optex-math-doc.pdf

.PHONY: clean dist test all help pdf format
help:
	@echo "Targets are"
	@echo " format    Create fmt file"
	@echo " pdf|test  Create PDF files (typeset documentation and demos)"
	@echo " all       Create fmt and PDF files"
	@echo " dist      Create ZIP distribution"
	@echo " clean     Cleanup"
format: $(BUILD_DIR)/texmf/web2c/luatex/optex.fmt
test: pdf
dist: $(BUILD_DIR)/optex.zip
all: format pdf
pdf: $(PDF_FILES)
dist: $(BUILD_DIR)/optex.zip

clean:
	rm -rf $(BUILD_DIR)

$(BUILD_DIR)/texmf/web2c/luatex/optex.fmt: $(BASE_FILES)
	mkdir -p $(BUILD_DIR)/doc $(BUILD_DIR)/demo $(BUILD_DIR)/pkg $(BUILD_DIR)/texmf/web2c/luatex $(BUILD_DIR)/texmf/tex/optex
	cp -r base pkg doc $(BUILD_DIR)/texmf/tex/optex/
	cd $(BUILD_DIR)/texmf/tex/optex/base && luatex -ini optex.ini
	cp $(BUILD_DIR)/texmf/tex/optex/base/optex.fmt $(BUILD_DIR)/texmf/web2c/luatex/optex.fmt

$(BUILD_DIR)/run-optex.sh: $(BUILD_DIR)/texmf/web2c/luatex/optex.fmt
	@echo '#!/bin/sh' > $(BUILD_DIR)/run-optex.sh
	@echo 'set -e' >> $(BUILD_DIR)/run-optex.sh
	@echo 'set -x' >> $(BUILD_DIR)/run-optex.sh
	@echo 'export TEXMFHOME='$(shell realpath $(BUILD_DIR) )/texmf >> $(BUILD_DIR)/run-optex.sh
	@echo 'cd $$1' >> $(BUILD_DIR)/run-optex.sh
	@echo 'for i in 1 2 3 4 ; do' >> $(BUILD_DIR)/run-optex.sh
	@echo 'luatex --halt-on-error --interaction=batchmode -fmt=optex --jobname=$$2 $$3' >> $(BUILD_DIR)/run-optex.sh
	@echo 'done' >> $(BUILD_DIR)/run-optex.sh
	chmod +x $(BUILD_DIR)/run-optex.sh

$(BUILD_DIR)/doc/optex-doc.pdf: doc/optex-doc.tex doc/optex-techdoc.tex doc/optex-userdoc.tex $(BUILD_DIR)/run-optex.sh
	cp $(^) $(@D)
	$(BUILD_DIR)/run-optex.sh $(@D) $(basename $(<F) .tex) $(<F)

$(BUILD_DIR)/doc/%.pdf: doc/%.tex $(BUILD_DIR)/run-optex.sh
	cp $(^) $(@D)
	$(BUILD_DIR)/run-optex.sh $(@D) $(basename $(<F) .tex) $(<F)

$(BUILD_DIR)/demo/%.pdf: demo/%.tex $(BUILD_DIR)/run-optex.sh
	cp $(^) $(@D)
	$(BUILD_DIR)/run-optex.sh $(@D) $(basename $(<F) .tex) $(<F)

$(BUILD_DIR)/pkg/optex-math-doc.pdf: pkg/math.opm $(BUILD_DIR)/run-optex.sh
	cp $(^) $(@D)
	$(BUILD_DIR)/run-optex.sh $(@D) $(basename $(@F) .pdf) '\docgen $(basename $(<F))'

$(BUILD_DIR)/optex.zip: $(BASE_FILES) $(PDF_FILES) $(OTHER_FILES)
	rm -rf $(BUILD_DIR)/optex.zip $(BUILD_DIR)/dist
	mkdir -p $(BUILD_DIR)/dist/optex
	cp -r base demo doc pkg README $(BUILD_DIR)/dist/optex
	cp $(BUILD_DIR)/doc/*.pdf  $(BUILD_DIR)/dist/optex/doc
	# We could also copy package documentation into the distribution
	# if we want:
	# # cp $(BUILD_DIR)/pkg/*.pdf $(BUILD_DIR)/dist/optex/doc
	cd $(BUILD_DIR)/dist && zip -9 -r ../optex.zip .
	ls -lh $(BUILD_DIR)/optex.zip
