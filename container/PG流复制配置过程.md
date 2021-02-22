# PG流复制配置



#### Standby数据库原理：

首先我们做主从同步的目的就是实现db服务的高可用性，通常是一台主数据库提供读写，然后把数据同步到另一台从库，然后从库不断apply从主库接收到的数据，从库不提供写服务，只提供读服务。在postgresql中提供读写全功能的服务器称为primary database或master database，在接收主库同步数据的同时又能提供读服务的从库服务器称为hot standby server。

#### 1、搭建两个PG数据库（最好版本一致）

#### 2、主库数据目录postgresql.conf作如下修改

1.listen_address = ‘*’（默认localhost）
2.port = 10280       （默认是5432）
3.wal_level = hot_standby（默认是minimal）
4.max_wal_senders=2（默认是0）
5.wal_keep_segments=64（默认是0）

参数说明：

第一个是监听任何主机，wal_level表示启动搭建Hot Standby，max_wal_senders则需要设置为一个大于0的数，它表示主库最多可以有多少个并发的standby数据库，而最后一个wal_keep_segments也应当设置为一个尽量大的值，以防止主库生成WAL日志太快，日志还没有来得及传送到standby就被覆盖，但是需要考虑磁盘空间允许，一个WAL日志文件的大小是16M。

#### 3、接下来还需要在主库创建一个超级用户来专门负责让standby连接去拖WAL日志：

CREATE ROLE replica login replication encrypted password 'replica';

#### 4、打开数据目录下的pg_hba.conf文件然后做以下修改：

[postgres@localhost pg_xlog]$ tail -2 /data/pgsql100/data/pg_hba.conf 
#host    replication     postgres        ::1/128                 trust
host    replication     replica     10.0.0.110/32                md5

#### 5、启动主库

pg_ctl start

#### 6、从库上初始化数据库时指定的数据目录清空，在从库上使用pg_basebackup命令工具来生成master主库的基础备份数据。

出现下面信息，说明备份成功。

46256/46256 kB (100%), 1/1 tablespace

pg_basebackup -h node1 -U replica -p 5432 -F p -x -P -R -D /opt/pg_data -l replbackup

#### 参数说明（可以通过pg_basebackup --help进行查看），

-h指定连接的数据库的主机名或IP地址，这里就是主库的ip。
-U指定连接的用户名，此处是我们刚才创建的专门负责流复制的repl用户。
-F指定了输出的格式，支持p（原样输出）或者t（tar格式输出）。
-x表示备份开始后，启动另一个流复制连接从主库接收WAL日志。
-P表示允许在备份过程中实时的打印备份的进度。
-R表示会在备份结束后自动生成recovery.conf文件，这样也就避免了手动创建。

-D指定把备份写到哪个目录，这里尤其要注意一点就是做基础备份之前从库的数据目录（/data/psql110/data/）目录需要手动清空。

-l为备份设置标签

生成的恢复文件：

[postgres@node2 pg_data]$ cat recovery.conf
standby_mode = 'on'
primary_conninfo = 'user=replica host=node1 port=5432 sslmode=prefer sslcompression=1 krbsrvname=postgres'



#### 7、修改从库

修改一下从库数据目录下的postgresql.conf文件，将hot_standby改为启用状态，即hot_standby=on。

参数含义

hot_standby = on            # "on" allows queries during recovery

#### 8、启动从库

pg_ctl start

9、验证

从库看到进程

[postgres@node2 ~]$ ps -ef|grep postgres
root       7234   7217  0 11:09 pts/0    00:00:00 su - postgres
postgres   7235   7234  0 11:09 pts/0    00:00:00 -bash
postgres   7258      1  0 11:09 pts/0    00:00:00 /home/postgres/pg96/bin/postgres
***postgres   7259   7258  0 11:09 ?        00:00:00 postgres: startup process   recovering 000000010000000000000003***
postgres   7260   7258  0 11:09 ?        00:00:00 postgres: checkpointer process
postgres   7261   7258  0 11:09 ?        00:00:00 postgres: writer process
postgres   7262   7258  0 11:09 ?        00:00:00 postgres: stats collector process
***postgres   7263   7258  0 11:09 ?        00:00:00 postgres: wal receiver process   streaming 0/304CA*68**
postgres   7264   7235  2 11:10 pts/0    00:00:00 ps -ef
postgres   7265   7235  0 11:10 pts/0    00:00:00 grep --color=auto postgres

主库看到如下进程

