#!/bin/sh

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

set -o errexit

if [ -n "${SWARM_DELAYED_START}" ]; then
  sleep "${SWARM_DELAYED_START}"
fi

if ! echo "$COMMAND_OPTIONS" | grep -q -- '-fsroot' ; then
    COMMAND_OPTIONS="${COMMAND_OPTIONS} -fsroot ${SWARM_HOME}"
fi

# Use docker secret to retrieve password, but env always overrides
if [ -n "${SWARM_AGENT_PASSWORD}" ]; then
    COMMAND_OPTIONS="${COMMAND_OPTIONS} -username ${SWARM_AGENT_USER} -password ${SWARM_AGENT_PASSWORD}"
elif [ -f /run/secrets/agent_password ]; then
    COMMAND_OPTIONS="${COMMAND_OPTIONS} -username ${SWARM_AGENT_USER} -password $(cat /run/secrets/agent_password)"
fi

if [ -n "${SWARM_CLIENT_NAME}" ]; then
    COMMAND_OPTIONS="${COMMAND_OPTIONS} -name ${SWARM_CLIENT_NAME}"
else
    HOSTNAME=$(cat /etc/hostname)
    COMMAND_OPTIONS="${COMMAND_OPTIONS} -name ${HOSTNAME}"
fi

java -jar "/usr/bin/swarm-client.jar" -deleteExistingClients ${COMMAND_OPTIONS}
