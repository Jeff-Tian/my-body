# 本地发版（`make release`）完整指南

只把 **App Store 元数据 + 截图** 推送到 App Store Connect。不打包、不提审。

```bash
make release
```

Makefile 会自动载入项目根目录下的 `.env`，无需手动 `source`。

---

## 一次性准备（只做一次，之后永不再碰）

### 推荐：一条命令搞定（`make install_asc_key`）

```bash
make install_asc_key
```

它会：

1. 打开 ASC API Keys 页面（默认浏览器）
2. 监听 `~/Downloads`，等你点"下载"按钮后自动捕获 `AuthKey_XXXXXXXXXX.p8`
3. 移动到 `~/.appstoreconnect/` 并 `chmod 600`
4. 从文件名解析 **Key ID**
5. 交互式问你 **Issuer ID**（UUID 格式，从页面顶部复制）
6. 写入 / 更新项目根目录的 `.env`
7. 最后跑一次 `make check_asc_env` 验证

你只需要在浏览器里**点一下"下载"按钮**，其余全自动。

**如果 .p8 你已经下好了**：

```bash
make install_asc_key ASC_P8=/path/to/AuthKey_SMNH29AFVG.p8
```

之后直接 `make release` 即可发版。

---

### 手动（若 `install_asc_key` 不适用）

<details>
<summary>展开手动步骤</summary>

### Step 1. 创建 App Store Connect API Key

这是整个流程**唯一**无法自动化的步骤——`.p8` 私钥文件只能下载一次。

1. 登录 <https://appstoreconnect.apple.com>
2. 左侧栏 → **Users and Access**
3. 顶部 Tab → **Integrations**
4. 左侧 → **App Store Connect API** → **Team Keys**
5. 点右上角 **"+"** → **Generate API Key**
   - Name: `my-body local release`（随意）
   - Access: **App Manager**（⚠️ `Developer` 级别权限不够，`produce`/`deliver` 会失败）
6. 点 **Generate**，页面会出现一行：
   ```
   Download API Key  ←  只能点一次，下载后 Apple 不会再给
   ```
7. 下载得到 `AuthKey_XXXXXXXXXX.p8`。**建议放到 `~/.appstoreconnect/` 这类固定位置**：
   ```bash
   mkdir -p ~/.appstoreconnect
   mv ~/Downloads/AuthKey_*.p8 ~/.appstoreconnect/
   chmod 600 ~/.appstoreconnect/AuthKey_*.p8   # 防止意外被读
   ```
8. 记下三个值：
   - 表格里的 **Key ID**（10 位大写字母数字，例 `ABCDE12345`）
   - 页面顶部的 **Issuer ID**（UUID 格式，例 `69a6de7f-xxxx-xxxx-xxxx-xxxxxxxxxxxx`）
   - `.p8` 的**绝对路径**

### Step 2. 填 `.env`

```bash
cp .env.example .env     # 已存在则跳过
$EDITOR .env
```

把 Step 1 记下的三个值填入对应字段：

```bash
APP_STORE_CONNECT_KEY_IDENTIFIER=ABCDE12345
APP_STORE_CONNECT_ISSUER_ID=69a6de7f-xxxx-xxxx-xxxx-xxxxxxxxxxxx
APP_STORE_CONNECT_PRIVATE_KEY_PATH=/Users/YOUR_NAME/.appstoreconnect/AuthKey_ABCDE12345.p8
```

⚠️ `.env` 与 `.p8` 都在 `.gitignore` 中，**切勿提交**。`.p8` 最好放在仓库之外。

### Step 3. 跑一次 `make release`

```bash
make release
```

首次运行会额外触发一件事：**fastlane `produce` 在 ASC 自动创建 App 记录**，使用如下参数（与代码约定一致）：

