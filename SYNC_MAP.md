# Upstream ↔ HarmonyOS 文件映射表 (`SYNC_MAP.md`)

本表记录上游 Flutter 仓库 `d:\Rsk2ayton_Workplace\ShuYo-src` 与原生鸿蒙仓库 `ShuYoHarmony` 的模块对应关系，便于上游变更后按图索骥做增量同步。

- **当前上游同步基准 Commit**：`3da602e`（`feat(schedule): add graduate timetable sync and term import`）
- **鸿蒙分支基线**：`main` / `beta/native-kits`（`v0.5.4`）

---

## 1. 核心基础设施与共享层

| 领域 | 上游 Flutter (`ShuYo-src/lib/...`) | 鸿蒙原生 (`entry/src/main/ets/...`) | 纯协议/单测覆盖 | 说明 |
|---|---|---|---|---|
| 常量与 OAuth 目标 | `core/academic_constants.dart`<br>`core/webvpn_urls.dart`<br>`core/wecom_constants.dart`<br>`core/classroom_url_resolver.dart`<br>`core/otp_url_resolver.dart` | `core/ShuYoConstants.ets` | `WebVpnProtocol.test.ets` | 含教务、WebVPN、There/超星、企微等全量常量 |
| 主题与动效/毛玻璃 | `shared/theme/shuyo_theme.dart`<br>`shared/theme/custom_background.dart` | `core/ShuYoTheme.ets`<br>`core/ShuYoMotionGlass.ets` | - | 鸿蒙 7.0 原生 `UIMaterial` / `BackgroundEffect` 与弹簧动效 |
| HTTP 与 Cookie 罐 | `data/services/session_cookie_jar.dart`<br>`data/services/http_timeout.dart` | `services/HttpClientService.ets`<br>`services/WebVpnProtocol.ets` | `WebVpnProtocol.test.ets` | `rcp` 会话请求、Set-Cookie 持久化、WebVPN 域重写与网关 Token 注入 |
| 安全存储与偏好 | `data/services/secure_app_store.dart`<br>`data/services/client_settings_service.dart` | `services/SecureStorageService.ets`<br>`services/PreferencesService.ets` | - | Asset Store Kit 硬件加密存储 + 首选项 |
| 数据模型与全局状态 | `data/models/*.dart`<br>`app/app_shell.dart` | `models/ShuYoModels.ets`<br>`store/ShuYoAppStore.ets` | - | ArkUI V2 `@ObservedV2` + `@Trace` 单例状态中心 |
| 公共 UI 组件 | `shared/widgets/app_header.dart`<br>`shared/widgets/empty_state.dart` | `components/ShuYoCommonViews.ets` | - | 顶栏 `ShuYoTopBar`、空状态、通用区块标题 |

---

## 2. 当前重点维护域（WebVPN / 图书馆预约 / 通知公告）

| 领域 | 上游 Flutter (`ShuYo-src/lib/...`) | 鸿蒙原生 (`entry/src/main/ets/...`) | 纯协议/单测覆盖 | 同步要点与注意事项 |
|---|---|---|---|---|
| **身份认证与 WebVPN** | `data/services/academic_native_auth_service.dart`<br>`data/services/webvpn_session_store.dart`<br>`data/services/webvpn_device_id.dart`<br>`data/services/wecom_auth_service.dart` | `services/AuthService.ets`<br>`services/WebVpnAuthService.ets`<br>`services/WebVpnProtocol.ets`<br>`pages/subpages/NativeLoginPage.ets`<br>`pages/subpages/WeComScanPage.ets` | `services/WebVpnProtocol.ets`<br>`test/WebVpnProtocol.test.ets` | `canonicalSsoUrl` 需覆盖 `oauth.shu.edu.cn` 与两个 `webvpn` 代理域名；`webvpn-token` 仅限 `webvpn.shu.edu.cn`，代理请求必须显式附带 |
| **图书馆预约 (There + 超星)** | `data/services/there_booking_client.dart`<br>`data/services/chaoxing_booking_client.dart`<br>`data/services/chaoxing_booking_adapter.dart`<br>`features/library_booking/library_booking_page.dart` | `services/LibraryBookingService.ets`<br>`services/ChaoxingBookingService.ets`<br>`services/LibraryBookingProtocol.ets`<br>`services/LibraryFloorPlanLayout.ets`<br>`components/LibraryFloorPlanView.ets`<br>`pages/subpages/LibraryBookingPage.ets` | `services/LibraryBookingProtocol.ets`<br>`test/LibraryBookingProtocol.test.ets` | There 提交前必须重拉最新区域座位并校验 `officeAreaId`/`abilities`，严格校验返回 `data[0].id`；超星按 `[captcha=]...[salt]` 计算 `enc` 并执行 10s 防重提交 |
| **通知公告** | `data/services/announcement_api_client.dart`<br>`data/repositories/announcement_repository.dart`<br>`features/home/announcements_page.dart` | `services/AnnouncementService.ets`<br>`services/AnnouncementParser.ets`<br>`pages/subpages/AnnouncementsPage.ets` | `services/AnnouncementParser.ets`<br>`test/AnnouncementParser.test.ets` | 详情 `bindSheet` 内 `Scroll` 必须包在受限高度容器内（`.layoutWeight(1)` + `nestedScroll`）；解析层覆盖官网/院系六大列表与表格/图片/附件正文块 |

