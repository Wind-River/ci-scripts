#!/bin/bash

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

set -uo pipefail

# taken from http://stackoverflow.com/questions/4023830/bash-how-compare-two-strings-in-version-format
function vercomp {
    if [[ "$1" == "$2" ]]; then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

export JENKINS_MASTER_TAG=latest
export JENKINS_AGENT_TAG=latest
export RPROXY_TAG=latest
export BUILDER_TAG=latest
export TOASTER_TAG=latest
export POSTBUILD_TAG=latest
export CONSUL_TAG=1.2.0
# Default to using Docker Hub
export REGISTRY=windriver
export JENKINS_MASTER_NUM_EXECUTORS=0
export JENKINS_AGENT_NUM_EXECUTORS=2
export JENKINS_INIT_DEBUG="false"

usage() {
    cat <<EOF
Usage $0 [--registry] [--file] [--rm] [--with-lava]
  --registry=(ala|yow|pek)-lpdfs01: Docker registry to download images from.
     Will attempt to locate closest registry if not provided.

  --file <compose yaml>: Extra compose yaml file(s) to extend wrl-ci.yaml
     Accepts multiple --file parameters

  --rm: Delete containers and volumes when script exits

  --no-rm: Do not delete containers and unnamed volumes when script exits

  --jenkins-master-tag: Set the tag for the jenkins-master image
    Defaults to latest

  --jenkins-agent-tag: Set the tag for the jenkins-swarm-client image.
    Defaults to latest

  --jenkins-agent-num-executors: Number of executors to run on each Jenkins Agent.
    Default: 2

  --jenkins-master-num-executors: Number of executors to run on the Jenkins Master.
    Default: 0

  --builder-tag: Set the tag for the ubuntu1604_64 builder image
    Defaults to latest

  --consul-tag: Set the tag for the consul image
    Defaults to 0.9.3

  --postbuild-tag: Set the tag for the postbuild image
    Defaults to latest

  --registry: Set the location of the CI docker images.
    Defaults to windriver organization on Docker Hub/Cloud.

  --no-pull: Do not attempt to pull images from Registry. Useful when testing
     new versions of the images.

  --debug: Enable debugging output
EOF
    exit 1
}

CLEANUP=1
PULL_IMAGES=1
SWARM=0

declare -a FILES
FILES=(--file wrl-ci.yaml)

while [ "$#" -gt 0 ]; do
    case "$1" in
        --registry=*)     REGISTRY="${1#*=}"; shift 1;;
        --registry)       REGISTRY="$2"; shift 2;;
        --file)           FILES=("${FILES[@]}" --file $2); shift 2;;
        --rm)             CLEANUP=1; shift 1;;
        --no-rm)          CLEANUP=0; shift 1;;
        --jenkins-master-tag=*) JENKINS_MASTER_TAG="${1#*=}"; shift 1;;
        --jenkins-agent-tag=*)  JENKINS_AGENT_TAG="${1#*=}"; shift 1;;
        --builder-tag=*)  BUILDER_TAG="${1#*=}"; shift 1;;
        --toaster-tag=*)  TOASTER_TAG="${1#*=}"; shift 1;;
        --postbuild-tag=*) POSTBUILD_TAG="${1#*=}"; shift 1;;
        --consul-tag=*)   CONSUL_TAG="${1#*=}"; shift 1;;
        --no-pull)        PULL_IMAGES=0; shift 1;;
        --swarm)          SWARM=1; shift 1;;
        --debug)          JENKINS_INIT_DEBUG="true"; shift 1;;
        --jenkins-agent-num-executors=*)  JENKINS_AGENT_NUM_EXECUTORS="${1#*=}"; shift 1;;
        --jenkins-master-num-executors=*) JENKINS_MASTER_NUM_EXECUTORS="${1#*=}"; shift 1;;
        *)            usage ;;
    esac
done

command -v docker >/dev/null 2>&1 || { echo >&2 "Docker is not installed. https://docs.docker.com/install/  Aborting."; exit 1; }

DOCKER_VERSION=$(docker --version | cut -d' ' -f 3)
vercomp '17.03.0' "$DOCKER_VERSION"
if [ $? != '2' ]; then
    echo >&2 "Require docker version 17.03.0 or later. Aborting"
    exit 1
fi

DOCKER_CMD="docker"
if groups | grep -vq docker; then
    echo "This user is not in the docker group. Will attempt to run docker info using sudo."
    DOCKER_CMD=(sudo docker)
fi

${DOCKER_CMD[*]} info > /dev/null 2>&1
if [ $? != 0 ]; then
    echo >&2 "Unable to run '${DOCKER_CMD[*]}'. Either give the user sudo access to run docker or add it to the docker group. Aborting."
    exit 1
fi

echo 'Successfully ran docker info'

