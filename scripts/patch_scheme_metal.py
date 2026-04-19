#!/usr/bin/env python3
"""幂等地把 Xcode scheme 的 <LaunchAction> 里 4 项 Metal 诊断选项全部反勾选。

Xcode scheme XML 中这 4 项的语义并不一致,必须区别处理:

  | UI 选项                  | 属性名                         | "反勾选"做法              |
  |--------------------------|--------------------------------|---------------------------|
  | Metal API Validation     | enableGPUValidationMode        | 设为 "1"(Xcode 的默认 off)|
  | Metal Shader Validation  | enableGPUShaderValidationMode  | 移除属性(存在即勾选)       |
  | Show Graphics Overview   | showGraphicsOverview           | 移除属性(存在即勾选)       |
  | Log Graphics Overview    | logGraphicsOverview            | 移除属性(存在即勾选)       |

在 "Designed for iPhone on Mac" 上运行时,启用这些诊断会让 Vision 内部对
shared-storage 的 Metal 纹理调用 synchronizeResource 触发断言崩溃。

用法: patch_scheme_metal.py <path-to-xcscheme>
"""
import re
import sys
from pathlib import Path

# 要显式写入固定值的属性(API Validation: "1" 就是 off,也是 Xcode 默认写法)
SET_ATTRS = {
    "enableGPUValidationMode": "1",
}

# 要移除的属性(存在即表示 on,删掉才等于反勾选)
REMOVE_ATTRS = (
    "enableGPUShaderValidationMode",
    "showGraphicsOverview",
    "logGraphicsOverview",
)


def main(path_str: str) -> int:
    path = Path(path_str)
    if not path.is_file():
        print(f"[patch_scheme_metal] 未找到 scheme: {path}", file=sys.stderr)
        return 1

    src = path.read_text(encoding="utf-8")
    match = re.search(r"<LaunchAction\b[^>]*>", src, flags=re.DOTALL)
    if not match:
        print("[patch_scheme_metal] scheme 中没有 <LaunchAction>,跳过")
        return 0

    block = match.group(0)
    new_block = block

    # 1) 覆盖/插入固定值的属性
    for key, val in SET_ATTRS.items():
        attr_re = re.compile(r"\b" + re.escape(key) + r'\s*=\s*"[^"]*"')
        replacement = f'{key} = "{val}"'
        if attr_re.search(new_block):
            new_block = attr_re.sub(replacement, new_block)
        else:
            new_block = new_block.rstrip(">").rstrip() + f"\n      {replacement}>"

    # 2) 删除表示"开启"的属性(以及紧邻的空白/换行,避免残留空行)
    for key in REMOVE_ATTRS:
        attr_re = re.compile(r"\s*" + re.escape(key) + r'\s*=\s*"[^"]*"')
        new_block = attr_re.sub("", new_block)

    if new_block == block:
        print("[patch_scheme_metal] 4 项 Metal 诊断已全部处于关闭状态")
        return 0

    path.write_text(src.replace(block, new_block, 1), encoding="utf-8")
    print("[patch_scheme_metal] 已反勾 scheme 中全部 4 项 Metal 诊断")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: patch_scheme_metal.py <path-to-xcscheme>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
