# NKAS Flutter 原型与后端对接映射

> 依据：`mobile/design/nkas-mobile-interactive.html`、`module/webui/api/app.py` 及各路由实现。
>
> 结论先行：原型的信息架构可以保留，但不能把 HTML 中的假数据和本地布尔状态直接搬进 Flutter。实例、任务配置、调度、活动日历、历史日志、更新可以复用现有后端；STAR 验证和初始化复用现有 Android 实现；Android 本地服务启停通过 Termux 执行；实时日志、画面控制、后台通知和日志自动滚动暂不定最终方案。

## 1. 对接结论

| 范围 | 结论 | 处理方式 |
| --- | --- | --- |
| 总览实例摘要 | 可对接 | `/api/instances`，状态补充 `/ws/state` |
| 总览服务状态 | 所有后端可展示 | 请求 `/api/system/status` 成功表示后端在线；Android 本机可额外通过 Termux 脚本判断本地进程状态 |
| 总览服务启停 | 仅 Android 本机 | 调用 Termux 中的 `~/.nkas/nkas-service.sh start|stop|restart`，与任何具体实例无关；iOS 和远程后端模式不显示启停按钮 |
| 活动日历 | 可对接 | `/api/calendar`，禁止继续使用固定活动文案 |
| 实例队列 | 可对接 | `/api/{name}/queue` + `/ws/{name}/queue` |
| 任务配置 | 可对接但必须 schema 驱动 | `/api/{name}/schema`、`/config`、`PATCH /config` |
| 调度设置 | 可对接但原型控件过于简化 | `/schedule`、`/schedule/save`、`/schedule/reset` |
| 历史日志 | 可对接 | `/api/system/logs/files`、`/logs`、`/logs/download` |
| 实时日志 | 待定 | 现有 WS 返回 HTML，不在第一阶段强行接入；保留页面位置，最终协议另行决定 |
| 画面预览 | 可对接 | `/api/{name}/screenshot` 轮询 JPEG |
| 画面控制 | 待定 | `/api/{name}/scrcpy` 当前返回 Web 页面/流地址；是否 WebView、外部 WebUI 或原生控制另行决定 |
| STAR 验证 | Android 已实现 | 复用 `AccessGate`、`GatePage`、OAuth 回调和 RSA 许可证校验逻辑，通过 Flutter 平台桥暴露状态和操作 |
| Android 初始化 | Android 已实现 | 复用 `SetupPage`、`TermuxBridge`、`BootstrapService`、`AdbPairingService` 和脚本能力；业务逻辑不重写 |
| 更新 | 可对接源码更新 | `/api/system/status`、`/system/update`、`/update/check`、`/update`、`/restart` |
| 修改后端地址 | App 连接配置 | Flutter 本地保存、探测、重连；第一阶段直接连接，token 暂不实现 |

## 2. 页面与功能映射

### 2.1 总览

| 原型元素 | 真实数据/操作 | 接口与状态 | 需要调整 |
| --- | --- | --- | --- |
| “已连接” | API 健康状态 | `GET /api/system/status` | 不能写死；区分连接中、已连接、断开、版本不兼容 |
| 主服务状态 | 后端是否可达 | `GET /api/system/status` | 所有后端都能展示在线/不可达；接口当前没有 uptime，原型“运行 2 小时 18 分”需删除或后端新增字段 |
| 主服务启停 | Android 本地 Termux 服务 | Android 平台桥执行 `nkas-service.sh start|stop` | 与实例启停无关；只在 Android 且当前连接指向本机部署时展示。iOS、远程连接隐藏 |
| 实例状态列表 | 名称、state、当前任务、下一个任务、备注、头像、config module | `GET /api/instances` | `state` 不是布尔值：1 运行、2 停止、3 错误停止、4 更新中；串行等待还要合并 `/api/serial/state` |
| 实例刷新 | 重新拉取摘要 | `/api/instances` | 加 loading、失败和过期标记 |
| 活动日历 | 分类、标题、副标题、起止时间、banner、PASS 合成图、超频阶段 | `GET /api/calendar?language=zh-CN`，刷新时 `refresh=true` | 去掉固定“当前剧情活动”数据；`updated_at` 来自接口 |
| 活动分类 Tab | 前端过滤 | `items[].category` | 分类名称必须映射后端 category，不要假定“Raid/招募”等永远存在 |

### 2.2 实例页

#### 实例头部

