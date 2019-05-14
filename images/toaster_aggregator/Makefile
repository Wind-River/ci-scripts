# Copyright (c) 2017 Wind River Systems Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

SHELL = /bin/bash #requires bash
VENV = $(PWD)/.venv
DEPS = $(wildcard *.py)
GET_PIP = $(VENV)/bin/get-pip.py
PIP = $(VENV)/bin/pip3
PEX = $(VENV)/bin/pex

.PHONY: build image toaster_aggregator setup clean test help

.DEFAULT_GOAL := help

help:
	@echo "Make options for jenkins ci development"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}'

toaster_aggregator: ## Use multi-stage docker build to build pex and final toaster aggregator image
ifndef TAG
	$(eval TAG=latest)
endif
ifndef REGISTRY
	$(eval REGISTRY=windriver)
endif
	docker pull alpine:3.9 # bug in multi-stage does not allow docker build --pull
	docker build --rm=true -t $(REGISTRY)/$@:$(TAG) -f Dockerfile .

dist/toaster_aggregator: $(DEPS) $(VENV)
	rm -f $(PWD)/.pex/build/toaster*; \
	export PEX_ROOT=$(PWD)/.pex; \
	$(VENV)/bin/python setup.py bdist_pex --bdist-all --pex-args="-v --pex-root=$(PWD)/.pex"

# Use get-pip.py to avoid requiring installation of ensurepip package
$(VENV):
	type python3 >/dev/null 2>&1 || { echo >&2 "Python3 required. Aborting."; exit 1; }; \
	test -d $(VENV) || python3 -m venv --without-pip $(VENV); \
	touch $(VENV); \
	wget -O $(GET_PIP) https://bootstrap.pypa.io/get-pip.py; \
	$(VENV)/bin/python3 $(GET_PIP) --ignore-installed; \
	$(PIP) install pylint flake8 pex; \
	touch $(PEX); \
	$(VENV)/bin/python3 setup.py develop;

setup: $(VENV) ## Install all python dependencies in .venv

dev: $(DEPS) $(VENV) ## Run a local development version of the app
	$(VENV)/bin/gunicorn --paste development.ini

clean: ## Delete virtualenv and all build directories
	rm -rf $(VENV) *.egg-info build dist .pex
