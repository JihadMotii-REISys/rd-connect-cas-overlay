#!/bin/sh

# OpenLDAP initial setup
domainDC='rd-connect'
domainO="RD-Connect"
domainCountry='eu'
domainDN="dc=${domainDC},dc=${domainCountry}"
adminName='admin'
adminDN="cn=$adminName,$domainDN"
adminGroupDN="cn=admin,ou=groups,$domainDN"
mfaGroupDN="cn=mfa-eligible,ou=groups,$domainDN"
rootMail="platform@${domainDC}.${domainCountry}"
demoMail="demo@${domainDC}.${domainCountry}"

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
else
	ldapCerts=/tmp/rd-connect_cas_ldap_certs
fi

# Which directory contains OpenLDAP?
for dir in /etc/openldap /etc/ldap ; do
	if [ -d "$dir" ] ; then
		ldapProfileDir="$dir"
		break
	fi
done

if [ -z "$ldapProfileDir" ] ; then
	echo "ERROR: Unable to find LDAP profile directory!" 1>&2
	exit 1
fi

case "$ldapProfileDir" in
	/etc/openldap)
		base1='{1}monitor'
		base2='{2}hdb'
		ldapUser=ldap
		ldapGroup=ldap
		pwVerb=add
		openLdapStartCommand="systemctl start sladp"
		openLdapStopCommand="systemctl stop sladp"
		;;
	/etc/ldap)
		base1=''
		base2='{1}mdb'
		ldapUser=openldap
		ldapGroup=openldap
		pwVerb=replace
		openLdapStartCommand="/etc/init.d/slapd start"
		openLdapStopCommand="/etc/init.d/slapd stop"
		;;
	*)
		echo "ERROR: Unable to find LDAP profile directory!" 1>&2
		exit 1
		;;
esac

