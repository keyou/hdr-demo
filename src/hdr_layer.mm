#import "hdr_layer.h"

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

@implementation HDRContentLayer

- (instancetype)init {
  self = [super init];
  if (self) {
    // 启用扩展动态范围内容
    self.contentsFormat = kCAContentsFormatRGBA16Float;
    self.wantsExtendedDynamicRangeContent = YES;
    self.colorIndex = 0;
    [self startContentChange];
  }
  return self;
}

- (void)startContentChange {
  // 使用定时器每隔1秒更新
  [NSTimer scheduledTimerWithTimeInterval:1
                                   target:self
                                 selector:@selector(updateContent)
                                 userInfo:nil
                                  repeats:YES];
}

- (void)updateContent {
  NSLog(@"set contents begin");
  // 创建HDR PixelBuffer
  CVPixelBufferRef pixelBuffer =
      [self createHDRPixelBufferWithSize:self.bounds.size];

  if (pixelBuffer) {
    self.contents = CFBridgingRelease(CVBufferRetain(pixelBuffer));
    NSLog(@"set contents end");
  }
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
