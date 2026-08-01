# amazon linux 2023 部署

## 安装docker

```bash
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl enable --now docker

sudo usermod -aG docker $USER
newgrp docker
```

## 安装docker-compose

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins

sudo curl -SL \
  "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose

sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

docker compose version  
```


## 更新docker compose buildx

```bash
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64)
    BUILDX_ARCH="amd64"
    ;;
  aarch64|arm64)
    BUILDX_ARCH="arm64"
    ;;
  *)
    echo "不支持的 CPU 架构：$ARCH"
    exit 1
    ;;
esac

BUILDX_VERSION="v0.36.0"

sudo mkdir -p /usr/local/lib/docker/cli-plugins

sudo curl -fSL \
  "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-${BUILDX_ARCH}" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx

sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
docker buildx version
```

## 安装git

```bash
sudo yum install -y git
```

## 安装发卡平台

```bash
git clone https://github.com/zyl1012/faka
```

#### 注意这里缺失一些文件

- .env
- config/config.yml
- config/epusdt/epusdt.env


#### 注意先进行数据库初始化
```baseh
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

#### 补齐上面的文件再启动

```bash
docker compose up -d
```

#### epusdt需要通过下面的方式获取密码

```bash
docker compose --env-file .env logs epusdt | grep -A4 'Default admin account created'
```


