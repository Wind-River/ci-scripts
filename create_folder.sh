#!/bin/bash -x
set -euo pipefail

SERVER=https://yow-kscherer-d3.wrs.com

APITOKEN=$(curl -k -s "$SERVER/auth/build_auth.txt" | tr -d '\n')

CRUMB=$(curl -k -s --user "$APITOKEN" \
             "$SERVER"/jenkins/crumbIssuer/api/xml?xpath='concat(//crumbRequestField,":",//crumb)' )

curl -X POST -k -H "$CRUMB" --user "$APITOKEN" \
     "$SERVER/jenkins/job/folder_create/buildWithParameters?TOKEN=devbuild&NAME=devbuilds"

