# NKAS Flutter 移动端 UI 适配计划

> 状态：视觉预览与架构确认阶段。`mobile/` 当前使用假数据，不连接真实 NKAS API。
> 视觉规范以 `mobile/DESIGN.md` 为唯一依据，组件库使用 `shadcn_ui`。

## 1. 目标与边界

使用 Flutter 建立 Android/iOS 统一的移动控制面板：查看所有后端的服务状态、在 Android 本机通过 Termux 启停本地服务、切换实例、查看日志、执行常用配置操作。

Android 保留本机部署和运行能力；iOS 作为远程控制端，不包含 Android 初始化内容。两端共享页面结构、设计系统、数据模型和 API 客户端。

不重写 Python、ADB、Termux 或任务引擎。Flutter 只通过 REST、WebSocket 和少量平台桥访问能力，不直接调用 Python 模块或读写运行配置文件。

```text
android/       现有 Kotlin：Star 验证、初始化、Termux、通知和后台服务
mobile/        Flutter：Android/iOS 统一控制界面
webui/         Vue WebUI：现有完整功能与配色参考
module/webui/  Starlette REST/WebSocket 服务
```

## 2. 导航与信息架构

### 2.1 一级导航

手机竖屏使用 5 项浮动底部导航：

```text
总览    实例    日志    部署    设置
```

- 底部导航只用于页面切换，不放服务启停等业务操作；
- 当前项使用品牌蓝选中态，点击区域不小于 44×44px；
- 部署页消费 `/api/system/deploy` 系列接口，复刻 WebUI 部署页；更新、STAR 验证、初始化、后端地址和原始 WebUI 从设置进入；不保留独立顶栏更多菜单；
- 服务状态展示在总览主状态区，所有后端模式均可用 `/api/system/status`；服务启停只在 Android 本机模式显示，由 Termux 执行 `nkas-service.sh start|stop|restart`，与具体 NKAS 实例无关。

### 2.2 页面标题

AppBar 是唯一页面级标题。正文不重复“总览”“实例”“日志”“设置”等同名标题，只显示简短说明、功能分组和上下文。

“总览 / 运行概览”和“日志 / 实时日志”分别属于页面级与分组级标题，可以同时存在。

### 2.3 页面层级

```text
总览：后端服务状态与 Android 本地主服务操作 → 实例摘要 → 活动日历
实例：实例列表 → 实例详情（状态、任务、调度、配置）
日志：日期/来源/级别筛选 → 历史日志 → 错误详情；实时日志待定
设置：连接 → 外观与通知 → 安全 → 高级
设置子页：STAR 验证 → 初始化 NKAS → 后端连接（原始 WebUI、源码更新）→ 外观与通知 → 关于
```

## 3. Android 与 iOS 流程

### Android

```text
启动 → 现有 Android Star 验证 → 未初始化则进入现有原生初始化 → 初始化完成后进入 Flutter
     → 连接本地 `127.0.0.1:12271` → 通过 Termux 控制本地 NKAS 服务
```

保留 `AccessGate`、`GatePage`、`SetupPage`、`TermuxBridge`、`BootstrapService`、`AdbPairingService`、`BootReceiver` 和 `InstanceNotificationService`。Flutter 通过平台桥复用这些能力，不在 Dart 中重写 Star/OAuth、Termux 或 ADB 流程。初始化完成后使用 Flutter Activity 或 Flutter module 承载主 UI。

### iOS

```text
启动 → 服务器配置 → 认证与连通性检查 → 进入同一 Flutter 控制界面
```

iOS 不显示 Termux、ADB、依赖安装和本地服务启停等 Android 专属内容。通过 API 连接后端，只展示服务状态和实例控制，不维护两套 UI。

## 4. 响应式适配

### 手机竖屏（<600px）

- 单列滚动，水平边距 16px；
- AppBar + 5 项底部导航；
- 操作按钮整行或二等分；
- 表格转为列表、分组行或详情 Sheet；
- 键盘弹出时保证字段和保存操作可见。

### 横屏/折叠屏（600–839px）

- 内容最大宽度 760px，居中显示；
- 总览可使用两列摘要，日志保持全宽；
- 底部导航不因旋转改变；
- 弹窗宽度限制在 520–600px。

### 平板（≥840px）

- 底部导航可切换为左侧 NavigationRail；
- 列表与详情允许双栏；
- 日志可显示筛选栏 + 详情双栏；
- 内容设置最大宽度，不按比例放大手机卡片。

### 系统适配

