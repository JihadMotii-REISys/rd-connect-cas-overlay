Debugging CAS
=============

* Low level debugs require setting logging levels from `/etc/cas/log4j2.xml file` to `debug`.
* Higher level debugs which tell the CAS attributes of a user require to put file [casGenericSuccessView.jsp](casGenericSuccessView.jsp) into src/main/webapp/WEB-INF/view/jsp/default/ui (if you are rebuilding CAS war), or in /var/lib/tomcat7/webapps/cas/WEB-INF/view/jsp/default/ui (if you are playing with a running instance). Most of the times a Tomcat restart is adviced, as CAS webapp suffers some memory leaks on reloads and undeploy/redeployments.
