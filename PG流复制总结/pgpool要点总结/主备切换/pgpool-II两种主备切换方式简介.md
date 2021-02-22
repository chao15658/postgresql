pgpool主备切换方式简介

1、使用trigger文件
基本原理
在主服务器发生故障时快速在备节点创建一个触发文件trigger_file,备库一旦检测到该文件，立马从只读模式提升为读写模式，从而继续为前台提供服务。

配置文件（failover.sh + recovery.conf+pgpool.conf）

pgpool.conf
failover_command = '/usr/local/pgpool/etc/failover.sh %d %H /var/lib/pgsql/trigger_file'

缺陷：只能切换一次，判断如果备节点挂掉，就直接退出。
补救：根据节点性质进行判断，或使用pg_ctl promote。


2、pg_ctl promote
基本原理
在主服务器挂掉时在备服务器执行pg_ctl promote将备服务器提升为新的主节点，继续对外提供服务。

配置文件（failover_promote.sh + recovery.conf+pgpool.conf）

pgpool.conf
failover_command = '/usr/local/pgpool/etc/failover.sh %H'

优缺点
不涉及节点id变更，可以主备来回切换。

