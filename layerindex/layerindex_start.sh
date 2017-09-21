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
# ./layerindex_start.sh --input=restapi-web --branch=master \
#          --source=https://layers.openembedded.org/layerindex/api/
#
# To populate it with a cached mirror-index:
#
# ./layerindex_start.sh --type=restapi-files --branch=WRLINUX_9_BASE \
#    --base_url=https://github.com/WindRiver-Labs/wrlinux-9.git \
#    --source=https://github.com/WindRiver-Labs/mirror-index.git

COMPOSE_PROJECT_NAME=${PWD##*/}
if [ -n "$BUILD_ID" ]; then
    export COMPOSE_PROJECT_NAME="build$BUILD_ID"
fi

TYPE=restapi-web
BASE_URL=https://github.com/WindRiver-Labs/
OUTPUT=/opt/layerindex
SOURCE=https://layers.openembedded.org/layerindex/api/

if [ -z "$BRANCH" ]; then
    BRANCH=WRLINUX_9_BASE
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
        --base_url=*) BASE_URL=${i#*=} ;;
        *)          ;;
    esac
    shift
done

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
for i in {10..1};do echo -n "$i." && sleep 1; done; echo

# Initialize the db without an admin user
echo
echo "Initializing database"
docker-compose exec -T layerindex /bin/bash -c 'cd /opt/layerindex; python3 manage.py syncdb --noinput'

# clone repos that will be used to generate initial layerindex state
docker-compose exec -T layerindex /bin/bash -c 'cd /opt/; git clone --depth=1 https://github.com/WindRiver-Labs/wrlinux-9.git'

# copy script that transforms mirror-index into django format
docker cp ./transform_index.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/wrlinux-9/bin

declare -a TRANSFORM_CMD

if [ "$TYPE" == 'restapi-files' ]; then
    echo
    echo "Cloning Mirror-index"
    docker-compose exec -T layerindex /bin/bash -c "cd /opt/; git clone --depth=1 $SOURCE restapi-files"
    TRANSFORM_CMD=(--base_url "$BASE_URL")

    SOURCE=/opt/restapi-files
fi

TRANSFORM_CMD+=(--input "$TYPE" --branch "$BRANCH" --output "$OUTPUT" --source "$SOURCE")

# transform mirror-index to django format
echo
echo "Transforming database"
docker-compose exec -T layerindex /bin/bash -c "cd /opt/wrlinux-9/bin; ./transform_index.py ${TRANSFORM_CMD[*]}"

# import initial layerindex state.
echo
echo "Importing transformed database"
docker-compose exec -T layerindex /bin/bash -c "cd /opt/layerindex; python3 manage.py loaddata import.json"

# setup django command directory
docker-compose exec -T layerindex /bin/bash -c 'cd /opt/layerindex/layerindex; mkdir -p management; touch management/__init__.py; mkdir -p management/commands; touch management/commands/__init__.py'

# add commands to layerindex
docker cp commands/*.py "${COMPOSE_PROJECT_NAME}_layerindex_1":/opt/layerindex/layerindex/management/commands

# fetch oe-core because many layers depend on it
docker-compose exec -T layerindex /bin/bash -c "cd /opt/layerindex/layerindex; ./update.py --branch=$BRANCH -l openembedded-core"

# show available commands
#docker-compose exec -T layerindex /bin/bash -c 'cd /opt/layerindex; python3 manage.py'
