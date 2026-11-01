/*
 * ADDBORDER -- Windows 1.01 GDI, segment _POLYGON, offset 0x0C89..0x121E.
 *
 * Reconstructed from windows1.01-reasm/omf/GDI/_POLYGON.asm (near Pascal).
 * Build:  CL /AL /Gw /Os /Gs /c /FaOUT.ASM /FoOUT.OBJ ADDBORDER.C
 *
 * Calling convention (13 argument words, 9 logical parameters, ret 1Ah):
 *
 *   arg 1  NODE far * far *alist   [bp+1A]  array of node-list far pointers,
 *                                           indexed by the edge "tag" * 4
 *   arg 2  EDGE far *e1            [bp+16]  first edge list (6-byte records)
 *   arg 3  WORD n1                 [bp+14]  number of records in e1
 *   arg 4  EDGE far *e2            [bp+10]  second edge list
 *   arg 5  WORD n2                 [bp+0E]  number of records in e2
 *   arg 6  WORD style              [bp+0C]  style word stored in every vertex
 *   arg 7  NODE far *pool          [bp+08]  vertex/list pool
 *   arg 8  WORD stride             [bp+06]  nodes per pool block
 *   arg 9  WORD block              [bp+04]  current pool block (in/out)
 *
 * Returns the updated pool block index (arg 9).
 *
 * EDGE is the 6-byte scan-conversion/edge record used by _POLYGON:
 *   +0  int   x
 *   +2  WORD  unused here
 *   +4  int   tag (index into alist; 0x8001 is the "dead" marker)
 *
 * NODE is the 10-byte list node.  The first node of a block is a list head:
 *   +0  far pointer to the next pool block   (long x on a vertex node)
 *   +4  vertex count                         (style on a vertex node)
 *   +6  far pointer to the paired list head  (long tag on a vertex node)
 * Vertex nodes follow the head at +10, +20, ...
 */

typedef unsigned short WORD;
typedef unsigned long  DWORD;

typedef struct _EDGE {
    int  x;                 /* +0 */
    WORD pad;               /* +2 */
    int  tag;               /* +4 */
} EDGE;

struct _NODE;

typedef union _NODEREF {
    long value;             /* long coordinate / long tag */
    struct _NODE far *node; /* far link to another list head */
} NODEREF;

typedef struct _NODE {
    NODEREF x;              /* +0 */
    int     count;          /* +4 */
    NODEREF tag;            /* +6 */
} NODE;

/* near Pascal helper, same segment, 5 argument words (ret 0Ah):
 *   CREATENEWLIST(tag, x, style, lp)
 * Initializes lp as a list head with two vertex nodes at lp+10 and lp+20.
 */
extern void pascal near CREATENEWLIST(WORD tag, WORD x, WORD style,
                                      NODE far *lp);

