#!/bin/bash
set -euo pipefail

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "This script requires bash version 4+"
    exit 1
fi

# workaround bash bug in <4.4 where empty array is considered unbound
# https://git.savannah.gnu.org/cgit/bash.git/tree/CHANGES?id=3ba697465bc74fab513a26dea700cc82e9f4724e#n878
if [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; then
    set +u
fi

# In a yocto buildarea, use bitbake to query active layers and
# determine if there are new commits on any of those layers. The new
# commits are staged on lxgit and a yaml structure with the info is
# sent to Jenkins
# Currently specific to WR

usage()
{
    cat <<USAGE
Usage: start_devbuild.sh [OPTIONS]

Detect local patches, upload those patches to lxgit and trigger builds
and runtime tests on Wrigel using those patches.

See: http://lpd-web.wrs.com/wr-process/master/WRLinux_CI_design.html

Build Customization Options:

     --distros=<comma separated list of distros>

        Select the distros used for the builds
        Default: wrlinux-graphics

    --machines=<comma separated list of machines>

        Select the machine types built for each distro
        Default: qemux86, qemux86-64, qemuarm64, qemuarm

   --images=<comma separated list of images>

       Select the image types for each build. The first image type
       will be used for runtime tests.
       Default depends on distro

   --recipes=<comma separated list of recipes>

       Select the recipes for each build. Note this overrides any
       images and disables runtime testing.

   --sdkmachine=<machine>

       Select the machine type used for the SDK build. Supports x86-64 or i686.
       Default: x86-64

   --sdk

       Build the SDK. No runtime tests or other builds are done

   --sdk-ext

       Build the extended SDK. No runtime tests or other builds are done

   --localconf=<file>

       Override the default local.conf with provided one. If the file
       cannot be found the local.conf from the buildarea will be
       used. Note that the build_configure.sh script will still be run.

   --build_image=<image>

       Select the container image used for the build stage.
       Images validated by Wraxl:
        - wr-docker-registry:5000/fedora28_64_py3
        - wr-docker-registry:5000/fedora29_64
        - wr-docker-registry:5000/opensuse151_64
        - wr-docker-registry:5000/ubuntu1604_64_py3
        - wr-docker-registry:5000/ubuntu1804_64
       Default: windriver/ubuntu1604_64

   --disable-test

       By default runtime testing is enabled for any bsp and image
       with support. This flag disables the runtime tests.

Development Options:

    --email=<email>

       Set the email address where build failure emails should be sent
       Default: git user.email config setting

    --server=<jenkins>

       Select the Wrigel Jenkins server for the devbuilds.
       Default: ala-blade21.wrs.com

    --ci-repo=<git repo>

       Select the ci-scripts git repo used for the devbuild setup
       Default: git://ala-lxgit.wrs.com/projects/wrlinux-ci/ci-scripts

    --ci-branch=<branch>

       Select the ci-scripts branch to be used.
       Default: master

    --no-upstream-check

       Do not check if the layers are up to date with upstream repositories.

    --dry-run

        Save the yaml file that would be sent to Jenkins to devbuild.yaml

Miscellaneous:

    -v, --verbose

        Enable more logging

    -h, --help

        Display this message and exit
USAGE
}

DRY_RUN=no
VERBOSE=0

log()
{
    if [ "$VERBOSE" -ne  0 ]; then echo "$@"; fi
}

get_current_branch()
{
    git rev-parse --abbrev-ref HEAD
}

# Ask bitbake for all the enabled layers in the project
get_bb_layers()
{
    bitbake -e | grep BBLAYERS= | cut -d= -f 2 | tr -d '"'
}

# Some layers share the same git repository. This will make a
# list of all the git repositories that store the active layers
# Only supports a single directory embedded in the repo
get_layer_repos()
{
    local BBLAYERS=
    BBLAYERS=$(get_bb_layers)

    local REPO_LAYERS=()
    local BBLAYER=
    for BBLAYER in $BBLAYERS; do
        if [ -f "${BBLAYER}/.git/HEAD" ]; then
            REPO_LAYERS+=($BBLAYER)
        elif [ -f "${BBLAYER}/../.git/HEAD" ]; then
            REPO_LAYERS+=($(readlink -f "${BBLAYER}/.."))
        fi
    done
    readarray -t REPO_LAYERS < <(printf '%s\0' "${REPO_LAYERS[@]}" | sort -zu | xargs -0n1)
    echo "${REPO_LAYERS[*]}"
}

# From inside a git repo, retrieve the repo path on the git server
get_remote_repo_path()
{
    local URL=

    URL=$(git remote -v | grep push | awk '{printf "%s", substr($2,0)}')
    if [ "${URL:0:6}" == 'git://' ]; then
        echo "${URL#git://*/}"
    elif [ "${URL:0:6}" == 'ssh://' ]; then
        echo "${URL#ssh://*/}"
    elif [ "${URL:0:4}" == 'git@' ]; then
        echo "${URL#*:}"
    fi
}

send_email()
{
    # check if git send-email has been installed
    git send-email --help >/dev/null 2>&1
    if [ $? != 0 ]; then
        echo "git-email is not installed!"
        echo "You can use 'apt-get install git-email' command to install it."
        exit 1
    fi

    local USER_EMAIL=$1
    local MAIL_BODY=$2
    local SMTPSERVER=prod-webmail.windriver.com

    # Build up set of --to addresses as bash array because it properly passes
    # sets of args to another program
    local ADDRESS=
    set -f; IFS=,
    for ADDRESS in $USER_EMAIL ; do
        TO_STR=("${TO_STR[@]}" --to "$ADDRESS")
    done
    set +f; unset IFS

    # git send-email requires .gitconfig at writable location and perl requires that
    # LANG is a valid locale. The postbuild image meets these requirements
    git config --global user.email "ci-scripts@windriver.com"
    git config --global user.name "CI"
    git send-email --from=ci-scripts@windriver.com --quiet --confirm=never \
        "${TO_STR[@]}" "--smtp-server=$SMTPSERVER" "$MAIL_BODY"
    if [ $? != 0 ]; then
        echo "git send fail email failed"
        exit 1
    fi
}


main()
{
    echo "Script Version: $(git --git-dir "$(readlink -f "${0%/*}"/.git)" rev-parse HEAD)"

    local SERVER=https://ala-blade21.wrs.com
    local CI_REPO=git://ala-lxgit.wrs.com/projects/wrlinux-ci/ci-scripts
    local CI_BRANCH=master
    local USER_EMAIL=
    USER_EMAIL=$(git config --global --get user.email)

    local DISTROS=()
    local MACHINES=()
    local IMAGES=()
    local SDK=false
    local SDKMACHINE=x86_64
    local SDK_EXT=false
    local RECIPES=()
    local LOCALCONF=no
    local BUILD_IMAGE=
    local ARG=
    local TEST=enable
    local CHECK_UPSTREAM=yes

    while [ $# -gt 0 ]; do
        case "$1" in
            --server=*)               SERVER=${1#*=} ;;
            --server)                 SERVER=$2; shift ;;
            --ci[-_]repo=*)           CI_REPO=${1#*=} ;;
            --ci[-_]repo)             CI_REPO=$2; shift ;;
            --ci[-_]branch=*)         CI_BRANCH=${1#*=} ;;
            --ci[-_]branch)           CI_BRANCH=$2; shift ;;
            --email=*)                USER_EMAIL=${1#*=} ;;
            --email)                  USER_EMAIL=$2; shift ;;
            --distro=*|--distros=*)   ARG=${1#*=}; DISTROS=(${ARG//,/ }) ;;
            --distro|--distros)       ARG=$2; DISTROS=(${ARG//,/ }); shift ;;
            --machine=*|--machines=*) ARG=${1#*=}; MACHINES=(${ARG//,/ }) ;;
            --machine|--machines)     ARG=$2; MACHINES=(${ARG//,/ }); shift ;;
            --image=*|--images=*)     ARG=${1#*=}; IMAGES=(${ARG//,/ }) ;;
            --image|--images)         ARG=$2; IMAGES=(${ARG//,/ }); shift ;;
            --recipe=*|--recipes=*)   ARG=${1#*=}; RECIPES=(${ARG//,/ }) ;;
            --recipe|--recipes)       ARG=$2; RECIPES=(${ARG//,/ }); shift ;;
            --dry[-_]run)             DRY_RUN=yes ;;
            --sdk)                    SDK=true ;;
            --sdk[-_]ext)             SDK_EXT=true ;;
            --sdk[-_]machine=*)       SDKMACHINE=${1#*=} ;;
            --sdk[-_]machine)         SDKMACHINE=$2; shift ;;
            --sdkmachine=*)           SDKMACHINE=${1#*=} ;;
            --sdkmachine)             SDKMACHINE=$2; shift ;;
            --localconf=*)            LOCALCONF=${1#*=} ;;
            --localconf)              LOCALCONF=$2; shift ;;
            --build[-_]image=*)       BUILD_IMAGE=${1#*=} ;;
            --build[-_]image)         BUILD_IMAGE=$2; shift ;;
            --no-upstream-check)      CHECK_UPSTREAM=no ;;
            --disable[-_]test)        TEST="disable"; shift ;;
            --wrlinux-x=*)            WRLINUX_X=${1#*=} ;;
            --wrlinux-x)              WRLINUX_X=$2; shift ;;
            -v|--verbose)             VERBOSE=1 ;;
            -h|--help)                usage; exit 0 ;;
            *)                        echo "Unrecognized arg $1."; usage; exit 1 ;;
        esac
        shift
    done

    # Must be able to run bitbake to get the active layers
    command -v bitbake >/dev/null 2>&1 || { echo >&2 "Could not find bitbake. Aborting."; exit 0; }

    if [ -z "$BBPATH" ]; then
        echo "Bitbake not enabled. Run oe-init-build-env."
        exit 1
    fi

    if [ "${SERVER:0:8}" != 'https://' ]; then
        SERVER="https://$SERVER"
    fi

    for RECIPE in "${RECIPES[@]}"; do
        if [ "${RECIPE:0:14}" == 'wrlinux-image-' ]; then
            echo "Detected recipe $RECIPE which starts with wrlinux-image- and is an image type."
            echo "Please rerun using the --images option instead"
            exit 1
        fi
    done

    if [ "$SDK" == 'true' ] || [ "$SDK_EXT" == 'true' ]; then
        if [ "$SDKMACHINE" != 'x86_64' ] && [ "$SDKMACHINE" != 'i686' ]; then
            echo "ERROR: Invalid SDKMACHINE specified: $SDKMACHINE"
            exit 1
        fi
    fi

    if [ "$SDK" == 'true' ] && [ "${#MACHINES[@]}" -eq 0 ]; then
        echo "SDK selected without specifying machine so qemux86-64 selected as MACHINE"
        MACHINES=(qemux86-64)
    fi

    if [ "$SDK_EXT" == 'true' ] && [ "${#MACHINES[@]}" -eq 0 ]; then
        echo "Extended SDK selected without specifying machine so qemux86-64 selected as MACHINE"
        MACHINES=(qemux86-64)
    fi

    if [ "$LOCALCONF" != 'no' ] && [ ! -f "$LOCALCONF" ]; then
        LOCALCONF="$BBPATH/conf/local.conf"
        if [ ! -f "$LOCALCONF" ]; then
            echo "Could not find valid local.conf at $LOCALCONF."
            exit 1
        fi
        echo "Could not find valid local.conf at $LOCALCONF. Using project $LOCALCONF"
    fi

    if [ -f "$LOCALCONF" ]; then
        if grep -q 'TEST_IMAGE' "$LOCALCONF"; then
            echo "Found TEST_IMAGE in $LOCALCONF. Wrigel devbuild uses testexport and does not support running tests using runqemu."
            exit 1
        fi
        if grep -q 'TEST_SUITES_forcevariable' "$LOCALCONF"; then
            echo "WARN: Found TEST_SUITES_forcevariable in $LOCALCONF. Wrigel devbuild uses testexport and some OEQA tests do not work using testexport."
        fi
    fi

    if [ -z "$USER_EMAIL" ]; then
        echo "Git config user.email is not set. Use --email to set email address to send results"
        echo "Since I don't know where to send results, dev build is cancelled."
        exit 1
    fi

    echo "Checking gitolite access"
    local GITOLITE_USER=
    GITOLITE_USER=$(ssh -o PasswordAuthentication=no git@ala-lxgit.wrs.com help 2> /dev/null | head -n 1 | cut -d' ' -f 2 | tr -d ',')

    if [ -n "$GITOLITE_USER" ]; then
        echo "Authenticated with git@lxgit as $GITOLITE_USER"
    else
        echo "Unable to authenticate with git@lxgit. Will run in dry-run mode"
        GITOLITE_USER=unknown
        DRY_RUN=yes
    fi

    echo "Retrieving available layers from bitbake"
    local REPOS=
    REPOS=$(get_layer_repos)

    local CURRENT_DIR=
    CURRENT_DIR=$(readlink -f "$PWD")
    export PUSH_LAYERS=()

    local BITBAKE_PATH=
    BITBAKE_PATH=$(command -v bitbake)
    BITBAKE_PATH=${BITBAKE_PATH%/*}

    # Since setup.sh will always put bitbake in a known location, use that to figure out
    # where wrlinux-x and the top of the source tree is
    local TOP=
    TOP=$(readlink -f "${BITBAKE_PATH}/../../../../")

    if [ "${RELEASE:-unset}" == 'unset' ]; then
        if [ -d "$WRLINUX_X" ]; then
            RELEASE=$(cut -d'/' -f 3 < "$WRLINUX_X"/.git/HEAD)
        elif [ -d "$TOP/wrlinux-x" ]; then
            echo "--wrlinux-x is not specified, trying $TOP/wrlinux-x."
            RELEASE=$(cut -d'/' -f 3 < "$TOP"/wrlinux-x/.git/HEAD)
        else
            echo "Unable to find wrlinux-x repo and could not determine release. Please set $RELEASE env variable"
            exit 1
        fi
    fi
    echo "Using release $RELEASE"

    local REPO=
    if [ "$CHECK_UPSTREAM" == 'yes' ]; then
        echo "Checking if layers are out of date"
        local UPTODATE=yes
        for REPO in $REPOS; do
            cd "$REPO"

            local ORIGINAL_BRANCH=
            ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref m/master)
            ORIGINAL_BRANCH="${ORIGINAL_BRANCH:5}"
            local BASE_URL=
            BASE_URL=$(git config remote.base.url)

            if [ "${BASE_URL:0:6}" == "git://" ] || [ "${BASE_URL:0:6}" == "ssh://" ] || [ "${BASE_URL:0:4}" == 'git@' ]; then
                local UPSTREAM_COMMIT=
                UPSTREAM_COMMIT=$(git ls-remote "$BASE_URL" "$ORIGINAL_BRANCH" | cut -f 1)

                # get the commit before local commits might have been added
                local LAST_SYNC_COMMIT=
                LAST_SYNC_COMMIT=$(git rev-parse m/master)

                if [ "$LAST_SYNC_COMMIT" != "$UPSTREAM_COMMIT" ]; then
                    echo "WARN: the repo $REPO is behind upstream. Upstream commit for $ORIGINAL_BRANCH is $UPSTREAM_COMMIT"
                    local UPTODATE=no
                fi
            fi

            cd "$CURRENT_DIR"
        done
        if [ "$UPTODATE" == 'no' ]; then
            echo
            echo "Detected repositories not up to date. It is recommended to sync the local buildarea"
            echo "to avoid devbuild build failures. Do you wish to continue anyways? [N/y]"
            read -r ans
            if [ "x$ans" != "xy" ] && [ "x$ans" != "xY" ] ; then
                exit 1
            fi
        fi
    fi

    echo "Searching layers in $TOP for local commits"
    for REPO in $REPOS; do
        cd "$REPO"
        log "Checking $REPO for commits"

        local COMMITS=
        local BRANCH=
        BRANCH=$(get_current_branch)

        local RANGE=
        if [ "$BRANCH" == "HEAD" ]; then
            set +e # need to check the return code
            if git rev-parse --abbrev-ref m/master &> /dev/null; then
                RANGE=m/master..HEAD
            else
                echo "$REPO has detached HEAD and repository wasn't setup with repo. Exiting"
                exit 1
            fi
            set -e
        else
            RANGE=$(git status --short --branch --untracked-files=no | cut -d' ' -f 2)
        fi

        COMMITS=$(git log --pretty=oneline "$RANGE" 2> /dev/null)
        if [ -n "$COMMITS" ]; then
            echo "Found following local commits on ${REPO#$TOP/}:"
            echo "$COMMITS"
            echo
            PUSH_LAYERS+=(${REPO})
        fi
        cd "$CURRENT_DIR"
    done

    if [ "${#PUSH_LAYERS[@]}" -eq 0 ]; then
        echo "No local commits on $TOP found."
        exit 0
    fi

    echo -n "Stage the above commits on lxgit and start devbuilds? [N/y] "
    read -r ans
    if [ "x$ans" != "xy" ] && [ "x$ans" != "xY" ] ; then
        exit 1
    fi

    local DEVBUILD_ARGS=
    DEVBUILD_ARGS=$(mktemp --tmpdir devbuild-XXXXXXXXX)
    function finish {
        rm -f "$DEVBUILD_ARGS"
    }
    trap finish EXIT

    {
        echo "---"
        echo "release: $RELEASE"
        echo "email: $USER_EMAIL"
        echo "distros:"
        for DISTRO in "${DISTROS[@]}"; do
            echo "- $DISTRO"
        done
        echo "machines:"
        for MACHINE in "${MACHINES[@]}"; do
            echo "- $MACHINE"
        done
        echo "images:"
        for IMAGE in "${IMAGES[@]}"; do
            echo "- $IMAGE"
        done
        echo "recipes:"
        for RECIPE in "${RECIPES[@]}"; do
            echo "- $RECIPE"
        done
        echo "sdk: $SDK"
        echo "sdk_ext: $SDK_EXT"
        echo "sdkmachine: $SDKMACHINE"
        echo "build_image: $BUILD_IMAGE"
        echo "test: $TEST"
        echo "repos:"
    } >> "$DEVBUILD_ARGS"

    PULL_TOP=$(mktemp --tmpdir -d "pull-requests-${GITOLITE_USER}.XXXXXXXXXX")
    function finish2 {
        rm -rf "$PULL_TOP"
    }
    trap finish2 EXIT

    local NOW=
    NOW=$(date +%Y%m%d-%H%M)

    for PUSH_LAYER in "${PUSH_LAYERS[@]}"; do
        (
            cd "$PUSH_LAYER"
            log "Creating fork $PUSH_LAYER on lxgit"

            local SERVER_REPO_PATH=
            SERVER_REPO_PATH=$(get_remote_repo_path)
            ssh git@ala-lxgit.wrs.com wrfork "$SERVER_REPO_PATH"

            local BRANCH=
            BRANCH=$(get_current_branch)

            local PULL_REQ_FILE=
            PULL_REQ_FILE=$(mktemp -p "${PULL_TOP}" "pull-${PUSH_LAYER##*/}-$BRANCH-$NOW-XXXXXXXXXX")
            local PULL_REQ=${PULL_REQ_FILE##*/}

            local PUSH_RANGE="${BRANCH}:refs/heads/$PULL_REQ"

            git push git@ala-lxgit.wrs.com:wrpush/"$GITOLITE_USER/${PUSH_LAYER##*/}" "$PUSH_RANGE"

            local RANGE=
            if [ "$BRANCH" == "HEAD" ]; then
                RANGE=m/master..HEAD
            else
                RANGE=$(git status -sb | cut -d' ' -f 2)
            fi
            local PR_REPO=git://ala-lxgit.wrs.com/wrpush/"$GITOLITE_USER/${PUSH_LAYER##*/}"

            # if the git repo contains multiple layers then _all_ the layers in that repo
            # need to be updated on the layerindex
            local LAYERS=()

            # look for more layer.conf files in subdirectory and use the base as the layer name
            LAYERS=($(find . -maxdepth 3 -path './*/conf/layer.conf' -printf '%P ' | sed 's#/conf/layer.conf##g'))

            # if there is a conf/layer.conf file, then the current dir is a layer
            if [ -f 'conf/layer.conf' ]; then
                LAYERS+=(${PUSH_LAYER##*/})
            fi

            # special case for oe-core which is a layer in a meta directory but has a
            # different name in the layerindex
            if [ "${PUSH_LAYER##*/}" == 'oe-core' ]; then
                LAYERS+=('openembedded-core')
                # setup assumes bitbake and oe-core are on the same server
                ssh git@ala-lxgit.wrs.com wrfork bitbake
            fi

            # remove duplicate layers
            readarray -t LAYERS < <(printf '%s\0' "${LAYERS[@]}" | sort -zu | xargs -0n1)

            {
                echo "- dir: ${PUSH_LAYER#$TOP/}"
                echo "  repo: $PR_REPO"
                echo "  branch: $PULL_REQ"
                echo "  layers:"
                local LAYER=
                for LAYER in "${LAYERS[@]}"; do
                    echo "    - $LAYER"
                done
            } >> "$DEVBUILD_ARGS"
        )
        echo
    done

    if [ "$DRY_RUN" == 'no' ]; then
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

        KEYS=$(mktemp --tmpdir -d devbuild-keys-XXXXXXXXX)
        function finish {
            rm -rf "$KEYS"
        }
        trap finish EXIT

        # submit devbuild job
        curl --dump-header "$KEYS/headers" -X POST -k -H "$CRUMB" --user "$APITOKEN" \
             --data-urlencode DEVBUILD_ARGS@"$DEVBUILD_ARGS" \
             --data-urlencode "$LOCALCONF_UPLOAD" \
             "$SERVER/jenkins/job/devbuilds/job/devbuild/buildWithParameters?$PARAMS"

        local QUEUE=
        # the headers have a line feed character embedded in it
        QUEUE=$(grep Location: "$KEYS/headers" | awk '{print $2}' | tr -d '\r')

        echo "Waiting for submiting devbuild job to complete"
        local JOB=
        while :
        do
            sleep 5
            echo "Checking if queued devbuild Job has been scheduled"
            JOB=$(curl --insecure --silent --show-error "${QUEUE}api/xml?tree=executable\[url\]" || true)
            if [[ "$JOB" == *"job/devbuilds/"* ]]; then
                break
            fi
        done

        # extract job url from queue status and then strip tags
        JOB=$(echo "$JOB" | grep -o '<url>.*</url>' )
        JOB="${JOB:5:(-6)}"

        # get new DevBuild Id
        local DEVBUILD_ID=
        local DEVBUILD_JSON=
        local DEVBUILD_CONSOLE_LOG=

        DEVBUILD_ID=$(wget --no-check-certificate -qO- "${JOB}/buildNumber")

        for i in {1..12}
        do
            DEVBUILD_JSON=$(wget --no-check-certificate -qO- "${JOB}/api/xml?tree=result")
            if [[ "$DEVBUILD_JSON" == *"SUCCESS"* ]]; then
                echo "New DevBuild job created: $JOB"
                DEVBUILD_CONSOLE_LOG=$(wget --no-check-certificate -qO- "${JOB}/consoleText")
                break
            elif [[ "$i" == 12 ]]; then
                echo "DevBuild job was not created or failed!"
                exit -1
            else
                echo "Submitting build jobs have not been done, wait for 10 seconds ..."
                sleep 10
            fi
        done

        if [ ! -z "$DEVBUILD_CONSOLE_LOG" ]; then
            # DevBuild job(s) have been launched
            local START_SECOND=$(date '+%s')
            local START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
            local MATCHES=
            local POSTPROCESS_ARGS=()
            local ARGS=()
            local ARG=

            # get POSTPROCESS_ARGS from DevBuild console log, such as HTTP_ROOT, RSYNC_DEST_DIR
            MATCHES=$(echo "$DEVBUILD_CONSOLE_LOG" | grep "POSTPROCESS_ARGS: " | sed "s/POSTPROCESS_ARGS: //g")
            POSTPROCESS_ARGS=($MATCHES[0])
            ARGS=(${POSTPROCESS_ARGS//,/ })
            for ARG in "${ARGS[@]}"
            do
                if [[ "$ARG" == *"HTTP_ROOT"* ]] || [[ "$ARG" == *"RSYNC_DEST_DIR"* ]]; then
                    eval "$ARG"
                fi
            done

            # get build names within this DevBuild
            MATCHES=$(echo "$DEVBUILD_CONSOLE_LOG" | grep "NAME: " | sed "s/NAME: //g")
            local NAMES=($MATCHES)
            local NUMBER_OF_BUILDS=${#NAMES[@]}

            # get WRLinux_Build id of each build name
            local LAST_BUILD_ID=$(wget --no-check-certificate -qO- "${SERVER}/jenkins/job/WRLinux_Build/lastBuild/buildNumber")
            local BUILD_ID=
            local BUILD_NAME=
            local BUILD_IDS=()
            local BUILD_JSON=()
            MATCHES=0
            # try to check more builds in Jenkins in case other builds are launched at the same time
            for x in $(seq 0 $((NUMBER_OF_BUILDS+50)))
            do
                BUILD_ID=$((LAST_BUILD_ID - x))
                BUILD_JSON[$x]=$(wget --no-check-certificate -qO- "${SERVER}/jenkins/job/WRLinux_Build/${BUILD_ID}/api/json")
                for y in $(seq 0 $((NUMBER_OF_BUILDS-1)))
                do
                    BUILD_NAME="${NAMES[$y]}"
                    if [[ "${BUILD_JSON[$x]}" =~ "$BUILD_NAME"'"}' ]]; then
                        BUILD_NAMES[$x]="$BUILD_NAME"
                        BUILD_IDS[$x]="$BUILD_ID"
                        MATCHES=$((MATCHES+ 1))
                        break
                    fi
                done
                if [[ "$MATCHES" == "$NUMBER_OF_BUILDS" ]]; then
                    break
                fi
            done

            # track all builds, show progress of each build
            local CURRENT_TIME=
            local END_SECOND=
            local END_TIME=
            local FINISHED=
            local CONSOLE_LOG=
            local LAST_LINE=
            local RESULTS=()
            while true
            do
                clear
                CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
                echo "Tracking progress - $CURRENT_TIME"
                FINISHED=0
                for x in $(seq 0 $((NUMBER_OF_BUILDS-1)))
                do
                    CONSOLE_LOG=$(wget --no-check-certificate -qO- "${SERVER}/jenkins/job/WRLinux_Build/${BUILD_IDS[$x]}/consoleText")
                    LAST_LINE=${CONSOLE_LOG##*$'\n'}
                    if [[ "$LAST_LINE" == 'Finished: SUCCESS' ]] ||
                       [[ "$LAST_LINE" == 'Finished: FAILURE' ]] ||
                       [[ "$LAST_LINE" == 'Finished: ABORTED' ]]; then
                        FINISHED=$((FINISHED + 1))
                        RESULTS[$x]=${LAST_LINE//Finished: /}
                    fi
                    echo "$x: "
                    echo -e " - Build Name  : ${BUILD_NAMES[$x]}"
                    echo -e " - Jenkins Job : ${SERVER}/jenkins/job/WRLinux_Build/${BUILD_IDS[$x]}"
                    echo -e " - Tail of log : ${LAST_LINE}"
                    echo ""
                done
                if [[ "$FINISHED" == "$NUMBER_OF_BUILDS" ]]; then
                    END_SECOND=$(date '+%s')
                    END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
                    break
                fi
                sleep 30
            done

            # generate summary and send report email
            local DEVBUILD_SUMMARY=devbuild_summary.log
            {
                echo "Subject: Devbuild #${DEVBUILD_ID} Finished"
                echo ""
                echo "Information:"
                echo " - Jenkins job : ${SERVER}/jenkins/job/devbuilds/job/devbuild/${DEVBUILD_ID}"
                echo " - Artifacts   : ${HTTP_ROOT}/${RSYNC_DEST_DIR}"
                echo " - Start time  : $START_TIME ($START_SECOND)"
                echo " - Finish time : $END_TIME ($END_SECOND)"
                echo " - Spent (sec) : $((END_SECOND - START_SECOND))"
                echo ""
                echo "Details:"
                for x in $(seq 0 $((NUMBER_OF_BUILDS-1)))
                do
                    echo "$x: "
                    echo -e " - Build Name  : ${BUILD_NAMES[$x]}"
                    echo -e " - Jenkins Job : ${SERVER}/jenkins/job/WRLinux_Build/${BUILD_IDS[$x]}"
                    echo -e " - Test Result : ${RESULTS[$x]}"
                    echo ""
                done
            } > "$DEVBUILD_SUMMARY"

            pwd
            cat "$DEVBUILD_SUMMARY"

            send_email "$USER_EMAIL" "$DEVBUILD_SUMMARY"

        else
            echo "DevBuild job is empty, something is wrong!"
            exit 1
        fi

    else
        echo "Dry run: copying devbuild config to devbuild.yaml"
        cp -f "$DEVBUILD_ARGS" devbuild.yaml
    fi

    rm -f "$DEVBUILD_ARGS"
}

main "$@"
