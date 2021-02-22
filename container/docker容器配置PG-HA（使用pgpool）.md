# docker容器配置PG-HA（使用pgpool）

实现了一主多从，pgpool后台心跳检测，实现主备自动切换。

## 配置流程

目前测试是在一台宿主机上启动多个容器，每个容器启动一个PG实例、pgpool实例。

pgpool启动配置修改为监控PG集群节点，实现对PG一主多从集群的管理。



## 增加自定义网络

docker network create -d bridge  --subnet 172.28.0.0/16  mynet 



## 自定义网络与默认的网络区别

默认情况下，默认网络只能通过IP访问，自定义网络可通过容器名、自定义网络别名访问。自定义网络的网络隔离性好。



## Master：

docker run \ 
-e INITIAL_NODE_TYPE='master' \ 
-e NODE_ID=1 \
 -e NODE_NAME='node1' \
 -e CLUSTER_NODE_NETWORK_NAME='pgmaster' \
 -e POSTGRES_PASSWORD='monkey_pass' \
 -e POSTGRES_USER='monkey_user' \
 -e POSTGRES_DB='monkey_db' \ 
 -e CLUSTER_NODE_REGISTER_DELAY=5 \
 -e REPLICATION_DAEMON_START_DELAY=120 \ 
 -e CLUSTER_NAME='pg_cluster' \ 
 -e REPLICATION_DB='replication_db' \
 -e REPLICATION_USER='replication_user' \
 -e REPLICATION_PASSWORD='replication_pass' \
 -v cluster-archives:/var/cluster_archive \ 
 -p 5440:5432 \ 
 --net mynet \
 --net-alias pgmaster \ 
 --name pgmastertest \
 paunin/postgresql-cluster-pgsql



## Slave1：

docker run \ 
-e INITIAL_NODE_TYPE='standby' \
 -e NODE_ID=2 \ 
 -e NODE_NAME='node2' \
 -e REPLICATION_PRIMARY_HOST='pgmaster' \
 -e CLUSTER_NODE_NETWORK_NAME='pgslave1' \ 
 -e REPLICATION_UPSTREAM_NODE_ID=1 \ 
 -v cluster-archives:/var/cluster_archive \
 -p 5441:5432 \
 --net mynet \ 
 --net-alias pgslave1 \
 --name pgslavetest \
 paunin/postgresql-cluster-pgsql



## Slave2：

docker run \ 
-e INITIAL_NODE_TYPE='standby' \
 -e NODE_ID=3 \ 
 -e NODE_NAME='node3' \ 
 -e REPLICATION_PRIMARY_HOST='pgmaster' \
 -e CLUSTER_NODE_NETWORK_NAME='pgslave2' \
 -e REPLICATION_UPSTREAM_NODE_ID=2 \ 
 -v cluster-archives:/var/cluster_archive \ 
 -p 5442:5432 \ 
 --net mynet \ 
 --net-alias pgslave2 \
 --name pgslavetest2 \
 paunin/postgresql-cluster-pgsql



## Slave3：

docker run \ 
-e INITIAL_NODE_TYPE='standby' \
 -e NODE_ID=4 \ 
 -e NODE_NAME='node4' \
 -e REPLICATION_PRIMARY_HOST='pgmaster' \ 
 -e CLUSTER_NODE_NETWORK_NAME='pgslave3' \
 -e REPLICATION_UPSTREAM_NODE_ID=3 \
 -v cluster-archives:/var/cluster_archive \
 -p 5443:5432 \ 
 --net mynet \ 
 --net-alias pgslave3 \
 --name pgslavetest3 \
 paunin/postgresql-cluster-pgsql



## pgpool：

docker run \ 
-e PCP_USER='pcp_user' \
 -e PCP_PASSWORD='pcp_pass' \
 -e PGPOOL_START_DELAY=120 \
 -e REPLICATION_USER='replication_user' \
 -e REPLICATION_PASSWORD='replication_pass' \ 
 -e SEARCH_PRIMARY_NODE_TIMEOUT=5 \ 
 -e DB_USERS='monkey_user:monkey_pass' \
 -e BACKENDS='0:pgmaster:5432:1:/var/lib/postgresql/data:ALLOW_TO_FAILOVER,1:pgslave1::::,2:pgslave2::::,3:pgslave3::::' \ 
 -p 5430:5432 \
 -p 9898:9898 \
 --net mynet \
 --net-alias pgpool \ 
 --name pgpooltest \
 paunin/postgresql-cluster-pgpool

#### 启动pgpool对外暴露端口5430提供服务，用户使用用户/密码：pcp_user/pcp_pass访问数据库。



# 通过pgpool连接数据库

#### 使用如下命令远程访问数据库

psql -h host -p 5430 -U pcp_user 

其中，-h指定宿主机ip，根据提示输入pcp_user的密码，可正常连接数据库。

#### 查询集群状态:

psql -c 'show pool_nodes'



## 主备切换后，原来的主加入集群。

进入pgpool容器，执行下面命令：

```
pcp_attach_node -U pcp_user -h localhost -n 1p
cp_node_info -U pcp_user -h localhost -n 1
```



#### 容器持久化存储：

