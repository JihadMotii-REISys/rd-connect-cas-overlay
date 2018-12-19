# Setup needed before installing CAS
* A LDAP server must be setup and working, according [INSTALL_LDAP.md](INSTALL_LDAP.md). We are assuming along this document that its name is `ldap.rd-connect.eu`.
* The CAS server host must have its official name, either through the name server or using a new /etc/hosts entry. We are assuming along this document that the name is `rdconnectcas.rd-connect.eu`.
* Install git, Java >= 1.8, Ant and Apache Maven >= 3.0.
```bash
yum -y install git java-devel ant ant-contrib maven
```

* Install Tomcat 8.5.x.
  * You can generate the needed RPMs for Tomcat just following the instructions in [this repository](//github.com/inab/rpm-tomcat). Once generated, RPMs are available at `~/rpmbuild/RPMS/noarch`, and you have to install only the needed RPMs:
  ```bash
  cd "${HOME}"/rpmbuild/RPMS/noarch
  # Supposing it is Tomcat 8.5.35
  sudo yum install tomcat8-8.5.35-1.noarch.rpm tomcat8-admin-webapps-8.5.35-1.noarch.rpm tomcat8-lib-8.5.35-1.noarch.rpm tomcat8-root-webapp-8.5.35-1.noarch.rpm
  # Now, creating a symlink from tomcat8 to tomcat in /etc and /usr/share
  # so next instructions are coherent
  sudo ln -s /etc/tomcat8 /etc/tomcat
  sudo ln -s /usr/share/tomcat8 /usr/share/tomcat
  ```
  
  * Old Tomcat versions available in CentOS 7 has the deployment bug which breaks CAS deployment. When there is an updated one, the installation steps would be:
  ```bash
  yum -y install tomcat tomcat-admin-webapps
  ```

    * Due an installation bug in old Tomcat versions available in CentOS 7, Tomcat deployment tasks for ant will not work without some additional symlinks:
    ```bash
    cd /usr/share/tomcat/lib
    ln -s tomcat-el-2.2-api.jar el-api.jar
    ln -s tomcat-jsp-2.2-api.jar jsp-api.jar
    ln -s tomcat-servlet-3.0-api.jar servlet-api.jar
    ```

* Edit /etc/tomcat/tomcat-users.xml (CentOS, RPM) or $CATALINA_BASE/conf/tomcat-users.xml, creating a user `cas-tomcat-deployer` with a unique password, and the `manager-script` and `manager-gui` roles.

```xml
<role rolename="manager-gui" />
<role rolename="manager-script" />
<user name="cas-tomcat-deployer" password="ChangeThisPassword!!!" roles="manager-gui, manager-script"/>
```

* In standard installations (i.e. using system packages), like in CentOS or Ubuntu, it is not needed to export environment variables.
  * Otherwise, you have to check that `JAVA_HOME` and `JAVA_JRE` variables are exported, so your Tomcat servlet container uses the right version of Java.
  * The same is applied to `CATALINA_HOME` environment variable.

# SSL/TLS for Tomcat (CentOS, RPM, Ubuntu)
* First, we are going to get a copy of the default keystore, which is located at ${JAVA_HOME}, and we are going to change its default password to something different, for instance `cas.Keystore.Pass`

```bash
mkdir -p "${HOME}"/cas-server-certs
cp "${JAVA_HOME}"/jre/lib/security/cacerts "${HOME}"/cas-server-certs/cas-tomcat-server.jks
keytool -storepasswd -new cas.Keystore.Pass -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass changeit
```

* Then, we need to have a key pair for https:// protocol as well as CA public key in the keystore, as CAS server is going to run in secured mode.
  * If we already have generated / obtained them in PEM format as `cert.pm`, `key.pem` and `cacert.pem`, we can import the set of keys into the keystore using next commands:
  
  ```bash
  certtool --load-ca-certificate cacert.pem \
    --load-certificate cert.pem --load-privkey key.pem \
    --to-p12 --p12-name=rdconnectcas.rd-connect.eu --password=rdconnectcas.rd-connect.eu \
    --outder --outfile "${HOME}"/cas-server-certs/cas-keystore.p12
  keytool -v -importkeystore -srckeystore "${HOME}"/cas-server-certs/cas-keystore.p12 \
    -srcstorepass rdconnectcas.rd-connect.eu -srcstoretype PKCS12 \
    -destkeystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -deststorepass cas.Keystore.Pass
  ```
  
  * Generating it by hand is done following next steps:

	1. First, we are going to generate a key pair for https:// protocol, as CAS server is going to run in secured mode. Java `keytool` executable is going to be used, and it was installed at the beginning. We will use the public and private keys from a Certificate Authority (in this guide, `/etc/pki/CA/cacert.pem` and `/etc/pki/CA/private/cakey.pem`). In case you need it, you can create your own CA following [this procedure](INSTALL_CA.md)

	2. Now, we are going to create the private key encrypted with another password different from the keystore's one (for instance `pass,Key,CAS`):

	```bash
	keytool -genkey -alias rdconnectcas.rd-connect.eu -keyalg RSA -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass cas.Keystore.Pass -keypass pass,Key,CAS -dname "CN=rdconnectcas.rd-connect.eu, OU=Spanish Bioinformatics Institute, O=INB at CNIO, L=Madrid, S=Madrid, C=ES"
	```
	  and then, the certificate request (which contains the private key) for the server:

	```bash
	keytool -certreq -keyalg RSA -alias rdconnectcas.rd-connect.eu -file "${HOME}"/cas-server-certs/cas-server.csr -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass cas.Keystore.Pass
	```

	3. Now, as we are the certification authority, with the certificate request we are going to get the matching signed, public key, agreed for 1451 days (4 years, one of them a leap year):

	```bash
	# See below what you have to answer
	certtool --generate-certificate --load-request "${HOME}"/cas-server-certs/cas-server.csr --load-ca-certificate /etc/pki/CA/cacert.pem --load-ca-privkey /etc/pki/CA/private/cakey.pem --outfile "${HOME}"/cas-server-certs/cas-server-crt.pem
	```

	  Be sure the common name matches the hostname of the CAS server, and use the private key password
  
	```
	Generating a signed certificate...
	Enter password: 
	Enter the certificate's serial number in decimal (default: 6211541704542909289): 


	Activation/Expiration time.
	The certificate will expire in (days): 1451


	Extensions.
	Do you want to honour the extensions from the request? (y/N): 
	Does the certificate belong to an authority? (y/N): 
	Is this a TLS web client certificate? (y/N): 
	Will the certificate be used for IPsec IKE operations? (y/N): 
	Is this a TLS web server certificate? (y/N): Y
	Enter a dnsName of the subject of the certificate: rdconnectcas.rd-connect.eu
	Enter a dnsName of the subject of the certificate: 
	Enter a URI of the subject of the certificate: https://rdconnectcas.rd-connect.eu:9443/
	Enter a URI of the subject of the certificate: https://rdconnectcas.rd-connect.eu/
	Enter a URI of the subject of the certificate: 
	Enter the IP address of the subject of the certificate: 
	Will the certificate be used for signing (DHE and RSA-EXPORT ciphersuites)? (Y/n): 
	Will the certificate be used for encryption (RSA ciphersuites)? (Y/n): 
	```

	4. Now, we are importing the CA certificate (public key) used for LDAP and CAS. If you have used different CAs, then you have to repeat this step for each one of them, changing the alias and the path to the public key:
	```bash
	keytool -import -alias rdconnect-ca-root -file /etc/pki/CA/cacert.pem -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass cas.Keystore.Pass
	```
	5. At last, import generated certificate (public key) into the keystore, as well as the public Java keystore:
	```bash
	keytool -import -trustcacerts -alias rdconnectcas.rd-connect.eu -file "${HOME}"/cas-server-certs/cas-server-crt.pem -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass cas.Keystore.Pass
	```
	  It is possible to check that the certificates are in place just using next sentence:

	```bash
	keytool -list -v -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass cas.Keystore.Pass
	```

# Configure Tomcat to use the prepared keystore (CentOS, RPM)

* First, we are going to put the keystore in a place where it can be read only by Tomcat user:

```bash
install -D -o tomcat -g tomcat -m 600 "${HOME}"/cas-server-certs/cas-tomcat-server.jks /etc/tomcat/cas-tomcat-server.jks
```
* Now, we augment it importing the existing certificates from the used JVM into the CAS keystore, so third party certificates are agreed:
```bash
# Next sentence only works in CentOS
keytool -importkeystore -srckeystore /etc/pki/java/cacerts -srcstorepass changeit -destkeystore /etc/tomcat/cas-tomcat-server.jks -deststorepass cas.Keystore.Pass
```
```bash
# Next sentence is for custom JVMs
keytool -importkeystore -srckeystore "${JAVA_HOME}"/jre/lib/security/cacerts -srcstorepass changeit -destkeystore /etc/tomcat/cas-tomcat-server.jks -deststorepass cas.Keystore.Pass
```

* Then, edit /etc/tomcat/server.xml (or $CATALINA_BASE/conf/server.xml), adding next connector:
```xml
<Connector port="9443" protocol="HTTP/1.1"
	address="0.0.0.0"
        connectionTimeout="20000"
        redirectPort="9443"
        SSLEnabled="true"
        scheme="https"
        secure="true"
        sslProtocol="TLS"
        keyAlias="rdconnectcas.rd-connect.eu"
        keyPass="pass,Key,CAS"
        keystoreFile="/etc/tomcat/cas-tomcat-server.jks"
        keystorePass="cas.Keystore.Pass"
        truststoreFile="/etc/tomcat/cas-tomcat-server.jks"
        truststorePass="cas.Keystore.Pass" />

```

* If you don’t have any applications running in the 8080 port, you can comment out the lines inside /etc/tomcat/server.xml (or $CATALINA_BASE/conf/server.xml):
```xml
<!-- <Connector port="8080" protocol="HTTP/1.1"
connectionTimeout="20000"
    redirectPort="9443" />
-->
```

* Now, tell java instance used to run Tomcat which keystore must be used.
  * If your Tomcat is installed at system level, then add next line to the end of file `/etc/sysconfig/tomcat7` or `/etc/sysconfig/tomcat`:
  ```bash
  export JAVA_OPTS=" -Djavax.net.ssl.keyStore=/etc/tomcat/cas-tomcat-server.jks -Djavax.net.ssl.keyStorePassword=cas.Keystore.Pass -Djavax.net.ssl.trustStore=/etc/tomcat/cas-tomcat-server.jks -Djavax.net.ssl.trustStorePassword=cas.Keystore.Pass"
  ```
  * If you are running your own Tomcat instance, then follow [the instructions](https://apereo.github.io/cas/5.3.x/installation/Troubleshooting-Guide.html) on subsection ["When All Else Fails"](https://apereo.github.io/cas/5.3.x/installation/Troubleshooting-Guide.html#when-all-else-fails), putting on `KEYSTORE`and `TRUSTSTORE` variables the full path to the CAS Tomcat JKS.

* Last, start the Tomcat server and add it to the startup sequence:
  * If you generated the RPMs
  ```bash
  systemctl start tomcat8
  systemctl enable tomcat8
  ```
  * If you are using CentOS 7 RPMs
  ```bash
  systemctl start tomcat
  systemctl enable tomcat
  ```

# CAS Maven Overlay Installation
* Clone git project with the simple overlay template here
```bash
git clone -b cas-5.3.x https://github.com/inab/rd-connect-cas-overlay.git /tmp/cas-5.3.x
```	

* Inside the checked-out directory, run `./mvnw clean package` in order to generate the war:
```bash
cd /tmp/cas-5.3.x
./mvnw clean package
```

* Now, depending on whether you are using a system or an user Tomcat, you have to slightly change your installation procedure.

  * (SYSTEM) Create directories /etc/cas and /var/log/cas as the `tomcat` user, and copy cas.properties.template, log4j2-system.xml and cacert.pem to /etc/cas , renaming wherever it is needed:
  ```bash
  install -o tomcat -g tomcat -m 755 -d /etc/cas
  install -o tomcat -g tomcat -m 755 -d /etc/cas/services
  install -o tomcat -g tomcat -m 755 -d /var/log/cas
  install -D -o tomcat -g tomcat -m 600 /tmp/cas-5.3.x/etc/cas.properties.template /etc/cas/config/cas.properties
  install -D -o tomcat -g tomcat -m 644 /tmp/cas-5.3.x/etc/log4j2-system.xml /etc/cas/config/log4j2.xml
  install -D -o tomcat -g tomcat -m 644 /etc/pki/CA/cacert.pem /etc/cas/cacert.pem
  ```
  
  * (USER) Create directories ${HOME}/etc/cas and ${HOME}/cas-log, and copy cas-managers.properties, cas.properties.template, log4j2-user.xml, cacert.pem and services to "${HOME}"/etc/cas , renaming wherever it is needed:
  ```bash
  mkdir -p "${HOME}"/etc/cas "${HOME}"/cas-log
  cp -p /tmp/cas-5.3.x/etc/cas.properties.template "${HOME}"/etc/cas/cas.properties
  cp -p /tmp/cas-5.3.x/etc/log4j2-user.xml "${HOME}"/etc/cas/log4j2.xml
  cp -p /etc/pki/CA/cacert.pem "${HOME}"/etc/cas/cacert.pem
  cp -p /tmp/cas-5.3.x/etc/cas-managers.properties /tmp/cas-5.3.x/etc/services "${HOME}"/etc/cas
  chmod go-r "${HOME}"/etc/cas/cas.properties "${HOME}"/etc/cas-managers.properties 
  chmod go-rx "${HOME}"/etc/cas/services
  ```
  
  * (SYSTEM, USER) Edit cas.properties file, and apply next changes:
    * Uncomment `cas.resources.dir` and `cas.log.dir` according your installation environment.
    * Change `ldap.managerPassword` by the password needed to bind to the LDAP directory using the user declared at `ldap.managerDn`.
    * Fill-in parameters `tgc.encryption.key` and `tgc.signing.key`. In order to generate these keys you need to go to json-web-key-generator folder and deploy by
    ```bash
    cd /tmp
    git clone -b json-web-key-generator-0.3 https://github.com/mitreid-connect/json-web-key-generator.git
    cd /tmp/json-web-key-generator
    /tmp/cas-5.3.x/mvnw clean package
    # Generating the first key
    java -jar target/json-web-key-generator-*-jar-with-dependencies.jar -t oct -s 512 -S | grep -F '"k":' | cut -f 4 -d '"'
    # Generating the second key
    java -jar target/json-web-key-generator-*-jar-with-dependencies.jar -t oct -s 256 -S | grep -F '"k":' | cut -f 4 -d '"'
    ```	
    These generated keys are needed to update your cas.properties at next parameters:
    ```
    cas.tgc.crypto.signing.key=<First key generated>
    cas.tgc.crypto.encryption.key=<Second key generated>
    ```
    
    And we repeat the procedure for Google Authenticator setup keys:
    ```bash
    # Generating the gauth first key
    java -jar target/json-web-key-generator-*-jar-with-dependencies.jar -t oct -s 512 -S | grep -F '"k":' | cut -f 4 -d '"'
    # Generating the gauth second key
    java -jar target/json-web-key-generator-*-jar-with-dependencies.jar -t oct -s 256 -S | grep -F '"k":' | cut -f 4 -d '"'
    These generated keys are needed to update your cas.properties at next parameters:
    ```
    cas.authn.mfa.gauth.crypto.signing.key=<First gauth key generated>
    cas.authn.mfa.gauth.crypto.encryption.key=<Second gauth key generated>
    ```

* (SYSTEM, USER) Last, deploy it using the provided ant script. You have to copy `etc/tomcat-deployment.properties.template` to `etc/tomcat-deployment.properties`, and put there the password you assigned to the Tomcat user `cas-tomcat-deployer`:

```bash
cd /tmp/cas-5.3.x
cp etc/tomcat-deployment.properties.template etc/tomcat-deployment.properties
# Apply the needed changes to etc/tomcat-deployment.properties

# Now deploy the application, using the keystore previously generated
ANT_OPTS="-Djavax.net.ssl.trustStore=/etc/tomcat/cas-tomcat-server.jks -Djavax.net.ssl.trustStorePassword=cas.Keystore.Pass" ant deploy
```

# Further steps:

* Install CAS Management webapp, following [these instructions](//github.com/inab/rd-connect-cas-management-overlay/blob/cas-5.3.x/INSTALL.md).
