#!/bin/sh

# Tomcat CAS initial setup

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
	ldapAdminPass="$3"
	tomcatSysconfigFile="$4"
else
	certsDir="cas-tomcat"
	ldapAdminPass="changeit"
	tomcatSysconfigFile=/etc/sysconfig/tomcat8
fi
# Hack, convention, whatever
p12Pass="$certsDir"

destEtcCASDir=/etc/cas
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
	install -o tomcat -g tomcat -m 755 -d "${destEtcCASDir}"/services
	install -o tomcat -g tomcat -m 755 -d "${destCASLog}"
	
	install -D -o tomcat -g tomcat -m 600 "${etccasdir}"/cas.properties.template "${destEtcCASDir}"/cas.properties
	install -D -o tomcat -g tomcat -m 600 "${etccasdir}"/cas-managers.properties "${destEtcCASDir}"/cas-managers.properties
	install -D -o tomcat -g tomcat -m 644 "${etccasdir}"/log4j2-system.xml "${destEtcCASDir}"/log4j2.xml
	install -D -o tomcat -g tomcat -m 600 -t "${destEtcCASDir}"/services "${etccasdir}"/services/*
	
	echo >> "${destEtcCASDir}"/cas.properties
	echo "# Parameters automatically added from Dockerfile" >> "${destEtcCASDir}"/cas.properties
	echo "cas.resources.dir=${destEtcCASDir}" >> "${destEtcCASDir}"/cas.properties
	echo "cas.log.dir=${destCASLog}" >> "${destEtcCASDir}"/cas.properties
	
	# Generating the TGC keys
	(
		cd "${etccasdir}"/../../json-web-key-generator
		if [ ! -f target/json-web-key-generator-*-jar-with-dependencies.jar ] ; then
			mvn -B clean package
		fi
		tgc_signing_key="$(java -jar target/json-web-key-generator-*-jar-with-dependencies.jar -t oct -s 512 -S | grep -F '"k":' | cut -f 4 -d '"')"
		tgc_encryption_key="$(java -jar target/json-web-key-generator-*-jar-with-dependencies.jar -t oct -s 256 -S | grep -F '"k":' | cut -f 4 -d '"')"
		echo "tgc.signing.key=$tgc_signing_key" >> "${destEtcCASDir}"/cas.properties
		echo "tgc.encryption.key=$tgc_encryption_key" >> "${destEtcCASDir}"/cas.properties
	)
	
	# Setting up LDAP manager password
	sed -i "s#^ldap.managerPassword=.*#ldap.managerPassword=${ldapAdminPass}#" "${destEtcCASDir}"/cas.properties
	
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
	install -D -o tomcat -g tomcat -m 600 "${tempKeystore}" "${destKeystore}"

	# This is needed, in order to get next steps working
	keyAlias="$(keytool -rfc -list -storetype PKCS12 -keystore "${initialP12Keystore}" -storepass "${p12Pass}" | grep -F 'Alias name' | head -n 1 | sed 's#^[^:]\+: \(.\+\)$#\1#')"
	fragFile="$(mktemp)"
	cat > "$fragFile" <<EOF
	<Connector port="9443" protocol="HTTP/1.1"
		address="0.0.0.0"
		connectionTimeout="20000"
		redirectPort="9443"
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
	sed -i -e "/^ *redirectPort=/r ${fragFile}" "${destEtcTomcatDir}"/server.xml
	
	# Setting up truststore password for CAS
	sed -i "s#^http.client.truststore.file=.*#http.client.truststore.file=${destTruststore}#" "${destEtcCASDir}"/cas.properties
	sed -i "s#^http.client.truststore.psw=.*#http.client.truststore.psw=${truststorePass}#" "${destEtcCASDir}"/cas.properties
	
	# Patching tomcat7 sysconfig file, so it uses the keystore and truststore from the very beginning
	cat >> "${tomcatSysconfigFile}" <<EOF
export JAVA_OPTS=" -Djavax.net.ssl.keyStore=${destKeystore} -Djavax.net.ssl.keyStorePassword=${keystorePass} -Djavax.net.ssl.trustStore=${destTruststore} -Djavax.net.ssl.trustStorePassword=${truststorePass}"
EOF
	
	# Last, cleanup
	rm -rf "$tempKeystoreDir"
	rm -f "$fragFile"
fi
