import java.util.*

def boolean run(final Object... args) {
    def authentication = args[0]
    def principal = args[1]
    def registeredService = args[2]
    def provider = args[3]
    def logger = args[4]
    def httpRequest = args[5]

    // Example: Ignore MFA for everyone, except casuser
    //logger.info("Evaluating multifactor authn bypass rules for {}", principal)
    //return principal.id.equalsIgnoreCase("casuser")

    return true
}

