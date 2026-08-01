# IM 服务测试脚本集

本目录包含 IM 服务的端到端测试脚本集合，涵盖性能测试、功能测试和连通性验证。支持 Linux (Bash) 和 Windows (PowerShell) 双平台。

## 目录结构

```
test-scripts/
├── common/
│   ├── utils.ps1                       # 通用工具函数库（PowerShell）
│   ├── utils.sh                        # 通用工具函数库（Bash）
│   ├── env.sh                          # 环境变量加载（.env 文件支持）
│   ├── db_utils.sh                     # 数据库工具函数（MySQL/MongoDB）
│   ├── test_data_factory.sh            # 测试数据工厂
│   └── data_quality_check.sh           # 数据质量验证
├── performance/                        # 性能测试脚本
│   ├── config.sh                       # 公共配置（基准数据、公式、报告生成）
│   ├── run_long_connection_test.sh     # 百万长连接测试 (TC-LC-001)
│   ├── run_single_chat_test.sh         # 单聊消息测试 (TC-SC-001/002) [Bash]
│   ├── run_single_chat_test.ps1        # 单聊消息测试 (TC-SC-001/002) [PowerShell]
│   ├── run_group_chat_test.sh          # 群聊消息测试 (TC-GC-100/200/1000) [Bash]
│   ├── run_group_chat_test.ps1         # 群聊消息测试 (TC-GC-100/200/1000) [PowerShell]
│   ├── run_chatroom_test.sh            # 聊天室消息测试 (TC-CR-1000/2000/5000)
│   ├── run_cluster_test.sh             # 集群性能测试 (TC-CL-001~004)
│   ├── run_mixed_workload_test.sh      # 混合负载测试 (TC-MX-001)
│   ├── calc_performance.sh             # 性能估算计算器
│   ├── stress_single_chat.toml         # stress-tool 单聊消息测试配置模板
│   ├── stress_group_chat.toml          # stress-tool 群聊消息测试配置模板
│   ├── stress_chatroom.toml            # stress-tool 聊天室消息测试配置模板
│   ├── lib_stress.sh                   # stress-tool 集成库
│   └── k6_single_chat.js               # k6 负载测试
├── square/                             # 广场功能测试
│   ├── test_moments_api.ps1            # 广场动态功能测试（PowerShell）
│   ├── test_moments_api.sh             # 广场动态功能测试（Bash）
│   ├── test_square_api.ps1             # 广场话题功能测试（PowerShell）
│   ├── test_square_api.sh              # 广场话题功能测试（Bash）
│   └── config.toml                     # stress-tool 广场压测配置
├── push/                               # 推送服务测试
│   ├── test_push_server.ps1            # 推送服务测试（PowerShell）
│   └── test_push_server.sh             # 推送服务测试（Bash）
├── spec/                               # 测试规范文档
│   └── IM服务性能测试规范.md
├── docker-compose.test.yml
├── setup.sh
├── .env.example
├── .github/workflows/test.yml
└── README.md
```

## 环境变量配置

可通过环境变量或 `.env` 文件配置目标服务地址（优先级：环境变量 > .env 文件 > 默认值）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `IM_HOST` | `localhost` | IM 服务器地址 |
| `IM_HTTP_PORT` | `80` | IM HTTP 端口 |
| `IM_ADMIN_PORT` | `18080` | IM Admin 端口 |
| `IM_ADMIN_SECRET` | `123456` | IM Admin 密钥 |
| `PUSH_HOST` | `localhost` | 推送服务器地址 |
| `PUSH_PORT` | `8085` | 推送服务端口 |
| `PUSH_ADMIN_PORT` | `8086` | 推送管理后台端口 |
| `MYSQL_HOST` | `localhost` | MySQL 地址 |
| `MYSQL_USER` | `root` | MySQL 用户名 |
| `MYSQL_PASS` | — | MySQL 密码 |
| `MYSQL_DB` | `imdb` | MySQL 数据库名 |
| `MONGO_HOST` | `localhost` | MongoDB 地址 |
| `MONGO_PORT` | `27017` | MongoDB 端口 |
| `CLUSTER_NODE_IPS` | — | 集群节点 IP（空格分隔） |
| `CLUSTER_AUTH_IP` | — | 集群授权节点 IP |

