# FootageFinder 开发说明

## 架构

- `Models/`：统一 `MediaAsset`、搜索筛选、五态 License 模型。
- `Providers/`：`MediaProvider` 协议及 Pexels、Pixabay、Wikimedia、Internet Archive、YouTube 独立实现。
- `Networking/`：URLSession、超时、HTTP 错误中文映射、429/5xx 有限指数退避和取消。
- `Services/`：Keychain、平台缓存、最多 3 并发下载、两次下载重试、日志和 source sidecar。
- `Persistence/`：项目、镜头、收藏、搜索历史、下载记录的 Codable 原子本地数据库。
- `ViewModels/`：Provider 并发搜索、去重、综合排序和平台独立失败。
- `Views/`：SwiftUI Sidebar、网格、AVKit 预览、项目、收藏、下载历史、设置、文稿批量搜索。

当前机器只有 Command Line Tools，缺少 `SwiftDataMacros` 和 XCTest/Swift Testing 模块，因此 SwiftData `@Model` 无法编译。持久化接口已隔离，并使用原生 Codable 原子文件保证交付 App 可以实际构建和跨重启保存；完整 Xcode 环境可将 `DataStore` 替换为 SwiftData，而无需修改 Provider 或主要 View。

## 当前官方 API

- Pexels：`GET /v1/videos/search`、`GET /v1/search`，`Authorization` Header。
- Pixabay：`GET /api/videos/`、`GET /api/`；按官方要求结果缓存 24 小时。
- Wikimedia Commons：MediaWiki Action API，`generator=search` + `imageinfo` + `extmetadata`。
- Internet Archive：Advanced Search `advancedsearch.php` + Item Metadata `/metadata/{identifier}`。
- YouTube Data API v3：`search.list`，`part=snippet&type=video`。为节省额度，每次总搜索最多使用前 2 个启用关键词。

所有 Key 均通过 Security.framework 存入 Keychain，源码、UserDefaults、日志和数据库均不保存 Key。

## 新增 Provider

1. 新建实现 `MediaProvider` 的类型，声明 `ProviderInfo`。
2. 将平台 JSON 严格映射到 `MediaAsset`；缺失字段保留 `nil`，不得猜 License。
3. 在 `SearchViewModel.makeProviders()`、`BatchSearchService` 和设置页加入 Provider。
4. 添加固定 JSON fixture 与解析测试，并加入 `SelfTestRunner`。

## 构建与验证

```text
scripts/build_app.sh
scripts/verify_app.sh
```

发布构建使用 SwiftPM Release，随后生成标准 `.app` bundle、图标并做本机 Ad Hoc codesign。`FootageFinder --self-test` 当前覆盖 16 项离线单元检查；`--live-smoke` 验证 Wikimedia、Internet Archive 和缺 Key 降级；`--acceptance-test <目录>` 还会下载一个明确 Public Domain 的 Wikimedia 测试视频、生成 sidecar 并验证项目/收藏重开。

测试 fixtures 位于 `Tests/FootageFinderTests/Fixtures/`。完整 Xcode 安装后可直接启用 XCTest 文件；当前 CLT 环境运行 `swift test` 会报告缺少 `XCTest` 模块，这是工具链边界，不是应用构建失败。
