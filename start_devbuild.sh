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

   --sdk-machine=<machine>

       Select the machine type used for the SDK build.
       Default: qemux86

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
       Default: windriver/ubuntu1604_64

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
    local REMOTE=
    REMOTE=$(git remote | tail -n 1)
    local URL=
    URL=$(git remote get-url "$REMOTE")
    if [ "${URL:0:6}" == 'git://' ]; then
        echo "${URL#git://*/}"
    elif [ "${URL:0:6}" == 'ssh://' ]; then
        echo "${URL#git://*/}"
    elif [ "${URL:0:4}" == 'git@' ]; then
        echo "${URL#*:}"
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
    local SDK=no
    local SDK_MACHINE=i686-mingw32
    local SDK_EXT=no
    local RECIPES=()
    local LOCALCONF=no
    local BUILD_IMAGE=
    local ARG=

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
            --distro=*|--distros=*)   ARG=${1#*=}; DISTROS=(${ARG/,/ }) ;;
            --distro|--distros)       ARG=$2; DISTROS=(${ARG/,/ }); shift ;;
            --machine=*|--machines=*) ARG=${1#*=}; MACHINES=(${ARG/,/ }) ;;
            --machine|--machines)     ARG=$2; MACHINES=(${ARG/,/ }); shift ;;
            --image=*|--images=*)     ARG=${1#*=}; IMAGES=(${ARG/,/ }) ;;
            --image|--images)         ARG=$2; IMAGES=(${ARG/,/ }); shift ;;
            --recipe=*|--recipes=*)   ARG=${1#*=}; RECIPES=(${ARG/,/ }) ;;
            --recipe|--recipes)       ARG=$2; RECIPES=(${ARG/,/ }); shift ;;
            --dry[-_]run)             DRY_RUN=yes ;;
            --sdk)                    SDK=yes ;;
            --sdk[-_]ext)             SDK_EXT=yes ;;
            --sdk[-_]machine=*)       SDK_MACHINE=${1#*=} ;;
            --sdk[-_]machine)         SDK_MACHINE=$2; shift ;;
            --localconf=*)            LOCALCONF=${1#*=} ;;
            --localconf)              LOCALCONF=$2; shift ;;
            --build[-_]image=*)       BUILD_IMAGE=${1#*=} ;;
            --build[-_]image)         BUILD_IMAGE=$2; shift ;;
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

    if [ "$SDK" == 'yes' ] && [ -z "$MACHINE" ]; then
        echo "SDK selected without specifying machine so qemux86 selected as SDK_MACHINE"
        MACHINE=qemux86
    fi

    if [ "$SDK_EXT" == 'yes' ] && [ -z "$MACHINE" ]; then
        echo "Extended SDK selected without specifying machine so qemux86 selected as SDK_MACHINE"
        MACHINE=qemux86
    fi

    if [ "$LOCALCONF" != 'no' ] && [ ! -f "$LOCALCONF" ]; then
        LOCALCONF="$BBPATH/conf/local.conf"
        if [ ! -f "$LOCALCONF" ]; then
            echo "Could not find valid local.conf at $LOCALCONF."
            exit 1
        fi
        echo "Could not find valid local.conf at $LOCALCONF. Using project $LOCALCONF"
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
        if [ ! -d "$TOP/wrlinux-x" ]; then
            echo "Unable to find wrlinux-x repo and could not determine release. Please set $RELEASE env variable"
            exit 1
        fi
        RELEASE=$(cut -d'/' -f 3 < "$TOP"/wrlinux-x/.git/HEAD)
    fi
    echo "Using release $RELEASE"

    echo "Searching layers in $TOP for local commits"
    local REPO=
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
            RANGE=$(git status -sb | cut -d' ' -f 2)
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
        echo "sdk_machine: $SDK_MACHINE"
        echo "build_image: $BUILD_IMAGE"
        echo "repos:"
    } >> "$DEVBUILD_ARGS"

    local PULL_TOP=
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

            local UPSTREAM=
            local RANGE=
            if [ "$BRANCH" == "HEAD" ]; then
                UPSTREAM=m/master
                RANGE=m/master..HEAD
            else
                UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}')
                RANGE=$(git status -sb | cut -d' ' -f 2)
            fi
            local PR_REPO=git://ala-lxgit.wrs.com/wrpush/"$GITOLITE_USER/${PUSH_LAYER##*/}"

            git request-pull "$UPSTREAM" "$PR_REPO" \
                    "$PUSH_RANGE" > "$PULL_REQ_FILE"

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

        echo "Starting devbuild on $SERVER/jenkins"
        curl -X POST -k -H "$CRUMB" --user "$APITOKEN" \
             --data-urlencode DEVBUILD_ARGS@"$DEVBUILD_ARGS" \
             --data-urlencode "$LOCALCONF_UPLOAD" \
             "$SERVER/jenkins/job/devbuilds/job/devbuild/buildWithParameters?$PARAMS"
    else
        echo "Dry run: copying devbuild config to devbuild.yaml"
        cp -f "$DEVBUILD_ARGS" devbuild.yaml
    fi

    rm -f "$DEVBUILD_ARGS"
}

main "$@"
