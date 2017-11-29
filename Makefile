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
VENV = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/.venv
DEPS = $(wildcard *.py)
GET_PIP = $(VENV)/bin/get-pip.py
PIP = $(VENV)/bin/pip3

.PHONY: build image setup clean test help

.DEFAULT_GOAL := help

help:
	@echo "Make options for jenkins ci development"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}'

# Use get-pip.py to avoid requiring installation of ensurepip package
$(VENV):
	type python3 >/dev/null 2>&1 || { echo >&2 "Python3 required. Aborting."; exit 1; }; \
	test -d $(VENV) || python3 -m venv --without-pip $(VENV); \
	touch $(VENV); \
	wget -O $(GET_PIP) https://bootstrap.pypa.io/get-pip.py; \
	$(VENV)/bin/python3 $(GET_PIP) --ignore-installed; \
	$(PIP) install pylint flake8 python-jenkins PyYAML requests;

setup: $(VENV) ## Install all python dependencies in .venv

volume_clean: ## Delete named docker volumes
	type docker >/dev/null 2>&1 && \
	{ \
		docker volume rm ci_jenkins_agent; \
		docker volume rm ci_jenkins_home; \
		docker volume rm ci_rproxy_nginx_config; \
	}

clean: volume_clean ## Delete virtualenv and all build directories
	rm -rf $(VENV)
