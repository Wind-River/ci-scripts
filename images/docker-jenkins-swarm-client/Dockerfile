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

FROM docker:stable

ARG version=0.1.0-dev
ARG build_date=unknown
ARG commit_hash=unknown
ARG vcs_url=unknown
ARG vcs_branch=unknown

LABEL maintainer="Konrad Scherer <Konrad.Scherer@windriver.com>" \
    org.label-schema.vendor="WindRiver" \
    org.label-schema.name="docker-jenkins-swarm-client" \
    org.label-schema.description="Jenkins agent using Swarm plugin with Docker" \
    org.label-schema.usage="README.md" \
    org.label-schema.url="https://github.com/WindRiver-OpenSourceLabs/docker-jenkins-swarm-client/blob/master/README.md" \
    org.label-schema.vcs-url=$vcs_url \
    org.label-schema.vcs-branch=$vcs_branch \
    org.label-schema.vcs-ref=$commit_hash \
    org.label-schema.version=$version \
    org.label-schema.schema-version="1.0" \
    org.label-schema.build-date=$build_date

RUN addgroup -g 1000 jenkins && addgroup -g 997 docker && addgroup -g 996 docker2 \
    && addgroup -g 998 docker3 && addgroup -g 995 docker4 \
    && adduser -u 1000 -G jenkins -D -s /sbin/nologin jenkins \
    && adduser jenkins docker2 && adduser jenkins docker3 && adduser jenkins docker4 \
    && adduser jenkins ping && adduser jenkins jenkins \
    && apk --update --no-cache add tini openjdk8-jre python git openssh openssl bash sudo py-pip curl python-dev libc-dev libffi-dev openssl-dev gcc make \
    && pip install docker-compose \
    && echo "jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN mkdir /license-report  && cd /license-report \
    && curl --silent --remote-name https://raw.githubusercontent.com/WindRiver-OpenSourceLabs/license-report/master/generate_report.sh \
    && apk update && sh generate_report.sh > report \
    && rm -rf /var/cache/apk/* && rm /license-report/generate_report.sh

ENV SWARM_CLIENT_VERSION="3.17" \
    SWARM_SHA="96dfbf0ceda7a380fb94df449ddaeddec686f800" \
    SWARM_HOME="/home/jenkins" \
    SWARM_DELAYED_START="" \
    SWARM_AGENT_USER="agent" \
    COMMAND_OPTIONS=""

# note busybox sha1sum requires two spaces between SHA and filename
RUN wget -q https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/${SWARM_CLIENT_VERSION}/swarm-client-${SWARM_CLIENT_VERSION}.jar -P /usr/bin/ \
   && mv /usr/bin/swarm-client-*.jar /usr/bin/swarm-client.jar \
   && echo "$SWARM_SHA  /usr/bin/swarm-client.jar" | sha1sum -c - \
   && mkdir -p "${SWARM_HOME}/workspace" && chown -R jenkins:jenkins "$SWARM_HOME"

COPY scripts/docker-entrypoint.sh /docker-entrypoint.sh

USER jenkins

VOLUME ["$SWARM_HOME"]

ENTRYPOINT ["/sbin/tini","--","/docker-entrypoint.sh"]
