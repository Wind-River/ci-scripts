#!/bin/bash
if [ -z "$3" ]; then
    echo "ERROR: run_tests.sh needs these variables:"
    echo "       LAVA_TEST_REPO, LAVA_JOB_TEMPLATE, LAVA_JOB_TIMEOUT"
    exit 1
fi

LAVA_TEST_REPO=$1
LAVA_JOB_TEMPLATE=$2
LAVA_JOB_TIMEOUT=$3

source "$WORKSPACE"/ci-scripts/common.sh
export HOME=/home/jenkins

BUILD="$WORKSPACE/builds/builds-$BUILD_ID"

TEST_MAIL=${BUILD}/mail.txt
TEST_REPORT=${BUILD}/${TEST}.csv
OEQA_TEST_IMAGE=testexport.tar.gz

# Create teststats.json file
TEST_STATFILE=${BUILD}/teststats.json
create_report_statfile "$TEST_STATFILE" "$JENKINS_URL" "$JOB_BASE_NAME"

{
    if [ -f "$BUILD/00-PASS" ]; then
        printf '    "build_result": "PASSED"\n'
    elif [ -f "$BUILD/00-FAIL" ]; then
        printf '    "build_result": "FAILED"\n'
    fi
    printf '  },\n'
    printf '\n  "test_info": {\n'
    if [ -n "$EMAIL" ]; then
        printf '    "email": "%s",\n' "$EMAIL"
    fi
    printf '    "start_time": "%s (%s)",\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(date +%s)"
} >> "$TEST_STATFILE"

function generate_test_mail () {
    STATUS=$1

    echo "Subject: [wrigel][$STATUS] Test $NAME on $TEST_DEVICE finished" > "$TEST_MAIL"
    echo "" >> "$TEST_MAIL"
    cat "$TEST_STATFILE" >> "$TEST_MAIL"
}

function quit_test () {
    RET=$1

    rm -rf "$BUILD"/00-TEST-*

    if [ "$RET" == 0 ]; then
        STATUS='PASSED'
        touch "$BUILD/00-TEST-PASS"
    elif [ "$RET" == -2 ]; then
        STATUS='NOTARGET'
        touch "$BUILD/00-TEST-FAIL"
    else
        STATUS='FAILED'
        touch "$BUILD/00-TEST-FAIL"
    fi

    {
        printf '    "end_time": "%s %s",\n' "$(date '+%Y-%m-%d %H:%M:%S')" "($(date +%s))"
        printf '    "test_result": "%s"\n' "${STATUS}"
        printf '  },\n'

        printf '\n  "test_report": {\n'
        awk -F "," '{if (NR!=1 && (NF-1)>0) {print "   ", $(NF-3), ":", $3, ","}}' "$TEST_REPORT"
        printf '    "eof": ""\n'
        printf '  }\n'
        printf '}'
    } >> "$TEST_STATFILE"

    rsync -avL "$TEST_STATFILE" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"

    # Get LAVA job log
    LAVA_JOB_PLAIN_LOG="http://${LAVA_SERVER}/scheduler/job/${job_id}/log_file/plain"
    LAVA_JOB_LOG="$BUILD/lava_job_${job_id}.log"
    echo "curl -k $LAVA_JOB_PLAIN_LOG -o $LAVA_JOB_LOG"
    curl -k "$LAVA_JOB_PLAIN_LOG" -o "$LAVA_JOB_LOG"
    rsync -avL "$LAVA_JOB_LOG" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"

    # Get LAVA test result in csv format
    LAVA_JOB_RESULT_CSV="http://${LAVA_SERVER}/results/${job_id}/csv"
    LAVA_JOB_RESULT_YAML="http://${LAVA_SERVER}/results/${job_id}/yaml"
    LAVA_JOB_REPORT_CSV="$BUILD/lava_job_${job_id}_result.csv"
    LAVA_JOB_REPORT_YAML="$BUILD/lava_job_${job_id}_result.yaml"
    echo "curl -k $LAVA_JOB_RESULT_CSV -o $LAVA_JOB_REPORT_CSV"
    curl -k "$LAVA_JOB_RESULT_CSV" -o "$LAVA_JOB_REPORT_CSV"
    echo "curl -k $LAVA_JOB_RESULT_YAML -o $LAVA_JOB_REPORT_YAML"
    curl -k "$LAVA_JOB_RESULT_YAML" -o "$LAVA_JOB_REPORT_YAML"
    rsync -avL "$LAVA_JOB_REPORT_CSV" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"
    rsync -avL "$LAVA_JOB_REPORT_YAML" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"

    generate_test_mail $STATUS
    exit "$RET"
}

