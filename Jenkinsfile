#!/usr/bin/env groovy

node('docker') {
  stage('Docker Run Check') {
    dir('ci-scripts') {
      git(url:'git://ala-git.wrs.com/projects/wrlinux-ci/ci-scripts.git', branch:'master')
    }
    sh "${WORKSPACE}/ci-scripts/docker_run_check.sh"
  }
  stage('Cache Sources') {
    dir('ci-scripts') {
      git(url:'git://ala-git.wrs.com/projects/wrlinux-ci/ci-scripts.git', branch:'master')
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
      git(url:'git://ala-git.wrs.com/projects/wrlinux-ci/ci-scripts.git', branch:'master')
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
}