WORD pascal near ADDBORDER(NODE far * far *alist,
                           EDGE far *e1, WORD n1,
                           EDGE far *e2, WORD n2,
                           WORD style,
                           NODE far *pool, WORD stride,
                           WORD block)
{
    int a, b;
    int i, j;
    int tag, x, found;
    int c1, c2;
    int tag1, tag2, x2;
    WORD nsize;
    NODE far *node, far *p, far *q;
    EDGE rec[2];

    /* Pass 1: pair up records that carry the same tag in both lists.  The
     * first list supplies the vertex; both tags are negated to mark them
     * consumed for the merge below (0 becomes the 0x8001 dead marker).
     */
    for (i = 0; i < n1; i++) {
        if (e1[i].tag == 0x8001)
            e1[i].tag = 0;
        if (e1[i].tag < 0)
            e1[i].tag = -e1[i].tag;

        tag = e1[i].tag;
        x = e1[i].x;
        found = 0;

        for (j = 0; j < n2 && !found; j++) {
            if (e2[j].tag != tag)
                continue;

            found = 1;
            node = alist[tag];
            p = (NODE far *)((char far *)node +
                             (WORD)(node->count * (int)sizeof(NODE)));
            p->x.value = (long)x;
            p->count = style;

            e1[i].tag = -e1[i].tag;
            if (e1[i].tag == 0)
                e1[i].tag = 0x8001;
            e2[j].tag = -e2[j].tag;
            if (e2[j].tag == 0)
                e2[j].tag = 0x8001;
        }
    }

    /* Pass 2: merge the remaining (non-negative tag) records by x, two at a
     * time.  The two picked records decide how their list heads get linked:
     * two from list 1 link the two heads, two from list 2 allocate a fresh
     * pair of pool blocks, one from each appends two shared vertices.
     */
    a = 0;
    b = 0;
    for (;;) {
        if (a >= n1 && b >= n2)
            return block;

        while (a < n1 && e1[a].tag < 0)
            a++;
        if (a == n1)
            e1[a].x = 0x7FFF;
        while (b < n2 && e2[b].tag < 0)
            b++;
        if (b == n2)
            e2[b].x = 0x7FFF;

        c1 = 0;
        c2 = 0;
        tag1 = 0;
        tag2 = 0;
        x2 = 0;

        if (a >= n1 && b >= n2)
            continue;

        /* first record of this step */
        if (e2[b].x <= e1[a].x) {
            rec[c1 + c2].tag = e2[b].tag;
            rec[c1 + c2].x = e2[b].x;
            tag2 = e2[b].tag;
            x2 = e2[b].x;
            b++;
            c2++;
        } else {
            rec[c1 + c2].tag = e1[a].tag;
            rec[c1 + c2].x = e1[a].x;
            tag1 = e1[a].tag;
            a++;
            c1++;
        }

        /* skip consumed records again, then take the second record */
        while (a < n1 && e1[a].tag < 0)
            a++;
        if (a == n1)
            e1[a].x = 0x7FFF;
        while (b < n2 && e2[b].tag < 0)
            b++;
        if (b == n2)
            e2[b].x = 0x7FFF;

        if (e2[b].x <= e1[a].x) {
            rec[c1 + c2].tag = e2[b].tag;
            rec[c1 + c2].x = e2[b].x;
            tag2 = e2[b].tag;
            x2 = e2[b].x;
            b++;
            c2++;
        } else {
            rec[c1 + c2].tag = e1[a].tag;
            rec[c1 + c2].x = e1[a].x;
            tag1 = e1[a].tag;
            a++;
            c1++;
        }

        if (c1 == 2) {
            /* both records came from list 1: cross-link their list heads */
            p = alist[rec[0].tag];
            q = alist[rec[1].tag];
            p->tag.node = q;
            q->tag.node = p;
        } else if (c2 == 2) {
            /* both records came from list 2: create two new list blocks */
            p = (NODE far *)((char far *)pool +
                             (WORD)((int)block * (int)stride *
                                    (int)sizeof(NODE)));
            CREATENEWLIST(rec[0].tag, rec[0].x, style, p);

            nsize = (WORD)((int)sizeof(NODE) * (int)stride);
            p->x.node = (NODE far *)((char far *)p + nsize);
            alist[rec[0].tag] = p;

            q = (NODE far *)((char far *)p + nsize);
            CREATENEWLIST(rec[1].tag, rec[1].x, style, q);
            q->x.node = p;
            alist[rec[1].tag] = q;

            block += 2;
        } else {
            /* one record from each list: append two shared vertices to the
             * list 1 head and make the list 2 tag point at that same head */
            node = alist[tag1];
            p = (NODE far *)((char far *)node +
                             (WORD)(node->count * (int)sizeof(NODE)));
            p->tag.value = (long)tag2;
            node->count += 2;

            p = (NODE far *)((char far *)p + sizeof(NODE));
            p->x.value = (long)x2;
            p->count = style;

            p = (NODE far *)((char far *)p + sizeof(NODE));
            p->x.value = (long)x2;
            p->count = style;

            alist[tag2] = node;
        }
    }
}
