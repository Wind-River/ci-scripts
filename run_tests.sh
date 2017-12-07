#!/bin/bash

source ${WORKSPACE}/ci-scripts/common.sh
export HOME=/home/jenkins

BUILD="$WORKSPACE/builds/builds-$BUILD_ID"
TIME="/usr/bin/time $QUIET -f %e -o $BUILD/test_time.log"

TEST_MAIL=${BUILD}/mail.txt
TEST_REPORT=${BUILD}/${TEST_SUITE}.csv
TEST_STATFILE=${BUILD}/teststats.log
create_test_statfile "$TEST_STATFILE"

function generate_test_mail () {
    STATUS=$1

    echo "Subject: [ci-scripts][$STATUS] Test $NAME on $TEST_DEVICE finished" > "$TEST_MAIL"
    echo "" >> "$TEST_MAIL"
    cat "$TEST_STATFILE" >> "$TEST_MAIL"
}

function quit_test () {
    RET=$1

    rm -rf "$BUILD"/00-TEST-*

    if [ "$RET" == 0 ]; then
        STATUS='PASSED'
        touch "$BUILD/00-TEST-PASS"
    else
        STATUS='FAILED'
        touch "$BUILD/00-TEST-FAIL"
    fi

    {
        echo "End: $(date) ($(date +%s))"
        echo "Status: ${STATUS}"

        echo -e "\nTest result:"
        echo -e "============"
        awk -F "\"*,\"*" '{if (NR!=1) {print $14, "\t", $3}}' "$TEST_REPORT"
    } >> "$TEST_STATFILE"

    cat "$TEST_STATFILE"

    generate_test_mail $STATUS
    exit "$RET"
}

# Check if lava-tool exists
command -v lava-tool >/dev/null 2>&1 || { echo >&2 "lava-tool required. Aborting."; exit 0; }

# Check necessary parameters
if [ -z "$LAVA_USER" ] || [ -z "$LAVA_SERVER" ] || [ -z "$NFS_ROOT" ] || \
   [ -z "$HTTP_ROOT" ] || [ -z "$RSYNC_DEST_DIR" ]; then
    echo "Error: runtime test script requires LAVA_USER, LAVA_SERVER, \
          NFS_ROOT, HTTP_ROOT and RSYNC_DEST_DIR defined!" >> $"$TEST_STATFILE"
    echo "Example: --test_args=LAVA_USER=lpdtest,\
LAVA_SERVER=yow-lpdtest.wrs.com:8080,NFS_ROOT=/net/yow-lpdtest/var/lib/tftpboot,\
HTTP_ROOT=http://128.224.56.215/tftpboot,RSYNC_DEST_DIR=builds/x86-64_oe-test-04"
    quit_test -1
fi

if [ -z "$TEST_DEVICE" ]; then
    TEST_DEVICE=simics
fi

if [ -z "$TEST_SUITE" ]; then
    TEST_SUITE=oeqa-default-test
fi

WRL_VER=$(get_wrlinux_version "$BUILD")

FILE_LINK="${HTTP_ROOT}/${RSYNC_DEST_DIR}/${NAME}"

{
    echo "WRLinux ver:   $WRL_VER"
    echo "LAVA server:   $LAVA_SERVER"
    echo "LAVA user:     $LAVA_USER"
    echo "NFS root:      $NFS_ROOT"
    echo "HTTP root:     $HTTP_ROOT"
    echo "Test images:   ${FILE_LINK}"
    echo "Test device:   ${TEST_DEVICE}"
    echo "Test suite:    ${TEST_SUITE}"
} >> "$TEST_STATFILE"

# Start the hang check by the test post process script
touch "$BUILD/00-TEST-INPROGRESS"

cd "$BUILD"

# Get test job templates and necessary script files
git clone --quiet git://ala-git.wrs.com/lpd-ops/lava-test.git

if [ -d lava-test ]; then
    echo "Test git repo: git://ala-git.wrs.com/lpd-ops/lava-test.git" >> "$TEST_STATFILE"

    # LAVA authentication
    echo "[LAVA-CMD] lava-tool auth-list |grep yow-lpdtest"
    lava-tool auth-list | grep yow-lpdtest

    # If the auth token exists, remove it
    if [ $? == 0 ]; then
        echo "[LAVA-CMD] lava-tool auth-remove http://${LAVA_USER}@${LAVA_SERVER}"
        lava-tool auth-remove "http://${LAVA_USER}@${LAVA_SERVER}"

        echo "[LAVA-CMD] lava-tool auth-list |grep yow-lpdtest"
        lava-tool auth-list | grep yow-lpdtest
        if [ $? == 0 ]; then
            echo "lava-tool auth-remove failed!" >> "$TEST_STATFILE"
            quit_test -1
        fi
    fi

    # Add new auth token to make sure it's the latest
    echo "[LAVA-CMD] lava-tool auth-add http://${LAVA_USER}@${LAVA_SERVER} \
        --token-file ${BUILD}/lava-test/scripts/auth-token-lpdtest"
    lava-tool auth-add "http://${LAVA_USER}@${LAVA_SERVER}" --token-file \
        "${BUILD}/lava-test/scripts/auth-token-lpdtest"

    echo "[LAVA-CMD] lava-tool auth-list |grep yow-lpdtest"
    lava-tool auth-list |grep yow-lpdtest
    if [ $? != 0 ]; then
        echo "lava-tool auth-add failed!" >> "$TEST_STATFILE"
        quit_test -1
    fi
else
    echo "clone git repo: lava-test failed!" >> "$TEST_STATFILE"
    quit_test -1
fi


