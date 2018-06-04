# CI Scripts

This repository contains scripts and Docker Compose files that form
the Wind River Linux Continuous Integration Prototype.

## Introduction

I have built two build systems at WindRiver, but they were very
specific to the WRLinux workflow and internal infrastructure. This is
my third build system and an attempt to make a generic build and CI
system with features around building and testing Yocto.

This repo contains the scripts to orchestrate all the components as
well as all the Dockerfile used to build the images. The images are
hosted on Docker Hub and are automated builds linked to the
Dockerfiles in this repository. All the images with links to back to
the Dockerfile used to build them can be found here:
https://hub.docker.com/r/windriver/

## Features

1) Multi-host builds using Docker Swarm. This provides an easy way to
scale the machines in a build cluster up and down and Docker Swarm
makes this surprisingly simple.

2) Developer builds. This enables build testing of patches before they
are committed to the main branches. This leverages the [WR setup][1]
program and a temporary layerindex to assemble a custom project that
matches the developer's local project.

3) Toaster integration. A simple UI to dynamically expose the Toaster
interface of all builds in progress.

## Getting Started

### Requirements:

make
python3: >= 3.3

Docker CE: >= 17.03

https://docs.docker.com/engine/installation/

Docker Compose: >= 1.13.0

https://docs.docker.com/compose/install/

### Docker Socket permissions

In order for Jenkins Agent to start docker containers without opening
the socket to every user on the machine, the host system needs to
allow a process with uid 1000 rw access to /var/run/docker.sock. This
can be done by adding uid 1000 to the docker group. Currently if the
host docker group has guid 995 to 999, this will enable access.

If the /var/run/docker.sock does not sufficient permissions, the swarm
client image will attempt to enable world rw permissions on the socket
before attempting the build.

### Single Host Setup

To start Jenkins Master and Agent on a single system using
docker-compose run:

    ./start_jenkins.sh

This will download the images from the Docker Cloud/Hub and start the
images using docker-compose.

The Jenkins web UI is accessible at https://localhost/jenkins. If
attempting to access the web UI from a different machine, replace
localhost with the name or IP of the server where the repository was
cloned to.

The Jenkins interface is behind an nginx reverse proxy which uses a
self signed certificate to provide TLS. The browser will warn you that
the web page is using a cert from an unknown CA and require you to
grant a security exception.

### Multi-Host Setup

The CI prototype supports distributing builds onto multiple machines
using Docker Swarm.

    ./start_jenkins.sh --swarm

The machine where the `start_jenkins.sh` script is run must be a
Docker swarm manager node. It will be labeled the "master" node and
no builds will be scheduled on this node.

Using Docker Swarm requires some manual setup on each machine that
will be part of the cluster. Each node needs Docker 17.03+
installed. On the node that will be master run:

    docker swarm init

and note the provided command line with join token. On the worker nodes
run the provided command which will have the following form:

    docker swarm join --token <token> <manager_IP>:2377

Limitations:

1. Each worker node will start one Jenkins worker with 2
   executors. I will investigate using Docker labels to set Jenkins
   Node labels to control number of executors and job scheduling
   control.
2. No scaling tests have been performed, although I expect this setup
   to work well for a 2-10 machine cluster.

For more information on managing a Docker Swarm, consult
the [Docker Swarm Documentation][2]

[2]: https://docs.docker.com/engine/swarm/


## Scheduling Jobs

By default the Jenkins Master does not have authentication enabled and
jobs can be submitted from any machine. On the same or a different
machine, clone this repository. To install the python-jenkins package
locally and submit a job run:

    make setup
    .venv/bin/python3 ./jenkins_job_submit.py \
        --jenkins <jenkins> --configs <config name from combos> \
        --build_configs_file configs/WRLinux9/combos-WRLINUX_9_BASE.yaml

This will install all the python libraries into .venv and contact
the Jenkins Master and schedule a build on the Jenkins Agent. The
<config name from combos> is a comma separated list of names from the
yaml file. As examples the combos-WRLINUX_9_BASE.yaml contains names
such as qemuarm_glibc-small_Base and qemux86-64_glibc-core_Base.

The combos-WRLINUX_9_BASE.yaml file is a generated list of valid
combinations of qemu bsps and configuration options. At WindRiver we
generate these yaml files using the machines and images listed in the
LayerIndex.

### Scheduling Poky Builds

An example config is provided to demonstrate building Poky locally:

    .venv/bin/python3 ./jenkins_job_submit.py --jenkins <jenkins> \
       --build_configs_file configs/OpenEmbedded/combos-pyro.yaml \
       --configs=pyro-minimal

To reuse the ubuntu1604_64 image, the poky build uses the WRLinux
buildtools from Github.

### Toaster Integration

All builds enable toaster by default and the prototype uses
Registrator and Consul to discover toaster instances. The toaster
aggregator webapp provides an overview of running toaster instances
and the current progress of each as well as links to the individual
toaster instances.

The toaster aggregator web UI is available at
https://localhost/toaster_aggregator

### Post build operations

