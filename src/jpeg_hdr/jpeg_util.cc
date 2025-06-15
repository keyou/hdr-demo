/**
 * 功能：生成一张使用 JPEG+ICC 实现的 HDR 图片。
 *
 * 使用方法：
 * 1. 安装 libjpeg-turbo 库: `brew install libjpeg-turbo`；
 * 2. cmake && make 编译；
 * 3. 执行 ./jpeg_util 后生成 output_rec2020_pq.jpg 文件；
 */

#include <cmath>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <jerror.h>
#include <jpeglib.h>

// Half 浮点类型定义 (FP16)
// __fp16 由 mac 平台提供，其他平台没有，如果想要将 demo 迁移到其他平台需要适配
typedef __fp16 fp16;

// Half 转 Float (简化版)，mac 平台可以自动转换，其他平台需要适配
float half_to_float(fp16 h) { return h; }

struct __attribute__((packed)) RGBAColor {
  fp16 r;
  fp16 g;
  fp16 b;
  fp16 a;
};

// 从文件读取 ICC 配置文件
unsigned char *read_icc_profile(const char *filename, size_t *icc_size) {
  FILE *file = fopen(filename, "rb");
  if (!file) {
    fprintf(stderr, "无法打开 ICC 配置文件: %s\n", filename);
    return NULL;
  }

  fseek(file, 0, SEEK_END);
  *icc_size = ftell(file);
  fseek(file, 0, SEEK_SET);

  unsigned char *icc_data = (unsigned char *)malloc(*icc_size);
  if (!icc_data) {
    fclose(file);
    return NULL;
  }

  if (fread(icc_data, 1, *icc_size, file) != *icc_size) {
    free(icc_data);
    fclose(file);
    return NULL;
  }

  fclose(file);
  return icc_data;
}

// PQ 曲线 (ST.2084) 正向变换，也就是 PQ 光电转换函数（线性光 → 非线性电信号）
// https://en.wikipedia.org/wiki/Perceptual_quantizer
// 输入：L 线性光亮度，范围 [0, 1]
// 输出：PQ 非线性电信号，范围 [0, 1]
float pq_forward(float L) {
  const float m1 = 2610.0 / 4096.0 / 4.0;
  const float m2 = 2523.0 / 4096.0 * 128.0;
  const float c1 = 3424.0 / 4096.0;
  const float c2 = 2413.0 / 4096.0 * 32.0;
  const float c3 = 2392.0 / 4096.0 * 32.0;

  float Lm = powf(L, m1);
  float numerator = c1 + c2 * Lm;
  float denominator = 1.0f + c3 * Lm;
  return powf(numerator / denominator, m2);
}

// 写入 ICC 配置文件到 JPEG
void write_icc_profile(j_compress_ptr cinfo, const unsigned char *icc_data,
                       size_t icc_size) {
  const size_t MAX_ICC_SEGMENT_SIZE = 65533;
  size_t segments =
      (icc_size + MAX_ICC_SEGMENT_SIZE - 1) / MAX_ICC_SEGMENT_SIZE;
  size_t remaining = icc_size;

  for (size_t i = 0; i < segments; i++) {
    size_t segment_size =
        remaining > MAX_ICC_SEGMENT_SIZE ? MAX_ICC_SEGMENT_SIZE : remaining;

    jpeg_write_m_header(cinfo, JPEG_APP0 + 2, segment_size + 14);

    // ICC 标记头
    jpeg_write_m_byte(cinfo, 'I');
    jpeg_write_m_byte(cinfo, 'C');
    jpeg_write_m_byte(cinfo, 'C');
    jpeg_write_m_byte(cinfo, '_');
    jpeg_write_m_byte(cinfo, 'P');
    jpeg_write_m_byte(cinfo, 'R');
    jpeg_write_m_byte(cinfo, 'O');
    jpeg_write_m_byte(cinfo, 'F');
    jpeg_write_m_byte(cinfo, 'I');
    jpeg_write_m_byte(cinfo, 'L');
    jpeg_write_m_byte(cinfo, 'E');
    jpeg_write_m_byte(cinfo, '\0');
    jpeg_write_m_byte(cinfo, (JOCTET)(i + 1));  // 当前段序号
    jpeg_write_m_byte(cinfo, (JOCTET)segments); // 总段数

    // 写入 ICC 数据段
    for (size_t j = 0; j < segment_size; j++) {
      jpeg_write_m_byte(cinfo, icc_data[i * MAX_ICC_SEGMENT_SIZE + j]);
    }

    remaining -= segment_size;
  }
}

