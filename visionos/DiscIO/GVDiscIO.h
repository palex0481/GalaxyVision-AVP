// SPDX-License-Identifier: GPL-3.0-or-later
// C interface to Dolphin DiscIO extraction (adapted from upstream GalaxyPadDiscExtractor.mm).
#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Extracts the RMGE01 rev 0 game partition of a Wii disc image (plain/encrypted ISO or WBFS)
// into destination (must not exist): sys/ + files/. Returns 0 on success, otherwise writes a
// player-facing message to error. progress may be NULL; cancelled may be NULL.
int GVDiscIOExtract(const char *image, const char *destination,
                    void (*progress)(void *ctx, double fraction),
                    int (*cancelled)(void *ctx), void *ctx,
                    char *error, size_t errorSize);
// 1 if DiscIO can open the file as a Wii disc at all (any title).
int GVDiscIOCanOpen(const char *image);
#ifdef __cplusplus
}
#endif
