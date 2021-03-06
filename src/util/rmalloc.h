#ifndef __REDISGRAPH_ALLOC__
#define __REDISGRAPH_ALLOC__

#include <stdlib.h>
#include <string.h>
#include "../redismodule.h"

#ifdef REDIS_MODULE_TARGET /* Set this when compiling your code as a module */

static inline void *rm_malloc(size_t n) {
	return RedisModule_Alloc(n);
}
static inline void *rm_calloc(size_t nelem, size_t elemsz) {
	return RedisModule_Calloc(nelem, elemsz);
}
static inline void *rm_realloc(void *p, size_t n) {
	return RedisModule_Realloc(p, n);
}
static inline void rm_free(void *p) {
	RedisModule_Free(p);
}
static inline char *rm_strdup(const char *s) {
	return RedisModule_Strdup(s);
}

#endif
#ifndef REDIS_MODULE_TARGET
/* for non redis module targets */
#define rm_malloc malloc
#define rm_free free
#define rm_calloc calloc
#define rm_realloc realloc
#define rm_strdup strdup
#endif

#define rm_new(x) rm_malloc(sizeof(x))

/* Revert the allocator patches so that
 * the stdlib malloc functions will be used
 * for use when executing code from non-Redis
 * contexts like unit tests. */
void Alloc_Reset(void);

#endif

