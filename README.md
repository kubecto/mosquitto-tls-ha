

### 原理介绍

mosquitto-tls-ha 架构通过nginx主备及keepalived主备切换的能力来保证mosquiito是故障容错的能力

在华为私有云环境中，生产环境终端可对接内网elb来指向内网vip地址及端口来提供服务的可靠性，如其他原因测试希望公开公网地址，那么此时可以通过elb绑定弹性公网或者开启SNAT的转发来公开公网地址，后端同时代理到内网的vip地址

在阿里云/腾讯云环境中，如使用公有云，由于默认在公有云禁止使用vip，所以采用slb来代理后端的2台nginx:9000端口来实现mqtt的高可用

此时架构流量从vip入口进入，因为涉及到vip主和备的绑定关系，流量会先到达主的nginx上，当前nginx会通过负载均衡的能力，同时代理多个broker, 由于本身nginx负载均衡的算法，每次请求只会发送一个后端broker，为了实现订阅者都能收到发送的消息，此时引入mqtt的桥接模式，而作为bridge master的mqtt，它订阅了来自vip/elb上来的消息，mqtt桥接模式会将broker的消息进行复制分发到对等的broker上，那么此时消息也就完成了复制分发，如果其中一个主的keepalived及主的nginx挂掉，那么此时vip会通过健康检测并漂移到备的keepalived和备的nginx上，那么流量分发过程和上述相同。

为了保证节点的broker及bridge由于其他原因导致进程挂掉，那么节点都会安排一个进程状态检测的脚本，每3s钟进行探测一次进程状态，如果进程挂掉，那么触发启动进程脚本，来保证每个节点都有健康检测的能力，同时nginx也被keepalived进行检测，如果一个nginx挂掉，会进行重新启动，如果启动失败就进行vip漂移

### 私有云安装步骤
默认安装为一个broker,一个master,两个nginx,两个keepalived,还有一个vip,另外如有其他的需求也可以在安装部署时增加加多个broker，或者在后续添加broker时也可以同时增加多个broker

安装整个环境需要4台机器，其中规划一台broker,一台master,两个nginx和keepalived放在两个节点上，另外需要再准备一个vip,也就是需要准备5个ip地址，(私有云环境可以单独拿一台服务器充当vip地址).

### 机器配额
nginx+keepalived1 4c8g 200g系统盘
nginx+keepalived2 4c8g 200g系统盘
mosquitto-master 2c4g 200g系统盘
mosquitto-broker 2c4g 200g系统盘

### 1、节点配置主机名（这里以准备4台机器为例）
hostnamectl set-hostname mosquitto-bridge
hostnamectl set-hostname mosquitto-broker1
hostnamectl set-hostname mosquitto-nginx-keepalived1
hostnamectl set-hostname mosquitto-nginx-keepalived2

### 2、将主机名及ip地址写入/etc/hosts，如后续扩容，请将新的节点ip和主机名填写入内，注意用于ansible与节点的通信及任务分发

10.101.9.1 mosquitto-bridge
10.101.9.2 mosquitto-broker1
10.101.9.4 mosquitto-nginx-keepalived1
10.101.9.5 mosquitto-nginx-keepalived2

### 3、解压安装包,并安装ansible节点环境

tar xf mqtt-tls-v1.2.1.tar.gz
cd mqtt-tls
bash mosquitto.sh

### 4、配置hosts文件告诉ansible在哪个节点去运行任务

[mosquitto-master] # 这里选择一个ip作为mosquitto-master的节点，主要用来桥接实现消息的复制（填写主机名）
mosquitto-bridge

[mosquitto-broker] # 这里选择一个ip作为mosquitto-broker的节点，主要用于发布及订阅消息 （填写主机名）
mosquitto-broker1

[mosquitto-broker-address] # 这里选择一个ip作为mosquitto-broker的节点，主要用于发布及订阅消息 （填写ip地址）
10.101.9.4

[mosquitto-nginx-keepalived] # 这里选择两个ip作为nginx-keepalived的反向代理及故障vip的转移 （填写主机名）
mosquitto-nginx-keepalived1
mosquitto-nginx-keepalived2

[keepalived-vip] # 这里选择一个ip作为keepalived的vip,主要用于消息的发布提供地址 （填写ip地址）
10.101.9.167

[vip-port] # 这里选择一个端口为虚拟ip提供一个vip 的端口号，这个端口号默认会监听本地的nginx，而nginx会反向代理给后端的broker节点进行消息分发，同时这时的mqtt-master将收到的消息进行订阅，而它再负责将消息复制到其他的broker节点上
9000

