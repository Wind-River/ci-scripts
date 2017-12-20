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

if [ -z "$BASE" ]; then
    echo "BASE is not set. Do not know where to clone wrlinux. Aborting"
    exit 1
fi

if [ -z "$CREDENTIALS" ] && [ -f "${BASE}/credentials.txt" ]; then
    CREDENTIALS=credentials.txt
fi

call_setup_with_timeout()
{
    local SETUP_REPO=$1
    local TIMEOUT=$2
    local CREDENTIAL_CONTENT=
    local USER=
    local PASSWORD=
    local SETUP_ARGS=(--all-layers --dl-layers --mirror "--accept-eula=yes")

    if [ -z "$TIMEOUT" ]; then
        TIMEOUT=20m
    fi

    # extract credentials and pass to setup.sh
    if [ -f "${BASE}/${CREDENTIALS}" ]; then
        CREDENTIAL_CONTENT=$(cat "${BASE}/${CREDENTIALS}")
        USER=${CREDENTIAL_CONTENT%%:*}
        PASSWORD=${CREDENTIAL_CONTENT##*:}
        SETUP_ARGS=(${SETUP_ARGS[@]} "--user=${USER}" "--password=${PASSWORD}")
    fi

    # give setup $TIMEOUT minutes to complete and set TERM signal. If that doesn't work,
    # send KILL 60s later
    timeout --kill-after=60s "$TIMEOUT" \
            "./${SETUP_REPO}/setup.sh" "${SETUP_ARGS[@]}"
    local RET=$?
    if [ $RET != 0 ]; then
        echo "fatal: Setup command exited with $RET or timed out"
    fi
}

check_mirror_index_size()
{
    if [ -d mirror-index ]; then
        local MIRROR_INDEX_SIZE=
        MIRROR_INDEX_SIZE=$(du -sm mirror-index | cut -f1)
        if [ "$MIRROR_INDEX_SIZE" -gt 50 ]; then
            echo "Mirror index cache at $PWD has grown to over 50MB and will be deleted"
            rm -rf mirror-index
        fi
    fi
}

wrl_clone_or_update()
{
    local BRANCH=$1

    local REMOTE=$2
    local SETUP_REPO=
    local WRLINUX_BRANCH=
    WRLINUX_BRANCH=$(echo "${BRANCH^^}" | tr '-' '_' )
    SETUP_REPO=wrlinux-9
    if [ "${REMOTE:0:6}" == 'git://' ]; then
        SETUP_REPO=wrlinux-x
    fi

    # create credential file for use by git credential.helper
    if [ -f "${BASE}/${CREDENTIALS}" ]; then
        echo "Using credentials in ${BASE}/${CREDENTIALS}"
        local CREDENTIAL_CONTENT=
        CREDENTIAL_CONTENT=$(cat "${BASE}/${CREDENTIALS}")
        local REMOTE_PROTOCOL=${REMOTE%%//*}
        local REMOTE_URL=${REMOTE##*//}
        echo "${REMOTE_PROTOCOL}//${CREDENTIAL_CONTENT}@${REMOTE_URL}" > "${BASE}/url_${CREDENTIALS}"
    fi

    if [ ! -f "${BASE}/wrlinux-${BRANCH}/${SETUP_REPO}/setup.sh" ]; then
        (
            mkdir -p "${BASE}/wrlinux-$BRANCH/${SETUP_REPO}"
            cd "${BASE}/wrlinux-$BRANCH/${SETUP_REPO}"

            echo "Initializing repo in $SETUP_REPO"
            git init
            git remote add -t "${WRLINUX_BRANCH}" origin "${REMOTE}"
            if [ -f "${BASE}/${CREDENTIALS}" ]; then
                git config credential.helper "store --file ${BASE}/url_${CREDENTIALS}"
            fi
            echo "Fetch and checkout branch $WRLINUX_BRANCH from $REMOTE"
            git fetch origin "${WRLINUX_BRANCH}"
            if ! git checkout -t "origin/${WRLINUX_BRANCH}"; then
                echo "FATAL: Clone from branch ${WRLINUX_BRANCH} on repo ${REMOTE} failed."
                echo "Validate credentials are correct."
                exit 1
            fi
            cd "${BASE}/wrlinux-$BRANCH"
            echo "Mirroring wrlinux source tree with setup program on branch $BRANCH"
            call_setup_with_timeout "$SETUP_REPO" 60m
        )
    else
        (
            echo "Updating $SETUP_REPO on branch $WRLINUX_BRANCH"
            cd "${BASE}/wrlinux-${BRANCH}/${SETUP_REPO}"
            git fetch --quiet
            git reset --hard "origin/$WRLINUX_BRANCH"
        )
        (
            echo "Updating wrlinux source tree with setup program on branch $BRANCH"
            cd "${BASE}/wrlinux-$BRANCH/"
            check_mirror_index_size
            call_setup_with_timeout "$SETUP_REPO"
        )
    fi
    rm -f "${BASE}/url_${CREDENTIALS}"
}

lock_and_update()
{
    local BRANCH=$1
    local REMOTE=$2
    echo "Starting update for $BRANCH by trying to take lock"
    local LOCKFILE="${BASE}/.update-${BRANCH}.lck"
    exec 8>"$LOCKFILE"
    flock --exclusive 8
    echo "Lock for $BRANCH aquired"
    if ! wrl_clone_or_update "$BRANCH" "$REMOTE"; then
        echo "FATAL: Clone failed"
        exit 1
    fi
    flock --unlock 8
    echo "Completed update of $BRANCH and releasing lock"
}

main()
{
    echo "*************"
    echo "Starting wrlinux mirror updates"

    cd "$BASE" || exit 1

    local BRANCHES=$*

    local BRANCH=
    for BRANCH in $BRANCHES; do
        case "$BRANCH" in
            WRLinux-9-Base*)
                if [ -z "$REMOTE" ]; then
                    REMOTE='https://github.com/WindRiver-Labs/wrlinux-9'
                fi
                lock_and_update "$BRANCH" "$REMOTE"
                ;;
            WRLinux-lts-*-Base)
                if [ -z "$REMOTE" ]; then
                    REMOTE='https://github.com/WindRiver-Labs/wrlinux-x'
                fi
                lock_and_update "$BRANCH" "$REMOTE"
                ;;
            WRLinux-9-LTS*)
                if [ -z "$REMOTE" ]; then
                    REMOTE="https://windshare.windriver.com/ondemand/remote.php/gitsmart/$BRANCH/wrlinux-9"
                fi
                lock_and_update "$BRANCH" "$REMOTE"
                ;;
            WRLinux-lts*-Core)
                if [ -z "$REMOTE" ]; then
                    REMOTE="https://windshare.windriver.com/ondemand/remote.php/gitsmart/$BRANCH/wrlinux-x"
                fi
                lock_and_update "$BRANCH" "$REMOTE"
                ;;
            WRLINUX_*)
                if [ -z "$REMOTE" ]; then
                    REMOTE='git://ala-git.wrs.com/wrlinux-x'
                fi
                lock_and_update "$BRANCH" "$REMOTE"
                ;;
        esac
    done
    echo "Finished update"
}

main "$@"