使用运行启动参数-v指定将容器的/var/lib/postgres/data目录挂载到宿主机的/root/path路径下。

docker run -v /root/path:/var/lib/postgres/data



#### postgresql启动脚本分析：

dockerfile(部分内容，像信息见postgresql-dockerfile):

![1560655861425](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560655861425.png)

docker.io/paunin/postgresql-cluster-pgsql分析:

```
[root@node1 ~]# docker inspect 49b3dd811b4b|grep -C 5 Cmd
                "LOG_LEVEL=INFO",
                "CHECK_PGCONNECT_TIMEOUT=10",
                "REPMGR_SLOT_NAME_PREFIX=repmgr_slot_",
                "NOTVISIBLE=in users profile"
            ],
            "Cmd": [
                "/bin/sh",
                "-c",
                "#(nop) ",
                "CMD [\"/usr/local/bin/cluster/entrypoint.sh\"]"
            ],
--
                "LOG_LEVEL=INFO",
                "CHECK_PGCONNECT_TIMEOUT=10",
                "REPMGR_SLOT_NAME_PREFIX=repmgr_slot_",
                "NOTVISIBLE=in users profile"
            ],
            "Cmd": [
                "/usr/local/bin/cluster/entrypoint.sh"
            ],
            "ArgsEscaped": true,
            "Image": "sha256:2738d8bf867f1cf3301adb3cccbd1ef91c6e985a3cc22d090309706ebdb884d4",
            "Volumes": {
```

发现其入口脚本是/usr/local/bin/cluster/entrypoint.sh

![1560609259914](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560609259914.png)

发现其还调用了/usr/local/bin/cluster/postgres/entrypoint.sh。

内容如下：

![1560610988917](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560610988917.png)

![1560611033544](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560611033544.png)

发现其调用
/usr/local/bin/cluster/repmgr/configure.sh

内容如下：

![1560611822883](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560611822883.png)

![1560611868422](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560611868422.png)

主要用于读取和配置环境变量。



还调用脚本/uar/local/bin/cluster/repmgr/start.sh

脚本内容如下：

![1560612131050](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560612131050.png)



通过环境变量识别不同类型的节点。
在主节点上，将/usr/local/bin/cluster/postgres/primary/entrypoint.sh拷贝到/docker-entrypoint-initdb.d/目录,并调用/docker-entrypoint.sh postgres &
分析/entrypoint.sh脚本可发现其对/docker-entrypoint-initdb.d/目录下的.sh、.sql、.sql.gz文件会执行（包括刚才拷贝到/docker-entrypoint-initdb.d/目录的/usr/local/bin/cluster/postgres/entrypoint.sh脚本）。因此，用户想要在容器启动后自动调用的脚本可放到该目录下。

/docker-entrypoint.sh脚本内容：

![1560610438163](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560610438163.png)

![1560610494211](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560610494211.png)

![1560610530240](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560610530240.png)

![1560610573176](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560610573176.png)

![1560610698845](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560610698845.png)



/usr/local/bin/cluster/postgres/primary/entrypoint.sh内容：

![1560609940032](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560609940032.png)



在从节点调用/usr/local/bin/cluster/postgres/standby/entrypoint.sh

![1560611203638](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560611203638.png)





#### pgpool启动脚本分析：

dockerfile（部分内容，详细信息见pgpool-dockerfile）：

![1560655526822](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560655526822.png)

[root@node1 ~]# docker inspect docker.io/paunin/postdock-pgpool|grep -C 5 'Cmd'
                "WAIT_BACKEND_TIMEOUT=120",
                "REQUIRE_MIN_BACKENDS=0",
                "SSH_ENABLE=0",
                "NOTVISIBLE=in users profile"

​           ],
​            "Cmd": [
​                "/bin/sh",
​                "-c",
​                "#(nop) ",
​                "CMD [\"/usr/local/bin/pgpool/entrypoint.sh\"]"

​                     ],

​            "WAIT_BACKEND_TIMEOUT=120",
​            "REQUIRE_MIN_BACKENDS=0",
​            "SSH_ENABLE=0",
​            "NOTVISIBLE=in users profile"
​        ],
​        "Cmd": [
​            "/usr/local/bin/pgpool/entrypoint.sh"
​        ],
​        "Healthcheck": {
​            "Test": [
​                "CMD-SHELL",

脚本/usr/local/bin/pgpool/entrypoint.sh：

![1560654889793](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560654889793.png)

查看脚本/usr/local/bin/pgpool/pgpool_setup.sh

![1560655024915](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560655024915.png)

![1560655060054](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560655060054.png)

![1560655093060](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560655093060.png)

![1560655128415](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560655128415.png)



脚本/usr/local/bin/pgpool/pgpool_start.sh内容：

![1560655269619](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560655269619.png)



脚本/usr/local/bin/pgpool/has_write_node.sh内容（如dockerfile所写，每1min调一次，重试次数5）：

![1560687447633](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560687447633.png)

![1560687227109](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1560687227109.png)

参考链接：

<https://hub.docker.com/r/paunin/postgresql-cluster-pgsql#publications>

https://stackoverflow.com/questions/37710868/how-to-promote-master-after-failover-on-postgresql-with-docker?r=SearchResults

