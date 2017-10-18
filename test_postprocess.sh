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


function setup_post_scripts {
    local POST_DIR="$1"
    local POST_SCRIPTS="$2"
    local BUILD="$3"
    local SCRIPT=
    local COUNTER_STR=

    mkdir -p "${BUILD}/${POST_DIR}"

    COUNTER=0
    set -f; IFS=,
    for SCRIPT in $POST_SCRIPTS; do
        COUNTER_STR=$(printf "%02d" "$COUNTER")
        local SCRIPT_FULLPATH="$WORKSPACE/ci-scripts/scripts/${SCRIPT}.sh"
        if [ -f "$SCRIPT_FULLPATH" ]; then
            ln -s "$SCRIPT_FULLPATH" "${BUILD}/${POST_DIR}/${COUNTER_STR}-$SCRIPT"
        fi
        COUNTER=$((COUNTER + 1))
    done
    set +f; unset IFS
}

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

    setup_post_scripts "post-test-success.d" "$POST_TEST_SUCCESS" "$BUILD"
    setup_post_scripts "post-test-fail.d" "$POST_TEST_FAIL" "$BUILD"

    if [ -f "00-TEST-PASS" ]; then
        run_post_scripts "$BUILD" "post-test-success.d"
    elif [ -f "00-TEST-FAIL" ]; then
        run_post_scripts "$BUILD" "post-test-fail.d"
    fi
}

main "$@"
