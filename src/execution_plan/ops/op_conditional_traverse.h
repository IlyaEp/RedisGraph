/*
* Copyright 2018-2019 Redis Labs Ltd. and Contributors
*
* This file is available under the Redis Labs Source Available License Agreement
*/

#ifndef __OP_COND_TRAVERSE_H
#define __OP_COND_TRAVERSE_H

#include "op.h"
#include "../../arithmetic/algebraic_expression.h"
#include "../../../deps/GraphBLAS/Include/GraphBLAS.h"
#include "../../util/vector.h"

/* OP Traverse */
typedef struct {
	OpBase op;
	Graph *graph;
	AlgebraicExpression *ae;
	int srcNodeIdx;             // Index into record.
	int destNodeIdx;            // Index into record.
	int *edgeRelationTypes;     // One or more relation types.
	int edgeRelationCount;      // length of edgeRelationTypes.
	GrB_Matrix F;               // Filter matrix.
	GrB_Matrix M;               // Algebraic expression result.
	Edge *edges;                // Discovered edges.
	GxB_MatrixTupleIter *iter;  // Iterator over M.
	int edgeRecIdx;             // Index into record.
	int recordsCap;             // Max number of records to process.
	int recordsLen;             // Number of records to process.
	bool transposed_edge;       // Track whether the expression references a transposed edge.
	Record *records;            // Array of records.
	Record r;                   // Current selected record.
} CondTraverse;

/* Creates a new Traverse operation */
OpBase *NewCondTraverseOp(Graph *g, RecordMap *record_map, AlgebraicExpression *ae,
						  uint records_cap);

/* One-time setup of Traverse operation. */
OpResult CondTraverseInit(OpBase *opBase);

/* TraverseConsume next operation
 * each call will update the graph
 * returns NULL when no additional updates are available */
Record CondTraverseConsume(OpBase *opBase);

/* Restart iterator */
OpResult CondTraverseReset(OpBase *ctx);

/* Frees Traverse*/
void CondTraverseFree(OpBase *ctx);

#endif
