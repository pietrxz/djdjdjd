#pragma once
#include <mach-o/loader.h>
#include <stdint.h>
#include <stddef.h>

typedef struct { const char *name; uintptr_t replacement; unsigned writes; } EzwinImportBinding;
typedef struct { unsigned writes, protectionFailures, restoreFailures; } EzwinRebindResult;
EzwinRebindResult EzwinRebindImports(const mach_header_64 *image,intptr_t slide,
    EzwinImportBinding *bindings,size_t count);
