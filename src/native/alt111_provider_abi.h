#ifndef ALT111_PROVIDER_ABI_H
#define ALT111_PROVIDER_ABI_H

/*
 * Cross-process/source boundary for integrated CarPlay AltScreen mode.
 *
 * libdirect_upload remains the proven cockpit presentation layer. In standalone
 * B3 it captures the final MMI display. In integrated MMI-Cockpit-Carplay mode it
 * MUST NOT capture/fallback to MMI. Instead it dlopens a provider implementing the
 * three symbols below.
 *
 * The provider owns how a decoded private stream111 frame crosses from the CarPlay
 * receiver/decoder process to the cockpit renderer process (QNX Screen surface,
 * shared memory, native buffer, etc.). That transport is P1404-specific and must
 * be verified locally. This ABI deliberately keeps the renderer independent of it.
 *
 * Frame contract:
 *   - canvas exactly 1024x480;
 *   - packed BGRA8888, stride exactly width*4;
 *   - pointer stays valid until the next cp_alt111_provider_frame() call;
 *   - frame_seq changes only for a newly decoded/presentable private111 frame;
 *   - frame_time_us is provider capture/presentation time when available;
 *   - returning NULL/0 means "no Alt111 frame", NEVER "use MMI instead".
 */

#define CP_ALT111_PROVIDER_ABI_VERSION 1
#define CP_ALT111_CANVAS_W 1024
#define CP_ALT111_CANVAS_H 480
#define CP_ALT111_FORMAT_BGRA8888 1

typedef unsigned int cp_alt111_u32;
typedef unsigned long long cp_alt111_u64;

/* Return 0 only when the provider is ready for the requested canvas/format. */
int cp_alt111_provider_open(int abi_version, int width, int height, int format);

/* Return packed BGRA frame pointer, or 0 when no valid private111 frame exists. */
const void *cp_alt111_provider_frame(cp_alt111_u32 *frame_seq,
                                     cp_alt111_u64 *frame_time_us,
                                     int *stride_bytes);

/* Optional diagnostic. Return non-zero only while the private111 source is alive. */
int cp_alt111_provider_health(cp_alt111_u32 *last_frame_seq,
                              cp_alt111_u64 *last_frame_time_us);

#endif
