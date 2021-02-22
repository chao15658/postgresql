# HASH索引

#### 基本组织结构：

![1572882457075](C:\Users\cc\AppData\Roaming\Typora\typora-user-images\1572882457075.png)



```
元页结构
typedef struct HashMetaPageData
{
​    uint32      hashm_magic;    /* magic no. for hash tables */
​    uint32      hashm_version;  /* version ID */
​    double      hashm_ntuples;  /* number of tuples stored in the table 表存储的行数*/
​    uint16      hashm_ffactor;  /* target fill factor (tuples/bucket) 目标填充因子（总行数/桶个数）*/
​    uint16      hashm_bsize;    /* index page size (bytes) 索引页大小（字节）*/
​    uint16      hashm_bmsize;   /* bitmap array size (bytes) - must be a power of 2  位图数组大小*/
​    uint16      hashm_bmshift;  /* log2(bitmap array size in BITS)  */
​    uint32      hashm_maxbucket;    /* ID of maximum bucket in use 在用的最大桶的ID*/
​    uint32      hashm_highmask; /* mask to modulo into entire table 桶号高16位*/
​    uint32      hashm_lowmask;  /* mask to modulo into lower half of table 桶号低16位*/
​    uint32      hashm_ovflpoint;/* splitpoint from which ovflpgs being allocated 溢出页分裂点*/
​    uint32      hashm_firstfree;    /* lowest-number free ovflpage (bit#) 第一个空闲页*/
​    uint32      hashm_nmaps;    /* number of bitmap pages */
​    RegProcedure hashm_procid;  /* hash procedure id from pg_proc */
​    uint32      hashm_spares[HASH_MAX_SPLITPOINTS];     /* spare pages before each splitpoint 每一次分裂点的空闲页*/
​    BlockNumber hashm_mapp[HASH_MAX_BITMAPS];   /* blknos of ovfl bitmaps 溢出页的块id*/
} HashMetaPageData;
```



```
Hash页数据结构
双链表结构：记录前一页、后一页指针、页所在桶id
typedef struct HashPageOpaqueData
{
​    BlockNumber hasho_prevblkno;    /* previous ovfl (or bucket) blkno 前一个溢出页指针 */
​    BlockNumber hasho_nextblkno;    /* next ovfl blkno 后一个溢出页指针 */
​    Bucket      hasho_bucket;   /* bucket number this pg belongs to 页所在的桶ID */
​    uint16      hasho_flag;     /* page type code, see above 页的类型 */
​    uint16      hasho_page_id;  /* for identification of hash indexes */
} HashPageOpaqueData;
```



# 索引

#### 索引创建

hashbuild

​    _hash_metapinit  初始化元页

填充因子计算方法

#### 1、为什么要进行桶分裂？

因为实际每个桶填充因子超过设定值

ffactor=num_tuples/nbuckets 因为桶个数nbuckets在动态变化，而且一般情况下每次增加一个，如果hctl->max_bucket变成了2的整数次幂，就需要更新hctl->low_mask和hctl->high_mask。

#### 2、为什么要添加溢出页？

待插数据的桶没有空间，因此需要增加溢出页，链接到桶的尾部，并将新数据插入新的溢出页中。

桶个数计算方法

​    IndexBuildHeapScan  扫描基表， 将基表元组生成Hash索引元组，并插入Hash表。

​    hashbuildCallback

#### 索引元组插入

函数：_hash_doinsert

大致流程：

先计算待插入桶的桶号，进入待插入桶的第一页，判断是否有足够空间，不够的话，不断向后找，直到找到一个可用的页；如果遍历到最后一个溢出页依然没有发现，则申请一个溢出页，链接到桶的尾部。之后插入元组。修改溢出页（总行数+1）。之后检查是否需要分裂，进行相应的操作。

插入单行时给要插入的页加HASH_SHARE锁。

注意：索引插入可以和索引扫描并发运行。由于索引插入并未改变现有索引行。

#### 溢出页分配

获取一个溢出页


$$
/*

 \*  _hash_getovflpage()

 *

 \*  Find an available overflow page and return it.  The returned buffer

 \*  is pinned and write-locked, and has had _hash_pageinit() applied,

 \*  but it is caller's responsibility to fill the special space.

 *

 \* The caller must hold a pin, but no lock, on the metapage buffer.

 \* That buffer is left in the same state at exit.

 */

static Buffer

_hash_getovflpage(Relation rel, Buffer metabuf)

