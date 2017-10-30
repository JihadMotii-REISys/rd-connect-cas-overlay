s~dn: cn=\{([0-9]+)\}([0-9]*_)?(.*)$~dn: cn=\3,cn=schema,cn=config~g
s~cn: \{([0-9]+)\}([0-9]*_)?(.*)$~cn: \3~g
s~^(structuralObjectClass|entryUUID|creatorsName|createTimestamp|entryCSN|modifiersName|modifyTimestamp):.*$~~g
