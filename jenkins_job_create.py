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
import sys
import jenkins

# import the jenkins connection code
from common import get_jenkins


def create_parser():
    """Parse command line args"""
    from argparse import ArgumentParser
    from argparse import RawTextHelpFormatter

    descr = '''Create or update Jenkins job using local xml files'''

    op = ArgumentParser(description=descr, formatter_class=RawTextHelpFormatter)

    op.add_argument('--jenkins', dest='jenkins', required=False,
                    help='Jenkins master endpoint.')

    op.add_argument("--jenkins_auth", dest="jenkins_auth", required=False,
                    default='jenkins_auth.txt',
                    help="Specify the file path for jenkins authentication infomation")

    op.add_argument('--job', dest='job', required=False,
                    default='WRLinux_Build',
                    help='Jenkins Job name. \nDefault WRLinux_Build')

    op.add_argument('--ci_branch', dest='ci_branch', required=False,
                    default='master',
                    help='The branch to use for the ci-scripts repo.'
                    'Used for local modifications.\nDefault master.')

    op.add_argument('--ci_repo', dest='ci_repo', required=False,
                    help='The location of the ci-scripts repo.')

    op.add_argument("--git_credential", dest="git_credential", required=False,
                    choices=['enable', 'disable'],
                    help="Specify if jenkins need to use stored credential.")

    op.add_argument("--git_credential_id", dest="git_credential_id", required=False,
                    help="Specify the credential id when git_credential is enabled. Default: git")

    return op


def main():
    """Main"""

    # Get options from command line
    parser = create_parser()
    opts = parser.parse_args(sys.argv[1:])

    server = get_jenkins(opts)

    job_config = os.path.join('jobs', opts.job) + '.xml'
    xml_config = jenkins.EMPTY_CONFIG_XML
    if not os.path.exists(job_config):
        print("Could not find matching Job definition for " + opts.job)
    else:
        with open(job_config) as job_config_file:
            xml_config = job_config_file.read()
            if opts.ci_branch != 'master':
                # replace branch in xml definition of job
                import xml.etree.ElementTree as ET
                root = ET.fromstring(xml_config)
                branches = root.find('definition').find('scm').find('branches')
                branch = branches.find('hudson.plugins.git.BranchSpec').find('name')
                branch.text = '*/' + opts.ci_branch
                xml_config = ET.tostring(root, encoding="unicode")
            if opts.ci_repo:
                # replace git repo in xml definition of job
                import xml.etree.ElementTree as ET
                root = ET.fromstring(xml_config)
                ci_repos = root.find('definition').find('scm').find('userRemoteConfigs')
                ci_repo = ci_repos.find('hudson.plugins.git.UserRemoteConfig').find('url')
                ci_repo.text = opts.ci_repo
                xml_config = ET.tostring(root, encoding="unicode")

    try:
        server.get_job_config(opts.job)
        server.reconfig_job(opts.job, xml_config)
    except jenkins.NotFoundException:
        server.create_job(opts.job, xml_config)


if __name__ == "__main__":
    main()
