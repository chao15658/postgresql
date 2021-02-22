# HASH索引的构建过程

```
/*
 \*  hashbuild() -- build a new hash index.
 */
IndexBuildResult *
hashbuild(Relation heap, Relation index, IndexInfo *indexInfo)
{
​    IndexBuildResult *result;
​    BlockNumber relpages;
​    double      reltuples;
​    double      allvisfrac;
​    uint32      num_buckets;
​    long        sort_threshold;
​    HashBuildState buildstate;
​    /*
​     \* We expect to be called exactly once for any index relation. If that's
​     \* not the case, big trouble's what we have.
​     */
​    if (RelationGetNumberOfBlocks(index) != 0)
​        elog(ERROR, "index \"%s\" already contains data",
​             RelationGetRelationName(index));
​    /* Estimate the number of rows currently present in the table 
估计表当前行数
*/
​    estimate_rel_size(heap, NULL, &relpages, &reltuples, &allvisfrac);
​    /* Initialize the hash index metadata page and initial buckets
初始化hash索引元页和初始化桶
*/
​    num_buckets = _hash_metapinit(index, reltuples, MAIN_FORKNUM);
​    /*
​     \* If we just insert the tuples into the index in scan order, then
​     \* (assuming their hash codes are pretty random) there will be no locality
​     \* of access to the index, and if the index is bigger than available RAM
​     \* then we'll thrash horribly.  To prevent that scenario, we can sort the
​     \* tuples by (expected) bucket number.  However, such a sort is useless
​     \* overhead when the index does fit in RAM.  We choose to sort if the
​     \* initial index size exceeds maintenance_work_mem, or the number of
​     \* buffers usable for the index, whichever is less.  (Limiting by the
​     \* number of buffers should reduce thrashing between PG buffers and kernel
​     \* buffers, which seems useful even if no physical I/O results.  Limiting
​     \* by maintenance_work_mem is useful to allow easy testing of the sort
​     \* code path, and may be useful to DBAs as an additional control knob.)
​     *
​     \* NOTE: this test will need adjustment if a bucket is ever different from
​     \* one page.  Also, "initial index size" accounting does not include the
​     \* metapage, nor the first bitmap page.
​     */
​    sort_threshold = (maintenance_work_mem * 1024L) / BLCKSZ;
​    if (index->rd_rel->relpersistence != RELPERSISTENCE_TEMP)
​        sort_threshold = Min(sort_threshold, NBuffers);
​    else
​        sort_threshold = Min(sort_threshold, NLocBuffer);
​    if (num_buckets >= (uint32) sort_threshold)
​        buildstate.spool = _h_spoolinit(heap, index, num_buckets);
​    else
​        buildstate.spool = NULL;
​    /* prepare to build the index */
​    buildstate.indtuples = 0;
​    /* do the heap scan */
​    reltuples = IndexBuildHeapScan(heap, index, indexInfo, true,
​                                   hashbuildCallback, (void *) &buildstate);
​    if (buildstate.spool)
​    {
​        /* sort the tuples and insert them into the index */
​        _h_indexbuild(buildstate.spool);
​        _h_spooldestroy(buildstate.spool);
​    }
​    /*
​     \* Return statistics
​     */
​    result = (IndexBuildResult *) palloc(sizeof(IndexBuildResult));
​    result->heap_tuples = reltuples;
​    result->index_tuples = buildstate.indtuples;
​    return result;
}
```





估计表或索引的页数和行数

