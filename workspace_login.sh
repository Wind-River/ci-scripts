#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

usage()
{
    cat <<USAGE
Usage: devbuild_login.sh [OPTIONS]

Using command line specified in build failure email, log into the
buildarea of the failed build.

Options:

    --builder=<hostname>

        Hostname of the system where the build was done

    --build_dir=<dir>

        Location of build directory on build server

    --type=<build|test>

        docker image will be used for build or runtime test

Development Options:

    --server=<jenkins>

       Select the Wrigel Jenkins server for the devbuilds.
       Default: ala-blade21.wrs.com

    --ci-repo=<git repo>

       Select the ci-scripts git repo used for the devbuild setup
       Default: git://ala-lxgit.wrs.com/projects/wrlinux-ci/ci-scripts

    --ci-branch=<branch>

       Select the ci-scripts branch to be used.
       Default: master

       It requires to run the following command to switch ci-scripts branch:
       .venv/bin/python3 jenkins_job_create.py --jenkins <jenkins> --job Login --ci_branch <branch>

Miscellaneous:

    -v, --verbose

        Enable more logging

    -h, --help

        Display this message and exit
USAGE
}

DRY_RUN=no
VERBOSE=0

log()
{
    if [ "$VERBOSE" -ne  0 ]; then echo "$@"; fi
}

main()
{
    echo "Script Version: $(git --git-dir "$(readlink -f "${0%/*}"/.git)" rev-parse HEAD)"

    local SERVER=https://ala-blade21.wrs.com
    local CI_REPO=git://ala-lxgit.wrs.com/projects/wrlinux-ci/ci-scripts
    local CI_BRANCH=master
    local BUILDER=
    local BUILD_DIR=
    local IMAGE_TYPE=build
    local USER=wrlbuild

    while [ $# -gt 0 ]; do
        case "$1" in
            --server=*)               SERVER=${1#*=} ;;
            --server)                 SERVER=$2; shift ;;
            --ci[-_]repo=*)           CI_REPO=${1#*=} ;;
            --ci[-_]repo)             CI_REPO=$2; shift ;;
            --ci[-_]branch=*)         CI_BRANCH=${1#*=} ;;
            --ci[-_]branch)           CI_BRANCH=$2; shift ;;
            --builder=*)              BUILDER=${1#*=} ;;
            --builder)                BUILDER=$2; shift ;;
            --build[-_]dir=*)         BUILD_DIR=${1#*=} ;;
            --build[-_]dir)           BUILD_DIR=$2; shift ;;
            --type=*)                 IMAGE_TYPE="${1#*=}"; shift ;;
            --user=*)                 USER=${1#*=} ;;
            --user)                   USER=$2; shift ;;
            -v|--verbose)             VERBOSE=1 ;;
            -h|--help)                usage; exit 0 ;;
            *)                        echo "Unrecognized arg $1."; usage; exit 1 ;;
        esac
        shift
    done

    if [ -z "$BUILDER" ]; then
        echo "ERROR: Require hostname of the system where the buildarea is located"
        exit 1
    fi

    if [ -z "$BUILD_DIR" ]; then
        echo "ERROR: Require location of the buildarea on $BUILDER"
        exit 1
    fi

    # make sure $SERVER starts with https:// and does not end with jenkins
    if [ "${SERVER:0:8}" != 'https://' ]; then
        SERVER="https://$SERVER"
    fi

    if [ "${SERVER:(-8)}" == 'jenkins/' ]; then
        SERVER="${SERVER:(-8)}"
    fi

    if [ "${SERVER:(-7)}" == 'jenkins' ]; then
        SERVER="${SERVER:(-7)}"
    fi

    local BUILDER_HOSTNAME="${BUILDER:0:(-9)}"
    if ! host "$BUILDER_HOSTNAME" &> /dev/null ; then
        echo "The Builder Hostname $BUILDER is not valid. Cannot figure out proper host to log into."
        exit 1
    fi

    KEYS=$(mktemp --tmpdir -d devbuild-keys-XXXXXXXXX)
    function finish {
        rm -rf "$KEYS"
    }
    trap finish EXIT

    log "Creating ssh keypair in $KEYS"
    ssh-keygen -q -t rsa -f "$KEYS/id_rsa" -C "" -N ""
    awk '{print $2}' < "$KEYS/id_rsa.pub" > "$KEYS/key.pub"

    echo "Retrieving authentication information from $SERVER"
    local APITOKEN=
    APITOKEN=$(curl --insecure --silent --show-error "$SERVER/auth/build_auth.txt" | tr -d '\n')

    local CRUMB=
    CRUMB=$(curl --insecure --silent --show-error --user "$APITOKEN" \
                 "$SERVER"/jenkins/crumbIssuer/api/xml?xpath='concat(//crumbRequestField,":",//crumb)' )

    if [[ -z "$IMAGE_TYPE" ]]; then
         IMAGE_TYPE='build'
    fi

    local PARAMS="token=devbuild&BUILDER=${BUILDER}&BUILD_DIR=${BUILD_DIR}&CI_REPO=${CI_REPO}&CI_BRANCH=${CI_BRANCH}&IMAGE_TYPE=${IMAGE_TYPE}"

    echo "Starting Login Setup Job on $SERVER/jenkins"
    curl --dump-header "$KEYS/headers" -X POST --insecure -H "$CRUMB" --user "$APITOKEN" \
         --data-urlencode PUBLIC_SSH_KEY@"${KEYS}/key.pub" \
         "$SERVER/jenkins/job/Login/buildWithParameters?$PARAMS"

    local QUEUE=
    # the headers have a line feed character embedded in it
    QUEUE=$(grep Location: "$KEYS/headers" | awk '{print $2}' | tr -d '\r')
    log "Login Setup Job queued at: $QUEUE"

    echo "Waiting for Login setup to complete"
    local JOB=
    while :
    do
        sleep 5
        echo "Checking if queued Login Setup Job has been scheduled"
        JOB=$(curl --insecure --silent --show-error "${QUEUE}api/xml?tree=executable\[url\]" || true)
        if [[ "$JOB" =~ "job/Login/" ]]; then
            break
        fi
    done

    # extract job url from queue status and then strip tags
    JOB=$(echo "$JOB" | grep -o '<url>.*</url>' )
    JOB="${JOB:5:(-6)}"

    echo "Login Setup Job has been scheduled at $JOB."
    local STATUS=
    while :
    do
        sleep 2
        echo "Attempting login."
        ssh -o IdentitiesOnly=yes -o CheckHostIp=no -o StrictHostKeyChecking=no \
            -o PasswordAuthentication=no -i "${KEYS}/id_rsa" -S none -l "$USER" "${BUILDER_HOSTNAME}" || true

        STATUS=$(curl --insecure --silent --show-error "${JOB}api/xml?tree=result")
        if [[ "$STATUS" =~ "SUCCESS" ]]; then
            break
        elif [[ "$STATUS" =~ "FAILURE" ]]; then
            echo "Login Setup Job failed! Another login session may be in progress. Try again later."
            exit 1
        elif [[ "$STATUS" =~ "ABORTED" ]]; then
            echo "Login Setup Job aborted!"
            exit 1
        fi
    done
    echo
}

main "$@"