- 使用 `SafeArea` 处理刘海、圆角屏和手势区；
- 支持系统字体 100%–200%、TalkBack、VoiceOver 和键盘焦点；
- 支持 Android 返回手势和 iOS 边缘返回；
- 竖屏为主，日志与配置页允许横屏；
- 不用固定屏幕高度定位业务控件。

## 5. 视觉与组件规范

完整 token 见 `mobile/DESIGN.md`，核心规则如下：

- 品牌主蓝与 WebUI 统一为 `#0099FF`；`#40B0FF` 只用于高光；
- 不使用渐变 Hero，不使用第二个饱和交互色；
- 浅色主题优先，深色主题保持同构；
- 页面只保留一个明显主视觉，其余内容使用分组列表；
- 卡片只承载独立状态、工具、表单或模态内容；
- 实例、设置、事件优先使用共享 surface + 分隔行；
- 状态同时提供颜色、图标和文字；
- 图标统一使用 Lucide，避免混用线条风格。

通用组件：

```text
NkasAppShell / NkasSection / NkasStatusBadge
NkasInstanceRow / NkasActionButton / NkasConfigField
NkasLoadingView / NkasEmptyState / NkasErrorState
NkasLogEntry / NkasConfirmDialog / NkasToast
```

## 6. 页面实施规格

### 总览

- 主状态区显示连接对象、后端可达状态和同步时间；
- Android 本机模式才显示 Termux 服务启动/停止，停止需要二次确认；
- 刷新有 loading 和成功反馈；
- 实例摘要最多显示 3 个，最近事件使用无外框列表；
- 覆盖未连接、初始化中、服务异常和空状态。

### 实例与详情

- 实例行显示名称、状态、当前任务和最近运行时间；
- 当前实例使用 `accentSoft`，不依赖阴影；
- 点击实例进入详情，不自动跳回总览；
- 任务、调度、配置使用 Tabs 或分段导航；
- 删除、停止等高风险操作必须确认；
- 实例较多时提供搜索和状态筛选。

### 日志

- 提供日期、实例来源和等级筛选；不做关键词搜索；
- 时间、等级、消息使用等宽/对齐排版；
- WARN/ERROR 使用语义色，不整块高饱和填充；
- 复制和分享待定；自动滚动待定；
- 错误详情使用 Bottom Sheet；
- 长列表虚拟化并限制内存中的日志数量。

### 部署与初始化

- Android 本机部署属于初始化流程，由现有 Android/Termux 原生层负责；Flutter 只展示状态、入口和结果；
- 远程后端模式不展示 Termux、ADB、容器安装等本机步骤，只做连接检查；
- `deploy.yaml` 编辑由一级“部署”页面承担，使用 `/api/system/deploy` 的 schema 驱动渲染与保存（复刻 WebUI 部署页）；
- 执行时显示步骤、进度、实时输出和取消能力；离开页面后仍需能恢复状态。

### 设置

- 不重复显示“设置”正文标题；
- 分为验证与初始化、后端连接、外观与通知、关于；
- 主题使用品牌蓝分段控件；
- 后端地址提供连接测试；第一阶段直接连接，不实现 token；
- Android 显示本地服务启停和初始化状态，iOS 隐藏；
- 本地主题和语言由 Flutter 管理，不调用 WebUI 主题/语言接口。

### 关于与更新

- 关于展示版本、执行端、协议和项目链接；
- 源码更新放在“后端连接”分组最下面；不单独实现启动器更新；
- 更新区分 Flutter App、Android 运行环境和 NKAS 代码；移动端第一阶段只接入 NKAS 源码更新；
- 展示当前版本、目标版本、变更摘要和失败恢复方式。

## 7. 状态、数据与安全

每个异步页面覆盖：

```text
initial → loading → success
                  ↘ empty
                  ↘ recoverable error → retry
                  ↘ permission required
                  ↘ disconnected → reconnecting
```

- 首次加载使用 skeleton，短操作使用按钮 spinner；
- 保存成功使用轻量 toast；错误包含原因和下一步；
- 服务断开时保留数据但标记过期；
- 防止重复点击造成重复请求。

接口映射以 `doc/mobile/flutter-backend-mapping.md` 为准。现有 Starlette API 的关键端点是：

```text
GET  /api/system/status         GET  /api/system/update
GET  /api/instances              GET  /api/{name}/schema
GET  /api/{name}/config          PATCH /api/{name}/config
GET  /api/{name}/queue           GET  /api/{name}/schedule
POST /api/{name}/schedule/save   GET  /api/calendar
GET  /api/system/logs            POST /api/update
WS   /ws/state                   WS   /ws/{name}/queue
WS   /ws/{name}/log
```

