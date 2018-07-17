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

COMPOSE_PROJECT_NAME=${PWD##*/}
if [ -n "$BUILD_ID" ]; then
    export COMPOSE_PROJECT_NAME="build$BUILD_ID"
fi

echo "Command: $0"
for i in "$@"
do
    echo "Arg: $i"
    case $i in
        --type=*)   TYPE=${i#*=} ;;
        --branch=*) BRANCH=${i#*=} ;;
        --output=*) OUTPUT=${i#*=} ;;
        --output_format=*) OUTPUT_FORMAT=${i#*=} ;;
        --source=*) SOURCE=${i#*=} ;;
        *)          ;;
    esac
    shift
done

if [ -z "$TYPE" ]; then
    TYPE=restapi-web
fi

if [ -z "$BRANCH" ]; then
    echo "Branch not defined"
    exit 1
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT='/opt/mirror-index'
fi

if [ -z "$OUTPUT_FORMAT" ]; then
    OUTPUT_FORMAT=restapi
fi

if [ -z "$SOURCE" ]; then
    SOURCE=http://localhost:5000/layerindex/api/
fi

DOCKER_EXEC=(docker-compose exec -T)

TRANSFORM_CMD+=(--input "$TYPE" --branch "$BRANCH" --output "$OUTPUT" --output_format "$OUTPUT_FORMAT" --source "$SOURCE")

# transform local running layerindex to mirror-index format
echo
echo "Exporting layerindex to $OUTPUT/layerindex.json"
"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/wrlinux-[9x]/bin; ./transform_index.py ${TRANSFORM_CMD[*]}"

echo "Copying $OUTPUT/layerindex.json into the workarea"
docker cp "${COMPOSE_PROJECT_NAME}_layerindex_1:${OUTPUT}/layerindex.json" .
