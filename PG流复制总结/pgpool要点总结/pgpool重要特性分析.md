

# pgpool-II判主情况分析

#### 版本

pgpool-II-3.2.9

pg9.4

## pgpool判断pg master

#### 1、pgpool启动时判断master



调用栈如下：

   ->find_primary_node

  main

解释：

在pgpool启动过程中读取pgpool.conf中配置的数据库节点信息，对集群中数据库节点从0开始一个个遍历，并发送SQL语句 select pg_is_in_recovery() ，根据返回的结果判断

那个数据库节点是master。

#### 2、故障切换时pgpool选举master角色



调用栈如下：

   ->find_primary_node

->find_primary_node_repeatedly

failover



解释：

在故障切换时，pgpool读取配置文件写的backend信息，按照id从小到大选择一个新的节点作为新的pg master；如果遍历结束都未找到，返回-1。

```
static int find_primary_node(void)
{
	BackendInfo *bkinfo;
	POOL_CONNECTION_POOL_SLOT *s;
	POOL_CONNECTION *con; 
	POOL_SELECT_RESULT *res;
	bool is_standby;
	int i;
```

	/* Streaming replication mode? */
	if (pool_config->master_slave_mode == 0 ||
		strcmp(pool_config->master_slave_sub_mode, MODE_STREAMREP))
	{
		/* No point to look for primary node if not in streaming
		 * replication mode.
		 */
		pool_debug("find_primary_node: not in streaming replication mode");
		return -1;
	}
	for(i=0;i<NUM_BACKENDS;i++)
	{
		if (!VALID_BACKEND(i))
			continue;
		/*
		 * Check to see if this is a standby node or not.
		 */
		is_standby = false;
	
		bkinfo = pool_get_node_info(i);
		s = make_persistent_db_connection(bkinfo->backend_hostname, 
										  bkinfo->backend_port,
										  "postgres",
										  pool_config->sr_check_user,
										  pool_config->sr_check_password, true);
		if (!s)
		{
			pool_error("find_primary_node: make_persistent_connection failed");
	
			/*
			 * It is possible that a node is down even if
			 * VALID_BACKEND tells it's valid.  This could happen
			 * before health checking detects the failure.
			 * Thus we should continue to look for primary node.
			 */
			continue;
		}
		con = s->con;
```
#ifdef NOT_USED
		status = do_query(con, "SELECT count(*) FROM pg_catalog.pg_proc AS p WHERE p.proname = 'pgpool_walrecrunning'",
						  &res, PROTO_MAJOR_V3);
		if (res->numrows <= 0)
		{
			pool_log("find_primary_node: do_query returns no rows");
		}
		if (res->data[0] == NULL)
		{
			pool_log("find_primary_node: do_query returns no data");
		}
		if (res->nullflags[0] == -1)
		{
			pool_log("find_primary_node: do_query returns NULL");
		}
		if (res->data[0] && !strcmp(res->data[0], "0"))
		{
			pool_log("find_primary_node: pgpool_walrecrunning does not exist");
			free_select_result(res);
			discard_persistent_db_connection(s);
			return -1;
		}
#endif
		if(do_query(con, "SELECT pg_is_in_recovery()", &res, PROTO_MAJOR_V3) == POOL_CONTINUE)
		{
			if (res->numrows <= 0)
			{
				pool_log("find_primary_node: do_query returns no rows");
			}
			if (res->data[0] == NULL)
			{
				pool_log("find_primary_node: do_query returns no data");
			}
			if (res->nullflags[0] == -1)
			{
				pool_log("find_primary_node: do_query returns NULL");
			}
			if (res->data[0] && !strcmp(res->data[0], "t"))
			{
				is_standby = true;
			}
		}
		else
		{
			pool_log("find_primary_node: do_query failed");
		}
		if(res)
			free_select_result(res);
		discard_persistent_db_connection(s);
```

		/*
		 * If this is a standby, we continue to look for primary node.
		 */
		if (is_standby)
		{
			pool_debug("find_primary_node: %d node is standby", i);
		}
		else
		{
			break;
		}
	}
	if (i == NUM_BACKENDS)
	{
		pool_debug("find_primary_node: no primary node found");
		return -1;
	}
	
	pool_log("find_primary_node: primary node id is %d", i);
	return i;
	}




	static int find_primary_node_repeatedly(void)
	{
		int sec;
		int node_id = -1;
	/* Streaming replication mode? */
	if (pool_config->master_slave_mode == 0 ||
		strcmp(pool_config->master_slave_sub_mode, MODE_STREAMREP))
	{
		/* No point to look for primary node if not in streaming
		 * replication mode.
		 */
		pool_debug("find_primary_node: not in streaming replication mode");
		return -1;
	}
	
	pool_log("find_primary_node_repeatedly: waiting for finding a primary node");
	for (sec = 0; sec < pool_config->recovery_timeout; sec++)
	{
		node_id = find_primary_node();
		if (node_id != -1)
			break;
		pool_sleep(1);
	}
	return node_id;
	}


参考链接

 https://www.cnblogs.com/songyuejie/p/7054393.html 

## pgpool自身VIP选取机制









 `failover_when_quorum_exists`  

 `failover_require_consensus`  

 `allow_multiple_failover_requests_from_node`  

 `enable_consensus_with_half_votes`  

