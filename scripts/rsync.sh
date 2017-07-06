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
    local BUILD="$1"
    local TOP="$2"

    command -v bzip2 >/dev/null 2>&1 || { echo >&2 "bzip2 required. Aborting."; exit 0; }
    command -v rsync >/dev/null 2>&1 || { echo >&2 "rsync required. Aborting."; exit 0; }

    if [ -z "$NAME" ] || [ -z "$RSYNC_SERVER" ] || [ -z "$RSYNC_DEST_DIR" ]; then
        echo "Error: Rsync post process script requires NAME, RSYNC_SERVER and RSYNC_DEST_DIR defined!"
        exit 0
    fi

    # The directory that will be rsync'd elsewhere
    local RSYNC_SOURCE_DIR="$BUILD/rsync/$NAME"
    mkdir -p "$RSYNC_SOURCE_DIR"

    # "Copy" kernel to prepare for rsync
    ln -sfrL export/*bzImage* "$RSYNC_SOURCE_DIR/."

    # compress the ext3/ext4 images which have lots of empty space
    local EXPORT_DIR=
    EXPORT_DIR=$(readlink -f export)
    find "$EXPORT_DIR" -type l -name "*ext[34]" \
         -exec /bin/bash -c "bzip2 -ck \"{}\" > \"{}\".bz2" \;

    # "Copy" compressed images to rsync dir
    find "$EXPORT_DIR" -name "*ext[34].bz2" \
         -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/." \;

    # "Copy" dtb file (arm only) to rsync dir
    find "$EXPORT_DIR" -name "*dtb" \
         -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/." \;

    if [ "$RSYNC_SSTATE" == "yes" ]; then
        mkdir -p "$RSYNC_SOURCE_DIR/sstate"
        # Skip the native sstate because it is already built and distributed
        find bitbake_build/sstate-cache/ -maxdepth 1 -mindepth 1 -type d \
             -name '[a-z0-9][a-z0-9]' -exec ln -sfrL {} "$RSYNC_SOURCE_DIR/sstate/." \;
    fi

    # Initial rsync copies symlinks to destination
    # Note: RSYNC_OPTIONS must be a bash array
    rsync -aL "$RSYNC_SOURCE_DIR" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"

    # Notify that rsync is complete
    local RSYNC_STAMP="$BUILD/00-RSYNC-$NAME"
    touch "$RSYNC_STAMP"
    rsync -aL "$RSYNC_STAMP" "rsync://${RSYNC_SERVER}/${RSYNC_DEST_DIR}/"

    touch "$STAMP"
}

post_rsync "$@" &>> "$(basename "$0").log"

exit 0