The conventional way to add post build operations on Jenkins Pipeline
projects is to add stages to the pipeline. Each pipeline stage would
also require more build parameters be added to the job
configuration. Each additional post build step would require
significant changes and would not compose well.

The post build operations can be run in a different container than the
build to avoid having to add tools like rsync to the build
container. This also allows the build to run without network
access. To select a different post build image:

    .venv/bin/python3 ./jenkins_job_submit.py \
        --jenkins <jenkins> --postprocess_image <image>

The prototype contains a generic post build step that does not require
modifications to job config or Jenkinsfile. The post build scripts are
located in the scripts directory and can be selected to run using the
command line:

    .venv/bin/python3 ./jenkins_job_submit.py \
        --jenkins <jenkins> --post_success=rsync,cleanup \
        --post_fail=send_email,cleanup,report

This would run the scripts/rsync.sh and scripts/cleanup.sh scripts
after a successful build and scripts/send_email.sh, scripts/cleanup.sh
and scripts/report.sh after a failed build.

To pass parameters to the post build scripts use:

    .venv/bin/python3 ./jenkins_job_submit.py \
        --jenkins <jenkins> --postprocess_args FOO1=bar,FOO2=baz

The prototype will take the parameters, split them and inject them
into the postbuild environment.

To add post build steps, add a script to the scripts directory and add
the script name to the --post_success and/or --post_fail and add any
required parameters to --postprocess_args.

## Developer Builds

An ideal Continuous Integration workflow supports the testing of
patches before they are committed to the "trunk" branches. Also known
as pre-merge testing or pull request testing. The standard git
workflow is to use topic branches and have the CI system run tests
against the topic branch.

Yocto projects contain a hierarchy of git repositories and there isn't
a standardized way to create a project area. The wr-lx-setup [1]
attempts to standardize creation of Yocto projects using the
Layerindex as a source of available layers and locations. This
simplifies and standardizes the setup of Yocto projects, but it adds
the Layerindex as a component required by the CI workflow.

The prototype supports creation of a temporary per build Layerindex
and modifying the attributes of a layer in the temporary
Layerindex. This enables a developer to create a topic branch on a
layer git repository and run builds and tests using this branch.

An example workflow:

    .venv/bin/python3 ./jenkins_job_submit.py \
        --jenkins <jenkins> --configs master-minimal \
        --devbuild_layer_name openembedded-core \
        --build_configs_file configs/OpenEmbedded/combos-master.yaml \
        --configs master-minimal --devbuild_layer_name openembedded-core \
        --devbuild_layer_vcs_url git://github.com/kscherer/openembedded-core.git \
        --devbuild_actual_branch devbuild

The sequence of events is:

1. Temporary Layerindex is created and retrieves master branch info
   from official layers.openembedded.org Layerindex.
2. The vcs_url and actual_branch for the openembedded-core layer in
   temp layerindex is changed and the temp layerindex runs update.py
   to parse this layer. If the update fails, the build also
   fails. This provides a mechanism to test the addition of new
   layers.
3. The wr-lx-setup.sh program is run using the temp layerindex as its
   source and creates a build area using the openembedded layer as
   defined in the supplied vcs_url.
4. After setup is complete, the normal build process continues.
5. After build is complete, the temp layerindex is shutdown and
   cleaned up.

Current Limitations:

1. The Layerindex assumes that bitbake and openembedded-core
   repositories are located on the same git server at the same path.
2. Only changing a single layer is currently supported. There is no
   technical reason why multiple layers could not be changed.
3. Only tested with http://layers.openembedded.org

[1]: https://github.com/Wind-River/wr-lx-setup

## Rsync server

To support collection of build artifact results from a build cluster,
an rsync server has been integrated. The runs beside the reverse proxy
service and accepts files without authentication. The postbuild image
now runs in the same network as the rsync server and can use the
postbuild rsync script to copy files to this server or any external
server.

The contents of the rsync server are available over HTTPS through the
reverse proxy at `https://<jenkins>/builds`

## Using Jenkins Credential Store to access Git server

Jenkins has an encrypted credential store which can manage credentials
used to access the git server. Connect to Jenkins and select
Credentials in the left menu. Then select System -> "Global
(unrestricted)" -> Add Credentials. Use ID "git" which is the default
used by jenkins_job_submit.py.

    .venv/bin/python3 ./jenkins_job_submit.py \
        --jenkins <jenkins> --configs <config name from combos> \
        --build_configs_file configs/WRLinux9/combos-WRLINUX_9_BASE.yaml \
        --git_credential=enable

## Scheduling Jobs when Jenkins requires Authentication

The jenkins_job_submit.py can submit jobs to the Jenkins master that
requires Authentication. If unauthenticated access fails,
jenkins_job_submit.py check for a local file containing the
authentication credentials. The default name of the local auth file is
jenkins_auth.txt at the root path of this CI script. To use a
different file name use the command line option
`--jenkins-auth=FILE_NAME`. Format of the local auth file
should be `USERNAME:API_TOKEN`, and only one line of text is allowed.

