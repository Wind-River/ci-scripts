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

if [ -z "$DEVBUILD_BRANCH" ]; then
    BRANCH=WRLINUX_9_BASE
else
    BRANCH="$DEVBUILD_BRANCH"
fi

if [ -z "$REMOTE" ]; then
    REMOTE=https://github.com/WindRiver-Labs/wrlinux-9
fi

SETUPTOOLS=$(echo "$REMOTE" |sed 's/https:\/\/github.com\/WindRiver-Labs\///g')

echo "Command: $0"
for i in "$@"
do
    echo "Arg: $i"
    case $i in
        --type=*)   TYPE=${i#*=} ;;
        --branch=*) BRANCH=${i#*=} ;;
        --output=*) OUTPUT=${i#*=} ;;
        --source=*) SOURCE=${i#*=} ;;
        --base_url=*) BASE_URL=${i#*=} ;;
        *)          ;;
    esac
    shift
done

if [ "$TYPE" == '' ]; then
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

# create and star the layerindex and mariadb containers
docker-compose create
docker-compose up -d

# hack to wait for db to come online
echo
echo "Waiting for database to come online"
for i in {11..1};do echo -n "$i." && sleep 1; done; echo

DOCKER_EXEC=(docker-compose exec -T)

# replace BITBAKE_REPO_URL in settings.py if it's been set
if [ "$BITBAKE_REPO_URL" != '' ]; then
    replace_line="BITBAKE_REPO_URL = \"$BITBAKE_REPO_URL\""
    sed -i "/^BITBAKE_REPO_URL/c ${replace_line}" settings.py
    cat settings.py | grep BITBAKE_REPO_URL
fi

# override settings.py and tell gunicorn to reload
docker cp settings.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/layerindex/
docker cp settings.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/layerindex/layerindex
PID=$("${DOCKER_EXEC[@]}" layerindex /bin/bash -c 'cat /opt/layerindex/gunicorn.pid')
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "kill -HUP $PID"

# Initialize the db without an admin user
echo
echo "Initializing database"
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c 'cd /opt/layerindex; python3 manage.py migrate'

# clone repos that will be used to generate initial layerindex state
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/; git clone --depth=1 $REMOTE"

# copy script that transforms mirror-index into django format
docker cp ./transform_index.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/"$SETUPTOOLS"/bin

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
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/"$SETUPTOOLS"/bin; ./transform_index.py ${TRANSFORM_CMD[*]}"

# import initial layerindex state.
echo
echo "Importing transformed database"
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/layerindex; python3 manage.py loaddata import.json"

# setup django command directory
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c 'cd /opt/layerindex/layerindex; mkdir -p management; touch management/__init__.py; mkdir -p management/commands; touch management/commands/__init__.py'

# add commands to layerindex
docker cp commands/*.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/layerindex/layerindex/management/commands

# fetch oe-core because many layers depend on it
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/layerindex/layerindex; ./update.py --branch=$BRANCH -l openembedded-core"

# show available commands
#"${DOCKER_EXEC[@]}" layerindex /bin/bash -c 'cd /opt/layerindex; python3 manage.py'
