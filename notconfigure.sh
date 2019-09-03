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

LOCALCONF=conf/local.conf

if [ ! -f "$LOCALCONF" ]; then
    echo "ERROR: conf/local.conf not found"
    exit 1
fi

KERNEL_TYPE=
TARGET_SUPPORTED_KTYPE=
RM_WORK=yes
PKG_JOBS=
JOBS=
BOOTIMAGE=
BUILDSTATS=yes
PATCHRESOLVE=
BUILDTYPE=
SYSTEM_INIT=
PKGS=
WHITELIST_PKGS=
WHITELIST_INTEL_PKGS=
PKG_MANAGER=
LICENSE_BLACKLIST=
DEBUGINFO_SPLIT=
ALLOW_BSP_PKGS=
TEST_IMAGE=no
OE_TEST=no
TEST_SUITES=
BB_NO_NETWORK=
PREMIRROR_PATH=
DL_DIR=
MACHINE=
SHARED_SSTATE_DIR=

for i in "$@"
do
    case $i in
        --kernel-type=*)        KERNEL_TYPE="${i#*=}" ;;
        --target-supported-ktype=*)          TARGET_SUPPORTED_KTYPE="${i#*=}" ;;
        --rm_work=*)            RM_WORK="${i#*=}" ;;
        --parallel_pkgbuilds=*) PKG_JOBS="${i#*=}" ;;
        --jobs=*)               JOBS="${i#*=}" ;;
        --buildstats=*)         BUILDSTATS="${i#*=}" ;;
        --patchresolve=*)       PATCHRESOLVE="${i#*=}" ;;
        --enable-bootimage=*)   BOOTIMAGE="${i#*=}" ;;
        --enable-build=*)       BUILDTYPE="${i#*=}" ;;
        --with-init=*)          SYSTEM_INIT="${i#*=}" ;;
        --with-package=*)       PKGS="${i#*=}" ;;
        --whitelist-package=*)  WHITELIST_PKGS="${i#*=}" ;;
        --whitelist-intel-package=*)         WHITELIST_INTEL_PKGS="${i#*=}" ;;
        --enable-package-manager=*)          PKG_MANAGER="${i#*=}" ;;
        --with-license-flags-blacklist=*)    LICENSE_BLACKLIST="${i#*=}" ;;
        --with-license-blacklist=*)          LICENSE_BLACKLIST="${i#*=}" ;;
        --enable-debuginfo-split=*)          DEBUGINFO_SPLIT="${i#*=}" ;;
        --allow-bsp-pkgs=*)     ALLOW_BSP_PKGS="${i#*=}" ;;
        --test-image=*)         TEST_IMAGE="${i#*=}" ;;
        --oe-test=*)            OE_TEST="${i#*=}" ;;
        --oe-test-suites=*)     OE_TEST_SUITES="${i#*=}" ;;
        --no-network=*)         BB_NO_NETWORK="${i#*=}" ;;
        --premirror_path=*)     PREMIRROR_PATH="${i#*=}" ;;
        --dl_dir=*)             DL_DIR="${i#*=}" ;;
        --machine=*)            MACHINE="${i#*=}" ;;
        --enable-shared-sstate=*) SHARED_SSTATE_DIR="${i#*=}" ;;
        *)                      ;;
    esac
    shift
done

# process --enable-build
process_buildtype(){
    local buildtype=$1
    case $buildtype in
        debug)
            echo "SELECTED_OPTIMIZATION = \"\${DEBUG_OPTIMIZATION}\""
            echo "DEBUG_BUILD = \"1\""
            ;;
        profiling)
            echo "SELECTED_OPTIMIZATION = \"\${PROFILING_OPTIMIZATION}\""
            ;;
        production|productiondebug)
            ;;
        esac

    if [ "$BUILDTYPE" != "production" ]; then
        echo "EXTRA_IMAGE_FEATURES += \"dbg-pkgs\""
    fi
}

