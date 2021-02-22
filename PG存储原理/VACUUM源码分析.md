# VACUUM源码分析

调用关系大致如下：

vacuum

-> vacuum_rel

​    ->cluster_rel  :  对应full vacuum

​    ->lazy_vacuum_rel ： 对应 lazy vacuum

​         ->lazy_scan_heap

​             ->lazy_vacuum_heap  删除堆中的每个页面，其中包括将死元组截断为死行指针、整理页面碎片

​                 ->lazy_vacuum_page  清理单页死亡元组并整理碎片，将dead tuple标记为unused（0）。

​                     ->PageRepairFragmentation  碎片整理



1、FULL VACUUM

Vacuum Full和Vacuum最大的不同就是，Vacuum Full是物理删除dead tuples，并把释放的空间重新交给操作系统，所以在vacuum full后，表的大小会减小为实际的空间大小。其处理过程和vacuum大不相同，处理步骤如下：

  \1. vacuum full开始执行时，系统会先对目标创建一个AccessExclusiveLock ，不允许外界再进行访问（为后面拷贝做准备），然后创建一个表结构和目标表相同的新表。

  \2. 扫描目标表，把表中的live tuples 拷贝到新表中。

  \3. 删除目标表，在新表上，重新创建索引，更新VM， FSM以及统计信息，相关系统表等。

  vacuum full的本质是生成一个新的数据文件，然后把原有表的live tuples存放到该数据文件中。对比vacuum， vacuum full缺点就是在执行期间不能对表进行访问，由于需要往新表中导入live tuples数据，其执行效率也会很慢。优点是执行后，表空间只存放live tuples，没有冗余的dead tuples，在执行查询效率上会有所提高。

2、LAZY VACUUM



问题1：并发vacuum怎么做的

问题2：在线vacuum的 pg_repack怎么实现的

1、在原表上创建触发器

2、建立临时表，索引

3、将原表数据导入临时表

4、表重命名，数据文件交换

问题3：HOT怎么vacuum HOT链、处理无效行、索引

问题4：HOT面临的问题

更新后两行不在同一个页面HOT失效、更新的索引属性未发生变化

- 为了避免XID 回卷，freeze tuple等操作是如何实现的
- FULL vacuum的具体操作是如何实现的
- TOAST 表的vacuum 是如何实现的