#### standby_redo



#### heap2_redo



当standby节点有查询冲突时，会产生恢复过程中的等待，到等待时间后会杀死standby的查询进程。

[postgres@node2 ~]$ pstack 7370
#0  0x00007f68b5dc4f53 in __select_nocancel () from /lib64/libc.so.6
#1  0x00000000009d61f6 in pg_usleep (microsec=1000000) at pgsleep.c:56
#2  0x00000000007fed49 in ***WaitExceedsMaxStandbyDelay*** () at standby.c:200
#3  0x00000000007fee85 in ResolveRecoveryConflictWithVirtualXIDs (waitlist=0x13062c8, reason=PROCSIG_RECOVERY_CONFLICT_LOCK) at standby.c:261
#4  0x00000000007ff07b in ResolveRecoveryConflictWithLock (locktag=...) at standby.c:404
#5  0x000000000080c4cc in ProcSleep (locallock=0x1300300, lockMethodTable=0xb5e120 <default_lockmethod>) at proc.c:1223
#6  0x00000000008056ed in WaitOnLock (locallock=0x1300300, owner=0x0) at lock.c:1745
#7  0x00000000008043b8 in LockAcquireExtended (locktag=0x7ffc44297930, lockmode=8, sessionLock=1 '\001', dontWait=0 '\000', reportMemoryError=1 '\001', locallockp=0x0) at lock.c:1026
#8  0x000000000080395d in LockAcquire (locktag=0x7ffc44297930, lockmode=8, sessionLock=1 '\001', dontWait=0 '\000') at lock.c:689
#9  0x00000000007ff40c in StandbyAcquireAccessExclusiveLock (xid=10237, dbOid=13325, relOid=33506) at standby.c:667
#10 0x00000000007ff8a7 in **standby_redo*** (record=0x1302950) at standby.c:822
#11 0x00000000005339b0 in StartupXLOG () at xlog.c:6989
#12 0x00000000007999ae in StartupProcessMain () at startup.c:210
#13 0x0000000000547528 in AuxiliaryProcessMain (argc=2, argv=0x7ffc44298530) at bootstrap.c:419
#14 0x000000000079896a in StartChildProcess (type=StartupProcess) at postmaster.c:5306
#15 0x00000000007934ec in PostmasterMain (argc=1, argv=0x12d6a40) at postmaster.c:1322
#16 0x00000000006daeae in main (argc=1, argv=0x12d6a40) at main.c:228



[postgres@sscloud21 ~]$ pstack 197120
#0  0x00007f695b6faf53 in __select_nocancel () from /lib64/libc.so.6
#1  0x000000000088c97a in pg_usleep (microsec=<optimized out>) at pgsleep.c:56
#2  0x0000000000729ef9 in **WaitExceedsMaxStandbyDelay** () at standby.c:201
#3  ResolveRecoveryConflictWithVirtualXIDs (waitlist=0x1c706e0, reason=reason@entry=PROCSIG_RECOVERY_CONFLICT_SNAPSHOT) at standby.c:262
#4  0x000000000072a10e in ResolveRecoveryConflictWithVirtualXIDs (reason=PROCSIG_RECOVERY_CONFLICT_SNAPSHOT, waitlist=<optimized out>) at standby.c:315
#5  ResolveRecoveryConflictWithSnapshot (latestRemovedXid=<optimized out>, node=...) at standby.c:313
#6  0x00000000004c23be in heap_xlog_clean (record=0x1c00698) at heapam.c:8198
#7  **heap2_redo** (record=0x1c00698) at heapam.c:9351
#8  0x0000000000503e85 in StartupXLOG () at xlog.c:7306
#9  0x00000000006d82b1 in StartupProcessMain () at startup.c:211
#10 0x0000000000512275 in AuxiliaryProcessMain (argc=argc@entry=2, argv=argv@entry=0x7fff8b5d99b0) at bootstrap.c:441
#11 0x00000000006d53a0 in StartChildProcess (type=StartupProcess) at postmaster.c:5331
#12 0x00000000006d7b75 in PostmasterMain (argc=argc@entry=3, argv=argv@entry=0x1bd0e40) at postmaster.c:1371
#13 0x000000000048124f in main (argc=3, argv=0x1bd0e40) at main.c:228