没有通用的 `/api/service/start` 或 `/api/service/stop`；实例启停使用
`POST /api/{name}/start|stop`，全部实例使用 `/api/all/start|stop`。Flutter 不创建重复业务服务；总览的“服务启停”必须先明确为全部实例启停，不能停止承载 API 的后端进程。

平台桥只处理初始化状态、通知/文件/局域网权限、系统设置、Android 前台服务、文件选择、分享和二维码扫描。

第一阶段按当前决定直接连接，不实现 token；连接配置只适合本机或可信局域网，ApiClient 预留认证拦截器。日志导出提示可能包含路径和账号；不把生产地址写入源码。

## 8. Flutter 工程与依赖

```text
mobile/lib/
├── app/       # App、路由、主题
├── core/      # API、WebSocket、模型、平台桥、通用组件
└── features/  # overview、instances、logs、settings
```

依赖建议：

```text
shadcn_ui              UI 组件和主题
flutter_riverpod       状态与依赖注入
go_router              路由和深链
dio                    REST 客户端
web_socket_channel     实时状态与日志
shared_preferences     普通偏好
flutter_secure_storage 预留认证凭据（第一阶段不启用）
intl                   日期、数字和本地化
```

从当前预览拆分时，先拆业务组件和模型，再接入状态管理，避免同时改变行为。

## 9. 开发、编译、测试与发布

在 `mobile/` 执行：

```powershell
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
flutter build web --release
```

开发运行：

```powershell
flutter run -d chrome
flutter devices
flutter run -d <device-id>
```

Android：

```powershell
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
```

iOS（macOS + Xcode）：

```bash
flutter test
flutter build ios --release
flutter build ipa --release
```

每个 PR 至少执行 format、analyze、test 和 Web release build。发布前确认包名、版本、签名、权限、明文 HTTP/ATS、通知、前台服务、局域网访问和 ABI 配置。

## 10. 测试矩阵

### Widget

- 5 项导航切换和选中态；
- 总览 Android 本地服务启停确认、loading 和错误；
- 实例选择和空状态；
- 日志日期/来源/级别筛选和错误详情；自动滚动待定；
- 设置分组与主题切换；
- 360px 宽度无溢出。

### 集成

- 首次连接、断开和自动重连；
- Android 初始化完成后进入 Flutter；
- Android Termux 启停服务后状态和通知一致；
- WebSocket 队列持续更新；实时日志待定；
- Android 初始化后台继续、取消和失败恢复；
- 键盘、字体放大、旋转和切后台恢复。

### 真机

- Android 360×800、390×844、高 DPI；
- 小屏 iPhone、标准尺寸、Pro Max；
- 至少一台平板横竖屏；
- light/dark/跟随系统；
- 弱网、服务端重启和权限拒绝；认证待定。

## 11. 里程碑与验收

| 阶段 | 交付 | 验收 |
| --- | --- | --- |
| M0 | 视觉预览、`DESIGN.md`、5 项导航 | Web 可运行，检查和测试通过 |
| M1 | 工程拆分、主题、路由、通用状态 | 页面行为不回归，360px–平板稳定 |
| M2 | REST、连接状态机 | 可配置服务端，断线可恢复；token 暂不纳入 |
| M3 | 真实总览与实例 | 状态实时更新，实例操作闭环 |
| M4 | 历史日志与错误详情 | 大量日志不卡顿，可按日期/来源/级别定位；实时日志待定 |
| M5 | schema 配置和 Android 初始化桥 | 常用字段可编辑，初始化流程可恢复 |
| M6 | Android 原生接合 | 验证/初始化保留，Flutter 进入正常 |
| M7 | iOS 远程控制 | 局域网、HTTPS、认证和权限可用 |
| M8 | 无障碍、真机回归与发布 | Android 内测、iOS TestFlight 达标 |

## 12. 当前执行顺序

1. 固化当前预览的 5 项底部导航和 `DESIGN.md` token；
2. 拆分 `main.dart` 为 app/core/features，保持假数据行为；
3. 增加 loading、empty、error、disconnected 预览状态；
4. 对照 Starlette API 建立接口清单和连接状态模型；
5. 接入真实总览、实例和队列 WebSocket；
6. 通过平台桥接入既有 Android Star/初始化流程；实时日志和画面控制待方案确定后再接入。

在 M1 完成前不扩展复杂动画、不引入新的颜色体系，也不让 Flutter 直接承担 Python/ADB 执行逻辑。