// 保存 RGBA Half 为 JPEG 并应用 Rec.2020 PQ 转换函数
void save_half_rgba_as_jpeg_with_pq(const char *filename, const fp16 *rgba_data,
                                    int width, int height, int quality,
                                    const char *icc_profile_path) {
  // 读取 ICC 配置文件，它是 Rec.2020 Gamut with PQ Transfer 标准
  size_t icc_size;
  unsigned char *icc_data = read_icc_profile(icc_profile_path, &icc_size);
  if (!icc_data) {
    fprintf(stderr, "无法读取 ICC 配置文件\n");
    return;
  }

  struct jpeg_compress_struct cinfo;
  struct jpeg_error_mgr jerr;
  FILE *outfile;
  JSAMPROW row_pointer[1];

  // 初始化 JPEG 压缩对象
  cinfo.err = jpeg_std_error(&jerr);
  jpeg_create_compress(&cinfo);

  if ((outfile = fopen(filename, "wb")) == NULL) {
    fprintf(stderr, "无法打开输出文件 %s\n", filename);
    free(icc_data);
    return;
  }
  jpeg_stdio_dest(&cinfo, outfile);

  // 设置图像参数
  cinfo.image_width = width;
  cinfo.image_height = height;
  cinfo.input_components = 3; // RGB
  cinfo.in_color_space = JCS_RGB;

  // 设置 JPEG 参数
  jpeg_set_defaults(&cinfo);
  jpeg_set_quality(&cinfo, quality, TRUE);

  // 8-bit 精度
  cinfo.data_precision = 8;
  cinfo.arith_code = FALSE;
  cinfo.optimize_coding = TRUE;

  // 开始压缩
  jpeg_start_compress(&cinfo, TRUE);

  // 写入 ICC 配置文件
  write_icc_profile(&cinfo, icc_data, icc_size);

  // 分配行缓冲区
  unsigned char *row_buffer = (unsigned char *)malloc(width * 3);
  if (!row_buffer) {
    fprintf(stderr, "内存分配失败\n");
    fclose(outfile);
    free(icc_data);
    jpeg_destroy_compress(&cinfo);
    return;
  }

  // 逐行处理图像
  while (cinfo.next_scanline < cinfo.image_height) {
    const fp16 *src_row = rgba_data + cinfo.next_scanline * width * 4;

    // 将 fp16 RGBA 转换为 8-bit RGB with PQ
    for (int x = 0; x < width; x++) {
      // 转换为 float
      float r = half_to_float(src_row[x * 4 + 0]);
      float g = half_to_float(src_row[x * 4 + 1]);
      float b = half_to_float(src_row[x * 4 + 2]);

      // 应用 PQ 曲线 (假设输入是归一化后的线性光值)
      r = pq_forward(r);
      g = pq_forward(g);
      b = pq_forward(b);

      // 转换为 8-bit
      row_buffer[x * 3 + 0] = (unsigned char)(r * 255.0f);
      row_buffer[x * 3 + 1] = (unsigned char)(g * 255.0f);
      row_buffer[x * 3 + 2] = (unsigned char)(b * 255.0f);
    }

    row_pointer[0] = row_buffer;
    jpeg_write_scanlines(&cinfo, row_pointer, 1);
  }

  // 完成压缩
  jpeg_finish_compress(&cinfo);
  fclose(outfile);
  free(row_buffer);
  free(icc_data);
  jpeg_destroy_compress(&cinfo);
}

int main() {
  // 示例用法
  const int width = 480;
  const int height = 480;

  // 分配并初始化 RGBA Half 数据 (示例)
  RGBAColor *rgba_data =
      (RGBAColor *)malloc(width * height * sizeof(RGBAColor));
  if (!rgba_data) {
    fprintf(stderr, "内存分配失败\n");
    return 1;
  }

  // macbook m2 pro 默认显示配置中 SDR=500, HDR=1600
  const float sdr_nits = 500.f;
  const float hdr_nits = 1600.f;
  const float max_nits = 10000.0f; // PQ 定义的最大亮度值

  // sdr 相对 hdr 的亮度，因为后面要用 PQ 转换函数，因此这里需要按照 max_nits 归一化
  const fp16 relative_brightness =sdr_nits/max_nits;
  RGBAColor sdr_white_color = {
      .r = relative_brightness, .g = relative_brightness, .b = relative_brightness, .a = 1.0f};
  // 填充示例数据 (这里填充简单的渐变)
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      size_t index = y * width + x;
      // 为了方便对比，上半部分是最亮的 HDR 白色，下半部分是 SDR 白色
      if (y < height / 2) {
        // 1 表示使用 HDR 的最高亮度
        rgba_data[index] = {
            .r = 1.f,
            .g = 1.f,
            .b = 1.f,
            .a = 1.f,
        };
      } else {
        rgba_data[index] = sdr_white_color;
      }
    }
  }

  // 保存为 JPEG 并应用 Rec.2020 PQ
  save_half_rgba_as_jpeg_with_pq("hdr_rec2020_pq.jpg", (fp16*)rgba_data, width,
                                 height, 95,
                                 "rec-2020-pq.icc");

  free(rgba_data);
  return 0;
}
