#!/bin/bash

# Validation of provided environment args
if [ -z "$DEVBUILD_LAYER_NAME" ]; then
    echo "Without a layer name, there is nothing to do"
    exit 1
fi

if [ -z "$DEVBUILD_BRANCH" ]; then
    echo "Without a branch to use for updates, there is nothing to do"
    exit 1
fi

# Local layerindex will have project name based on build id to avoid conflicts

COMPOSE_PROJECT_NAME=${PWD##*/}
if [ -n "$BUILD_ID" ]; then
    export COMPOSE_PROJECT_NAME="build$BUILD_ID"
fi

# Support only changing the actual branch or just the vcs_url.
# If neither is provided, the layer will be updated for nothing

ARGS=(--name $DEVBUILD_LAYER_NAME --branch $DEVBUILD_BRANCH)

if [ -n "$DEVBUILD_LAYER_VCS_URL" ]; then
    ARGS+=(--vcs_url $DEVBUILD_LAYER_VCS_URL)
fi

if [ -n "$DEVBUILD_LAYER_ACTUAL_BRANCH" ]; then
    ARGS+=(--actual_branch $DEVBUILD_LAYER_ACTUAL_BRANCH)
fi

if [ -n "$DEVBUILD_LAYER_VCS_SUBDIR" ]; then
    ARGS+=(--vcs_subdir $DEVBUILD_LAYER_VCS_SUBDIR)
fi

DOCKER_EXEC=(docker-compose exec -T)

"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/layerindex; python3 manage.py layer_update ${ARGS[*]}"

"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/layerindex/layerindex; ./update.py --branch=$DEVBUILD_BRANCH -l $DEVBUILD_LAYER_NAME --fullreload"