# process --with-init
process_init(){
    sed -e 's!^VIRTUAL-RUNTIME_init_manager = "systemd"!#VIRTUAL-RUNTIME_init_manager = "systemd"!g' \
        -e 's!^DISTRO_FEATURES_append = " systemd"!#DISTRO_FEATURES_append = " systemd"!g' \
        -e 's!^DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"!#DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"!g' \
        -e 's!^KERNEL_FEATURES_append = " cfg/systemd.scc"!#KERNEL_FEATURES_append = " cfg/systemd.scc"!g' \
        -i $LOCALCONF
}

# process --enable-bootimage
process_bootimage(){
    local bootimage=$1
    local do_uboot=0

    for i in ${bootimage//,/ } ; do
        case ${i} in
        tar.gz|tar.bz2|jffs2|vmdk)
            echo "IMAGE_FSTYPES += \"${i}\""
            ;;
        iso)
            echo "IMAGE_FSTYPES += \"live\""
            ;;
        hdd)
            echo "IMAGE_FSTYPES += \"ext3\""
            ;;
        hddimg)
            echo "IMAGE_FSTYPES += \"hddimg\""
            ;;
        ext2|ext3|ext4)
            echo "IMAGE_FSTYPES += \"${i}\""
            ;;
        ubifs)
            echo "IMAGE_FSTYPES += \"ubifs\""
            echo "MKUBIFS_ARGS ?= \"-m 2048 -e 129024 -c 1996\""
            ;;
        cpio|cpio.gz)
            echo "IMAGE_FSTYPES += \"cpio.gz\""
            ;;
        noimage)
            echo "IMAGE_FSTYPES_forcevariable = \"\""
            ;;
        *u-boot)
            do_uboot=1
            echo "IMAGE_FSTYPES += \"${i}\""
            ;;
        esac

        if [ "$do_uboot" != "0" ] ; then
            echo "IMAGE_CLASSES += \"image_types_uboot\""
        fi
    done
}

