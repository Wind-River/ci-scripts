// imports
import jenkins.model.Jenkins
import jenkins.security.s2m.*

Jenkins jenkins = Jenkins.getInstance()

jenkins.getDescriptor("jenkins.CLI").get().setEnabled(false)

// define protocols
HashSet<String> oldProtocols = new HashSet<>(jenkins.getAgentProtocols())
oldProtocols.removeAll(Arrays.asList("JNLP3-connect", "JNLP2-connect", "JNLP-connect", "CLI-connect"))

// set protocols
jenkins.setAgentProtocols(oldProtocols)

// save to disk
jenkins.save()
