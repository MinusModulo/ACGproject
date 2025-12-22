#!/usr/bin/env python3
"""
处理铁锈纹理：将浅灰色背景（接近 #c1c5c5）变成透明，只保留铁锈色（接近 #995a2b）
"""

import sys
from PIL import Image
import numpy as np

def rgb_to_lab(rgb):
    """将 RGB 转换为 LAB 颜色空间（用于更好的颜色距离计算）"""
    # 简化的 RGB 到 LAB 转换
    # 实际应该使用完整的转换，这里用简化的欧氏距离
    return rgb

def color_distance(color1, color2):
    """计算两个颜色之间的距离（使用加权欧氏距离）"""
    r1, g1, b1 = color1
    r2, g2, b2 = color2
    
    # 使用加权欧氏距离（对绿色更敏感，符合人眼感知）
    delta_r = float(r1) - float(r2)
    delta_g = float(g1) - float(g2)
    delta_b = float(b1) - float(b2)
    
    # 加权距离（对绿色更敏感）
    distance = np.sqrt(
        2.0 * delta_r * delta_r +
        4.0 * delta_g * delta_g +
        3.0 * delta_b * delta_b
    )
    return distance

def hex_to_rgb(hex_color):
    """将十六进制颜色转换为 RGB"""
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def process_rust_texture(input_path, output_path, 
                        background_color='#c1c5c5', 
                        rust_color='#995a2b',
                        background_threshold=40.0,
                        rust_threshold=60.0):
    """
    处理铁锈纹理
    
    参数:
        input_path: 输入图片路径
        output_path: 输出图片路径
        background_color: 背景颜色（十六进制）
        rust_color: 铁锈颜色（十六进制）
        background_threshold: 背景颜色阈值（小于此距离的像素变为透明）
        rust_threshold: 铁锈颜色阈值（用于识别铁锈区域）
    """
    # 打开图片
    img = Image.open(input_path)
    
    # 转换为 RGBA 模式（如果还不是）
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # 转换为 numpy 数组
    img_array = np.array(img)
    
    # 转换目标颜色
    bg_rgb = hex_to_rgb(background_color)
    rust_rgb = hex_to_rgb(rust_color)
    
    print(f"背景颜色 (RGB): {bg_rgb}")
    print(f"铁锈颜色 (RGB): {rust_rgb}")
    print(f"处理图片: {input_path}")
    print(f"图片尺寸: {img.size}")
    print(f"背景阈值: {background_threshold}")
    print(f"铁锈阈值: {rust_threshold}")
    
    # 采样一些像素来调试
    sample_pixels = [
        img_array[0, 0, :3],
        img_array[512, 512, :3],
        img_array[1023, 1023, :3],
    ]
    print("\n采样像素颜色:")
    for i, px in enumerate(sample_pixels):
        bg_d = color_distance(px, bg_rgb)
        rust_d = color_distance(px, rust_rgb)
        print(f"  像素 {i}: RGB{tuple(px)} -> 背景距离: {bg_d:.1f}, 铁锈距离: {rust_d:.1f}")
    
    # 创建新的 alpha 通道
    alpha = img_array[:, :, 3].copy()
    
    # 统计信息
    total_pixels = img_array.shape[0] * img_array.shape[1]
    transparent_count = 0
    rust_count = 0
    
    # 使用向量化操作提高性能
    pixels = img_array[:, :, :3].astype(np.float32)  # 转换为 float 避免溢出
    
    # 计算所有像素到背景颜色的距离（使用欧氏距离）
    bg_diff = pixels - np.array(bg_rgb, dtype=np.float32)
    bg_distances = np.sqrt(
        2.0 * bg_diff[:, :, 0] ** 2 +
        4.0 * bg_diff[:, :, 1] ** 2 +
        3.0 * bg_diff[:, :, 2] ** 2
    )
    
    # 计算所有像素到铁锈颜色的距离
    rust_diff = pixels - np.array(rust_rgb, dtype=np.float32)
    rust_distances = np.sqrt(
        2.0 * rust_diff[:, :, 0] ** 2 +
        4.0 * rust_diff[:, :, 1] ** 2 +
        3.0 * rust_diff[:, :, 2] ** 2
    )
    
    # 创建 alpha 通道
    # 策略：比较到背景和铁锈的距离，如果更接近背景则透明，否则保留
    
    # 初始化 alpha
    alpha = np.full(img_array.shape[:2], 255, dtype=np.uint8)
    
    # 如果非常接近背景颜色（在阈值内），设为透明
    very_close_to_bg = bg_distances < background_threshold
    alpha[very_close_to_bg] = 0
    
    # 如果非常接近铁锈颜色（在阈值内），保持不透明
    very_close_to_rust = rust_distances < rust_threshold
    alpha[very_close_to_rust] = 255
    
    # 对于其他像素，比较哪个更接近
    # 如果更接近背景，设为透明；如果更接近铁锈，保持不透明
    other_pixels = ~(very_close_to_bg | very_close_to_rust)
    if np.any(other_pixels):
        # 比较相对距离：如果到背景的距离 < 到铁锈的距离，则更接近背景
        closer_to_bg_mask = bg_distances[other_pixels] < rust_distances[other_pixels]
        alpha[other_pixels] = np.where(closer_to_bg_mask, 0, 255)
    
    # 统计
    transparent_count = np.sum(alpha == 0)
    rust_count = np.sum((alpha > 0) & (rust_distances < rust_threshold))
    
    # 额外统计：非常接近背景/铁锈的像素数
    very_close_bg_count = np.sum(very_close_to_bg)
    very_close_rust_count = np.sum(very_close_to_rust)
    print(f"非常接近背景: {very_close_bg_count} ({very_close_bg_count/total_pixels*100:.1f}%)")
    print(f"非常接近铁锈: {very_close_rust_count} ({very_close_rust_count/total_pixels*100:.1f}%)")
    
    # 调试：检查距离分布
    print(f"\n距离统计:")
    print(f"  背景距离 - 最小: {np.min(bg_distances):.1f}, 最大: {np.max(bg_distances):.1f}, 平均: {np.mean(bg_distances):.1f}")
    print(f"  铁锈距离 - 最小: {np.min(rust_distances):.1f}, 最大: {np.max(rust_distances):.1f}, 平均: {np.mean(rust_distances):.1f}")
    
    # 应用 alpha 通道
    img_array[:, :, 3] = alpha.astype(np.uint8)
    
    # 创建新图片
    result_img = Image.fromarray(img_array, 'RGBA')
    
    # 保存结果
    result_img.save(output_path, 'PNG')  # 使用 PNG 格式以支持透明度
    
    # 打印统计信息
    print(f"\n处理完成！")
    print(f"总像素数: {total_pixels}")
    print(f"透明像素: {transparent_count} ({transparent_count/total_pixels*100:.1f}%)")
    print(f"铁锈像素: {rust_count} ({rust_count/total_pixels*100:.1f}%)")
    print(f"其他像素: {total_pixels - transparent_count - rust_count} ({(total_pixels - transparent_count - rust_count)/total_pixels*100:.1f}%)")
    print(f"输出文件: {output_path}")

if __name__ == '__main__':
    # 默认参数
    input_file = 'build/src/Debug/Metal053B_1K-JPG/Metal053B_1K-JPG_Color.jpg'
    output_file = 'build/src/Debug/Metal053B_1K-JPG/Metal053B_1K-JPG_Color_Masked.png'
    
    # 从命令行参数获取输入输出路径
    if len(sys.argv) >= 2:
        input_file = sys.argv[1]
    if len(sys.argv) >= 3:
        output_file = sys.argv[2]
    
    # 处理图片
    try:
        # 调整阈值参数以获得更好的效果
        # background_threshold: 越小越严格（只去除非常接近背景的颜色）
        # rust_threshold: 越大越宽松（保留更多铁锈相关的颜色）
        process_rust_texture(
            input_file,
            output_file,
            background_color='#c1c5c5',
            rust_color='#995a2b',
            background_threshold=30.0,  # 背景颜色阈值（只去除非常接近背景的颜色）
            rust_threshold=150.0  # 铁锈颜色阈值（保留更多铁锈相关颜色）
        )
        print("\n[SUCCESS] Processing completed!")
    except Exception as e:
        print(f"\n[ERROR] {e}")
        sys.exit(1)

