/*
 * Included into every cgo C file (CGO_CFLAGS in .goreleaser.yaml). musl 1.2.4 removed
 * the basename() declaration from string.h; older containers/storage calls it
 * in pkg/unshare/unshare.c without including libgen.h, and zig's clang refuses
 * implicit declarations. Assembly files get CGO_CFLAGS too.
 */
#ifndef __ASSEMBLER__
#include <libgen.h>
#endif
