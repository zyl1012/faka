# Dujiao-Next + EPUSDT Docker Compose 部署

本目录部署以下服务：

- Dujiao-Next `v1.4.1` 发卡平台
- EPUSDT `v2.0.0` 收款平台
- PostgreSQL 16
- Redis 7

两个应用共用同一个 PostgreSQL 实例，但使用相互独立的数据库和账号。PostgreSQL、Redis 均不映射到宿主机端口；两个 Web 服务只监听宿主机 `127.0.0.1`，生产环境应通过 Nginx 或其他反向代理提供 HTTPS 访问。

## 服务和入口

| 服务 | 宿主机入口 | 容器内地址 | 说明 |
| --- | --- | --- | --- |
| Dujiao-Next 前台 | `http://127.0.0.1:8080/` | `http://dujiao-next:8080` | 发卡商城 |
| Dujiao-Next 后台 | `http://127.0.0.1:8080/dj-mgmt-c1379b345ceb/` | 同上 | 后台路径来自 `config/config.yml`，不是 `/admin` |
| EPUSDT 后台 | `http://127.0.0.1:8000/admin` | `http://epusdt:8000/admin` | 钱包、链、API Key 和订单管理 |
| PostgreSQL | 不对宿主机开放 | `postgres:5432` | 两个独立数据库 |
| Redis | 不对宿主机开放 | `redis:6379` | Dujiao 缓存和队列 |

管理员账号、初始密码、数据库密码、EPUSDT PID 和 Secret Key 保存在 `.env`。不要把 `.env` 提交到公开仓库，也不要把其中的值粘贴到日志、工单或聊天记录中。

在后台修改管理员密码不会自动回写 `.env`。在 EPUSDT 后台轮换 Secret Key 后，还需要同步更新 Dujiao 支付渠道和 `.env` 中的记录。

## 数据库布局

PostgreSQL 容器名为 `dujiaonext-postgres`，数据持久化在 `data/postgres/`：

| 应用 | 数据库 | 数据库账号 |
| --- | --- | --- |
| Dujiao-Next | `dujiao_next` | `dujiao` |
| EPUSDT | `epusdt` | `epusdt` |

EPUSDT 的业务数据，包括管理员、API Key、钱包地址和订单，均写入 PostgreSQL 的 `epusdt` 数据库。

`data/epusdt/runtime/epusdt-runtime.db` 仍然是 SQLite 文件。这是 EPUSDT 自身的运行时任务队列，不是业务主库。`data/epusdt/epusdt.db` 是切换 PostgreSQL 前保留的旧主库备份，当前配置不会再使用它。

Dujiao-Next `v1.4.1` 官方只实现 SQLite 和 PostgreSQL，不支持 MySQL。当前使用 PostgreSQL 也是官方推荐的生产部署方式。

## 目录说明

```text
.
|-- .env                              # 版本、端口和敏感参数
|-- docker-compose.yml                # 四个服务的 Compose 配置
|-- config/
|   |-- config.yml                    # Dujiao-Next 配置
|   `-- epusdt/epusdt.env             # EPUSDT 配置
|-- docker/epusdt/
|   |-- Dockerfile                    # 固定源码版本并构建兼容镜像
|   `-- postgres-compat.patch         # EPUSDT v2.0.0 PostgreSQL 补丁
`-- data/
    |-- postgres/                     # PostgreSQL 数据目录
    |-- redis/                        # Redis AOF 数据
    |-- uploads/                      # Dujiao 上传文件
    |-- logs/                         # Dujiao 日志
    `-- epusdt/                       # EPUSDT 日志和运行时 SQLite
```

## 启动

### 已初始化的当前环境

```bash
docker compose --env-file .env up -d
docker compose --env-file .env ps
```

EPUSDT 本地镜像已经构建完成，普通启动和重启不会重复编译。

### 全新服务器或空数据目录

PostgreSQL 官方镜像只会根据 `POSTGRES_DB` 自动创建一个数据库。首次部署到空数据目录时，应先启动 PostgreSQL 和 Redis，再创建 EPUSDT 的独立账号和数据库。