The windriver/jenkins-master image requires authentication and has a
special mechanism to retrieve this information transparently. If
authentication to a different Jenkins server fails, contact the
manager of Jenkins server and put the valid authentication in local
auth file to submit jobs.

    .venv/bin/python3 ./jenkins_job_submit.py \
        --jenkins <jenkins> --configs <config name from combos> \
        --build_configs_file configs/WRLinux9/combos-WRLINUX_9_BASE.yaml \
        --jenkins_auth <path to file>

## Runtime tests

Runtime tests are supported using LAVA, which is a server running
outside of CI scripts. The LAVA server configuration is set in
config files which locates in configs folder.

To enable runtime tests, the following settings in the YAML config
file under configs folder are required:

```yaml
  post_build:
    post_process_image: postbuild
    postprocess_args:
      RSYNC_SERVER: yow-lpdtest.wrs.com
      RSYNC_DEST_DIR: builds/wrlinux10
      HTTP_ROOT: http://yow-lpdtest.wrs.com/tftpboot
      REPORT_SERVER: http://yow-lpdtest.wrs.com:9200
      SMTPSERVER: prod-webmail.windriver.com
      EMAIL: first.last@windriver.com
    post_success:
      - rsync
      - cleanup
    post_fail:
      - rsync
      - cleanup
      - send_mail
      - report

  test_config:
	test: [disable (default) or test_suite_name]
    test_image: postbuild
    test_args:
      LAVA_SERVER: <lava_server_link>
      LAVA_USER: <lava_username>
      NFS_ROOT: /net/yow-lpdtest/var/lib/tftpboot
      TEST_DEVICE: [simics (default) or hardware]
      RETRY: 1
```

### Test Suites
In above YAML config file, **test** under **test_config** section is used to set which test suite
will be used for runtime test.

_Supported Runtime Tests_

| Product      | Supported Test Suite            | Supported  Device  |
|--------------|---------------------------------|--------------------|
| WRLinux 9    | oeqa-default-test (default)     | simics or hardware |
| WRLinux 10   | oeqa-default-test (default)     | simics or hardware |
| WRLinux 10   | linaro-smoke-test               | simics or hardware |
| WRLinux 10   | linaro-busybox-test             | simics or hardware |
| WRLinux 10   | linaro-signal-test              | simics or hardware |
| WRLinux 10   | linaro-singlenode-advanced-test | simics or hardware |
| WRLinux 10   | linaro-pi-stress-test           | hardware           |
| WRLinux 10   | linaro-pmq-test                 | hardware           |

Configurations for each test suite are set in test_configs.yaml under configs folder. 
Here is and example:

```yaml
- name: oeqa-default-test
  prebuild_cmd_for_test:
  - test_configure.py
  build_options:
  - INHERIT += "testexport"
  - IMAGE_INSTALL_append += "python3-pkgutil"
  - IMAGE_INSTALL_append += "python3-unittest"
  - IMAGE_INSTALL_append += "python3-multiprocessing"
  - TEST_TARGET_IP = "localhost"
  - TEST_SERVER_IP = "localhost"
  - TEST_SUITES = "ping ssh df connman syslog xorg scp vnc date pam perl python rpm ldd smart dmesg dash"
  lava_test_repo: git://ala-lxgit.wrs.com/lpd-ops/lava-test.git
  simics:
    job_template: lava-test/jobs/templates/wrlinux-10/x86_simics_job_oeqa-default-test_template.yaml
    timeout: 420
  hardware:
    job_template: lava-test/jobs/templates/wrlinux-10/x86_64_job_oeqa-default-test_template.yaml
    timeout: 480
```

## Modifying docker images

The CI prototype uses the following images:

- windriver/jenkins-master
- windriver/jenkins-swarm-client
- windriver/ubuntu1604_64
- windriver/toaster_aggregator
- blacklabelops/nginx
- gliderlabs/registrator
- consul
- windriver/layerindex

To test image modifications rebuild the container locally and run:

    ./start_jenkins.sh --no-pull

## TODO

- Build notifications
- Simplify settings of runtime tests
- Select a good project name

## Contributing

Contributions submitted must be signed off under the terms of the Linux
Foundation Developer's Certificate of Origin version 1.1. Please refer to:
   https://developercertificate.org

To submit a patch:

- Open a Pull Request on the GitHub project
- Optionally create a GitHub Issue describing the issue addressed by the patch

# Docker Images

This repository contains only the Dockerfiles used to generate the
images. The images are assembled and hosted by Docker on the Docker
Cloud/Hub.

The images contain Open Source software as distributed by the
following projects.

- Ubuntu Linux: https://www.ubuntu.com/
- Alpine Linux: https://www.alpinelinux.org/
- Jenkins: https://jenkins.io/
- Jenkins Plugins: https://plugins.jenkins.io/
- Docker: https://www.docker.com/

# Included Third Party Components

## MIT License

- jQuery Compat JavaScript Library v3.0.0-pre 81b6e46522d8c680f6c38d5e95c732b2b47130b9
- Skeleton V2.0.4
- DataTables 1.10.13

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
