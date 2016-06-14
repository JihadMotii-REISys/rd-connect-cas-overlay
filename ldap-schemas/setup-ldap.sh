#!/bin/sh

# OpenLDAP initial setup

ldapcasdir="$(dirname "$0")"
case "${ldapcasdir}" in
	/*)
		true
		;;
	*)
		ldapcasdir="${PWD}"/"${ldapcasdir}"
		;;
esac

# Which directory contains the certificates?
if [ $# -gt 0 ] ; then
	ldapCerts="$1"
	if [ $# -gt 2 ] ; then
		openLdapStartCommand="$2"
		openLdapStopCommand="$3"
	else
		openLdapStartCommand="systemctl start sladp"
		openLdapStopCommand="systemctl stop sladp"
	fi
else
	ldapCerts=/tmp/rd-connect_cas_ldap_certs
fi

alreadyGen=/etc/openldap/for_sysadmin.txt

if [ ! -f "${alreadyGen}" ] ; then
	# We want it to exit on first error
	set -e
	
	# Now, first slapd start
	eval "$openLdapStartCommand"
	
	if type apg >/dev/null 2>&1 ; then
		adminPass="$(apg -n 1 -m 12 -x 16 -M ncl)"
		domainPass="$(apg -n 1 -m 12 -x 16 -M ncl)"
		rootPass="$(apg -n 1 -m 12 -x 16 -M ncl)"
	else
		adminPass='CHANGEIT'
		domainPass='OTHERCHANGEIT'
		rootPass='LASTCHANGEIT'
	fi
	# OpenLDAP administrator password
	adminHashPass="$(slappasswd -s "$adminPass")"
	# RD-Connect domain administrator password
	domainHashPass="$(slappasswd -s "$domainPass")"
	# root user (user with administration privileges) password
	rootHashPass="$(slappasswd -s "$rootPass")"


	# Setting up the OpenLDAP administrator password
	cat > /tmp/chrootpw.ldif <<EOF
# specify the password generated above for "olcRootPW" section

dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $adminHashPass

EOF
	ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/chrootpw.ldif

	# Let's add the needed schemas
	cat > /tmp/all-schemas.conf <<EOF
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/nis.schema
include /etc/openldap/schema/inetorgperson.schema
include ${ldapcasdir}/rd-connect-common.schema
include ${ldapcasdir}/basicRDproperties.schema
include ${ldapcasdir}/cas-management.schema
include ${ldapcasdir}/pwm.schema
EOF

	mkdir -p /tmp/ldap-ldifs/fixed
	slaptest -f /tmp/all-schemas.conf -F /tmp/ldap-ldifs
	for f in /tmp/ldap-ldifs/cn\=config/cn\=schema/*ldif ; do
		sed -rf "${ldapcasdir}"/fix-ldifs.sed "$f" > /tmp/ldap-ldifs/fixed/"$(basename "$f")"
	done
	# It rejects duplicates
	for f in /tmp/ldap-ldifs/fixed/*.ldif ; do
		ldapadd -Y EXTERNAL -H ldapi:/// -f "$f" || echo "[NOTICE] File '$f' was skipped"
	done

	# Domain creation
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
	eval "$openLdapStopCommand"
	slapindex -b "$domainDN"
	eval "$openLdapStartCommand"

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

	# Adding the default service
	cat > /tmp/defaultservice.ldif <<EOF
# The default service
dn: uid=10000001,ou=services,dc=rd-connect,dc=eu
objectClass: casRegisteredService
uid: 10000001
EOF
	base64 "${ldapcasdir}"/../etc/services/HTTPS-10000001.json | sed 's#^# #;1 s#^#description::#;' >> /tmp/defaultservice.ldif
	ldapadd -x -D "$adminDN" -W -f /tmp/defaultservice.ldif


	# SSL/TLS for OpenLDAP
	# It assumes that the public and private keys from the Certificate Authority are
	# at /etc/pki/CA/cacert.pem and /etc/pki/CA/private/cakey.pem

	if [ ! -f /etc/openldap/certs/ldap-server-crt.pem ] ; then
		mkdir -p "${HOME}"/ldap-certs
		if [ -f "${ldapCerts}"/cas-ldap/cert.pem ] ;then
			ln -s "${ldapCerts}"/cas-ldap/cert.pem "${HOME}"/ldap-certs/ldap-server-crt.pem
			ln -s "${ldapCerts}"/cas-ldap/key.pem "${HOME}"/ldap-certs/ldap-server-key.pem
			ln -s "${ldapCerts}"/cacert.pem "${HOME}"/ldap-certs/cacert.pem
		else
			if [ ! -f "${HOME}"/ldap-certs/ldap-server-crt.pem ] ; then
				if [ ! -f /etc/pki/CA/cacert.pem ] ; then
					(umask 277 && certtool --generate-privkey --outfile /etc/pki/CA/private/cakey.pem)
					certtool --generate-self-signed \
						--template "${ldapcasdir}"/catemplate.cfg \
						--load-privkey /etc/pki/CA/private/cakey.pem \
						--outfile /etc/pki/CA/cacert.pem
				fi

				certtool --generate-privkey --outfile "${HOME}"/ldap-certs/ldap-server-key.pem

				# See below what you have to answer
				certtool --generate-certificate --load-privkey "${HOME}"/ldap-certs/ldap-server-key.pem --outfile "${HOME}"/ldap-certs/ldap-server-crt.pem --load-ca-certificate /etc/pki/CA/cacert.pem --load-ca-privkey /etc/pki/CA/private/cakey.pem
			fi
			ln -s /etc/pki/CA/cacert.pem "${HOME}"/ldap-certs/cacert.pem
		fi
		mkdir -p /etc/openldap/certs
		install -D -o ldap -g ldap -m 644 "${HOME}"/ldap-certs/ldap-server-crt.pem /etc/openldap/certs/ldap-server-crt.pem
		install -D -o ldap -g ldap -m 600 "${HOME}"/ldap-certs/ldap-server-key.pem /etc/openldap/certs/ldap-server-key.pem
		install -D -o ldap -g ldap -m 644 "${HOME}"/ldap-certs/cacert.pem /etc/openldap/certs/cacert.pem
	fi

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

	# Now, make openLDAP listen on SSL port
	sed -i 's/^\(SLAPD_URLS=.*\)/#\1/' /etc/sysconfig/slapd
	echo 'SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"' >> /etc/sysconfig/slapd

	sed -i 's/^\(URI\|TLS_REQCERT\|TLS_CACERT\)\([ \t].*\)/#\1\2/' /etc/openldap/ldap.conf
	cat >> /etc/openldap/ldap.conf <<EOF
URI ldap:// ldaps:// ldapi://
TLS_REQCERT allow
TLS_CACERT     /etc/openldap/certs/cacert.pem
EOF

	# Restart it
	eval "$openLdapStopCommand"
	eval "$openLdapStartCommand"

	# If you are using SELinux, then these steps are needed
	if type authconfig >/dev/null 2>&1 ; then
		authconfig --enableldaptls --update
	fi
	if type setsebool >/dev/null 2>&1 ; then
		setsebool -P httpd_can_connect_ldap 1
	fi

	# If you are using nslcd, then this step is needed
	if [ -f /etc/nslcd.conf ] ; then
		echo "tls_reqcert allow" >> /etc/nslcd.conf
		systemctl restart nslcd
	fi

	# This last step is needed to save the passwords in clear somewhere
	cat > "${alreadyGen}" <<EOF
adminPass=${adminPass}
domainPass=${domainPass}
rootPass=${rootPass}
EOF
	chmod go= "${alreadyGen}"
fi
