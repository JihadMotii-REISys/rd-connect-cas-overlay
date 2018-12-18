RD-Connect CAS Overlay (based on CAS Overlay template)
============================

Cursomized CAS WAR overlay , with support for REST, throttling, SAML 1.1 and LDAP authentication. The RD-Connect CAS services management overlay is available [here](/inab/rd-connect-cas-management-overlay).

# Versions

```xml
<cas.version>5.3.x</cas.version>
```

# Requirements

* JDK 1.8+

# Configuration

The `etc` directory contains the configuration files and directories that need to be copied to `/etc/cas/config`.

# Build and deployment

Follow these [installation instructions](INSTALL.md).

## External

Deploy resultant `target/cas.war` to a servlet container of choice.

# Configuration
The [etc](etc) directory contains the sample configuration files that would need to be copied to an external file system location (`/etc/cas/config` or `${user.home}/etc/cas/config` by default) and configured to satisfy local CAS and CAS Management installation needs. Current files are:

* `cas.properties.template`, which is a template for `cas.properties`.
* `log4j2-user.xml` or `log4j2-system.xml`, depending on a user or a system Tomcat installation.

