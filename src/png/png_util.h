#include <iostream>
#include <vector>
#include <png.h>

bool ReadRGBA_PNG(const char* filename, std::vector<unsigned char>& image,
                 size_t& width, size_t& height) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        std::cerr << "Could not open file " << filename << std::endl;
        return false;
    }

    // 检查PNG签名
    png_byte header[8];
    fread(header, 1, 8, fp);
    if (png_sig_cmp(header, 0, 8)) {
        std::cerr << "File is not a valid PNG" << std::endl;
        fclose(fp);
        return false;
    }

    // 初始化libpng
    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png_ptr) {
        fclose(fp);
        return false;
    }

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr) {
        png_destroy_read_struct(&png_ptr, NULL, NULL);
        fclose(fp);
        return false;
    }

    if (setjmp(png_jmpbuf(png_ptr))) {
        png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
        fclose(fp);
        return false;
    }

    png_init_io(png_ptr, fp);
    png_set_sig_bytes(png_ptr, 8);
    png_read_info(png_ptr, info_ptr);

    // 获取图像信息
    width = png_get_image_width(png_ptr, info_ptr);
    height = png_get_image_height(png_ptr, info_ptr);
    png_byte color_type = png_get_color_type(png_ptr, info_ptr);
    png_byte bit_depth = png_get_bit_depth(png_ptr, info_ptr);

    // 确认确实是RGBA格式
    if (color_type != PNG_COLOR_TYPE_RGBA) {
        std::cerr << "Expected RGBA PNG, but got color type: " << (int)color_type << std::endl;
        png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
        fclose(fp);
        return false;
    }

    // 确保是8位每通道
    if (bit_depth == 16) {
        png_set_strip_16(png_ptr);
    }

    png_read_update_info(png_ptr, info_ptr);

    // 分配行指针
    png_bytep* row_pointers = (png_bytep*)malloc(sizeof(png_bytep) * height);
    const png_size_t rowbytes = png_get_rowbytes(png_ptr, info_ptr);

    // 一次性分配所有图像数据
    image.resize(rowbytes * height);

    for (unsigned long y = 0; y < height; y++) {
        row_pointers[y] = &image[y * rowbytes];
    }

    // 读取图像数据
    png_read_image(png_ptr, row_pointers);
    png_read_end(png_ptr, NULL);

    // 清理
    free(row_pointers);
    png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
    fclose(fp);
    return true;
}