# Check if lava-tool exists
command -v lava-tool >/dev/null 2>&1 || { echo >&2 "lava-tool required. Aborting."; exit 0; }

# Check necessary parameters
if [ -z "$LAVA_USER" ] || [ -z "$LAVA_SERVER" ] || [ -z "$NFS_ROOT" ] || \
   [ -z "$HTTP_ROOT" ] || [ -z "$RSYNC_DEST_DIR" ]; then
    echo "Error: runtime test script requires LAVA_USER, LAVA_SERVER, \
          NFS_ROOT, HTTP_ROOT and RSYNC_DEST_DIR defined!"
    echo "Example: --test_args=LAVA_USER=lpdtest,\
LAVA_SERVER=yow-lpdtest.wrs.com:8080,NFS_ROOT=/net/yow-lpdtest/var/lib/tftpboot,\
HTTP_ROOT=http://128.224.56.215/tftpboot,RSYNC_DEST_DIR=builds/x86-64_oe-test-04"
    quit_test -1
fi

# when using simics instances in simics server
#SIMICS_IMG_ROOT="$NFS_ROOT"
# when using simics instances in simics-docker
SIMICS_IMG_ROOT='/images'

if [ -z "$TEST_DEVICE" ]; then
    TEST_DEVICE=simics
fi

if [ -z "$TEST" ]; then
    TEST=oeqa-default-test
fi

WRL_VER=$(get_wrlinux_version "$BUILD")

FILE_LINK="${HTTP_ROOT}/${RSYNC_DEST_DIR}/${NAME}"

{
    printf '    "wrl_ver": "%s",\n' "$WRL_VER"
    printf '    "LAVA_server": "%s",\n' "$LAVA_SERVER"
    printf '    "LAVA_user": "%s",\n' "$LAVA_USER"
    printf '    "LAVA_token": "%s",\n' "$LAVA_AUTH_TOKEN"
    printf '    "NFS_root": "%s",\n' "$NFS_ROOT"
    printf '    "HTTP_root": "%s",\n' "$HTTP_ROOT"
    printf '    "test_images": "%s",\n' "${HTTP_ROOT}/${RSYNC_DEST_DIR}"
    printf '    "test_device": "%s",\n' "${TEST_DEVICE}"
    printf '    "test_suite": "%s",\n' "${TEST}"
} >> "$TEST_STATFILE"

# Start the hang check by the test post process script
touch "$BUILD/00-TEST-INPROGRESS"

cd "$BUILD"

# Get test job templates and necessary script files
repo_folder=$(basename "$LAVA_TEST_REPO" | sed 's/.git//g')
git clone --quiet "$LAVA_TEST_REPO"

if [ -d "$repo_folder" ]; then
    printf '    "test_git_repo": "%s",\n' "$LAVA_TEST_REPO" >> "$TEST_STATFILE"

    # LAVA authentication
    echo "[LAVA-CMD] lava-tool auth-list |grep ${LAVA_SERVER}"
    lava-tool auth-list | grep "$LAVA_SERVER"

    # If the auth token exists, remove it because LAVA server could be updated and
    # old token may not work any more
    if [ $? == 0 ]; then
        echo "[LAVA-CMD] lava-tool auth-remove http://${LAVA_USER}@${LAVA_SERVER}"
        lava-tool auth-remove "http://${LAVA_USER}@${LAVA_SERVER}"

        echo "[LAVA-CMD] lava-tool auth-list |grep ${LAVA_SERVER}"
        lava-tool auth-list | grep "$LAVA_SERVER"
        if [ $? == 0 ]; then
            printf '    "ERROR": "lava-tool auth-remove failed!",\n' >> "$TEST_STATFILE"
            quit_test -1
        fi
    fi

    # Replace LAVA auth-token if user specified in configs
    TOKEN_FILE="$repo_folder/scripts/auth-token"
    if [ ! -z "$LAVA_AUTH_TOKEN" ]; then
        echo "$LAVA_AUTH_TOKEN" > "$BUILD/$TOKEN_FILE"
    fi

    # Add latest auth token to make sure it's the latest
    echo "[LAVA-CMD] lava-tool auth-add http://${LAVA_USER}@${LAVA_SERVER} \
        --token-file $BUILD/$TOKEN_FILE"
    lava-tool auth-add "http://${LAVA_USER}@${LAVA_SERVER}" --token-file \
        "${BUILD}/$TOKEN_FILE"

    echo "[LAVA-CMD] lava-tool auth-list |grep ${LAVA_SERVER}"
    lava-tool auth-list |grep "$LAVA_SERVER"
    if [ $? != 0 ]; then
        printf '    "ERROR": "LAVA Server $LAVA_SERVER is in unhealthy status.",\n' >> "$TEST_STATFILE"
        echo "LAVA Server $LAVA_SERVER is in unhealthy status, exit!"
        quit_test -1
    fi
