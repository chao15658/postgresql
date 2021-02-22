# pgpool-II操作流程



####  节点规划

 pgpool-3.2.9 + PG-9.4(1主1从) 

其中，pgpool和pg都部署在node0、node4上，其中node0既是pgpool的主节点（VIP所在节点）也是pg的主节点



#### 0、创建目录/usr/local/pgpool，授权为postgres用户

mkdir -p /usr/local/pgpool
chown postgres:postgres -R /usr/local/pgpool

#### 1、解压压缩包

tar xvzf pgpool2-3_2_9.tar.gz

1、1 解决pcp.so问题

yum install -y postgresql94-devel.x86_64

#### 2、在PG用户下编译pgpool-II

cd pgpool-II-3.2.9/ && ./configure --prefix=/usr/local/pgpool

make && make install

#### 3、将/usr/local/pgpool/拷至备节点

#### 4、设置主机互信

主节点：

[root@node0 .ssh]# ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node0   允许以root用户连接本地postgres用户    xx

[root@node0 .ssh]# ssh-copy-id -i ~/.ssh/id_rsa.pub root@node0      允许以root用户连接本节点root用户      xx  用于本地切换

[root@node0 .ssh]# ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node4  允许以root用户连接node4的postgres用户  vv用于ssh以postgres用户切换至node4

[root@node0 .ssh]# ssh-copy-id -i ~/.ssh/id_rsa.pub root@node4      允许以root用户连接node4的root用户     vv