{

​    HashMetaPage metap;

​    Buffer      mapbuf = 0;

​    Buffer      newbuf;

​    BlockNumber blkno;

​    uint32      orig_firstfree;

​    uint32      splitnum;

​    uint32     *freep = NULL;

​    uint32      max_ovflpg;

​    uint32      bit;

​    uint32      first_page;

​    uint32      last_bit;

​    uint32      last_page;

​    uint32      i,

​                j;



​    /* Get exclusive lock on the meta page */

​    _hash_chgbufaccess(rel, metabuf, HASH_NOLOCK, HASH_WRITE);



​    _hash_checkpage(rel, metabuf, LH_META_PAGE);

​    metap = HashPageGetMeta(BufferGetPage(metabuf));



​    /* start search at hashm_firstfree */

​    orig_firstfree = metap->hashm_firstfree;

​    first_page = orig_firstfree >> BMPG_SHIFT(metap);

​    bit = orig_firstfree & BMPG_MASK(metap);

​    i = first_page;

​    j = bit / BITS_PER_MAP;

​    bit &= ~(BITS_PER_MAP - 1);



​    /* outer loop iterates once per bitmap page */

​    for (;;)

​    {

​        BlockNumber mapblkno;

​        Page        mappage;

​        uint32      last_inpage;



​        /* want to end search with the last existing overflow page */

​        splitnum = metap->hashm_ovflpoint;

​        max_ovflpg = metap->hashm_spares[splitnum] - 1;

​        last_page = max_ovflpg >> BMPG_SHIFT(metap);

​        last_bit = max_ovflpg & BMPG_MASK(metap);



​        if (i > last_page)

​            break;



​        Assert(i < metap->hashm_nmaps);

​        mapblkno = metap->hashm_mapp[i];



​        if (i == last_page)

​            last_inpage = last_bit;

​        else

​            last_inpage = BMPGSZ_BIT(metap) - 1;



​        /* Release exclusive lock on metapage while reading bitmap page */

​        _hash_chgbufaccess(rel, metabuf, HASH_READ, HASH_NOLOCK);



​        mapbuf = _hash_getbuf(rel, mapblkno, HASH_WRITE, LH_BITMAP_PAGE);

​        mappage = BufferGetPage(mapbuf);

​        freep = HashPageGetBitmap(mappage);



​        for (; bit <= last_inpage; j++, bit += BITS_PER_MAP)

​        {

​            if (freep[j] != ALL_SET)

​                goto found;

​        }



​        /* No free space here, try to advance to next map page */

​        _hash_relbuf(rel, mapbuf);

​        i++;

​        j = 0;                  /* scan from start of next map page */

​        bit = 0;



​        /* Reacquire exclusive lock on the meta page */

​        _hash_chgbufaccess(rel, metabuf, HASH_NOLOCK, HASH_WRITE);

​    }



​    /*

​     \* No free pages --- have to extend the relation to add an overflow page.

​     \* First, check to see if we have to add a new bitmap page too.

​     */

​    if (last_bit == (uint32) (BMPGSZ_BIT(metap) - 1))

​    {

​        /*

​         \* We create the new bitmap page with all pages marked "in use".

​         \* Actually two pages in the new bitmap's range will exist

​         \* immediately: the bitmap page itself, and the following page which

​         \* is the one we return to the caller.  Both of these are correctly

​         \* marked "in use".  Subsequent pages do not exist yet, but it is

​         \* convenient to pre-mark them as "in use" too.

​         */

​        bit = metap->hashm_spares[splitnum];

​        _hash_initbitmap(rel, metap, bitno_to_blkno(metap, bit), MAIN_FORKNUM);

​        metap->hashm_spares[splitnum]++;

​    }

​    else

​    {

​        /*

​         \* Nothing to do here; since the page will be past the last used page,

​         \* we know its bitmap bit was preinitialized to "in use".

​         */

​    }



​    /* Calculate address of the new overflow page */

​    bit = metap->hashm_spares[splitnum];

​    blkno = bitno_to_blkno(metap, bit);



​    /*

​     \* Fetch the page with _hash_getnewbuf to ensure smgr's idea of the

​     \* relation length stays in sync with ours.  XXX It's annoying to do this

​     \* with metapage write lock held; would be better to use a lock that

​     \* doesn't block incoming searches.

​     */

​    newbuf = _hash_getnewbuf(rel, blkno, MAIN_FORKNUM);



​    metap->hashm_spares[splitnum]++;



​    /*

​     \* Adjust hashm_firstfree to avoid redundant searches.  But don't risk

​     \* changing it if someone moved it while we were searching bitmap pages.

​     */

​    if (metap->hashm_firstfree == orig_firstfree)

​        metap->hashm_firstfree = bit + 1;



​    /* Write updated metapage and release lock, but not pin */

​    _hash_chgbufaccess(rel, metabuf, HASH_WRITE, HASH_NOLOCK);



​    return newbuf;



found:

​    /* convert bit to bit number within page */

​    bit += _hash_firstfreebit(freep[j]);



​    /* mark page "in use" in the bitmap */

​    SETBIT(freep, bit);

​    _hash_wrtbuf(rel, mapbuf);



​    /* Reacquire exclusive lock on the meta page */

​    _hash_chgbufaccess(rel, metabuf, HASH_NOLOCK, HASH_WRITE);



​    /* convert bit to absolute bit number */

​    bit += (i << BMPG_SHIFT(metap));



​    /* Calculate address of the recycled overflow page */

​    blkno = bitno_to_blkno(metap, bit);



​    /*

​     \* Adjust hashm_firstfree to avoid redundant searches.  But don't risk

​     \* changing it if someone moved it while we were searching bitmap pages.

​     */

​    if (metap->hashm_firstfree == orig_firstfree)

​    {

​        metap->hashm_firstfree = bit + 1;



​        /* Write updated metapage and release lock, but not pin */

​        _hash_chgbufaccess(rel, metabuf, HASH_WRITE, HASH_NOLOCK);

​    }

​    else

​    {

​        /* We didn't change the metapage, so no need to write */

​        _hash_chgbufaccess(rel, metabuf, HASH_READ, HASH_NOLOCK);

​    }



​    /* Fetch, init, and return the recycled page */

​    return _hash_getinitbuf(rel, blkno);

}
$$

