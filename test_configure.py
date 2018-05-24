#!/usr/bin/python3

# Copyright (c) 2018 Wind River Systems Inc.
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
import yaml

def main():
    """Main"""

    WORKSPACE = os.environ['WORKSPACE']
    TOP = WORKSPACE + '/ci-scripts/'
    LOCALCONF = 'conf/local.conf'
    TEST = os.environ['TEST']
    TEST_CONFIGS_FILE = TOP + os.environ['TEST_CONFIGS_FILE']

    if os.path.exists(LOCALCONF) == False:
        print("ERROR: The file does not exist: " + LOCALCONF)
        sys.exit(1)

    if TEST == 'disable' or TEST == '' or TEST is None:
        print('Test is not enabled')
        sys.exit(0)
    else:
        print('Test is enabled and set to ' + TEST)

    if TEST_CONFIGS_FILE is None:
        TEST_CONFIGS_FILE = 'configs/test_configs.yaml'

    if not os.path.exists(TEST_CONFIGS_FILE):
        print("ERROR: The file does not exist: " + TEST_CONFIGS_FILE)
    else:
        print("Test configuration file exists: " + TEST_CONFIGS_FILE)

        with open(TEST_CONFIGS_FILE) as test_configs_file:
            test_configs = yaml.load(test_configs_file)
            if test_configs is None:
                sys.exit(1)

    # Write conf/local.conf
    with open(LOCALCONF, "a") as local_conf:
        for test_config in test_configs:
            if test_config['name'] == TEST:
                for build_option in test_config['build_options']:
                    local_conf.write(build_option + "\n")

if __name__ == "__main__":
    main()
