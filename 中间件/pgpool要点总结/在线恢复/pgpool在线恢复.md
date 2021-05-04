# PG主备切换之后，pgpool和原来的Primary节点失去连接

#### 原主要恢复为新的standby节点需要执行步骤：

1、对新的主节点做全量备份，由recovery_1st_stage_command 命令指定，这里使用脚本recovery_1st_stage是采用pg_basebackup进行全量备份。
2、停止当前主节点，对当前主节点在全量备份期间所产生的更新做增量备份（切换xlog），由recovery_2nd_stage_command指定，这里采用recovery_2nd_stage脚本是利用函数pgpool_switch_xlog。

3、远程启动原主上的pg实例，pgpool_remote_start需要配置免密。

pgpool相关配置

```
recovery_user = 'postgres' # Online recovery user
recovery_password = 'passwd' # Online recovery password
                             # Leaving it empty will make Pgpool-II to first look for the
                             # Password in pool_passwd file before using the empty password
recovery_1st_stage_command = 'recovery_1st_stage'  # Executes a command in first stage
recovery_2nd_stage_command= 'recovery_2nd_stage'   # Executes a command in second stage
recovery_timeout = 90
```

postgresql.conf配置：

```
wal_level = hot_standby
archive_mode = on
archive_command = 'cp %p /var/lib/pgsql/archive/%f'
```


[postgres@node0 ~]$  psql -h 192.168.31.137 -p 9999                         
psql (9.4.26)
Type "help" for help.

postgres=# show pool_nodes;
 node_id | hostname | port | status | lb_weight |  role   
---------+----------+------+--------+-----------+---------
 0       | node0    | 5432 | 2      | 0.500000  | primary
 1       | node4    | 5432 | 3      | 0.500000  | standby
(2 rows)

1、使用pcp_attach_node将原Primary节点重新纳入pgpool管理。
/usr/local/pgpool/bin/pcp_attach_node 10 node4 9898 postgres  passwd 1        

状态恢复正常，显示ok
postgres=# show pool_nodes;
 node_id | hostname | port | status | lb_weight |  role   
---------+----------+------+--------+-----------+---------
 0       | node0    | 5432 | 2      | 0.500000  | primary
 1       | node4    | 5432 | 2      | 0.500000  | standby
(2 rows)


2、恢复
[postgres@node0 ~]$ /usr/local/pgpool/bin/pcp_recovery_node 10 node4 9898 postgres  passwd 1

3、查看主备实例状态
主实例状态：
[postgres@node0 etc]$ ps -ef|grep postgres
postgres  1808     1  0 04:47 pts/0    00:00:04 /usr/pgsql-9.4/bin/postgres -D /var/lib/pgsql/9.4/data
postgres  1809  1808  0 04:47 ?        00:00:00 postgres: logger process   
postgres  1811  1808  0 04:47 ?        00:00:00 postgres: checkpointer process   
postgres  1812  1808  0 04:47 ?        00:00:00 postgres: writer process   
postgres  1813  1808  0 04:47 ?        00:00:00 postgres: wal writer process   
postgres  1814  1808  0 04:47 ?        00:00:00 postgres: autovacuum launcher process   
postgres  1815  1808  0 04:47 ?        00:00:00 postgres: archiver process   last was 00000007000000000000004F
postgres  1816  1808  0 04:47 ?        00:00:00 postgres: stats collector process   
postgres  1818  1808  0 04:47 ?        00:00:00 postgres: wal sender process postgres 192.168.31.134(56966) streaming 0/500006B0
root      2961  1916  0 05:04 pts/1    00:00:00 su - postgres
postgres  2962  2961  0 05:04 pts/1    00:00:00 -bash
postgres  5943  2962  0 05:23 pts/1    00:00:00 ps -ef
postgres  5944  2962  0 05:23 pts/1    00:00:00 grep --color=auto postgres

备实例状态：
[root@node4 etc]# ps -ef|grep postgres
postgres  1819     1  0 04:47 pts/0    00:00:02 /usr/pgsql-9.4/bin/postgres -D /var/lib/pgsql/9.4/data
postgres  1820  1819  0 04:47 ?        00:00:00 postgres: logger process   
postgres  1821  1819  0 04:47 ?        00:00:00 postgres: startup process   recovering 000000070000000000000050
postgres  1822  1819  0 04:47 ?        00:00:00 postgres: checkpointer process   
postgres  1823  1819  0 04:47 ?        00:00:00 postgres: writer process   
postgres  1824  1819  0 04:47 ?        00:00:00 postgres: stats collector process   
postgres  1828  1819  0 04:47 ?        00:00:02 postgres: wal receiver process   streaming 0/500006B0
root      2825  1874  0 05:05 pts/1    00:00:00 su - postgres
postgres  2826  2825  0 05:05 pts/1    00:00:00 -bash
postgres  2863  2826  0 05:05 pts/1    00:00:00 psql -h node4 -p 9999
root      5698  170  0 05:24 pts/0    00:00:00 grep --color=auto postgres

流复制状态：
postgres=# select * from pg_stat_replication ;
-[ RECORD 1 ]----+-----------------------------
pid              | 1818
usesysid         | 10
usename          | postgres
application_name | walreceiver
client_addr      | 192.168.31.134
client_hostname  | 
client_port      | 56966
backend_start    | 2021-02-05 04:47:32.39416-05
backend_xmin     | 
state            | streaming
sent_location    | 0/500006B0
write_location   | 0/500006B0
flush_location   | 0/500006B0
replay_location  | 0/500006B0
sync_priority    | 0
sync_state       | async



recovery.conf（恢复之后，原主节点）配置：

```
-bash-4.2$ cat recovery.conf    
standby_mode = 'on'
primary_conninfo = 'user=postgres host=node0 port=5432 sslmode=prefer sslcompression=1 krbsrvname=postgres'
```

其中recovery.conf为流复制所需要的的文件，保存在备节点上，指定了当前的主节点，用于备节点从主节点拉取WAL文件用于主备同步。


注意：在线恢复必须开启日志归档功能，否则无法恢复。











升级pg至9.6再试着恢复集群。