

#### 问题:

pgpool-II版本 4.2

1、只启用1个pgpool-II去管理整个pg集群时，VIP无法启动

原因：

参数enable_consensus_with_half_votes被设置为了off



解法：

编辑pgpool.conf将enable_consensus_with_half_votes设置为on，之后重启pgpool，然后查看设置的VIP是否生效。



参数解释



       # apply majority rule for consensus and quorum computation
       # at 50% of votes in a cluster with even number of nodes.
       # when enabled the existence of quorum and consensus
       # on failover is resolved after receiving half of the
       # total votes in the cluster, otherwise both these
       # decisions require at least one more vote than
       # half of the total votes.
       # (change requires restart)
超过一半时开启仲裁。