# Find image name
pushd "$BUILD/rsync/$NAME"
IMAGE_NAME=$(ls ./*.tar.bz2 | sed s/.tar.bz2//g)
echo "IMAGE_NAME = $IMAGE_NAME"

# Find rpm-doc file name
RPM_NAME=$(ls rpm-doc*)
echo "RPM_NAME = $RPM_NAME"

# Set OE test export image name
TEST_EXPORT_IMAGE=testexport.tar.gz

# Set LAVA test job name
TIME_STAMP=$(date +%Y%m%d_%H%M%S)
TEST_JOB=test_${TIME_STAMP}.yaml
echo "LAVA test job: ${BUILD}/lava-test/${TEST_JOB}" >> "$TEST_STATFILE"

popd

# Replace image files in LAVA JOB file
if [ $TEST_DEVICE == 'simics' ]; then
    JOB_TEMPLATE=${BUILD}/lava-test/jobs/templates/wrlinux-${WRL_VER}/x86_simics_job_${TEST_SUITE}_template.yaml
    cp -f "$JOB_TEMPLATE" "${BUILD}/lava-test/${TEST_JOB}"
    sed -i "s@HDD_IMG@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${IMAGE_NAME}.hddimg@g" "lava-test/${TEST_JOB}"
else
    JOB_TEMPLATE=${BUILD}/lava-test/jobs/templates/wrlinux-${WRL_VER}/x86_64_job_${TEST_SUITE}_template.yaml
    cp -f "$JOB_TEMPLATE" "${BUILD}/lava-test/${TEST_JOB}"
    sed -i "s@KERNEL_IMG@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/bzImage@g" "lava-test/${TEST_JOB}"
    sed -i "s@ROOTFS@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${IMAGE_NAME}.tar.bz2@g" "lava-test/${TEST_JOB}"
fi

# For OE QA test specifically
if [[ $TEST_SUITE == *"oeqa"* ]]; then
    sed -i "s@TEST_PACKAGE@--no-check-certificate\ $FILE_LINK\/${TEST_EXPORT_IMAGE}@g" "lava-test/${TEST_JOB}"
    sed -i "s@MANIFEST_FILE@--no-check-certificate\ $FILE_LINK\/${IMAGE_NAME}.manifest@g" "lava-test/${TEST_JOB}"
    sed -i "s@RPM_FILE@--no-check-certificate\ $FILE_LINK\/${RPM_NAME}@g" "lava-test/${TEST_JOB}"
fi
#cat lava-test/${TEST_JOB}

if [ -z "$RETRY" ]; then
    RETRY=0;
fi
echo "Retry times:   $RETRY" >> "$TEST_STATFILE"

echo -e "\nStart running OE test ..." >> "$TEST_STATFILE"

for (( r=0; r<=RETRY; r++ ))
do
    # Submit an example job
    echo "[LAVA-CMD] lava-tool submit-job http://${LAVA_USER}@${LAVA_SERVER} lava-test/${TEST_JOB}"
    ret=$(lava-tool submit-job "http://${LAVA_USER}@${LAVA_SERVER}" "lava-test/${TEST_JOB}")
    job_id=$(echo "$ret" | sed "s/submitted as job: http:\/\/${LAVA_SERVER}\/scheduler\/job\///g")

    if [ -z "$job_id" ]; then
        echo "job_id = ${job_id}, failed to submit LAVA job!" >> "$TEST_STATFILE"
        quit_test -1
    else
        echo "LAVA test job id: $job_id" >> "$TEST_STATFILE"
    fi

    echo "[LAVA-CMD] lava-tool job-details http://${LAVA_USER}@${LAVA_SERVER} ${job_id}"
    lava-tool job-details "http://${LAVA_USER}@${LAVA_SERVER}" "$job_id"

    # Echo LAVA job links
    {
        echo "Test job def: http://${LAVA_SERVER}/scheduler/job/${job_id}/definition"
        echo "Test log:     http://${LAVA_SERVER}/scheduler/job/${job_id}"
        echo "Test result:  http://${LAVA_SERVER}/results/${job_id}"
    } >> "$TEST_STATFILE"

    # Loop 60 x 10s to wait test result
    for (( c=1; c<=60; c++ ))
    do
       ret=$(lava-tool job-status "http://${LAVA_USER}@${LAVA_SERVER}" "${job_id}" |grep 'Job Status: ')
       job_status=${ret//Job Status: /}
       echo "$c. Job Status: $job_status"
       if [ "$job_status" == 'Complete' ]; then
           echo "Job ${job_id} finished successfully!" >> "$TEST_STATFILE"

           # Generate test report
           echo "[LAVA-CMD] lava-tool test-suite-results --csv http://${LAVA_USER}@${LAVA_SERVER} ${job_id} 0_${TEST_SUITE} > ${TEST_REPORT}"
           lava-tool test-suite-results --csv "http://${LAVA_USER}@${LAVA_SERVER}" "${job_id}" 0_${TEST_SUITE} > "${TEST_REPORT}"

           if [ -f "$TEST_REPORT" ]; then
               quit_test 0
           else
               echo "Generate test report file failed!" >> "$TEST_STATFILE"
               quit_test -1
           fi
       elif [ "$job_status" == 'Incomplete' ]; then
           echo "Job ${job_id} Incompleted!" >> "$TEST_STATFILE"
           break;
       elif [ "$job_status" == 'Canceled' ]; then
           echo "Job ${job_id} Canceled!" >> "$TEST_STATFILE"
           break;
       elif [ "$job_status" == 'Submitted' ] || [ "$job_status" == 'Running' ]; then
           sleep 10
       fi
    done

    if [ $r -lt $RETRY ]; then
       echo "Retry the $((r + 1)) time ..." >> "$TEST_STATFILE"
    fi
done

# exit with failure or timeout
quit_test -1
