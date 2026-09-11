# NKAS Mobile Design System

> 以 `mobile/design/nkas-mobile-interactive.html` 为唯一视觉与交互原型。
> Flutter 后续页面、组件、主题和交互必须先对照原型，再映射到 `shadcn_ui`。本文件约束实现，不重新定义另一套视觉方向。

## 1. 产品定位

NKAS Mobile 是 Android/iOS 移动控制端，不是营销页，也不是完整 WebUI 的缩小版。主要任务是查看后端状态、Android 本机服务控制、实例切换、任务/调度查看、历史日志和设置入口。

- 一级页面固定为：总览、实例、日志、设置；
- STAR 验证和 Android 初始化复用现有 Android 原生流程；
- 后端地址、原始 WebUI、更新从设置进入；
- 实时日志、进入控制、后台通知、日志自动滚动在方案确定前保持可插拔，不显示假接入状态。

## 2. 原型基准

原型基准画布为 390 x 844：状态栏 28px，主内容滚动底部预留 88px，内容左右内边距 18px；宽度 <=360px 时左右内边距 14px。

Flutter 不使用固定高度模拟手机外框。内容区随窗口全幅流式展开，桌面浏览器预览时上限 480px 居中；真实页面使用 `SafeArea`、滚动容器和系统窗口尺寸，但必须保持顶部状态区、AppBar、内容区和底部导航不重叠。

设置子页：STAR 验证、初始化 NKAS、后端地址、原始 WebUI、更新。子页显示返回按钮并隐藏底部导航。页面标题只在 AppBar 出现一次；正文可使用“运行概览”“实例状态”“日志文件”等模块标题，但不重复页面标题。

## 3. 视觉语言

关键词：浅色、冷静、紧凑、可扫描、轻量分组、浅蓝品牌色、低阴影。

禁止：渐变 Hero、紫色主交互色、中央 FAB、底部悬浮启停按钮、每行独立卡片、无用途顶栏菜单、emoji 图标、WebUI 适配说明、固定假数据、本地布尔状态冒充后端状态、按钮图标与文字换行。

## 4. 颜色 Tokens

颜色以原型 CSS 为准，Flutter 统一放进 `mobile/lib/theme.dart` 的主题扩展，组件不得散落裸 hex。

### Light

| Token | 值 | 用途 |
| --- | --- | --- |
| `page` | `#F6F9FB` | 页面背景 |
| `surface` | `#FFFFFF` | 列表、设置分组、详情 |
| `ink` | `#172331` | 主文字 |
| `muted` | `#70808E` | 说明和次要信息 |
| `line` | `#E1E9EF` | 分隔线、细边框 |
| `blue` | `#0099FF` | 主按钮、选中、链接、焦点 |
| `blueHi` | `#40B0FF` | 按压/高光辅助 |
| `blueSoft` | `#E0F3FF` | Hero、选中软底、徽标 |
| `success` | `#159A72` | 运行中、完成、已连接 |
| `warning` | `#BD7A18` | 等待、警告、更新可用 |
| `danger` | `#C94D42` | 错误、危险操作 |

辅助表面：连接背景 `#E8F8F2`，输入背景 `#F5F8FA`，日志背景 `#F2F4F5`，次级按钮使用半透明白色。

### Dark

| Token | 值 | 用途 |
| --- | --- | --- |
| `page` | `#17232B` | 页面背景 |
| `surface` | `#202E37` | 内容表面 |
| `ink` | `#E7F0F4` | 主文字 |
| `muted` | `#9FB1BC` | 副文字 |
| `line` | `#344752` | 分隔线 |
| `blue` | `#40B0FF` | 主交互 |
| `blueSoft` | `#173E55` | 选中软底 |
| `success` | `#35C995` | 成功/运行中 |
| `warning` | `#FFC178` | 警告/等待 |
| `danger` | `#FF8E82` | 错误/危险 |

## 5. 字体和层级

使用平台系统字体：Android Roboto/Noto CJK，iOS SF/苹方。不打包额外 UI 字体；日志、命令和 URL 使用等宽字体。