| 原型元素 | 真实实现 |
| --- | --- |
| 当前实例名称/头像/状态 | 来自 `/api/instances`；头像使用 `/avatars/{filename}`，不要用首字模拟 |
| 切换实例 | 从 `/api/instances` 动态生成选择器；切换后重新加载 schema、config、queue、schedule，并切换两个实例 WS |
| 启动/停止 | `POST /api/{name}/start`、`POST /api/{name}/stop`；处理 403 `admin_required`、409 已运行/已停止、串行失败状态 |
| 状态实时变化 | `WS /ws/state` 每秒推送 `{type,name,state}`；本地状态只做 loading，不作为事实源 |

#### 概览 Tab

| 原型元素 | 真实实现 |
| --- | --- |
| 运行中/队列中/等待中 | `GET /api/{name}/queue` 或 `WS /ws/{name}/queue`，响应固定为 `running/pending/waiting` 数组 |
| 任务名 | `name_i18n` |
| 任务命令 | `command`，点击任务详情时作为 schema/config 的 key |
| 下一次运行 | `next_run` 字符串，前端只格式化，不自行计算 |
| 串行等待 | 额外读取 `/api/serial/state`；`waiting`、`current`、`failed`、`halted` 不能从 queue 推断 |
| 当前“任务总数/最近运行/调度器”四格 | 后端没有同样聚合字段；删除或明确计算规则，不应继续显示虚拟数字 |

#### 任务配置 Tab

| 原型元素 | 真实实现 |
| --- | --- |
| “日常/活动/工具”分组 | 使用 `/api/{name}/schema` 的 `menus`，不要硬编码原型中的三组 |
| 任务列表 | `schema.tasks[task]` 的 `name/help/groups` |
| 任务详情 | 按 `groups[].fields[]` 通用渲染；字段标题、说明、当前值、readonly、disabled、options、validate 均来自 schema |
| 保存单字段 | `PATCH /api/{name}/config`，body `{key,value}`；按 `ok/invalid/message` 判断 |
| 立即执行任务 | `POST /api/{name}/task/{task}/run`；原型目前缺少但 WebUI 已有 |
| 工具任务 | `POST /api/{name}/tool/{task}/start`；与普通任务不能混用 |
| 特殊控件 | `item_table` 调 `/warehouse`；拦截战统计调 `/interception/stats`；导入调 `/interception/import`；路径选择在移动端不能调用桌面文件对话框 |

Flutter 至少要支持：`checkbox`、`select`、`multiselect`、`number`、`text`、`textarea`、`priority`、`path picker`、锁定/禁用、物品表、拦截战统计和特殊导入。不能用当前原型里的“执行模式/通知”两个虚拟字段替代真实任务字段。

#### 调度设置 Tab

| 原型元素 | 真实实现 |
| --- | --- |
| 任务列表 | `GET /api/{name}/schedule` 返回 `tasks[]` |
| 启用开关 | `enabled`；`enable_locked=true` 时只读 |
| 周期 | `cadence`: `daily/weekly/monthly`；`cadence_locked=true` 时禁止切换 |
| 每日 | `daily_times` |
| 每周 | `weekly_days`、`weekly_time` |
| 每月 | `monthly_day`、`monthly_time` |
| 下次运行 | `next_run`，只读展示 |
| 保存 | `POST /api/{name}/schedule/save`，body `{changes:[...]}`；整批校验，任一错误都不落盘 |
| 还原 | `POST /api/{name}/schedule/reset` |

原型只有两个固定任务和简单 time 输入，不足以承载真实调度。Flutter 应按接口动态生成任务行，并展示锁定原因和 422 `errors`。

#### 实时日志 Tab

| 原型元素 | 真实实现 |
| --- | --- |
| 日志流 | `WS /ws/{name}/log` |
| 现有 payload | `{type:"log", html: string|string[]}`，HTML 片段是给 Vue 插入的 |
| 级别筛选/自动滚动 | Flutter 本地筛选和滚动可以保留，但当前后端不会按级别过滤 WS |

实时日志先标记为待定，不纳入第一阶段后端对接验收。现有 HTML payload 不应在 Flutter 中通过正则解析；如果后续保留原生日志页，需要先确定结构化协议，否则使用原始 WebUI/WebView 作为过渡。

#### 画面 Tab

| 原型元素 | 真实实现 |
| --- | --- |
| 预览 | `GET /api/{name}/screenshot`，返回 JPEG；用定时器轮询并读取 `X-Captured-At` |
| 进入控制 | `GET /api/{name}/scrcpy` 返回 ws-scrcpy URL；不是 Flutter 原生输入协议 |
| Web 控制页 | `/scrcpy/{name}/` 及其静态资源 |

