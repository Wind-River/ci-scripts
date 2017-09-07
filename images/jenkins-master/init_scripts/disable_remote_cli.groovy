import jenkins.model.*
Jenkins.instance.getDescriptor("jenkins.CLI").get().setEnabled(false)
