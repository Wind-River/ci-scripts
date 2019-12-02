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
PREBUILD_CMD_FOR_TEST=()
BUILD_CMD=()
BUILD_CMD_FOR_TEST=()
WORLD_BUILD=
SKIP_CLEANUP=no
WRLINUX=
ARCH=$(uname -m)
SOURCE_LAYOUT=

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
        --prebuild_cmd_for_test=*)    PREBUILD_CMD_FOR_TEST=(${i#*=}) ;;
        --build_id=*)           BUILD_ID=${i#*=} ;;
        --build_cmd=*)          BUILD_CMD=(${i#*=}) ;;
        --build_cmd_for_test=*)       BUILD_CMD_FOR_TEST=(${i#*=}) ;;
        --post-success=*)       POST_SUCCESS=${i#*=} ;;
        --post-fail=*)          POST_FAIL=${i#*=} ;;
        --world_build=*)        WORLD_BUILD=${i#*=} ;;
        --skip-cleanup=*)       SKIP_CLEANUP=${i#*=} ;;
        --wrlinux=*)            WRLINUX=${i#*=} ;;
        --fail_repo=*)          FAIL_REPO=${i#*=} ;; # override default in configs.sh
        --toaster=*)            TOASTER=${i#*=} ;;
        --source_layout=*)      SOURCE_LAYOUT=${i#*=} ;;
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

# Default to release layout unless the remote is defined using git protocol
# which means it will be in the dev layout
if [ -z "$SOURCE_LAYOUT" ]; then
    if [ "${REMOTE:0:6}" == 'git://' ]; then
        SOURCE_LAYOUT=dev
    else
        SOURCE_LAYOUT=release
    fi
fi

CACHE_BASE="${TOP}/../wrlinux-${SOURCE_LAYOUT}-${BRANCH}"
# Use reference clone support in repo to speed up setup.sh
export REPO_MIRROR_LOCATION="$CACHE_BASE"

# if setup_args does not contain --accept-eula=yes, add it
# https://stackoverflow.com/questions/14366390/check-if-an-element-is-present-in-a-bash-array/14367368#14367368
if [[ " ${SETUP_ARGS[*]} " != *" --accept-eula=yes "* ]]; then
    SETUP_ARGS+=('--accept-eula=yes')
fi

# if setup_args starts with -- add the setup command
if [ "${SETUP_ARGS[0]:0:2}" == '--' ]; then
    if [ -z "$WRLINUX" ]; then
        WRLINUX="${CACHE_BASE}/wrlinux-9"
    fi
    if [ ! -d "$WRLINUX" ]; then
        WRLINUX="${CACHE_BASE}/wrlinux-x"
    fi
    if [ ! -d "$WRLINUX" ]; then
        echo "Local clone of WRLinux at $WRLINUX not found!"
        exit 1
    fi

    # devbuild only works when patches are on same server as repos
    # due to way repo sets up the remotes
    if [ -f "${BUILD}/layerindex.json" ]; then
        WRLINUX="$REMOTE"
    fi

    # Make a clone of local mirror so setup will use local mirror
    wrlinux_setup_clone "$WRLINUX" "$BUILD" "$BRANCH" "$TOP"

    SETUP_ARGS=("$BUILD/${WRLINUX:(-9)}/setup.sh" "${SETUP_ARGS[@]}")
fi

if [ -f "${BUILD}/layerindex.json" ]; then
    log "Found serialized layerindex data for layerindex override"

    # modify settings.py to force setup to use local layerindex
    # until I can figure out how to use the local json file
    SETTINGS="$BUILD/${WRLINUX:(-9)}/bin/settings.py"
    sed -i -e 's#http://layers.wrs.com#http://does_not_exist.wrs.com#' \
        -e "s/'TYPE' : 'restapi-web'/'TYPE' : 'export'/" \
        "$SETTINGS"

    mkdir -p "$BUILD"/config/index-cache
    cp "${BUILD}/layerindex.json" "${BUILD}/config/index-cache/layers_wrs_com.json"

    # HACK: remove mirror-index from cache to prevent setup from loading it
    rm -rf "${CACHE_BASE}/mirror-index"
fi

# run the setup tool
log "${SETUP_ARGS[*]}" 2>&1 | tee --append "$BUILD/00-wrsetup.log"
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

    # if there is a local.conf in $TOP, override the default local.conf
    if [ -f "$BUILD/local.conf" ]; then
        cp "$BUILD/local.conf" conf/local.conf
    fi

    # Run prebuild command which may modify files like local.conf
    log "${PREBUILD_CMD[*]}" 2>&1 | tee -a "$BUILD/00-prebuild.log"
    $TIME bash -c "${PREBUILD_CMD[*]}" >> "$BUILD/00-prebuild.log" 2>&1
    RET=$?
    log_stats "Prebuild" "$BUILD"
    echo "Prebuild: ${PREBUILD_CMD[*]}" >> "$STATFILE"

    if [ "$RET" != 0 ]; then
        log "Prebuild failed"
    fi

    # Run prebuild command for test which may modify files like local.conf
    if [ "$RET" == 0 ] && [ ${#PREBUILD_CMD_FOR_TEST[@]} -ne 0 ]; then
        echo "Prebuild_for_test: ${PREBUILD_CMD_FOR_TEST[*]}" >> "$STATFILE"
        log "${PREBUILD_CMD_FOR_TEST[*]}" 2>&1 | tee -a "$BUILD/00-prebuild.log"
        $TIME bash -c "$WORKSPACE/ci-scripts/${PREBUILD_CMD_FOR_TEST[*]}" >> "$BUILD/00-prebuild.log" 2>&1
        RET=$?
        log_stats "Prebuild_for_test" "$BUILD"
        if [ "$RET" != 0 ]; then
            log "Prebuild for Test Image failed"
        fi
    fi

    if [ "$RET" == 0 ]; then
        # Source toaster start script to prepare Toaster GUI
        if [ "$TOASTER" == "enable" ]; then
            source toaster start webport=0.0.0.0:8800 >> "$BUILD/00-prebuild.log" 2>&1
        fi

        echo "Build: ${BUILD_CMD[*]}" >> "$STATFILE"
        log "${BUILD_CMD[*]}" 2>&1 | tee --append "$BUILD/00-wrbuild.log"
        $TIME bash -c "${BUILD_CMD[*]}" 2>&1 | log_stdout >> "$BUILD/00-wrbuild.log"
        RET=${PIPESTATUS[0]}
        log_stats "Build" "$BUILD"
        if [ "$RET" != 0 ]; then
            log "Build failed"
        fi
    else
        log "Skipping Build due to Prebuild failures"
    fi

    if [ "$RET" == 0 ] && [ ${#BUILD_CMD_FOR_TEST[@]} -ne 0 ]; then
        echo "Build for test: ${BUILD_CMD_FOR_TEST[*]}" >> "$STATFILE"
        log "${BUILD_CMD_FOR_TEST[*]}" 2>&1 | tee --append "$BUILD/00-wrbuild.log"
        $TIME bash -c "${BUILD_CMD_FOR_TEST[*]}" 2>&1 | log_stdout >> "$BUILD/00-wrbuild.log"
        RET=${PIPESTATUS[0]}
        log_stats "Build_for_test" "$BUILD"

        # If build failed but all images got generated, don't exit 1
        if [ "$RET" != 0 ]; then
            DETECT_IMAGES=$(detect_built_images "$BUILD" "$NAME")
            DETECT_IMAGES=${DETECT_IMAGES// /;/}
            IFS=' ; ' read -ra IMAGES <<< "$DETECT_IMAGES"

            if [ -z "${IMAGES[3]}" ]; then
                log "Detect built images: At least one of the images doesn't exist!"
            else
                log "Detect built images: Build failed but all images got generated"
                RET=2 # used by Jenkins to mark build as UNSTABLE but continue to run tests
            fi
        else
            log "Build for Test failed"
        fi
    fi

    echo "FinishUTC: $(date +%s)" >> "$STATFILE"

    if [ "$RET" == 0 ]; then
        echo "Status: PASSED" >> "$STATFILE"
    elif [ "$RET" == 1 ]; then
        echo "Status: FAILED" >> "$STATFILE"
    else
        echo "Status: PASSED" >> "$STATFILE"
    fi
fi

trigger_postprocess "$STATFILE"

log "Done build"

exit "$RET"
