cmake_minimum_required(VERSION 3.15)
project(hdr_demo)

set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_C_COMPILER "clang")
set(CMAKE_CXX_COMPILER "clang++")

enable_language(OBJCXX)

# 依赖 libjpeg-turbo 库, 使用 brew install libjpeg-turbo 安装
find_package(JPEG REQUIRED)
find_package(PNG REQUIRED)

set(BASEPATH "${CMAKE_SOURCE_DIR}")
include_directories("${BASEPATH}/src")

set(CMAKE_CXX_STANDARD 20)

add_executable(hdr_demo src/main.mm
  src/app_delegate.h src/app_delegate.mm
  src/hdr_layer.h src/hdr_layer.mm) # 一个 HDR 渲染演示程序，演示 HDR 内容如何被渲染
target_link_libraries(hdr_demo PRIVATE
  "-framework Cocoa"
  "-framework QuartzCore"
  "-framework Accelerate"
  "-framework CoreImage"
  "-framework ImageIO"
  "-framework CoreFoundation"
  JPEG::JPEG
  PNG::PNG)

# 一个用于生成 JPEG+ICC HDR 图片的工具，演示 HDR 图片的生成
add_executable(jpeg_util src/jpeg_hdr/jpeg_util.cc)
target_link_libraries(jpeg_util PRIVATE JPEG::JPEG)