移动端第一版应将“进入控制”定义为 WebView/原始 WebUI 入口；如果要原生触控，需要新增 Android ADB 控制层，不能仅靠现有接口完成。

### 2.3 日志页

| 原型元素 | 真实实现 | 原型调整 |
| --- | --- | --- |
| 日期/来源选项 | `/api/system/logs/files` 返回 `{date,source}[]` | 动态生成，不写死日期和实例 |
| 级别 | `debug/info/warn/err` 阈值 | 将原型的 `WARN` 映射为后端 `warn`，`WARNING`/`CRITICAL` 统一展示 |
| 日志记录 | `records[]`: time、level、rank、source、text、kind、traceback | 支持 traceback 折叠，不只渲染 message |
| 匹配数量/截断 | `matched`、`truncated` | 区分匹配总数和当前显示数 |
| 刷新 | 重新请求 files/query | 增加 loading/error |
| 导出 | `/api/system/logs/download?date=&source=` | 导出当前文件，不包含筛选条件；文案要说明 |

### 2.4 设置、验证、初始化、更新

| 原型入口 | 当前后端 | 结论 |
| --- | --- | --- |
| STAR 验证 | Android `AccessGate` + `GatePage` 已实现 | Flutter 通过平台桥读取授权状态、打开验证、接收 OAuth 回调；不新增 Python 后端接口 |
| 初始化 NKAS | Android `SetupPage` + Termux/Bootstrap 已实现 | Flutter 通过平台桥启动、读取、刷新初始化步骤；iOS 隐藏；远程后端模式只做连接检查 |
| 后端地址 | 不属于 NKAS API | App 本地保存 control base URL；第一阶段直接探测 `/api/system/status`，token 暂不实现 |
| 原始 WebUI | `/app/` | 使用当前 base URL 拼接 `/app/`，在 WebView 或外部浏览器打开 |
| 主题 | Flutter 本地设置 | 不调用 `/api/system/theme`；WebUI 自己的主题独立保存 |
| 语言 | Flutter 本地设置 | 不调用 `/api/system/language`；需要处理后端 schema/queue/schedule 文案的语言来源 |
| 后台通知 | 待定 | Android 已有通知服务，但 App 开关与实例通知策略尚未确定 |
| 日志自动滚动 | 待定 | 先不承诺持久化或跨页面同步 |
| 更新 | `/api/system/update`、`/api/update/check`、`/api/update`、`/api/restart` | 接入源码更新；轮询 `checking/start/wait/run update/failed/idle`；不做单独启动器更新 |

当前 `/api/system/status` 只有 `api_version`、`spa_version` 和 `capabilities.spa/websocket`。第一阶段可以直接连接，不把 token 作为阻塞项；但应限制为可信局域网/本机地址，后续再补认证和能力项。

## 3. 接口清单

### 全局

```text
GET  /api/system/status         GET  /api/system/update
POST /api/update/check          POST /api/update
POST /api/restart               GET  /api/calendar
GET  /api/system/logs/files     GET  /api/system/logs
GET  /api/system/logs/download  GET  /api/serial/state
POST /api/serial/reset          GET  /api/system/deploy
PATCH /api/system/deploy        POST /api/system/deploy/reset
```

### 实例

```text
GET  /api/instances              POST /api/all/start
POST /api/all/stop               POST /api/{name}/start
POST /api/{name}/stop            GET  /api/{name}/schema
GET  /api/{name}/config          PATCH/POST /api/{name}/config
GET  /api/{name}/queue           GET  /api/{name}/schedule
POST /api/{name}/schedule/save   POST /api/{name}/schedule/reset
POST /api/{name}/task/{task}/run POST /api/{name}/tool/{task}/start
GET  /api/{name}/screenshot      GET  /api/{name}/scrcpy
POST /api/{name}/notify/test
```

### WebSocket

```text
WS /ws/state
WS /ws/{name}/queue
WS /ws/{name}/log
```

## 4. 必须修正的原型假设

