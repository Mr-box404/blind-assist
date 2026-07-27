# 此目录用于存放AI深度估计模型文件

# 需要下载的模型文件：midas_small.tflite
# 下载地址：https://github.com/isl-org/MiDaS/releases
#
# 或者使用Python转换脚本：
# 1. pip install tensorflow
# 2. 下载MiDaS small PyTorch模型
# 3. 使用AI Studio中的转换脚本转为TFLite格式
#
# 模型规格：
#   - 输入: [1, 256, 256, 3] float32
#   - 输出: [1, 256, 256, 1] float32
#   - 大小: 约24MB
