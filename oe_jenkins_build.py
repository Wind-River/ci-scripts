#!/usr/bin/env python3

import sys
import yaml
import jenkins
import ssl

if hasattr(ssl, '_create_unverified_context'):
    ssl._create_default_https_context = ssl._create_unverified_context

def create_parser():
    """Parse command line args"""
    from argparse import ArgumentParser

    descr = '''Trigger build on Jenkins using a configuration from yaml files'''

    op = ArgumentParser(description=descr)

    op.add_argument('--jenkins', dest='jenkins', required=True,
                    help='Jenkins master endpoint.')

    op.add_argument('--job', dest='job', required=True,
                    help='Jenkins Job name.')

    op.add_argument('--configs_file', dest='configs_file', required=True,
                    help='Comma separated list of tests or test collections to submit.')

    op.add_argument('--configs', dest='configs', required=True,
                    help='Comma separated list of builds as specified in config_file.'
                    'Use all to queue all the configs.')

    op.add_argument("--image", dest="image", required=False,
                    default='ubuntu1404_64',
                    help="The Docker image used for the build. Default: ubuntu1404_64.")

    op.add_argument("--location", dest="location", required=False,
                    default='ala', choices=['ala', 'yow', 'pek', 'local'],
                    help="Location to run builds. Default: ala")

    op.add_argument("--wrlinux", dest="wrlinux", required=False,
                    help="Location of source tree. Defaults to local cache on builder.")

    return op


def validate_args(opts):
    """Validation of args"""


def parse_args(args):
    parser = create_parser()
    opts = parser.parse_args(args)
    validate_args(opts)
    return opts


RELEASE_BRANCH_MAP = {
    'WRLinux-9-Base': 'WRLINUX_9_BASE',
    'WRLinux-9-LTS': 'WRLINUX_9_LTS',
    'WRLinux-9-LTS-CVE': 'WRLINUX_9_LTS_CVE',
}

BRANCH_WRLINUX_MAP = {
    'WRLinux-9-Base': 'http://GITSERVER/release/WRL9/WRLinux-9-Base/wrlinux-9',
    'WRLinux-9-LTS': 'http://GITSERVER/release/WRL9/WRLinux-9-LTS/wrlinux-9',
    'WRLinux-9-LTS-CVE': 'http://GITSERVER/release/WRL9/WRLinux-9-LTS-CVE/wrlinux-9',
}


def main():
    """Main"""
    opts = parse_args(sys.argv[1:])

    server = jenkins.Jenkins(opts.jenkins)

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
                                           'PREBUILD_ARGS': ' '.join(config['prebuild']),
                                           'BUILD_CMD': ' '.join(config['build']),
                                          })

                print(output)

if __name__ == "__main__":
    main()

