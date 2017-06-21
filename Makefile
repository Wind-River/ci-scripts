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
VENV_NAME = jenkins_env
VENV = $(HOME)/.virtualenvs/$(VENV_NAME)
DEPS = $(wildcard *.py)
PIP = $(HOME)/.local/bin/pip3
VIRTUALENV = $(HOME)/.local/bin/virtualenv
VENVWRAPPER = $(HOME)/.local/bin/virtualenvwrapper.sh

.PHONY: build image setup clean test help

.DEFAULT_GOAL := build

help:
	@echo "Make options for jenkins ci development"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}'

$(VENV): $(VIRTUALENV) $(VENVWRAPPER)
	export VIRTUALENVWRAPPER_VIRTUALENV=$(VIRTUALENV); \
	export VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3; \
	source $(VENVWRAPPER); \
	test -d $(VENV) || mkvirtualenv -p python3 $(VENV_NAME); \
	touch $(VENV); \
	$(VENV)/bin/pip3 install pylint nose flake8; \
	touch $(PEX); \
	$(VENV)/bin/pip3 install python-jenkins PyYAML;

setup: $(VENV) ## Install all python dependencies in jenkins_env virtualenv.

$(PIP):
	wget -O /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py; \
	python3 /tmp/get-pip.py --user; \
	rm -f /tmp/get-pip.py

$(VIRTUALENV): $(PIP)
	$(PIP) install --user --upgrade virtualenv

$(VENVWRAPPER): $(PIP)
	$(PIP) install --user --upgrade virtualenvwrapper

clean: ## Delete virtualenv and all build directories
	rm -rf $(VENV) build dist .check .tmp

test: ## Run tests
	$(VENV)/bin/python setup.py test