#### 添加一个溢出页

获取一个溢出页，找到当前桶最后一页，将获取的溢出页链接到桶后。

调用函数_hash_getovflpage()
$$
/*

 \*  _hash_addovflpage

 *

 \*  Add an overflow page to the bucket whose last page is pointed to by 'buf'.

 *

 \*  On entry, the caller must hold a pin but no lock on 'buf'.  The pin is

 \*  dropped before exiting (we assume the caller is not interested in 'buf'

 \*  anymore).  The returned overflow page will be pinned and write-locked;

 \*  it is guaranteed to be empty.

 *

 \*  The caller must hold a pin, but no lock, on the metapage buffer.

 \*  That buffer is returned in the same state.

 *

 \*  The caller must hold at least share lock on the bucket, to ensure that

 \*  no one else tries to compact the bucket meanwhile.  This guarantees that

 \*  'buf' won't stop being part of the bucket while it's unlocked.

 *

 \* NB: since this could be executed concurrently by multiple processes,

 \* one should not assume that the returned overflow page will be the

 \* immediate successor of the originally passed 'buf'.  Additional overflow

 \* pages might have been added to the bucket chain in between.

 \* 将溢出页面添加到存储桶，其最后一页由“ buf”指向。进入时，呼叫者必须按住别针，但不能锁定“ buf”。 别针是

退出前掉线（我们假设呼叫者对“ buf”不感兴趣不再）。 返回的溢出页将被固定并被写锁定；保证为空。

调用者必须在元页缓冲区上保留一个别针，但不要锁定。该缓冲区以相同状态返回。

呼叫者必须至少在存储桶上保持共享锁，以确保没有其他人试图同时压缩存储桶。 

这保证了“ buf”在解锁时不会停止成为存储桶的一部分。

 注意：由于可以由多个进程同时执行，一个人不应该假定返回的溢出页面将是最初通过的“ buf”的直接后继者。 

 两者之间可能已将其他溢出页面添加到存储桶链中。

 */

Buffer

_hash_addovflpage(Relation rel, Buffer metabuf, Buffer buf)

{

​    Buffer      ovflbuf;

​    Page        page;

​    Page        ovflpage;

​    HashPageOpaque pageopaque;

​    HashPageOpaque ovflopaque;



​    /* allocate and lock an empty overflow page */

​    ovflbuf = _hash_getovflpage(rel, metabuf);



​    /*

​     \* Write-lock the tail page.  It is okay to hold two buffer locks here

​     \* since there cannot be anyone else contending for access to ovflbuf.

​     */

​    _hash_chgbufaccess(rel, buf, HASH_NOLOCK, HASH_WRITE);



​    /* probably redundant... */

​    _hash_checkpage(rel, buf, LH_BUCKET_PAGE | LH_OVERFLOW_PAGE);



​    /* loop to find current tail page, in case someone else inserted too */

​    for (;;)

​    {

​        BlockNumber nextblkno;



​        page = BufferGetPage(buf);

​        pageopaque = (HashPageOpaque) PageGetSpecialPointer(page);

​        nextblkno = pageopaque->hasho_nextblkno;



​        if (!BlockNumberIsValid(nextblkno))

​            break;



​        /* we assume we do not need to write the unmodified page */

​        _hash_relbuf(rel, buf);



​        buf = _hash_getbuf(rel, nextblkno, HASH_WRITE, LH_OVERFLOW_PAGE);

​    }



​    /* now that we have correct backlink, initialize new overflow page */

​    ovflpage = BufferGetPage(ovflbuf);

​    ovflopaque = (HashPageOpaque) PageGetSpecialPointer(ovflpage);

​    ovflopaque->hasho_prevblkno = BufferGetBlockNumber(buf);

​    ovflopaque->hasho_nextblkno = InvalidBlockNumber;

​    ovflopaque->hasho_bucket = pageopaque->hasho_bucket;

​    ovflopaque->hasho_flag = LH_OVERFLOW_PAGE;

​    ovflopaque->hasho_page_id = HASHO_PAGE_ID;



​    MarkBufferDirty(ovflbuf);



​    /* logically chain overflow page to previous page */

​    pageopaque->hasho_nextblkno = BufferGetBlockNumber(ovflbuf);

​    _hash_wrtbuf(rel, buf);



​    return ovflbuf;

}
$$




#### 溢出页回收

回收要求：持有所在桶排他锁。

回收主要功能：

断开桶链（断开前后指针，增加双向指针），释放溢出页，标记为可用。



