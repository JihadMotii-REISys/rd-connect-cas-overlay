# Create a certification authority using OpenSSL

* Install `openssl` package, if you use Ubuntu, or `openssl-perl` package, if you use CentOS. CA.pl is located at /etc/pki/tls/misc/CA.pl in CentOS 7, and at /usr/lib/ssl/misc/CA.pl in Ubuntu 14.04. Then, follow [http://linoxide.com/security/make-ca-certificate-authority/](this guide).













* Or follow [https://jamielinux.com/docs/openssl-certificate-authority/](this guide).

  
```bash
mkdir -p "${HOME}"/ca
cd "${HOME}"/ca
mkdir certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
```

# Create Certificate Authority using TinyCA
* Create CA. We used tinyca2, generating a CA inside rdconnect_demo_CA folder (this is the name given inside the Name (for local storage) parameter during the CA creation).
* Move .TinyCA/rdconnect_demo_CA to /etc/ssl or ${HOME}/etc/ssl (depending on your privileges)
* Make a backup of /etc/ssl/openssl.cnf just in case...
* Move /etc/ssl/rdconnect_demo_CA/openssl.cnf to /etc/ssl/openssl.cnf
* Edit /etc/ssl/openssl.cnf. Set dir = /etc/ssl/rdconnect_demo_CA
