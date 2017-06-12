#!/bin/bash

env

"$WORKSPACE"/ci-scripts/oe_build.sh \
    --top="$WORKSPACE" --name="$NAME" --branch="$BRANCH" \
    --host="$NODE_NAME" --setup_args="$SETUP_ARGS" --prebuild_cmd="$PREBUILD_CMD" \
    --build_cmd="$BUILD_CMD" \
    --email=Konrad.Scherer@windriver.com
