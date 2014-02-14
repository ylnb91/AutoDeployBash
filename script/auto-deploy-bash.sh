#!/bin/bash

# *******************************************
# 2014.2.11 first version
# 
#
# *******************************************

current=`dirname $0`;
. $current/deploy.properties;

if [[ $# == 0 || $1 == "help" ]]; then
    echo -e "Command syntax error.\nUsage: `basename $0` [qa|prod] \n"; exit 1;
fi

if [[ $1 == "qa" || $1 == "prod" ]]; then
    rm -f $current/$1.properties $current/build.properties;
else
    echo "Illegal input, only "qa","prod" is allowed."; exit 1;
fi

read -p "Please input the appname you want to deploy:" appname;
read -p "Please input the svn target: (head|branch|tag name)" target;

case $target in
    head ) svn_path_target="trunk"; svn_app_path=$appname;;
    branch ) svn_path_target="branches"; svn_app_path=$appname;;
    * ) svn_path_target="tags"; svn_app_path=$target;;
esac

sed "s/@appname@/$appname/g; s/@target@/$svn_path_target/g; s/@path@/$svn_app_path/g" $current/general.properties > /tmp/temp-build.properties;

build_svn=`grep svn.repository= /tmp/temp-build.properties | awk -F= '{printf $2}'`;
svn_username=`grep svn.user= /tmp/temp-build.properties | awk -F= '{printf $2}'`;
svn_account=`grep svn.user.pwd= /tmp/temp-build.properties | awk -F= '{printf $2}'`;
svn ls $build_svn --username $svn_username --password $svn_account &> /dev/null;

#exit if the tag name does not exist
if [[ $? != 0 ]]; then
    echo "the tag dose not exist."; exit 1;
fi

#classify the clusters
error_count=0;
while (( $error_count < 3 )); do
    string=`ls /usr/local | grep ${appname}-node`;
    echo -e "please input the cluster instance name you want to deploy: \c";
    [[ -n $string ]] && read -p "`echo $string` | all " clusters || read -p "${appname}-node[0...n] " clusters;

    if [[ -z $clusters ]]; then
        echo "input error."; ((error_count++)); continue;
    fi

    dir_all=`ls /usr/local`;    
    not_exist_clusters=(); exist_clusters=();

    clusters=($(awk -vRS=' ' '!a[$1]++' <<< $clusters));

    if [[ `echo ${clusters[0]} | awk '{print tolower($1)}'` == "all" ]]; then
        exist_clusters=($string); 
    else
        for cluster in ${clusters[*]}; do
            for dir in $dir_all; do [[ $cluster == $dir ]] && exist_clusters=(${exist_clusters[*]} $cluster) ||  not_exist_clusters=(${not_exist_clusters[*]} $cluster); done
        done
    fi
    not_exist_clusters=($(awk -vRS=' ' '!a[$1]++' <<< ${not_exist_clusters[*]}));
    break;
done

if (( $error_count > 2 )); then
    echo "you must input something, program is going to quit now."; exit 1;
fi

[[ $nginx_server_ip == "localhost" || "$nginx_server_ip" == "127.0.0.1" ]] && is_local="local" || is_local="";
echo "~~~~~~~$is_local";

# create not exist clusters
if [[ ${#not_exist_clusters[*]} != 0 ]]; then
    # N(default)：create a http instance; 
    # y: create a https instance; 
    # cancle: do not create any instances.
    read -p "do you want to create a https instance[N/y/cancle]:" is_https;
    nginx_path=/usr/local/nginx/conf/vhost;

    case `echo $is_https | awk '{print tolower($1)}'` in
        cancle ) echo "program exit."; exit 0;;
        y ) port_type="https";;
        * ) port_type="http";;
    esac
    
    sed "s/@appname@/$appname/g" $current/${port_type}.conf > $current/${appname}.conf.tmp ;
    if [[ $is_local == "local" ]]; then
        ls $nginx_path | grep ${appname}.conf &> /dev/null;
        if [[ $? != 0 ]]; then
            sudo mv -f $current/${appname}.conf.tmp $nginx_path/${appname}.conf;
            sudo sed -i "s/include files here/include files here\n    include vhost\/$appname.conf;/g" /usr/local/nginx/conf/nginx.conf;
        fi
    else
        ssh -tq $nginx_server_ip "ls $nginx_path | grep ${appname}.conf" &> /dev/null;
        if [[ $? != 0 ]]; then
            rsync $current/${appname}.conf.tmp ${nginx_server_ip}:~/${appname}.conf.tmp;
            ssh -tq $nginx_server_ip "sudo mv -f ~/${appname}.conf.tmp $nginx_path/${appname}.conf; sudo sed -i 's/include files here/include files here\n    include vhost\/$appname.conf;/g' /usr/local/nginx/conf/nginx.conf";
        fi
    fi
    rm $current/${appname}.conf.tmp;
