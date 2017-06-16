# CI Scripts

This repository contains scripts and Docker Compose files that form
the Wind River Linux Continuous Integration Prototype.

## Introduction

The prototype has four components:

1) Jenkins Master Docker image
2) Jenkins Agent Docker image with Swarm plugin
3) Ubuntu 16.04 image with all required host packages necessary to
build Yocto.
4) This repo with scripts to orchestrate all the components.

## Getting Started

### Requirements:

docker-engine: >= 17.03
docker-compose: >= 1.13.0

In order for Jenkins Agent to start docker containers, the host system
needs to allow a process with uid 1000 rw access to
/var/run/docker.sock. This can be done by adding uid 1000 to the
docker group. Currently if the host docker group has guid 995 to 999,
this will enable access.

If the host docker group does not have guid in this range it
will be necessary to run:

    sudo chmod 666 /var/run/docker.sock

To enable access.

### Starting Jenkins

To start Jenkins Master and Agent on a single system using
docker-compose run:

    ./start-jenkins.sh

This will download the images from the Docker Cloud/Hub and start the
images using docker-compose

### Scheduling Builds

On the same or a different machine, clone this repository. To install
the python-jenkins package locally run:

    make setup
    workon jenkins_env
    ./oe_jenkins_build.py \
        --jenkins https://<jenkins> --configs_file combos-WRLINUX_9_BASE.yaml \
        --configs <config name from combos>

This will contact the Jenkins Master and schedule a build on the
Jenkins Agent.

## Contributing

Contributions submitted must be signed off under the terms of the Linux
Foundation Developer's Certificate of Origin version 1.1. Please refer to:
   https://developercertificate.org

To submit a patch:

- Open a Pull Request on the GitHub project
- Optionally create a GitHub Issue describing the issue addressed by the patch


# License

MIT License

Copyright (c) 2017 Wind River Systems Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
