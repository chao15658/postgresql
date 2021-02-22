

#### repmgr选举策略



根据LSN、Priority和node id选择新的Primary节点。

函数调用如下：

  do_primary_failover->do_election

具体选举逻辑如下：

		/* compare LSN */
		if (cell->node_info->last_wal_receive_lsn > candidate_node->last_wal_receive_lsn)
		{
			/* other node is ahead */
			log_info(_("node \"%s\" (ID: %i) is ahead of current candidate \"%s\" (ID: %i)"),
					 cell->node_info->node_name,
					 cell->node_info->node_id,
					 candidate_node->node_name,
					 candidate_node->node_id);	
		    candidate_node = cell->node_info;
		}
		/* LSN is same - tiebreak on priority, then node_id */
		else if (cell->node_info->last_wal_receive_lsn == candidate_node->last_wal_receive_lsn)
		{
			log_info(_("node \"%s\" (ID: %i) has same LSN as current candidate \"%s\" (ID: %i)"),
					 cell->node_info->node_name,
					 cell->node_info->node_id,
					 candidate_node->node_name,
					 candidate_node->node_id);
	
			if (cell->node_info->priority > candidate_node->priority)
			{
				log_info(_("node \"%s\" (ID: %i) has higher priority (%i) than current candidate \"%s\" (ID: %i) (%i)"),
						 cell->node_info->node_name,
						 cell->node_info->node_id,
						 cell->node_info->priority,
						 candidate_node->node_name,
						 candidate_node->node_id,
						 candidate_node->priority);
	
				candidate_node = cell->node_info;
			}
			else if (cell->node_info->priority == candidate_node->priority)
			{
				if (cell->node_info->node_id < candidate_node->node_id)
				{
					log_info(_("node \"%s\" (ID: %i) has same priority but lower node_id than current candidate \"%s\" (ID: %i)"),
							 cell->node_info->node_name,
							 cell->node_info->node_id,
							 candidate_node->node_name,
							 candidate_node->node_id);
	
					candidate_node = cell->node_info;
				}
			}