else
    printf '    "ERROR": "clone git repo: %s failed!",\n' "$repo_folder" >> "$TEST_STATFILE"
    quit_test -1
fi

# Find kernel file name
pushd "$BUILD/rsync/$NAME"
if [ "$TEST_DEVICE" == "mxe5400-qemu-ppc" ] || [ "$TEST_DEVICE" == "mxe5400-qemu-mips64" ]; then
    KERNEL_FILE=$(ls ./vmlinux)
else
    KERNEL_FILE=$(ls ./*Image)
fi
echo "KERNEL_FILE = $KERNEL_FILE"

# Find image name
pushd "$BUILD/rsync/$NAME"
IMAGE_FULL_NAME=$(ls ./*.tar.bz2)
IMAGE_NAME="${IMAGE_FULL_NAME%.tar.bz2}"
echo "IMAGE_NAME = $IMAGE_NAME"

# Find dtb file
DTB_FILE=$(ls ./*.dtb | tail -1)
echo "DTB_FILE = $DTB_FILE"

# Find rpm-doc file name
RPM_NAME=$(ls rpm-doc*)
echo "RPM_NAME = $RPM_NAME"

# Find initramfs file name
INITRAMFS_NAME=$(ls *rootfs.cpio.gz)
echo "INITRAMFS_NAME = $INITRAMFS_NAME"

# Set LAVA test job name
TIME_STAMP=$(date +%Y%m%d_%H%M%S)
TEST_JOB="$BUILD/$repo_folder/test_${TIME_STAMP}.yaml"
printf '    "LAVA_test_job": "%s",\n' "$TEST_JOB" >> "$TEST_STATFILE"

popd

# Replace image files in LAVA JOB file
JOB_TEMPLATE="$BUILD/$LAVA_JOB_TEMPLATE"
cp -f "$JOB_TEMPLATE" "$TEST_JOB"

if [[ "$TEST_DEVICE" == *"simics"* ]]; then
    sed -i "s@HDD_IMG@${SIMICS_IMG_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${IMAGE_NAME}.hddimg@g" "$TEST_JOB"
elif [[ "$TEST_DEVICE" == "qemu-x86_64" ]]; then
    sed -i "s@KERNEL_IMG@${FILE_LINK}\/${KERNEL_FILE}@g; \
            s@HDD_IMG@${FILE_LINK}\/${IMAGE_NAME}.hddimg@g; \
            s@INITRD_IMG@${FILE_LINK}\/${INITRAMFS_NAME}@g" "$TEST_JOB"
elif [[ "$TEST_DEVICE" == *"qemu-arm"* ]] || \
     [ "$TEST_DEVICE" == "mxe5400-qemu-x86_64" ] || \
     [ "$TEST_DEVICE" == "mxe5400-qemu-ppc" ] || \
     [ "$TEST_DEVICE" == "mxe5400-qemu-mips64" ]; then
    sed -i "s@KERNEL_IMG@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${KERNEL_FILE}@g; \
            s@EXT4_IMG@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${IMAGE_NAME}.ext4@g; \
            s@DTB_FILE@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${DTB_FILE}@g" "$TEST_JOB"
else
    sed -i "s@KERNEL_IMG@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${KERNEL_FILE}@g; \
            s@ROOTFS@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${IMAGE_NAME}.tar.bz2@g; \
            s@DTB_FILE@${NFS_ROOT}\/${RSYNC_DEST_DIR}\/${NAME}\/${DTB_FILE}@g" "$TEST_JOB"
fi

# For OE QA test specifically
if [[ "$TEST" == *"oeqa"* ]]; then
    sed -i "s@TEST_PACKAGE@$FILE_LINK\/${OEQA_TEST_IMAGE}@g; \
            s@RPM_FILE@$FILE_LINK\/${RPM_NAME}@g; \
            s@MANIFEST_FILE@$FILE_LINK\/${IMAGE_NAME}.manifest@g" "$TEST_JOB"
fi
#cat "$TEST_JOB"

if [ -z "$RETRY" ]; then
    RETRY=0;
fi
printf '    "retry_times": %d,\n' "$RETRY" >> "$TEST_STATFILE"

echo "Start running LAVA test ..."

for (( r=0; r<=RETRY; r++ ))
do
    # Submit an example job
    echo "[LAVA-CMD] lava-tool submit-job http://${LAVA_USER}@${LAVA_SERVER} $TEST_JOB"
    ret=$(lava-tool submit-job "http://${LAVA_USER}@${LAVA_SERVER}" "$TEST_JOB")
    job_id=${ret//submitted as job: http:\/\/${LAVA_SERVER}\/scheduler\/job\//}

    if [ -z "$job_id" ]; then
        printf '    "ERROR": "job_id = %d, failed to submit LAVA job!",\n' "$job_id" >> "$TEST_STATFILE"
        quit_test -1
    else
        printf '\n    "LAVA_test_job_id": %d,\n' "$job_id" >> "$TEST_STATFILE"
    fi

    echo "[LAVA-CMD] lava-tool job-details http://${LAVA_USER}@${LAVA_SERVER} ${job_id}"
    lava-tool job-details "http://${LAVA_USER}@${LAVA_SERVER}" "$job_id"

    # Echo LAVA job links
    {
        printf '    "test_job_def": "http://%s/scheduler/job/%d/definition",\n' "$LAVA_SERVER" "$job_id"
        printf '    "test_log": "http://%s/scheduler/job/%d",\n' "$LAVA_SERVER" "$job_id"
        printf '    "test_report": "http://%s/results/%d",\n' "$LAVA_SERVER" "$job_id"
    } >> "$TEST_STATFILE"

    # Loop $LAVA_JOB_TIMEOUT seconds to wait test result
    TEST_LOOPS=$((LAVA_JOB_TIMEOUT / 10))
    for (( c=1; c<="$TEST_LOOPS"; c++ ))
    do
       ret=$(lava-tool job-status "http://${LAVA_USER}@${LAVA_SERVER}" "${job_id}" |grep 'Job Status: ')
       job_status=${ret//Job Status: /}
       echo "$c. Job Status: $job_status"
       if [ "$job_status" == 'Complete' ]; then
           printf '    "test_job_status": "Completed",\n' >> "$TEST_STATFILE"

           # Generate test report
           echo "curl http://${LAVA_SERVER}/results/${job_id}/0_${TEST}/csv > $TEST_REPORT"
           curl "http://${LAVA_SERVER}/results/${job_id}/0_${TEST}/csv" > "$TEST_REPORT"

           if [ -f "$TEST_REPORT" ]; then
               quit_test 0
           else
               printf '    "ERROR": "Generate test report file failed!",\n' >> "$TEST_STATFILE"
               quit_test -1
           fi
       elif [ "$job_status" == 'Incomplete' ]; then
           printf '    "test_job_status": "Incompleted",\n' >> "$TEST_STATFILE"
           break;
       elif [ "$job_status" == 'Canceled' ]; then
           printf '    "test_job_status": "Canceled",\n' >> "$TEST_STATFILE"
           break;
       elif [ "$job_status" == 'Submitted' ] || [ "$job_status" == 'Running' ]; then
           sleep 10
       fi
    done

    if [ $r -lt $RETRY ]; then
       printf '\n    "Status": "Retry the %d time ...",\n' "$((r + 1))" >> "$TEST_STATFILE"
    fi
done

if [ "$job_status" == 'Submitted' ] && [ "$((c-1))" == "$TEST_LOOPS" ]; then
    # exit with no_target and timeout
    quit_test -2
else
    # exit with failure or timeout
    quit_test -1
fi