[root@node1 ~]# ps -ef|grep postgres
root       7327   7309  0 11:09 pts/1    00:00:00 su - postgres
postgres   7328   7327  0 11:09 pts/1    00:00:00 -bash
postgres   7351      1  0 11:09 pts/1    00:00:00 /home/postgres/pg96/bin/postgres
postgres   7353   7351  0 11:09 ?        00:00:00 postgres: checkpointer process
postgres   7354   7351  0 11:09 ?        00:00:00 postgres: writer process
postgres   7355   7351  0 11:09 ?        00:00:00 postgres: wal writer process
postgres   7356   7351  0 11:09 ?        00:00:00 postgres: autovacuum launcher process
postgres   7357   7351  0 11:09 ?        00:00:00 postgres: stats collector process
postgres   7358   7351  0 11:09 ?        00:00:00 postgres: bgworker: TimescaleDB Background Worker Launcher
postgres   7359   7351  0 11:09 ?        00:00:00 postgres: bgworker: TimescaleDB Background Worker Scheduler    waiting for 0/304CA30
***postgres   7360   7351  0 11:09 ?        00:00:00 postgres: wal sender process postgres 192.168.31.131(18531)*** ***streaming 0/304CA68***
postgres   7361   7328  0 11:09 pts/1    00:00:00 psql
postgres   7362   7351  0 11:09 ?        00:00:00 postgres: postgres postgres [local] idle
root       7371   7279  0 11:12 pts/0    00:00:00 grep --color=auto postgres

#### 11、主库建表



## 相关参数

wal_level = hot_standby（默认是minimal）

多种模式minimal, archive,replica，hot_standby, or logical

wal_level决定有多少信息被写入到WAL中。

 默认值是最小的，其中写入唯一从崩溃或立即关机中恢复的所需信息。

 archive补充WAL归档需要的日志记录； 

hot_standby进一步增加在备用服务器上运行只读查询所需的信息； 

最终logical增加支持逻辑编码所必需的信息。 
每个级别都包括所有更低级别记录的信息，这个参数只能在服务器启动时设置。

4.max_wal_senders=2（默认是0）

max_wal_senders则需要设置为一个大于0的数，它表示主库最多可以有多少个并发的standby数据库。

5.wal_keep_segments=64（默认是0）

表示主库保存的xlog的个数，每个文件16MB，wal_keep_segments也应当设置为一个尽量大的值，以防止主库生成WAL日志太快，日志还没有来得及传送到standby就被覆盖，但是需要考虑磁盘空间允许。

hot_standby = on            # "on" allows queries during recovery

指定恢复期间是否可以连接并运行查询，默认值是off。 这个参数只能在服务器启动时设置。它在存档恢复或处于待机模式时见效。

## synchronous_commit（同步复制的几种级别）

synchronous_commit参数设置on,remote_write,local,off

on：在primary数据库提交事务时，必须要等事务日志刷写到本地磁盘,并且还需要等到传到备库确认（备库已经接收到流日志，并且落盘写到日志文件）才会返回客户端已经提交，这样可以保证主备库数据零丢失。

remote_write：主库的事务提交时，必须要等事务日志刷写到本地磁盘,并且还需要等到传到备库确认（备库已经接收到数据库内存，不要求落盘）才会返回客户端已经提交，这样可以保证备库数据可能不丢失，（如果操作系统故障，内存数据会丢失）。

local：主库的事务提交时，必须要等事务日志刷写到本地磁盘，不必等备库的确认，备库会延迟主库几秒数据，但是这种方式对主库性能影响较小。

off：主库的事务提交时，不需要等事务日志刷写到本地磁盘，直接返回客户端已经提交。



#### 注意：

如果1主1备同步模式，备库故障会导致主库挂起；通常解决办法是1主多备，只要有任意备库可用，主库就不会挂起。



## 流复制延迟查看

在主库上执行

```
select
        application_name,
        pg_size_pretty(pg_xlog_location_diff(pg_current_xlog_location(), replay_location)) as diff
from
        pg_stat_replication;
```

查询结果：

postgres=# **select****
        **application_name,**
        **pg_size_pretty(pg_xlog_location_diff(pg_current_xlog_location(), replay_location)) as diff**
**from**
        pg_stat_replication;**
-[ RECORD 1 ]----+------------
application_name | walreceiver
diff             | 32 MB

函数pg_xlog_location_diff说明：

基本描述

用于查看备库落后主库多少个字节的wal日志

入参：事务id

postgres=# \df+ pg_xlog_location_diff
List of functions
-[ RECORD 1 ]-------+----------------------------------------------
Schema              | pg_catalog
Name                | pg_xlog_location_diff
Result data type    | numeric
Argument data types | pg_lsn, pg_lsn
Type                | normal
Volatility          | immutable
Parallel            | safe
Owner               | postgres
Security            | invoker
Access privileges   |
Language            | internal
Source code         | pg_xlog_location_diff
Description         | difference in bytes, given two xlog locations



### 二、时间差异

在从库上执行：

```
select now() - pg_last_xact_replay_timestamp() as replication_delay;
```

函数pg_last_xact_replay_timestamp介绍

standby recovery过程中最后一个事务执行的时间。

postgres=# \df+ pg_last_xact_replay_timestamp
List of functions
-[ RECORD 1 ]-------+------------------------------
Schema              | pg_catalog
Name                | pg_last_xact_replay_timestamp
Result data type    | timestamp with time zone
Argument data types |
Type                | normal
Volatility          | volatile
Parallel            | safe
Owner               | postgres
Security            | invoker
Access privileges   |
Language            | internal
Source code         | pg_last_xact_replay_timestamp
Description         | timestamp of last replay xact



#### 参考链接

https://yq.aliyun.com/articles/498414?spm=a2c4e.11153940.0.0.51284e92NNKASg

https://blog.csdn.net/sunziyue/article/details/50972106

