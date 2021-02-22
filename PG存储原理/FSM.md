## FSM（空闲空间映射）

和数据文件一一对应。



## 创建时机：

1、vacuum关系时

2、第一次insert表查找FSM文件时

```
/*

 \* Structure of a FSM page. See src/backend/storage/freespace/README for

 \* details.

 */
typedef struct
{
​    /*
​     \* fsm_search_avail() tries to spread the load of multiple backends by
​     \* returning different pages to different backends in a round-robin
​     \* fashion. fp_next_slot points to the next slot to be returned (assuming
​     \* there's enough space on it for the request). It's defined as an int,
​     \* because it's updated without an exclusive lock. uint16 would be more
​     \* appropriate, but int is more likely to be atomically
​     \* fetchable/storable.
​     */
​    int         fp_next_slot;
​    /*
​     \* fp_nodes contains the binary tree, stored in array. The first
​     \* NonLeafNodesPerPage elements are upper nodes, and the following
​     \* LeafNodesPerPage elements are leaf nodes. Unused nodes are zero.
​     */
​    uint8       fp_nodes[FLEXIBLE_ARRAY_MEMBER];
} FSMPageData;
```



待补充

FSM逻辑图、FSM创建、查询、调整

![freespacemap](C:\Users\cc\Desktop\freespacemap.png)







#### 参考资料

C:\Users\cc\Desktop\工作总结\book\pg\POSTGRESQL修炼之道从小工到专家.pdf

C:\Users\cc\Desktop\工作总结\book\pg\PostgreSQL数据库内核分析@www.java1234.com.pdf