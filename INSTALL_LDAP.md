#Installing and configuring OpenLDAP

* First, the LDAP server host must have its official name, either through the name server or using a new /etc/hosts entry.
* Then, this branch must be in the /tmp directory of the host, as next steps assume it:

```bash
git clone -b cas-4.1.x https://github.com/inab/ldap-rest-cas4-overlay.git /tmp/ldap-cas-4.1.x
```

* If you are using Ubuntu 14.04 (or compatible), install next packages

```bash
    apt-get update
    apt-get install slapd
    apt-get install ldap-utils
    apt-get install gnutls-bin
```

* If you are using Centos 7 (or compatible), install next packages (see also [http://www.server-world.info/en/note?os=CentOS_7&p=openldap&f=1](this))

```bash
yum -y install openldap-servers openldap-clients gnutls-utils
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap. /var/lib/ldap/DB_CONFIG
systemctl start slapd
systemctl enable slapd
```

* Setting the password for openldap administrator is easy (substituting `CHANGEIT` by a real password):
  

```bash
adminHashPass="$(slappasswd -s 'CHANGEIT')"
cat > /tmp/chrootpw.ldif <<EOF
# specify the password generated above for "olcRootPW" section

dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $adminHashPass

EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/chrootpw.ldif
```

* Now, let's add the needed LDAP schemas, so we are going to regenerate them. We need to create a file /tmp/all-schemas.conf, which points to all of the schemas just in use. This is the content of the file for for Ubuntu:

```
include /etc/ldap/schema/core.schema
include /etc/ldap/schema/cosine.schema
include /etc/ldap/schema/nis.schema
include /etc/ldap/schema/inetorgperson.schema
include /tmp/ldap-cas-4.1.x/ldap-schemas/rd-connect-common.schema
include /tmp/ldap-cas-4.1.x/ldap-schemas/basicRDproperties.schema
include /tmp/ldap-cas-4.1.x/ldap-schemas/cas-management.schema
include /tmp/ldap-cas-4.1.x/ldap-schemas/pwm.schema
```

and this is for CentOS:

```
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/nis.schema
include /etc/openldap/schema/inetorgperson.schema
include /tmp/ldap-cas-4.1.x/ldap-schemas/rd-connect-common.schema
include /tmp/ldap-cas-4.1.x/ldap-schemas/basicRDproperties.schema
include /tmp/ldap-cas-4.1.x/ldap-schemas/cas-management.schema
include /tmp/ldap-cas-4.1.x/ldap-schemas/pwm.schema
```

so we run next command in order to generate the needed LDIFs:

```bash
mkdir -p /tmp/ldap-ldifs/fixed
slaptest -f /tmp/all-schemas.conf -F /tmp/ldap-ldifs
for f in /tmp/ldap-ldifs/cn\=config/cn\=schema/*ldif ; do
sed -rf /tmp/ldap-cas-4.1.x/ldap-schemas/fix-ldifs.sed "$f" > /tmp/ldap-ldifs/fixed/"$(basename "$f")"
done
# It rejects duplicates
for f in /tmp/ldap-ldifs/fixed/*.ldif ; do
ldapadd -Y EXTERNAL -H ldapi:/// -f "$f"
done
```

* In order to create the domain, you must run next sentence. You must change `OTHERCHANGEIT` by a real password for the rd-connect.eu LDAP domain administrator, and `LASTCHANGEIT` by a real password for the 'root' user, usable under CAS and other services which rely on OpenLDAP settings.

```bash
domainHashPass="$(slappasswd -s 'OTHERCHANGEIT')"
domainDN='dc=rd-connect,dc=eu'
adminName='admin'
adminDN="cn=$adminName,$domainDN"
cat > /tmp/chdomain.ldif <<EOF
# replace to your own domain name for "dc=***,dc=***" section
# specify the password generated above for "olcRootPW" section

dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth"
  read by dn.base="$adminDN" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $domainDN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: $adminDN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $domainHashPass

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by
  dn="$adminDN" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="$adminDN" write by * read
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/chdomain.ldif

rootHashPass="$(slappasswd -s 'LASTCHANGEIT')"
cat > /tmp/basedomain.ldif <<EOF
# replace to your own domain name for "dc=***,dc=***" section

dn: $domainDN
objectClass: top
objectClass: dcObject
objectclass: organization
o: RD-Connect
dc: rd-connect

dn: $adminDN
objectClass: organizationalRole
cn: $adminName
description: RD-Connect LDAP domain manager

dn: ou=people,$domainDN
objectClass: organizationalUnit
ou: people
description: RD-Connect platform users

dn: ou=groups,$domainDN
objectClass: organizationalUnit
ou: groups
description: RD-Connect platform groups

dn: ou=admins,ou=people,$domainDN
objectClass: organizationalUnit
ou: admins
description: RD-Connect platform privileged users

dn: ou=services,$domainDN
objectClass: organizationalUnit
ou: services
description: RD-Connect platform allowed services

dn: cn=root,ou=admins,ou=people,$domainDN
objectClass: inetOrgPerson
objectClass: basicRDproperties
uid: root
disabledAccount: FALSE
userPassword: $rootHashPass
cn: root
sn: root
mail: platform@rd-connect.eu
description: A user named root

dn: cn=admin,ou=groups,$domainDN
objectClass: groupOfNames
cn: admin
member: cn=root,ou=admins,ou=people,$domainDN
owner: cn=root,ou=admins,ou=people,$domainDN
description: Users with administration privileges

dn: cn=pwmAdmin,ou=groups,$domainDN
objectClass: groupOfNames
cn: pwmAdmin
member: cn=root,ou=admins,ou=people,$domainDN
owner: cn=root,ou=admins,ou=people,$domainDN
description: Users with administration privileges on PWM
EOF
ldapadd -x -D "$adminDN" -W -f /tmp/basedomain.ldif

cat > /tmp/memberOfModify.ldif <<EOF
dn: cn=root,ou=admins,ou=people,$domainDN
changetype: modify
add: memberOf
memberOf: cn=admin,ou=groups,$domainDN
memberOf: cn=pwmAdmin,ou=groups,$domainDN
EOF
ldapmodify -x -D "$adminDN" -W -f /tmp/memberOfModify.ldif
```

* As root, open /etc/ldap/ldap.conf (if you are using Ubuntu) or /etc/openldap/ldap.conf (if you are using CentOS) and change `BASE` declaration to `BASE    dc=rd-connect,dc=eu` (this only affects OpenLDAP clients).

    In the case of CentOS, you may have to restart the service running `systemctl restart slapd`.
    
    In the case of Ubuntu you may need either to restart the service running `service slapd restart`.

#SSL/TLS for OpenLDAP.

* First, we are going to generate a key pair for ldaps:// protocol. GnuTLS executables are going to be used, and they were installed at the beginning. We will use the Certificate Authority created following [this procedure](INSTALL_CA.md)

```bash
mkdir -p "${HOME}"/ldap-certs
certtool --generate-privkey --outfile "${HOME}"/ldap-certs/ldap-server-key.pem

# See below what you have to answer
certtool --generate-certificate --load-privkey "${HOME}"/ldap-certs/ldap-server-key.pem --outfile "${HOME}"/ldap-certs/ldap-server-crt.pem --load-ca-certificate /etc/pki/CA/cacert.pem --load-ca-privkey /etc/pki/CA/private/cakey.pem
```

    Be sure the common name matches the hostname of the OpenLDAP server

```
Common name: ldap.rd-connect.eu
UID: 
Organizational unit name: 
Organization name: 
Locality name: 
State or province name: Madrid
Country name (2 chars): ES
Enter the subject's domain component (DC): 
This field should not be used in new certificates.
E-mail: 
Enter the certificate's serial number in decimal (default: 6208555100061008756): 


Activation/Expiration time.
The certificate will expire in (days): 50000


Extensions.
Does the certificate belong to an authority? (y/N): 
Is this a TLS web client certificate? (y/N): 
Will the certificate be used for IPsec IKE operations? (y/N): 
Is this a TLS web server certificate? (y/N): Y
Enter a dnsName of the subject of the certificate: ldap.rd-connect.eu
Enter a dnsName of the subject of the certificate: 
Enter a URI of the subject of the certificate: ldaps://ldap.rd-connect.eu/
Enter a URI of the subject of the certificate: 
Enter the IP address of the subject of the certificate: 
Will the certificate be used for signing (DHE and RSA-EXPORT ciphersuites)? (Y/n): 
Will the certificate be used for encryption (RSA ciphersuites)? (Y/n): 
```

* (CentOS) Install the certificates on LDAP server

```bash
mkdir -p /etc/openldap/certs
install -D -o ldap -g ldap -m 644 "${HOME}"/ldap-certs/ldap-server-crt.pem /etc/openldap/certs/ldap-server-crt.pem
install -D -o ldap -g ldap -m 600 "${HOME}"/ldap-certs/ldap-server-key.pem /etc/openldap/certs/ldap-server-key.pem
install -D -o ldap -g ldap -m 644 /etc/pki/CA/cacert.pem /etc/openldap/certs/cacert.pem
cat > /tmp/mod_ldap_ssl_centos.ldif <<EOF
# create new

dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/openldap/certs/cacert.pem
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/ldap-server-crt.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/ldap-server-key.pem
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/mod_ldap_ssl_centos.ldif
```

* (Ubuntu) Install the certificates on LDAP server

```bash
mkdir -p /etc/ldap/certs
install -D -o openldap -g openldap -m 644 "${HOME}"/ldap-certs/ldap-server-crt.pem /etc/ldap/certs/ldap-server-crt.pem
install -D -o openldap -g openldap -m 600 "${HOME}"/ldap-certs/ldap-server-key.pem /etc/ldap/certs/ldap-server-key.pem
install -D -o openldap -g openldap -m 644 /etc/pki/CA/cacert.pem /etc/ldap/certs/cacert.pem
cat > /tmp/mod_ldap_ssl_ubuntu.ldif <<EOF
# create new

dn: cn=config
changetype: modify
replace: olcTLSVerifyClient
olcTLSVerifyClient: never
-
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ldap/certs/cacert.pem
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ldap/certs/ldap-server-crt.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ldap/certs/ldap-server-key.pem
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/mod_ldap_ssl_ubuntu.ldif
```

* (Ubuntu) If starting slapd, we get in /var/log/syslog [...] main: TLS init def ctx failed: -1  We have to uncomment line TLSCipherSuite NORMAL like this:

        dn: cn=config
        changetype: modify
        replace: olcTLSCipherSuite
        olcTLSCipherSuite: NORMAL
        #changetype: modify

        And run again: ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/mod_ldap_ssl_ubuntu.ldif

* (Ubuntu) An output of a working version of ldapmodify is:

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

* (CentOS) Modify /etc/sysconfig/slapd. Find the line which defines `SLAPD_URLS`, and rewrite it like this:

```
SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"
```

  Also, open /etc/openldap/ldap.conf and change `URI`, `TLS_REQCERT` and `TLS_CACERT` declarations to the ones shown below (needed by LDAP client):

```
URI	ldap:// ldaps:// ldapi://
TLS_REQCERT allow
TLS_CACERT     /etc/openldap/certs/cacert.pem
```

  Finally, restart the service with `systemctl restart slapd`.
    
  * If you are using SELinux (most probably), you will need to run next commands in order to allow LDAP and LDAP TLS:
    
```bash
authconfig --enableldaptls --update
setsebool -P httpd_can_connect_ldap 1
```
  * If you are using nslcd, you will have to run `echo "tls_reqcert allow" >> /etc/nslcd.conf`, and restart nslcd service.

* (Ubuntu) Modify /etc/default/slapd. Find the line which defines `SLAPD_SERVICES`, and rewrite it like this:

```
SLAPD_SERVICES="ldapi:/// ldap:/// ldaps:///"
```

  Also, open /etc/ldap/ldap.conf and change `URI`, `TLS_REQCERT` and `TLS_CACERT`declarations to the ones shown below (needed by LDAP client):

```
URI	ldap:// ldaps:// ldapi://
TLS_REQCERT allow
TLS_CACERT     /etc/ldap/certs/cacert.pem
```

  Finally, restart the service with `service slapd restart`

* To verify the new configuration `netstat -nap|grep slapd `. Should see something like this:

```
tcp        0      0 ip_ldap:636          0.0.0.0:*               LISTEN      28879/slapd
tcp        0      0 ip_ldap:389          0.0.0.0:*               LISTEN      28879/slapd
tcp        0      0 ip_ldap:636          ip_ldap:55574        ESTABLISHED 28879/slapd
unix  2      [ ACC ]     STREAM     LISTENING     106783   28879/slapd         /var/run/slapd/ldapi
unix  2      [ ]         DGRAM                    106779   28879/slapd
```

# (Ubuntu) Fix untrusted certificate problem
* Uncomment lines in /etc/ldap/ldap.conf or /etc/openldap/ldap.conf
```
# TLS certificates (needed for GnuTLS)
TLS_CACERT     /etc/ssl/certs/cacert.pem
TLS_REQCERT     never
CA_CERTREQ      never
```

# (CentOS) Install phpldapadmin (and a web server)

```bash
yum -y install httpd
# Remove welcome page
rm -f /etc/httpd/conf.d/welcome.conf
yum -y install epel-release
yum repolist
yum --enablerepo=epel -y install phpldapadmin
```

* (Optional) Edit /etc/httpd/conf/httpd.conf and apply next changes:

```apache
# line 86: change to admin's email address

ServerAdmin root@ldap.rd-connect.eu
# line 95: change to your server's name

ServerName ldap.rd-connect.eu:80
# line 151: change

AllowOverride All
# line 164: add file name that it can access only with directory's name

DirectoryIndex index.html index.cgi index.php
# add follows to the end

# server's response header

ServerTokens Prod
# keepalive is ON

KeepAlive On
```

  and start the service

```bash
systemctl start httpd
systemctl enable httpd
```

* Configure phpldapadmin, by editing /etc/phpldapadmin/config.php

```
# line 291: set connection parameters
$servers->setValue('server','name','RD-Connect LDAP Server');
$servers->setValue('server','host','ldap.rd-connect.eu');
$servers->setValue('server','port',389);
$servers->setValue('server','base',array('dc=rd-connect,dc=eu'));
$servers->setValue('login','bind_id','');
$servers->setValue('login','bind_pass','');
$servers->setValue('server','tls',true);

# line 397: uncomment, line 398: comment out

$servers->setValue('login','attr','dn');
// $servers->setValue('login','attr','uid'); 

```



#Setup secure configuration for phpldapadmin 
* Following this link (https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-openldap-and-phpldapadmin-on-an-ubuntu-14-04-server) and starting from "Create an SSL Certificate".
* If you get an error "Error trying to get a non-existant value (appearance,password_hash)" when adding a new user, you should change password_hashen in file /usr/share/phpldapadmin/lib/TemplateRender.php to password_hash_custom (line 2469)

#Configuring cas.properties file in etc/cas/cas.properties

The ldap.trustedCert parameter line should have this sintaxis:
        
	ldap.trustedCert=file:path_to_cacert.pem

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

