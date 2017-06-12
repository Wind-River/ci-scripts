#!/usr/bin/env groovy

node('docker') {
  stage('Test') {
    dir('wr-buildscripts') {
      git(url:'git://ala-git.wrs.com/lpd-ops/wr-buildscripts.git', branch:'jenkins')
    }
    docker.withRegistry('http://wr-docker-registry:5000') {
      docker.image("${IMAGE}").inside('--tmpfs /tmp --tmpfs /var/tmp -v /etc/localtime:/etc/localtime:ro -u 1000') {
        withEnv(['LANG=en_US.UTF-8', "MESOS_TASK_ID=${BUILD_ID}", "BASE=${WORKSPACE}", "LOCATION=yow"]) {
          sh "${WORKSPACE}/wr-buildscripts/wrlinux_update.sh ${BRANCH}"
          sh "mkdir -p ${WORKSPACE}/builds"
          sh "${WORKSPACE}/wr-buildscripts/jenkins_build.sh"
        }
      }
    }
  }
}
