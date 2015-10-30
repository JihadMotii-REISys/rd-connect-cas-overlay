# Setup needed before installing CAS
* First, the CAS server host must have its official name, either through the name server or using a new /etc/hosts entry. We are assuming along this document that the name is `rdconnectcas.rd-connect.eu`.
* Install git, Java >= 1.7, Ant, Apache Maven >= 3.0 and Tomcat 7.x. For CentOS 7 would be:

```bash
yum -y install git java-devel ant maven tomcat tomcat-admin-webapps
```
* Edit /etc/tomcat/tomcat-users.xml (CentOS) or conf/tomcat-users.xml, creating a user `cas-tomcat-deployer` with a unique password, and the `manager-script` and `manager-gui` roles.

```xml
<role rolename="manager-gui" />
<role rolename="manager-script" />
<user name="cas-tomcat-deployer" password="ChangeThisPassword!!!" roles="manager-gui, manager-script"/>
```

* In standard installations (i.e. using system packages), like in CentOS or Ubuntu, it is not needed to export environment variables.
  * Otherwise, you have to check that `JAVA_HOME` and `JAVA_JRE` variables are exported, so your Tomcat servlet container uses the right version of Java.
  * The same is applied to `CATALINA_HOME` environment variable.

# SSL/TLS for Tomcat (CentOS, Ubuntu)
* First, we are going to generate a key pair for https:// protocol, as CAS server is going to run in secured mode. Java `keytool` executable is going to be used, and it was installed at the beginning. We will use the public and private keys from a Certificate Authority (in this example, `/etc/pki/CA/cacert.pem` and `/etc/pki/CA/private/cakey.pem`. You can create one following [this procedure](INSTALL_CA.md)

* Now, we are going to create the Java keystore which is going to be used by Tomcat:

```bash
mkdir -p "${HOME}"/cas-server-certs
keytool -genkey -alias rdconnectcas.rd-connect.eu -keyalg RSA -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass changeit -keypass changeit -dname "CN=rdconnectcas.rd-connect.eu, OU=Spanish Bioinformatics Institute, O=INB at CNIO, L=Madrid, S=Madrid, C=CN"
```
  and then, the certificate request (which contains the private key) for the server:

```bash
keytool -certreq -keyalg RSA -alias rdconnectcas.rd-connect.eu -file "${HOME}"/cas-server-certs/cas-server.csr -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass changeit
```

* Now, as we are the certification authority, with the certificate request we are going to get the matching signed, public key, agreed for 1451 days (4 years, one of them a leap year):

```bash
# See below what you have to answer
certtool --generate-certificate --load-request "${HOME}"/cas-server-certs/cas-server.csr --load-ca-certificate /etc/pki/CA/cacert.pem --load-ca-privkey /etc/pki/CA/private/cakey.pem --outfile "${HOME}"/cas-server-certs/cas-server-crt.pem
```

  Be sure the common name matches the hostname of the CAS server
  
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

* Now, we are importing the CA certificate (public key):
```bash
keytool -import -alias rdconnect-ca-root -file /etc/pki/CA/cacert.pem -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass changeit
```
* At last, import generated certificate (public key) into the keystore:
```bash
keytool -import -trustcacerts -alias rdconnectcas.rd-connect.eu -file "${HOME}"/cas-server-certs/cas-server-crt.pem -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass changeit
```
  It is possible to check that the certificates are in place just using next sentence:

```bash
keytool -list -v -keystore "${HOME}"/cas-server-certs/cas-tomcat-server.jks -storepass changeit
```

# Configure Tomcat to use the prepared keystore (CentOS)

* First, we are going to put the keystore in a place where it can be read only by Tomcat user:

```bash
install -D -o tomcat -g tomcat -m 600 "${HOME}"/cas-server-certs/cas-tomcat-server.jks /etc/tomcat/cas-tomcat-server.jks
```

* Then, edit /etc/tomcat/server.xml , adding next connector:
```xml
<Connector port="9443" protocol="HTTP/1.1"
        connectionTimeout="20000"
        redirectPort="9443"
        SSLEnabled="true"
        scheme="https"
        secure="true"
        sslProtocol="TLS"
        keystoreFile="/etc/tomcat/cas-tomcat-server.jks"
        truststoreFile="/etc/tomcat/cas-tomcat-server.jks"
        keystorePass="changeit" />

```


# Certificates (Ubuntu):