[add-broker] # 这里选择两个节点作为弹性扩容broker的节点，当然这个只会在你想添加broker节点的时候才会使用，如果不需要增加节点，可以不填/填写也不影响最初的安装，另外默认扩容默认支持2个节点同时扩容，如果想扩容多个可以看后续的文档说明 （填写主机名）
add-broker1
add-broker2

[add-broker-address] # 这里选择两个节点作为弹性扩容broker的节点，这里和上面一样，（填写ip地址）
10.101.9.3
10.101.9.10


### 5、开始安装集群
ansible-playbook site-all.yml -k

6、注意！！安装完集群之后，此脚本一定要在bridge节点和broker节点进行执行，防止后续忘记，因为在扩容时会涉及到重新启动bridge，另外开启脚本之后后续挂掉也能执行健康检测来自动启动进程

集群安装后会在mosquitto-master及mosquiito-broker和add-broker节点
/opt/pass/mosquitto/ ⽬录下⽣成 Service_detect.sh 后台进程监控脚本，此脚本主要为 mosquitto-master及mosquiito-broker和add-broker 提供进程检查，防⽌ mosquitto进程挂掉， 启动后会探测 mosquitto 进程是否存活，没有存活会启动该进程。
启动检测脚本
cd /opt/pass/mosquitto/ 
bash Service_detect.sh

### 6.1、测试脚本可用性
注意⚠：此脚本需要进⼊ /opt/pass/mosquitto/ ⽬录下之后才能执⾏，如果直接bash /opt/pass/mosquitto/Service_detect.sh 脚本测试脚本可⽤性 
ps -ef |grep mosquitto 
kill -9 pid 
此时mosquitto已经挂掉 再次查看mosquitto进程，此时这个进程默认会⾃动启动，因为Service_detect.sh会探测pid是否挂掉，挂掉会帮忙启动 
ps -ef |grep mosquitto

### 6.2、测试关机之后脚本是否自动启动及mosquitto进程是否正常运行
reboot
ps -ef |grep mosquitto
ps -ef |grep Service_detect
开机之后默认，会看到两个进程已经启动，这说明正常, 如果没有启动进程，则需要手动再进行启动下
cd /opt/pass/mosquitto/
bash Service_detect.sh

### 6.3、nginx探活脚本测试
keepalived主备的关系可以预防一个主的keepalived挂掉,当主的挂掉之后，vip会切换到备的节点上
那么默认nginx在主节点上的话，增加探活脚本之后，当主的nginx挂掉的话，会重新启动，当遇到nginx起不来，进程探测不到，说明nginx挂掉，keepalived检测到，那么就会将vip进行漂移

### 7、测试集群消息发送及订阅
# 默认在两个nginx节点分别安装了两个mosquitto_pub,主要用于去发送消息
# 此处默认发送消息的地址则是vip地址，9000端口则是vip端口
mosquitto_pub -t hello -h 10.101.9.167 --insecure -p 9000 --cafile /etc/mosquitto/cert/mosquitto-server-ca.crt --cert /etc/mosquitto/cert/mosquitto-server.crt --key /etc/mosquitto/cert/mosquitto-server.key -m "hello"

### 7.2、在broker-master上订阅hello的消息
 mosquitto_sub -t hello -h 10.101.9.6 --insecure -p 8883 --cafile /etc/mosquitto/cert/mosquitto-server-ca.crt --cert /etc/mosquitto/cert/mosquitto-server.crt --key /etc/mosquitto/cert/mosquitto-server.key

收到的消息: hello

### 7.3、在broker上订阅hello的消息
mosquitto_sub -t hello -h 10.101.9.4 --insecure -p 8883 --cafile /etc/mosquitto/cert/mosquitto-server-ca.crt --cert /etc/mosquitto/cert/mosquitto-server.crt --key /etc/mosquitto/cert/mosquitto-server.key

收到的消息: hello

### 8、扩容broker节点

[add-broker] # 这里默认选择两个节点作为弹性扩容broker的节点，当然这个只会在你想添加broker节点的时候才会使用，如果不需要增加节点，可以不填,扩容时需要提前将/etc/hosts填写。 （填写主机名）
add-broker1
add-broker2

[add-broker-address] (填写添加的对应的broker ip地址)
10.206.0.10
10.206.0.8

