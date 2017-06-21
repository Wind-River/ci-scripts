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

    descr = '''Trigger build on Jenkins using a configuration from yaml files'''

    op = ArgumentParser(description=descr)

    op.add_argument('--jenkins', dest='jenkins', required=True,
                    help='Jenkins master endpoint.')

    op.add_argument('--job', dest='job', required=False, default='WRLinux_Build',
                    help='Jenkins Job name.')

    op.add_argument('--configs_file', dest='configs_file', required=True,
                    help='Name of file that contains valid build configurations.')

    op.add_argument('--configs', dest='configs', required=True,
                    help='Comma separated list of builds as specified in config_file.'
                    'Use all to queue all the configs.')

    op.add_argument("--image", dest="image", required=False,
                    default='ubuntu1604_64',
                    help="The Docker image used for the build. Default: ubuntu1404_64.")

    op.add_argument("--registry", dest="registry", required=False,
                    default='windriver',
                    help="The Docker registry to pull images from. Default: windriver.")

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
                                           'IMAGE': opts.image,
                                           'BRANCH': branch,
                                           'SETUP_ARGS': ' '.join(config['setup']),
                                           'PREBUILD_CMD': ' '.join(config['prebuild']),
                                           'BUILD_CMD': ' '.join(config['build']),
                                           'REGISTRY': opts.registry,
                                          })

                print("Scheduled build " + str(next_build_number))
                if output:
                    print("Jenkins Output:" + output)


if __name__ == "__main__":
    main()
