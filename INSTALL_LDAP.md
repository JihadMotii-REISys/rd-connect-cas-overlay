#Installing and configuring OpenLDAP

```bash
    apt-get update
    apt-get install slapd
    apt-get install ldap-utils
```
* Open /etc/ldap/ldap.conf and write:
            #
            # LDAP Defaults
            #

            # See ldap.conf(5) for details
            # This file should be world readable but not world writable.

            BASE    dc=rd-connect,dc=eu
            URI     ldap://ldap.rd-connect.eu

            # TLS certificates (needed for GnuTLS)
            #TLS_CACERT     /etc/ssl/certs/cacert.pem
            #TLS_REQCERT     never
            #CA_CERTREQ      never
```bash
    dpkg-reconfigure slapd
```
* Select NO and follow the guide, type in your domain, e.g. example.com, choose recommend settings.

#Installing and configuring phpldapadmin and SSL/TLS

```bash
    apt-get install phpldapadmin
```
* Open /etc/phpldapadmin/config.php and change values to:
        $servers = new Datastore();
        $servers->newServer('ldap_pla');
        $servers->setValue('server','name','RD-Connect LDAP Server');
        $servers->setValue('server','host','ldap.rd-connect.eu');
        $servers->setValue('server','port',389);
        $servers->setValue('server','base',array('dc=rd-connect,dc=eu'));
        $servers->setValue('login','bind_id','cn=admin,dc=rd-connect,dc=eu');

* Adding objects People / Groups

    Click Create new entry here > Click Generic: Organization Unit > Name the unit people > Commit
    Click Create new entry here > Click Generic: Organization Unit > Name the unit groups > Commit
    Click ou=groups > Click Create a child entry > Click Generic: Posix Group > Name the group genusers for "General users"
    Click ou=people > Click Create a child entry > Click Generic: User Account > Name the user fill in the relevant fields. Be sure to assign user to genusers GID.

#SSL/TLS for OpenLDAP. 

* We will use the Certificate Authority created in [a relative link](INSTALL_CA.md)
```bash
    apt-get update
    apt-get install gnutls-bin

    certtool --generate-privkey --outfile /root/certs/serverkey.pem

    certtool --generate-certificate --load-privkey /root/certs/serverkey.pem --outfile /root/certs/servercrt.pem --load-ca-certificate /etc/ssl/rdconnect_demo_CA/cacert.pem --load-ca-privkey /etc/ssl/rdconnect_demo_CA/cacert.key
    (Be sure the common name matches the hostname of the OpenLDAP server)
```
* Install the certs
```bash
        install -D -o openldap -g openldap -m 600 /root/certs/servercrt.pem /etc/ssl/certs/servercrt.pem
        install -D -o openldap -g openldap -m 600 /root/certs/serverkey.pem /etc/ssl/certs/serverkey.pem
        install -D -o openldap -g openldap -m 600 /etc/ssl/rdconnect_demo_CA /etc/ssl/certs/cacert.pem
```
* Create ldif file (/etc/ldap/ssl.ldif) for importing into the configuration database. With this content:

        dn: cn=config
        changetype: modify
        #replace: olcTLSCipherSuite
        #olcTLSCipherSuite: NORMAL
        #changetype: modify
        #-
        replace: olcTLSVerifyClient
        olcTLSVerifyClient:     never
        -
        replace: olcTLSCACertificateFile
        olcTLSCACertificateFile: /etc/ssl/certs/cacert.pem
        -
        replace: olcTLSCertificateFile
        olcTLSCertificateFile: /etc/ssl/certs/servercrt.pem
        -
        replace: olcTLSCertificateKeyFile
        olcTLSCertificateKeyFile: /etc/ssl/certs/serverkey.pem

