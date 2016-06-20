# How to apply this patch as root

```
ldapmodify -Y EXTERNAL -H ldapi:/// -f modify.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f modify2.ldif
```
