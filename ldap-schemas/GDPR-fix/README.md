# How to apply this patch as root

```
ldapmodify -Y EXTERNAL -H ldapi:/// -f addAcceptGDPRattr.ldif
# This one must be generated
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/ldap-ldifs/fixed/cn=\{8\}ldaprddocuments.ldif 
```