if [ $# -gt 2 ] ; then
	certsDir="$2"
	openLdapStartCommand="$3"
	openLdapStopCommand="$4"
else
	certsDir="cas-ldap"
fi

alreadyGen="${ldapProfileDir}"/for_sysadmin.txt

if [ ! -f "${alreadyGen}" ] ; then
	# We want it to exit on first error
	set -e
	
	# Now, first slapd start
	eval "$openLdapStartCommand"
	
	if type apg >/dev/null 2>&1 ; then
		adminPass="$(apg -n 1 -m 12 -x 16 -M ncl)"
		domainPass="$(apg -n 1 -m 12 -x 16 -M ncl)"
		rootPass="$(apg -n 1 -m 12 -x 16 -M ncl)"
		demoPass="$(apg -n 1 -m 12 -x 16 -M ncl)"
	else
		adminPass='CHANGEIT'
		domainPass='OTHERCHANGEIT'
		rootPass='LASTCHANGEIT'
		demoPass='NOCHANGEIT'
	fi
	# OpenLDAP administrator password
	adminHashPass="$(slappasswd -s "$adminPass")"
	# RD-Connect domain administrator password
	domainHashPass="$(slappasswd -s "$domainPass")"
	# root user (user with administration privileges) password
	rootHashPass="$(slappasswd -s "$rootPass")"
	# demo user (user with no privileges) password
	demoHashPass="$(slappasswd -s "$demoPass")"


	# Setting up the OpenLDAP administrator password
	if grep -qF olcRootPW "${ldapProfileDir}/slapd.d/cn=config/olcDatabase={0}config.ldif" ; then
		rootPwVerb=modify
	else
		rootPwVerb=add
	fi
	cat > /tmp/chrootpw.ldif <<EOF
# specify the password generated above for "olcRootPW" section
dn: olcDatabase={0}config,cn=config
changetype: modify
${rootPwVerb}: olcRootPW
olcRootPW: $adminHashPass

EOF
	ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/chrootpw.ldif

	# Let's add the needed schemas
	cat > /tmp/all-schemas.conf <<EOF
include ${ldapProfileDir}/schema/core.schema
include ${ldapProfileDir}/schema/cosine.schema
include ${ldapProfileDir}/schema/nis.schema
include ${ldapProfileDir}/schema/inetorgperson.schema
EOF
	for schema in "${ldapcasdir}"/*.schema ; do
		echo "include ${schema}" >> /tmp/all-schemas.conf
	done

	mkdir -p /tmp/ldap-ldifs/fixed
	slaptest -f /tmp/all-schemas.conf -F /tmp/ldap-ldifs
	for f in /tmp/ldap-ldifs/cn\=config/cn\=schema/*ldif ; do
		fixedName="$(basename "$f" | sed 's/[0-9]\+_//')"
		sed -rf "${ldapcasdir}"/fix-ldifs.sed "$f" > /tmp/ldap-ldifs/fixed/"${fixedName}"
	done
	# It rejects duplicates
	for f in /tmp/ldap-ldifs/fixed/*.ldif ; do
		ldapadd -Y EXTERNAL -H ldapi:/// -f "$f" || echo "[NOTICE] File '$f' was skipped"
	done

	# Domain creation
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

EOF
	if [ -n "${base1}" ] ; then
		if grep -qF olcAccess "${ldapProfileDir}/slapd.d/cn=config/olcDatabase=${base1}.ldif" ; then
			domainAccVerb=replace
		else
			domainAccVerb=add
		fi
		cat >> /tmp/chdomain.ldif <<EOF
# This operation removes all the access rules
dn: olcDatabase=${base1},cn=config
changetype: modify
${domainAccVerb}: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth"
  read by dn.base="$adminDN" read by * none

EOF
	fi
	
	if [ -d /etc/openldap ] ; then
		cat >> /tmp/chdomain.ldif <<EOF
# We declare an index on uid
dn: olcDatabase=${base2},cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: uid pres,eq

EOF
	elif [ -d /etc/ldap ] ; then
		cat >> /tmp/chdomain.ldif <<EOF
# We declare an index on uid
dn: olcDatabase=${base2},cn=config
changetype: modify
delete: olcDbIndex
olcDbIndex: cn,uid eq

dn: olcDatabase=${base2},cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: cn,mail,surname,givenname eq,pres,sub
olcDbIndex: uid pres,eq
#olcDbIndex: ou,cn,mail,surname,givenname eq,pres,sub
#olcDbIndex: uidNumber,gidNumber eq
#olcDbIndex: member,memberUid eq

EOF
	fi
	
	if grep -qF olcAccess "${ldapProfileDir}/slapd.d/cn=config/olcDatabase=${base2}.ldif" ; then
		domain2AccVerb=replace
	else
		domain2AccVerb=add
	fi
	cat >> /tmp/chdomain.ldif <<EOF
dn: olcDatabase=${base2},cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $domainDN

dn: olcDatabase=${base2},cn=config
changetype: modify
replace: olcRootDN
olcRootDN: $adminDN

dn: olcDatabase=${base2},cn=config
changetype: modify
${pwVerb}: olcRootPW
olcRootPW: $domainHashPass

# These rules grant write access to LDAP topology parts
# based on admin group
dn: olcDatabase=${base2},cn=config
changetype: modify
${domain2AccVerb}: olcAccess
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
o: $domainO
dc: $domainDC

dn: $adminDN
objectClass: organizationalRole
cn: $adminName
description: $domainO LDAP domain manager

dn: ou=people,$domainDN
objectClass: organizationalUnit
ou: people
description: $domainO platform users

dn: ou=groups,$domainDN
objectClass: organizationalUnit
ou: groups
description: $domainO platform groups

dn: ou=admins,ou=people,$domainDN
objectClass: organizationalUnit
ou: admins
description: $domainO platform privileged users

dn: ou=services,$domainDN
objectClass: organizationalUnit
ou: services
description: $domainO platform allowed services

dn: cn=root,ou=admins,ou=people,$domainDN
objectClass: inetOrgPerson
objectClass: basicRDproperties
uid: root
disabledAccount: FALSE
acceptedGDPR: 19700101
userPassword: $rootHashPass
cn: root
sn: root
displayName: root
mail: ${rootMail}
description: A user named root

dn: cn=demo,ou=admins,ou=people,$domainDN
objectClass: inetOrgPerson
objectClass: basicRDproperties
uid: demo
disabledAccount: FALSE
acceptedGDPR: 19700101
userPassword: $demoHashPass
cn: demo
sn: demo
displayName: demo
mail: ${demoMail}
description: The demo user

dn: $adminGroupDN
objectClass: groupOfNames
cn: admin
member: cn=root,ou=admins,ou=people,$domainDN
owner: cn=root,ou=admins,ou=people,$domainDN
description: Users with administration privileges

dn: $mfaGroupDN
objectClass: groupOfNames
cn: mfa-eligible
member: cn=demo,ou=admins,ou=people,$domainDN
owner: cn=root,ou=admins,ou=people,$domainDN
description: Users who have enabled MFA
EOF
	ldapadd -x -D "$adminDN" -w "$domainPass" -f /tmp/basedomain.ldif

	cat > /tmp/memberOfModify.ldif <<EOF
dn: cn=root,ou=admins,ou=people,$domainDN
changetype: modify
add: memberOf
memberOf: $adminGroupDN

dn: cn=demo,ou=admins,ou=people,$domainDN
changetype: modify
add: memberOf
memberOf: $mfaGroupDN
EOF
	ldapmodify -x -D "$adminDN" -w "$domainPass" -f /tmp/memberOfModify.ldif

	# Adding the default service
	cat > /tmp/defaultservice.ldif <<EOF
# The default service
dn: uid=10000001,ou=services,${domainDN}
objectClass: casRegisteredService
uid: 10000001
EOF
	base64 "${ldapcasdir}"/HTTPS-10000001.json | sed 's#^# #;1 s#^#description::#;' >> /tmp/defaultservice.ldif
	ldapadd -x -D "$adminDN" -w "$domainPass" -f /tmp/defaultservice.ldif


	# SSL/TLS for OpenLDAP
	# It assumes that the public and private keys from the Certificate Authority are
	# at /etc/pki/CA/cacert.pem and /etc/pki/CA/private/cakey.pem

	if [ ! -f "${ldapProfileDir}"/certs/ldap-server-crt.pem ] ; then
		mkdir -p "${HOME}"/ldap-certs
		if [ -f "${ldapCerts}"/"${certsDir}"/cert.pem ] ;then
			ln -s "${ldapCerts}"/"${certsDir}"/cert.pem "${HOME}"/ldap-certs/ldap-server-crt.pem
			ln -s "${ldapCerts}"/"${certsDir}"/key.pem "${HOME}"/ldap-certs/ldap-server-key.pem
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
		mkdir -p "${ldapProfileDir}"/certs
		install -D -o "${ldapUser}" -g "${ldapGroup}" -m 644 "${HOME}"/ldap-certs/ldap-server-crt.pem "${ldapProfileDir}"/certs/ldap-server-crt.pem
		install -D -o "${ldapUser}" -g "${ldapGroup}" -m 600 "${HOME}"/ldap-certs/ldap-server-key.pem "${ldapProfileDir}"/certs/ldap-server-key.pem
		install -D -o "${ldapUser}" -g "${ldapGroup}" -m 644 "${HOME}"/ldap-certs/cacert.pem "${ldapProfileDir}"/certs/cacert.pem
	fi

	cat > /tmp/mod_ldap_ssl.ldif <<EOF
# create new

dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: ${ldapProfileDir}/certs/cacert.pem
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: ${ldapProfileDir}/certs/ldap-server-crt.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: ${ldapProfileDir}/certs/ldap-server-key.pem
EOF
	ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/mod_ldap_ssl.ldif

	# Now, make openLDAP listen on SSL port
	if [ -f /etc/sysconfig/slapd ] ; then
		sed -i 's/^\(SLAPD_URLS=.*\)/#\1/' /etc/sysconfig/slapd
		echo 'SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"' >> /etc/sysconfig/slapd
	elif [ -f /etc/default/slapd ] ; then
		sed -i 's/^\(SLAPD_SERVICES=.*\)/#\1/' /etc/default/slapd
		echo 'SLAPD_SERVICES="ldapi:/// ldap:/// ldaps:///"' >> /etc/default/slapd
	fi

	sed -i 's/^\(BASE\|URI\|TLS_REQCERT\|TLS_CACERT\)\([ \t].*\)/#\1\2/' ${ldapProfileDir}/ldap.conf
	cat >> ${ldapProfileDir}/ldap.conf <<EOF
URI ldap:// ldaps:// ldapi://
TLS_REQCERT allow
TLS_CACERT     ${ldapProfileDir}/certs/cacert.pem
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
adminDN=${adminDN}
adminPass=${adminPass}
domainPass=${domainPass}
rootPass=${rootPass}
demoPass=${rootPass}
EOF
	chmod go= "${alreadyGen}"
fi
