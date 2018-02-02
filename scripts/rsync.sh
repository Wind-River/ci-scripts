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

post_rsync() {
    source "${WORKSPACE}/ci-scripts/common.sh"
    local BUILD="$1"

    command -v bzip2 >/dev/null 2>&1 || { echo >&2 "bzip2 required. Aborting."; exit 0; }
    command -v rsync >/dev/null 2>&1 || { echo >&2 "rsync required. Aborting."; exit 0; }

    if [ -z "$NAME" ]; then
        echo "Error: Rsync post process script requires NAME defined!"
        exit 0
    fi

    # Use internal rsync server if one has not been specified
    if [ -z "$RSYNC_SERVER" ]; then
        echo "RSYNC_SERVER not defined. Using internal rsync server."
        RSYNC_SERVER=rsync
    fi

    # if RSYNC_DEST_DIR not defined and internal rsync server is used, then default to a reasonable destination
    if [ -z "$RSYNC_DEST_DIR" ] && [ "$RSYNC_SERVER" == "rsync" ]; then
        RSYNC_DEST_DIR="builds/${NAME}-$(date --iso-8601=date)"
    fi

    # The directory that will be rsync'd elsewhere
    local RSYNC_SOURCE_DIR="$BUILD/rsync/$NAME"
    mkdir -p "$RSYNC_SOURCE_DIR"

    # Decide tmp folder based on different WRLinux version
    WRL_VER=$(get_wrlinux_version "$BUILD")
    if [ "$WRL_VER" == "10" ]; then
        TMP_DIR=tmp-glibc
    else
        TMP_DIR=tmp
    fi

    # compress the ext3/ext4 images which have lots of empty space
    local EXPORT_DIR=
    EXPORT_DIR=$(readlink -f "${NAME}/${TMP_DIR}/deploy/images")
    find "$EXPORT_DIR" -type f -name "*ext[34]" \
         -exec /bin/bash -c "bzip2 '{}'" \;

    # Get image name
    IMAGE_NAME=$(find "$EXPORT_DIR" -type l -name '*.iso' -printf '%f' |sed 's/.iso//g')

    # Get *.hddimg, *.tar.bz2 and bzImage files
    find "$EXPORT_DIR" -name "${IMAGE_NAME}.*" -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/." \;
    find "$EXPORT_DIR" -name "bzImage" -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/." \;

    # "Copy" all conf files to rsync dir
    ln -sfrL "${BUILD}/${NAME}/conf" "$RSYNC_SOURCE_DIR/conf"

    # "Copy" all 00-* log files to rsync dir
    find "$BUILD" -type f -name "00-*" -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/." \;

    if [[ "$OE_TEST" == "yes" || "$OE_TEST" == True ]]; then
        # Get rpm package for OE test
        local DEPLOY_DIR=
        DEPLOY_DIR=$(readlink -f "${NAME}/${TMP_DIR}/deploy/rpm")
        find "$DEPLOY_DIR" -name "rpm-doc*" \
             -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/." \;

        # Get OE test package
        local TEST_EXPORT_DIR=
        TEST_EXPORT_DIR=$(readlink -f "${NAME}/${TMP_DIR}/testexport")
        find "$TEST_EXPORT_DIR" -type f -name "testexport.tar.gz" \
             -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/." \;
    fi

    if [ "$RSYNC_SSTATE" == "yes" ]; then
        mkdir -p "$RSYNC_SOURCE_DIR/sstate"
        # Skip the native sstate because it is already built and distributed
        find "$NAME/sstate-cache/" -maxdepth 1 -mindepth 1 -type d \
             -name '[a-z0-9][a-z0-9]' -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/sstate/." \;
    fi

    # Initial rsync copies symlinks to destination
    echo "Rsyncing objects to rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"
    rsync -avL "$RSYNC_SOURCE_DIR" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"

    # Notify that rsync is complete
    local RSYNC_STAMP="$BUILD/00-RSYNC-$NAME"
    touch "$RSYNC_STAMP"
    rsync -avL "$RSYNC_STAMP" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"

    if [ "$RSYNC_SERVER" == "rsync" ]; then
        echo "Artifacts can be accessed at ${JENKINS_URL/%jenkins\//builds}${RSYNC_DEST_DIR/#builds/}"
    fi
}

post_rsync "$@"

exit 0
