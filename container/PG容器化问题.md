# PG流复制遇到的问题



## 1、pgpool连接数超了，导致pgpool不断挂掉并被k8s重启

### 定位过程，使用kubectl describe -n itoa +pod_name 查看pod描述信息发现liveness报错信息如下：

psql timeout expired

### 查看liveness调用脚本如下：

/usr/local/bin/pgpool/has_write_node.sh  && /usr/local/bin/pgpool/has_enough_backends.sh

/usr/local/bin/pgpool/has_write_node.sh内容如下：

![1561726922576](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1561726922576.png)

通过读取环境变量的值，使用psql连接postgresql，show pool_nodes获取pg所有实例。过滤出主实例，并计数，如果主实例个数小于1，则退出码为1，否则为0。（shell中，0代表正常退出，1代表异常退出）

/usr/local/bin/pgpool/has_enough_backends.sh内容如下：

![1561727110487](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1561727110487.png)

使用psql连接pgpool获取所有pg后端数。判断当前运行的后端数是否少于设定的后端数，如果少于，则异常退出；否则，正常退出。（REQUIRE_MIN_BACKENDS在dockerfile里设置了，可以在容器启动时指定）

#### 解决办法：

num_init_children

 控制并发连接数，根据需要调大该值。重启pgpool。预生成的 pgpool-II 服务进程数。默认为 32。 num_init_children 也是 pgpool-II 支持的从客户端发起的最大并发连接数。 如果超过 num_init_children 数的客户端尝试连接到 pgpool-II，它们将被阻塞（而不是拒绝连接）， 直到到任何一个 pgpool-II 进程的连接被关闭为止。 最多有 2*num_init_children 可以被放入等待队列。

#### max_pool

在 pgpool-II 子进程中缓存的最大连接数。当有新的连接使用相同的用户名连接到相同的数据库，pgpool-II 将重用缓存的连接。如果不是，则 pgpool-II 建立一个新的连接到 PostgreSQL。如果缓存的连接数达到了 max_pool，则最老的连接将被抛弃，并使用这个槽位来保存新的连接。默认值为 4。请小心通过 pgpool-II 进程到后台的连接数可能达到`num_init_children` * `max_pool` 个。需要重启 pgpool-II 以使改动生效。



### 2、pgpool开启负载均衡出现大量数据插入后，立即查询时查不到提交的数据。

​      pg默认开启异步复制，以及pgpool默认启用负载均衡。由此导致主备节点数据同步存在时延。

解决办法：要么pg开启同步流复制；要么在这种场景下关闭pgpool的负载均衡。

同步流复制：只有当主备节点的WAL都持久化后，插入事务才会提交。

pgpool负载均衡：pgpool会将select类型语句发送到主或者从节点，根据自身的规则。在异步流复制情况下，会出现短时间数据不同步。

同步流复制开启弊端：

当开启一主一从时，主备数据完全同步，数据零丢失。但是，当从节点停机后，主节点数据插入会一直阻塞，直到从恢复。

当存在多个从时，只有一个主处于同步状态，在pgpool开启负载均衡时也会出现访问延时问题。

关闭方法：在查询语句前增加如下注释：

/NO LOAD BALANCE*/ SELECT count(*) from test;

或者使用修改pgpool.conf将参数load_balance_mode设为off来关闭pgpool的负载均衡。 



### 3、pgpool连接释放时间过长，导致连接数增长过快，2-3分钟就能达到上限，出现连接拒绝问题。

报错信息：

#### FATAL: remaining connection slots are reserved for non-replication superuser connections

发现pgpool连接数配置有问题

配置公式：

max_pool，num_init_children，max_connections 和 superuser_reserved_connections 必须符合以下规则：

```
max_pool*num_init_children <= (max_connections - superuser_reserved_connections) (不需要取消查询)
max_pool*num_init_children*2 <= (max_connections - superuser_reserved_connections) (需要取消查询)
```

当时配置max_connections 2000  superuser_reserved_connections 3  

max_pool 10 num_init_children 2000

正确配置为

需要取消查询

max_pool 2   num_init_children 2000

max_connections 8010 superuser_reserved_connections 3

要根据实际业务需求调整。



#### 4、在pg一主一从切换后，然后给pg插入一些数据，将原来的主拉起来后出现主备数据不同步问题

这是流复制在这种一主一备场景下的问题，需要手动做数据同步。同步方法参考postgresql从小工到专家.pdf。

手动也可以浮现这种问题。

复现步骤：

1、搭建pg模型，一主一从

2、给主插入几条数据

3、分别连接主、备节点，查询数据量是否一致

4、停止主节点，pgpool会自动将备切成主

5、给当前的主再插入几条数据

6、将原来的主拉起来，同时连接这两个节点，发现数据量不一致。



#### 参考链接

<http://www.pgpool.net/docs/pgpool-II-3.5.4/doc/pgpool-zh_cn.html#NUM_INIT_CHILDREN>

<https://yq.aliyun.com/articles/55676>

<https://yq.aliyun.com/articles/498414?spm=a2c4e.11153940.0.0.51284e92NNKASg>