| 字段 | 值 | 出处 |
|---|---|---|
| Bundle ID | `brickverse.MyBodyApp` | `project.yml` |
| App Name | `我的身体` | `fastlane/Fastfile` `APP_NAME` |
| Primary Language | Simplified Chinese | `fastlane/Fastfile` `PRIMARY_LANG`，**一经设定不可改** |
| SKU | `MyBody` | `fastlane/Fastfile` `APP_SKU` |
| Platform | iOS only | `fastlane/Fastfile` |
| App Version | `1.0` | `fastlane/Fastfile` |

第二次起 `produce` 检测到 App 已存在，会直接跳过（幂等）。

</details>

---

## `make release` 内部步骤

```
make release
├── check_asc_env       # 校验 .env 里 API Key 三元组 + .p8 文件存在
├── screenshots         # fastlane snapshot：模拟器跑 UI 测试生成截图
└── push_metadata
    ├── ensure_app_on_asc  # fastlane produce：ASC 建 App（幂等）
    └── upload_to_app_store # fastlane deliver：推文案 + 截图
                            # skip_binary_upload: true
                            # submit_for_review: false
```

每步单独运行：

```bash
make check_asc_env       # 只做校验
make screenshots         # 只生成截图
make push_metadata       # 只推送（跳过截图重跑）
```

## 可选开关

```bash
SKIP_SNAPSHOT=1 make release       # 跳过截图重跑（使用 fastlane/screenshots 中已有文件）
SKIP_METADATA=1 make release       # 只推截图
SKIP_SCREENSHOTS=1 make release    # 只推文案
```

## 管理 App Store 文案（description / keywords / release notes…）

`make release` 首次运行后，ASC 里的 App 已创建但文案为空。要在本地用 git 管理文案：

```bash
cd fastlane
bundle exec fastlane deliver download_metadata \
  --app_identifier brickverse.MyBodyApp --force
```

这会把 ASC 上的现有文案拉到 `fastlane/metadata/<lang>/*.txt`：

```
fastlane/metadata/
├── zh-Hans/
│   ├── name.txt
│   ├── subtitle.txt
│   ├── description.txt
│   ├── keywords.txt
│   ├── release_notes.txt
│   ├── promotional_text.txt
│   ├── marketing_url.txt
│   ├── privacy_url.txt
│   └── support_url.txt
└── review_information/
```

编辑 `description.txt` 等后 `make release` 即推送。

## 常见问题

### Q: `produce` 报错 "App Name is not available"

App 名字已被别人占用。修改 `fastlane/Fastfile` 里的 `APP_NAME` 常量后重试。ASC 要求 App Name 全球唯一。

### Q: `produce` 报错 "Bundle ID is not available"

两种可能：
1. Bundle ID 已属于别的开发者账号 → 改 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER`。
2. Bundle ID 在 Developer Portal 存在但 ASC 没绑过 → 正常，`produce` 会自动绑定，报错往往是网络或权限问题，重试一次通常 OK。

### Q: `upload_to_app_store` 提示 missing screenshots

ASC 要求每个**追加的**本地化都提供至少一张对应尺寸的截图。如果你在 ASC 手动加了 English 语言但 `fastlane/screenshots/en-US/` 是空的 → 跑 `SKIP_METADATA=1 make release` 会失败。临时方案：从 ASC 删掉 English 本地化，或给 `Snapfile.languages` 加上 `en-US` 并录英文截图。

### Q: 能自动上传 IPA 到 TestFlight 吗？

当前不行。这个 Makefile 专注元数据 + 截图，不做构建签名。TestFlight 上传依赖证书 + provisioning profile + IPA，属于独立链路；参考 `SimpleMultiApp/Makefile` 里的 `push_testflight` lane 模板可按需追加。

## 不需要做的事（避免走弯路）

- ❌ **不用**在 ASC 手动创建 App（`produce` 自动做）
- ❌ **不用**手动 `source .env`（Makefile 自动载入）
- ❌ **不用**预先在 ASC 建截图占位（`overwrite_screenshots: true` 会覆盖）
- ❌ **不用**先上传一次二进制才能推文案（只要 App 记录存在即可）
