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

#### 补齐上面的文件再启动

```bash
docker compose up -d
```

