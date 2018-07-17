#!/usr/bin/env groovy
// -*- mode: groovy; tab-width: 2; groovy-indent-offset: 2 -*-
// Copyright (c) 2017 Wind River Systems Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

node('docker') {

  // function for adding array of env vars to string
  def add_env = {
    String command, String[] env_args ->
    for ( arg in env_args ) {
      if ( arg.contains('EMAIL=') ) {
        arg = arg.replace(' ', ',')
      }
      command = command + " -e ${arg} "
    }
    return command
  }

  // Node name is from docker swarm is hostname + dash + random string. Remove random part of recover hostname
  def hostname = "${NODE_NAME}"
  hostname = hostname[0..-10]
  def common_docker_params = "--rm --name build-${BUILD_ID} --hostname ${hostname} -i --tmpfs /tmp --tmpfs /var/tmp -v /etc/localtime:/etc/localtime:ro -u 1000 -v ci_jenkins_agent:/home/jenkins --ulimit nofile=1024:1024 "
  common_env_args = ["LANG=en_US.UTF-8", "BUILD_ID=${BUILD_ID}", "WORKSPACE=${WORKSPACE}", "JENKINS_URL=${JENKINS_URL}" ]
  common_docker_params = add_env( common_docker_params, common_env_args )

  stage('Docker Run Check') {
    dir('ci-scripts') {
      git(url:params.CI_REPO, branch:params.CI_BRANCH)
    }
    sh "${WORKSPACE}/ci-scripts/docker_run_check.sh"
  }

  stage('Cache Sources') {
    dir('ci-scripts') {
      git(url:params.CI_REPO, branch:params.CI_BRANCH)
    }

    def env_args = ["BASE=${WORKSPACE}/..", "REMOTE=${REMOTE}"]
    def docker_params = add_env( common_docker_params, env_args )
    if (params.GIT_CREDENTIAL == "enable") {
      withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId:"${GIT_CREDENTIAL_ID}", usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
        writeFile (file: "credentials.txt", text: "${USERNAME}:${PASSWORD}")
      }
    }

    def cmd="${WORKSPACE}/ci-scripts/wrlinux_update.sh ${BRANCH}"
    sh "docker run ${docker_params} ${REGISTRY}/${IMAGE} ${cmd}"

    // cleanup credentials
    if (params.GIT_CREDENTIAL == "enable") {
      sh "rm -f credentials.txt url_credentials.txt"
    }
  }

  stage('Layerindex Setup') {
    // if devbuilds are enabled, start build in same network as layerindex
    if (params.DEVBUILD_ARGS != "") {
      dir('ci-scripts') {
        git(url:params.CI_REPO, branch:params.CI_BRANCH)
      }
      devbuild = readYaml text: params.DEVBUILD_ARGS
      devbuild_env = ["LAYERINDEX_SOURCE=${LAYERINDEX_SOURCE}"]
      devbuild_env = devbuild_env + ["BITBAKE_REPO_URL=${BITBAKE_REPO_URL}"]
      withEnv(devbuild_env) {
        dir('ci-scripts/layerindex') {
          try {
            sh "./layerindex_start.sh --type=${LAYERINDEX_TYPE}"
            for ( repo in devbuild.repos ) {
              for ( layer in repo.layers ) {
                layer_args = [
                  "DEVBUILD_LAYER_NAME=${layer}",
                  "DEVBUILD_LAYER_VCS_URL=${repo.repo}",
                  "DEVBUILD_LAYER_ACTUAL_BRANCH=${repo.branch}"]
                if (!repo.repo.endsWith(layer)) {
                  layer_args = layer_args + ["DEVBUILD_LAYER_VCS_SUBDIR=${layer}"]
                }
                withEnv(layer_args) {
                  sh "./layerindex_layer_update.sh"
                }
              }
            }
            sh "./layerindex_export.sh --branch=${BRANCH}"
            sh "mv -f layerindex.json ${WORKSPACE}"
          } finally {
            sh "./layerindex_stop.sh"
          }
        }
      }
    }
    else {
      println("Not starting local LayerIndex")
    }
  }

  try {
    stage('Build') {
      dir('ci-scripts') {
        git(url:params.CI_REPO, branch:params.CI_BRANCH)
      }

      def docker_params = common_docker_params
      def env_args = ["MESOS_TASK_ID=${BUILD_ID}", "BASE=${WORKSPACE}", "REMOTE=${REMOTE}"]
      if (params.TOASTER == "enable") {
        docker_params = docker_params + ' --expose=8800 -P '
        env_args = env_args + ["SERVICE_NAME=toaster", "SERVICE_CHECK_HTTP=/health"]
      }

      env_args = env_args + ["NAME=${NAME}", "BRANCH=${BRANCH}"]
      env_args = env_args + ["NODE_NAME=${NODE_NAME}", "SETUP_ARGS=\'${SETUP_ARGS}\'"]
      env_args = env_args + ["PREBUILD_CMD=\'${PREBUILD_CMD}\'", "PREBUILD_CMD_FOR_TEST=\'${PREBUILD_CMD_FOR_TEST}\'"]
      env_args = env_args + ["TEST=${TEST}", "TEST_CONFIGS_FILE=${TEST_CONFIGS_FILE}"]
      env_args = env_args + ["BUILD_CMD=\'${BUILD_CMD}\'", "TOASTER=${TOASTER}"]
      env_args = env_args + ["BUILD_CMD_FOR_TEST=\'${BUILD_CMD_FOR_TEST}\'"]
      docker_params = add_env( docker_params, env_args )
      def cmd="${WORKSPACE}/ci-scripts/jenkins_build.sh"

      try {
        sh "docker run ${docker_params} ${REGISTRY}/${IMAGE} ${cmd}"
      } catch (err) {
        def err_message = err.getMessage()
        if (err_message == "script returned exit code 2") {
          echo "Build stage succeeded but with errors!"
          currentBuild.result = 'UNSTABLE'
        }
        else {
          echo "Build stage failed!"
          currentBuild.result = 'FAILURE'
          throw err
        }
      }
    }
  } finally {
    stage('Post Process') {
      dir('ci-scripts') {
        git(url:params.CI_REPO, branch:params.CI_BRANCH)
      }
      def docker_params = common_docker_params + " --network=rsync_net "
      def env_args = ["NAME=${NAME}"]
      env_args = env_args + ["POST_SUCCESS=${POST_SUCCESS}", "POST_FAIL=${POST_FAIL}", "TEST=" + params.TEST]
      env_args = env_args + params.POSTPROCESS_ARGS.tokenize(',')
      docker_params = add_env( docker_params, env_args )
      def cmd="${WORKSPACE}/ci-scripts/build_postprocess.sh"
      sh "docker run --init ${docker_params} ${REGISTRY}/${POSTPROCESS_IMAGE} ${cmd}"
    }
  }

  try {
    stage('Test') {
      if (params.TEST != 'disable' && params.TEST != '') {
        dir('ci-scripts') {
          git(url:params.CI_REPO, branch:params.CI_BRANCH)
        }
        def docker_params = common_docker_params
        def env_args = ["NAME=${NAME}"]
        env_args = env_args + ["TEST=" + params.TEST, "RUNTIME_TEST_CMD=\'${RUNTIME_TEST_CMD}\'"]
        env_args = env_args + params.TEST_ARGS.tokenize(',')
        env_args = env_args + params.POSTPROCESS_ARGS.tokenize(',')
        docker_params = add_env( docker_params, env_args )
        def cmd="${WORKSPACE}/ci-scripts/${RUNTIME_TEST_CMD}"
        sh "docker run --init ${docker_params} ${REGISTRY}/${TEST_IMAGE} ${cmd}"
      } else {
        println("Test is disabled, ignore 'Test' stage.")
      }
    }
  } finally {
    stage('Post Test') {
      if (params.TEST != 'disable' && params.TEST != '') {
        dir('ci-scripts') {
          git(url:params.CI_REPO, branch:params.CI_BRANCH)
        }
        def docker_params = common_docker_params
        def env_args = ["NAME=${NAME}"]
        env_args = env_args + ["POST_TEST_SUCCESS=${POST_TEST_SUCCESS}", "POST_TEST_FAIL=${POST_TEST_FAIL}"]
        env_args = env_args + params.TEST_ARGS.tokenize(',')
        env_args = env_args + params.POSTPROCESS_ARGS.tokenize(',')
        docker_params = add_env( docker_params, env_args )
        def cmd="${WORKSPACE}/ci-scripts/test_postprocess.sh"
        sh "docker run --init ${docker_params} ${REGISTRY}/${POST_TEST_IMAGE} ${cmd}"
      } else {
        println("Test is disabled, ignore 'Post Test' stage.")
      }
    }
  }
}
