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

if [ -z "$BRANCH" ]; then
    BRANCH=master
fi
SDKARCH=${SDKARCH:-$(uname -m)}
WR_LX_SETUP=git://github.com/Wind-River/wr-lx-setup.git

git clone --single-branch --branch "$BRANCH" "$WR_LX_SETUP" setup 2>&1

BUILDTOOLS=$(curl -s -L https://raw.githubusercontent.com/WindRiver-Labs/wrlinux-9/WRLINUX_9_BASE/data/environment.d/04_wrl_buildtools.sh | grep BUILDTOOLS_REMOTE: | cut -d'-' -f 2- | cut -d'}' -f 1)

BUILDTOOLS_REMOTE="$WORKSPACE/wrlinux-WRLinux-9-Base/$BUILDTOOLS.git"
if [ ! -d "$BUILDTOOLS_REMOTE" ]; then
    BUILDTOOLS_REMOTE="https://github.com/WindRiver-Labs/$BUILDTOOLS"
fi

git clone "$BUILDTOOLS_REMOTE" buildtools

mkdir bin

BUILDTOOLSSDK=$(find buildtools -name "${SDKARCH}-buildtools-nativesdk-standalone-*.sh" 2>/dev/null | sort | head -n1)
if [ -z "${BUILDTOOLSSDK}" ]; then
	echo "Unable to find buildtools-nativesdk-standalone archive for ${SDKARCH}." >&2
	echo >&2
    exit 1
fi
${BUILDTOOLSSDK} -d bin/buildtools -y

ENVIRON=$(find -L bin/buildtools -name "environment-setup-${SDKARCH}-*-linux" | head -n1)
if [ -z "${ENVIRON}" ]; then
	echo "Error unable to load buildtools environment-setup file." >&2
	exit 1
fi
ln -sf "$ENVIRON" .
. "./$ENVIRON"

# When doing devbuilds, setup needs to use the local layerindex
if [ -n "$DEVBUILD_LAYER_NAME" ]; then
    sed -i "s#http://layers.openembedded.org/layerindex/api/#http://layerindex:5000/layerindex/api/#" setup/bin/settings.py
fi

# drop first param which is name of this script
shift
./setup/setup.sh "$@"
