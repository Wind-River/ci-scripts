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

#make sure current dir is same as location of script
cd "$(dirname "$0")"

source common.sh

TOP=/home/wrlbuild
BRANCH=WRLINUX_9_BASE
BUILD_NAME=generic
HOST=
EMAIL=
SETUP_ARGS=()
PREBUILD_CMD=()
BUILD_CMD=()
WORLD_BUILD=
SKIP_CLEANUP=no
WRLINUX=
ARCH=$(uname -m)

echo "Command: $0"
for i in "$@"
do
    echo "Arg: $i"
    case $i in
        --top=*)                TOP=${i#*=} ;;
        --branch=*)             BRANCH=${i#*=} ;;
        --host=*)               HOST=${i#*=} ;;
        --setup_args=*)         SETUP_ARGS=(${i#*=}) ;;
        --name=*)               BUILD_NAME=${i#*=} ;;
        --email=*)              EMAIL=${i#*=} ;;
        --prebuild_cmd=*)       PREBUILD_CMD=(${i#*=}) ;;
        --build_id=*)           BUILD_ID=${i#*=} ;;
        --build_cmd=*)          BUILD_CMD=(${i#*=}) ;;
        --post-success=*)       POST_SUCCESS=${i#*=} ;;
        --post-fail=*)          POST_FAIL=${i#*=} ;;
        --world_build=*)        WORLD_BUILD=${i#*=} ;;
        --skip-cleanup=*)       SKIP_CLEANUP=${i#*=} ;;
        --wrlinux=*)            WRLINUX=${i#*=} ;;
        --fail_repo=*)          FAIL_REPO=${i#*=} ;; # override default in configs.sh
        --toaster=*)            TOASTER=${i#*=} ;;
        *)                      ;;
    esac
    shift
done

HOME="$TOP"
export PATH="$TOP/ci-scripts/:$PATH"

BUILD=
create_build_dir
cd "$BUILD"

TIME="/usr/bin/time $QUIET -f %e -o $BUILD/time.log"

STATFILE=$BUILD/buildstats.log
create_statfile "$STATFILE"

# Start the hang check by the build post process script
touch "$BUILD/00-INPROGRESS"

# if setup_args starts with -- add the setup command
if [ "${SETUP_ARGS[0]:0:2}" == '--' ]; then
    if [ -z "$WRLINUX" ]; then
        WRLINUX="$TOP/wrlinux-$BRANCH/wrlinux-9"
    fi
    if [ ! -d "$WRLINUX" ]; then
        WRLINUX="$TOP/wrlinux-$BRANCH/wrlinux-x"
    fi
    if [ ! -d "$WRLINUX" ]; then
        echo "Local clone of WRLinux at $TOP/wrlinux-$BRANCH not found!"
        exit 1
    fi

    WRLINUX_BRANCH=$(echo "${BRANCH^^}" | tr '-' '_' )

    # Make a clone of local mirror so setup will use local mirror
    wrlinux_setup_clone "$WRLINUX" "$BUILD" "$WRLINUX_BRANCH" "$TOP"

    SETUP_ARGS=("$BUILD/${WRLINUX:(-9)}/setup.sh" "${SETUP_ARGS[@]}")
fi

# run the setup tool
log "${SETUP_ARGS[*]}" 2>&1 | tee "$BUILD/00-wrsetup.log"
$TIME bash -c "${SETUP_ARGS[*]}" >> "$BUILD/00-wrsetup.log" 2>&1
RET=$?
log_stats "Setup" "$BUILD"
echo "Setup: ${SETUP_ARGS[*]}" >> "$STATFILE"

if [ "$RET" != 0 ]; then
    log "Setup failed"
    echo "FinishUTC: $(date +%s)" >> "$STATFILE"
    echo "Status: FAILED" >> "$STATFILE"
else
    # Use the buildtools, setup env, run prebuild script and do build
    . ./environment-setup-x86_64-wrlinuxsdk-linux > "$BUILD/00-prebuild.log" 2>&1
    . ./oe-init-build-env "$BUILD_NAME" > "$BUILD/00-prebuild.log" 2>&1

    # Run prebuild command which may modify files like local.conf
    log "${PREBUILD_CMD[*]}" 2>&1 | tee -a "$BUILD/00-prebuild.log"
    $TIME bash -c "${PREBUILD_CMD[*]}" >> "$BUILD/00-prebuild.log" 2>&1
    log_stats "Prebuild" "$BUILD"
    echo "Prebuild: ${PREBUILD_CMD[*]}" >> "$STATFILE"

    # Source toaster start script to prepare Toaster GUI
    if [ "$TOASTER" == "enable" ]; then
        source toaster start webport=0.0.0.0:8800 >> "$BUILD/00-prebuild.log" 2>&1
    fi

    echo "Build: ${BUILD_CMD[*]}" >> "$STATFILE"
    log "${BUILD_CMD[*]}" 2>&1 | tee "$BUILD/00-wrbuild.log"
    $TIME bash -c "${BUILD_CMD[*]}" 2>&1 | log_stdout >> "$BUILD/00-wrbuild.log"

    RET=${PIPESTATUS[0]}

    # If build failed but all images got generated, don't exit 1
    if [ "$RET" != 0 ]; then
        DETECT_IMAGES=$(detect_built_images $BUILD "$NAME")
        DETECT_IMAGES=${DETECT_IMAGES// /;/}
        IFS=' ; ' read -ra IMAGES <<< "$DETECT_IMAGES"

        if [ -z "${IMAGES[3]}" ]; then
            log "Detect built images: At least one of the images doesn't exist!"
        else
            log "Detect built images: Build failed but all images got generated"
            RET=2 # used by Jenkins to mark build as UNSTABLE but continue to run tests
        fi
    fi

    echo "FinishUTC: $(date +%s)" >> "$STATFILE"
    log_stats "Build" "$BUILD"

    if [ "$RET" == 0 ]; then
        echo "Status: PASSED" >> "$STATFILE"
    elif [ "$RET" == 1 ]; then
        log "Build failed"
        echo "Status: FAILED" >> "$STATFILE"
    else
        echo "Status: PASSED" >> "$STATFILE"
    fi
fi

trigger_postprocess "$STATFILE"

log "Done build"

exit "$RET"
