# FootageFlow

[English](README.md) · [简体中文](README.zh-CN.md)

搜索 · 发现 · 下载 · 整理

FootageFlow 是一款注重隐私的桌面素材搜索与管理软件，可一次搜索多个真实视频和图片素材库，适合历史、国家、财经、人物、科普、纪录片和短视频创作。

当前版本是原生 **macOS 15+ Apple Silicon** 应用。Windows 版会在 macOS v0.1.0 稳定后开发，本次发布尚不包含 Windows 版本。

## 已实现功能

- 同时搜索 Pexels、Pixabay、Wikimedia Commons、Internet Archive 和 YouTube
- 显示来源、作者、分辨率、时长，以及 Provider 实际返回的 License 信息
- 筛选、相关度排序、去重、逐平台返回结果和单平台失败提示
- 视频/图片预览、收藏、项目库、文稿拆分和搜索历史
- 下载队列、进度、速度、取消、重试，最多同时下载 3 个素材
- 每个下载文件自动生成同名 `.source.txt` 和 `.source.json`
- English / 简体中文；首次启动默认 English，右上角始终有醒目的语言切换
- API Key 保存在操作系统安全凭据存储中
- 不含分析、广告、跟踪、云端账号、付费大模型，也不依赖 OpenAI API、Codex 或终端脚本

YouTube 只通过官方 Data API 提供搜索、缩略图、元数据和打开来源页，不提供 YouTube 视频下载。

## 界面截图

![FootageFlow 搜索](docs/images/search.png)

![FootageFlow 项目管理](docs/images/projects.png)

## 在 macOS 安装

1. 从 Releases 下载 `FootageFlow-0.1.0-macOS-arm64.dmg`。
2. 打开 DMG，把 FootageFlow 拖入“应用程序”。
3. 打开 FootageFlow。v0.1.0 使用 Ad Hoc 签名，尚未公证；如果首次启动被 macOS 拦截，请前往“系统设置 → 隐私与安全性 → 仍要打开”。

日常使用不需要打开终端。

## 第一次使用

1. 打开 FootageFlow；暂时没有 API Key 时可点 **Set Up Later**。
2. Wikimedia Commons 和 Internet Archive 无需 Key，可以直接搜索。
3. 如需更多来源，进入 **Settings**，填写 Pexels、Pixabay 或 YouTube Data API Key，点 **Save**，再点 **Test Connection**。
4. 回到 **Quick Search**，输入题材，检查自动生成的关键词，然后点 **Search Footage**。
5. 如需按项目整理，请先选择项目，再收藏或下载素材。
6. 发布前务必查看每个素材的 License 和原始来源页。

默认下载目录为 `~/Movies/FootageFlow/<项目名>/`，可在设置中修改。只删除下载记录不会删除原素材；只有明确点击“删除本地文件”并再次确认后，应用才会删除文件。

## Provider 配置

| Provider | API Key | 主要用途 |
|---|---:|---|
| [Pexels](https://www.pexels.com/api/) | 需要 | 现代 B-roll 视频和图片 |
| [Pixabay](https://pixabay.com/api/docs/) | 需要 | 视频和图片 |
| [Wikimedia Commons](https://commons.wikimedia.org/wiki/Commons:API) | 不需要 | 历史图片、地图、人物、地点和部分视频 |
| [Internet Archive](https://archive.org/developers/) | 不需要 | 历史电影、新闻胶片、录音和公共档案 |
| [YouTube Data API](https://developers.google.com/youtube/v3/getting-started) | 需要 | 寻找研究线索和原始来源页 |

API Key 是开发接口凭据，不等同于登录账号。免费额度、配额和平台规则由各 Provider 决定。

## License 与来源安全

FootageFlow 绝不猜测 License。缺少元数据时会显示“授权未知”。Internet Archive 素材不会被自动视为 Public Domain。使用前请打开原始来源页并核对当前授权条款。

本项目与 Pexels、Pixabay、Wikimedia Foundation、Internet Archive、Google 或 YouTube 均无隶属或背书关系。请阅读 [PRIVACY.md](PRIVACY.md) 和 [YouTube API 服务条款](https://developers.google.com/youtube/terms/api-services-terms-of-service)。

FootageFlow 源代码采用 [MIT License](LICENSE)。通过软件找到的媒体素材仍然受各自来源和 License 约束。

## 从源码构建

需要 macOS 15+、Swift 6；运行 XCTest 需要完整 Xcode。

```bash
swift build -c release
swift test
scripts/build_app.sh
scripts/verify_app.sh
```

架构和新增 Provider 方法见 [DEVELOPMENT.md](DEVELOPMENT.md)，参与贡献请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 常见问题

- **提示需要 API Key**：在设置中填写，或关闭该 Provider。
- **请求次数过多**：稍后重试；FootageFlow 不会绕过平台限制。
- **一个 Provider 失败**：其他来源的成功结果仍然可以使用。
- **无法预览**：Provider 没有兼容预览流时，请点“打开来源”。
- **License 有疑问**：以原始来源页为准，可刷新搜索获取最新元数据。
- **查看日志**：进入“设置 → 打开日志”。日志不会记录 API Key。
