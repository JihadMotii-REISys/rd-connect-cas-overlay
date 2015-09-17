# Create Certificate Authority
* Create CA. We used tinyca2, generating a CA inside rdconnect_demo_CA folder (this is the name given inside the Name (for local storage) parameter during the CA creation).
* Move .TinyCA/rdconnect_demo_CA to /etc/ssl or ${HOME}/etc/ssl (depending on your privileges)
* Make a backup of /etc/ssl/openssl.cnf just in case...
* Move /etc/ssl/rdconnect_demo_CA/openssl.cnf to /etc/ssl/openssl.cnf
* Edit /etc/ssl/openssl.cnf. Set dir = /etc/ssl/rdconnect_demo_CA