```
/*
 \* estimate_rel_size - estimate # pages and # tuples in a table or index
 \* We also estimate the fraction of the pages that are marked all-visible in
 \* the visibility map, for use in estimation of index-only scans.
 \* If attr_widths isn't NULL, it points to the zero-index entry of the
 \* relation's attr_widths[] cache; we fill this in if we have need to compute
 \* the attribute widths for estimation purposes.
 */
void
estimate_rel_size(Relation rel, int32 *attr_widths,
​                  BlockNumber *pages, double *tuples, double *allvisfrac)
{
​    BlockNumber curpages;
​    BlockNumber relpages;
​    double      reltuples;
​    BlockNumber relallvisible;
​    double      density;
​    switch (rel->rd_rel->relkind)
​    {
​        case RELKIND_RELATION:
​        case RELKIND_INDEX:
​        case RELKIND_MATVIEW:
​        case RELKIND_TOASTVALUE:
​            /* it has storage, ok to call the smgr */
​            curpages = RelationGetNumberOfBlocks(rel);
​            /*
​             \* HACK: if the relation has never yet been vacuumed, use a
​             \* minimum size estimate of 10 pages.  The idea here is to avoid
​             \* assuming a newly-created table is really small, even if it
​             \* currently is, because that may not be true once some data gets
​             \* loaded into it.  Once a vacuum or analyze cycle has been done
​             \* on it, it's more reasonable to believe the size is somewhat
​             \* stable.
​             *
​             \* (Note that this is only an issue if the plan gets cached and
​             \* used again after the table has been filled.  What we're trying
​             \* to avoid is using a nestloop-type plan on a table that has
​             \* grown substantially since the plan was made.  Normally,
​             \* autovacuum/autoanalyze will occur once enough inserts have
​             \* happened and cause cached-plan invalidation; but that doesn't
​             \* happen instantaneously, and it won't happen at all for cases
​             \* such as temporary tables.)
​             *
​             \* We approximate "never vacuumed" by "has relpages = 0", which
​             \* means this will also fire on genuinely empty relations.  Not
​             \* great, but fortunately that's a seldom-seen case in the real
​             \* world, and it shouldn't degrade the quality of the plan too
​             \* much anyway to err in this direction.
​             *
​             \* There are two exceptions wherein we don't apply this heuristic.
​             \* One is if the table has inheritance children.  Totally empty
​             \* parent tables are quite common, so we should be willing to
​             \* believe that they are empty.  Also, we don't apply the 10-page
​             \* minimum to indexes.
​             */
​            if (curpages < 10 &&
​                rel->rd_rel->relpages == 0 &&
​                !rel->rd_rel->relhassubclass &&
​                rel->rd_rel->relkind != RELKIND_INDEX)
​                curpages = 10;
​            /* report estimated # pages */
​            *pages = curpages;
​            /* quick exit if rel is clearly empty */
​            if (curpages == 0)
​            {
​                *tuples = 0;
​                *allvisfrac = 0;
​                break;
​            }
​            /* coerce values in pg_class to more desirable types */
​            relpages = (BlockNumber) rel->rd_rel->relpages;
​            reltuples = (double) rel->rd_rel->reltuples;
​            relallvisible = (BlockNumber) rel->rd_rel->relallvisible;
​            /*
​             \* If it's an index, discount the metapage while estimating the
​             \* number of tuples.  This is a kluge because it assumes more than
​             \* it ought to about index structure.  Currently it's OK for
​             \* btree, hash, and GIN indexes but suspect for GiST indexes.
​             */
​            if (rel->rd_rel->relkind == RELKIND_INDEX &&
​                relpages > 0)
​            {
​                curpages--;
​                relpages--;
​            }
​            /* estimate number of tuples from previous tuple density */
​            if (relpages > 0)
​                density = reltuples / (double) relpages;
​            else
​            {
​                /*
​                 \* When we have no data because the relation was truncated,
​                 \* estimate tuple width from attribute datatypes.  We assume
​                 \* here that the pages are completely full, which is OK for
​                 \* tables (since they've presumably not been VACUUMed yet) but
​                 \* is probably an overestimate for indexes.  Fortunately
​                 \* get_relation_info() can clamp the overestimate to the
​                 \* parent table's size.
​                 *
​                 \* Note: this code intentionally disregards alignment
​                 \* considerations, because (a) that would be gilding the lily
​                 \* considering how crude the estimate is, and (b) it creates
​                 \* platform dependencies in the default plans which are kind
​                 \* of a headache for regression testing.
​                 */
​                int32       tuple_width;
​                tuple_width = get_rel_data_width(rel, attr_widths);
​                tuple_width += MAXALIGN(SizeofHeapTupleHeader);
​                tuple_width += sizeof(ItemIdData);
​                /* note: integer division is intentional here */
​                density = (BLCKSZ - SizeOfPageHeaderData) / tuple_width;
​            }
​            *tuples = rint(density * (double) curpages);
​            /*
​             \* We use relallvisible as-is, rather than scaling it up like we
​             \* do for the pages and tuples counts, on the theory that any
​             \* pages added since the last VACUUM are most likely not marked
​             \* all-visible.  But costsize.c wants it converted to a fraction.
​             */
​            if (relallvisible == 0 || curpages <= 0)
​                *allvisfrac = 0;
            else if ((double) relallvisible >= curpages)
​                *allvisfrac = 1;
​            else
​                *allvisfrac = (double) relallvisible / curpages;
​            break;
​        case RELKIND_SEQUENCE:
​            /* Sequences always have a known size */
​            *pages = 1;
​            *tuples = 1;
​            *allvisfrac = 0;
​            break;
​        case RELKIND_FOREIGN_TABLE:
​            /* Just use whatever's in pg_class */
​            *pages = rel->rd_rel->relpages;
​            *tuples = rel->rd_rel->reltuples;
​            *allvisfrac = 0;
​            break;
​        default:
​            /* else it has no disk storage; probably shouldn't get here? */
​            *pages = 0;
​            *tuples = 0;
            *allvisfrac = 0;
            break;
    }
}
```





索引元组数据结构

```
 \* Index tuple header structure
 \* All index tuples start with IndexTupleData.  If the HasNulls bit is set,
 \* this is followed by an IndexAttributeBitMapData.  The index attribute
 \* values follow, beginning at a MAXALIGN boundary.
 \* Note that the space allocated for the bitmap does not vary with the number
 \* of attributes; that is because we don't have room to store the number of
 \* attributes in the header.  Given the MAXALIGN constraint there's no space
 \* savings to be had anyway, for usual values of INDEX_MAX_KEYS.
 */
typedef struct IndexTupleData
{
​    ItemPointerData t_tid;      /* reference TID to heap tuple */  元组的tid的引用
​    /* ---------------
​     \* t_info is laid out in the following fashion:
​     \* 15th (high) bit: has nulls 有空值
​     \* 14th bit: has var-width attributes 可变长属性
​     \* 13th bit: unused 未使用
​     \* 12-0 bit: size of tuple 元组大小
​     \* ---------------
​     */
​    unsigned short t_info;      /* various info about tuple */  元组的各个信息
} IndexTupleData;               /* MORE DATA FOLLOWS AT END OF STRUCT */
```