* Create CA following instructions in INSTALL_CA file
* Move .TinyCA/rdconnect_demo_CA to /etc/ssl or ${HOME}/etc/ssl (depending on your privileges)
* Make a backup of /etc/ssl/openssl.cnf just in case...
* Move /etc/ssl/rdconnect_demo_CA/openssl.cnf to /etc/ssl/openssl.cnf
* Edit /etc/ssl/openssl.cnf. Set dir = /etc/ssl/rdconnect_demo_CA

* Create Tomcat Server Certificate (at ${HOME}/etc/ssl/rdconnect_demo_CA):
```bash
	keytool -genkey -alias tomcat-server -keyalg RSA -keystore tomcat-server.jks -storepass changeit -keypass changeit -dname "CN=rdconnectcas.rd-connect.eu, OU=Spanish Bioinformatics Institute, O=INB at CNIO, L=Madrid, S=Madrid, C=CN"
	keytool -certreq -keyalg RSA -alias tomcat-server -file tomcat-server.csr -keystore tomcat-server.jks -storepass changeit
```
* Sign the request
```bash
	openssl x509 -req -in tomcat-server.csr -out tomcat-server.pem  -CA ${HOME}/etc/ssl/rdconnect_demo_CA/cacert.pem -CAkey ${HOME}/etc/ssl/rdconnect_demo_CA/cacert.key -days 1451 -CAcreateserial -sha1 -trustout
```
* Verify the purpose
```bash
	openssl verify -CAfile ${HOME}/etc/ssl/rdconnect_demo_CA/cacert.pem -purpose sslserver tomcat-server.pem
	openssl x509 -in tomcat-server.pem -inform PEM -out tomcat-server.der -outform DER
```
* Import root certificate:
```bash
	keytool -import -alias rdconnect-root -file ${HOME}/etc/ssl/rdconnect_demo_CA/cacert.pem -keystore tomcat-server.jks -storepass changeit
```
* Import tomcat-server certificate:
```bash
	keytool -import -trustcacerts -alias tomcat-server -file tomcat-server.der -keystore tomcat-server.jks -storepass changeit
	keytool -list -v -keystore tomcat-server.jks -storepass changeit
```

# Configure Tomcat to use certificate:
* Edit conf/server.xml adding:
```xml
	<Connector port="9443" protocol="HTTP/1.1"
                connectionTimeout="20000"
                redirectPort="9443"
                SSLEnabled="true"
                scheme="https"
                secure="true"
                sslProtocol="TLS"
                keystoreFile="${user.home}/etc/ssl/rdconnect_demo_CA/tomcat-server.jks"
                truststoreFile="${user.home}/etc/ssl/rdconnect_demo_CA/tomcat-server.jks"
                keystorePass="changeit" />

```
    
# Maven Overlay Installation
* Clone git project with the simple overlay template here
```bash
	git clone -b cas-4.1.x --recurse-submodules https://github.com/inab/ldap-rest-cas4-overlay.git
```	
* Execute inside the project folder:  `mvn clean package`
* Copy simple-cas-overlay-template/target/cas.war to $CATALINA_HOME/webapps/
* Copy etc/* directory (including directory services) to ${HOME}/etc/cas , but tomcat-deployment.properties.template
* Copy etc/tomcat-deployment.properties.template to etc/tomcat-deployment.properties , and set it up properly.
  * The `tomcat-deployer` Tomcat user is put on this file.
* Configure parameters `tgc.encryption.key` and `tgc.signing.key` at ${HOME}/etc/cas/cas.properties. In order to generate this keys you need to go to json-web-key-generator folder and deploy by
```bash
mvn clean package
cd json-web-key-generator
java -jar target/json-web-key-generator-0.2-SNAPSHOT-jar-with-dependencies.jar -t oct -s 512 -S
java -jar target/json-web-key-generator-0.2-SNAPSHOT-jar-with-dependencies.jar -t oct -s 256 -S
```	
* The result contains a couple of keys which are needed to update your cas.properties at next parameters:

```
tgc.signing.key=<First key generated>
tgc.encryption.key=<Second key generated>
```

* If you don’t have any applications running in the 8080 port, you can comment out the lines inside $CATALINA_BASE/conf/server.xml:
```xml
	<!-- <Connector port="8080" protocol="HTTP/1.1"
	connectionTimeout="20000"
        redirectPort="9443" />
	-->

```
(In order to restrict the traffic only to secure ports)