* Import the settings with ldapmodify:
```bash
        ldapmodify -Y EXTERNAL -H ldapi:/// -f /etc/ldap/ssl.ldif
```
* By default, slapd runs as user/group openldap, so it can't read the key file. On Debian Lenny, the preferred solution to this dilemma seems to be to chown the key to root:ssl-cert, set permissions to 640 and add the user openldap to group ssl-cert:
```bash
        usermod -a -G ssl-cert openldap
```
* If starting slapd, we get in /var/log/syslog [...] main: TLS init def ctx failed: -1  We have to uncomment line TLSCipherSuite NORMAL like this:

        dn: cn=config
        changetype: modify
        replace: olcTLSCipherSuite
        olcTLSCipherSuite: NORMAL
        #changetype: modify
        -
        replace: olcTLSVerifyClient
        olcTLSVerifyClient:     never
        -
        replace: olcTLSCACertificateFile
        olcTLSCACertificateFile: /etc/ssl/certs/cacert.pem
        -
        replace: olcTLSCertificateFile
        olcTLSCertificateFile: /etc/ssl/certs/servercrt.pem
        -
        replace: olcTLSCertificateKeyFile
        olcTLSCertificateKeyFile: /etc/ssl/certs/serverkey.pem

        And run again: ldapmodify -Y EXTERNAL -H ldapi:/// -f /etc/ldap/ssl.ldif

* An output of a working version of ldapmodify is:

        ldap_initialize( ldapi:///??base )
        SASL/EXTERNAL authentication started
        SASL username: gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth
        SASL SSF: 0
        add olcTLSCACertificateFile:
                /etc/ssl/certs/ldap-ca-cert.pem
        add olcTLSCertificateFile:
                /etc/ssl/certs/ldap-server.crt
        add olcTLSCertificateKeyFile:
                /etc/ssl/certs/ldap-server.key
        modifying entry "cn=config"
        modify complete


#Make OpenLDAP listen on SSL port

    * Modify /etc/default/slapd. Find the line that says:
    SLAPD_SERVICES="ldap:/// ldapi:///"
    Modify it to say
    SLAPD_SERVICES="ldap://ip_ldap/ ldapi://ip_ldap/ ldaps://ip_ldap/"   (Change ip_ldap with your ldap server IP)
```bash
    service slapd restart
```
    * To verify the new configuration ```bash netstat -nap|grep slapd ```
    * Should see something like this:

            tcp        0      0 ip_ldap:636          0.0.0.0:*               LISTEN      28879/slapd
            tcp        0      0 ip_ldap:389          0.0.0.0:*               LISTEN      28879/slapd
            tcp        0      0 ip_ldap:636          ip_ldap:55574        ESTABLISHED 28879/slapd
            unix  2      [ ACC ]     STREAM     LISTENING     106783   28879/slapd         /var/run/slapd/ldapi
            unix  2      [ ]         DGRAM                    106779   28879/slapd

#Fix untrusted certificate problem
    * Uncomment lines in /etc/ldap/ldap.conf
        #
        # LDAP Defaults
        #

        # See ldap.conf(5) for details
        # This file should be world readable but not world writable.

        BASE    dc=rd-connect,dc=eu
        URI     ldap://ldap.rd-connect.eu

        # TLS certificates (needed for GnuTLS)
        TLS_CACERT     /etc/ssl/certs/cacert.pem
        TLS_REQCERT     never
        CA_CERTREQ      never
```bash
    service slapd restart
```

#Setup secure configuration for phpldapadmin 
* Following this link (https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-openldap-and-phpldapadmin-on-an-ubuntu-14-04-server) and starting from "Create an SSL Certificate".
* If you get an error "Error trying to get a non-existant value (appearance,password_hash)" when adding a new user, you should change password_hashen in file /usr/share/phpldapadmin/lib/TemplateRender.php to password_hash_custom (line 2469)

#Configuring cas.properties file in etc/cas/cas.properties

    The ldap.trustedCert parameter line should have this sintaxis:
        ldap.trustedCert=file:path_to_cacert.pem
