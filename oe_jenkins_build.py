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
import sys
import ssl
import yaml
import jenkins

if hasattr(ssl, '_create_unverified_context'):
    ssl._create_default_https_context = ssl._create_unverified_context


def create_parser():
    """Parse command line args"""
    from argparse import ArgumentParser
    from argparse import RawTextHelpFormatter

    descr = '''Trigger build on Jenkins using a configuration from yaml files'''

    op = ArgumentParser(description=descr,formatter_class=RawTextHelpFormatter)

    op.add_argument('--jenkins', dest='jenkins', required=True,
                    help='Jenkins master endpoint.')

    op.add_argument('--job', dest='job', required=False, default='WRLinux_Build',
                    help='Jenkins Job name. \nDefault WRLinux_Build')

    op.add_argument('--ci_branch', dest='ci_branch', required=False, default='master',
                    help='The branch to use for the ci-scripts repo. Used for local modifications.\nDefault master.')

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
                    default='ubuntu1604_64',
                    help="The Docker image used for the post process stage. \nDefault: ubuntu1604_64.")

    op.add_argument("--postprocess_args", dest="postprocess_args", required=False,
                    default='',
                    help="A comma separated list of args in form KEY=VAL that will be"
                    "injected into post process script environment.")

    op.add_argument("--post_success", dest="post_success", required=False,
                    default='cleanup',
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a successful build. \nDefault: cleanup.")

    op.add_argument("--post_fail", dest="post_fail", required=False,
                    default='cleanup',
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a failed build. \nDefault: cleanup,send_email.")
    op.add_argument("--network", dest="network", required=False,
                    default='bridge', choices=['bridge', 'none'],
                    help="The network switch for network access.\n"
                     "Only two options allowed: bridge (with network access) and none (without network). \n"
                     "Default: bridge.")

    return op


def main():
    """Main"""
    parser = create_parser()
    opts = parser.parse_args(sys.argv[1:])

    server = jenkins.Jenkins(opts.jenkins)

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

                next_build_number = server.get_job_info(opts.job)['nextBuildNumber']

                output = server.build_job(opts.job,
                                          {'NAME': config['name'],
                                           'CI_BRANCH': opts.ci_branch,
                                           'IMAGE': opts.image,
                                           'BRANCH': branch,
                                           'SETUP_ARGS': ' '.join(config['setup']),
                                           'PREBUILD_CMD': ' '.join(config['prebuild']),
                                           'BUILD_CMD': ' '.join(config['build']),
                                           'REGISTRY': opts.registry,
                                           'POSTPROCESS_IMAGE': opts.post_process_image,
                                           'POSTPROCESS_ARGS': opts.postprocess_args,
                                           'POST_SUCCESS': opts.post_success,
                                           'POST_FAIL': opts.post_fail,
                                           'NETWORK': opts.network,
                                          })

                print("Scheduled build " + str(next_build_number))
                if output:
                    print("Jenkins Output:" + output)


if __name__ == "__main__":
    main()
