#import "hdr_layer.h"

#include "png/png_util.h"

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

typedef __fp16 fp16;
struct __attribute__((packed)) RGBAColor {
  fp16 r;
  fp16 g;
  fp16 b;
  fp16 a;
};

@implementation HDRContentLayer

- (instancetype)init {
  self = [super init];
  if (self) {
    // 启用扩展动态范围内容
    self.contentsFormat = kCAContentsFormatRGBA16Float;
    self.wantsExtendedDynamicRangeContent = YES;
    self.colorIndex = 0;
    // [self startContentChange];
  }
  return self;
}

- (void)layoutSublayers {
  NSLog(@"layoutSublayers");
  [super layoutSublayers];
  [self updateContent];
}

- (void)startContentChange {
  [self updateContent];
  // 使用定时器每隔1秒更新
  [NSTimer scheduledTimerWithTimeInterval:10
                                   target:self
                                 selector:@selector(updateContent)
                                 userInfo:nil
                                  repeats:YES];
}

- (void)updateContent {
  NSLog(@"set contents begin");
  // 创建HDR PixelBuffer
  // CVPixelBufferRef pixelBuffer =
  //     [self createHDRPixelBufferWithSize:self.bounds.size];
  CVPixelBufferRef pixelBuffer =
      // [self createBGRAPixelBufferWithSize:self.bounds.size];
      [self createF16PixelBufferWithSize:self.bounds.size];

  if (pixelBuffer) {
    self.contents = CFBridgingRelease(CVBufferRetain(pixelBuffer));
    NSLog(@"set contents end");
  }
}

- (CVPixelBufferRef)createBGRAPixelBufferWithSize:(CGSize)size
    CF_RETURNS_RETAINED {
  // if (size.width <= 0 || size.height <= 0) {
  //   NSLog(@"Invalid size: %@", NSStringFromSize(size));
  //   return nullptr;
  // }

  size_t width = size.width;
  size_t height = size.height;
  unsigned char *rgba_data;
  {
    const char *filename = "rgba.png";
    std::vector<unsigned char> image;
    unsigned long img_width, img_height;
    if (!ReadRGBA_PNG(filename, image, img_width, img_height)) {
      return nullptr;
    }

    std::cout << "Loaded RGBA PNG: " << img_width << "x" << img_height
              << std::endl;
    rgba_data = image.data();
    width = img_width;
    height = img_height;
  }

  CVPixelBufferRef pixelBuffer = NULL;

  NSDictionary *attributes = @{
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
    (id)kCVPixelBufferOpenGLCompatibilityKey : @YES,
    (id)kCVPixelBufferMetalCompatibilityKey : @YES
  };

  // 创建BGRA格式的像素缓冲区
  CVReturn status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      (__bridge CFDictionaryRef)attributes, &pixelBuffer);

  if (status != kCVReturnSuccess) {
    std::cerr << "CVPixelBufferCreate failed: " << status << std::endl;
    return NULL;
  }

  // 锁定缓冲区进行写入
  CVPixelBufferLockBaseAddress(pixelBuffer, 0);

  void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

  // 将RGBA转换为BGRA
  unsigned char *src = rgba_data;
  unsigned char *dst = (unsigned char *)baseAddress;

  for (size_t y = 0; y < height; y++) {
    unsigned char *src_row = src + y * width * 4;
    unsigned char *dst_row = dst + y * bytesPerRow;

    for (size_t x = 0; x < width; x++) {
      dst_row[x * 4 + 0] = src_row[x * 4 + 2]; // B
      dst_row[x * 4 + 1] = src_row[x * 4 + 1]; // G
      dst_row[x * 4 + 2] = src_row[x * 4 + 0]; // R
      dst_row[x * 4 + 3] = src_row[x * 4 + 3]; // A
    }
  }

  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
  return pixelBuffer;
}

