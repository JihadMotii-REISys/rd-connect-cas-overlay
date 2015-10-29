# Prerequisites needed before installing CAS
* Install Java >= 1.7 and Apache Maven >= 3.0
* Check `JAVA_HOME` and `JAVA_JRE` variables are exported
* Install Tomcat 7.x, creating a user `tomcat-deployer` in conf/tomcat-users.xml with the `manager-script` and `manager-gui` roles.
* (optional) export CATALINA_HOME
* Config DNS giving server a name (rdconnectcas.rd-connect.eu). In our case server hostname is rdconnectcas. In client machine we added an entry for rdconnectcas.rd-connect.eu in /etc/hosts


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
	openssl x509 -req -in tomcat-server.csr -out tomcat-server.pem  -CA ${HOME}/etc/ssl/rdconnect_demo_CA/cacert.pem -CAkey ${HOME}/etc/ssl/rdconnect_demo_CA/cacert.key -days 365 -CAcreateserial -sha1 -trustout  -CA ${HOME}/etc/ssl/rdconnect_demo_CA/cacert.pem -CAkey ${HOME}/etc/ssl/rdconnect_demo_CA/cacert.key -days 365 -CAserial ${HOME}/etc/ssl/rdconnect_demo_CA/serial -sha1 -trustout
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
	git clone -b cas.4.1.x --recurse-submodules https://github.com/inab/ldap-rest-cas4-overlay.git
```	
* Execute inside the project folder:  `mvn clean package`
* Copy simple-cas-overlay-template/target/cas.war to $CATALINA_HOME/webapps/
* Copy etc/* directory (including directory services) to ${HOME}/etc/cas , but tomcat-deployment.properties.template
* Copy etc/tomcat-deployment.properties.template to etc/tomcat-deployment.properties , and set it up properly.
  * The `tomcat-deployer` Tomcat user is put on this file.
* Configure parameters tgc.encryption.key and tgc.signing.key at ${HOME}/etc/cas/cas.properties. In order to generate this keys you need to go to json-web-key-generator folder and deploy by
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
