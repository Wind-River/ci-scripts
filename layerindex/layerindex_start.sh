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

# This script is used to setup a temp layerindex and populate it with data from
# another layerindex or cached mirror-index
#
# To populate it with entries from a running layerindex like layers.openembedded.org:
#
# ./layerindex_start.sh --type=restapi-web --branch=master \
#          --source=https://layers.openembedded.org/layerindex/api/
#
# To populate it with a cached mirror-index:
#
# ./layerindex_start.sh --type=restapi-files --branch=WRLINUX_9_BASE \
#    --base_url=https://github.com/WindRiver-Labs/ \
#    --source=https://github.com/WindRiver-Labs/mirror-index.git

set -e

COMPOSE_PROJECT_NAME=${PWD##*/}
if [ -n "$BUILD_ID" ]; then
    export COMPOSE_PROJECT_NAME="build$BUILD_ID"
fi

BASE_URL=https://github.com/WindRiver-Labs
OUTPUT=/opt/layerindex

if [ -z "$LAYERINDEX_SOURCE" ]; then
    SOURCE=https://layers.openembedded.org/layerindex/api/
else
    SOURCE="$LAYERINDEX_SOURCE"
fi

if [ -z "$BRANCH" ]; then
    BRANCH=WRLINUX_9_BASE
fi

if [ -z "$REMOTE" ]; then
    REMOTE=https://github.com/WindRiver-Labs/wrlinux-9
fi

echo "Command: $0"
for i in "$@"
do
    echo "Arg: $i"
    case $i in
        --type=*)   TYPE=${i#*=} ;;
        --branch=*) BRANCH=${i#*=} ;;
        --output=*) OUTPUT=${i#*=} ;;
        --source=*) SOURCE=${i#*=} ;;
        --remote=*) REMOTE=${i#*=} ;;
        --base_url=*) BASE_URL=${i#*=} ;;
        *)          ;;
    esac
    shift
done

if [ -z "$TYPE" ]; then
    TYPE=restapi-web
fi

if [ "$TYPE" == 'restapi-web' ] && [ -z "$SOURCE" ]; then
    echo "When import type is restapi-web a source layerindex must be defined"
    exit 1
fi

if [ "$TYPE" == 'restapi-files' ] && [ -z "$BASE_URL" ]; then
    echo "When using input type restapi-files a base url must be defined"
    exit 1
fi

SETUPTOOLS=$(basename $REMOTE)

# create and start the layerindex and mariadb containers
docker-compose up -d

# Wait until health check passed for MariaDB
echo
echo "Waiting for database to come online..."
HEALTH_STATUS=""
CONTAINER_NAME="${COMPOSE_PROJECT_NAME}"_mariadb_1

while [[ $HEALTH_STATUS != "healthy" ]]; do
    HEALTH_STATUS=$( (docker inspect --format="{{.State.Health.Status}}" ${CONTAINER_NAME}) 2>/dev/null)

    if [[ $HEALTH_STATUS != "starting" && $HEALTH_STATUS != "healthy" ]]; then
        echo "Database is in $HEALTH_STATUS. Without database there is nothing to do. Shutting down"
        ./layerindex_stop.sh
        exit 1
    fi
    echo "Current status is $HEALTH_STATUS. Waiting..."
    sleep 2
done

echo "Database online"

DOCKER_EXEC=(docker-compose exec -T)

# override settings.py and tell gunicorn to reload
docker cp settings.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/layerindex/

# replace BITBAKE_REPO_URL in settings.py if it's been set
if [ -n "$BITBAKE_REPO_URL" ]; then
    replace_line="BITBAKE_REPO_URL = \'$BITBAKE_REPO_URL\'"
    "${DOCKER_EXEC[@]}" layerindex /bin/bash -c "sed -i \"/^BITBAKE_REPO_URL/c ${replace_line}\" /opt/layerindex/settings.py"
fi

PID=$("${DOCKER_EXEC[@]}" layerindex /bin/bash -c 'cat /tmp/gunicorn.pid')
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "kill -HUP $PID"

# Initialize the db without an admin user
echo
echo "Initializing database"
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c 'cd /opt/layerindex; python3 manage.py migrate'

# Ensure that /opt is writeable
"${DOCKER_EXEC[@]}" -u 0 layerindex /bin/bash -c 'chown layers /opt'

# clone repos that will be used to generate initial layerindex state
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/; git clone --depth=1 --branch=master-wr --single-branch $REMOTE"

# copy script that transforms mirror-index into django format
docker cp ./transform_index.py "${COMPOSE_PROJECT_NAME}_layerindex_1:/opt/${SETUPTOOLS}/bin"

declare -a TRANSFORM_CMD

if [ "$TYPE" == 'restapi-files' ]; then
    echo
    echo "Cloning Mirror-index"
    "${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/; git clone --depth=1 $SOURCE restapi-files"
    TRANSFORM_CMD=(--base_url "$BASE_URL")

    SOURCE=/opt/restapi-files
fi

TRANSFORM_CMD+=(--input "$TYPE" --branch "$BRANCH" --output "$OUTPUT" --source "$SOURCE")

# transform mirror-index to django format
echo
echo "Transforming database"
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/${SETUPTOOLS}/bin; ./transform_index.py ${TRANSFORM_CMD[*]}"

# import initial layerindex state.
echo
echo "Importing transformed database"
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/layerindex; sed -i 's/YPCompatibleVersions/YPCompatibleVersion/g' layerindex.json; python3 manage.py loaddata layerindex.json"

# setup django command directory
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c 'cd /opt/layerindex/layerindex; mkdir -p management; touch management/__init__.py; mkdir -p management/commands; touch management/commands/__init__.py'

# add commands to layerindex
docker cp commands/*.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/layerindex/layerindex/management/commands

# fetch oe-core because many layers depend on it
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/layerindex/layerindex; ./update.py --branch=$BRANCH -l openembedded-core"

# show available commands
#"${DOCKER_EXEC[@]}" layerindex /bin/bash -c 'cd /opt/layerindex; python3 manage.py'
