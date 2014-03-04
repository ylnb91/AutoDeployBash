##Java-web-cluster-auto-deployment

This shell/ant script tool will do the following things:

- Initial the tomcat instance if it does not exist;
- Checkout source coude from svn server;
- Build the source code to war file;
- Deploy the war file to specified tomcat instance;
- Bring up/down tomcat instance;
- Compress js/css files;
- Make nginx reload to take updated static files;

Features:

- Auto detect the svn path, support check codes from trunk, branches and tags;
- Support http/https tomcat instance, the tomcat template is configurable;
- Auto create command file under /etc/init.d/ to enable new tomcat instance start/stop as service;
- Support quick re-deployment for both single tomcat instance or tomcat cluster;
- Paring the pom.xml to download the dependency jars from Manven center repository;
- No shutdown in cluster deployment process;
- Support Nginx reload static files manually or automatically;
- Support cross server deployment.

Useage:
 To be filled...
