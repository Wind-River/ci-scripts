#!/bin/bash

if [ -n "$BUILD_ID" ]; then
    export COMPOSE_PROJECT_NAME="build$BUILD_ID"
fi

# stop and clean up containers and volumes
docker-compose down -v

