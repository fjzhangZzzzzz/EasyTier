# Homelab EasyTier Web 有限候选

这是隔离评估候选，版本及上游来源以 [HOMELAB_FORK.json](HOMELAB_FORK.json) 为准。上游许可证及原作者归属保留；本候选不代表 EasyTier 官方发布，也没有投入 Homelab 生产。

## 改动范围

- 引入上游 PR #2702 的设备 Token 与界面，修正内置认证到实际控制会话、配置版本及运行配置协调的账户归属。
- 首次认领、同 UUID 刷新及未撤销判断使用一次原子 SQLite UPDATE，以更新行数决定授权结果；并发抢占只能一个 UUID 成功。
- Manual 中央网络支持官方已有 `peers[].peer_public_key`，贯通界面、API、SQLite、编译、成员覆盖及配置导出。旧 URL-only 数据仍可读取；旧客户端省略字段时不得静默删除已保存的 pin。
- 安全网络添加设备默认采用上游独立凭据模式，界面默认 180 天；14 天内到期及已到期成员显示警告。只提供界面提醒，没有新增自动续期或通知服务。
- 修正 Token 撤销提示，保留外部 Webhook 模式的原有接入界面行为。未改变外部 JSON 认证协议；进程内账户归属字段不能由外部响应注入。

没有修改官方 Core、Windows GUI、驱动或组网协议。没有实现客户端自动升级、硬件身份认证或新的授权服务。

## 两种凭据

**配置通道 Token** 绑定第一次使用的设备 UUID，后续持续认证远程配置通道。它是 bearer 凭据，UUID 绑定不是硬件证明；首次使用前被窃取仍存在抢先认领风险。它不是有短期限的一次性安装票据。当前兼容模型将其原值保存在受限 SQLite，已登录管理员能够重新取得；不声称哈希存储或仅展示一次。

**网络凭据** 使用上游 Secure Mode 独立凭据模式（上游内部仍称 `temporary`），普通终端不接收网络共享主密钥。移除网络成员才能撤销该凭据并更新管理员配置；只撤销配置 Token 不会撤销已落盘的 VPN 凭据。离线管理员、配置传播及缓存会影响实际撤权，必须在采用前测量，不承诺瞬时全网撤权。

180 天到期后复用上游移除、重新添加成员的签发机制；操作前保存地址、成员覆盖及 ACL，重新添加后复核，因为成员 UUID、凭据和关联 ACL 会变化，连接可能中断。没有自定义无感续期服务。自动企业微信到期提醒尚未实现，不能将界面警告当作推送收达。

## 构建与验证

依赖 Rust 1.95、Node、pnpm、protoc，以及上游要求的本机编译工具。依赖以提交的锁文件为准。

```sh
pnpm install --frozen-lockfile
pnpm --dir easytier-web/frontend build
cargo +1.95 fmt -p easytier-web --check
cargo +1.95 test --locked -p easytier-web -- --test-threads=4
cargo +1.95 build --locked -p easytier-web --features embed
```

浏览器测试使用模拟 API；真实官方控制客户端和 SQLite 回归在 Rust 测试中。两类结果分别报告，不把它们当成已经完成真实浏览器到真实生产网络的全链路验收。

```sh
cd easytier-web/frontend
pnpm exec playwright install chromium
node --test tests/dashboard.test.mjs
```

官方二进制互通测试须先校验工件；只设置 `EASYTIER_TEST_OFFICIAL_CORE` 为已核验的官方 Core 路径，再显式执行：

```sh
cargo +1.95 test --locked -p easytier-web official_core_enrolls_persists_pins_and_loses_control_access_after_revocation -- --ignored --nocapture
```

该项仅启动回环配置服务、无 TUN 测试实例并写临时配置，不安装系统服务；另在控制服务不响应时，从刚下发的同一目录重新启动官方 Core，通过官方 CLI 核对缓存实例和公钥。测试子进程退出后清理。测试生成的凭据不得用于生产。大型连接压力测试保留上游忽略状态，不为本次小规模接入修改系统限制。

CI 工作流只在本候选分支构建和上传带来源、版本、SHA256 清单的 Linux 工件，不创建 GitHub Release、不推送镜像、不部署。CI 工件不是生产发行承诺；正式发布前必须完成评审并递增候选版本，生产部署仍使用已提交发布包。

## 采用前与回退

未来采用必须关闭自助注册、禁止用户名 Token 回退、不启用自动创建账户；其中 `--disable-registration --disallow-username-tokens` 为必选。管理页面与配置通道都需要受保护入口，不能因为 HTTP 管理页使用 HTTPS 就认为 UDP/TCP 配置通道自动获得 TLS。公网配置入口应单独验证官方 WSS 与反向代理路径。

SQLite 新增设备 Token 表及 `networks.peers` 列。升级前备份数据库及配套工件；降级恢复对应备份，不运行旧 Web 写入新数据库。公钥迁移明确拒绝有损 `down`，避免静默丢失信任约束。

新托管实例由 Web 独占配置，仓库保存导出和恢复依据；现有本地 TOML 实例保持原管理入口，不能同时覆盖同一实例。后续仍需验证 Windows GUI 服务安装、持久目录、服务开机恢复、升级和回退、真实撤权传播以及资源预算；Core 进程的隔离缓存冷启动测试不能代替系统服务验收。

上游具备等价能力并通过迁移与回归后，删除对应本地补丁并回归官方构建。新增补丁必须说明不能直接使用官方机制的原因，不扩大到自研客户端或数据面。
