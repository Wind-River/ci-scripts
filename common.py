#!/usr/bin/env python3

# Copyright (c) 2017-2018 Wind River Systems Inc.
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

# To ignore no-member pylint errors:
#     pylint: disable=E1101

import os
import re
import sys
import ssl
import requests
import jenkins

if hasattr(ssl, '_create_unverified_context'):
    ssl._create_default_https_context = ssl._create_unverified_context


def validate_login(jenkins_master_endpoint, login_auth):
    checkpoint = jenkins_master_endpoint + "/credentials/store/system/domain/_/api/json?tree=credentials[id]"
    try:
        response = requests.get(checkpoint, verify=False, auth=login_auth)
        return response.status_code
    except:
        print("Jenkins login validation checkpoint fail. Check jenkins server status.")
        sys.exit(1)


def fetch_auth_from_local_file(jenkins_auth_file):
    file_path = jenkins_auth_file
    if not os.path.isfile(file_path):
        print("No local auth file detected.")
        return None
    with open(file_path, 'rt') as auth_file:
        try:
            auth_content = auth_file.read()
            if not auth_content:
                print("Local auth file empty.")
                return None
            local_auth = re.split(r'[:,;\s]\s*', auth_content)
            if len(local_auth) != 2:
                print("Local auth file format invalid.")
                return None
            return tuple(local_auth)
        except:
            print("Local auth file format invalid.")
            return None


def fetch_auth_from_jenkins_server(jenkins_master_endpoint):
    if jenkins_master_endpoint.endswith('/jenkins'):
        jenkins_auth_endpoint = jenkins_master_endpoint[:-8] + "/auth/jenkins_auth.txt"
    try:
        print("Trying to use auth info on jenkins server to login.")
        requests.packages.urllib3.disable_warnings()
        response = requests.get(jenkins_auth_endpoint, verify=False)
        return tuple(response.text.split(":"))
    except:
        print("Fetching auth info from jenkins server fails.")
        print("Jenkins need credential to submit build job. Please put proper auth info in \"jenkins_auth.txt\" to continue.")
        print("Credential format accepted is \"USERNAME:API_TOKEN\"")
        sys.exit(1)


def detect_jenkins_auth(jenkins_master_endpoint, jenkins_auth_file):
    try:
        requests.packages.urllib3.disable_warnings()
        check_without_auth = validate_login(jenkins_master_endpoint, login_auth=None)
        if check_without_auth == 200:
            print("Insecured jenkins server detected.")
            return None
        local_auth_info = fetch_auth_from_local_file(jenkins_auth_file)
        check_with_local_auth = validate_login(jenkins_master_endpoint, login_auth=local_auth_info)
        if check_with_local_auth == 200:
            print("Login with local auth info succeeded.")
            return local_auth_info
        remote_auth_info = fetch_auth_from_jenkins_server(jenkins_master_endpoint)
        check_with_remote_auth = validate_login(jenkins_master_endpoint, login_auth=remote_auth_info)
        if check_with_remote_auth == 200:
            print("Login with remote auth info on jenkins server succeeded.")
            return remote_auth_info
        print("Jenkins need credential to submit build job. Please put proper auth info in your local auth file using \"--jenkins_auth\" argument.")
        print("Credential format accepted is \"USERNAME:API_TOKEN\"")
        sys.exit(1)
    except:
        print("Login fail.")
        sys.exit(1)

def fetch_credentials(jenkins_master_endpoint, jenkins_auth=None):
    credential_ids = []
    credential_endpoint = jenkins_master_endpoint + "/credentials/store/system/domain/_/api/json?tree=credentials[id]"
    try:
        requests.packages.urllib3.disable_warnings()
        response = requests.get(credential_endpoint, verify=False, auth=jenkins_auth)
        credentials = response.json()['credentials']
        for credential in credentials:
            credential_ids.append(credential['id'])
    except requests.ConnectionError:
        print("Connection to Jenkins REST api failed.")
        sys.exit(1)
    except KeyError:
        print("No credential stored in Jenkins")
        sys.exit(1)
    return credential_ids


def get_jenkins(opts):
    jenkins_url = opts.jenkins
    if jenkins_url.startswith('http://'):
        jenkins_url.replace('http://', 'https://')

    if not jenkins_url.startswith('https://'):
        jenkins_url = 'https://' + jenkins_url

    if not jenkins_url.endswith('/jenkins'):
        jenkins_url = jenkins_url + '/jenkins'

    jenkins_auth = detect_jenkins_auth(jenkins_url, opts.jenkins_auth)

    if opts.git_credential == "enable":
        credentials = fetch_credentials(jenkins_url, jenkins_auth)
        if opts.git_credential_id not in credentials:
            print("Could not find the Git Credential Id labelled %s in Jenkins." % opts.git_credential_id)
            sys.exit(1)
        else:
            print("Using the Git Credential Id %s in Jenkins to access git server." % opts.git_credential_id)

    try:
        if not jenkins_auth:
            server = jenkins.Jenkins(jenkins_url)
        else:
            server = jenkins.Jenkins(jenkins_url, username=jenkins_auth[0], password=jenkins_auth[1])
        server._session.verify = False
    except jenkins.JenkinsException:
        print("Connection to Jenkins server %s failed." % jenkins_url)
        sys.exit(1)

    return server
