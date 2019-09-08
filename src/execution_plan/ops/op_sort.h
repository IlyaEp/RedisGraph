/*
* Copyright 2018-2019 Redis Labs Ltd. and Contributors
*
* This file is available under the Redis Labs Source Available License Agreement
*/

#pragma once

#include "op.h"
#include "../../util/heap.h"
#include "../../arithmetic/arithmetic_expression.h"

typedef struct {
	OpBase op;
	AR_ExpNode **expressions;   // Expression to sort by.
	heap_t *heap;               // Holds top n records.
	Record *buffer;             // Holds all records.
	unsigned int offset;        // Offset into projected order expressions within a record.
	unsigned int limit;         // Total number of records to produce, 0 no limit.
	int direction;              // Ascending / desending.
} OpSort;

/* Creates a new Sort operation */
OpBase *NewSortOp(AR_ExpNode **expressions, int direction, unsigned int limit);
