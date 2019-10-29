#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

TYPE='build'
if [[ -z "$1" ]]; then
    TYPE="$1"
fi

main()
{
    if [ -z "$BUILD_DIR" ] || [ ! -f "$BUILD_DIR/${TYPE}_login.sh" ]; then
        echo "ERROR: Require build dir with ${TYPE}_login.sh for the login"
        exit 1
    fi

    if [ -z "$PUBLIC_SSH_KEY" ]; then
        echo "ERROR: Require a public ssh key"
        exit 1
    fi

    local SSH_DIR=/home/wrlbuild/.ssh
    if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi

    local AUTH_KEYS="$SSH_DIR/authorized_keys2"
    if [ ! -f "$AUTH_KEYS" ]; then
        touch "$AUTH_KEYS"
        chmod 600 "$AUTH_KEYS"
    fi

    # Since stamp file is created outside of docker, the build dir is not accessible
    # create a stamp file in the ssh dir with slashes replaced by hashes
    local LOGIN_STAMP="${SSH_DIR}/.${BUILD_DIR////#}.login"

    # add the ssh key to the authorized_keys2 file to allow passwordless
    # logins that start the same docker in the right place
    if grep -q "$BUILD_DIR" "$AUTH_KEYS"; then
        # is there actually a login in progress
        if [ -f "${LOGIN_STAMP}" ]; then
            echo "ERROR: A login has already been setup for ${BUILD_DIR}. Try again later"
            exit 1
        else
            # probably the last login attempt was aborted and the login never occurred.
            /bin/sed -i "\\#${BUILD_DIR}#d" "$AUTH_KEYS"
        fi
    else
        # if there isn't an entry in authorized_keys, then there shouldn't be a login stamp
        rm -f "$LOGIN_STAMP"
    fi

    CMD=$(cat "$BUILD_DIR/${TYPE}_login.sh")

    echo "Adding key for $BUILD_DIR to authorized keys"
    echo "command=\"touch ${LOGIN_STAMP}; $CMD; /bin/rm -f ${LOGIN_STAMP}; /bin/sed -i '\\#${BUILD_DIR}#d' $AUTH_KEYS\" ssh-rsa $PUBLIC_SSH_KEY $BUILD_DIR" >> "$AUTH_KEYS"

    # allow a minute for a login. If it doesn't happen, abort and remove the key
    local TIMEOUT=60
    local COUNTER=0
    local LOGIN_DETECTED=0
    while [ "$COUNTER" -lt "$TIMEOUT" ]; do
        if [ -f "$LOGIN_STAMP" ]; then
            echo "Login detected. Ending Jenkins Job"
            LOGIN_DETECTED=1
            break
        else
            echo "Waiting for login on $BUILD_DIR"
            COUNTER=$((COUNTER + 2))
            sleep 2
        fi
    done

    # if no login was detected, cleanup and fail the job
    if [ "$LOGIN_DETECTED" == "0" ]; then
        echo "No login detected. Removing login entry and failing job"
        /bin/sed -i "\\#${BUILD_DIR}#d" "$AUTH_KEYS"
        exit 1
    fi
    exit 0
}

main "$@"
