1个pgpool +1 Master + 2 Slave出现脑裂
pgpool心跳检测时会出现和Master通信不畅时误认为当前Master已死（实际上Master还活着）。pgpool会重新将另一个从节点拉起成为一个新的Master。
这样就会出现“双主”问题。
解决办法：
1、增加pg自杀机制。
2、增加集群中pgpool的节点数，起3个pgpool。