---

## 3. 其余业务模块映射（当前保持稳定）

| 领域 | 上游 Flutter (`ShuYo-src/lib/...`) | 鸿蒙原生 (`entry/src/main/ets/...`) | 说明 |
|---|---|---|---|
| **课表与日程 / 桌面卡片 / 提醒** | `data/services/academic_schedule_api_client.dart`<br>`data/services/graduate_schedule_api_client.dart`<br>`data/services/academic_schedule_notification_service.dart`<br>`data/services/academic_schedule_widget_service.dart`<br>`features/home/academic_schedule_page.dart`<br>`features/home/academic_schedule_editor_page.dart`<br>`features/home/academic_schedule_collection_page.dart`<br>`features/home/schedule_share_page.dart` | `services/ScheduleService.ets`<br>`services/ClassReminderService.ets`<br>`services/ScheduleWidgetService.ets`<br>`entryformability/EntryFormAbility.ets`<br>`widget/pages/ScheduleWidgetCard.ets`<br>`pages/tabs/AcademicScheduleView.ets`<br>`pages/subpages/ScheduleEditorPage.ets`<br>`pages/subpages/ScheduleCollectionPage.ets`<br>`pages/subpages/ScheduleSharePage.ets` | 含本研课表同步、Form Kit 桌面卡片、BackgroundTasksKit 课前提醒 |
| **首页与布局定制** | `features/home/home_dashboard_page.dart`<br>`features/home/home_layout_page.dart`<br>`features/onboarding/startup_onboarding.dart` | `pages/Index.ets`<br>`pages/tabs/HomeDashboardView.ets`<br>`pages/subpages/HomeLayoutPage.ets` | 4 Tab 懒挂载常驻 + 悬浮毛玻璃胶囊底栏 |
| **学业进度与成绩排名** | `data/services/academic_progress_api_client.dart`<br>`data/services/academic_progress_parser.dart`<br>`data/services/academic_ranking_api_client.dart`<br>`features/home/academic_progress_page.dart` | `services/AcademicProgressService.ets`<br>`pages/tabs/AcademicProgressView.ets` | 修读树、GPA 与排名解析 |
| **课程评价** | `data/services/course_review_api_client.dart`<br>`features/rate/*.dart` | `services/CourseReviewService.ets`<br>`pages/tabs/RateHomeView.ets`<br>`pages/subpages/RateDetailPage.ets`<br>`pages/subpages/RatePublishPage.ets` | 课评检索、详情与发布 |
| **空教室查询** | `data/services/classroom_api_client.dart`<br>`data/services/classroom_auth_service.dart`<br>`features/home/empty_classroom_page.dart` | `services/ClassroomService.ets`<br>`pages/subpages/EmptyClassroomPage.ets` | 支持直连与 WebVPN 模式切换 |
| **校园一卡通** | `data/services/campus_card_service.dart`<br>`features/home/campus_card_page.dart` | `services/CampusCardService.ets`<br>`pages/subpages/CampusCardPage.ets` | 余额查询与 90 天分片账单 |
| **动态口令 (OTP)** | `data/services/otp_token_api_client.dart`<br>`data/services/otp_token_parser.dart`<br>`features/home/otp_token_page.dart` | `services/OtpTokenService.ets`<br>`pages/subpages/OtpTokenPage.ets` | 6 位动态口令与倒计时刷新 |
| **课程录播与播放器** | `features/home/shuyo_content_page.dart` | `services/CourseRecordingService.ets`<br>`pages/subpages/CourseRecordingsPage.ets`<br>`pages/subpages/CourseRecordingPlayerPage.ets` | 多机位课程录播（支持 WebVPN 映射） |
| **三校区地图** | `data/repositories/campus_map_repository.dart`<br>`features/campus_map/*.dart` | `services/CampusMapService.ets`<br>`services/CampusLocationService.ets`<br>`pages/subpages/CampusMapPage.ets` | 宝山/嘉定/延长矢量地图与点位详情 |
| **设置 / 头像 / 贡献者** | `features/settings/*.dart`<br>`data/services/github_contributors_service.dart` | `pages/subpages/SettingsPage.ets`<br>`pages/subpages/AvatarCropPage.ets`<br>`pages/subpages/ContributorsPage.ets` | 主题配色、WebVPN 开关、本地缓存清理 |