$$
/*

 \*  _hash_freeovflpage() -

 *

 \*  Remove this overflow page from its bucket's chain, and mark the page as

 \*  free.  On entry, ovflbuf is write-locked; it is released before exiting.

 *

 \*  Since this function is invoked in VACUUM, we provide an access strategy

 \*  parameter that controls fetches of the bucket pages.

 *

 \*  Returns the block number of the page that followed the given page

 \*  in the bucket, or InvalidBlockNumber if no following page.

 *

 \*  NB: caller must not hold lock on metapage, nor on either page that's

 \*  adjacent in the bucket chain.  The caller had better hold exclusive lock

 \*  on the bucket, too.

 从存储桶链中删除该溢出页面，并将该页面标记为空闲。 进入时，ovflbuf被写锁定。 在退出之前将其释放。

由于此功能是在VACUUM中调用的，因此我们提供了一个访问策略参数，用于控制存储区页面的提取。

返回存储桶中给定页面之后的页面的块号，如果没有后续页面，则返回InvalidBlockNumber。

注意：呼叫者不得在元页面上或任何一个页面上保持锁定在桶链中相邻。 

调用者最好也将专用锁定保持在存储桶上。

 */

BlockNumber

_hash_freeovflpage(Relation rel, Buffer ovflbuf,

​                   BufferAccessStrategy bstrategy)

{

​    HashMetaPage metap;

​    Buffer      metabuf;

​    Buffer      mapbuf;

​    BlockNumber ovflblkno;

​    BlockNumber prevblkno;

​    BlockNumber blkno;

​    BlockNumber nextblkno;

​    HashPageOpaque ovflopaque;

​    Page        ovflpage;

​    Page        mappage;

​    uint32     *freep;

​    uint32      ovflbitno;

​    int32       bitmappage,

​                bitmapbit;

​    Bucket bucket PG_USED_FOR_ASSERTS_ONLY;



​    /* Get information from the doomed page */

​    _hash_checkpage(rel, ovflbuf, LH_OVERFLOW_PAGE);

​    ovflblkno = BufferGetBlockNumber(ovflbuf);

​    ovflpage = BufferGetPage(ovflbuf);

​    ovflopaque = (HashPageOpaque) PageGetSpecialPointer(ovflpage);

​    nextblkno = ovflopaque->hasho_nextblkno;

​    prevblkno = ovflopaque->hasho_prevblkno;

​    bucket = ovflopaque->hasho_bucket;



​    /*

​     \* Zero the page for debugging's sake; then write and release it. (Note:

​     \* if we failed to zero the page here, we'd have problems with the Assert

​     \* in _hash_pageinit() when the page is reused.)

​     */

​    //标记溢出页为空闲

​    MemSet(ovflpage, 0, BufferGetPageSize(ovflbuf));

​    _hash_wrtbuf(rel, ovflbuf);



​    /*

​     \* Fix up the bucket chain.  this is a doubly-linked list, so we must fix

​     \* up the bucket chain members behind and ahead of the overflow page being

​     \* deleted.  No concurrency issues since we hold exclusive lock on the

​     \* entire bucket.

​     */

​    //修改前向指针指向

​    if (BlockNumberIsValid(prevblkno))

​    {

​        Buffer      prevbuf = _hash_getbuf_with_strategy(rel,

​                                                         prevblkno,

​                                                         HASH_WRITE,

​                                           LH_BUCKET_PAGE | LH_OVERFLOW_PAGE,

​                                                         bstrategy);

​        Page        prevpage = BufferGetPage(prevbuf);

​        HashPageOpaque prevopaque = (HashPageOpaque) PageGetSpecialPointer(prevpage);



​        Assert(prevopaque->hasho_bucket == bucket);

​        prevopaque->hasho_nextblkno = nextblkno;

​        _hash_wrtbuf(rel, prevbuf);

​    }

​    //修改后向指针指向

​    if (BlockNumberIsValid(nextblkno))

​    {

​        Buffer      nextbuf = _hash_getbuf_with_strategy(rel,

​                                                         nextblkno,

​                                                         HASH_WRITE,

​                                                         LH_OVERFLOW_PAGE,

​                                                         bstrategy);

​        Page        nextpage = BufferGetPage(nextbuf);

​        HashPageOpaque nextopaque = (HashPageOpaque) PageGetSpecialPointer(nextpage);



​        Assert(nextopaque->hasho_bucket == bucket);

​        nextopaque->hasho_prevblkno = prevblkno;

​        _hash_wrtbuf(rel, nextbuf);

​    }



​    /* Note: bstrategy is intentionally not used for metapage and bitmap */



​    /* Read the metapage so we can determine which bitmap page to use */

​    metabuf = _hash_getbuf(rel, HASH_METAPAGE, HASH_READ, LH_META_PAGE);

​    metap = HashPageGetMeta(BufferGetPage(metabuf));



​    /* Identify which bit to set */

​    ovflbitno = blkno_to_bitno(metap, ovflblkno);



​    bitmappage = ovflbitno >> BMPG_SHIFT(metap);

​    bitmapbit = ovflbitno & BMPG_MASK(metap);



​    if (bitmappage >= metap->hashm_nmaps)

​        elog(ERROR, "invalid overflow bit number %u", ovflbitno);

​    blkno = metap->hashm_mapp[bitmappage];



​    /* Release metapage lock while we access the bitmap page */

​    _hash_chgbufaccess(rel, metabuf, HASH_READ, HASH_NOLOCK);



​    /* Clear the bitmap bit to indicate that this overflow page is free */

​    mapbuf = _hash_getbuf(rel, blkno, HASH_WRITE, LH_BITMAP_PAGE);

​    mappage = BufferGetPage(mapbuf);

​    freep = HashPageGetBitmap(mappage);

​    Assert(ISSET(freep, bitmapbit));

​    CLRBIT(freep, bitmapbit);

​    _hash_wrtbuf(rel, mapbuf);



​    /* Get write-lock on metapage to update firstfree */

​    _hash_chgbufaccess(rel, metabuf, HASH_NOLOCK, HASH_WRITE);



​    /* if this is now the first free page, update hashm_firstfree */

​    if (ovflbitno < metap->hashm_firstfree)

​    {

​        metap->hashm_firstfree = ovflbitno;

​        _hash_wrtbuf(rel, metabuf);


​    }

​    else

​    {

​        /* no need to change metapage */

​        _hash_relbuf(rel, metabuf);

​    }



​    return nextblkno;

}
$$



