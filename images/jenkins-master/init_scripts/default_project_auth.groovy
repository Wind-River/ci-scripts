import jenkins.*
import jenkins.model.*
import hudson.model.*
import jenkins.model.Jenkins
import org.jenkinsci.plugins.authorizeproject.*
import org.jenkinsci.plugins.authorizeproject.strategy.*
import jenkins.security.QueueItemAuthenticatorConfiguration

def instance = Jenkins.getInstance()

// default to running jobs as user that triggered them
def authenticators = QueueItemAuthenticatorConfiguration.get().getAuthenticators()
authenticators.add(new GlobalQueueItemAuthenticator(new TriggeringUsersAuthorizationStrategy()))

instance.save()