```bash
set -a
. ./.env
set +a

docker compose --env-file .env up -d postgres redis

until docker exec dujiaonext-postgres \
  pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
  sleep 2
done

docker exec -i dujiaonext-postgres psql -v ON_ERROR_STOP=1 \
  -U "$POSTGRES_USER" -d postgres \
  -v ep_user="$EPUSDT_POSTGRES_USER" \
  -v ep_pass="$EPUSDT_POSTGRES_PASSWORD" \
  -v ep_db="$EPUSDT_POSTGRES_DB" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'ep_user', :'ep_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'ep_user') \gexec

SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'ep_user', :'ep_pass') \gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'ep_db', :'ep_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'ep_db') \gexec

SELECT format('ALTER DATABASE %I OWNER TO %I', :'ep_db', :'ep_user') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'ep_db') \gexec
SQL

docker compose --env-file .env up -d --build
docker compose --env-file .env ps
```

首次构建 EPUSDT 需要访问 GitHub 和 Docker Hub。后续构建会使用 Docker 缓存。

## 常用命令

查看状态：

```bash
docker compose --env-file .env ps
```

查看日志：

```bash
docker compose --env-file .env logs --tail=200 dujiao-next
docker compose --env-file .env logs --tail=200 epusdt
docker compose --env-file .env logs --tail=200 postgres redis
```

重启单个服务：

```bash
docker compose --env-file .env restart dujiao-next
docker compose --env-file .env restart epusdt
```

停止全部服务但保留数据：

```bash
docker compose --env-file .env down
```

不要删除 `data/postgres/`。本项目使用宿主机目录持久化数据，因此 `docker compose down` 不会删除数据库，但手动删除 `data/` 会造成数据丢失。

## 健康检查

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8000/payments/gmpay/v1/config

docker exec dujiao-next \
  wget -qO- http://epusdt:8000/payments/gmpay/v1/config
```

预期 Dujiao 健康接口返回 `{"status":"ok"}`，EPUSDT 配置接口返回 `status_code: 200`。

检查两个 PostgreSQL 数据库：

```bash
docker exec dujiaonext-postgres \
  psql -U dujiao -d dujiao_next -c 'SELECT current_database(), current_user;'

docker exec dujiaonext-postgres \
  psql -U epusdt -d epusdt -c 'SELECT current_database(), current_user;'
```

## 配置 Dujiao 使用 EPUSDT

先登录 EPUSDT 后台完成以下配置：

1. 检查需要使用的链和代币是否启用。
2. 配置可用 RPC 节点。
3. 添加至少一个收款钱包地址。
4. 在 API Key 页面确认 PID 和 Secret Key。

然后在 Dujiao 后台创建 `EPUSDT` 支付渠道，主要字段如下：

| 字段 | 建议值 |
| --- | --- |
| `gateway_url` | 生产环境填写 EPUSDT 的公网 HTTPS 地址，例如 `https://pay.example.com` |
| `pid` | `.env` 中的 `EPUSDT_PID` |
| `secret_key` | `.env` 中的 `EPUSDT_SECRET_KEY` |
| `order_mode` | `cashier` 或 `transaction` |
| `token` | `transaction` 模式下填写，例如 `USDT` |
| `network` | `transaction` 模式下填写，例如 `tron` |
| `currency` | 通常填写 `cny` |
| `notify_url` | `https://你的发卡域名/api/v1/payments/callback` |
| `return_url` | 买家支付完成后返回的发卡平台公网地址 |

`http://epusdt:8000` 是 Docker 网络内地址，可用于 Dujiao 容器到 EPUSDT 的连通性检查，但不应作为生产支付渠道的 `gateway_url`。EPUSDT 返回的收银台 URL 会交给买家浏览器，浏览器无法解析 Docker 服务名 `epusdt`。

同时将 `config/epusdt/epusdt.env` 中的 `app_uri` 改为 EPUSDT 的公网 HTTPS 地址。修改后重启 EPUSDT：

```bash
docker compose --env-file .env restart epusdt
```

