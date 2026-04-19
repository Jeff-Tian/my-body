# 多语言支持路线图

**当前状态**：App 主语言是**简体中文**（`zh-Hans`），这是 ASC 的 Primary Language，**一经设定不可修改**。所有其他语言都将作为 **Additional Localization** 追加，未翻译的内容回落到中文。

## 已完成的铺垫（无需再碰）

这些改动让未来加语言时"只需加料，不用重构"：

| 铺垫 | 位置 | 作用 |
|---|---|---|
| `developmentLanguage: "zh-Hans"` | `project.yml` | pbxproj 里 `developmentRegion = zh-Hans`；Xcode 自动加英文时不会误把源语言改成 `en` |
| `MyBody/Localizable.xcstrings` | 源码根 | 空的 String Catalog，`sourceLanguage=zh-Hans`；Xcode 编译时会**自动抽取**代码里 `Text("xxx")`、`String(localized:)` 的字符串填进去，无需手动维护 |
| `languages(["zh-Hans"])` 数组形式 | `fastlane/Snapfile` | 新增语言只要在数组里加一项，不动架构 |
| Primary Language = Simplified Chinese | ASC（首次 `make release` 自动设定） | 所有其他语言都以中文为 fallback |

## 加一个新语言（比如英文）需要做什么

### 1. App 内 UI 字符串（Xcode 层）

1. Xcode 打开 `MyBody.xcodeproj`，双击 `Localizable.xcstrings`。
2. 右侧语言列点 **"+"** → 选 **English**。
3. Xcode 会列出所有源字符串，手工（或用翻译工具 / Xcode "Generate with AI"）填英文值。
4. 对于 `Info.plist` 里的权限说明（`NSCameraUsageDescription` 等），同理在 String Catalog 里翻译 key `NSCameraUsageDescription` 即可；iOS 17+ 的 `xcstrings` 支持 Info.plist 键。

**写代码时注意**：
- `Text("趋势")` 会被自动抽成 key。
- 带变量的要用 `String(localized: "已记录 \(count) 条")`，而不是 `Text("已记录 \(count) 条")`（后者 Xcode 可能识别不出参数化模板）。
- **不要**写 `Text(record.label)` 然后期望 iOS 翻译它——`record.label` 是运行时数据，不会被 String Catalog 抽取。

### 2. 截图（fastlane snapshot 层）

1. 改 `fastlane/Snapfile`：
   ```ruby
   languages(["zh-Hans", "en-US"])
   ```
2. 在 `MyBodyUITests/SnapshotScreenshotsUITests.swift` 里**不需要改代码**——fastlane 的 `SnapshotHelper.swift` 会根据每个 language 启动前注入 `AppleLanguages` 参数，App 自动切到对应语言跑一次截图。
3. 跑：
   ```bash
   make screenshots
   ```
4. 产物：`fastlane/screenshots/zh-Hans/*.png` + `fastlane/screenshots/en-US/*.png`。

### 3. App Store 文案（fastlane deliver 层）

1. 在 ASC App Information → Localizations → **"+"** → 选 English。
2. 本地重新拉一份元数据骨架：
   ```bash
   cd fastlane
   bundle exec fastlane deliver download_metadata \
     --app_identifier brickverse.MyBodyApp --force
   ```
   会生成 `fastlane/metadata/en-US/` 目录。
3. 编辑 `fastlane/metadata/en-US/{name,description,keywords,release_notes,...}.txt` 填英文。
4. `make release` 一次性推中英截图 + 中英文案。

### 4. ASC 侧

App Information → Localizations → "+" → English。之后 ASC 会开始要求 en-US 的 screenshots / description / keywords——这时 `make release` 会自动把本地的 en-US 内容填进去。

## 推荐引入节奏

1. **v1.0** — 只发中文。目前就是这个状态。
2. **v1.1** — 加英文：先只做 String Catalog 翻译（上面 Step 1），不在 ASC 加 en-US 本地化、不改 Snapfile。这样海外用户设备语言是英文时 App 界面是英文的，但 App Store 页面仍是中文；审核不会卡。
3. **v1.2** — 加英文 App Store 本地化：做 Step 2 + 3 + 4。
4. **v1.x+** — 按需加日语、韩语等。每次只需重复 Step 1–4 针对新语言。

分阶段的好处：**UI 翻译**与 **App Store 文案**是两件独立的事，一次只推进一个维度，出错时范围可控。

## 陷阱与最佳实践

### ⚠️ ASC 首次加 Localization 后不可"空跑"

如果在 ASC 加了 English 本地化但 `fastlane/screenshots/en-US/` 或 `fastlane/metadata/en-US/description.txt` 是空的，下次 `make release` 会因缺内容而**失败**。解决：

- 先在 ASC 加语言，再**同一天内**准备好对应的截图与文案推上去；或
- 临时用 `SKIP_SCREENSHOTS=1 SKIP_METADATA=1 make release`（其实就是 no-op），把内容补齐后再推。

### ⚠️ String Catalog 不要手改 JSON

`.xcstrings` 是 Xcode 管的 JSON，手改可能破坏内部 UUID 索引。一律在 Xcode 界面里编辑。

### ⚠️ 系统语言 vs 地区

App Store 地区列表（China, US, Japan…）和 Localization 语言是**两件事**：
- 一个 App 可以**在所有地区销售**（App Pricing → Availability，默认全选）
- 每个地区显示的语言 = 该地区用户设备语言与你提供的 Localization 的**交集**；没交集时回落到 Primary Language（中文）

所以加英文 Localization 后，美区用户会看到英文页面，日区会回落到中文（除非也加了日文 Localization）。

### ✅ 繁体中文（zh-Hant）建议策略

简体用户和繁体用户差异不大但存在——台湾、香港地区建议单独加 `zh-Hant` Localization，至少复制 `zh-Hans` 的文案过去做少量用词调整（「軟體」/「軟件」、「影片」/「视频」等）。

## 对应的 Fastfile / Snapfile 改动快照

未来执行 Step 2 时，`Snapfile` 这一行的 diff：

```ruby
- languages(["zh-Hans"])
+ languages(["zh-Hans", "en-US"])
```

`Fastfile` 的 `PRIMARY_LANG`**不要改**（它决定 `produce` 创建 App 时的 Primary Language，对已存在的 App 也已无效果）。

## 参考资料

- Apple 官方：[Localization - Apple Developer](https://developer.apple.com/documentation/xcode/localization)
- String Catalog：[WWDC23 "Discover String Catalogs"](https://developer.apple.com/videos/play/wwdc2023/10155/)
- fastlane deliver 语言列表：[fastlane/deliver Available Languages](https://docs.fastlane.tools/actions/deliver/#available-language-codes)
