import jenkins.model.*

def Integer numExecutors=0
if (System.env.JENKINS_MASTER_NUM_EXECUTORS) {
  numExecutors=Integer.parseInt(System.env.JENKINS_MASTER_NUM_EXECUTORS)
}

println("Num Master Executors: ${numExecutors}")
Jenkins.instance.setNumExecutors(numExecutors)
