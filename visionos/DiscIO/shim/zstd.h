// Declarations-only shim: GalaxyVision doesn't build Dolphin's WIA/RVZ (zstd) readers.
#pragma once
#include <stddef.h>
typedef struct ZSTD_DCtx_s ZSTD_DStream;
typedef struct ZSTD_CCtx_s ZSTD_CStream;
typedef struct ZSTD_outBuffer_s { void *dst; size_t size; size_t pos; } ZSTD_outBuffer;
