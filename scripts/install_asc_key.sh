#!/usr/bin/env bash
# install_asc_key.sh — 半自动化 ASC API Key 安装
#
# Apple 不允许通过 API 下载 .p8 文件，只能从 ASC 网页点一次性 "Download"。
# 本脚本处理下载之后的所有步骤：
#   1. 监听 ~/Downloads（可通过 DOWNLOADS_DIR 覆盖）直到 AuthKey_*.p8 出现
#   2. 移动到 ~/.appstoreconnect/（可通过 ASC_KEY_DIR 覆盖）
#   3. chmod 600
#   4. 从文件名提取 Key ID
#   5. 交互式询问 Issuer ID（若 .env 已有则直接复用）
#   6. 写入 / 更新 .env
#
# 用法：
#   make install_asc_key
# 或直接：
#   bash scripts/install_asc_key.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-$HOME/Downloads}"
ASC_KEY_DIR="${ASC_KEY_DIR:-$HOME/.appstoreconnect}"
ENV_FILE="$REPO_ROOT/.env"
ASC_URL="https://appstoreconnect.apple.com/access/integrations/api"

# 该变量在 Step 0 里可能被读取前就引用，先占位避免 set -u 报错
existing_key=""
existing_iss=""
existing_p8=""

# 注意：这里用 $'...' (ANSI-C quoting) 让变量存真正的 ESC 字节，
# 这样在 heredoc / cat 中也能被终端正确解释为颜色。
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
NC=$'\033[0m'

info()  { printf "%s[install_asc_key] %s%s\n" "$GREEN"  "$1" "$NC"; }
warn()  { printf "%s[install_asc_key] %s%s\n" "$YELLOW" "$1" "$NC"; }
error() { printf "%s[install_asc_key] %s%s\n" "$RED"    "$1" "$NC" >&2; }

# ---------------------------------------------------------------------------
# Step 0: 幂等快速通道
# 如果 .env 里三个字段都已正确填入、且 .p8 文件仍存在，直接返回。
# ---------------------------------------------------------------------------
if [ -f "$ENV_FILE" ] && [ $# -eq 0 ]; then
  existing_key=$(grep -E '^APP_STORE_CONNECT_KEY_IDENTIFIER='       "$ENV_FILE" | sed -E 's/^[^=]+=//' | tr -d '"' || true)
  existing_iss=$(grep -E '^APP_STORE_CONNECT_ISSUER_ID='            "$ENV_FILE" | sed -E 's/^[^=]+=//' | tr -d '"' || true)
  existing_p8=$( grep -E '^APP_STORE_CONNECT_PRIVATE_KEY_PATH='     "$ENV_FILE" | sed -E 's/^[^=]+=//' | tr -d '"' || true)
  if [ -n "$existing_key" ] && [ -n "$existing_iss" ] && [ -n "$existing_p8" ] && [ -f "$existing_p8" ]; then
    info ".env 已完整配置，.p8 文件也存在 → 跳过安装"
    printf "    Key ID  : %s\n" "$existing_key"
    printf "    Issuer  : %s\n" "$existing_iss"
    printf "    .p8 路径: %s\n" "$existing_p8"
    printf "如需重新安装，删除或清空 .env 中 APP_STORE_CONNECT_* 三行后再跑。\n"
    (cd "$REPO_ROOT" && make -s check_asc_env)
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Step 1: 找到 AuthKey_*.p8
# 优先顺序：
#   a) 命令行参数指定路径
#   b) ~/Downloads 里最新的 AuthKey_*.p8
#   c) 轮询 ~/Downloads 等待出现（最多 5 分钟）
# ---------------------------------------------------------------------------

find_latest_authkey() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  # shellcheck disable=SC2012
  ls -t "$dir"/AuthKey_*.p8 2>/dev/null | head -1 || return 1
}

p8_path=""

