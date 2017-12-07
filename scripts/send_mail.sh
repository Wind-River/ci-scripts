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

send_mail()
{
    local BUILD="$1"
    local TOP="$2"

    # for generate_mail function
    source "$TOP/common.sh"

    # email addresses come as comma separated list
    if [ -z "$EMAIL" ]; then
        echo "No one wants this email"
        exit 0
    fi
    if [ -z "$SMTPSERVER" ]; then
        echo "Do not know where to send the email"
        exit 0
    fi

    command -v git >/dev/null 2>&1 || { echo >&2 "git required. Aborting."; exit 0; }

    if [ ! -f "$BUILD/mail.txt" ]; then
        echo "Generating mail"
        generate_mail "$BUILD"
    fi

    echo "Send build failure email for $BUILD"

    # Build up set of --to addresses as bash array because it properly passes
    # sets of args to another program
    local ADDRESS=
    set -f; IFS=,
    for ADDRESS in $EMAIL ; do
        TO_STR=("${TO_STR[@]}" --to "$ADDRESS")
    done
    set +f; unset IFS

    # git send-email requires .gitconfig at writable location and perl requires that
    # LANG is a valid locale. The postbuild image meets these requirements
    git config --global user.email "ci-scripts@windriver.com"
    git config --global user.name "CI"
    git send-email --from=ci-scripts@windriver.com --quiet --confirm=never \
        "${TO_STR[@]}" "--smtp-server=$SMTPSERVER" "$BUILD/mail.txt"
    if [ $? != 0 ]; then
        echo "git send fail email failed"
        exit 1
    fi
}

send_mail "$@"

exit 0