## 快速开始

### 环境配置

```bash
# 方法一: 环境变量
export IM_HOST="<your-im-server-ip>"

# 方法二: .env 文件
cp .env.example .env
# 编辑 .env 填入实际地址
```

### Linux (Bash)

```bash
# ===== 性能测试 =====

# 长连接测试
bash performance/run_long_connection_test.sh --mode check

# 单聊消息测试
bash performance/run_single_chat_test.sh --mode check
bash performance/run_single_chat_test.sh --mode send
bash performance/run_single_chat_test.sh --mode recv
bash performance/run_single_chat_test.sh --mode full

# 群聊消息测试
bash performance/run_group_chat_test.sh --mode check
bash performance/run_group_chat_test.sh --mode 100
bash performance/run_group_chat_test.sh --mode 200
bash performance/run_group_chat_test.sh --mode 1000

# 聊天室消息测试
bash performance/run_chatroom_test.sh --mode check
bash performance/run_chatroom_test.sh --mode 1000
bash performance/run_chatroom_test.sh --mode 2000
bash performance/run_chatroom_test.sh --mode 5000

# 集群性能测试
bash performance/run_cluster_test.sh --mode check
bash performance/run_cluster_test.sh --mode 1
bash performance/run_cluster_test.sh --mode 2
bash performance/run_cluster_test.sh --mode 3
bash performance/run_cluster_test.sh --mode 4

# 混合负载测试
bash performance/run_mixed_workload_test.sh --mode check
bash performance/run_mixed_workload_test.sh --mode full

# 性能估算计算器
bash performance/calc_performance.sh --all
bash performance/calc_performance.sh --single-chat
bash performance/calc_performance.sh --group-chat
bash performance/calc_performance.sh --chatroom
bash performance/calc_performance.sh --cluster
bash performance/calc_performance.sh --custom

# ===== 功能测试 =====

# 广场动态功能测试
bash square/test_moments_api.sh --user-id "your_user_id"

# 广场话题功能测试
bash square/test_square_api.sh --user-id "your_user_id"

# 推送服务测试
bash push/test_push_server.sh
```

### Windows (PowerShell)

```powershell
# 配置目标服务器
$env:IM_HOST = "<your-im-server-ip>"
$env:PUSH_HOST = "<your-push-server-ip>"

# ===== 性能测试 =====

# 单聊消息测试
.\performance\run_single_chat_test.ps1 -Mode check
.\performance\run_single_chat_test.ps1 -Mode send
.\performance\run_single_chat_test.ps1 -Mode recv

# 群聊消息测试
.\performance\run_group_chat_test.ps1 -GroupSize check
.\performance\run_group_chat_test.ps1 -GroupSize 100
.\performance\run_group_chat_test.ps1 -GroupSize 200
.\performance\run_group_chat_test.ps1 -GroupSize 1000

# ===== 功能测试 =====

# 广场动态功能测试
.\square\test_moments_api.ps1 -TestUserId "your_user_id"

# 广场话题功能测试
.\square\test_square_api.ps1 -TestUserId "your_user_id"

# 推送服务测试
.\push\test_push_server.ps1
```

## 测试覆盖范围

### 性能测试用例