if [ $# -ge 1 ] && [ -n "$1" ]; then
  if [ -f "$1" ]; then
    p8_path="$1"
    info "使用命令行提供的 .p8：$p8_path"
  else
    error "指定的 .p8 文件不存在：$1"
    exit 64
  fi
fi

if [ -z "$p8_path" ]; then
  # 先看 .env 里已记录的路径（上次安装遗留的）
  if [ -n "$existing_p8" ] && [ -f "$existing_p8" ]; then
    info "沿用 .env 中记录的 .p8：$existing_p8"
    p8_path="$existing_p8"
  fi
fi

if [ -z "$p8_path" ]; then
  # 再看 ~/.appstoreconnect/ 里最新的（上次已移动过）
  asc_dir_existing=$(find_latest_authkey "$ASC_KEY_DIR" || true)
  if [ -n "$asc_dir_existing" ]; then
    info "在 $ASC_KEY_DIR 发现现成的 .p8：$(basename "$asc_dir_existing")"
    printf "直接使用它？ [Y/n] "
    read -r ans
    if [ -z "$ans" ] || [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      p8_path="$asc_dir_existing"
    fi
  fi
fi

if [ -z "$p8_path" ]; then
  # 再看 ~/Downloads 里已经有的
  existing=$(find_latest_authkey "$DOWNLOADS_DIR" || true)
  if [ -n "$existing" ]; then
    info "在 $DOWNLOADS_DIR 发现现成的 .p8：$(basename "$existing")"
    printf "直接使用它？ [Y/n] "
    read -r ans
    if [ -z "$ans" ] || [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      p8_path="$existing"
    fi
  fi
fi

if [ -z "$p8_path" ]; then
  # 打开浏览器，轮询等待下载
  info "打开 ASC API Keys 页面…"
  if command -v open >/dev/null 2>&1; then
    open "$ASC_URL" || true
  fi
  cat <<EOF

${YELLOW}请在浏览器中：${NC}
  1. 找到你的 API Key（权限为 App Manager）
  2. 点击右侧 "下载" 按钮，把 AuthKey_XXXXXXXXXX.p8 保存到：
       $DOWNLOADS_DIR
  3. 回到本终端（无需按任何键，下方脚本会自动侦测新文件）

已下载过的 Key 不能再次下载。如果该按钮已消失，请新建一个 API Key。
ASC 页面：$ASC_URL

EOF

  info "监听 $DOWNLOADS_DIR 中新出现的 AuthKey_*.p8… (Ctrl+C 取消)"
  timeout=300  # 5 分钟
  elapsed=0
  while [ $elapsed -lt $timeout ]; do
    latest=$(find_latest_authkey "$DOWNLOADS_DIR" || true)
    if [ -n "$latest" ]; then
      # 确认文件稳定（大小连续两次一致）
      size1=$(stat -f%z "$latest" 2>/dev/null || stat -c%s "$latest")
      sleep 1
      size2=$(stat -f%z "$latest" 2>/dev/null || stat -c%s "$latest")
      if [ "$size1" = "$size2" ] && [ "$size1" -gt 0 ]; then
        p8_path="$latest"
        info "检测到：$(basename "$p8_path") ($size1 bytes)"
        break
      fi
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  if [ -z "$p8_path" ]; then
    error "${timeout}s 内未检测到 AuthKey_*.p8，已放弃。"
    error "你可以下载后重跑本命令，或传路径：bash scripts/install_asc_key.sh /path/to/AuthKey.p8"
    exit 66
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: 解析 Key ID（从文件名）
# ---------------------------------------------------------------------------
filename="$(basename "$p8_path")"
key_id=$(echo "$filename" | sed -E 's/^AuthKey_([A-Z0-9]+)\.p8$/\1/')
if [ "$key_id" = "$filename" ] || [ -z "$key_id" ]; then
  error "无法从文件名解析 Key ID：$filename"
  error "预期文件名格式：AuthKey_ABCDE12345.p8"
  exit 65
fi
info "解析到 Key ID：$key_id"

# ---------------------------------------------------------------------------
# Step 3: 移到 ~/.appstoreconnect/ 并设权限
# ---------------------------------------------------------------------------
mkdir -p "$ASC_KEY_DIR"
chmod 700 "$ASC_KEY_DIR"
dest="$ASC_KEY_DIR/$filename"

if [ "$p8_path" = "$dest" ]; then
  info "文件已在目标位置：$dest"
else
  if [ -f "$dest" ]; then
    warn "目标位置已存在同名文件：$dest"
    printf "覆盖？ [y/N] "
    read -r ans
    if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
      info "保留原位置：$p8_path"
      dest="$p8_path"
    else
      mv "$p8_path" "$dest"
      info "已覆盖：$dest"
    fi
  else
    mv "$p8_path" "$dest"
    info "已移动：$p8_path → $dest"
  fi
fi
chmod 600 "$dest"
info "权限设为 600（仅所有者可读写）"

# ---------------------------------------------------------------------------
# Step 4: 从已有 .env 读取 Issuer ID，或交互式询问
# ---------------------------------------------------------------------------
existing_issuer=""
if [ -f "$ENV_FILE" ]; then
  existing_issuer=$(grep -E '^APP_STORE_CONNECT_ISSUER_ID=' "$ENV_FILE" | sed -E 's/^APP_STORE_CONNECT_ISSUER_ID=//' | tr -d '"' || true)
fi

issuer_id=""
if [ -n "$existing_issuer" ]; then
  info ".env 已有 Issuer ID：$existing_issuer"
  printf "沿用此值？ [Y/n] "
  read -r ans
  if [ -z "$ans" ] || [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    issuer_id="$existing_issuer"
  fi
fi

if [ -z "$issuer_id" ]; then
  cat <<EOF

${YELLOW}请从 ASC API Keys 页面顶部复制 Issuer ID（UUID 格式）：${NC}
  $ASC_URL

EOF
  printf "Issuer ID: "
  read -r issuer_id
  # 粗略格式校验：8-4-4-4-12 的十六进制
  if ! echo "$issuer_id" | grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
    error "Issuer ID 格式不正确（应为 UUID）：$issuer_id"
    exit 65
  fi
fi

# ---------------------------------------------------------------------------
# Step 5: 写入 / 更新 .env（保留其他行）
# ---------------------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$REPO_ROOT/.env.example" ]; then
    cp "$REPO_ROOT/.env.example" "$ENV_FILE"
    info "基于 .env.example 创建了 .env"
  else
    touch "$ENV_FILE"
    info "创建了空 .env"
  fi
fi

update_env_var() {
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    # macOS sed 要求 -i '' 参数
    if sed --version >/dev/null 2>&1; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    fi
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

update_env_var "APP_STORE_CONNECT_KEY_IDENTIFIER" "$key_id"
update_env_var "APP_STORE_CONNECT_ISSUER_ID"      "$issuer_id"
update_env_var "APP_STORE_CONNECT_PRIVATE_KEY_PATH" "$dest"

info "已更新 ${ENV_FILE}:"
grep -E '^APP_STORE_CONNECT_' "$ENV_FILE" | sed 's/^/    /'

# ---------------------------------------------------------------------------
# Step 6: 最终校验
# ---------------------------------------------------------------------------
info "运行 make check_asc_env 校验…"
if (cd "$REPO_ROOT" && make -s check_asc_env); then
  cat <<EOF

${GREEN}✅ ASC API Key 安装完成${NC}
  Key ID  : $key_id
  Issuer  : $issuer_id
  .p8 路径: $dest

下一步：
  ${GREEN}make release${NC}
EOF
else
  error "校验失败，请检查上方输出"
  exit 1
fi
