#!/usr/bin/env python3

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

import os
import re
import sys
import ssl
import requests
import yaml
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
        response = requests.get(jenkins_auth_endpoint,verify=False)
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

def create_parser():
    """Parse command line args"""
    from argparse import ArgumentParser
    from argparse import RawTextHelpFormatter

    descr = '''Trigger build on Jenkins using a configuration from yaml files'''

    op = ArgumentParser(description=descr, formatter_class=RawTextHelpFormatter)

    op.add_argument('--jenkins', dest='jenkins', required=True,
                    help='Jenkins master endpoint.')

    op.add_argument('--job', dest='job', required=False, default='WRLinux_Build',
                    help='Jenkins Job name. \nDefault WRLinux_Build')

    op.add_argument('--ci_branch', dest='ci_branch', required=False, default='master',
                    help='The branch to use for the ci-scripts repo.'
                    'Used for local modifications.\nDefault master.')

    op.add_argument('--ci_repo', dest='ci_repo', required=False,
                    default='https://github.com/WindRiver-OpenSourceLabs/ci-scripts.git',
                    help='The location of the ci-scripts repo. Override to use local mirror.\n'
                    'Default: https://github.com/WindRiver-OpenSourceLabs/ci-scripts.git.')

    op.add_argument('--configs_file', dest='configs_file', required=True,
                    help='Name of file that contains valid build configurations.')

    op.add_argument('--configs', dest='configs', required=True,
                    help='Comma separated list of builds as specified in config_file.'
                    'Use all to queue all the configs.')

    op.add_argument("--image", dest="image", required=False,
                    default='ubuntu1604_64',
                    help="The Docker image used for the build. \nDefault: ubuntu1604_64.")

    op.add_argument("--registry", dest="registry", required=False,
                    default='windriver',
                    help="The Docker registry to pull images from. \nDefault: windriver.")

    op.add_argument("--postprocess_image", dest="post_process_image", required=False,
                    default='postbuild',
                    help="The Docker image used for the post process stage. \n"
                    "Default: postbuild.")

    op.add_argument("--postprocess_args", dest="postprocess_args", required=False,
                    default='',
                    help="A comma separated list of args in form KEY=VAL that will be"
                    "injected into post process script environment.")

    op.add_argument("--post_success", dest="post_success", required=False,
                    default='rsync,cleanup',
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a successful build. \nDefault: rsync,cleanup.")

    op.add_argument("--post_fail", dest="post_fail", required=False,
                    default='cleanup',
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a failed build. \nDefault: cleanup,send_email.")

    op.add_argument("--network", dest="network", required=False,
                    default='bridge', choices=['bridge', 'none'],
                    help="The network switch for network access.\n"
                    "Only two options allowed: bridge (with network access) and none (without network). \n"
                    "Default: bridge.")

    op.add_argument("--toaster", dest="toaster", required=False,
                    default='enable', choices=['enable', 'disable'],
                    help="The switch for using toaster in build.\n"
                    "Only two options allowed: enable (with toaster) and disable (without toaster).\n"
                    "Default: enable.")

    op.add_argument("--branch", dest="branch", required=False,
                    default='',
                    help="Override the branch defined in the combos file.")

    op.add_argument("--remote", dest="remote", required=False,
                    default='',
                    help="Specify a remote for the wrlinux_update.sh script to clone or update from.")

    op.add_argument("--devbuild_layer_name", dest="devbuild_layer_name", required=False,
                    default='',
                    help="Specify a layer name to be modified as part of a Devbuild.")

    op.add_argument("--devbuild_layer_vcs_url", dest="devbuild_layer_vcs_url", required=False,
                    default='',
                    help="Specify the layer vcs_url to used with a Devbuild."
                    "If not specified the vcs_url will not be changed.")

    op.add_argument("--devbuild_layer_actual_branch", dest="devbuild_layer_actual_branch",
                    required=False, default='',
                    help="Specify the branch to be used with on the modified layer for a Devbuild."
                    "Defaults to branch used for build")

    op.add_argument("--devbuild_layer_vcs_subdir", dest="devbuild_layer_vcs_subdir", required=False,
                    default='',
                    help="Specify the subdir of a repository in which to find the layer.")

    op.add_argument("--test", dest="test", required=False,
                    default='disable', choices=['enable', 'disable'],
                    help="Switch to enable runtime testing of the build.\n"
                    "Only two options supported: enable (run tests) or disable. Default: disable")

    op.add_argument("--test_image", dest="test_image", required=False,
                    default='postbuild',
                    help="The Docker image used for the test stage.\n"
                    "Default: postbuild.")

    op.add_argument("--test_args", dest="test_args", required=False,
                    default='',
                    help="A comma separated list of args in form KEY=VAL that will be"
                    "injected into test and post test script environment.")

    op.add_argument("--post_test_image", dest="post_test_image", required=False,
                    default='postbuild',
                    help="The Docker image used for the post test stage.\n"
                    "Default: postbuild.")

    op.add_argument("--post_test_success", dest="post_test_success", required=False,
                    default='',
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a successful test. \nDefault: none.")

    op.add_argument("--post_test_fail", dest="post_test_fail", required=False,
                    default='',
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a failed test. \nDefault: none.")

    op.add_argument("--git_credential", dest="git_credential", required=False,
                    default='disable', choices=['enable', 'disable'],
                    help="Specify if jenkins need to use stored credential.")

    op.add_argument("--git_credential_id", dest="git_credential_id", required=False,
                    default='git',
                    help="Specify the credential id when git_credential is enabled. Default: git")

    op.add_argument("--jenkins_auth", dest="jenkins_auth", required=False,
                    default='jenkins_auth.txt',
                    help="Specify the file path for jenkins authentication infomation")

    return op


def main():
    """Main"""
    parser = create_parser()
    opts = parser.parse_args(sys.argv[1:])

    if opts.network == "none" and opts.toaster == "enable":
        print("Cannot enable Toaster if network is disabled."
              "Either enable network access or disable Toaster.")
        sys.exit(1)

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
        if(not jenkins_auth):
            server = jenkins.Jenkins(jenkins_url)
        else:
            server = jenkins.Jenkins(jenkins_url, username = jenkins_auth[0], password = jenkins_auth[1])
    except jenkins.JenkinsException:
        print("Connection to Jenkins server %s failed." % jenkins_url)
        sys.exit(1)

    job_config = os.path.join('jobs', opts.job) + '.xml'
    xml_config = jenkins.EMPTY_CONFIG_XML
    if not os.path.exists(job_config):
        print("Could not find matching Job definition for " + opts.job)
    else:
        with open(job_config) as job_config_file:
            xml_config = job_config_file.read()
            if opts.ci_branch != 'master':
                import xml.etree.ElementTree as ET
                root = ET.fromstring(xml_config)
                branches = root.find('definition').find('scm').find('branches')
                branch = branches.find('hudson.plugins.git.BranchSpec').find('name')
                branch.text = '*/' + opts.ci_branch
                xml_config = ET.tostring(root, encoding="unicode")

    try:
        server.get_job_config(opts.job)
        server.reconfig_job(opts.job, xml_config)
    except jenkins.NotFoundException:
        server.create_job(opts.job, xml_config)

    with open(opts.configs_file) as configs_file:
        configs = yaml.load(configs_file)
        if configs is None:
            sys.exit(1)

        configs_to_run = opts.configs.split(',')
        for config in configs:
            if opts.configs == 'all' or config['name'] in configs_to_run:

                print("Generating command for config %s" % config['name'])

                branch = config.get('branch', "WRLINUX_9_BASE")
                if opts.branch:
                    branch = opts.branch

                devbuild_args = ""
                if opts.devbuild_layer_name:
                    devbuild_args = "DEVBUILD_LAYER_NAME=" + opts.devbuild_layer_name
                    devbuild_args += ",DEVBUILD_BRANCH=" + branch
                    devbuild_args += ",DEVBUILD_LAYER_VCS_URL=" + opts.devbuild_layer_vcs_url

                    if not opts.devbuild_layer_actual_branch:
                        opts.devbuild_layer_actual_branch = branch
                    devbuild_args += ",DEVBUILD_LAYER_ACTUAL_BRANCH=" + opts.devbuild_layer_actual_branch

                    if not opts.devbuild_layer_vcs_subdir:
                        devbuild_args += ",DEVBUILD_LAYER_VCS_SUBDIR=" + opts.devbuild_layer_vcs_subdir

                next_build_number = server.get_job_info(opts.job)['nextBuildNumber']

                output = server.build_job(opts.job,
                                          {'NAME': config['name'],
                                           'CI_BRANCH': opts.ci_branch,
                                           'CI_REPO': opts.ci_repo,
                                           'IMAGE': opts.image,
                                           'BRANCH': branch,
                                           'REMOTE': opts.remote,
                                           'SETUP_ARGS': ' '.join(config['setup']),
                                           'PREBUILD_CMD': ' '.join(config['prebuild']),
                                           'BUILD_CMD': ' '.join(config['build']),
                                           'REGISTRY': opts.registry,
                                           'POSTPROCESS_IMAGE': opts.post_process_image,
                                           'POSTPROCESS_ARGS': opts.postprocess_args,
                                           'POST_SUCCESS': opts.post_success,
                                           'POST_FAIL': opts.post_fail,
                                           'NETWORK': opts.network,
                                           'TOASTER': opts.toaster,
                                           'GIT_CREDENTIAL': opts.git_credential,
                                           'GIT_CREDENTIAL_ID': opts.git_credential_id,
                                           'DEVBUILD_ARGS': devbuild_args,
                                           'TEST': opts.test,
                                           'TEST_IMAGE': opts.test_image,
                                           'TEST_ARGS': opts.test_args,
                                           'POST_TEST_IMAGE': opts.post_test_image,
                                           'POST_TEST_SUCCESS': opts.post_test_success,
                                           'POST_TEST_FAIL': opts.post_test_fail,
                                          })

                print("Scheduled build " + str(next_build_number))
                if output:
                    print("Jenkins Output:" + output)


if __name__ == "__main__":
    main()
