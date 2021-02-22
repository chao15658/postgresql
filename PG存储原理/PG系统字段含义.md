# PG系统字段含义

xmax 删除或更新事务id，首次插入时，该字段值默认为0。

xmin 插入事务id

cmax 删除命令id  等同于cmin，标识事务内命令执行顺序。

cmin 插入命令id

ctid 元组物理位置（块号+块内偏移）

这4个字段为隐藏字段，可使用pageinspect查看或直接查找这几个字段。

postgres=# select ctid,xmin,xmax,cmax,cmin ,*from dev;
 ctid  | xmin | xmax | cmax | cmin | a
-------+------+------+------+------+---
 (0,4) | 2038 |    0 |    0 |    0 | 4
(1 row)

#### 验证结果如下：

postgres=#  create table dev(a int);
CREATE TABLE

postgres=# insert into dev values(1);
INSERT 0 1
postgres=# SELECT * FROM heap_page_items(get_raw_page('dev', 0));
 lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid | t_infomask2 | t_infomask | t_hoff | t_bits | t_oid |   t_data
----+--------+----------+--------+--------+--------+----------+--------+-------------+------------+--------+--------+-------+------------
  1 |   8160 |        1 |     28 |   2035 |      0 |        0 | (0,1)  |           1 |       2048 |     24 |        |       | \x01000000
(1 row)

如上所示，xmin为插入事务id，目前未进行删除或更新，该值为0。ctid标识元组物理位置，目前指向自身。

postgres=# update dev set a=2 where a=1;
UPDATE 1
postgres=# SELECT * FROM heap_page_items(get_raw_page('dev', 0));
 lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid | t_infomask2 | t_infomask | t_hoff | t_bits | t_oid |   t_data
----+--------+----------+--------+--------+--------+----------+--------+-------------+------------+--------+--------+-------+------------
  1 |   8160 |        1 |     28 |   2035 |   2036 |        0 | (0,2)  |       16385 |        256 |     24 |        |       | \x01000000
  2 |   8128 |        1 |     28 |   2036 |      0 |        0 | (0,2)  |       32769 |      10240 |     24 |        |       | \x02000000
(2 rows)

更新之后，新增一行，ctid指向新增的行。xmax更新为2036 （插入事务id）。

postgres=# update dev set a=3 where a=2;
UPDATE 1
postgres=# SELECT * FROM heap_page_items(get_raw_page('dev', 0));
 lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid | t_infomask2 | t_infomask | t_hoff | t_bits | t_oid |   t_data
----+--------+----------+--------+--------+--------+----------+--------+-------------+------------+--------+--------+-------+------------
  1 |   8160 |        1 |     28 |   2035 |   2036 |        0 | (0,2)  |       16385 |       1280 |     24 |        |       | \x01000000
  2 |   8128 |        1 |     28 |   2036 |   2037 |        0 | (0,3)  |       49153 |       8448 |     24 |        |       | \x02000000
  3 |   8096 |        1 |     28 |   2037 |      0 |        0 | (0,3)  |       32769 |      10240 |     24 |        |       | \x03000000
(3 rows)

postgres=# update dev set a=4 where a=3;
UPDATE 1
postgres=# SELECT * FROM heap_page_items(get_raw_page('dev', 0));
 lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid | t_infomask2 | t_infomask | t_hoff | t_bits | t_oid |   t_data
----+--------+----------+--------+--------+--------+----------+--------+-------------+------------+--------+--------+-------+------------
  1 |   8160 |        1 |     28 |   2035 |   2036 |        0 | (0,2)  |       16385 |       1280 |     24 |        |       | \x01000000
  2 |   8128 |        1 |     28 |   2036 |   2037 |        0 | (0,3)  |       49153 |       9472 |     24 |        |       | \x02000000
  3 |   8096 |        1 |     28 |   2037 |   2038 |        0 | (0,4)  |       49153 |       8448 |     24 |        |       | \x03000000
  4 |   8064 |        1 |     28 |   2038 |      0 |        0 | (0,4)  |       32769 |      10240 |     24 |        |       | \x04000000
(4 rows)

测试vacuum效果：

postgres=# vacuum dev;
VACUUM

postgres=# SELECT * FROM heap_page_items(get_raw_page('dev', 0));
 lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid | t_infomask2 | t_infomask | t_hoff | t_bits | t_oid |   t_data
----+--------+----------+--------+--------+--------+----------+--------+-------------+------------+--------+--------+-------+------------
  1 |      4 |        2 |      0 |        |        |          |        |             |            |        |        |       |
  2 |      0 |        0 |      0 |        |        |          |        |             |            |        |        |       |
  3 |      0 |        0 |      0 |        |        |          |        |             |            |        |        |       |
  4 |   8160 |        1 |     28 |   2038 |        0 |        0 | (0,4)  |       32769 |      10496 |     24 |        |       | \x04000000
(4 rows)

指针被清空，lp_off直接指向新行。同时lp_flags为2（HOT重定向）。



#### lp_flag行状态标识

#define LP_UNUSED       0       /* unused (should always have lp_len=0) */未使用

\#define LP_NORMAL       1       /* used (should always have lp_len>0) */    已使用

\#define LP_REDIRECT     2       /* HOT redirect (should have lp_len=0) */   HOT重定向  。vacuum会将旧的行标记为LP_REDIRECT   

\#define LP_DEAD         3       /* dead, may or may not have storage */          死亡



#### cmin，cmax测试

每插入一次不同的值，cmin、cmax增加1：

postgres=# begin;
BEGIN
postgres=# select xmin,xmax,cmin,cmax,* from dev;
 xmin | xmax | cmin | cmax | a
------+------+------+------+---
 2049 |    0 |    0 |    0 | 5
(1 row)

postgres=# insert into dev values(5);
INSERT 0 1
postgres=# select xmin,xmax,cmin,cmax,* from dev;
 xmin | xmax | cmin | cmax | a
------+------+------+------+---
 2049 |    0 |    0 |    0 | 5
 2050 |    0 |    0 |    0 | 5
(2 rows)

postgres=# insert into dev values(4);
INSERT 0 1
postgres=# select xmin,xmax,cmin,cmax,* from dev;
 xmin | xmax | cmin | cmax | a
------+------+------+------+---
 2049 |    0 |    0 |    0 | 5
 2050 |    0 |    0 |    0 | 5
 2050 |    0 |    1 |    1 | 4
(3 rows)

postgres=# insert into dev values(3);
INSERT 0 1
postgres=# select xmin,xmax,cmin,cmax,* from dev;
 xmin | xmax | cmin | cmax | a
------+------+------+------+---
 2049 |    0 |    0 |    0 | 5
 2050 |    0 |    0 |    0 | 5
 2050 |    0 |    1 |    1 | 4
 2050 |    0 |    2 |    2 | 3
(4 rows)

postgres=# insert into dev values(2);
INSERT 0 1
postgres=# select xmin,xmax,cmin,cmax,* from dev;
 xmin | xmax | cmin | cmax | a
------+------+------+------+---
 2049 |    0 |    0 |    0 | 5
 2050 |    0 |    0 |    0 | 5
 2050 |    0 |    1 |    1 | 4
 2050 |    0 |    2 |    2 | 3
 2050 |    0 |    3 |    3 | 2
(5 rows)