if [ "$SWARM" != "1" ]; then
    command -v docker-compose >/dev/null 2>&1 || { echo >&2 "Docker-compose is not installed. https://docs.docker.com/compose/install/  Aborting."; exit 1; }

    DCOMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f 3 | tr -d ',')
    vercomp '1.12.0' "$DCOMPOSE_VERSION"
    if [ $? != '2' ]; then
        echo >&2 "Require docker-compose version 1.13.0 or later. Aborting"
        exit 1
    fi

    echo "Docker Compose is present and is version $DCOMPOSE_VERSION"
fi

echo "Using registry $REGISTRY."

if [ "$PULL_IMAGES" == '1' ]; then
    echo "Pull latest docker images from Docker Hub"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/jenkins-master:${JENKINS_MASTER_TAG}"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/jenkins-swarm-client:${JENKINS_AGENT_TAG}"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/ubuntu1604_64:${BUILDER_TAG}"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/postbuild:${POSTBUILD_TAG}"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/toaster_aggregator:${TOASTER_TAG}"
    ${DOCKER_CMD[*]} pull "consul:${CONSUL_TAG}"
    ${DOCKER_CMD[*]} pull "blacklabelops/nginx:${RPROXY_TAG}"
    ${DOCKER_CMD[*]} pull gliderlabs/registrator:latest
fi

get_primary_ip_address() {
    # show which device internet connection would use and extract ip of that device
    ip=$(ip -4 route get 8.8.8.8 | awk 'NR==1 {print $NF}')
    echo "$ip"
}

export HOST=$(hostname -f)
export HOSTIP=
HOSTIP=$(get_primary_ip_address)

# require a $HOSTNAME with a proper DNS entry
host "$HOSTNAME" > /dev/null 2>&1
if [ $? != 0 ]; then
    echo "The hostname for this system is not in DNS. Attempting ip address fallback"
    export HOST=$HOSTIP
fi

docker inspect rsync_net &> /dev/null
if [ $? == 0 ]; then
    echo "Removing rsync_net which was not properly cleaned up"
    docker network remove rsync_net &> /dev/null
fi

docker inspect ci_net &> /dev/null
if [ $? == 0 ]; then
    echo "Removing ci_net which was not properly cleaned up"
    docker network remove ci_net &> /dev/null
fi

sleep 1

function docker_stack_cleanup {
    echo "Removing ci stack"
    docker stack remove ci

    echo "Waiting for services to be removed before final cleanup"
    for i in {5..1};do echo -n "$i." && sleep 1; done; echo
    docker network remove rsync_net &> /dev/null
    docker node update --label-rm type "$HOSTNAME" &> /dev/null
    echo "Cleanup complete"
    exit 0
}

function random_char
{
    local VALID_CHARS=abcdefghijklmnopqrstuvwxyz0123456789
    local RANDOM_INDEX=$(( RANDOM % ${#VALID_CHARS} ))
    echo -n ${VALID_CHARS:$RANDOM_INDEX:1}
}

function random_char_seq
{
    local char_seq=
    for arg in $(seq 1 "$1"); do
        char_seq="$char_seq$(random_char)"
    done
    echo -n "$char_seq"
}

echo "Jenkins Master UI will be available at https://$HOSTIP"
if [ "$SWARM" == "0" ]; then
    export JENKINS_AGENT_PASSWORD="$(random_char_seq 10)"

    echo "Creating rsync network"
    docker network create --attachable --driver bridge rsync_net

    # match the docker stack volume and network prefix
    export COMPOSE_PROJECT_NAME=ci
    export NETWORK_TYPE=bridge
    echo "Starting CI with: docker-compose ${FILES[*]} up"
    docker-compose "${FILES[@]}" up --abort-on-container-exit

    if [ "$CLEANUP" == '1' ]; then
        echo "Cleaning up stopped containers"
        docker-compose "${FILES[@]}" rm --force -v
    fi
    docker network remove ci_net
    docker network remove rsync_net
else
    export NETWORK_TYPE=overlay

    if ! docker node ls &> /dev/null; then
        echo "This Docker engine is not in swarm mode or is not a swarm manager."
        echo "This script requires that the host be a Docker Swarm manager."
        echo 'Use "docker swarm init" or "docker swarm join" to connect this node to swarm and try again.'
        exit 1
    fi

    NUM_NODES=$(docker node ls -q | wc -l)
    if [ "$NUM_NODES" -le "1" ]; then
        echo "WARNING: No worker nodes detected. No builds will be scheduled until worker nodes join the swarm cluster"
    fi

    docker secret rm agent_password &> /dev/null
    random_char_seq 10 | docker secret create agent_password -

    echo "Using Docker Swarm with the following nodes"
    docker node ls

    echo "Marking this node as master node"
    docker node update --label-add type=master "$HOSTNAME"

    echo "Creating rsync network"
    docker network create --attachable --driver overlay rsync_net

    docker stack deploy --compose-file wrl-ci.yaml ci

    trap docker_stack_cleanup EXIT

    echo
    echo "CI Stack started. Waiting for Ctrl-C"
    sleep infinity
fi
exit 0
