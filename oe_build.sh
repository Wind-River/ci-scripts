#!/bin/bash

#make sure current dir is same as location of script
cd "$(dirname "$0")"

# print all env variables from mesos or local environment
env

source common.sh
source configs.sh

TOP=/home/wrlbuild
BRANCH=WRLINUX_9_BASE
BUILD_NAME=generic
HOST=
EMAIL=
SETUP_ARGS=()
PREBUILD_CMD=()
BUILD_CMD=()
POST_SUCCESS=process_build_stats
POST_FAIL=send_mail,process_build_failure,process_build_stats
WORLD_BUILD=
SKIP_CLEANUP=no
WRLINUX=
export PATH=$TOP/wr-buildscripts/configs:$PATH
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
        *)                      ;;
    esac
    shift
done

HOME="$TOP"
if [ -z "$WRLINUX" ]; then
    WRLINUX="$TOP/wrlinux-$BRANCH/wrlinux-x"
else
    GIT_SERVER=$(get_local_git_server)
    WRLINUX="${WRLINUX/GITSERVER/$GIT_SERVER}"
fi

BUILD=
create_build_dir
cd "$BUILD"

setup_post_scripts "$TOP" "post-success.d" "$POST_SUCCESS" "$BUILD"
setup_post_scripts "$TOP" "post-fail.d" "$POST_FAIL" "$BUILD"

TIME="/usr/bin/time $QUIET -f %e -o $BUILD/time.log"

STATFILE=$BUILD/buildstats.log
create_statfile "$STATFILE"

# Increase default parallelization for world build
if [ "$WORLD_BUILD" == "yes" ]; then
    PREBUILD_CMD=("${PREBUILD_CMD[@]}" --jobs=10 --parallel_pkgbuilds=20)
fi

# Make a clone of local mirror so setup will use local mirror
wrlinux_setup_clone "$WRLINUX" "$BUILD" "$BRANCH" "$TOP"

# Start the hang check by the build post process script
touch "$BUILD/00-INPROGRESS"

# If using http to clone project setup reference cloning with local copy
if [ "${WRLINUX:0:4}" == 'http' ]; then
    export REPO_MIRROR_LOCATION="$TOP/wrlinux-WRLinux-9-LTS-CVE"
    echo "Setup reference cloning with REPO_MIRROR_LOCATION=$REPO_MIRROR_LOCATION"
elif [ "${WRLINUX:0:3}" == 'git' ]; then
    export REPO_MIRROR_LOCATION="$TOP/wrlinux-WRLINUX_9_LTS_CVE"
    echo "Setup reference cloning with REPO_MIRROR_LOCATION=$REPO_MIRROR_LOCATION"
fi

# run the setup tool
SETUP_ARGS=("${SETUP_ARGS[@]}" --repo-verbose --verbose --accept-eula=yes)
log "setup.sh ${SETUP_ARGS[*]}" 2>&1 | tee "$BUILD/00-wrsetup.log"
$TIME "$BUILD/${WRLINUX:(-9)}/setup.sh" "${SETUP_ARGS[@]}" >> "$BUILD/00-wrsetup.log" 2>&1
RET=$?
log_stats "Setup" "$BUILD"
echo "Setup: ${SETUP_ARGS[*]}" >> "$STATFILE"

# Add symlink for compatibility for scripts that generate failmail
ln -s "$BUILD/00-wrsetup.log" "$BUILD/00-wrconfig.log"

if [ "$RET" != 0 ]; then
    log "Setup failed"
    echo "FinishUTC: $(date +%s)" >> "$STATFILE"
    echo "Status: FAILED" >> "$STATFILE"
    generate_failmail "$BUILD" "$BUILD_NAME"
    # Allow store_logs() work even the setup failed
    mkdir "$BUILD/$BUILD_NAME"
else
    # Use the buildtools, setup env, run prebuild script and do build
    . ./environment-setup-x86_64-wrlinuxsdk-linux
    . ./oe-init-build-env "$BUILD_NAME" > "$BUILD/00-prebuild.log" 2>&1

    # Run prebuild command which may modify files like local.conf
    log "$TOP/wr-buildscripts/${PREBUILD_CMD[0]} ${PREBUILD_CMD[*]:1}" 2>&1 | tee -a "$BUILD/00-prebuild.log"
    $TIME "$TOP/wr-buildscripts/${PREBUILD_CMD[0]}" "${PREBUILD_CMD[@]:1}" >> "$BUILD/00-prebuild.log" 2>&1
    log_stats "Prebuild" "$BUILD"
    echo "Prebuild: ${PREBUILD_CMD[*]}" >> "$STATFILE"

    setup_use_native_sstate "$ARCH" "$BRANCH" "$BUILD" "$BUILD_NAME" "$TOP"

    echo "Build: ${BUILD_CMD[*]}" >> "$STATFILE"
    log "${BUILD_CMD[*]}" 2>&1 | tee "$BUILD/00-wrbuild.log"
    $TIME "${BUILD_CMD[@]}" 2>&1 | log_stdout >> "$BUILD/00-wrbuild.log"

    RET=${PIPESTATUS[0]}

    echo "FinishUTC: $(date +%s)" >> "$STATFILE"
    log_stats "Build" "$BUILD"

    if [ "$RET" != 0 ]; then
        log "Build failed"
        echo "Status: FAILED" >> "$STATFILE"
        generate_failmail "$BUILD" "$BUILD_NAME"
    else
        echo "Status: PASSED" >> "$STATFILE"
        generate_successmail "$BUILD" "$BUILD_NAME"
        add_cgroup_stats "$STATFILE"

        if [ "$SKIP_CLEANUP" != "yes" ]; then
            log "Starting Cleanup"
            $TIME rm -rf "$BUILD/$BUILD_NAME"
            log_stats "Cleanup" "$BUILD"
        fi
    fi
fi

trigger_postprocess "$STATFILE"

log "Done build"
