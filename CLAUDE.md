# CLAUDE.md — mini-httpd 项目编程规范

## 1. 项目概述

- **项目名称：** mini-httpd — 安全静态文件 HTTP 服务器
- **语言：** Haskell (GHC 9.4+)，构建系统：Cabal 3.10+
- **许可证：** MIT
- **当前状态：** 已完成基本实现并通过测试
- **项目根目录：** `/home/simon/vibe-workspace/haskell-dojo/a-http-server`

---

## 2. 开发流程

严格遵循 **设计 -> 计划 -> 实现 -> 审查 -> 验证** 管线。

### 2.1 设计阶段（Design Spec）

创建规范文档于 `docs/superpowers/specs/YYYY-MM-DD-<project>-design.md`。

文档结构：
- 概述（Overview）
- 架构图（ASCII 架构图）
- 安全模型（表格形式）
- 数据流（ASCII 序列图）
- 关键设计决策（编号列表）
- 依赖项（表格：Package / Purpose）
- 范围外（Out of Scope，列表）
- 接口定义（CLI 参数 / 环境变量签名）
- 状态字段：`**Status:** Approved`

### 2.2 计划阶段（Implementation Plan）

创建实施计划于 `docs/superpowers/plans/YYYY-MM-DD-<project>-plan.md`。

文档结构：
- 目标（Goal）
- 架构（Architecture）
- 技术栈（Tech Stack）
- 文件映射表（File Map：文件路径 -> 职责）
- 编号任务（`### Task N: Title`），每项包含复选框步骤：
  - `- [ ] **Step N: 动作描述**` — 复选框 + 粗体步骤编号 + 祈使动词
  - 步骤中嵌入完整代码块和要执行的 shell 命令
  - 计划头中包含 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 指令

### 2.3 实现阶段

按计划逐任务执行。任务分离关注点：
- Task 1: 脚手架（Scaffold）
- Task 2: 测试（先于实现编写）
- Task 3: 核心模块实现
- Task 4: 可执行文件入口
- Task 5: E2E 验证
- Task 6: 最终测试和警告检查

### 2.4 验证阶段

验证步骤必须明确列出：
- 单元测试：`cabal test`
- E2E 测试：启动服务器 -> `curl` 命令 -> 关闭服务器
- 警告检查：`cabal build 2>&1 | grep -i warning` 必须无输出

---

## 3. 技能使用规范

| 技能 | 使用时机 |
|------|----------|
| `superpowers:brainstorming` | 任何创造性工作之前，探索需求和设计 |
| `superpowers:writing-plans` | 规范文档完成后、写代码之前 — 将规范转化为任务列表 |
| `superpowers:subagent-driven-development` | 执行实施计划时，独立任务使用独立 agent |
| `superpowers:executing-plans` | 替代 subagent-driven-development 的执行方式 |
| `superpowers:test-driven-development` | 先写测试、后写实现 |
| `superpowers:verification-before-completion` | 完成前必须做 E2E 验证 |
| `superpowers:using-superpowers` | 元技能，用于导航 superpowers 系统 |

---

## 4. Ultracode & Workflow 方法

### 任务驱动式实施计划

- 每个任务是一个标题节（`### Task N: Title`），包含复选框列表
- 文件映射表位于顶部，标明每个任务影响的文件
- 步骤格式：`- [ ] **Step N: 动作描述**`
- 每个创建/修改文件的步骤包含完整代码块
- 每个验证步骤包含确切的 shell 命令和预期输出

### 测试先行

- 测试套件在 Task 3 编写，核心实现在 Task 4，确保测试驱动 API
- WAI Application 测试：直接调用 Application，不通过网络
- 同步调用模式：
```haskell
runApp :: Application -> Request -> IO Response
runApp app req = do
    mv <- newEmptyMVar
    _ <- app req $ \r -> putMVar mv r >> return ResponseReceived
    takeMVar mv
```

### E2E 冒烟测试

Task 6 流程：
1. `cabal run mini-httpd &` — 后台启动服务器
2. `curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/` — 测试响应
3. `curl -s http://localhost:8080/` — 测试内容
4. `kill %1` — 关闭服务器

---

## 5. 提交规范

### 约定式提交格式

```
<类型>: <消息>
```

类型：
- `chore:` — 配置/基础设施（如 `.gitignore`）
- `docs:` — 文档（设计规范、实施计划）
- `build:` — 项目脚手架（`.cabal` 文件、源码存根、HTML 占位文件）
- `feat:` — 新功能
- `fix:` — 错误修复
- `refactor:` — 重构
- `test:` — 测试相关

### 原则

- **原子提交：** 每个提交是一个单一逻辑变更
- **线性历史：** 无合并提交
- **描述性消息：** 消息应准确说明变更内容
- **单一作者：** Simon-CHOU <mrsimonzhou@gmail.com>

---

## 6. 测试规范

### 框架与配置

- **框架：** `hspec` (>=2.10, <3)
- **测试类型：** `exitcode-stdio-1.0`，入口 `main = hspec spec`
- **Cabal 测试目标：** `test-suite mini-httpd-test`

