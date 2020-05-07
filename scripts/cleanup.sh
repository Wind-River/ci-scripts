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

cleanup() {
    local BUILD="$1"
    local TOP="$2"

    if [ -z "$NAME" ]; then
        echo "Error: Build NAME is not defined!"
        exit 1
    fi

    source "$TOP/common.sh"
    local BUILD_STATUS=$(get_stat 'Status')
    if [ "$BUILD_STATUS" == "PASSED" ]; then
        echo "Removing build directory $BUILD/$NAME"
        # fail if $BUILD is empty SC2115
        rm -rf "${BUILD:?}/$NAME"
    fi

    echo "Removing old build directories"

    #default threshold: 200G df uses 1Kb blocks so 1024 * 1024 * 200
    local DISK_THRESHOLD=209715200
    local REMAINING_DISK=

    local DAYS=
    for DAYS in 3 2 1 0; do
        REMAINING_DISK=$(get_remaining_disk_space /home/jenkins/workspace)
        if [ "$REMAINING_DISK" -lt "$DISK_THRESHOLD" ]; then
            echo "Removing build areas older than $DAYS days"
            find /home/jenkins/workspace/WRLinux_Build*/builds -maxdepth 1 -type d -name 'builds-*' -ctime +"$DAYS" -exec rm -rf {} \;
        fi

        echo "Removing sstate files that have not been accessed in $DAYS days"
        find /home/jenkins/workspace/*_sstate_cache -atime +"$DAYS" -delete
    done
}

cleanup "$@"

exit 0
