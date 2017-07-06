#!/usr/bin/env groovy

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
  stage('Docker Run Check') {
    dir('ci-scripts') {
      git(url:'git://ala-git.wrs.com/projects/wrlinux-ci/ci-scripts.git', branch:"${CI_BRANCH}")
    }
    sh "${WORKSPACE}/ci-scripts/docker_run_check.sh"
  }
  stage('Cache Sources') {
    dir('ci-scripts') {
      git(url:'git://ala-git.wrs.com/projects/wrlinux-ci/ci-scripts.git', branch:"${CI_BRANCH}")
    }
    docker.withRegistry('http://${REGISTRY}') {
      docker.image("${IMAGE}").inside('--tmpfs /tmp --tmpfs /var/tmp -v /etc/localtime:/etc/localtime:ro -u 1000') {
        withEnv(['LANG=en_US.UTF-8', "BASE=${WORKSPACE}", "LOCATION=yow"]) {
          sh "${WORKSPACE}/ci-scripts/wrlinux_update.sh ${BRANCH}"
        }
      }
    }
  }
  stage('Build') {
    dir('ci-scripts') {
      git(url:'git://ala-git.wrs.com/projects/wrlinux-ci/ci-scripts.git', branch:"${CI_BRANCH}")
    }
    docker.withRegistry('http://${REGISTRY}') {
      docker.image("${IMAGE}").inside('--tmpfs /tmp --tmpfs /var/tmp -v /etc/localtime:/etc/localtime:ro -u 1000') {
        withEnv(['LANG=en_US.UTF-8', "MESOS_TASK_ID=${BUILD_ID}", "BASE=${WORKSPACE}"]) {
          sh "mkdir -p ${WORKSPACE}/builds"
          sh "${WORKSPACE}/ci-scripts/jenkins_build.sh"
        }
      }
    }
  }

  stage('Post Process') {
    dir('ci-scripts') {
      git(url:'git://ala-git.wrs.com/projects/wrlinux-ci/ci-scripts.git', branch:"${CI_BRANCH}")
    }
    docker.withRegistry('http://${REGISTRY}') {
      def postprocess_args = "${POSTPROCESS_ARGS}".tokenize(',')
      docker.image("${POSTPROCESS_IMAGE}").inside('-v /etc/localtime:/etc/localtime:ro -u 1000') {
        withEnv([postprocess_args]) {
          sh "${WORKSPACE}/ci-scripts/build_postprocess.sh"
        }
      }
    }
  }
}