### 索引分裂

#### 基本原理：

锁：调用者必须在两个存储桶上都持有排他锁，以确保没有其他人试图访问它们（请参阅自述文件）。

将旧的桶中的部分元组一行一行插入到新的桶中。

然后原桶进行压缩。


$$
/*

 \* _hash_splitbucket -- split 'obucket' into 'obucket' and 'nbucket'

 *

 \* We are splitting a bucket that consists of a base bucket page and zero

 \* or more overflow (bucket chain) pages.  We must relocate tuples that

 \* belong in the new bucket, and compress out any free space in the old

 \* bucket.

 *

 \* The caller must hold exclusive locks on both buckets to ensure that

 \* no one else is trying to access them (see README).

 *

 \* The caller must hold a pin, but no lock, on the metapage buffer.

 \* The buffer is returned in the same state.  (The metapage is only

 \* touched if it becomes necessary to add or remove overflow pages.)

 *

 \* In addition, the caller must have created the new bucket's base page,

 \* which is passed in buffer nbuf, pinned and write-locked.  That lock and

 \* pin are released here.  (The API is set up this way because we must do

 \* _hash_getnewbuf() before releasing the metapage write lock.  So instead of

 \* passing the new bucket's start block number, we pass an actual buffer.)

 我们正在拆分一个由基本存储桶页面和零个或多个溢出（存储桶链）页面组成的存储桶。

 我们必须重新定位属于新存储桶的元组，并压缩掉旧存储桶中的任何可用空间。

调用者必须在两个存储桶上都持有排他锁，以确保没有其他人试图访问它们（请参阅自述文件）。

调用者必须在元页缓冲区上保留一个别针，但不要锁定。

缓冲区以相同状态返回。（仅在有必要添加或删除溢出页面时才创建元页面。）

此外，调用者必须已经创建了新存储桶的基础页面，

它在缓冲区nbuf中传递，固定并写锁定。 那个锁和别针在这里被释放。 （以这种方式设置API，

因为我们必须在释放元页写锁之前执行_hash_getnewbuf（）。

因此，我们传递了一个实际的缓冲区，而不是传递新存储区的起始块号。）

 */

static void

_hash_splitbucket(Relation rel,

​                  Buffer metabuf,

​                  Bucket obucket,

​                  Bucket nbucket,

​                  BlockNumber start_oblkno,

​                  Buffer nbuf,

​                  uint32 maxbucket,

​                  uint32 highmask,

​                  uint32 lowmask)

