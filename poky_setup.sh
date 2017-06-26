#!/bin/bash

# print all env variables from mesos or local environment
env

source "$(dirname "$0")"/common.sh

TOP=/home/wrlbuild
BRANCH=pyro
SDKARCH=${SDKARCH:-$(uname -m)}

echo "Command: $0"
for i in "$@"
do
    echo "Arg: $i"
    case $i in
        --top=*)                TOP=${i#*=} ;;
        --branch=*)             BRANCH=${i#*=} ;;
        *)                      ;;
    esac
    shift
done

git clone --branch "$BRANCH" --single-branch git://git.yoctoproject.org/poky
mv poky/* .

BUILDTOOLS=$(curl -s -L https://raw.githubusercontent.com/WindRiver-Labs/wrlinux-9/WRLINUX_9_BASE/data/environment.d/04_wrl_buildtools.sh | grep BUILDTOOLS_REMOTE: | cut -d'-' -f 2- | cut -d'}' -f 1)

#BUILDTOOLS_REMOTE="https://github.com/WindRiver-Labs/$BUILDTOOLS"
BUILDTOOLS_REMOTE="$TOP/wrlinux-WRLINUX_9_BASE/$BUILDTOOLS"

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
