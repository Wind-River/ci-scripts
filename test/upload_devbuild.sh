#!/bin/bash
set -euo pipefail

main()
{
    local SERVER=https://ala-blade21.wrs.com
    local CI_REPO=git://ala-lxgit.wrs.com/projects/wrlinux-ci/ci-scripts
    local CI_BRANCH=master
    local DEVBUILD_ARGS=
    local LOCALCONF=no

    for i in "$@"
    do
        echo "Arg: $i"
        case $i in
            --server=*)         SERVER=${i#*=} ;;
            --ci_repo=*)        CI_REPO=${i#*=} ;;
            --ci_branch=*)      CI_BRANCH=${i#*=} ;;
            --localconf=*)      LOCALCONF=${i#*=} ;;
            --devbuild=*)       DEVBUILD_ARGS=${i#*=} ;;
            *)                  ;;
        esac
        shift
    done

    if [ "${SERVER:0:8}" != 'https://' ]; then
        SERVER="https://$SERVER"
    fi

    if [ ! -f "$DEVBUILD_ARGS" ]; then
        echo "Invalid file: $DEVBUILD_ARGS"
        exit 1
    fi

    if [ "$LOCALCONF" != 'no' ] && [ ! -f "$LOCALCONF" ]; then
        echo "Invalid conf file: $LOCALCONF"
        exit 1
    fi

    local APITOKEN=
    APITOKEN=$(curl -k -s "$SERVER/auth/build_auth.txt" | tr -d '\n')

    local CRUMB=
    CRUMB=$(curl -k -s --user "$APITOKEN" \
                 "$SERVER"/jenkins/crumbIssuer/api/xml?xpath='concat(//crumbRequestField,":",//crumb)' )

    local LOCALCONF_UPLOAD=LOCALCONF@/dev/null
    if [ -f "$LOCALCONF" ]; then
        LOCALCONF_UPLOAD=LOCALCONF@"$LOCALCONF"
    fi

    local PARAMS="token=devbuild&CI_REPO=$CI_REPO&CI_BRANCH=$CI_BRANCH"

    echo "Starting devbuild on $SERVER/jenkins"
    curl -X POST -k -H "$CRUMB" --user "$APITOKEN" \
         --data-urlencode DEVBUILD_ARGS@"$DEVBUILD_ARGS" \
         --data-urlencode "$LOCALCONF_UPLOAD" \
         "$SERVER/jenkins/job/devbuilds/job/devbuild/buildWithParameters?$PARAMS"
}

main "$@"