| 角色 | 规格 |
| --- | --- |
| 页面标题 | 24px / 700 |
| Hero 状态 | 21px / 700 |
| 区块标题 | 16px / 700 |
| 卡片标题 | 14-15px / 650-700 |
| 正文 | 13-14px / 400-650 |
| 说明 | 11-13px / 400 |
| 标签 | 10-12px / 650-750 |
| 日志 | 10.5px 等宽 / 1.75 |

中文标题字距保持 0，不使用负字距。正文不小于 12px，关键操作文字不小于 13px。允许系统字体放大，长标题自然换行；状态、时间、版本号和 URL 必须保留完整值。

## 6. 间距、尺寸和圆角

基础间距使用 4/8 节奏：页面左右 18px，模块间距 25px，设置组间距 20px，列表标题下方 8-9px，行内间距 8-12px，按钮间距 8px，图标与文字 5-11px。

圆角：输入/小按钮 9-11px，图标按钮 12px，列表/设置表面 16-17px，认证卡片/预览 18px，主状态区 22px，底部导航 999px。

固定尺寸：图标按钮视觉 40x40（触控至少 44x44），主按钮最小高度 38，Sheet 操作至少 44，设置行至少 56，实例行至少 68，任务行至少 55，底部导航 244x58，导航单项至少 46x46。

所有 Flutter 控件满足 Android 48dp / iOS 44pt 触控范围。视觉图标可以更小，但不可缩小点击区域。

## 7. 阴影和边界

原型使用轻阴影和细边框分层。Flutter 只保留 `card`、`raised`、`brand` 三档语义阴影。普通列表使用 `surface + line`，不要逐行加阴影。

Hero 使用浅蓝 `blueSoft`，无渐变；导航使用轻微 raised 阴影；Sheet 使用向上阴影和半透明 scrim。深色主题下阴影透明度降低，并重新检查对比度。

## 8. 图标

原型使用 Lucide 线性图标。Flutter 使用同一视觉语言的 Lucide 图标包或等价线性图标，禁止混用填充图标。

常用语义：总览 `layout-dashboard`、实例 `layers-3`、日志 `scroll-text`、设置 `settings-2`、刷新 `refresh-cw`、启动 `play`、停止 `square`、返回 `arrow-left`、更新 `square-arrow-up`、验证 `shield-check/github`、初始化 `sparkles/rocket`、后端 `server`、WebUI `globe-2/external-link`。

图标按钮必须提供 `tooltip`/`semanticLabel`；同一层级统一 15-20px 尺寸；图标与文字按 baseline/center 对齐；不使用文字模拟系统图标。

## 9. 组件规范

### AppBar 与连接状态

AppBar 只保留页面标题和连接状态 pill。设置子页显示返回按钮，不显示底部导航，也不恢复三点菜单。连接状态包括已连接、连接中、不可达、版本不兼容，不能固定写“已连接”。

### Hero 主状态区

总览只有一个明显主视觉：浅蓝 Hero。结构为小眉标题、后端状态标题、右侧图标、连接对象/同步信息、Android 本机服务启停（仅本机模式）和刷新状态。

后端状态展示对所有平台可用；服务启停仅 Android 且 `controlBaseUrl` 指向本机 Termux 服务时出现，通过平台桥执行 `nkas-service.sh start|stop|restart`，与具体实例启停无关。iOS 和远程模式隐藏此按钮。

### 分组列表

实例、设置和事件使用共享 surface：外层一个 surface，行间 1px 分隔线，首尾裁切圆角，左右 padding 14px，标题、说明、状态和 chevron 固定列对齐。不把每一行做成独立卡片。

### 底部导航

原型是居中的白色半透明胶囊：宽 244px、高 58px、底部 14px + SafeArea、四项等宽。选中为 `blueSoft` 背景、蓝色图标和底部 4px 小圆点。只切换总览、实例、日志、设置，不放启停、部署或更新。

### Tabs

实例 Tab 使用横向滚动文字 Tab：`概览 | 任务配置 | 调度设置 | 实时日志 | 画面`。激活态为蓝色文字和底部 2px 指示线；必须单行，超出屏幕横向滚动。

### Bottom Sheet

实例切换、后端地址编辑、原始 WebUI 等临时操作使用 Sheet：半透明 scrim、38x4 拖拽提示条、24px 上圆角、操作项至少 44px、提供取消路径、打开时阻止底层重复操作。

## 10. 页面规范

