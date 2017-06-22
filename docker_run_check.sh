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

# This script checks to see if docker can run without permission errors
# If not it prints a diagnostic and attempts to set world rw permissions
# on /var/run/docker.sock and tries again.

docker info
if [ $? != 0 ]; then
    echo "Unable to run 'docker info'."
    GID=$(stat -c '%g' /var/run/docker.sock)
    PERMS=$(stat -c '%A' /var/run/docker.sock)
    echo "/var/run/docker.sock has GID $GID with file permissions $PERMS"
    echo "Either add UID 1000 to group $GID or give world RW permissions to /var/run/docker.sock"
    echo "Attempting to add world rw permissions to /var/run/docker.sock"
    sudo chmod 666 /var/run/docker.sock
    docker info
    if [ $? != 0 ]; then
        echo "Unable to run 'docker info' even after changing permissions. Aborting."
        exit 1
    fi
fi
echo "Docker info successful. Proceeding with build."
exit 0