{

​    Buffer      obuf;

​    Page        opage;

​    Page        npage;

​    HashPageOpaque oopaque;

​    HashPageOpaque nopaque;



​    /*

​     \* It should be okay to simultaneously write-lock pages from each bucket,

​     \* since no one else can be trying to acquire buffer lock on pages of

​     \* either bucket.

​     */

​    obuf = _hash_getbuf(rel, start_oblkno, HASH_WRITE, LH_BUCKET_PAGE);

​    opage = BufferGetPage(obuf);

​    oopaque = (HashPageOpaque) PageGetSpecialPointer(opage);



​    npage = BufferGetPage(nbuf);



​    /* initialize the new bucket's primary page */

​    nopaque = (HashPageOpaque) PageGetSpecialPointer(npage);

​    nopaque->hasho_prevblkno = InvalidBlockNumber;

​    nopaque->hasho_nextblkno = InvalidBlockNumber;

​    nopaque->hasho_bucket = nbucket;

​    nopaque->hasho_flag = LH_BUCKET_PAGE;

​    nopaque->hasho_page_id = HASHO_PAGE_ID;



​    /*

​     \* Partition the tuples in the old bucket between the old bucket and the

​     \* new bucket, advancing along the old bucket's overflow bucket chain and

​     \* adding overflow pages to the new bucket as needed.  Outer loop iterates

​     \* once per page in old bucket.

​     \* 在旧存储桶和新存储桶之间将旧存储桶中的元组划分，沿着旧存储桶的溢出存储桶链前进，

​     \* 并根据需要向新存储桶添加溢出页面。 外循环在旧存储桶中每页迭代一次。

​     */

​    for (;;)

​    {

​        BlockNumber oblkno;

​        OffsetNumber ooffnum;

​        OffsetNumber omaxoffnum;

​        OffsetNumber deletable[MaxOffsetNumber];

​        int         ndeletable = 0;



​        /* Scan each tuple in old page 扫描老的页中的元组*/

​        omaxoffnum = PageGetMaxOffsetNumber(opage);

​        for (ooffnum = FirstOffsetNumber;

​             ooffnum <= omaxoffnum;

​             ooffnum = OffsetNumberNext(ooffnum))

​        {

​            IndexTuple  itup;

​            Size        itemsz;

​            Bucket      bucket;



​            /*

​             \* Fetch the item's hash key (conveniently stored in the item) and

​             \* determine which bucket it now belongs in.

​             \* 获取项的哈希键（方便地存储在项中），然后确定它现在属于哪个存储桶。

​             */

​            itup = (IndexTuple) PageGetItem(opage,

​                                            PageGetItemId(opage, ooffnum));

​            bucket = _hash_hashkey2bucket(_hash_get_indextuple_hashkey(itup),

​                                          maxbucket, highmask, lowmask);



​            if (bucket == nbucket)

​            {

​                /*

​                 \* insert the tuple into the new bucket.  if it doesn't fit on

​                 \* the current page in the new bucket, we must allocate a new

​                 \* overflow page and place the tuple on that page instead.

​                 *

​                 \* XXX we have a problem here if we fail to get space for a

​                 \* new overflow page: we'll error out leaving the bucket split

​                 \* only partially complete, meaning the index is corrupt,

​                 \* since searches may fail to find entries they should find.

​                 \* 将元组插入新的存储桶。 如果它不适合新存储桶中的当前页面，则必须分配一个新的溢出页面，

​                 \* 然后将元组放置在该页面上。如果我们无法为新的溢出页面获取空间，我们会在这里遇到问题：

​                 \* XXX我们会出错，导致存储桶拆分仅部分完成，这意味着索引已损坏，因为搜索可能找不到他们应该找到的条目。

​                 */

​                itemsz = IndexTupleDSize(*itup);

​                itemsz = MAXALIGN(itemsz);



​                if (PageGetFreeSpace(npage) < itemsz)

​                {

​                    /* write out nbuf and drop lock, but keep pin */

​                    _hash_chgbufaccess(rel, nbuf, HASH_WRITE, HASH_NOLOCK);

​                    /* chain to a new overflow page */

​                    nbuf = _hash_addovflpage(rel, metabuf, nbuf);

​                    npage = BufferGetPage(nbuf);

​                    /* we don't need nopaque within the loop */

​                }



​                /*

​                 \* Insert tuple on new page, using _hash_pgaddtup to ensure

​                 \* correct ordering by hashkey.  This is a tad inefficient

​                 \* since we may have to shuffle itempointers repeatedly.

​                 \* Possible future improvement: accumulate all the items for

​                 \* the new page and qsort them before insertion.

​                 \* 使用_hash_pgaddtup在新页面上插入元组，以确保按哈希键正确排序。 

​                 \* 这有点低效，因为我们可能不得不反复洗改项目指针。

​                 \* 未来可能的改进：累积新页面的所有项目，并在插入之前对它们进行qsort。

​                 */

​                (void) _hash_pgaddtup(rel, nbuf, itemsz, itup);



​                /*

​                 \* Mark tuple for deletion from old page.

​                 */

​                deletable[ndeletable++] = ooffnum;

​            }

​            else

​            {

​                /*

​                 \* the tuple stays on this page, so nothing to do.

​                 */

​                Assert(bucket == obucket);


















          }

​        }



​        oblkno = oopaque->hasho_nextblkno;



​        /*

​         \* Done scanning this old page.  If we moved any tuples, delete them

​         \* from the old page.

​         \* 完成扫描此旧页面。 如果我们移动了任何元组，请从旧页面开始删除它们。

​         */

​        if (ndeletable > 0)

​        {

​            PageIndexMultiDelete(opage, deletable, ndeletable);

​            _hash_wrtbuf(rel, obuf);

​        }

​        else

​            _hash_relbuf(rel, obuf);



​        /* Exit loop if no more overflow pages in old bucket */

​        if (!BlockNumberIsValid(oblkno))

​            break;



​        /* Else, advance to next old page */

​        obuf = _hash_getbuf(rel, oblkno, HASH_WRITE, LH_OVERFLOW_PAGE);

​        opage = BufferGetPage(obuf);

​        oopaque = (HashPageOpaque) PageGetSpecialPointer(opage);

​    }



​    /*

​     \* We're at the end of the old bucket chain, so we're done partitioning

​     \* the tuples.  Before quitting, call _hash_squeezebucket to ensure the

+

































* tuples remaining in the old bucket (including the overflow pages) are

​     \* packed as tightly as possible.  The new bucket is already tight.

​     \* 我们已经到了旧桶链的末端，因此我们完成了分区元组。 退出之前，请调用_hash_squeezebucket

​     \* 以确保保留在旧存储桶中的元组（包括溢出页面）是尽可能紧密地包装。 新的存储桶已经很紧。

​     */

​    _hash_wrtbuf(rel, nbuf);



​    _hash_squeezebucket(rel, obucket, start_oblkno, NULL);

}
$$


