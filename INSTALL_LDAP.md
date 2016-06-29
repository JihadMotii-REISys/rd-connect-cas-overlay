#Installing and configuring OpenLDAP

* First, the LDAP server host must have its official name, either through the name server or using a new /etc/hosts entry. We are assuming along this document that the name is `ldap.rd-connect.eu`.
* Then, this branch must be in the /tmp directory of the host, as next steps assume it:

```bash
git clone https://github.com/inab/ldap-rest-cas4-overlay.git /tmp/ldap-cas-4.1.x
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
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap. /var/lib/ldap/DB_CONFIG
```
  Due [a bug](https://bugs.centos.org/view.php?id=8631) in OpenLDAP CentOS package, which would stop restores from a [OpenLDAP backup](http://blog.panek.work/2015/08/29/openldap_backup_restore.html), it is needed to patch the buggy configuration file before first start:

```bash
wget -O /tmp/openldap-centos.patch 'https://bugs.centos.org/file_download.php?file_id=3559&type=bug'
patch -d / -p 0 -N -t --dry-run < /tmp/openldap-centos.patch && patch -d / -p 0 -N -t < /tmp/openldap-centos.patch
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

* Now, let's add the needed LDAP schemas, so we are going to regenerate them. We need to create a file /tmp/all-schemas.conf, which points to all of the schemas just in use. You have to run this in order to generate it for Ubuntu:

```bash
cat > /tmp/all-schemas.conf <<EOF
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/nis.schema
include /etc/openldap/schema/inetorgperson.schema
EOF
for schema in /tmp/ldap-cas-4.1.x/ldap-schemas/*.schema ; do
	echo "include ${schema}" >> /tmp/all-schemas.conf
done
```

and this code snippet for CentOS:

```bash
cat > /tmp/all-schemas.conf <<EOF
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/nis.schema
include /etc/openldap/schema/inetorgperson.schema
EOF
for schema in /tmp/ldap-cas-4.1.x/ldap-schemas/*.schema ; do
	echo "include ${schema}" >> /tmp/all-schemas.conf
done
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
adminGroupDN="cn=admin,ou=groups,$domainDN"
cat > /tmp/chdomain.ldif <<EOF
# Disallow anonymous binds
dn: cn=config
changetype: modify
add: olcDisallows
olcDisallows: bind_anon

# Allow authenticated binds
dn: cn=config
changetype: modify
add: olcRequires
olcRequires: authc

dn: olcDatabase={-1}frontend,cn=config
changetype: modify
add: olcRequires
olcRequires: authc

# replace to your own domain name for "dc=***,dc=***" section
# specify the password generated above for "olcRootPW" section

dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth"
  read by dn.base="$adminDN" read by * none

# We declare an index on uid
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: uid pres,eq

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

# These rules grant write access to LDAP topology parts
# based on admin group
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: to attrs=userPassword,shadowLastChange
  by dn="$adminDN" write
  by group.exact="$adminGroupDN" write
  by anonymous auth
  by self write
  by * none
olcAccess: to dn.children="ou=people,$domainDN"
  attrs=pwmLastPwdUpdate,pwmEventLog,pwmResponseSet,pwmOtpSecret,pwmGUID
  by dn="$adminDN" manage
  by group.exact="$adminGroupDN" manage
  by group.exact="cn=pwmAdmin,ou=groups,$domainDN" manage
  by self manage
  by * none
olcAccess: to dn.children="ou=people,$domainDN"
  by dn="$adminDN" write
  by group.exact="$adminGroupDN" write
  by * read
olcAccess: to dn.children="ou=groups,$domainDN"
  by dn="$adminDN" write
  by group.exact="$adminGroupDN" write
  by * read
olcAccess: to dn.base="" by * read
olcAccess: to * by dn="$adminDN" write by * read
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/chdomain.ldif

# Now, a re-index is issued, as we declared new indexes on uid
systemctl stop sladp
slapindex -b "$domainDN"
systemctl start slapd

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
displayName: root
mail: platform@rd-connect.eu
description: A user named root

dn: $adminGroupDN
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
memberOf: $adminGroupDN
memberOf: cn=pwmAdmin,ou=groups,$domainDN
EOF
ldapmodify -x -D "$adminDN" -W -f /tmp/memberOfModify.ldif

cat > /tmp/defaultservice.ldif <<EOF
# The default service
dn: uid=10000001,ou=services,dc=rd-connect,dc=eu
objectClass: casRegisteredService
uid: 10000001
EOF
base64 /tmp/ldap-cas-4.1.x/etc/services/HTTPS-10000001.json | sed 's#^# #;1 s#^#description::#;' >> /tmp/defaultservice.ldif
ldapadd -x -D "$adminDN" -W -f /tmp/defaultservice.ldif
```

* As root, open /etc/ldap/ldap.conf (if you are using Ubuntu) or /etc/openldap/ldap.conf (if you are using CentOS) and change `BASE` declaration to `BASE    dc=rd-connect,dc=eu` (this only affects OpenLDAP clients).

    In the case of CentOS, you may have to restart the service running `systemctl restart slapd`.
    
    In the case of Ubuntu you may need either to restart the service running `service slapd restart`.

#SSL/TLS for OpenLDAP.

* First, we need a pair of public / private keys for the for ldaps:// protocol. They should be at `"${HOME}"/ldap-certs/ldap-server-crt.pem` and `"${HOME}"/ldap-certs/ldap-server-key.pem`. If they are not already available, they have to be obtained from a CA. GnuTLS executables are going to be used, and they were installed at the beginning. We will use the public and private keys from a Certificate Authority (in this example, `/etc/pki/CA/cacert.pem` and `/etc/pki/CA/private/cakey.pem`. You can create one following [this procedure](INSTALL_CA.md)

```bash
mkdir -p "${HOME}"/ldap-certs
certtool --generate-privkey --outfile "${HOME}"/ldap-certs/ldap-server-key.pem

# The template automates the answers. Beware encrypted CA private key!
certtool --generate-certificate --load-privkey "${HOME}"/ldap-certs/ldap-server-key.pem --template /tmp/ldap-cas-4.1.x/ldap-schemas/certtool-ldap-template.cfg --outfile "${HOME}"/ldap-certs/ldap-server-crt.pem --load-ca-certificate /etc/pki/CA/cacert.pem --load-ca-privkey /etc/pki/CA/private/cakey.pem
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

#####
# Add next lines to the end before the include sentences
####
# server's response header
ServerTokens Prod

# keepalive is ON
KeepAlive On
```

  and start the http service

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

#Configuring cas.properties file in etc/cas/cas.properties

The `ldap.trustedCert` parameter points to the LDAP public key certificate.

So, it should have this content in CentOS:
        
```
ldap.trustedCert=file:/etc/openldap/certs/ldap-server-crt.pem
```

and this content in Ubuntu

```
ldap.trustedCert=file:/etc/ldap/certs/ldap-server-crt.pem
```

# OpenLDAP backup and restore procedures

Instructions at [this link](http://blog.panek.work/2015/08/29/openldap_backup_restore.html)


#Beware!!! Outdated instructions!!! Don't follow them!!!

##Setup secure configuration for phpldapadmin 
* Following this link (https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-openldap-and-phpldapadmin-on-an-ubuntu-14-04-server) and starting from "Create an SSL Certificate".
* If you get an error "Error trying to get a non-existant value (appearance,password_hash)" when adding a new user, you should change password_hashen in file /usr/share/phpldapadmin/lib/TemplateRender.php to password_hash_custom (line 2469)

##Installing and configuring phpldapadmin and SSL/TLS

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