### 测试模式

- 夹具设置/清理：`before mkTestRoot $ after cleanupTestRoot $ describe "mini-httpd" $ do ...`
- 临时目录：持久化路径 `/tmp/mini-httpd-test`（使用 `mkTestRoot`/`cleanupTestRoot`）

### 请求构建助手函数

```haskell
mkGet, mkPost, mkHead, mkPut, mkDelete :: ByteString -> Request
```

每个函数构造 `Request` 并设置 `rawPathInfo` 和 `pathInfo`。

### 响应体提取

```haskell
responseBodyBS :: Response -> BL.ByteString
responseBodyBS (ResponseBuilder _ _ b) = BB.toLazyByteString b
responseBodyBS (ResponseRaw _ _)       = error "不支持 ResponseRaw"
responseBodyBS (ResponseFile _ _ _ _)  = error "不支持 ResponseFile"
responseBodyBS (ResponseStream _ _ _)  = error "不支持 ResponseStream"
```

### 测试分类

- happy path（200、Content-Type、404）
- HEAD 请求（200、空 body）
- 安全（POST/PUT/DELETE 返回 405、路径遍历拦截、编码遍历拦截）
- 文档根目录（子目录服务）

### 安全测试模式

使用 `shouldSatisfy` 配合 `elem` 同时接受 404 和 403：
```haskell
status `shouldSatisfy` (`elem` [status404, status403])
```

---

## 7. 安全规范

### 方法白名单

- 仅允许 GET 和 HEAD
- 其他方法返回 405，响应头 `Content-Type: text/plain; charset=utf-8`

### 路径遍历防护（双重规范化策略）

1. 对文档根目录执行 `makeAbsolute` + `canonicalizePath`
2. 给根目录追加尾部 `/`，防止前缀匹配攻击（如 `/var/public` vs `/var/public-extra`）
3. 对请求路径执行 `makeAbsolute` + `canonicalizePath`
4. 通过 `isPrefixOf` 验证解析后的路径是否以规范化根目录开头
5. 若文件不存在，先规范化父目录再重构路径做前缀检查
6. 拒绝空文件名、`.` 和 `..`
7. 拒绝根路径 `"/"`

### 信息泄露防护

- 文件不存在和路径遍历检测均返回 404（不区分 403）
- 无目录列表功能
- 请求路径超出文档根目录时不泄露文件是否存在

### 其他安全措施

- Content-Type 通过 `defaultMimeLookup` 从文件扩展名推断（`Network.Mime`）
- HEAD 请求与 GET 逻辑相同但返回空 body
- Warp 内建保护：slowloris 防护、超时、请求头限制
- 服务器名称通过 `setServerName "mini-httpd"` 设置
- 启动时验证文档根目录：`doesDirectoryExist` 检查；拒绝 `"/"`

---

## 8. 常用命令

```bash
# 刷新包索引
cabal update

# 构建所有目标
cabal build

# 运行测试套件
cabal test

# 运行服务器
cabal run mini-httpd

# 后台运行用于 E2E 测试
cabal run mini-httpd &
kill %1

# 检查警告
cabal build 2>&1 | grep -i warning

# GHCup 安装（需要时）
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
```

---

## 9. 目录结构

```
.
├── app/                        # 可执行文件入口
│   └── Main.hs                 # 服务器入口：参数解析、Warp 启动
├── src/                        # 库代码
│   └── Server.hs               # serveStatic 核心逻辑
├── test/                       # 测试套件
│   └── Spec.hs                 # hspec 测试
├── public/                     # 静态文件根目录（默认 DOCUMENT_ROOT）
│   └── index.html              # 默认首页
├── docs/                       # 文档
│   └── superpowers/
│       ├── specs/              # 设计规范
│       │   └── YYYY-MM-DD-<project>-design.md
│       └── plans/              # 实施计划
│           └── YYYY-MM-DD-<project>-plan.md
├── mini-httpd.cabal            # Cabal 构建配置
└── .gitignore                  # Git 忽略规则
```

### Cabal 构建目标

| 目标 | 类型 | 源目录 | 依赖 |
|------|------|--------|------|
| `mini-httpd` | library | `src/` | base, wai, http-types, mime-types, directory, filepath, bytestring, text |
| `mini-httpd` | executable | `app/` | base, mini-httpd, warp, wai, directory, filepath |
| `mini-httpd-test` | test-suite | `test/` | base, mini-httpd, hspec, wai, http-types, bytestring, directory, filepath, temporary |

### GHC 编译选项（通过 `common warnings` stanza）

```
-Wall -Wcompat -Widentities -Wincomplete-uni-patterns
-Wmissing-export-lists -Wpartial-fields -Wredundant-constraints
```

### 语言约定

- 语言扩展：仅 `OverloadedStrings`
- 默认语言：`Haskell2010`
- 显式导出列表：`module Server (serveStatic) where`
- 限定导入：`qualified Data.ByteString.Lazy as BL`
- Haddock 注释：`-- |` 用于导出函数
- 错误处理：`Control.Exception.try` 配合 `IOException`
- 模式守卫：`m | m == methodGet -> ...`