#### 索引压缩(vacuum时会调用)

基本原理：

将桶链后部页面的元组迁移到桶链前部页面中去，
– 从后面开始读（删除），从前面开始写（插入）。

定义两个指针wpage、rpage分别指向双链表的首尾，rpage将其上的元组插入到wpage指向的页，同时记录rpage上插入的行，后续进行删除。rpage指向页如果没有有效行，释放该溢出页。并将rpage指针前移；wpage在插入时会从头开始遍历寻找空闲大小足够的数据块，直到wpage和rpage指针相遇。






$$
/*

 \*  _hash_squeezebucket(rel, bucket)

 *

 \*  Try to squeeze the tuples onto pages occurring earlier in the

 \*  bucket chain in an attempt to free overflow pages. When we start

 \*  the "squeezing", the page from which we start taking tuples (the

 \*  "read" page) is the last bucket in the bucket chain and the page

 \*  onto which we start squeezing tuples (the "write" page) is the

 \*  first page in the bucket chain.  The read page works backward and

 \*  the write page works forward; the procedure terminates when the

 \*  read page and write page are the same page.

 *

 \*  At completion of this procedure, it is guaranteed that all pages in

 \*  the bucket are nonempty, unless the bucket is totally empty (in

 \*  which case all overflow pages will be freed).  The original implementation

 \*  required that to be true on entry as well, but it's a lot easier for

 \*  callers to leave empty overflow pages and let this guy clean it up.

 *

 \*  Caller must hold exclusive lock on the target bucket.  This allows

 \*  us to safely lock multiple pages in the bucket.

 *

 \*  Since this function is invoked in VACUUM, we provide an access strategy

 \*  parameter that controls fetches of the bucket pages.

 尝试将元组压缩到存储桶链中较早出现的页面上，以释放溢出的页面。当我们开始“挤压”时，

 我们从中开始读取元组的页面（“读取”页面）是存储桶链中的最后一个存储桶，

 而我们开始挤压元组的页面（“写入”页面）是第一行。桶链中的页面。读页面向后工作，写页面向前工作；

 当读取页面和写入页面为同一页面时，该过程终止。

完成此过程后，可以确保存储桶中的所有页面都是非空的，除非存储桶完全为空（在这种情况下，

所有溢出页面都将被释放）。原始实现要求在输入时也必须做到这一点，但对于调用者而言，

留下空白的溢出页面并让vacuum清理它要容易得多。

调用者必须在目标存储桶上拥有排他锁。这使我们可以安全地将多个页面锁定在存储桶中。

由于此功能是在VACUUM中调用的，因此我们提供了一个访问策略参数，用于控制存储区页面的提取。

 */

void

_hash_squeezebucket(Relation rel,

​                    Bucket bucket,

​                    BlockNumber bucket_blkno,

​                    BufferAccessStrategy bstrategy)

