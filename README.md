##自动部署脚本


环境：Centos

软件：Tomcat、Nginx，Tomcat放在当前文件夹下作为模板，Nginx放在/usr/localxia

启动：./auto-deploy.sh prod

然后按提示进行。

脚本已经做到nginx、tomcat负载均衡和静态文件的分离。