1. `state.running`、`state.instanceRunning`、`state.starAuthorized`、`state.initialized`、`sourceUpdateAvailable` 等只能作为演示状态。生产 Flutter 中，后端状态来自 API/WS，STAR 和初始化状态来自 Android 平台桥。
2. 所有实例名、任务名、分组、调度任务、日志日期和活动内容都必须来自后端。
3. 总览服务状态可以用 `/api/system/status` 判断；只有 Android 本机模式允许通过 Termux 启停承载 API 的服务，停止后 UI 必须立即切换为“本地服务已停止”，不能继续等待 API 回包。
4. 任务详情不能只渲染两个虚拟字段，必须由 schema 决定字段和分组。
5. 实时日志与自动滚动暂不确定，不纳入第一阶段实现；不能把原型假筛选直接搬入生产代码。
6. 原型里的“实时·2s”不是现有接口保证的刷新频率，应改成实际捕获时间或“预览不可用”。
7. 设置页的“后端地址”不能只保存字符串；至少要有连接测试、超时、重试、断开态和 API 版本/能力检查。
8. 第一阶段按用户决策直接连接，不实现 token；必须在代码结构中预留认证请求拦截器，并明确当前仅适合本机或可信局域网。

## 4.1 远程连接契约

“后端地址”保存后，Flutter 至少执行以下流程：

```text
规范化 URL
  -> HTTP/HTTPS 健康探测 /api/system/status
  -> 校验 api_version
  -> 建立 WS/WSS 地址
  -> 读取实例和页面数据
```

现有路由没有统一的移动端认证中间件。第一阶段按当前决定直接连接，但 UI 应提示远程地址仅用于可信网络。HTTP 后端对应 `ws://`，HTTPS 后端对应 `wss://`，不能在 Flutter 中固定拼接本地地址。token/session 方案保留为待定，不阻塞第一阶段。

Android 当前还有一个必须先拆分的配置问题：`SettingsStore.webUiUrl()` 同时用于 App 控制地址和写入 Termux 的 `NKAS_WEBUI_URL/HOST/PORT`。如果用户把它改成远程地址，再运行本地初始化，可能会把本地服务监听地址和健康检查目标一起写成远程服务器。Flutter 接入前应拆成：

- `controlBaseUrl`：App 当前控制的本机或远程后端地址；
- `localServiceUrl`/`localServiceHost`/`localServicePort`：Android Termux 本地 NKAS 服务配置，默认 `127.0.0.1:12271`。

只有当前 `controlBaseUrl` 指向该本地部署时，才显示 Termux 服务启停按钮。

App 语言同样存在契约问题：schema、queue 和 schedule 的 `name/help/name_i18n` 当前由后端全局 `module.webui.lang` 生成，而 Flutter 语言是本地偏好。可选方案是让相关 GET 接口接受 `language` 参数，或让后端返回稳定 key、Flutter 自己翻译。第一阶段至少要避免调用 `/api/system/language` 改变远程 WebUI 的语言。

## 5. Flutter 工程与 HTML 原型的不一致

当前 `mobile/lib/main.dart` 仍然包含旧模型：

- `NkasPage.about` 独立页面；
- 顶栏右上角 Overflow 菜单，菜单项包含部署、关于、更新；
- 总览和实例使用本地 `serviceRunning`/`instance` 状态；
- 页面结构与 HTML 原型最终确定的“总览、实例、日志、部署、设置”五项导航不一致。

接入前应以 `mobile/design/nkas-mobile-interactive.html` 和本文件为准，先删除旧的页面/菜单模型：

1. 保留五项一级导航：总览、实例、日志、部署、设置。
2. 更新、STAR 验证、初始化、后端地址和原始 WebUI 都从设置进入。
3. 不在顶栏保留没有实际用途的菜单按钮。
4. `deploy` 是一级“部署”页面，消费 `GET/PATCH /api/system/deploy` 与 `POST /api/system/deploy/reset`，复刻 WebUI 部署页；设置里的“初始化 NKAS”仍是 Android 本机 Termux 流程，与部署页互不影响。

这样可以避免 Flutter 接 API 时同时维护旧页面和新原型两套状态。

## 6. 推荐分层与顺序

```text
ApiClient
  -> Repositories
    -> 状态层
      -> Overview / Instance / Logs / Settings
```

Repositories 至少拆为 `System`、`Instances`、`Config`、`Schedule`、`Calendar`、`Logs`、`Preview`。页面不要散落 `http.get`，也不要自行计算任务调度状态。

推荐顺序：

1. `system/status`、实例列表、实例状态 WS、实例启停。
2. queue WS、活动日历、历史日志查询/关键字/下载、源码更新。
3. schema/config 通用字段渲染、schedule 动态编辑和特殊控件。
4. 结构化实时日志、远程认证/能力协商、Android 初始化桥接、截图和控制 WebView。

每阶段覆盖首次加载、空数据、断开、超时、403/409/422、重连、实例切换和页面离开后的资源释放。