- (CVPixelBufferRef)createF16PixelBufferWithSize:(CGSize)size
    CF_RETURNS_RETAINED {
  if (size.width <= 0 || size.height <= 0) {
    NSLog(@"Invalid size: %@", NSStringFromSize(size));
    // return nullptr;
  }

  size_t width = size.width;
  size_t height = size.height;
  unsigned char *rgba_data;
  {
    const char *filename = "rgba.png";
    std::vector<unsigned char> image;
    unsigned long img_width, img_height;
    if (!ReadRGBA_PNG(filename, image, img_width, img_height)) {
      return nullptr;
    }

    std::cout << "Loaded RGBA PNG: " << img_width << "x" << img_height
              << std::endl;
    rgba_data = image.data();
    width = img_width;
    height = img_height;
  }

  CVPixelBufferRef pixelBuffer = NULL;

  NSDictionary *attributes = @{
    (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_64RGBAHalf),
    (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
  };

  // 创建BGRA格式的像素缓冲区
  CVReturn status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_64RGBAHalf,
      (__bridge CFDictionaryRef)attributes, &pixelBuffer);

  if (status != kCVReturnSuccess) {
    NSLog(@"Failed to create pixel buffer: %d", status);
    return nullptr;
  }

  // 锁定PixelBuffer进行写入
  status = CVPixelBufferLockBaseAddress(pixelBuffer, 0);
  if (status != kCVReturnSuccess) {
    NSLog(@"Failed to lock pixel buffer: %d", status);
    CFRelease(pixelBuffer);
    return nullptr;
  }

  // 获取PixelBuffer数据指针
  void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
  width = CVPixelBufferGetWidth(pixelBuffer);
  height = CVPixelBufferGetHeight(pixelBuffer);

  RGBAColor *pixels = (RGBAColor *)baseAddress;
  size_t pixelsPerRow = bytesPerRow / sizeof(RGBAColor);

  // 填充背景色
  for (size_t y = 0; y < height; y++) {
    for (size_t x = 0; x < width; x++) {
      size_t index = y * pixelsPerRow + x;
      // 为了方便对比，上半部分是 HDR 颜色，下半部分是 SDR 颜色
      if (y < height / 2) {
        pixels[index] = {
            .r = 5.0f,
            .g = 5.0f,
            .b = 5.0f,
            .a = 1.0f,
        };
      } else {
        pixels[index] = {
            .r = 1.0f,
            .g = 1.0f,
            .b = 1.0f,
            .a = 1.0f,
        };
      }
    }
  }

  // void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
  // size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

  // // 将RGBA转换为BGRA
  // unsigned char *src = rgba_data;
  // unsigned char *dst = (unsigned char *)baseAddress;

  // for (size_t y = 0; y < height; y++) {
  //   unsigned char *src_row = src + y * width * 4;
  //   unsigned char *dst_row = dst + y * bytesPerRow;

  //   for (size_t x = 0; x < width; x++) {
  //     dst_row[x * 4 + 0] = src_row[x * 4 + 2]; // B
  //     dst_row[x * 4 + 1] = src_row[x * 4 + 1]; // G
  //     dst_row[x * 4 + 2] = src_row[x * 4 + 0]; // R
  //     dst_row[x * 4 + 3] = src_row[x * 4 + 3]; // A
  //   }
  // }

  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
  return pixelBuffer;
}

- (CVPixelBufferRef)createHDRPixelBufferWithSize:(CGSize)size
    CF_RETURNS_RETAINED {
  if (size.width <= 0 || size.height <= 0) {
    NSLog(@"Invalid size: %@", NSStringFromSize(size));
    return nullptr;
  }

  // 创建超亮颜色 (RGB值大于1.0表示HDR亮度)
  // 普通颜色的5倍亮度, 实际能达到的最高亮度受显示器硬件以及系统配置中的 HDR/SDR
  // 比值决定
  __fp16 brightness = 5.f;
  struct __attribute__((packed)) RGBAColor {
    __fp16 r;
    __fp16 g;
    __fp16 b;
    __fp16 a;
  } colors[] = {
      {brightness, brightness, brightness, 1.0f}, // 超亮白
      {brightness, 0.0f, 0.0f, 1.0f},             // 超亮红
      {0.0f, brightness, 0.0f, 1.0f},             // 超亮绿
      {0.0f, 0.0f, brightness, 1.0f}              // 超亮蓝
  };
  RGBAColor color = colors[self.colorIndex % 4];
  NSLog(@"color: %f, %f, %f, %f", color.r, color.g, color.b, color.a);
  self.colorIndex++;

  NSDictionary *pixelBufferAttributes = @{
    (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_64RGBAHalf),
    (id)kCVPixelBufferWidthKey : @(size.width),
    (id)kCVPixelBufferHeightKey : @(size.height),
    (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
  };

  // 创建PixelBuffer
  CVPixelBufferRef pixelBuffer;
  CVReturn status = CVPixelBufferCreate(
      kCFAllocatorDefault, size.width, size.height,
      kCVPixelFormatType_64RGBAHalf,
      (__bridge CFDictionaryRef)pixelBufferAttributes, &pixelBuffer);

  if (status != kCVReturnSuccess) {
    NSLog(@"Failed to create pixel buffer: %d", status);
    return nullptr;
  }

  // 锁定PixelBuffer进行写入
  status = CVPixelBufferLockBaseAddress(pixelBuffer, 0);
  if (status != kCVReturnSuccess) {
    NSLog(@"Failed to lock pixel buffer: %d", status);
    CFRelease(pixelBuffer);
    return nullptr;
  }

  // 获取PixelBuffer数据指针
  void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
  size_t width = CVPixelBufferGetWidth(pixelBuffer);
  size_t height = CVPixelBufferGetHeight(pixelBuffer);

  RGBAColor *pixels = (RGBAColor *)baseAddress;
  size_t pixelsPerRow = bytesPerRow / sizeof(RGBAColor);

  // 填充背景色
  for (size_t y = 0; y < height; y++) {
    for (size_t x = 0; x < width; x++) {
      size_t index = y * pixelsPerRow + x;
      // 为了方便对比，上半部分是 HDR 颜色，下半部分是 SDR 颜色
      if (y < height / 2) {
        pixels[index] = color;
      } else {
        pixels[index] = {
            .r = (__fp16)(color.r / brightness),
            .g = (__fp16)(color.g / brightness),
            .b = (__fp16)(color.b / brightness),
            .a = color.a,
        };
      }
    }
  }

  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
  return pixelBuffer;
}

@end
