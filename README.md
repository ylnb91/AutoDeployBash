##Java项目自动部署脚本

功能:

- 添加tomecat instance 如果输入的instance不存在;
- svn checkout;
- 用ant 打包checkout的文件;
- 把包部署到tomcat中，启动;
- 压缩js，css等静态文件;
- 修改nginx.conf中相关静态文件的配置，reload nginx;
