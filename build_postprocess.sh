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

# needed for setup_post_scripts
source "$(dirname "$0")"/common.sh

run_post_scripts()
{
    local BUILD="$1"
    local POST_SCRIPT_DIR="$2"

    if [ -d "$BUILD/$POST_SCRIPT_DIR" ]; then
        (
            run-parts --arg="$BUILD" --arg="$WORKSPACE/ci-scripts" \
                      -- "$BUILD/$POST_SCRIPT_DIR"
        )
    fi
}

main()
{
    local BUILD="$WORKSPACE/builds/builds-$BUILD_ID"
    cd "$BUILD" || exit 1

    setup_post_scripts "$WORKSPACE/ci-scripts" "post-success.d" "$POST_SUCCESS" "$BUILD"
    setup_post_scripts "$WORKSPACE/ci-scripts" "post-fail.d" "$POST_FAIL" "$BUILD"

    if [ -f "00-PASS" ]; then
        run_post_scripts "$BUILD" "post-success.d"
    elif [ -f "00-FAIL" ]; then
        run_post_scripts "$BUILD" "post-fail.d"
    fi
}

main "$@"
