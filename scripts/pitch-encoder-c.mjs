// C Source Code for mp4enc: Self-Contained H.264 Baseline + MP4 Muxer
// Compiles with: clang -O3 -Wall -framework CoreGraphics -framework ImageIO -framework Foundation

export const C_MP4ENC_SOURCE = `
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>

typedef struct {
    uint8_t *buf;
    size_t cap;
    size_t bit_pos;
} BitWriter;

static void bw_init(BitWriter *bw, size_t cap) {
    bw->buf = (uint8_t *)calloc(1, cap);
    bw->cap = cap;
    bw->bit_pos = 0;
}

static void bw_write_bit(BitWriter *bw, int bit) {
    size_t byte_idx = bw->bit_pos / 8;
    int bit_offset = 7 - (bw->bit_pos % 8);
    if (byte_idx >= bw->cap) {
        bw->cap *= 2;
        bw->buf = (uint8_t *)realloc(bw->buf, bw->cap);
        memset(bw->buf + bw->cap / 2, 0, bw->cap / 2);
    }
    if (bit) {
        bw->buf[byte_idx] |= (1 << bit_offset);
    } else {
        bw->buf[byte_idx] &= ~(1 << bit_offset);
    }
    bw->bit_pos++;
}

static void bw_write_bits(BitWriter *bw, uint32_t val, int n) {
    for (int i = n - 1; i >= 0; i--) {
        bw_write_bit(bw, (val >> i) & 1);
    }
}

static void bw_write_ue(BitWriter *bw, uint32_t val) {
    uint32_t v = val + 1;
    int len = 0;
    while ((v >> len) > 0) len++;
    for (int i = 0; i < len - 1; i++) bw_write_bit(bw, 0);
    bw_write_bits(bw, v, len);
}

static void bw_write_se(BitWriter *bw, int32_t val) {
    if (val <= 0) {
        bw_write_ue(bw, (uint32_t)(-val * 2));
    } else {
        bw_write_ue(bw, (uint32_t)(val * 2 - 1));
    }
}

static void bw_align_zero(BitWriter *bw) {
    while (bw->bit_pos % 8 != 0) {
        bw_write_bit(bw, 0);
    }
}

static void bw_rbsp_trailing(BitWriter *bw) {
    bw_write_bit(bw, 1);
    bw_align_zero(bw);
}

static void bw_append_bytes(BitWriter *bw, const uint8_t *data, size_t len) {
    bw_align_zero(bw);
    size_t start_byte = bw->bit_pos / 8;
    if (start_byte + len > bw->cap) {
        while (start_byte + len > bw->cap) bw->cap *= 2;
        bw->buf = (uint8_t *)realloc(bw->buf, bw->cap);
    }
    memcpy(bw->buf + start_byte, data, len);
    bw->bit_pos += len * 8;
}

static size_t rbsp_to_ebsp(const uint8_t *rbsp, size_t rbsp_len, uint8_t *ebsp) {
    size_t out_len = 0;
    int zero_count = 0;
    for (size_t i = 0; i < rbsp_len; i++) {
        uint8_t b = rbsp[i];
        if (zero_count == 2 && b <= 0x03) {
            ebsp[out_len++] = 0x03;
            zero_count = 0;
        }
        ebsp[out_len++] = b;
        if (b == 0x00) zero_count++;
        else zero_count = 0;
    }
    return out_len;
}

typedef struct {
    uint8_t *data;
    size_t size;
    size_t cap;
} Buf;

static void buf_init(Buf *b) {
    b->cap = 4096;
    b->size = 0;
    b->data = (uint8_t *)malloc(b->cap);
}

static void buf_free(Buf *b) {
    free(b->data);
}

static void buf_write(Buf *b, const void *ptr, size_t len) {
    if (b->size + len > b->cap) {
        while (b->size + len > b->cap) b->cap *= 2;
        b->data = (uint8_t *)realloc(b->data, b->cap);
    }
    memcpy(b->data + b->size, ptr, len);
    b->size += len;
}

static void buf_u8(Buf *b, uint8_t v) { buf_write(b, &v, 1); }
static void buf_u16(Buf *b, uint16_t v) {
    uint8_t d[2] = { (uint8_t)(v >> 8), (uint8_t)v };
    buf_write(b, d, 2);
}
static void buf_u32(Buf *b, uint32_t v) {
    uint8_t d[4] = { (uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v };
    buf_write(b, d, 4);
}
static void buf_fourcc(Buf *b, const char *fcc) {
    buf_write(b, fcc, 4);
}

static size_t buf_begin_box(Buf *b, const char *fcc) {
    size_t pos = b->size;
    buf_u32(b, 0);
    buf_fourcc(b, fcc);
    return pos;
}

static void buf_end_box(Buf *b, size_t pos) {
    uint32_t len = (uint32_t)(b->size - pos);
    b->data[pos]     = (uint8_t)(len >> 24);
    b->data[pos + 1] = (uint8_t)(len >> 16);
    b->data[pos + 2] = (uint8_t)(len >> 8);
    b->data[pos + 3] = (uint8_t)len;
}

static int load_png_yuv(const char *path, int width, int height, uint8_t *out_Y, uint8_t *out_U, uint8_t *out_V) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
    if (!url) return -1;
    CGImageSourceRef src = CGImageSourceCreateWithURL(url, NULL);
    CFRelease(url);
    if (!src) return -2;
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!img) return -3;

    size_t w = CGImageGetWidth(img);
    size_t h = CGImageGetHeight(img);
    if ((int)w != width || (int)h != height) {
        CGImageRelease(img);
        return -4;
    }

    uint8_t *rgba = (uint8_t *)malloc(width * height * 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba, width, height, 8, width * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), img);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    CGImageRelease(img);

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            size_t off = (y * width + x) * 4;
            int r = rgba[off];
            int g = rgba[off + 1];
            int b = rgba[off + 2];
            int y_val = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
            if (y_val < 16) y_val = 16;
            if (y_val > 235) y_val = 235;
            out_Y[y * width + x] = (uint8_t)y_val;
        }
    }

    for (int cy = 0; cy < height / 2; cy++) {
        for (int cx = 0; cx < width / 2; cx++) {
            int y0 = cy * 2;
            int x0 = cx * 2;
            size_t o00 = (y0 * width + x0) * 4;
            size_t o01 = (y0 * width + x0 + 1) * 4;
            size_t o10 = ((y0 + 1) * width + x0) * 4;
            size_t o11 = ((y0 + 1) * width + x0 + 1) * 4;

            int r = (rgba[o00] + rgba[o01] + rgba[o10] + rgba[o11] + 2) >> 2;
            int g = (rgba[o00 + 1] + rgba[o01 + 1] + rgba[o10 + 1] + rgba[o11 + 1] + 2) >> 2;
            int b = (rgba[o00 + 2] + rgba[o01 + 2] + rgba[o10 + 2] + rgba[o11 + 2] + 2) >> 2;

            int u_val = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
            int v_val = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;

            if (u_val < 16) u_val = 16;
            if (u_val > 240) u_val = 240;
            if (v_val < 16) v_val = 16;
            if (v_val > 240) v_val = 240;

            out_U[cy * (width / 2) + cx] = (uint8_t)u_val;
            out_V[cy * (width / 2) + cx] = (uint8_t)v_val;
        }
    }

    free(rgba);
    return 0;
}

static void extract_mb_pcm(const uint8_t *Y, const uint8_t *U, const uint8_t *V, int width, int mb_x, int mb_y, uint8_t *pcm) {
    for (int r = 0; r < 16; r++) {
        memcpy(pcm + r * 16, Y + (mb_y * 16 + r) * width + mb_x * 16, 16);
    }
    for (int r = 0; r < 8; r++) {
        memcpy(pcm + 256 + r * 8, U + (mb_y * 8 + r) * (width / 2) + mb_x * 8, 8);
    }
    for (int r = 0; r < 8; r++) {
        memcpy(pcm + 320 + r * 8, V + (mb_y * 8 + r) * (width / 2) + mb_x * 8, 8);
    }
}

static int mb_is_identical(const uint8_t *cur_Y, const uint8_t *cur_U, const uint8_t *cur_V,
                           const uint8_t *prev_Y, const uint8_t *prev_U, const uint8_t *prev_V,
                           int width, int mb_x, int mb_y) {
    for (int r = 0; r < 16; r++) {
        size_t off = (mb_y * 16 + r) * width + mb_x * 16;
        if (memcmp(cur_Y + off, prev_Y + off, 16) != 0) return 0;
    }
    for (int r = 0; r < 8; r++) {
        size_t off = (mb_y * 8 + r) * (width / 2) + mb_x * 8;
        if (memcmp(cur_U + off, prev_U + off, 8) != 0) return 0;
    }
    for (int r = 0; r < 8; r++) {
        size_t off = (mb_y * 8 + r) * (width / 2) + mb_x * 8;
        if (memcmp(cur_V + off, prev_V + off, 8) != 0) return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 6) {
        fprintf(stderr, "Usage: %s <manifest.txt> <output.mp4> <width> <height> <fps>\\n", argv[0]);
        return 1;
    }
    const char *manifest_path = argv[1];
    const char *output_mp4 = argv[2];
    int width = atoi(argv[3]);
    int height = atoi(argv[4]);
    int fps = atoi(argv[5]);

    int mb_w = width / 16;
    int mb_h = height / 16;
    int total_mbs = mb_w * mb_h;

    // Generate SPS
    BitWriter sps_bw;
    bw_init(&sps_bw, 128);
    bw_write_bits(&sps_bw, 66, 8);   // Baseline profile_idc=66
    bw_write_bits(&sps_bw, 0xc0, 8); // constraints=0xc0
    bw_write_bits(&sps_bw, 31, 8);   // level_idc=31 (720p30)
    bw_write_ue(&sps_bw, 0);         // sps_id=0
    bw_write_ue(&sps_bw, 0);         // log2_max_frame_num_minus4=0
    bw_write_ue(&sps_bw, 2);         // pic_order_cnt_type=2
    bw_write_ue(&sps_bw, 1);         // max_num_ref_frames=1
    bw_write_bit(&sps_bw, 0);        // gaps_in_frame_num_value_allowed_flag=0
    bw_write_ue(&sps_bw, mb_w - 1);  // 79 (1280/16 - 1)
    bw_write_ue(&sps_bw, mb_h - 1);  // 44 (720/16 - 1)
    bw_write_bit(&sps_bw, 1);        // frame_mbs_only_flag=1
    bw_write_bit(&sps_bw, 1);        // direct_8x8_inference_flag=1
    bw_write_bit(&sps_bw, 0);        // frame_cropping_flag=0
    bw_write_bit(&sps_bw, 0);        // vui_parameters_present_flag=0
    bw_rbsp_trailing(&sps_bw);

    uint8_t sps_nal[128];
    sps_nal[0] = 0x67;
    size_t sps_ebsp_len = rbsp_to_ebsp(sps_bw.buf, sps_bw.bit_pos / 8, sps_nal + 1);
    size_t sps_nal_len = 1 + sps_ebsp_len;
    free(sps_bw.buf);

    // Generate PPS
    BitWriter pps_bw;
    bw_init(&pps_bw, 128);
    bw_write_ue(&pps_bw, 0);
    bw_write_ue(&pps_bw, 0);
    bw_write_bit(&pps_bw, 0);
    bw_write_bit(&pps_bw, 0);
    bw_write_ue(&pps_bw, 0);
    bw_write_ue(&pps_bw, 0);
    bw_write_ue(&pps_bw, 0);
    bw_write_bit(&pps_bw, 0);
    bw_write_bits(&pps_bw, 0, 2);
    bw_write_se(&pps_bw, 0);
    bw_write_se(&pps_bw, 0);
    bw_write_se(&pps_bw, 0);
    bw_write_bit(&pps_bw, 1); // deblocking_filter_control_present_flag=1
    bw_write_bit(&pps_bw, 0);
    bw_write_bit(&pps_bw, 0);
    bw_rbsp_trailing(&pps_bw);

    uint8_t pps_nal[128];
    pps_nal[0] = 0x68;
    size_t pps_ebsp_len = rbsp_to_ebsp(pps_bw.buf, pps_bw.bit_pos / 8, pps_nal + 1);
    size_t pps_nal_len = 1 + pps_ebsp_len;
    free(pps_bw.buf);

    FILE *mf = fopen(manifest_path, "r");
    if (!mf) {
        perror("Failed to open frames manifest");
        return 1;
    }

    FILE *fp = fopen(output_mp4, "wb");
    if (!fp) {
        perror("Failed to open output mp4 file");
        fclose(mf);
        return 1;
    }

    // Write ftyp
    Buf ftyp;
    buf_init(&ftyp);
    size_t b_ftyp = buf_begin_box(&ftyp, "ftyp");
    buf_fourcc(&ftyp, "isom");
    buf_u32(&ftyp, 512);
    buf_fourcc(&ftyp, "isom");
    buf_fourcc(&ftyp, "iso2");
    buf_fourcc(&ftyp, "avc1");
    buf_fourcc(&ftyp, "mp41");
    buf_end_box(&ftyp, b_ftyp);
    fwrite(ftyp.data, 1, ftyp.size, fp);
    buf_free(&ftyp);

    // Reserve mdat
    long mdat_pos = ftell(fp);
    uint8_t mdat_hdr[8] = { 0, 0, 0, 0, 'm', 'd', 'a', 't' };
    fwrite(mdat_hdr, 1, 8, fp);

    uint8_t *cur_Y = (uint8_t *)malloc(width * height);
    uint8_t *cur_U = (uint8_t *)malloc((width / 2) * (height / 2));
    uint8_t *cur_V = (uint8_t *)malloc((width / 2) * (height / 2));
    uint8_t *prev_Y = (uint8_t *)malloc(width * height);
    uint8_t *prev_U = (uint8_t *)malloc((width / 2) * (height / 2));
    uint8_t *prev_V = (uint8_t *)malloc((width / 2) * (height / 2));
    uint8_t *pcm_block = (uint8_t *)malloc(384);

    size_t frame_cap = 2048;
    size_t total_frames = 0;
    uint32_t *frame_sizes = (uint32_t *)malloc(frame_cap * 4);
    uint32_t *frame_offsets = (uint32_t *)malloc(frame_cap * 4);

    char line[1024];
    int is_first_frame = 1;

    while (fgets(line, sizeof(line), mf)) {
        char png_path[512] = {0};
        int repeat_count = 1;
        if (sscanf(line, "%511s %d", png_path, &repeat_count) < 1) continue;
        if (repeat_count < 1) repeat_count = 1;

        if (load_png_yuv(png_path, width, height, cur_Y, cur_U, cur_V) != 0) {
            fprintf(stderr, "Failed to load PNG: %s\\n", png_path);
            continue;
        }

        if (is_first_frame) {
            BitWriter idr_bw;
            bw_init(&idr_bw, total_mbs * 400);
            bw_write_ue(&idr_bw, 0); // first_mb = 0
            bw_write_ue(&idr_bw, 7); // slice_type = 7 (I)
            bw_write_ue(&idr_bw, 0); // pps_id = 0
            bw_write_bits(&idr_bw, 0, 4); // frame_num = 0
            bw_write_ue(&idr_bw, 0); // idr_pic_id = 0
            bw_write_bit(&idr_bw, 0);
            bw_write_bit(&idr_bw, 0);
            bw_write_se(&idr_bw, 0);
            bw_write_ue(&idr_bw, 1); // disable deblocking

            for (int mb = 0; mb < total_mbs; mb++) {
                int mx = mb % mb_w;
                int my = mb / mb_w;
                bw_write_ue(&idr_bw, 25); // I_PCM
                extract_mb_pcm(cur_Y, cur_U, cur_V, width, mx, my, pcm_block);
                bw_append_bytes(&idr_bw, pcm_block, 384);
            }
            bw_rbsp_trailing(&idr_bw);

            size_t idr_rbsp_len = (idr_bw.bit_pos + 7) / 8;
            uint8_t *idr_nal = (uint8_t *)malloc(idr_rbsp_len * 2 + 1);
            idr_nal[0] = 0x65;
            size_t idr_ebsp_len = rbsp_to_ebsp(idr_bw.buf, idr_rbsp_len, idr_nal + 1);
            size_t idr_nal_len = 1 + idr_ebsp_len;
            free(idr_bw.buf);

            if (total_frames >= frame_cap) {
                frame_cap *= 2;
                frame_sizes = (uint32_t *)realloc(frame_sizes, frame_cap * 4);
                frame_offsets = (uint32_t *)realloc(frame_offsets, frame_cap * 4);
            }
            frame_offsets[total_frames] = (uint32_t)ftell(fp);
            uint8_t len_be[4] = { (uint8_t)(idr_nal_len >> 24), (uint8_t)(idr_nal_len >> 16), (uint8_t)(idr_nal_len >> 8), (uint8_t)idr_nal_len };
            fwrite(len_be, 1, 4, fp);
            fwrite(idr_nal, 1, idr_nal_len, fp);
            frame_sizes[total_frames] = (uint32_t)(4 + idr_nal_len);
            total_frames++;
            free(idr_nal);

            memcpy(prev_Y, cur_Y, width * height);
            memcpy(prev_U, cur_U, (width / 2) * (height / 2));
            memcpy(prev_V, cur_V, (width / 2) * (height / 2));
            is_first_frame = 0;
            repeat_count--;
        } else {
            BitWriter p_bw;
            bw_init(&p_bw, total_mbs * 400);
            bw_write_ue(&p_bw, 0); // first_mb = 0
            bw_write_ue(&p_bw, 5); // slice_type = 5 (P)
            bw_write_ue(&p_bw, 0); // pps_id = 0
            bw_write_bits(&p_bw, (total_frames & 0x0F), 4);
            bw_write_bit(&p_bw, 0);
            bw_write_bit(&p_bw, 0);
            bw_write_bit(&p_bw, 0);
            bw_write_se(&p_bw, 0);
            bw_write_ue(&p_bw, 1);

            int skip_run = 0;
            for (int mb = 0; mb < total_mbs; mb++) {
                int mx = mb % mb_w;
                int my = mb / mb_w;
                if (mb_is_identical(cur_Y, cur_U, cur_V, prev_Y, prev_U, prev_V, width, mx, my)) {
                    skip_run++;
                } else {
                    bw_write_ue(&p_bw, skip_run);
                    skip_run = 0;
                    bw_write_ue(&p_bw, 30); // I_PCM in P-slice
                    extract_mb_pcm(cur_Y, cur_U, cur_V, width, mx, my, pcm_block);
                    bw_append_bytes(&p_bw, pcm_block, 384);
                }
            }
            if (skip_run > 0) {
                bw_write_ue(&p_bw, skip_run);
            }
            bw_rbsp_trailing(&p_bw);

            size_t p_rbsp_len = (p_bw.bit_pos + 7) / 8;
            uint8_t *p_nal = (uint8_t *)malloc(p_rbsp_len * 2 + 1);
            p_nal[0] = 0x41;
            size_t p_ebsp_len = rbsp_to_ebsp(p_bw.buf, p_rbsp_len, p_nal + 1);
            size_t p_nal_len = 1 + p_ebsp_len;
            free(p_bw.buf);

            if (total_frames >= frame_cap) {
                frame_cap *= 2;
                frame_sizes = (uint32_t *)realloc(frame_sizes, frame_cap * 4);
                frame_offsets = (uint32_t *)realloc(frame_offsets, frame_cap * 4);
            }
            frame_offsets[total_frames] = (uint32_t)ftell(fp);
            uint8_t len_be[4] = { (uint8_t)(p_nal_len >> 24), (uint8_t)(p_nal_len >> 16), (uint8_t)(p_nal_len >> 8), (uint8_t)p_nal_len };
            fwrite(len_be, 1, 4, fp);
            fwrite(p_nal, 1, p_nal_len, fp);
            frame_sizes[total_frames] = (uint32_t)(4 + p_nal_len);
            total_frames++;
            free(p_nal);

            memcpy(prev_Y, cur_Y, width * height);
            memcpy(prev_U, cur_U, (width / 2) * (height / 2));
            memcpy(prev_V, cur_V, (width / 2) * (height / 2));
            repeat_count--;
        }

        // Emit hold frames (skip_run = total_mbs)
        while (repeat_count > 0) {
            BitWriter h_bw;
            bw_init(&h_bw, 64);
            bw_write_ue(&h_bw, 0); // first_mb = 0
            bw_write_ue(&h_bw, 5); // slice_type = 5 (P)
            bw_write_ue(&h_bw, 0); // pps_id = 0
            bw_write_bits(&h_bw, (total_frames & 0x0F), 4);
            bw_write_bit(&h_bw, 0);
            bw_write_bit(&h_bw, 0);
            bw_write_bit(&h_bw, 0);
            bw_write_se(&h_bw, 0);
            bw_write_ue(&h_bw, 1);
            bw_write_ue(&h_bw, total_mbs); // skip all!
            bw_rbsp_trailing(&h_bw);

            uint8_t h_nal[64];
            h_nal[0] = 0x41;
            size_t h_ebsp = rbsp_to_ebsp(h_bw.buf, (h_bw.bit_pos + 7) / 8, h_nal + 1);
            size_t h_len = 1 + h_ebsp;
            free(h_bw.buf);

            if (total_frames >= frame_cap) {
                frame_cap *= 2;
                frame_sizes = (uint32_t *)realloc(frame_sizes, frame_cap * 4);
                frame_offsets = (uint32_t *)realloc(frame_offsets, frame_cap * 4);
            }
            frame_offsets[total_frames] = (uint32_t)ftell(fp);
            uint8_t len_be[4] = { (uint8_t)(h_len >> 24), (uint8_t)(h_len >> 16), (uint8_t)(h_len >> 8), (uint8_t)h_len };
            fwrite(len_be, 1, 4, fp);
            fwrite(h_nal, 1, h_len, fp);
            frame_sizes[total_frames] = (uint32_t)(4 + h_len);
            total_frames++;
            repeat_count--;
        }
    }
    fclose(mf);

    // Finalize mdat size
    long mdat_end = ftell(fp);
    uint32_t mdat_size = (uint32_t)(mdat_end - mdat_pos);
    fseek(fp, mdat_pos, SEEK_SET);
    mdat_hdr[0] = (uint8_t)(mdat_size >> 24);
    mdat_hdr[1] = (uint8_t)(mdat_size >> 16);
    mdat_hdr[2] = (uint8_t)(mdat_size >> 8);
    mdat_hdr[3] = (uint8_t)mdat_size;
    fwrite(mdat_hdr, 1, 4, fp);
    fseek(fp, mdat_end, SEEK_SET);

    // Write moov
    Buf moov;
    buf_init(&moov);
    size_t b_moov = buf_begin_box(&moov, "moov");

    // mvhd
    size_t b_mvhd = buf_begin_box(&moov, "mvhd");
    buf_u32(&moov, 0);
    buf_u32(&moov, 0);
    buf_u32(&moov, 0);
    buf_u32(&moov, fps);
    buf_u32(&moov, (uint32_t)total_frames);
    buf_u32(&moov, 0x00010000);
    buf_u16(&moov, 0x0100);
    buf_u16(&moov, 0);
    buf_u32(&moov, 0);
    buf_u32(&moov, 0);
    buf_u32(&moov, 0x00010000); buf_u32(&moov, 0); buf_u32(&moov, 0);
    buf_u32(&moov, 0); buf_u32(&moov, 0x00010000); buf_u32(&moov, 0);
    buf_u32(&moov, 0); buf_u32(&moov, 0); buf_u32(&moov, 0x40000000);
    for (int k = 0; k < 6; k++) buf_u32(&moov, 0);
    buf_u32(&moov, 2);
    buf_end_box(&moov, b_mvhd);

    // trak
    size_t b_trak = buf_begin_box(&moov, "trak");

    // tkhd
    size_t b_tkhd = buf_begin_box(&moov, "tkhd");
    buf_u32(&moov, 3);
    buf_u32(&moov, 0);
    buf_u32(&moov, 0);
    buf_u32(&moov, 1);
    buf_u32(&moov, 0);
    buf_u32(&moov, (uint32_t)total_frames);
    buf_u32(&moov, 0); buf_u32(&moov, 0);
    buf_u16(&moov, 0);
    buf_u16(&moov, 0);
    buf_u16(&moov, 0);
    buf_u16(&moov, 0);
    buf_u32(&moov, 0x00010000); buf_u32(&moov, 0); buf_u32(&moov, 0);
    buf_u32(&moov, 0); buf_u32(&moov, 0x00010000); buf_u32(&moov, 0);
    buf_u32(&moov, 0); buf_u32(&moov, 0); buf_u32(&moov, 0x40000000);
    buf_u32(&moov, width << 16);
    buf_u32(&moov, height << 16);
    buf_end_box(&moov, b_tkhd);

    // mdia
    size_t b_mdia = buf_begin_box(&moov, "mdia");

    // mdhd
    size_t b_mdhd = buf_begin_box(&moov, "mdhd");
    buf_u32(&moov, 0);
    buf_u32(&moov, 0);
    buf_u32(&moov, 0);
    buf_u32(&moov, fps);
    buf_u32(&moov, (uint32_t)total_frames);
    buf_u16(&moov, 0x55c4);
    buf_u16(&moov, 0);
    buf_end_box(&moov, b_mdhd);

    // hdlr
    size_t b_hdlr = buf_begin_box(&moov, "hdlr");
    buf_u32(&moov, 0);
    buf_u32(&moov, 0);
    buf_fourcc(&moov, "vide");
    buf_u32(&moov, 0); buf_u32(&moov, 0); buf_u32(&moov, 0);
    const char *hdlr_name = "VideoHandler";
    buf_write(&moov, hdlr_name, strlen(hdlr_name) + 1);
    buf_end_box(&moov, b_hdlr);

    // minf
    size_t b_minf = buf_begin_box(&moov, "minf");

    // vmhd
    size_t b_vmhd = buf_begin_box(&moov, "vmhd");
    buf_u32(&moov, 1);
    buf_u16(&moov, 0);
    buf_u16(&moov, 0); buf_u16(&moov, 0); buf_u16(&moov, 0);
    buf_end_box(&moov, b_vmhd);

    // dinf
    size_t b_dinf = buf_begin_box(&moov, "dinf");
    size_t b_dref = buf_begin_box(&moov, "dref");
    buf_u32(&moov, 0);
    buf_u32(&moov, 1);
    size_t b_url = buf_begin_box(&moov, "url ");
    buf_u32(&moov, 1);
    buf_end_box(&moov, b_url);
    buf_end_box(&moov, b_dref);
    buf_end_box(&moov, b_dinf);

    // stbl
    size_t b_stbl = buf_begin_box(&moov, "stbl");

    // stsd
    size_t b_stsd = buf_begin_box(&moov, "stsd");
    buf_u32(&moov, 0);
    buf_u32(&moov, 1);

    size_t b_avc1 = buf_begin_box(&moov, "avc1");
    for (int k = 0; k < 6; k++) buf_u8(&moov, 0);
    buf_u16(&moov, 1);
    buf_u16(&moov, 0);
    buf_u16(&moov, 0);
    buf_u32(&moov, 0); buf_u32(&moov, 0); buf_u32(&moov, 0);
    buf_u16(&moov, width);
    buf_u16(&moov, height);
    buf_u32(&moov, 0x00480000);
    buf_u32(&moov, 0x00480000);
    buf_u32(&moov, 0);
    buf_u16(&moov, 1);
    uint8_t cname[32] = { 0 };
    cname[0] = 7;
    memcpy(cname + 1, "ExoH264", 7);
    buf_write(&moov, cname, 32);
    buf_u16(&moov, 0x0018);
    buf_u16(&moov, 0xffff);

    // avcC
    size_t b_avcc = buf_begin_box(&moov, "avcC");
    buf_u8(&moov, 1);
    buf_u8(&moov, 66);
    buf_u8(&moov, 0xc0);
    buf_u8(&moov, 31);
    buf_u8(&moov, 0xff);
    buf_u8(&moov, 0xe1);
    buf_u16(&moov, sps_nal_len);
    buf_write(&moov, sps_nal, sps_nal_len);
    buf_u8(&moov, 1);
    buf_u16(&moov, pps_nal_len);
    buf_write(&moov, pps_nal, pps_nal_len);
    buf_end_box(&moov, b_avcc);

    buf_end_box(&moov, b_avc1);
    buf_end_box(&moov, b_stsd);

    // stts
    size_t b_stts = buf_begin_box(&moov, "stts");
    buf_u32(&moov, 0);
    buf_u32(&moov, 1);
    buf_u32(&moov, (uint32_t)total_frames);
    buf_u32(&moov, 1);
    buf_end_box(&moov, b_stts);

    // stss
    size_t b_stss = buf_begin_box(&moov, "stss");
    buf_u32(&moov, 0);
    buf_u32(&moov, 1);
    buf_u32(&moov, 1);
    buf_end_box(&moov, b_stss);

    // stsc
    size_t b_stsc = buf_begin_box(&moov, "stsc");
    buf_u32(&moov, 0);
    buf_u32(&moov, 1);
    buf_u32(&moov, 1);
    buf_u32(&moov, 1);
    buf_u32(&moov, 1);
    buf_end_box(&moov, b_stsc);

    // stsz
    size_t b_stsz = buf_begin_box(&moov, "stsz");
    buf_u32(&moov, 0);
    buf_u32(&moov, 0);
    buf_u32(&moov, (uint32_t)total_frames);
    for (size_t i = 0; i < total_frames; i++) {
        buf_u32(&moov, frame_sizes[i]);
    }
    buf_end_box(&moov, b_stsz);

    // stco
    size_t b_stco = buf_begin_box(&moov, "stco");
    buf_u32(&moov, 0);
    buf_u32(&moov, (uint32_t)total_frames);
    for (size_t i = 0; i < total_frames; i++) {
        buf_u32(&moov, frame_offsets[i]);
    }
    buf_end_box(&moov, b_stco);

    buf_end_box(&moov, b_stbl);
    buf_end_box(&moov, b_minf);
    buf_end_box(&moov, b_mdia);
    buf_end_box(&moov, b_trak);
    buf_end_box(&moov, b_moov);

    fwrite(moov.data, 1, moov.size, fp);
    buf_free(&moov);
    fclose(fp);

    free(cur_Y); free(cur_U); free(cur_V);
    free(prev_Y); free(prev_U); free(prev_V);
    free(pcm_block);
    free(frame_sizes);
    free(frame_offsets);
    return 0;
}
`;
