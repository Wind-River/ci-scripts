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

FROM jenkins/jenkins:lts-alpine

# Increase timeout to try and avoid plugin download errors
ENV CURL_CONNECTION_TIMEOUT 60

# split the plugin installation into multiple stages to reduce chance of download failure
RUN /usr/local/bin/install-plugins.sh git workflow-aggregator docker-workflow swarm greenballs matrix-auth

# init script written in groovy to setup Jenkins on startup
COPY init_scripts/ /usr/share/jenkins/ref/init.groovy.d/

RUN echo 2.5 > /usr/share/jenkins/ref/jenkins.install.UpgradeWizard.state
