# Devbuilds

## Setup

Create a WRLinux project. The example will be a WRL10 project:

    > git clone --branch WRLINUX_10_17_LTS --single-branch git://lxgit.wrs.com/wrlinux-x
    > ./wrlinux-x/setup.sh --machine qemux86-64 --dl-layers --accept-eula=yes

## Making local changes

The recommended method of creating local patches is to use `repo
start`. Here is an example when the repo contains a single layer:

    > ./wrlinux-x/bin/repo start devbuild layers/meta-dpdk
    > cd layers/meta-dpdk
    > git branch
      * devbuild
    > touch devbuild-test
    > git add devbuild-test
    > git commit -m "Devbuild test"

Here is an example when the repo contains multiple layers:

    > ./wrlinux-x/bin/repo start devbuild layers/meta-openembedded
    > cd layers/meta-openembedded
    > git branch
      * devbuild
    > cd meta-python
    > touch devbuild-python-test
    > cd ../meta-gnome
    > touch debuild-gnome-test
    > cd ..; git add -A
    > git commit -m "Multiple layer devbuild test"

Adding a commit without using `repo start` is also supported:

    > cd meta/virtualization
    > touch devbuild-virt-test
    > git add devbuild-virt-test
    > git commit -m "Devbuild virt test"

This is not recommended because this commit would be lost if `repo
sync` were run. The last commit will also be missed by `'repo status`.

## Starting a devbuild

The `start_devbuild.sh` script must be located on the system:

    > git clone git://ala-lxgit.wrs.com/projects/wrlinux-ci/ci-scripts.git

From the base of the WRLinux workarea, run the script:

    > <path to ci-scripts>/start_devbuild.sh

Using the above changes as a template the script will detect the
following changes:

    Found following local commits on layers/meta-dpdk:
    6b401fb40d148fb6082cfa00076692db7a0fd64c Devbuild test

    Found following local commits on layers/meta-openembedded:
    b8ef0eaf1b68687a53233320ea7c0bb4b40450f8 Multiple layer devbuild test

    Found following local commits on layers/meta-virtualization:
    a87115407636541ca415e4315c9d72e0fc0edb28 Devbuild virt test

Each repository will be forked and a branch with the commits will be
pushed to ala-lxgit.

Due to the way the layerindex works, every layer in a git repository
with multiple sublayers (like meta-openembedded) will need to be
updated. This will increase the time required for the layerindex update
stage.

## Development Tips

To trigger a devbuild using a development jenkins server with a
ci-scripts branch:

    > CI_BRANCH=mydev SERVER=<my.jenkins.org> ./start_devbuild.sh

To retrieve the admin password for Jenkins:

Start Jenkins server using `start_jenkins.sh --debug` and then on
the same server in a different console:

    > docker logs ci_jenkins_1 |& grep Admin

To change the branch of the devbuilds/devbuild and WRLinux_Build jobs
to be able to test changes to the Jenkinsfile-devbuild without logging
in:

    > .venv/bin/python3 jenkins_job_create.py --jenkins <jenkins> --job
        devbuilds/devbuild --ci_branch <new_branch>
    > .venv/bin/python3 jenkins_job_create.py --jenkins <jenkins> --job
        WRLinux_Build --ci_branch <new_branch>

It is possible that this change could be automated using the Job DSL
plugin.

## Limitations

- Currently triggers only a single build with the patches with hard
  coded build parameters
- Race condition on the shared wrlinux cache repository and the
  deletion of the mirror-index
