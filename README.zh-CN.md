# FootageFlow

[English](README.md) · [简体中文](README.zh-CN.md)

**搜索素材，粘贴链接，下载媒体。**

一款面向视频创作者的免费开源桌面工具，支持 macOS 和 Windows。你既可以一次搜索多个素材来源，也可以粘贴支持的公开媒体链接，尝试解析和下载媒体。

**macOS Apple Silicon** · **Windows 11 x64** · **免费** · **开源（MIT）**

[下载 macOS 或 Windows 最新正式版](https://github.com/xcslys99/FootageFlow/releases/latest) · [查看全部版本](https://github.com/xcslys99/FootageFlow/releases)

FootageFlow 注重隐私，适合历史、国家、财经、人物、科普、纪录片和短视频创作。FootageFlow v0.7.2 正式支持 **macOS 15+ Apple Silicon** 和 **Windows 11 x64**。两个版本共用全部 17 个搜索 Provider、十语复合主题检索、分页、统一 Metadata/Rights、本地相关性重排、创作者输出元数据、来源 Sidecar、项目持久化和版本判断核心。

## FootageFlow 的两种核心用法

### 1. 素材搜索

在一个界面中同时搜索多个素材来源。

- 多 Provider 并发搜索、分页与“加载更多”
- 高级筛选，包括“仅显示可直接下载”
- 多选并通过现有下载管理器进行批量下载
- 项目、收藏、搜索历史和下载历史
- 保存 Provider 实际提供的来源、Rights、License 和署名信息

### 2. 链接下载

已经有媒体链接？把一个或多个支持的公开媒体链接粘贴进 FootageFlow，软件会尝试解析并下载可用媒体。

- 读取来源 Metadata 和实际可用格式
- 可下载完整媒体或经过校验的开始/结束时间片段
- 来源提供时可选择清晰度、仅音频、字幕、原始输出和剪辑兼容 MP4
- 支持 YouTube、X/Twitter、Vimeo，以及当前内置 yt-dlp 支持的其他公开网站
- 所有任务进入同一个下载管理器，继续支持进度、取消、重试、历史记录和来源 Sidecar

可用性取决于来源网站、具体媒体、访问权限、地区限制、登录要求以及平台变化。FootageFlow 是尽力提供的链接下载器，不承诺 100% 下载成功。

## 创作者工作流

- **只下载需要的片段：** 链接解析后输入开始/结束时间，或使用轻量范围控件；任务仍进入原有下载管理器。
- **用十种语言搜索复合主题：** 每次搜索都会保持完整意图，并生成英语、简体中文、繁体中文、西班牙语、巴西葡萄牙语、日语、韩语、德语、法语和俄语查询。默认显示输入语言和英语；点击“查看全部语言”可编辑全部查询。不使用付费 AI API。
- **输出剪辑兼容文件：** 保留原格式、生成 H.264/AAC/yuv420p 且支持 fast-start 的 MP4，或提取 M4A 音频；完成前会验证兼容输出。
- **在本机检测复制的媒体链接：** 剪贴板检测默认关闭，仅在 FootageFlow 处于活动状态时运行，不上传剪贴板内容。
- **搜索 Openverse：** 查找开放授权的图片和音频，并保留每项实际提供的许可与署名元数据。
- **发现 Dailymotion 视频：** 搜索公开元数据并打开原始页面；Dailymotion 主要作为发现来源。

## 已实现功能

- 并发搜索 17 个来源，包括 Pexels、Pixabay、Wikimedia Commons、Internet Archive、YouTube、NASA、Library of Congress、National Archives、Europeana、PeerTube/SepiaSearch、Coverr、Vimeo、Openverse 和 Dailymotion
- 可见、可编辑、可关闭的十语复合查询；输入语言和英语还可各增加最多两条视觉扩展，总量不超过 14 条
- 两阶段检索与本地概念相关性重排，可选择精准、均衡或宽泛模式；默认“均衡”会过滤只匹配复合主题中一个宽泛概念的结果
- Provider 独立分页和“加载更多”；追加结果不会清空已有列表，下一页失败也不会丢失已加载素材
- “链接下载”可一次解析一个或多个公开媒体链接，选择完整/片段与输出预设，并将任务送入原有下载管理器
- 按来源、素材类型、年份、时长、分辨率、Rights 和直接下载能力进行高级筛选
- 多选、选择当前可见结果、批量进入原有三并发下载队列、加入项目、重试失败任务、复制来源信息
- 每项均可复制来源或复制署名信息，内容只使用 Provider 实际提供的元数据
- 视频/图片预览、收藏、项目库、文稿拆分、搜索历史和下载历史
- 每个成功下载文件自动生成同名 `.source.txt` 和 `.source.json`
- 支持 English、简体中文、繁體中文、西班牙语、巴西葡萄牙语、日语、韩语、德语、法语和俄语；首次启动仍默认 English
- 搜索栏下方明确提示 National Archives、Europeana 和 YouTube 配置官方免费 API 后效果更好，并可直接进入素材来源设置
- 明显的“反馈与社区”页面集成 GitHub Issues 和 Discussions，可报告问题、提出建议、提问并查看仓库与正式版本
- 可选 API Key 只保存在 macOS Keychain 或 Windows Credential Manager
- 可选的前台剪贴板媒体链接检测；默认关闭且完全在本机进行
- 跨平台更新提示会在启动时显示官方版本说明，并提供“查看更新”与“稍后提醒”；FootageFlow 绝不会自动安装更新
- 不含分析、广告、跟踪、云端账号、付费大模型，也不依赖 OpenAI API、Codex 或终端脚本

配置 Key 后，YouTube 搜索可使用官方 Data API。FootageFlow 也内置本地 yt-dlp，用于尽力搜索和下载公开内容。由于平台限流、地区限制、登录要求、版权限制或接口变化，部分视频可能无法下载。FootageFlow 不读取浏览器 Cookie、不绕过 DRM，也不承诺每个视频都能下载。

## 界面截图

以下截图来自 macOS 版 FootageFlow。Windows 版采用相同产品结构，并使用符合 Windows 习惯的原生控件。

![FootageFlow v0.6.0 智能搜索扩展与可编辑本地关键词](docs/images/smart-search-expansion.png)

![FootageFlow v0.6.0 链接下载的有效片段范围与剪辑兼容输出](docs/images/link-clip-output.png)

![FootageFlow v0.6.0 Openverse 真实搜索结果与已加载缩略图](docs/images/openverse-results.png)

![FootageFlow v0.6.0 Dailymotion 发现结果](docs/images/dailymotion-results.png)

![FootageFlow v0.6.0 可选且仅限本机的剪贴板检测设置](docs/images/clipboard-settings.png)

![FootageFlow Provider 模式与十种界面语言](docs/images/provider-settings.png)

## 在 macOS 安装

1. 从 Releases 下载 `FootageFlow-0.7.2-macOS-arm64.dmg`。
2. 打开 DMG，把 FootageFlow 拖入“应用程序”。
3. 打开 FootageFlow。v0.7.2 使用 Ad Hoc 签名，尚未公证；如果首次启动被系统拦截，请前往“系统设置 → 隐私与安全性 → 仍要打开”。

日常使用不需要打开终端。

## 在 Windows 安装

1. 在 Windows 11 x64 电脑上下载 `FootageFlow-Setup-0.7.2-Windows-x64.exe`。
2. 使用同时提供的 `.sha256` 文件核对安装包，然后双击安装。
3. 完成安装向导，从“开始”菜单打开 FootageFlow。

安装包已包含运行组件，普通用户不需要安装 Python、Node.js、Swift、.NET、yt-dlp 或 FFmpeg。Windows 安装包尚未代码签名，因此 Microsoft Defender SmartScreen 可能提示“无法识别的应用”。请只使用本仓库正式 Release 的安装包，并确认校验值一致。

## 第一次使用

1. 打开 FootageFlow 后可立即搜索；首次启动不要求配置 API Key。
2. 可先尝试 `Apollo 11` 或 `World War II`，再打开“高级筛选”或“仅显示可直接下载”。
3. 勾选结果后，可批量下载、加入现有/新项目或复制来源信息。
4. 发布前使用“复制署名信息”，并核对原始来源页。
5. National Archives、Europeana 和 YouTube 接入官方免费 API 后搜索效果更好；如需配置，请进入“设置 → 素材来源”。
6. 如需从公开媒体页面下载，进入“链接下载”，粘贴一个或多个 URL，选择实际可用格式后点击“下载所选”。

macOS 默认下载目录为 `~/Movies/FootageFlow/<项目名>/`，Windows 默认为 `%USERPROFILE%\Videos\FootageFlow\<项目名>\`，均可在设置中修改。删除数据库记录不会删除已经下载的素材文件。

## 软件更新

从 v0.7.0 开始，FootageFlow 每次启动只检查一次本仓库最新的 GitHub 正式 Release。发现更高版本时，应用会显示版本号、发布日期和完整版本说明，让你选择“查看更新”或“稍后提醒”。“查看更新”只会打开官方 GitHub Release 页面，FootageFlow 不会静默下载或自动安装。“稍后提醒”会把同一版本延后 24 小时；如果期间发布了更高版本，新版本仍可立即提示。也可以在“设置 → 软件更新”中手动检查。

v0.6.0 及更早版本本身没有更新检查代码，因此无法被远程补上提示。这些用户需要手动安装一次 v0.7.0；此后的新版本才能在应用内被发现。

## 支持来源与 Provider 模式

FootageFlow 不要求所有素材来源采用相同的接入方式。部分平台提供无需 API Key 的公开接口；部分平台在用户配置自己的 API Key 后可以获得更完整和稳定的搜索体验。在技术条件和平台规则允许的情况下，FootageFlow 仍会提供无需 API Key 的受限或尽力搜索模式。

| Provider | 搜索 / API 模式 | 无 Key 模式 | 下载 | Rights 元数据 |
|---|---|---|---|---|
| [Pexels](https://www.pexels.com/api/) | 用户 Key + 官方 API | 直接搜索，尽力提供 | 来源给出媒体地址时可下载 | API 元数据；直接模式可能未知 |
| [Pixabay](https://pixabay.com/api/docs/) | 用户 Key + 官方 API | 直接搜索，尽力提供 | 来源给出媒体地址时可下载 | API 元数据；直接模式可能未知 |
| [Wikimedia Commons](https://commons.wikimedia.org/wiki/Commons:API) | 公共 MediaWiki API | 完整公共接口 | 来源给出原始媒体时可下载 | 来源 `extmetadata` |
| [Internet Archive](https://archive.org/developers/) | 公共搜索和项目元数据 | 完整公共接口 | 按项目文件决定 | 来源提供 License/Rights 时显示 |
| [YouTube](https://developers.google.com/youtube/v3/getting-started) | 用户 Key + Data API | yt-dlp 尽力搜索 | yt-dlp 条件性下载 | 通常无法确认，需核对原始页 |
| [NASA](https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf) | 官方公开 Images API | 无需 Key | 来源提供官方 Asset 时可下载 | 仅按项目元数据；不自动视为 Public Domain |
| [Library of Congress](https://www.loc.gov/apis/) | 官方公开 JSON API | 无需 Key | 来源给出且未限制的资源 | Rights Advisory/Access 字段 |
| [National Archives](https://www.archives.gov/research/catalog/help/api) | 用户 Key + Catalog API | 受限：打开官方搜索 | 来源给出 Digital Object 时可下载 | 来源限制/Rights 字段 |
| [Europeana](https://europeana.atlassian.net/wiki/spaces/EF/pages/2462351393/Accessing+the+APIs) | 用户 Key + Search API | 受限：打开官方搜索 | 来源给出直接媒体时可下载 | 来源 `edmRights`/rights |
| [PeerTube / SepiaSearch](https://docs.joinpeertube.org/api-rest-reference.html) | 公开 SepiaSearch API | 无需 Key | 仅发现 | 来源明确提供的单项 License |
| [Videvo](https://www.videvo.net/) | 受限发现 | 打开官方搜索 | 仅打开原始页面 | 逐项核对原始页面 |
| [Videezy](https://www.videezy.com/) | 受限发现 | 打开官方搜索 | 仅打开原始页面 | 免费素材可能要求署名，逐项核对 |
| [Mixkit](https://mixkit.co/) | 受限发现 | 打开官方搜索 | 仅打开原始页面 | 免费/受限授权不同，逐项核对 |
| [Coverr](https://api.coverr.co/docs) | 用户 Key + 官方 API | 受限：打开官方搜索 | API 提供媒体地址时可下载 | 保留 Coverr API/License 与署名信息 |
| [Vimeo](https://developer.vimeo.com/api/reference) | 用户 Token + 官方 API | 受限：打开官方搜索 | 默认仅发现 | 仅显示来源明确提供的 License |
| [Openverse](https://api.openverse.org/) | 公开图片/音频 API | 可匿名访问 | 来源提供原始媒体时可下载 | 每项实际返回的许可、链接、作者与署名元数据 |
| [Dailymotion](https://developers.dailymotion.com/reference/api-list-videos) | 公开视频发现接口 | 当前公开字段无需 Key | 仅发现 | 除非元数据明确提供，否则保持未知 |

API Key 是开发接口凭据，不等同于平台登录账号。Key 只留在本机、界面默认隐藏，可在“设置 → 素材来源”中添加、替换、测试或删除。Key 不会进入普通设置、日志、源码、Git、Telemetry 或请求 URL。

## 链接下载

进入“链接下载”，粘贴一个或多个公开媒体页面 URL，然后点击“解析”。FootageFlow 使用内置、隔离用户配置的 yt-dlp 适配器读取来源实际提供的元数据、可用视频高度、纯音频流和字幕。你可以选择完整媒体或经过校验的开始/结束片段，并保留原输出、生成剪辑兼容 MP4，或提取 M4A 音频。YouTube、X/Twitter、Vimeo、Dailymotion 及内置工具支持的其他公开网站可能可用，但不承诺任何网站或具体链接 100% 可下载。

所选任务全部进入搜索下载共用的 Download Manager，继续支持进度、速度、取消、重试、打开文件夹、下载记录和来源 Sidecar。输出预设与片段时间会保留在下载记录和 Sidecar 中。FootageFlow 不读取浏览器 Cookie、不绕过 DRM、不绕过登录/私人视频权限，也不破解付费或会员内容；同时拒绝包含内嵌凭据或敏感查询参数的链接，并阻止本机与私有网络地址。无法访问时请使用“打开原始页面”。

下载可用性取决于来源网站、具体媒体、访问权限以及平台变化。用户应遵守来源网站条款、版权规则及适用法律。

## 反馈与社区

- Bug → [GitHub Issues](https://github.com/xcslys99/FootageFlow/issues/new?template=bug_report.yml)
- 功能建议 → [GitHub Discussions](https://github.com/xcslys99/FootageFlow/discussions/categories/ideas)
- 提问 → [GitHub Discussions Q&A](https://github.com/xcslys99/FootageFlow/discussions/categories/q-a)
- 版本下载 → [GitHub Releases](https://github.com/xcslys99/FootageFlow/releases)

应用内链接只预填 FootageFlow 版本、平台、系统版本和界面语言，不会附带凭据、本地路径、历史记录、下载记录或项目内容。

## Rights 与来源安全

FootageFlow 绝不猜测 Rights 或 License。缺少元数据时显示“版权 / 授权未知”。下载成功不等于允许商业使用。Internet Archive、NASA、Library of Congress、National Archives、Europeana 和 Wikimedia 素材都不会被自动视为 Public Domain。使用前必须核对原始来源页。

This product uses the National Archives Catalog API but is not endorsed or certified by the National Archives and Records Administration.

本项目与列出的素材 Provider 均无隶属或背书关系。请阅读 [PRIVACY.md](PRIVACY.md) 和 [YouTube API 服务条款](https://developers.google.com/youtube/terms/api-services-terms-of-service)。

FootageFlow 源码采用 [MIT License](LICENSE)。通过软件找到的媒体仍受各来源自身的版权和授权条件约束。

## 从源码构建

普通用户应直接安装 Release，无需开发环境。macOS 开发需要 Swift 6 和完整 Xcode；Windows 开发需要 Swift 6.3.3、.NET 10、Visual Studio 2022 C++ 环境和 Inno Setup 7。

```bash
swift build -c release
swift test
scripts/build_app.sh
scripts/verify_app.sh
```

Windows 打包、干净安装、GUI 启动、卸载和 Provider 冒烟验收由 Windows 11 x64 GitHub Actions 执行。架构与新增 Provider 方法见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 常见问题

- **National Archives/Europeana 显示受限模式**：添加自己的 Key 进行完整应用内搜索，或点“打开官方搜索”。
- **Pexels/Pixabay 直接搜索暂不可用**：稍后重试，或选择添加对应 API Key。
- **请求次数过多**：稍后重试；FootageFlow 不会绕过平台限制。
- **一个 Provider 失败**：其他来源的成功结果仍然可用。
- **没有预览/下载按钮**：来源没有提供兼容的官方媒体地址，请打开原始页。
- **Rights 未知**：以当前原始来源页为准，FootageFlow 不推测使用权限。
- **查看日志**：进入“设置 → 打开日志”。日志不会记录 API Key。