### 总览

顺序固定为页面说明、主状态 Hero、实例状态、活动日历。活动日历使用真实后端数据和分类，banner 不使用渐变；没有活动时显示空状态，不显示固定示例活动。

### 实例

顶部是一行紧凑头部：头像 + 实例名 + 状态 | 切换 | 启动/停止。不要再放重复实例列表卡片。概览只显示后端 `running/pending/waiting` 分组，不增加无接口依据的统计卡片。任务配置按 schema 的菜单/任务/分组动态生成，调度按真实 cadence 和锁定状态生成。实时日志和画面区域保留原型位置，但协议未确定前不得显示假数据或“实时 2s”。

### 日志

筛选只包含日期、来源、级别，不做关键词搜索。内容使用等宽字体和固定列：时间、级别、来源、消息。WARN/ERROR 使用语义背景，不能整块高饱和。实时日志、自动滚动、复制和分享均待定。

### 设置

设置使用分组行，不重复显示“设置”正文标题。顺序为验证与初始化、后端连接、外观与通知、关于；更新放在后端连接分组最下面。主题和语言是 App 自己的本地设置，不调用 WebUI 主题/语言接口。Android 的 STAR 验证、初始化和本地服务启停通过平台桥复用既有原生流程；iOS 隐藏 Termux/ADB 内容。

## 11. Flutter 实现约束

推荐结构：

```text
mobile/lib/
├── app/             # Shell、路由、主题、本地语言
├── core/
│   ├── api/         # ApiClient、WS 地址、错误模型
│   ├── models/      # system、instance、schema、queue、schedule、log
│   ├── platform/    # Android Star/初始化/Termux 平台桥
│   └── widgets/     # surface、status、sheet、empty/error
└── features/        # overview、instances、logs、settings
```

- `shadcn_ui` 作为组件基础，最终视觉由 `theme.dart` tokens 控制；
- 使用声明式路由和 `PopScope`；动态列表使用稳定 `ValueKey`；
- API 请求集中在 repository，不在 Widget 中散落；
- `controlBaseUrl` 与 Android `localServiceUrl` 分离，远程地址不能改写本地 Termux 配置；
- 第一阶段 token 不阻塞直连，但 ApiClient 预留认证拦截器；
- REST 使用 `http/https`，WebSocket 根据 scheme 转为 `ws/wss`；
- 按 Android/iOS 平台隐藏本机专属控件；
- 保持 `shadcn_ui` 组件的尺寸、圆角、颜色和文字与本原型一致，不直接套用默认主题外观。

## 12. 动效、状态和错误

页面切换和导航选中约 150ms；按钮按压只改变透明度/轻微缩放，不改变布局；Sheet 从底部进入，退出更快。系统 reduced motion 时取消非必要动画。异步按钮必须显示 loading 并阻止重复点击。

页面状态覆盖：`initial -> loading -> success/empty/error/disconnected/reconnecting`。保留后端错误原因：403 权限、409 状态冲突、422 字段校验、5xx/timeout 服务不可用。不要用短暂“已保存”掩盖真实失败。

## 13. 验收清单

- [ ] 390px、360px 手机无横向溢出；
- [ ] 四项底部导航位置、尺寸、选中态与原型一致；
- [ ] 总览只有一个浅蓝 Hero，无渐变；
- [ ] 实例头部一行显示状态、切换、启停；
- [ ] Tab 单行横向滚动，激活线正确；
- [ ] 设置、实例、日志使用共享 surface + 分隔行；
- [ ] 图标、文字、状态列对齐，按钮不换行；
- [ ] 浅色/深色检查对比度，支持系统字体放大；
- [ ] 实例、任务、调度、活动、日志和版本来自接口；
- [ ] 服务状态来自 `/api/system/status`，不使用静态 bool；
- [ ] Android 服务启停与实例启停明确区分；
- [ ] Android Star/初始化复用现有原生流程；
- [ ] iOS 不显示 Termux/ADB/本地服务启停；
- [ ] 日志不提供关键词搜索；
- [ ] App 主题和语言与 WebUI 解耦；
- [ ] `controlBaseUrl` 与 `localServiceUrl` 分离；
- [ ] 实时日志、控制、通知和自动滚动未定能力不显示假数据。
