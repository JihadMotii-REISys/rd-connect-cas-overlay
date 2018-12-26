#!/bin/sh

# Tomcat CAS initial setup
TOMCAT_PORT=9443

etccasdir="$(dirname "$0")"
case "${etccasdir}" in
	/*)
		true
		;;
	*)
		etccasdir="${PWD}"/"${etccasdir}"
		;;
esac

# Which directory contains the certificates?
if [ $# -gt 0 ] ; then
	tomcatCerts="$1"
else
	tomcatCerts=/tmp/rd-connect_cas_tomcat_certs
fi
if [ $# -gt 2 ] ; then
	certsDir="$2"
	ldapServer="$3"
	ldapAdminDn="$4"
	ldapAdminPass="$5"
	tomcatSysconfigFile="$6"
	jwkgPath="$7"
else
	certsDir="cas-tomcat"
	ldapServer="ldap.rd-connect.eu"
	ldapAdminDn="cn=admin,dc=rd-connect,dc=eu"
	ldapAdminPass="changeit"
	tomcatSysconfigFile=/etc/sysconfig/tomcat8
	jwkgPath="$(echo /tmp/tgc-repo/target/json-web-key-generator-*-jar-with-dependencies.jar)"
fi
# Hack, convention, whatever
p12Pass="$certsDir"

# This changed on CAS 5.x
destEtcCASDir=/etc/cas/config
destEtcTomcatDir=/etc/tomcat
destCASLog=/var/log/cas

if [ ! -d "${destEtcCASDir}" -o ! -f "${destEtcCASDir}"/cas.properties ] ; then
	# We want it to exit on first error
	set -e
	
	if [ -z "$JAVA_HOME" ] ; then
		for javaloc in /usr/lib/jvm/java ; do
			if [ -e "${javaloc}" ] ; then
				JAVA_HOME="${javaloc}"
				export JAVA_HOME
			fi
		done
	fi
	
	# Setting up basic paths
	install -o tomcat -g tomcat -m 755 -d "${destEtcCASDir}"
	install -o tomcat -g tomcat -m 755 -d "${destCASLog}"
	
	install -D -o tomcat -g tomcat -m 600 "${etccasdir}"/cas.properties.template "${destEtcCASDir}"/cas.properties
	install -D -o tomcat -g tomcat -m 644 "${etccasdir}"/log4j2-system.xml "${destEtcCASDir}"/log4j2.xml
	install -D -o tomcat -g tomcat -m 644 "${etccasdir}"/MultifactorBypass.groovy "${destEtcCASDir}"/MultifactorBypass.groovy
	
	# Multifactor secrets go here
	touch "${destEtcCASDir}"/multifactor-secrets.json
	chmod u=rw,go= "${destEtcCASDir}"/multifactor-secrets.json
	chown tomcat: "${destEtcCASDir}"/multifactor-secrets.json
	
	# Setting up properties
	echo >> "${destEtcCASDir}"/cas.properties
	echo "# Parameters automatically added from automated CAS setup ($(date -I))" >> "${destEtcCASDir}"/cas.properties
	echo "custom.resourcesDir=${destEtcCASDir}" >> "${destEtcCASDir}"/cas.properties
	#echo "custom.logDir=${destCASLog}" >> "${destEtcCASDir}"/cas.properties
	
	# Generating the TGC keys
	(
		# TGC
		tgc_signing_key="$(java -jar "$jwkgPath" -t oct -s 512 -S | grep -F '"k":' | cut -f 4 -d '"')"
		tgc_encryption_key="$(java -jar  "$jwkgPath" -t oct -s 256 -S | grep -F '"k":' | cut -f 4 -d '"')"
		echo "cas.tgc.crypto.signing.key=$tgc_signing_key" >> "${destEtcCASDir}"/cas.properties
		echo "cas.tgc.crypto.encryption.key=$tgc_encryption_key" >> "${destEtcCASDir}"/cas.properties
		
		# Google authenticator
		gauth_signing_key="$(java -jar  "$jwkgPath" -t oct -s 512 -S | grep -F '"k":' | cut -f 4 -d '"')"
		gauth_encryption_key="$(java -jar  "$jwkgPath" -t oct -s 256 -S | grep -F '"k":' | cut -f 4 -d '"')"
		echo "cas.authn.mfa.gauth.crypto.signing.key=$gauth_signing_key" >> "${destEtcCASDir}"/cas.properties
		echo "cas.authn.mfa.gauth.crypto.encryption.key=$gauth_encryption_key" >> "${destEtcCASDir}"/cas.properties
	)
	
	# Setting up LDAP manager DN and password in several places
	for configKey in 'cas.authn.ldap[0]' 'cas.serviceRegistry.ldap' 'cas.authn.attributeRepository.ldap[0]' ; do
		# Left square bracket escaping
		configSedKey="${configKey/\[/\\[}"
		# Right square bracket escaping
		configSedKey="${configSedKey/\]/\\]}"
		
		# Definitions commented-out
		sed -i 's/^\('"${configSedKey}"'.\(bindCredential\|bindDn\|ldapUrl\)=\)/#\1/' "${destEtcCASDir}"/cas.properties
		
		# New definitions at the end
		cat <<EOF >> "${destEtcCASDir}"/cas.properties
${configKey}.ldapUrl=ldaps://${ldapServer}
${configKey}.bindDn=${ldapAdminDn}
${configKey}.bindCredential=${ldapAdminPass}
EOF
	done

	#sed -i 's/^\(cas.authn.ldap\[0\].bindCredential=\)/#\1/' "${destEtcCASDir}"/cas.properties
	#echo "cas.authn.ldap[0].bindCredential=${ldapAdminPass}" >> "${destEtcCASDir}"/cas.properties
	#
	#sed -i 's/^\(cas.serviceRegistry.ldap.bindCredential=\)/#\1/' "${destEtcCASDir}"/cas.properties
	#echo "cas.serviceRegistry.ldap.bindCredential=${ldapAdminPass}" >> "${destEtcCASDir}"/cas.properties
	#
	#sed -i 's/^\(cas.authn.attributeRepository.ldap\[0\].bindCredential=\)/#\1/' "${destEtcCASDir}"/cas.properties
	#echo "cas.authn.attributeRepository.ldap[0].bindCredential=${ldapAdminPass}" >> "${destEtcCASDir}"/cas.properties
	
	# Generating the password for Tomcat user with management privileges
	sed -i 's#^</tomcat-users>.*##' "${destEtcTomcatDir}"/tomcat-users.xml
	cat >> "${destEtcTomcatDir}"/tomcat-users.xml <<EOF
	<role rolename='manager-gui' />
	<role rolename='manager-script' />
	<user name='cas-tomcat-deployer' password='$(apg -n 1 -m 12 -x 16 -M ncl)' roles='manager-gui, manager-script' />
</tomcat-users>
EOF

	# Setting up the base keystore
	keystorePass="$(apg -n 1 -m 12 -x 16 -M ncl)"
	tempKeystoreDir="/tmp/cas-server-certs.$$"
	initialP12Keystore="${tomcatCerts}"/"${certsDir}"/keystoreOpenSSL.p12
	tempKeystore="${tempKeystoreDir}"/cas-tomcat-server.jks
	destKeystore="${destEtcTomcatDir}"/cas-tomcat-server.jks
	
	truststorePass="${keystorePass}"
	destTruststore="${destKeystore}"
	
	mkdir -p "${tempKeystoreDir}"
	cp "${JAVA_HOME}"/jre/lib/security/cacerts "${tempKeystore}"
	keytool -storepasswd -new "${keystorePass}" -keystore "${tempKeystore}" -storepass changeit
	
	# Populating it
	install -D -o tomcat -g tomcat -m 644 "${tomcatCerts}"/cacert.pem "${destEtcCASDir}"/cacert.pem
	keytool -v -importkeystore -srckeystore "${initialP12Keystore}" -srcstorepass "${p12Pass}" -srcstoretype PKCS12 \
		-destkeystore "${tempKeystore}" -deststorepass "${keystorePass}"
	#keytool -v -alias 'ca' -importcert -file "${destEtcCASDir}"/cacert.pem -keystore "${tempKeystore}" -storepass "${keystorePass}" -noprompt -trustcacerts
	install -D -o tomcat -g tomcat -m 600 "${tempKeystore}" "${destKeystore}"

	# This is needed, in order to get next steps working
	keyAlias="$(keytool -rfc -list -storetype PKCS12 -keystore "${initialP12Keystore}" -storepass "${p12Pass}" | grep -F 'Alias name' | head -n 1 | sed 's#^[^:]\+: \(.\+\)$#\1#')"
	fragFile="$(mktemp)"
	
	cat > "$fragFile" <<EOF
	<Connector port="${TOMCAT_PORT}" protocol="HTTP/1.1"
		address="0.0.0.0"
		connectionTimeout="20000"
		redirectPort="${TOMCAT_PORT}"
		SSLEnabled="true"
		scheme="https"
		secure="true"
		sslProtocol="TLS"
		keyAlias="${keyAlias}"
		keyPass="${p12Pass}"
		keystoreFile="${destKeystore}"
		keystorePass="${keystorePass}"
		truststoreFile="${destTruststore}"
		truststorePass="${truststorePass}" />
EOF
	sed -i 's#pathname="[^"]*"#pathname="/etc/tomcat/tomcat-users.xml"#g' "${destEtcTomcatDir}"/server.xml
	sed -i -e "s#redirectPort=\"[^\"]*\"#redirectPort=\"${TOMCAT_PORT}\"#g; /^ *redirectPort=/r ${fragFile}" "${destEtcTomcatDir}"/server.xml
	
	# Setting up truststore password for CAS
	sed -i "s#^cas.httpClient.truststore.file=.*#cas.httpClient.truststore.file=${destTruststore}#" "${destEtcCASDir}"/cas.properties
	sed -i "s#^cas.httpClient.truststore.psw=.*#cas.httpClient.truststore.psw=${truststorePass}#" "${destEtcCASDir}"/cas.properties
	
	# Patching tomcat sysconfig file, so it uses the keystore and truststore from the very beginning
	cat >> "${tomcatSysconfigFile}" <<EOF
export JAVA_OPTS=" -Djavax.net.ssl.keyStore=${destKeystore} -Djavax.net.ssl.keyStorePassword=${keystorePass} -Djavax.net.ssl.trustStore=${destTruststore} -Djavax.net.ssl.trustStorePassword=${truststorePass}"
EOF
	
	# Last, cleanup
	rm -rf "$tempKeystoreDir"
	rm -f "$fragFile"
fi
