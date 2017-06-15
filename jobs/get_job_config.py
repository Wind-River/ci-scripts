#!/usr/bin/env python3

import sys
import ssl
import jenkins

if hasattr(ssl, '_create_unverified_context'):
    ssl._create_default_https_context = ssl._create_unverified_context


def create_parser():
    """Parse command line args"""
    from argparse import ArgumentParser

    descr = '''Retrieve and print xml config for a Jenkins Job'''

    op = ArgumentParser(description=descr)

    op.add_argument('--jenkins', dest='jenkins', required=True,
                    help='Jenkins master endpoint.')

    op.add_argument('--job', dest='job', required=True,
                    help='Jenkins Job name.')

    return op


def main():
    """Main"""
    parser = create_parser()
    opts = parser.parse_args(sys.argv[1:])

    server = jenkins.Jenkins(opts.jenkins)

    job = server.get_job_config(opts.job)

    print(job)


if __name__ == "__main__":
    main()
