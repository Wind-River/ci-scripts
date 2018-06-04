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

function get_jenkins_log () {
    local BUILD="$1"

    if [[ "$JENKINS_URL" != *"wrs.com"* ]]; then
        JENKINS_URL=${JENKINS_URL::-9}.wrs.com/jenkins/
    fi
    if [ -z "$JOB_BASE_NAME" ]; then
        JOB_BASE_NAME='WRLinux_Build'
    fi
    JENKINS_LOG_URL="${JENKINS_URL}job/${JOB_BASE_NAME}/${BUILD_ID}/consoleText"
    JENKINS_LOG=${BUILD}/jenkins_job_${BUILD_ID}_console.log

    # get jenkins console log
    echo "curl -k $JENKINS_LOG_URL -o $JENKINS_LOG"
    curl -k "$JENKINS_LOG_URL" -o "$JENKINS_LOG"
    rsync -avL "$JENKINS_LOG" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"
}

report() {
    source "$WORKSPACE"/ci-scripts/common.sh

    local BUILD="$1"
    export HOME=/home/jenkins

    get_jenkins_log "$BUILD"

    if [ -z "$REPORT_SERVER" ]; then
        echo "Do not know report server"
        exit 0
    fi

    command -v curl >/dev/null 2>&1 || { echo >&2 "curl required. Aborting."; exit 0; }

    # Handle build failure report
    if [ ! -f "$BUILD/teststats.json" ]; then
        if [ "$TEST" != 'disable' ] && [ -f "$BUILD/00-PASS" ]; then
            echo "Report info: Build passed and teststats.json has not been generated."
            exit 0
        else
            REPORT_STATFILE=${BUILD}/buildstats.json
            create_report_statfile "$REPORT_STATFILE" "$JENKINS_URL" "$JOB_BASE_NAME"

            if [ -f "$BUILD/00-PASS" ]; then
                echo "    \"build_result\": \"PASSED\"" >> "$REPORT_STATFILE"
            elif [ -f "$BUILD/00-FAIL" ]; then
                echo "    \"build_result\": \"FAILED\"" >> "$REPORT_STATFILE"
            fi

            WRL_VER=$(get_wrlinux_version "$BUILD")

            {
                echo "  },"
                echo -e "\n  \"test_info\": {"
                echo "    \"wrl_ver\": \"$WRL_VER\","
                echo "    \"test_images\": \"${HTTP_ROOT}/${RSYNC_DEST_DIR}\","
                echo "    \"test_result\": \"NULL\""
                echo "  }"
                echo "}"
            } >> "$REPORT_STATFILE"

            rsync -avL "$REPORT_STATFILE" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"
        fi
    else
        REPORT_STATFILE=${BUILD}/teststats.json
        # It should not happen when build failed but test continues, print WARNING.
        if [ -f "$BUILD/00-FAIL" ]; then
            echo "WARNING from report: Build failed! Test should not continue."
        fi
    fi

    echo "Reporting to $REPORT_SERVER"
    current_date=$(date +%Y.%m.%d)
    # report to elasticsearch server
    curl -XPOST "${REPORT_SERVER}/wrigel-${current_date}/logs" -d @"$REPORT_STATFILE"
}

report "$@"

exit 0
