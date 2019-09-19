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
import yaml
import jenkins
import git

# import the jenkins connection code
from common import get_jenkins


def create_parser():
    """Parse command line args"""
    from argparse import ArgumentParser
    from argparse import RawTextHelpFormatter

    descr = '''Trigger build on Jenkins using a configuration from yaml files'''

    op = ArgumentParser(description=descr, formatter_class=RawTextHelpFormatter)

    op.add_argument('--jenkins', dest='jenkins', required=False,
                    help='Jenkins master endpoint.')

    op.add_argument('--job', dest='job', required=False,
                    help='Jenkins Job name. \nDefault WRLinux_Build')

    op.add_argument('--ci_branch', dest='ci_branch', required=False,
                    help='The branch to use for the ci-scripts repo.'
                    'Used for local modifications.\nDefault master.')

    op.add_argument('--ci_repo', dest='ci_repo', required=False,
                    help='The location of the ci-scripts repo. Override to use local mirror.\n'
                    'Default: https://github.com/WindRiver-OpenSourceLabs/ci-scripts.git.')

    op.add_argument('--configs_file', dest='configs_file', required=False,
                    help='Name of file that contains the configurations for ci system.')

    op.add_argument('--build_configs_file', dest='build_configs_file', required=False,
                    help='Name of file that contains valid build configurations.')

    op.add_argument('--build_configs', dest='build_configs', required=False,
                    help='Comma separated list of builds as specified in build_configs_file.'
                    'Use all to queue all the configs.')

    op.add_argument('--test_configs_file', dest='test_configs_file', required=False,
                    help='Name of file that contains run-time test configurations.')

    op.add_argument("--image", dest="image", required=False,
                    help="The Docker image used for the build. \nDefault: ubuntu1604_64.")

    op.add_argument("--registry", dest="registry", required=False,
                    help="The Docker registry to pull images from. \nDefault: windriver.")

    op.add_argument("--postprocess_image", dest="post_process_image", required=False,
                    help="The Docker image used for the post process stage. \n"
                    "Default: postbuild.")

    op.add_argument("--postprocess_args", dest="postprocess_args", required=False,
                    help="A comma separated list of args in form KEY=VAL that will be"
                    "injected into post process script environment.")

    op.add_argument("--post_success", dest="post_success", required=False,
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a successful build. \nDefault: rsync,cleanup.")

    op.add_argument("--post_fail", dest="post_fail", required=False,
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a failed build. \nDefault: cleanup,send_email.")

    op.add_argument("--network", dest="network", required=False,
                    choices=['bridge', 'none'],
                    help="The network switch for network access.\n"
                    "Only two options allowed: bridge (with network access) and none (without network). \n"
                    "Default: bridge.")

    op.add_argument("--toaster", dest="toaster", required=False,
                    choices=['enable', 'disable'],
                    help="The switch for using toaster in build.\n"
                    "Only two options allowed: enable (with toaster) and disable (without toaster).\n"
                    "Default: enable.")

    op.add_argument("--branch", dest="branch", required=False,
                    help="Override the branch defined in the combos file.")

    op.add_argument("--remote", dest="remote", required=False,
                    help="Specify a remote for the wrlinux_update.sh script to clone or update from.")

    op.add_argument("--build_group_id", dest="build_group_id", required=False,
                    help="Specify a build group id after launching a Devbuild, it will be used for report.")

    op.add_argument("--devbuild_layer_name", dest="devbuild_layer_name", required=False,
                    help="Specify a layer name to be modified as part of a Devbuild.")

    op.add_argument("--devbuild_layer_vcs_url", dest="devbuild_layer_vcs_url", required=False,
                    help="Specify the layer vcs_url to used with a Devbuild."
                    "If not specified the vcs_url will not be changed.")

    op.add_argument("--devbuild_layer_actual_branch", dest="devbuild_layer_actual_branch",
                    required=False,
                    help="Specify the branch to be used with on the modified layer for a Devbuild."
                    "Defaults to branch used for build")

    op.add_argument("--devbuild_layer_vcs_subdir", dest="devbuild_layer_vcs_subdir", required=False,
                    help="Specify the subdir of a repository in which to find the layer.")

    op.add_argument("--layerindex_type", dest="layerindex_type", required=False,
                    help="Specify the type of layer index. \n"
                    "Default: restapi-web")

    op.add_argument("--layerindex_source", dest="layerindex_source", required=False,
                    help="Specify the source URL of layer index. \n"
                    "Default: https://layers.openembedded.org/layerindex/api")

    op.add_argument("--bitbake_repo_url", dest="bitbake_repo_url", required=False,
                    help="Specify the URL of bitbake repo. \n"
                    "Default: git://git.openembedded.org/bitbake")

    op.add_argument("--test", dest="test", required=False,
                    help="Switch to specific test suite name, such as oeqa-default-test \n"
                    "to enable runtime testing of the build. Default: disable")

    op.add_argument("--test_image", dest="test_image", required=False,
                    help="The Docker image used for the test stage.\n"
                    "Default: postbuild.")

    op.add_argument("--test_args", dest="test_args", required=False,
                    help="A comma separated list of args in form KEY=VAL that will be"
                    "injected into test and post test script environment.")

    op.add_argument("--post_test_image", dest="post_test_image", required=False,
                    help="The Docker image used for the post test stage.\n"
                    "Default: postbuild.")

    op.add_argument("--post_test_success", dest="post_test_success", required=False,
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a successful test. \nDefault: none.")

    op.add_argument("--post_test_fail", dest="post_test_fail", required=False,
                    help="A comma separated list of scripts in the scripts/ directory"
                    "to be run after a failed test. \nDefault: none.")

    op.add_argument("--git_credential", dest="git_credential", required=False,
                    choices=['enable', 'disable'],
                    help="Specify if jenkins need to use stored credential.")

    op.add_argument("--git_credential_id", dest="git_credential_id", required=False,
                    help="Specify the credential id when git_credential is enabled. Default: git")

    op.add_argument("--jenkins_auth", dest="jenkins_auth", required=False,
                    help="Specify the file path for jenkins authentication infomation")

    return op


def replace_dict_key(dic):
    """ Handle environment variables for devbuild_argsa """
    dict_var_names = {
        'branch'             : 'DEVBUILD_BRANCH',
        'layer_name'         : 'DEVBUILD_LAYER_NAME',
        'layer_vcs_url'      : 'DEVBUILD_LAYER_VCS_URL',
        'layer_actual_branch': 'DEVBUILD_LAYER_ACTUAL_BRANCH',
        'layer_vcs_subdir'   : 'DEVBUILD_LAYER_VCS_SUBDIR',
    }

    newdict={}
    for key, value in dic.items():
        if key in dict_var_names:
            newdict[dict_var_names[key]] = value
    for key, value in dic.items():
        if value is None:
            newdict[key] = ''

    return newdict


def parse_configs_from_yaml(configs_file):
    """
    This function is used to get all the options from a configuration file:
    configs/jenkins_job_configs.yaml
    """
    class Opts(dict):
        """ This class will be used to collect all the options. """
        pass

    def setattr_without_none(obj, attr, value):
        setattr(obj, attr, '' if value is None else value)

    def dict2list(d):
        return [(str(k) + '=' + (str(v) if v is not None else '')) for k, v in d.items()]

    if configs_file is None:
        configs_file = 'wrigel-configs/jenkins_job_configs.yaml'

    with open(configs_file) as yaml_configs_file:

        yaml_configs = yaml.safe_load(yaml_configs_file)

        if yaml_configs is None:
            print("No configurations were found in " + configs_file)
            sys.exit(1)

        else:
            # Get attributes without parsing details
            layer_id = 0
            setattr(Opts, 'devbuild_args', '')

            for section in yaml_configs:
                for section_cfgs in yaml_configs[section]:
                    if isinstance(section_cfgs, dict):
                        # configs for layers
                        if section_cfgs['layer_name']:
                            layer_id += 1
                            layername = 'layer_' + str(layer_id) + '_' + section_cfgs['layer_name']
                            setattr_without_none(Opts, layername, section_cfgs)

                            # TODO: we will support multiple layers in devbuild_args, currently
                            # devbuild_args is set to the first layer with its layer_name is defined
                            if layer_id == 1:
                                setattr(Opts, 'devbuild_args',
                                        ','.join(dict2list(replace_dict_key(section_cfgs))))
                        else:
                            print("WARNING - no layer_name: " + str(section_cfgs))
                    else:
                        value = yaml_configs[section][section_cfgs]
                        # configs for postprocess_args, test_args
                        if isinstance(value, dict):
                            setattr_without_none(Opts, section_cfgs, ','.join(dict2list(value)))
                        # configs for build_configs, post_fail/success, post_test_fail/success
                        elif isinstance(value, list):
                            setattr_without_none(Opts, section_cfgs, ','.join(value))
                        else:
                            setattr_without_none(Opts, section_cfgs, value)

    return Opts


def main():
    """Main"""
    # Common functions
    def get_attr_list(d):
        return [attr for attr in d.__dict__.keys() if not attr.startswith("__")]

    def num_spaces(word, fixed_length):
        return fixed_length - len(word)

    def dict2list(d):
        return [(str(k) + '=' + str(v)) for k, v in d.items()]

    # Get options from command line
    parser = create_parser()
    cml_opts = parser.parse_args(sys.argv[1:])

    cml_opts_attr_list = get_attr_list(cml_opts)
    cml_opts_attr_list.sort()

    # Check existence of wrigel-configs repo
    if not os.path.exists("wrigel-configs"):
        print("wrigel-configs repo does NOT exist, clone it.")
        git.Git(".").clone("git://ala-lxgit.wrs.com/git/projects/wrlinux-ci/wrigel-configs.git")
    else:
        print("wrigel-configs repo exists, pull latest changes.")
        wrigel_configs = git.cmd.Git("wrigel-configs")
        wrigel_configs.pull()

    # Get options from YAML configuration file
    opts = parse_configs_from_yaml(cml_opts.configs_file)

    opts_attr_list = get_attr_list(opts)
    opts_attr_list.sort()

    # Override the options get from YAML config file
    for attr in cml_opts_attr_list:
        cml_value = getattr(cml_opts, attr)

        if cml_value and attr != 'configs_file':
            yaml_value = getattr(opts, attr)

            if attr in opts_attr_list:
                # support overriding sub-items in postprocess_args and test_args
                if attr in ['postprocess_args', 'test_args']:
                    cml_value_in_dict = dict(item.split("=") for item in cml_value.split(","))
                    yaml_value_in_dict = dict(item.split("=") for item in yaml_value.split(","))

                    yaml_value_key_list = list(yaml_value_in_dict.keys())
                    for key, val in cml_value_in_dict.items():
                        if key in yaml_value_key_list:
                            yaml_value_in_dict[key] = val
                            if key == 'TEST_DEVICE':
                                test_device = val

                    setattr(opts, attr, ','.join(dict2list(yaml_value_in_dict)))
                else:
                    setattr(opts, attr, cml_value)
            else:
                print("WARNING: ", attr, "is not a known option in YAML config file!")

    print("============ Options after override ============")
    for attr in opts_attr_list:
        print(attr, ' ' * num_spaces(attr, 22), ':', getattr(opts, attr))
    print("================================================")

    if opts.network == "none" and opts.toaster == "enable":
        print("Cannot enable Toaster if network is disabled."
              "Either enable network access or disable Toaster.")
        sys.exit(1)

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

    with open(opts.build_configs_file) as build_configs_file:
        configs = yaml.safe_load(build_configs_file)
        if configs is None:
            sys.exit(1)

        configs_to_build = opts.build_configs.split(',')
        for config in configs:
            if opts.build_configs == 'all' or config['name'] in configs_to_build:

                print("Generating command for config %s" % config['name'])

                branch = config.get('branch', "WRLINUX_9_BASE")
                if opts.branch:
                    branch = opts.branch

                next_build_number = server.get_job_info(opts.job)['nextBuildNumber']

                prebuild_cmd_for_test = ''
                build_cmd_for_test = ''
                runtime_test_cmd = 'null'
                if opts.test != 'disable' and opts.test != '' and opts.test is not None:
                    with open(opts.test_configs_file) as test_configs_file:
                        test_configs = yaml.safe_load(test_configs_file)
                        if test_configs is None:
                            print('ERROR: Test is enabled but test configs file is empty.')
                            sys.exit(1)

                    #TODO: currently only run one test in test_configs
                    for test_config in test_configs:
                        if test_config['name'] == opts.test:
                            print('Test is enabled and test suite is set to ' + opts.test)
                            prebuild_cmd_for_test = ' '.join(test_config['prebuild_cmd_for_test'])

                            if test_config['build_cmd_for_test'] is not None:
                                build_cmd_for_test = ' '.join(test_config['build_cmd_for_test'])
                                if '-c testexport' in build_cmd_for_test:
                                    build_cmd_for_test = ' '.join(config['build']) + ' -c testexport'

                            runtime_test_cmd = 'run_tests.sh' \
                                               + ' ' + test_config['lava_test_repo'] \
                                               + ' ' + test_config[test_device]['job_template'] \
                                               + ' ' + str(test_config[test_device]['timeout'])

                if prebuild_cmd_for_test == 'null':
                    print('Test is disabled.')

                output = server.build_job(opts.job,
                                          {'NAME': config['name'],
                                           'CI_BRANCH': opts.ci_branch,
                                           'CI_REPO': opts.ci_repo,
                                           'IMAGE': opts.image,
                                           'BRANCH': branch,
                                           'REMOTE': opts.remote,
                                           'BUILD_GROUP_ID': opts.build_group_id,
                                           'SETUP_ARGS': ' '.join(config['setup']),
                                           'PREBUILD_CMD': ' '.join(config['prebuild']),
                                           'PREBUILD_CMD_FOR_TEST': prebuild_cmd_for_test,
                                           'BUILD_CMD': ' '.join(config['build']),
                                           'BUILD_CMD_FOR_TEST': build_cmd_for_test,
                                           'REGISTRY': opts.registry,
                                           'POSTPROCESS_IMAGE': opts.post_process_image,
                                           'POSTPROCESS_ARGS': opts.postprocess_args,
                                           'POST_SUCCESS': opts.post_success,
                                           'POST_FAIL': opts.post_fail,
                                           'NETWORK': opts.network,
                                           'TOASTER': opts.toaster,
                                           'GIT_CREDENTIAL': opts.git_credential,
                                           'GIT_CREDENTIAL_ID': opts.git_credential_id,
                                           'LAYERINDEX_TYPE': opts.layerindex_type,
                                           'LAYERINDEX_SOURCE': opts.layerindex_source,
                                           'BITBAKE_REPO_URL': opts.bitbake_repo_url,
                                           'TEST': opts.test,
                                           'TEST_CONFIGS_FILE': opts.test_configs_file,
                                           'RUNTIME_TEST_CMD': runtime_test_cmd,
                                           'TEST_IMAGE': opts.test_image,
                                           'TEST_ARGS': opts.test_args,
                                           'POST_TEST_IMAGE': opts.post_test_image,
                                           'POST_TEST_SUCCESS': opts.post_test_success,
                                           'POST_TEST_FAIL': opts.post_test_fail,
                                          })

                print("Scheduled build " + str(next_build_number))
                if output:
                    print("Jenkins Output:" + str(output))


if __name__ == "__main__":
    main()
