ldap-rest-cas4-overlay (based on simple-cas4-overlay-template)
==============================================================

CAS maven war overlay with LDAP and database authentication, and connection throttling, for CAS 4.x line

# Versions
```xml
<cas.version>4.0.1</cas.version>
```

# Recommended Requirements
* JDK 1.7+
* Apache Maven 3+
* Servlet container supporting Servlet 3+ spec (e.g. Apache Tomcat 7+)

# Configuration
The `etc` directory contains the sample configuration files and "service" directory that would need to be copied to an external file system location (`${user.home}/etc/cas` by default)
and configured to satisfy local CAS installation needs. Current files are:

* `cas.properties`
* `log4j.xml`
* `service` (directory)

# Deployment

* Execute `mvn clean package`
* Deploy resultant `target/cas.war` to a servlet container of choice. If it is Tomcat, you can use ant.
