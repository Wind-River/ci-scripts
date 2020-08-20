#!/bin/bash

BRANCH=
RELOAD=

echo "Command: $0"
for i in "$@"
do
    echo "Arg: $i"
    case $i in
        --branch*) BRANCH=${i#*=} ;;
        --reload)  RELOAD='--fullreload' ;;
        *)         echo "Unrecognized arg $i"; exit 1;;
    esac
    shift
done

# Validation of provided environment args
if [ -z "$BRANCH" ]; then
    echo "Without a branch to use for updates, there is nothing to do"
    exit 1
fi

# Local layerindex will have project name based on build id to avoid conflicts
COMPOSE_PROJECT_NAME=${PWD##*/}
if [ -n "$BUILD_ID" ]; then
    export COMPOSE_PROJECT_NAME="build$BUILD_ID"
fi

DOCKER_EXEC=(docker-compose exec -T)

"${DOCKER_EXEC[@]}" layerindex /bin/bash -c "cd /opt/layerindex/layerindex; ./update.py --branch=$BRANCH $RELOAD"