# process --with-package
process_package(){
    local packages=$1
    for i in ${packages//,/ } ; do
        echo "IMAGE_INSTALL_append = \" $i\""
    done
}

process_whitelist(){
    local packages=$1
    for i in ${packages//,/ } ; do
        echo "PNWHITELIST_openembedded-layer += \"$i\""
    done
}

process_whitelist_intel(){
    local packages=$1
    for i in ${packages//,/ } ; do
        echo "PNWHITELIST_intel += \"$i\""
    done
}

{
    if [ -n "$KERNEL_TYPE" ]; then
        echo "PREFERRED_PROVIDER_virtual/kernel = \"$KERNEL_TYPE\""
    fi

    if [ -n "$TARGET_SUPPORTED_KTYPE" ]; then
        echo "TARGET_SUPPORTED_KTYPES_append  = \" $TARGET_SUPPORTED_KTYPE\""
    fi

    if [ "$RM_WORK" == "yes" ]; then
        echo "INHERIT += \"rm_work\""
    fi

    if [ -n "$JOBS" ]; then
        echo "PARALLEL_MAKE = \"-j $JOBS\""
    fi

    if [ -n "$PKG_JOBS" ]; then
        echo "BB_NUMBER_THREADS = \"$PKG_JOBS\""
    fi

    if [ "$BUILDSTATS" == "yes" ]; then
        echo "USER_CLASSES += \"buildstats buildstats-summary\""
    fi

    if [ -n "$PATCHRESOLVE" ]; then
        echo "PATCHRESOLVE = \"$PATCHRESOLVE\""
    fi

    if [ -n "$BOOTIMAGE" ]; then
        process_bootimage "$BOOTIMAGE"
    fi

    if [ -n "$BUILDTYPE" ]; then
        process_buildtype "$BUILDTYPE"
    fi

    if [ -n "$PKGS" ]; then
        process_package "$PKGS"
    fi

    if [ -n "$WHITELIST_PKGS" ]; then
        process_whitelist "$WHITELIST_PKGS"
    fi

    if [ -n "$WHITELIST_INTEL_PKGS" ]; then
        process_whitelist_intel "$WHITELIST_INTEL_PKGS"
    fi

    if [ -n "$DEBUGINFO_SPLIT" ] && [ "$DEBUGINFO_SPLIT" == "no" ]; then
        echo "INHIBIT_PACKAGE_DEBUG_SPLIT = \"1\""
    fi

    if [ -n "$PKG_MANAGER" ]; then
        echo "PACKAGE_CLASSES = \"package_${PKG_MANAGER}\""
    fi

    if [ -n "$LICENSE_BLACKLIST" ]; then
        echo "INCOMPATIBLE_LICENSE += \"${LICENSE_BLACKLIST//,/ }\""
    fi

    if [ -n "$ALLOW_BSP_PKGS" ]; then
        echo "ALLOW_BSP_PKGS = \"$ALLOW_BSP_PKGS\""
    fi

    if [ "$TEST_IMAGE" == "yes" ]; then
        echo "TEST_IMAGE = \"1\""

        # Give the mips qemu more time to boot
        echo "TEST_QEMUBOOT_TIMEOUT = \"1500\""

        # If live image type is specified, testimage attempts to test the initramfs
        # which hangs and fails
        echo "IMAGE_FSTYPES_remove = \"live\""
    fi

    if [ -n "$OE_TEST" ] && [ "$OE_TEST" != "no" ]; then
        echo "INHERIT += \"testexport\""

        if [ "$OE_TEST" == "with_wrlinux9" ]; then
            # Make sure OE test has python3 library, this is for WRL9
            echo "IMAGE_INSTALL_append += \"python3-pip\""
        elif [ "$OE_TEST" == "with_wrlinux10" ]; then
            # Make sure OE test has python3 library, this is for WRL10
            echo "IMAGE_INSTALL_append += \"python3-pkgutil\""
            echo "IMAGE_INSTALL_append += \"python3-unittest\""
            echo "IMAGE_INSTALL_append += \"python3-multiprocessing\""
        fi
    fi

    if [ -n "$OE_TEST" ] && [ "$OE_TEST" != "no" ]; then
        # Setup target and server IP address
        echo "TEST_TARGET_IP = \"localhost\""
        echo "TEST_SERVER_IP = \"localhost\""

        if [ -z "$OE_TEST_SUITES" ]; then
            echo "TEST_SUITES = \"ping ssh df date scp pam perl python rpm\""
        else
            echo "TEST_SUITES = \"$(echo $OE_TEST_SUITES | sed 's/,/\ /g')\""
        fi
    fi

    if [ -n "$PREMIRROR_PATH" ]; then
        # echo does not expand the \n which is required for the PREMIRROR syntax to work
        echo "PREMIRRORS_append = \" .*://.*/.* file://${PREMIRROR_PATH}/downloads/ \n git://.*/.* git://${PREMIRROR_PATH}/git/MIRRORNAME;protocol=file \n \""
        echo "BB_FETCH_PREMIRRORONLY = \"1\""
    fi

    if [ -n "$DL_DIR" ]; then
        echo "DL_DIR = \"$WORKSPACE/../$DL_DIR/\""
    fi

    if [ -n "$MACHINE" ]; then
        echo "MACHINE = \"$MACHINE\""
    fi

    if [ -n "$SHARED_SSTATE_DIR" ]; then
        echo "SSTATE_DIR = \"$WORKSPACE/../$SHARED_SSTATE_DIR/\""
    fi
} >> "$LOCALCONF"

if [ -n "$BB_NO_NETWORK" ]; then
    sed -i '/BB_NO_NETWORK/d' "$LOCALCONF"
    echo "BB_NO_NETWORK = \"${BB_NO_NETWORK}\"" >> "$LOCALCONF"
fi

if [ -n "$SYSTEM_INIT" ] && [ "$SYSTEM_INIT" == "sysvinit" ]; then
    process_init
fi