[postgres@node0 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub root@node0  

[postgres@node0 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node0

[postgres@node0 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub root@node4  

[postgres@node0 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node4

备节点：

[root@node4 .ssh]# ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node4

[root@node4 .ssh]# ssh-copy-id -i ~/.ssh/id_rsa.pub root@node4

[root@node4 .ssh]# ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node0

[root@node4 .ssh]# ssh-copy-id -i ~/.ssh/id_rsa.pub root@node0

[postgres@node4 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub root@node4  

[postgres@node4 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node4

[postgres@node4 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub root@node0  

[postgres@node4 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node0

##### 注意：

**ssh-keygen** 产生公钥与私钥对.

**ssh-copy-id** 将本机的公钥复制到远程机器的authorized_keys文件中，ssh-copy-id也能让你有到远程机器的home, ~./ssh , 和 ~/.ssh/authorized_keys的权利


第一步:在本地机器上使用ssh-keygen产生公钥私钥对

第二步:用ssh-copy-id将公钥复制到远程机器中

$ ssh-copy-id -i .ssh/id_rsa.pub 用户名字@192.168.x.xxx

**注意:** ssh-copy-id **将key写到远程机器的 ~/** .ssh/authorized_key文件中

第三步:  登录到远程机器不用输入密码 

$ ssh 用户名字@192.168.x.xxx



 https://blog.csdn.net/liu_qingbo/article/details/78383892 

#### 5、修改pgpool.conf

listen_addresses = '*'
port = 9999

虚拟IP设置
use_watchdog = on
delegate_IP = '192.168.31.139'
if_cmd_path = '/usr/sbin'
if_up_cmd = 'ifconfig ens33:0 inet $_IP_$ netmask 255.255.255.0'
if_down_cmd = 'ifconfig ens33:0 down'
arping_path = '/usr/sbin'
arping_cmd = 'arping -U $_IP_$ -w 1 -I ens33'

PG后端实例配置
backend_hostname0 = 'node0'
backend_port0 = 5432
backend_weight0 = 1
backend_data_directory0 = '/var/lib/pgsql/9.4/data'
backend_flag0 = 'ALLOW_TO_FAILOVER'
backend_hostname1 = 'node4'
backend_port1 = 5432
backend_weight1 = 1
backend_data_directory1 = '/var/lib/pgsql/9.4/data'
backend_flag1 = 'ALLOW_TO_FAILOVER'

其他pgpool连接配置

other_pgpool_hostname0 = 'node4' #另外的pgpool节点主机名                           
other_pgpool_port0 = 9999                                 
other_wd_port0 = 9000

健康检查配置
health_check_period = 20
health_check_timeout = 20
health_check_user = 'postgres'
health_check_password = 'passwd'
health_check_max_retries = 0
health_check_retry_delay = 1

#### 6、为连接用户生成HASH密码

pg_md5 -p postgres

#### 7、修改pool_passwd文件，增加replica的访问权限

host postgres postgres 0.0.0.0/0 trust

#### 8、使用虚拟IP和连接用户postgres，指定端口访问pgpool

[root@node4 run]# ip a|grep ens
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.133/24 brd 192.168.31.255 scope global noprefixroute ens33
    inet 192.168.31.139/24 brd 192.168.31.255 scope global secondary ens33:0

[cc@node0 ~]$ psql -U postgres -h node0 -p 9999

#### 11、显示集群状态

postgres=# show pool_nodes;
 node_id | hostname | port | status | lb_weight |  role   
---------+----------+------+--------+-----------+---------
 0       | node0    | 5432 | 3      | 0.500000  | standby
 1       | node4    | 5432 | 2      | 0.500000  | primary
(2 rows)

#### 12、测试场景

**前提**：pg主节点和pgpool主节点都部署在node0上，pg备节点和pgpool备节点都部署在node4上，如下所示：

[root@node0 etc]# ip a

2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.133/24 brd 192.168.31.255 scope global noprefixroute ens33
    inet 192.168.31.139/24 brd 192.168.31.255 scope global secondary ens33:0

[root@node4 etc]# ip a

2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.134/24 brd 192.168.31.255 scope global noprefixroute ens33



1、pgpool主节点的pgpool服务停止，验证VIP的切换，以及是否会触发pg主备切换

a、停止pgpool服务

[root@**node0** etc]#  /usr/local/pgpool/bin/pgpool -m fast stop             

b、查看node0和node4 pg服务以及pgpool状态

[root@**node0** etc]# ps -ef|grep postgres
postgres  4912     1  0 22:51 pts/2    00:00:00 /usr/pgsql-9.4/bin/postgres
postgres  4914  4912  0 22:51 ?        00:00:00 postgres: logger process   
postgres  4916  4912  0 22:51 ?        00:00:00 postgres: checkpointer process  
postgres  4917  4912  0 22:51 ?        00:00:00 postgres: writer process   
postgres  4918  4912  0 22:51 ?        00:00:00 postgres: wal writer process  
postgres  4919  4912  0 22:51 ?        00:00:00 postgres: autovacuum launcher process  
postgres  4920  4912  0 22:51 ?        00:00:00 postgres: archiver process   last was 000000070000000000000053
postgres  4921  4912  0 22:51 ?        00:00:00 postgres: stats collector process  
postgres  4982  4912  0 22:52 ?        00:00:00 postgres: wal sender process postgres 192.168.31.134(60892) streaming 0/54000500



[root@**node4** etc]# ps -ef|grep postgres
postgres  3827     1  0 22:52 pts/1    00:00:00 /usr/pgsql-9.4/bin/postgres
postgres  3828  3827  0 22:52 ?        00:00:00 postgres: logger process   
postgres  3829  3827  0 22:52 ?        00:00:00 postgres: startup process   recovering 000000070000000000000054
postgres  3830  3827  0 22:52 ?        00:00:00 postgres: checkpointer process  
postgres  3831  3827  0 22:52 ?        00:00:00 postgres: writer process   
postgres  3832  3827  0 22:52 ?        00:00:00 postgres: stats collector process  
postgres  3833  3827  0 22:52 ?        00:00:01 postgres: wal receiver process   streaming 0/54000500
root      4656  2634  0 23:20 pts/1    00:00:00 grep --color=auto postgres



[root@node0 etc]# ip a|grep ens
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.133/24 brd 192.168.31.255 scope global noprefixroute ens33

[root@node4 etc]# ip a|grep ens33
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.134/24 brd 192.168.31.255 scope global noprefixroute ens33
    inet 192.168.31.139/24 brd 192.168.31.255 scope global secondary ens33:0

结论：发现VIP漂移到了node4上，而并未触发pg主备切换。



2、pg主节点的pg服务停止，验证pg是否会主备切换，以及VIP是否会漂移

a、删除备节点数据目录

rm -rf /var/lib/pgsql/9.4/data/*

b、恢复数据库至最初的状态

[postgres@node4 data]$ pg_basebackup -h node0 -U postgres -p 5432 -F p -x -P -R -D /var/lib/pgsql/9.4/data/ -l replbackup    

c、停止pg服务

[postgres@node0 ~]$ pg_ctl stop                 
waiting for server to shut down.... done
server stopped

d、查看node0、node4 pg以及pgpool状态

[root@node0 etc]# ip a|grep ens
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.133/24 brd 192.168.31.255 scope global noprefixroute ens33
    inet 192.168.31.139/24 brd 192.168.31.255 scope global secondary ens33:0



[root@node4 ~]# ip a|grep ens       
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.134/24 brd 192.168.31.255 scope global noprefixroute ens33



[root@node0 etc]# ps -ef|grep postgres
root      8197  2731  0 02:39 pts/3    00:00:00 su - postgres
postgres  8199  8197  0 02:39 pts/3    00:00:00 -bash
root     11994 10809  0 03:27 pts/0    00:00:00 grep --color=auto postgres



[root@node4 ~]# ps -ef|grep postgres
postgres  6416     1  0 03:18 pts/0    00:00:00 /usr/pgsql-9.4/bin/postgres
postgres  6417  6416  0 03:18 ?        00:00:00 postgres: logger process   
postgres  6419  6416  0 03:18 ?        00:00:00 postgres: checkpointer process  
postgres  6420  6416  0 03:18 ?        00:00:00 postgres: writer process   
postgres  6421  6416  0 03:18 ?        00:00:00 postgres: stats collector process  
postgres  6716  6416  0 03:26 ?        00:00:00 postgres: wal writer process  
postgres  6717  6416  0 03:26 ?        00:00:00 postgres: autovacuum launcher process  
postgres  6718  6416  0 03:26 ?        00:00:00 postgres: archiver process   last was 00000008.history
root      6794  6232  0 03:26 pts/0    00:00:00 grep --color=auto postgres

结论：pg主备发生切换，而pgpool VIP未发生变化，也就是说单独的数据库主备切换不会触发pgpool主备切换。



3、pg主节点停机，验证VIP是否会漂移以及pg是否会自动触发主备切换

a、删除备节点数据目录

rm -rf /var/lib/pgsql/9.4/data/*

b、恢复数据库至最初的状态

[postgres@node4 data]$ pg_basebackup -h node0 -U postgres -p 5432 -F p -x -P -R -D /var/lib/pgsql/9.4/data/ -l replbackup    

c、重启pgpool（node0、node4）

[root@node0 etc]# /usr/local/pgpool/bin/pgpool -m fast stop             

[root@node0 etc]#  nohup /usr/local/pgpool/bin/pgpool -nCD > /tmp/pgpool.log 2>&1 &

e、pgpool状态正常

postgres@node0 ~]$ psql -h node0 -p 9999 -U postgres         
psql (9.4.26)
Type "help" for help.

postgres=# show pool_nodes;
 node_id | hostname | port | status | lb_weight |  role   
---------+----------+------+--------+-----------+---------
 0       | node0    | 5432 | 2      | 0.500000  | primary
 1       | node4    | 5432 | 2      | 0.500000  | standby
(2 rows)



重启node0主机之前：

[root@node0 ~]# ip a|grep ens
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.133/24 brd 192.168.31.255 scope global noprefixroute ens33
    inet 192.168.31.139/24 brd 192.168.31.255 scope global secondary ens33:0
[root@node0 ~]# 



[root@node4 ~]# ip a|grep ens
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.134/24 brd 192.168.31.255 scope global noprefixroute ens33
[root@node4 ~]# 



postgres=# select * from pg_stat_replication ;
-[ RECORD 1 ]----+------------------------------
pid              | 17618
usesysid         | 10
usename          | postgres
application_name | walreceiver
client_addr      | 192.168.31.134
client_hostname  | 
client_port      | 40266
backend_start    | 2021-02-20 06:38:48.022854-05
backend_xmin     | 
state            | streaming
sent_location    | 0/5A0007F8
write_location   | 0/5A0007F8
flush_location   | 0/5A0007F8
replay_location  | 0/5A0007F8
sync_priority    | 0
sync_state       | async



重启后：

[root@node4 ~]# ip a|grep ens
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    inet 192.168.31.134/24 brd 192.168.31.255 scope global noprefixroute ens33
    inet 192.168.31.139/24 brd 192.168.31.255 scope global secondary ens33:0



[root@node4 ~]# ps -ef|grep postgres
postgres  7579     1  0 05:55 ?        00:00:02 /usr/pgsql-9.4/bin/postgres
postgres  7580  7579  0 05:55 ?        00:00:00 postgres: logger process   
postgres  7582  7579  0 05:55 ?        00:00:00 postgres: checkpointer process  
postgres  7583  7579  0 05:55 ?        00:00:00 postgres: writer process   
postgres  7584  7579  0 05:55 ?        00:00:00 postgres: stats collector process  
root     10718 10176  0 06:45 pts/1    00:00:00 su - postgres
postgres 10719 10718  0 06:45 pts/1    00:00:00 -bash
postgres 10886 10719  0 06:47 pts/1    00:00:00 tailf postgresql-Sat.log
postgres 11266  7579  0 06:54 ?        00:00:00 postgres: wal writer process  
postgres 11267  7579  0 06:54 ?        00:00:00 postgres: autovacuum launcher process  
postgres 11268  7579  0 06:54 ?        00:00:00 postgres: archiver process   last was 00000008.history
root     11471 10212  0 06:57 pts/2    00:00:00 grep --color=auto postgres

node4的pgpool日志出现如下内容：

2021-02-20 08:04:25 LOG:   pid 13538: execute command: /usr/local/pgpool/etc/failover.sh node4
server promoting
2021-02-20 08:04:25 LOG:   pid 13538: find_primary_node_repeatedly: waiting for finding a primary node
2021-02-20 08:04:26 LOG:   pid 13538: find_primary_node: primary node id is 1
2021-02-20 08:04:26 LOG:   pid 13538: failover: set new primary node: 1
2021-02-20 08:04:26 LOG:   pid 13538: failover: set new master node: 1
2021-02-20 08:04:27 LOG:   pid 13538: failover done. shutdown host node0(5432)

出现上述server promoting说明备节点已经被提升为新的主节点。
连接到之前PG备节点以及pgpool上再次确认
[postgres@node4 ~]$ ps -ef|grep postgres           
postgres 13336     1  0 07:55 pts/2    00:00:00 /usr/pgsql-9.4/bin/postgres
postgres 13337 13336  0 07:55 ?        00:00:00 postgres: logger process   
postgres 13339 13336  0 07:55 ?        00:00:00 postgres: checkpointer process  
postgres 13340 13336  0 07:55 ?        00:00:00 postgres: writer process   
postgres 13341 13336  0 07:55 ?        00:00:00 postgres: stats collector process  
postgres 13683 13336  0 08:04 ?        00:00:00 postgres: wal writer process  
postgres 13684 13336  0 08:04 ?        00:00:00 postgres: autovacuum launcher process  
postgres 13685 13336  0 08:04 ?        00:00:00 postgres: archiver process   last was 00000008.history
root     15047 13538  0 08:38 pts/1    00:00:00 pgpool: postgres postgres 192.168.31.134(36688) idle
root     15048 10176  0 08:38 pts/1    00:00:00 su - postgres
postgres 15049 15048  0 08:38 pts/1    00:00:00 -bash
root     15115 10212  0 08:38 pts/2    00:00:00 su - postgres
postgres 15116 15115  0 08:38 pts/2    00:00:00 -bash
postgres 15155 15116  0 08:38 pts/2    00:00:00 psql -h 192.168.31.139 -U postgres -p 9999
postgres 15156 13336  0 08:38 ?        00:00:00 postgres: postgres postgres 192.168.31.134(60530) idle
postgres 15276 15049  0 08:41 pts/1    00:00:00 ps -ef
postgres 15277 15049  0 08:41 pts/1    00:00:00 grep --color=auto postgres

-bash-4.2$ psql -h 192.168.31.139 -p 9999
psql (9.4.26)
Type "help" for help.

postgres=# show pool_nodes;
 node_id | hostname | port | status | lb_weight |  role   
---------+----------+------+--------+-----------+---------
 0       | node0    | 5432 | 3      | 0.500000  | standby
 1       | node4    | 5432 | 2      | 0.500000  | primary
(2 rows)



结论：发现VIP发生了漂移同时pg也进行了主备切换。

#### 13、启动pgpool

nohup /usr/local/pgpool/bin/pgpool -nCD > /tmp/pgpool.log 2>&1 &

#### 14、停止pgpool

/usr/local/pgpool/bin/pgpool -m fast stop



### 扩展问题



3节点（1个primary+2个standby验证）

pgpool分别部署在每个节点上，其中初始时pgpool和pg的primary部署在一个节点

#### 验证

1、当在node1、node2依次停止pgpool服务，发现VIP从node1漂移至node2，再到node3。

2、当在node1、node2依次停止pg服务，发现在第一次停止时触发了pg自动主备切换，第二次需要修改node3的recovery.conf,使其从node2（新主）上拉去WAL日志，之后重启node3上pg以及所有节点pgpool。前提是在第一次操作期间未进行数据操作。

#### 修改

新增节点node3（即node5）需要和node2（即node4）进行秘钥交换。操作如下：

[postgres@node5 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub root@node5    
[postgres@node5 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node5

[postgres@node5 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node4
[postgres@node5 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub root@node4    

[root@node5 ~]# ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node5
[root@node5 ~]# ssh-copy-id -i ~/.ssh/id_rsa.pub root@node5
[root@node5 ~]# ssh-copy-id -i ~/.ssh/id_rsa.pub root@node4     
[root@node5 ~]# ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node4 



node2执行下面命令：

[postgres@node4 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node5
[postgres@node4 ~]$ ssh-copy-id -i ~/.ssh/id_rsa.pub root@node5

[root@node4 ~]# ssh-copy-id -i ~/.ssh/id_rsa.pub postgres@node5
[root@node4 ~]# ssh-copy-id -i ~/.ssh/id_rsa.pub root@node5