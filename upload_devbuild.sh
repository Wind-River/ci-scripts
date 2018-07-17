#!/bin/bash -x
set -euo pipefail

if [ -z "$SERVER" ]; then
    SERVER=https://ala-blade21.wrs.com
fi

APITOKEN=$(curl -k -s "$SERVER/auth/build_auth.txt" | tr -d '\n')

CRUMB=$(curl -k -s --user "$APITOKEN" \
             "$SERVER"/jenkins/crumbIssuer/api/xml?xpath='concat(//crumbRequestField,":",//crumb)' )

curl -X POST -k -H "$CRUMB" --user "$APITOKEN" \
     --data-urlencode DEVBUILD_YAML@devbuild.yaml \
     "$SERVER/jenkins/job/devbuilds/job/devbuild/buildWithParameters?token=devbuild"