| 编号 | 场景 | 脚本（Bash） | 脚本（PowerShell） | 参考基线 |
|------|------|-------------|-------------------|----------|
| TC-LC-001 | 百万长连接 | `run_long_connection_test.sh` | — | 100万在线30分钟无掉线 |
| TC-SC-001 | 单聊发送消息 | `run_single_chat_test.sh --mode send` | `run_single_chat_test.ps1 -Mode send` | 19,646条/秒 (16C48G) |
| TC-SC-002 | 单聊收发消息 | `run_single_chat_test.sh --mode recv` | `run_single_chat_test.ps1 -Mode recv` | 13,908条/秒 (16C48G) |
| TC-GC-100 | 百人群聊 | `run_group_chat_test.sh --mode 100` | `run_group_chat_test.ps1 -GroupSize 100` | 1,340条/秒, 单核分发8,375 |
| TC-GC-200 | 两百人群聊 | `run_group_chat_test.sh --mode 200` | `run_group_chat_test.ps1 -GroupSize 200` | 685.8条/秒, 单核分发8,573 |
| TC-GC-1000 | 千人群聊 | `run_group_chat_test.sh --mode 1000` | `run_group_chat_test.ps1 -GroupSize 1000` | 140条/秒, 单核分发8,750 |
| TC-CR-1000 | 千人聊天室 | `run_chatroom_test.sh --mode 1000` | — | 256条/秒, 广播32,000 |
| TC-CR-2000 | 两千人聊天室 | `run_chatroom_test.sh --mode 2000` | — | 103条/秒, 广播25,773 |
| TC-CR-5000 | 五千人聊天室 | `run_chatroom_test.sh --mode 5000` | — | 21.5条/秒, 广播13,440 |
| TC-CL-001 | 集群 - 单节点 | `run_cluster_test.sh --mode 1` | — | 6,537条/秒 (4C8G) |
| TC-CL-002 | 集群 - 双节点 | `run_cluster_test.sh --mode 2` | — | 9,459条/秒 (8C16G) |
| TC-CL-003 | 集群 - 三节点 | `run_cluster_test.sh --mode 3` | — | 13,400条/秒 (12C24G) |
| TC-CL-004 | 集群 - 四节点 | `run_cluster_test.sh --mode 4` | — | 16,080条/秒 (16C32G) |
| TC-MX-001 | 混合负载 | `run_mixed_workload_test.sh` | — | 加权容量估算 |

### 功能测试用例

| 编号 | 场景 | 脚本 | 说明 |
|------|------|------|------|
| TC-MT-001 | 发布广场 | `test_moments_api.sh` | 文本/图片/视频/链接 4 种类型 |
| TC-MT-002 | 发布评论/点赞 | `test_moments_api.sh` | 评论和点赞功能 |
| TC-MT-003 | 拉取广场 | `test_moments_api.sh` | 分页拉取和最新拉取 |
| TC-MT-004 | 删除广场/评论 | `test_moments_api.sh` | 删除后二次确认 |
| TC-MT-005 | 广场设置 | `test_moments_api.sh` | 背景图/可见条数/可见范围 |
| TC-MT-006 | 黑名单/屏蔽名单 | `test_moments_api.sh` | 权限隔离验证 |
| TC-MT-007 | 广场消息通知 | `test_moments_api.sh` | line=1 通道消息监听 |
| TC-MT-008 | 机器人广场 | `test_moments_api.sh` | 全局/普通机器人行为 |
| TC-SQ-001 | 广场服务连通性 | `test_square_api.sh` | IM 服务可达检查 |
| TC-SQ-002 | 广场信息查询 | `test_square_api.sh` | 广场列表/详情 |
| TC-SQ-003 | 话题发布与浏览 | `test_square_api.sh` | 发布/列表/详情 |
| TC-SQ-004 | 话题互动 | `test_square_api.sh` | 评论/点赞/删除 |
| TC-SQ-005 | 话题管理 | `test_square_api.sh` | 删除/举报/搜索 |
| TC-SQ-006 | 广场成员管理 | `test_square_api.sh` | 加入/退出/成员列表 |
| TC-SQ-007 | 广场消息通知 | `test_square_api.sh` | 通知监听 |
| TC-SQ-008 | 广场配置检查 | `test_square_api.sh` | 配置项验证 |
| TC-SQ-009 | 广场性能要点 | `test_square_api.sh` | 性能模型参考 |
| TC-PS-001 | 推送服务连通性 | `test_push_server.sh` | 端口可达检查 |
| TC-PS-002 | DeviceToken 注册 | `test_push_server.sh` | Token 存储验证 |
| TC-PS-003 | 离线推送触发 | `test_push_server.sh` | 推送触发验证 |
| TC-PS-004 | 推送静音/免打扰 | `test_push_server.sh` | 推送决策条件 |
| TC-PS-005 | 推送后台管理 | `test_push_server.sh` | 管理后台检查 |