fi

for new_app in ${not_exist_clusters[*]}; do

    mkdir /tmp/$appname;
    new_tomcat=/tmp/$appname/${new_app};
    
    . $current/deploy.properties;

    [[ $port_type == "https" ]] && cp -rf $tomcat_https_template $new_tomcat || cp -rf $tomcat_template $new_tomcat;

    sed -i "s/@http.port@/$http_port/g; s/@https.port@/$https_port/g; s/@server.port@/$server_port/g; s/@connector.port@/$connector_port/g; s/@appname@/$appname/g" $new_tomcat/conf/server.xml;
    sed -i "s/@appname@/$new_app/g" $new_tomcat/bin/setenv.sh $new_tomcat/lib/pkgconfig/tcnative-1.pc $new_tomcat/bin/myshutdown.sh;
    
    echo "**************************************************************" ;
    echo "*******  Initing a $port_type instance:  $new_app  ***********" ;
    echo "**************************************************************" ;
    
    [[ $port_type == "https" ]] && port=$https_port || port=$http_port;

    repeat_port=`grep $new_app $current/cluster.instance`;

    if [[ $#repeat_port == 0 || $? != 0 ]]; then
        echo "$new_app=$port" >> $current/cluster.instance;
    else
        sed -i "/$new_app=/c $new_app=$port" $current/cluster.instance;
    fi

    sudo mv -f $new_tomcat /usr/local/$new_app ;
    sudo chown -R tomcat:tomcat /usr/local/$new_app ;
    sudo chkconfig --add $new_app;
    sudo chkconfig --level 2345 $new_app on;
    
    sed "s/@http.port@/$http_port/g; s/@appname@/$new_app/g" $service_template > $current/service.tmp;
    sudo mv -f $current/service.tmp /etc/init.d/$new_app;
    sudo chmod a+x /etc/init.d/$new_app;
    
    awk -F= '{if($1 ~ /port/) print $1,$2+1 > "deploy.properties";else print $1,$2 > "deploy.properties"}' OFS="=" $current/deploy.properties;

    if [[ $is_local == "local" ]]; then
        sudo sed -i "s/upstream $appname {/upstream $appname {\n    server 127.0.0.1:$port weight=1;/g" /usr/local/nginx/conf/vhost/$appname.conf;
    else
        remote_ip=`/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"`;
        ssh -tq $nginx_server_ip "sudo sed -i 's/upstream $appname {/upstream $appname {\n    server ${remote_ip}:${port} weight=1;/g' /usr/local/nginx/conf/vhost/$appname.conf";
    fi

    exist_clusters=(${exist_clusters[*]} $new_app);
done

nginx_error="false";
if [[ $is_local == "local" ]]; then
    sudo service nginx test;
    [[ $? == 0 ]] || nginx_error="true";
else
    ssh -tq $nginx_server_ip "sudo service nginx test";
    [[ $? == 0 ]] || nginx_error="true";
fi

# reload nginx , effect the new added clusters
if [[ ${#not_exist_clusters[*]} != 0 ]]; then
    if [[ $is_local == "local" ]]; then
        if [[ $nginx_error == "true" ]]; then
            echo "local nginx test error, please check the conf files...";
        else
            sudo service nginx reload;
        fi
    else
        if [[ $nginx_error == "true" ]]; then
            echo "remote ${nginx_server_ip} nginx test error, please check the conf files...";
        else
            ssh -tq $nginx_server_ip "sudo service nginx reload";
        fi
    fi
elif [[ ${#exist_clusters[*]} == 0 ]]; then
    echo "no instance. the deploy program quits."; exit 1;
fi


sed "s/@instance@/${exist_clusters[0]}/g" /tmp/temp-build.properties > $current/build.properties;
rm -f /tmp/temp-build.properties;
echo "\n Building Project $appname from $svn_path_target/$svn_app_path ...";

svn export $build_svn/deploy/$1.properties --username $svn_username --password $svn_account;
  
ant -f $current/build.xml -Dtarget=$1;
rm -f $current/build.properties;

#stop the static nginx agent
if [[ $is_local == "local" ]]; then
    #sudo sed -i "/include vhost\/static.conf/c #include vhost\/static.conf;" /usr/local/nginx/conf/vhost/$appname.conf
    startline=`sed -n '/#static conf start/=' /usr/local/nginx/conf/vhost/${appname}.conf | tr -d '\r\n'`;
    endline=`sed -n '/#static conf end/=' /usr/local/nginx/conf/vhost/${appname}.conf | tr -d '\r\n'`;

    if [[ $startline == 0 || $endline == 0 ]]; then
        echo "/usr/local/nginx/conf/vhost/${appname}.conf is invalid; please add static start/end flag."; exit 1;
    fi

    ((startline++));
    ((endline--));
    if [[ $endline -ge $startline ]]; then
        sed -i "${startline},${endline}d" /usr/local/nginx/conf/vhost/${appname}.conf;
    fi
    if [[ $nginx_error == "false" ]]; then sudo service nginx reload;fi 
else
    startline=`ssh -tq $nginx_server_ip "sed -n '/#static conf start/=' /usr/local/nginx/conf/vhost/${appname}.conf" | tr -d '\r\n'`;
    endline=`ssh -tq $nginx_server_ip "sed -n '/#static conf end/=' /usr/local/nginx/conf/vhost/${appname}.conf" | tr -d '\r\n'`;

    if [[ $startline == 0 || $endline == 0 ]]; then
        echo "/usr/local/nginx/conf/vhost/${appname}.conf is invalid; please add static start/end flag."; exit 1;
    fi

    ((startline++));
    ((endline--));
    if [[ $endline -ge $startline ]]; then
        ssh -tq $nginx_server_ip "sudo sed -i '${startline},${endline}d' /usr/local/nginx/conf/vhost/${appname}.conf";
    fi
    if [[ $nginx_error == "false" ]]; then ssh -tq $nginx_server_ip "sudo service nginx reload";fi
fi

# start all the clusters
for app in ${exist_clusters[*]}; do
    CATALINA_HOME=/usr/local/$app;

    sudo service $app stop;

    sleep 5;

    #Clean history deployment
    sudo rm -rf $CATALINA_HOME/webapps/$appname*;
    sudo rm -f $CATALINA_HOME/logs/*;
    #Clean finished

    #distribute war to tomcat cluster
    sudo cp $current/build/$appname.war $CATALINA_HOME/webapps/;

    sleep 5;

    sudo service $app start;
    
    echo "waiting for $app start...";
    sleep 5;
    port=`grep $app= $current/cluster.instance | awk -F= '{printf $2}'`;

    # test starting suc.
    if [[ ${#exist_clusters[*]} == 1 ]]; then continue; fi

    while true; do 
        sleep 5;
        http_status_code=`curl -s -o /dev/null -I -w '%{http_code}' http://localhost:${port}/$appname`;
        https_status_code=`curl -s -k -o /dev/null -I -w '%{http_code}' https://localhost:${port}/$appname`;
        ((status_code=$http_status_code+$https_status_code));
        if [[ $status_code < 400 && $status_code > 0 ]]; then
            echo "Ping localhost:$port/$appname ===> status: $status_code  ${app}: suc"; break;
        fi
        echo "Ping localhost:$port/$appname ===> status: $status_code, try accessing after 5s......";
    done
    echo "Deploy $appname at $app  finished";
done

if [[ `echo ${clusters[0]} | awk '{print tolower($1)}'` == "all" ]]; then
    
    #copy the static files
    static_root=/var/www/$appname ;
    web_dir=$current/$appname/src/main/webapp;

    #open the static agent
    if [[ $is_local=="local" ]]; then
        sudo mkdir -p $static_root;
        sudo rm -rf $static_root/*;
        sudo cp -rf $web_dir/js $static_root/js;
        sudo cp -rf $web_dir/css $static_root/css;
        sed "s/@appname@/$appname/g" static.conf > /tmp/$appname/static.new;
        sudo sed -i "/#static conf start/r /tmp/${appname}/static.new" /usr/local/nginx/conf/vhost/$appname.conf;

        if [[ $nginx_error == "true" ]]; then
            echo "local nginx test error, please check the conf files...";
        else
            sudo service nginx reload;
        fi
    else
        ssh -tq $nginx_server_ip "sudo rm -rf $static_root/*";
        ssh -tq $nginx_server_ip "mkdir -p ~/static";

        rsync -a $web_dir/js ${nginx_server_ip}:~/static;
        rsync -a $web_dir/css ${nginx_server_ip}:~/static;
        ssh -tq $nginx_server_ip "sudo mkdir -p $static_root;sudo rm -rf $static_root/*;sudo mv -f ~/static/js $static_root/js;sudo mv -f ~/static/css $static_root/css; sudo rm -rf ~/static";
        sed "s/@appname@/$appname/g" $current/static.conf > /tmp/$appname/static.new;
        ssh -tq $nginx_server_ip "sudo sed -i '/#static conf start/r /tmp/${appname}/static.new' /usr/local/nginx/conf/vhost/${appname}.conf";
        rm -f /tmp/${appname}/static.new;
        [[ $nginx_error == "false" ]] && ssh -tq $nginx_server_ip "sudo service nginx reload";
    fi
fi

echo "Auto deploy $appname finished";

exit $?;