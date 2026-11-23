# ShuYoHarmony（SHU友 原生鸿蒙版）

![Language](https://img.shields.io/badge/Language-ArkTS-0080FF) ![Platform](https://img.shields.io/badge/Platform-HarmonyOS-0A59F7)

专为上海大学师生设计的校园一站式服务原生 HarmonyOS 应用，基于 ArkTS 与 ArkUI 状态管理 V2 开发，改编自开源项目 [shuosc/ShuYo](https://github.com/shuosc/ShuYo)。

## 核心功能

- **身份认证与学籍切换**：支持本科生 / 研究生学籍系统、上海大学统一身份认证登录、企业微信扫码登录、校园 WebVPN 切换及免登录演示模式。
- **课表与日程**：教务课表同步、周视图课表、自定义课程编辑、课表合集管理与分享。
- **学业与评课**：成绩与 GPA 绩点查询、培养方案修读进度、历届课程评价查看与发布。
- **课程录播与直播回放**：支持多学期课程目录、直播课程置顶、周录播时间表、全校录播搜索、多机位视角切换、双画面同屏播放及 AI PPT 笔记定位跳转（暂未实现）。
- **校园工具箱**：空教室查询、校园一卡通（真实余额与近 90 天分片账单同步）、图书馆座位预约与规则/问答指引、宝山/嘉定/延长三校区矢量地图、动态口令（OTP）、通知公告。
- **外观与定制**：多套主题配色（含 Material Design 3）、深浅色模式、首页模块排版自定义。

## 项目信息

| 项目属性 | 说明 |
|---|---|
| 应用名称 | `SHU友` |
| Bundle Name | `com.rsk2ayton.shuyo.harmony` |
| 当前版本 | `v0.5.2`（`versionCode: 1000001`） |
| 目标 / 兼容 SDK | `HarmonyOS 26.0.0`（Stage 模型 / ArkUI V2） |
| 支持设备 | `phone` |

## 下载与安装

前往本仓库的 [Releases 页面](https://github.com/rsk2ayton-dev/ShuYoHarmony/releases) 下载对应版本的安装包。

> [!NOTE]
> Release 附件中的 `ShuYoHarmony-v0.5.2-unsigned.hap` 为**未签名（unsigned）** HAP 安装包（本仓库不包含签名密钥）。  
> 如需在真机安装运行，请在 DevEco Studio 中配置自动签名（或执行 `devecocli signature generate` 后运行 `devecocli run`），或使用您自己的 HarmonyOS 签名证书与 Profile 对 HAP 进行签名后再安装。

## 构建与开发

本工程使用 HarmonyOS Stage 模型与 Hvigor 构建工具链，可通过 DevEco Studio 打开根目录，或使用 `devecocli` 命令行构建与检查：

- Debug 构建：`devecocli build`
- Release 构建：`devecocli build --build-mode release`
- 代码检查：`devecocli check lint`
- 部署运行：`devecocli run`

## 目录结构

```text
ShuYoHarmony/
├── AppScope/                          # 应用级配置与全局资源（app.json5、应用图标等）
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── components/            # 公共 UI 组件
│       │   ├── core/                  # 常量配置、主题规范与加密工具
│       │   ├── entryability/          # 应用入口与备份 Ability
│       │   ├── models/                # 数据模型定义
│       │   ├── pages/                 # 主页面、Tabs 与各功能子页面
│       │   ├── services/              # 网络请求、认证、课表、校园服务等接口封装
│       │   └── store/                 # ArkUI V2 全局状态管理
│       └── resources/
│           └── rawfile/               # 三校区地图、图书馆指引、演示数据与静态资源
├── build-profile.json5                # 工程构建与 SDK 配置
├── code-linter.json5                  # 代码规范检查配置
└── oh-package.json5                   # 工程依赖配置
```

## 开源许可与致谢

本项目改编自开源项目 [shuosc/ShuYo](https://github.com/shuosc/ShuYo)，沿用其 GNU General Public License v3.0（GPL-3.0）开源协议。感谢原作者与贡献者们的付出。
