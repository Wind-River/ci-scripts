#!/bin/bash
set -euo pipefail

# In a yocto buildarea, use bitbake to query active layers and
# determine if there are new commits on any of those layers. The new
# commits are staged on lxgit and a yaml structure with the info is
# sent to Jenkins
# Currently specific to WR

DRY_RUN=no

if [ "${SERVER:-unset}" == 'unset' ]; then
    SERVER=https://ala-blade21.wrs.com
fi

if [ "${SERVER:0:8}" != 'https://' ]; then
    SERVER="https://$SERVER"
fi

if [ "${CI_REPO:-unset}" == 'unset' ]; then
    CI_REPO=git://ala-lxgit.wrs.com/projects/wrlinux-ci/ci-scripts
fi

if [ "${CI_BRANCH:-unset}" == 'unset' ]; then
    CI_BRANCH=master
fi

get_current_branch()
{
    git rev-parse --abbrev-ref HEAD
}

# Ask bitbake for all the enabled layers in the project
get_bb_layers()
{
    if [ -z "$BBPATH" ]; then
        echo "Bitbake not enabled. Run oe-init-build-env."
        exit 1
    fi
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

run_cmd()
{
    local CMD=($@)
    if [ "$DRY_RUN" == "yes" ]; then
        echo "Would run: ${CMD[*]}"
    else
        echo "Running ${CMD[*]}"
        "${CMD[@]}"
    fi
}

run_mktemp()
{
    local CMD=($@)
    if [ "$DRY_RUN" == "yes" ]; then
        mktemp --dry-run "${CMD[@]}"
    else
        mktemp "${CMD[@]}"
    fi
}

main()
{
    # Must be able to run bitbake to get the active layers
    command -v bitbake >/dev/null 2>&1 || { echo >&2 "Could not find bitbake. Aborting."; exit 0; }

    local USER_EMAIL=
    USER_EMAIL=$(git config --global --get user.email)
    if [ -z "$USER_EMAIL" ]; then
        echo "Git config user.email is not set."
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
    BITBAKE_PATH=$(which bitbake)
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

        local COMMITS=
        local BRANCH=
        BRANCH=$(get_current_branch)

        local RANGE=
        if [ "$BRANCH" == "HEAD" ]; then
            if git rev-parse --abbrev-ref m/master &> /dev/null; then
                RANGE=m/master..HEAD
            else
                echo "$REPO has detached HEAD and repository wasn't setup with repo. Exiting"
                exit 1
            fi
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

    local DEVBUILD_YAML=
    DEVBUILD_YAML=$(run_mktemp --tmpdir devbuild-XXXXXXXXX)

    {
        echo "---"
        echo "release: $RELEASE"
        echo "email: $USER_EMAIL"
        echo "repos:"
    } >> "$DEVBUILD_YAML"

    local PULL_TOP=
    PULL_TOP=$(run_mktemp --tmpdir -d "pull-requests-${GITOLITE_USER}.XXXXXXXXXX")
    local NOW=
    NOW=$(date +%Y%m%d-%H%M)

    for PUSH_LAYER in "${PUSH_LAYERS[@]}"; do
        (
            cd "$PUSH_LAYER"

            local SERVER_REPO_PATH=
            SERVER_REPO_PATH=$(get_remote_repo_path)
            run_cmd ssh git@ala-lxgit.wrs.com wrfork "$SERVER_REPO_PATH"

            local BRANCH=
            BRANCH=$(get_current_branch)

            local PULL_REQ_FILE=
            PULL_REQ_FILE=$(run_mktemp -p "${PULL_TOP}" "pull-${PUSH_LAYER##*/}-$BRANCH-$NOW-XXXXXXXXXX")
            local PULL_REQ=${PULL_REQ_FILE##*/}

            local PUSH_RANGE="${BRANCH}:refs/heads/$PULL_REQ"

            run_cmd git push git@ala-lxgit.wrs.com:wrpush/"$GITOLITE_USER/${PUSH_LAYER##*/}" "$PUSH_RANGE"

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

            run_cmd git request-pull "$UPSTREAM" "$PR_REPO" \
                    "$PUSH_RANGE" > "$PULL_REQ_FILE"

            # if the git repo contains multiple layers then _all_ the layers in that repo
            # need to be updated on the layerindex
            # This command will find all the sublayers starting with meta- in the current
            # git repo
            local LAYERS=()
            LAYERS=($(find . -maxdepth 1 -type d -name 'meta-*' -printf '%P '))

            if [ "${#LAYERS[@]}" -eq 0 ]; then
                LAYERS+=(${PUSH_LAYER##*/})
            fi

            # special case for oe-core which is a layer in a meta directory but has a
            # different name in the layerindex
            if [ "${PUSH_LAYER##*/}" == 'oe-core' ]; then
                LAYERS+=('openembedded-core')
                # setup assumes bitbake and oe-core are on the same server
                run_cmd ssh git@ala-lxgit.wrs.com wrfork bitbake
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
            } >> "$DEVBUILD_YAML"
        )
        echo
    done

    # cat "$DEVBUILD_YAML"

    if [ "$DRY_RUN" == 'no' ]; then
        APITOKEN=$(curl -k -s "$SERVER/auth/build_auth.txt" | tr -d '\n')

        CRUMB=$(curl -k -s --user "$APITOKEN" \
                     "$SERVER"/jenkins/crumbIssuer/api/xml?xpath='concat(//crumbRequestField,":",//crumb)' )

        echo "Starting devbuild on $SERVER/jenkins"
        curl -X POST -k -H "$CRUMB" --user "$APITOKEN" \
             --data-urlencode DEVBUILD_YAML@"$DEVBUILD_YAML" \
             "$SERVER/jenkins/job/devbuilds/job/devbuild/buildWithParameters?token=devbuild&CI_REPO=$CI_REPO&CI_BRANCH=$CI_BRANCH"
    fi

    rm -f "$DEVBUILD_YAML"
}

main "$@"