正式启用渠道前应使用小额订单完整验证下单、付款、链上确认、异步回调和发卡流程。

## EPUSDT PostgreSQL 兼容补丁

EPUSDT `v2.0.0` 虽然声明支持 PostgreSQL，但发布版本存在以下问题：

1. 管理员和系统设置查询中使用 MySQL 风格的反引号标识符，PostgreSQL 会返回语法错误。
2. 发布版本的 PostgreSQL 驱动与 GORM 版本组合会导致已有表重复迁移时报错。
3. 网页安装器会把配置模板重写为 SQLite，丢失 PostgreSQL 参数。

因此 Compose 不直接运行 `gmwallet/epusdt:v2.0.0`，而是通过 `docker/epusdt/Dockerfile`：

1. 固定拉取官方 `v2.0.0` 源码提交。
2. 应用 `docker/epusdt/postgres-compat.patch`。
3. 使用匹配的 PostgreSQL 驱动和 GORM 版本重新构建本地镜像 `epusdt-postgres:v2.0.0`。

这只是针对 PostgreSQL 的兼容修复，不改变 EPUSDT 的支付业务逻辑。普通重启不需要编译；只有本地镜像不存在、补丁变化或升级 EPUSDT 时才需要重新构建：

```bash
docker compose --env-file .env build epusdt
docker compose --env-file .env up -d --no-deps epusdt
```

升级 `EPUSDT_TAG` 前必须检查新版本是否已由上游修复这些问题，并同步更新 Dockerfile 中固定的提交哈希。补丁无法干净应用时，构建会主动失败，不能直接强行套用旧补丁。

## 备份

运行中的 PostgreSQL 应使用 `pg_dump` 进行一致性备份，不要直接复制正在写入的 `data/postgres/`。

```bash
set -a
. ./.env
set +a

umask 077
backup_dir="backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"

docker exec dujiaonext-postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc \
  > "$backup_dir/dujiao_next.dump"

docker exec dujiaonext-postgres \
  pg_dump -U "$EPUSDT_POSTGRES_USER" -d "$EPUSDT_POSTGRES_DB" -Fc \
  > "$backup_dir/epusdt.dump"

tar -czf "$backup_dir/config-and-files.tar.gz" \
  .env config docker docker-compose.yml README.md data/uploads
```

备份包包含数据库、配置和密钥，应限制文件权限并存放到加密的异地介质。恢复前先停止两个应用容器，并确认目标数据库和备份版本。

## 常见问题

### `http://127.0.0.1:8080/admin` 无法访问

Dujiao-Next 已配置自定义后台路径，当前入口是：

```text
http://127.0.0.1:8080/dj-mgmt-c1379b345ceb/
```

实际路径以 `config/config.yml` 中的 `web.admin_path` 为准，修改后需要重启 Dujiao-Next。

### EPUSDT 出现安装向导

检查以下文件是否存在并已挂载：

```text
config/epusdt/epusdt.env
```

其中 `install` 应为 `false`，`db_type` 应为 `postgres`。不要在当前 PostgreSQL 部署中重新提交网页安装向导，因为 v2.0.0 安装器会覆盖数据库配置。

### EPUSDT 可以打开但不能创建支付订单

优先检查：

- 是否添加并启用了钱包地址。
- 对应链、代币和 RPC 是否启用。
- Dujiao 渠道的 PID、Secret Key、网络和代币是否匹配。
- `gateway_url`、`notify_url` 是否为应用和买家都能访问的公网 HTTPS 地址。
- EPUSDT 和 Dujiao 容器日志中是否有签名或回调错误。

## 参考资料

- [Dujiao-Next Docker Compose 部署文档](https://dujiao-next.com/deploy/docker-compose)
- [Dujiao-Next 后台管理指南](https://dujiao-next.com/guide/admin-guide)
- [EPUSDT 项目](https://github.com/GMwalletApp/epusdt)
- [EPUSDT v2.0.0 Release](https://github.com/GMwalletApp/epusdt/releases/tag/v2.0.0)