{

​    BlockNumber wblkno;

​    BlockNumber rblkno;

​    Buffer      wbuf;

​    Buffer      rbuf;

​    Page        wpage;

​    Page        rpage;

​    HashPageOpaque wopaque;

​    HashPageOpaque ropaque;

​    bool        wbuf_dirty;



​    /*

​     \* start squeezing into the base bucket page.

​     */

​    wblkno = bucket_blkno;

​    wbuf = _hash_getbuf_with_strategy(rel,

​                                      wblkno,

​                                      HASH_WRITE,

​                                      LH_BUCKET_PAGE,

​                                      bstrategy);

​    wpage = BufferGetPage(wbuf);

​    wopaque = (HashPageOpaque) PageGetSpecialPointer(wpage);



​    /*

​     \* if there aren't any overflow pages, there's nothing to squeeze.

​     */

​    if (!BlockNumberIsValid(wopaque->hasho_nextblkno))

​    {

​        _hash_relbuf(rel, wbuf);

​        return;

​    }



​    /*

​     \* Find the last page in the bucket chain by starting at the base bucket

​     \* page and working forward.  Note: we assume that a hash bucket chain is

​     \* usually smaller than the buffer ring being used by VACUUM, else using

​     \* the access strategy here would be counterproductive.

​     \* 从基本存储桶开始查找存储桶链中的最后一页页面并继续前进。 

​     \* 注意：我们假设哈希桶链通常小于VACUUM使用的缓冲环，否则在这里使用访问策略将适得其反。

​     */

​    rbuf = InvalidBuffer;

​    ropaque = wopaque;

​    do

​    {

​        rblkno = ropaque->hasho_nextblkno;

​        if (rbuf != InvalidBuffer)

​            _hash_relbuf(rel, rbuf);

​        rbuf = _hash_getbuf_with_strategy(rel,

​                                          rblkno,

​                                          HASH_WRITE,

​                                          LH_OVERFLOW_PAGE,

​                                          bstrategy);

​        rpage = BufferGetPage(rbuf);

​        ropaque = (HashPageOpaque) PageGetSpecialPointer(rpage);

​        Assert(ropaque->hasho_bucket == bucket);

​    } while (BlockNumberIsValid(ropaque->hasho_nextblkno));



​    /*

​     \* squeeze the tuples.

​     */

​    wbuf_dirty = false;

​    for (;;)

​    {

​        OffsetNumber roffnum;

​        OffsetNumber maxroffnum;

​        OffsetNumber deletable[MaxOffsetNumber];

​        int         ndeletable = 0;



​        /* Scan each tuple in "read" page */

​        maxroffnum = PageGetMaxOffsetNumber(rpage);

​        for (roffnum = FirstOffsetNumber;

​             roffnum <= maxroffnum;

​             roffnum = OffsetNumberNext(roffnum))

​        {

​            IndexTuple  itup;

​            Size        itemsz;



​            itup = (IndexTuple) PageGetItem(rpage,

​                                            PageGetItemId(rpage, roffnum));

​            itemsz = IndexTupleDSize(*itup);

​            itemsz = MAXALIGN(itemsz);



​            /*

​             \* Walk up the bucket chain, looking for a page big enough for

​             \* this item.  Exit if we reach the read page.

​             */

​            while (PageGetFreeSpace(wpage) < itemsz)

​            {

​                Assert(!PageIsEmpty(wpage));



​                wblkno = wopaque->hasho_nextblkno;

​                Assert(BlockNumberIsValid(wblkno));



​                if (wbuf_dirty)

​                    _hash_wrtbuf(rel, wbuf);

​                else

​                    _hash_relbuf(rel, wbuf);



​                /* nothing more to do if we reached the read page */

​                if (rblkno == wblkno)

​                {

​                    if (ndeletable > 0)

​                    {

​                        /* Delete tuples we already moved off read page */

​                        PageIndexMultiDelete(rpage, deletable, ndeletable);

​                        _hash_wrtbuf(rel, rbuf);

​                    }

​                    else

​                        _hash_relbuf(rel, rbuf);

​                    return;

​                }



​                wbuf = _hash_getbuf_with_strategy(rel,

​                                                  wblkno,

​                                                  HASH_WRITE,

​                                                  LH_OVERFLOW_PAGE,

​                                                  bstrategy);

​                wpage = BufferGetPage(wbuf);

​                wopaque = (HashPageOpaque) PageGetSpecialPointer(wpage);

​                Assert(wopaque->hasho_bucket == bucket);

​                wbuf_dirty = false;

​            }



​            /*

​             \* we have found room so insert on the "write" page, being careful

​             \* to preserve hashkey ordering.  (If we insert many tuples into

​             \* the same "write" page it would be worth qsort'ing instead of

​             \* doing repeated _hash_pgaddtup.)

​             \* 插入行到wpage

​             */

​            (void) _hash_pgaddtup(rel, wbuf, itemsz, itup);

​            wbuf_dirty = true;



​            /* remember tuple for deletion from "read" page 标记要删除的行*/

​            deletable[ndeletable++] = roffnum;

​        }



​        /*

​         \* If we reach here, there are no live tuples on the "read" page ---

​         \* it was empty when we got to it, or we moved them all.  So we can

​         \* just free the page without bothering with deleting tuples

​         \* individually.  Then advance to the previous "read" page.

​         *

​         \* Tricky point here: if our read and write pages are adjacent in the

​         \* bucket chain, our write lock on wbuf will conflict with

​         \* _hash_freeovflpage's attempt to update the sibling links of the

​         \* removed page.  However, in that case we are done anyway, so we can

​         \* simply drop the write lock before calling _hash_freeovflpage.

​         \* 如果我们到达这里，则“读”页面上没有活动的元组-当我们到达那里时它是空的，

​         \* 或者我们全部搬走了。 因此，我们可以释放页面，而不必担心单独删除元组。 

​         \* 然后进入上一个“读”页面。

​         \* 这里的棘手点：如果我们的读取和写入页面在存储桶链中相邻，

​         \* 则我们在wbuf上的写入锁定将与_hash_freeovflpage尝试更新已删除页面的同级链接的冲突。 

​         \* 但是，在那种情况下我们还是要完成的，所以我们只需在调用_hash_freeovflpage之前放下

​         \* 写锁即可。

​         */

​        rblkno = ropaque->hasho_prevblkno;

​        Assert(BlockNumberIsValid(rblkno));



​        /* are we freeing the page adjacent to wbuf? */

​        if (rblkno == wblkno)

​        {

​            /* yes, so release wbuf lock first */

​            if (wbuf_dirty)

​                _hash_wrtbuf(rel, wbuf);

​            else

​                _hash_relbuf(rel, wbuf);

​            /* free this overflow page (releases rbuf) */

​            _hash_freeovflpage(rel, rbuf, bstrategy);

​            /* done */

​            return;

​        }



​        /* free this overflow page, then get the previous one */

​        _hash_freeovflpage(rel, rbuf, bstrategy);



​        rbuf = _hash_getbuf_with_strategy(rel,

​                                          rblkno,

​                                          HASH_WRITE,

​                                          LH_OVERFLOW_PAGE,

​                                          bstrategy);

​        rpage = BufferGetPage(rbuf);

​        ropaque = (HashPageOpaque) PageGetSpecialPointer(rpage);

​        Assert(ropaque->hasho_bucket == bucket);

​    }



​    /* NOTREACHED */

}
$$







pageinspect查看bitmap索引信息





