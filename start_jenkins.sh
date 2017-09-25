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
export ARTIFACTORY_IMAGE=docker.bintray.io/jfrog/artifactory-oss
export ARTIFACTORY_TAG=5.4.6
export CONSUL_TAG=0.9.0
# Default to using Docker Hub
export REGISTRY=windriver

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

  --builder-tag: Set the tag for the ubuntu1604_64 builder image
    Defaults to latest

  --consul-tag: Set the tag for the consul image
    Defaults to 0.9.0

  --postbuild-tag: Set the tag for the postbuild image
    Defaults to latest

  --with-artifactory: Enable an instance of artifactory inside the CI system

  --artifactory-image: Set the image name for the artifactory image used.
    Defaults to $ARTIFACTORY_IMAGE

  --artifactory-tag: Set the tag for the artifactory image.
    Defaults to $ARTIFACTORY_TAG

  --registry: Set the location of the CI docker images.
    Defaults to windriver organization on Docker Hub/Cloud.

  --no-pull: Do not attempt to pull images from Registry. Useful when testing
     new versions of the images.
EOF
    exit 1
}

CLEANUP=1
PULL_IMAGES=1
ARTIFACTORY=0

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
        --with-artifactory)  ARTIFACTORY=1; shift 1;;
        --artifactory-image=*) ARTIFACTORY_IMAGE="${1#*=}"; shift 1;;
        --artifactory-tag=*)   ARTIFACTORY_TAG="${1#*=}"; shift 1;;
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

command -v docker-compose >/dev/null 2>&1 || { echo >&2 "Docker-compose is not installed. https://docs.docker.com/compose/install/  Aborting."; exit 1; }

DCOMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f 3 | tr -d ',')
vercomp '1.12.0' "$DCOMPOSE_VERSION"
if [ $? != '2' ]; then
    echo >&2 "Require docker-compose version 1.13.0 or later. Aborting"
    exit 1
fi

echo "Docker Compose is present and is version $DCOMPOSE_VERSION"

echo "Using registry $REGISTRY."

if [ "$PULL_IMAGES" == '1' ]; then
    echo "Pull latest docker images from Docker Hub"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/jenkins-master:${JENKINS_MASTER_TAG}"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/jenkins-swarm-client:${JENKINS_MASTER_TAG}"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/ubuntu1604_64:${BUILDER_TAG}"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/postbuild:${POSTBUILD_TAG}"
    ${DOCKER_CMD[*]} pull "${REGISTRY}/toaster_aggregator:${TOASTER_TAG}"
    ${DOCKER_CMD[*]} pull "consul:${CONSUL_TAG}"
    ${DOCKER_CMD[*]} pull "blacklabelops/nginx:${RPROXY_TAG}"
    ${DOCKER_CMD[*]} pull gliderlabs/registrator:latest
    if [ "$ARTIFACTORY" == "1" ]; then
        ${DOCKER_CMD[*]} pull "${ARTIFACTORY_IMAGE}:${ARTIFACTORY_TAG}"
    fi
fi

get_primary_ip_address() {
    # show which device internet connection would use and extract ip of that device
    ip=$(ip -4 route get 8.8.8.8 | awk 'NR==1 {print $NF}')
    echo "$ip"
}

export HOST="$HOSTNAME"
export HOSTIP=
HOSTIP=$(get_primary_ip_address)

# require a $HOSTNAME with a proper DNS entry
host "$HOSTNAME" > /dev/null 2>&1
if [ $? != 0 ]; then
    echo "The hostname for this system is not in DNS. Attempting ip address fallback"
    export HOST=$HOSTIP
fi

if [ "$ARTIFACTORY" == "1" ]; then
    FILES=("${FILES[@]}" --file artifactory.yaml)
fi

echo "Jenkins Master UI will be available at https://$HOSTIP"
echo "Starting CI with: docker-compose ${FILES[*]} up"

sleep 1
docker-compose "${FILES[@]}" up --abort-on-container-exit

if [ "$CLEANUP" == '1' ]; then
    echo "Cleaning up stopped containers"
    docker-compose "${FILES[@]}" rm --force -v
fi
