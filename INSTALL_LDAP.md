#Installing and configuring OpenLDAP

* First, the LDAP server host must have its official name, either through the name server or using a new /etc/hosts entry. We are assuming along this document that the name is `ldap.rd-connect.eu`.
* Then, this branch must be in the /tmp directory of the host, as next steps assume it:

```bash
git clone https://github.com/inab/ldap-rest-cas4-overlay.git /tmp/cas-5.3.x
```

* If you are using Ubuntu 14.04 (or compatible), install next packages

```bash
    apt-get update
    apt-get install slapd
    apt-get install ldap-utils
    apt-get install gnutls-bin
```

* If you are using Centos 7 (or compatible), install next packages (see also [this](http://www.server-world.info/en/note?os=CentOS_7&p=openldap&f=1))

```bash
yum -y install openldap-servers openldap-clients gnutls-utils patch
```

You can find the LDAP initialization script at [ldap-schemas/setup-ldap.sh](ldap-schemas/setup-ldap.sh), which must be run as administrator. This setup script expects to be run in an unconfigured LDAP system, and at least 2 parameters:

	* A directory with the public CA key and a subdirectory with the LDAP public and private keys
	
	* The relative name of the LDAP keys inside the directory provided in the first parameter
	
The third and fourth parameter have to be used to tell the custom way to start and stop the LDAP server.