### 8.1、执行扩容broker节点 注意：(扩容broker，最好前期根据业务的规模进行规划好，尽量少扩容，如果后期需要扩容broker，最好在晚上业务比较低的时候进行扩容这样最好)
ansible-playbook site-add-broker.yml -k


### 8.2、扩容完到扩容节点执行启动脚本
cd /opt/pass/mosquitto/
bash Service_detect.sh


8.3、扩容时希望添加3个或更多的broker时，修改hosts文件add-broker，add-broker-address之外还需要修改site-add-broker.yml 
找到此处，并安装格式依次往下添加，需要注意这里的{{groups['add-broker'][0]}}和hosts文件对应比如三个broker，就012标签对应起来
    - name: Modify the address of the broker forwarded by the Bridge Master
      lineinfile:
        path: /etc/mosquitto/mosquitto.conf
        line: |

           connection {{groups['add-broker'][0]}}"
           address {{groups['add-broker-address'][0]}}:1883"
           topic # both 2 "" "" 

           connection {{groups['add-broker'][1]}}"
           address {{groups['add-broker-address'][1]}}:1883"
           topic # both 2 "" "" 

           connection {{groups['add-broker'][2]}}"
           address {{groups['add-broker-address'][2]}}:1883"
           topic # both 2 "" "" 

在下面找到并按照格式添加012的格式，批量添加3台
    - name: Add nginx reverse broker
      lineinfile:
        path: /etc/nginx/nginx.conf
        state: present
        line: "{{item}}"
        insertafter: 'upstream cloud_native_mosquitto_broker {'
      with_items:
      - "      server {{groups['add-broker-address'][0]}}:8883;"
      - "      server {{groups['add-broker-address'][1]}}:8883;"
      - "      server {{groups['add-broker-address'][2]}}:8883;"
扩容完记得启动健康检测脚本，另外如我第一次扩容了3个节点了，现在我又想扩容3个节点，此时可以将之前hosts文件注释掉，或者删掉，然后再运行此脚本，这样默认取模版的时候依然取三个对应扩容的模版扩容

9、部署时规划3个broker及更多，处理细节（除了在hosts文件mosquitto-broker组内及mosquitto-broker-address增加多个broker主机名及ip地址外）

还需要在vim roles/mosquitto/templates/mosquitto.confmaster.j2
继续往下添加，如hosts文件中填写了4个broker，那么这里则需要写4个对应起来
connection {{groups['mosquitto-broker'][0]}}
address {{groups['mosquitto-broker-address'][0]}}:1883
topic # both 2 "" ""

connection {{groups['mosquitto-broker'][1]}}
address {{groups['mosquitto-broker-address'][1]}}:1883
topic # both 2 "" ""

connection {{groups['mosquitto-broker'][2]}}
address {{groups['mosquitto-broker-address'][1]}}:1883
topic # both 2 "" ""

connection {{groups['mosquitto-broker'][3]}}
address {{groups['mosquitto-broker-address'][1]}}:1883
topic # both 2 "" ""


### 还需要在vim roles/nginx/templates/nginx.conf.j2 填写4个对应起来
  server {{groups['mosquitto-broker-address'][0]}}:8883;
  server {{groups['mosquitto-broker-address'][1]}}:8883;
  server {{groups['mosquitto-broker-address'][2]}}:8883;
  server {{groups['mosquitto-broker-address'][3]}}:8883;

### 10、故障信息查看地址
##### keepalived 
journalctl -u keepalived

##### nginx
more /var/log/nginx/error.log
more /var/log/nginx/access.log

##### mosquitto
/var/log/mosquitto/mosquitto.log

##### ansible

安装包内的ansible.log

##### 11、ansible安装报错
 {"changed": false, "msg": "Failed to connect to the host via ssh: ssh: Could not resolve hostname add-mosqitto-broker: Name or service not known", "unreachable": true}
需要检测hosts文件和/etc/hosts文件对应的主机名保持一致，不一致会导致ansible无法与远程主机进行通信执行任务

##### 12、找不到mosquitto_pub或者mosquitto_sub命令
mosquitto_pub -h
mosquitto_pub: error while loading shared libraries: libmosquitto.so.1: cannot open shared object file: No such file or directory
使用find / -name libmosquitto.so.1 找到对应的库文件，然后软连接到/usr/lib/libmosquitto.so
ln -s /usr/local/lib/libmosquitto.so.1 /usr/lib/libmosquitto.sh
使用ldconfig生效配置
ldconfig

###### 13、另外需要注意安装的时候需要依赖yum命令，尽量保持yum可以使用，否则会影响安装过程

