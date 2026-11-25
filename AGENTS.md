# ShuYoHarmony Agent Maintenance Rules (`AGENTS.md`)

本仓库为 [shuosc/ShuYo](https://github.com/shuosc/ShuYo) 的原生 HarmonyOS（Stage 模型 / ArkTS / ArkUI V2）移植工程，采用 **“上游 Flutter 变更参考 + 鸿蒙原生 AI 增量同步 + 人工真机把关”** 维护模式。所有 Agent 修改本项目前必须遵守以下硬性规范。

---

## 1. ArkTS & ArkUI V2 强制规范

- **状态管理统一 V2**：
  - 组件统一使用 `@ComponentV2`，状态使用 `@Local`、`@Param`、`@Once`、`@Event`、`@Provider`、`@Consumer`、`@Computed`、`@Monitor`。
  - 全局状态模型使用 `@ObservedV2` + `@Trace` + `AppStorageV2`（见 [ShuYoAppStore.ets](entry/src/main/ets/store/ShuYoAppStore.ets)）。
  - 双向绑定使用 `$$this.xxx`（如 `.bindSheet($$this.showSheet, ...)`）。
  - **禁止**在新增或修改的文件中引入或回退 V1 装饰器（`@Component`、`@State`、`@Prop`、`@Link`、`@Observed`、`@ObjectLink`、`@Watch`、`@StorageLink`）。
- **ArkTS 类型与安全**：
  - 禁止使用 `any`、`unknown`、无类型声明的对象字面量或运行时动态删改对象属性。
  - 所有函数与 `static` 方法必须显式标注参数类型与返回类型；严格处理 `undefined` 与边界值。
  - 若第三方/校方协议（如超星预约签名）确需 MD5 且被 `@security/no-unsafe-hash` 拦截，先查看 [code-linter.json5](code-linter.json5) 并保留合规的纯 ArkTS/Crypto fallback，同时用 `devecocli check lint` 实测确认零报错。
- **性能与交互规范**：
  - 长列表 (`List` / `Grid`) 必须提供稳定键值且配置 `.cachedCount(4)`，派生列表优先使用 `@Computed`。
  - 半模态 (`bindSheet`) 内的垂直 `Scroll` / `List` 必须具备明确受限高度（如外层固定 `height('100%')` 包裹层内使用 `.layoutWeight(1)`）并显式配置 `.nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })`。

---

## 2. 本地 DevEco SDK `.d.ts` 声明优先

调用或修改任何 `@kit.*` 或 ArkUI 组件属性（如 `NetworkKit`、`RemoteCommunicationKit`、`CryptoArchitectureKit`、`AssetStoreKit`、`BackgroundTasksKit`、`Scroll`、`bindSheet`、`UIMaterial`）前，**禁止凭记忆书写签名或枚举值**，必须先检索本机 SDK 声明目录：

- OpenHarmony SDK 声明：`D:\Huawei\DevEco Studio\sdk\default\openharmony\ets\`
  - Kit 入口：`kits\@kit.*.d.ts`
  - 系统 API：`api\@ohos.*.d.ts`
  - ArkUI 组件：`component\*.d.ts`（如 `scroll.d.ts`、`common.d.ts`、`enums.d.ts`）
- HMS Core SDK 声明：`D:\Huawei\DevEco Studio\sdk\default\hms\ets\`
  - Kit 入口：`kits\@kit.*.d.ts`（如 `@kit.RemoteCommunicationKit.d.ts`）
  - HMS API：`api\@hms.*.d.ts`（如 `@hms.collaboration.rcp.d.ts`）

---

## 3. 纯逻辑拆层与脱敏黄金单测（Local Test）

- **纯 ArkTS 可测拆层**：将 URL 重写、Cookie 域映射、认证状态机响应解析、图书馆协议校验、HTML/JSON 公告解析抽取为**零 `@kit.*` 依赖**的纯 ArkTS 模块（如 `WebVpnProtocol.ets`、`LibraryBookingProtocol.ets`、`AnnouncementParser.ets`、`JsonHelpers.ets`），供运行态 Service 与离线 Local Test 共同复用。
- **黄金 Fixture 单测**：
  - Local Test 位于 `entry/src/test/*.test.ets`，统一在 [List.test.ets](entry/src/test/List.test.ets) 注册。
  - 所有解析器、协议状态机修改后，必须使用脱敏真实报文 Fixture 补齐用例并跑通 Local Test（无真机/无校园网环境锁定核心回归）。
  - 注意：`entry/src/test/` 运行环境不含系统 C++/Kit 运行时，被测纯模块不得 import `@kit.*` 或 `@ohos.*` 原生能力。

---

## 4. 工程构建、检查与测试命令

在工程根目录 `d:\Rsk2ayton_Workplace\ShuYoHarmony` 下执行：

| 用途 | 命令 |
|---|---|
| 运行 Local Unit Tests | `$env:DEVECO_SDK_HOME = "D:\Huawei\DevEco Studio\sdk"; & "D:\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" test -p module=entry -p coverage=false` |
| 查看单测结果 | 读取 `entry\.test\default\intermediates\test\coverage_data\test_result.txt` |
| 代码规范检查 (Lint) | `devecocli check lint` |
| Debug 编译构建 | `devecocli build` |
| 未签名 Release 打包 | 先 `git checkout -- build-profile.json5`，再 `devecocli build --build-mode release` |

- Release 未签名产物路径：`entry\build\default\outputs\default\entry-default-unsigned.hap`。

---

## 5. 人机协作边界与安全红线

1. **AI 负责边界**：
   - 核对上游 `d:\Rsk2ayton_Workplace\ShuYo-src` 变更与 [SYNC_MAP.md](SYNC_MAP.md) 映射关系；
   - 检索本地 SDK `.d.ts` 声明后实现增量同步或定点修复；
   - 跑通 Local Unit Tests → `devecocli check lint` → `devecocli build` → 仅在模拟器（`127.0.0.1:5555`）做 Demo 模式冒烟验证。
2. **人工把关边界**：
   - Review 关键 diff 与业务逻辑边界；
   - 使用个人真机以真实校园账号冒烟验证敏感实网链路（统一认证 / WebVPN / 实时座位提交 / 长正文）；
   - 本地配置个人签名后发布与上架。
3. **绝对红线**：
   - **严禁提交**本地调试签名配置到 [build-profile.json5](build-profile.json5)（仓库中 `signingConfigs` 必须保持 `[]`）；
   - **严禁自动操作**已连接的个人真机设备（`devecocli device list` 中 `Kind = device` 的真机仅归开发者手动使用）；
   - 实网链路（如 WebVPN、预约提交）在未经过人工真机核验前，严禁擅自关闭对应 Issue。