## 性能基准速查

### 消息处理阶段单核性能 (16C48G)

| 阶段 | 单核速率 | 测试来源 |
|------|----------|----------|
| 发送阶段 | 1,227 条/秒/核 | 单聊发送测试 |
| 分发阶段 | 8,750 条/秒/核 | 群聊分发测试 |
| 通知+拉取阶段 | 2,978 条/秒/核 | 收发-发送推导 |
| 聊天室广播 | 13,000 条/秒/核 | 聊天室稳定值 |

### 集群扩展模型

| 节点数 | 总核心数 | 总体吞吐量 | 扩展系数 |
|--------|----------|------------|----------|
| 1 | 4C | 6,537 条/秒 | 1.0× (基准) |
| 2 | 8C | 9,459 条/秒 | 1.5× |
| 3 | 12C | 13,400 条/秒 | 2.0× |
| 4 | 16C | 16,080 条/秒 | 2.5× |
| N | N×4C | ≈ 6,537×(1+(N-1)×0.5) | — |

### 容量估算公式

```
单聊: 所需核心数 = 预估消息量(条/秒) ÷ 1,077 × 安全系数(≥1.5)
群聊: 所需核心数 = 预估消息量(条/秒) ÷ (8,750÷群人数) × 安全系数
聊天室: 所需核心数 = 预估消息量(条/秒) ÷ (13,000÷人数) × 安全系数
长连接: 所需核心数 = 预估连接数 ÷ 62,500 × 安全系数
集群: N节点吞吐 = 单节点吞吐 × (1 + (N-1) × 0.5)
混合: 加权单核速率 = 1 ÷ Σ(占比÷各类型单核速率)
```

## 前置条件

1. IM 服务已部署并可访问（HTTP 80 / Admin 18080）
2. MySQL 已配置并可达
3. 广场测试需要：
   - MongoDB 已配置
   - `moments.global_visible` 等配置项已设置
4. 推送服务已部署（8085 / 8086）
5. 集群测试需要 1~4 个 IM 节点 + `cluster-config.xml` TCP-IP 配置
6. 测试用户已在 IM 服务中注册
7. 压测需要 `stress-tool` 压测工具

## 通用工具函数

`common/` 目录提供可复用的测试基础设施：

| 文件 | 功能 |
|------|------|
| `utils.sh` / `utils.ps1` | 日志输出、断言、HTTP 请求、TCP 检查、重试机制、JSON 结果输出 |
| `env.sh` | `.env` 文件加载（自动读取键值对并导出为环境变量） |
| `db_utils.sh` | MySQL 连接检查/查询、MongoDB 连接检查/查询、消息分表统计 |

## 输出说明

- **PASS**（绿色）：测试通过
- **FAIL**（红色）：测试失败，需排查
- **SKIP**（黄色）：因前置条件不满足而跳过
- **INFO**（灰色）：补充信息
- **WARN**（黄色）：警告信息

脚本结束时输出汇总统计，失败时以退出码 1 退出（可用于 CI/CD 集成）。

## 判定标准

| 等级 | 条件 |
|------|------|
| 优秀 | 所有必采指标满足判定标准，且达到或超过参考基准 |
| 合格 | 所有必采指标满足判定标准，且不低于参考基准的 80% |
| 不合格 | 任一必采指标未满足判定标准 |
