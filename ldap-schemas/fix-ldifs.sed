s~dn: cn=\{([0-9]+)\}(.*)$~dn: cn=\2,cn=schema,cn=config~g
s~cn: \{([0-9]+)\}(.*)$~cn: \2~g
s~^(structuralObjectClass|entryUUID|creatorsName|createTimestamp|entryCSN|modifiersName|modifyTimestamp):.*$~~g
