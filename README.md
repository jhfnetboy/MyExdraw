# MyExDraw数字公共物品产品说明（免费与订阅分级）
这是一个使用Mycelium协议的范例DApp数字公共物品,希望具备这些特征：
- 数据存在你本地,不会因为身份和数据都在大平台而被360度裸体泄露
- 根据隐私程度，不同加密级别，存储到远端(not required)
- 链上存储用户身份,你是自由个体,可以随时在松散社区之间迁移
- 提供开源代码，可以自己部署,保持开源精神
- 提供公共物品，个人一定程度免费使用
- 提供订阅服务，个人或者小团队可以根据资源需要升级
## MyExDraw数字公共物品
- 面向对象：个人与小团队的私有白板与只读分享
- 能力与隐私：
- 自建私有画板与一键生成只读链接
- 端到端加密、密文存储，服务端不可见明文
- 链接 # 片段携带解密密钥，仅持有完整链接者可查看
- 分级方案：
- 免费版：可创建 1 个画布（本地编辑），服务器提供加密存储和分享链接，用于体验与个人使用，需要Reputation大于10,以及是Mycelium协议任意社区注册成员。
- 订阅 10 元/年：最多 100 个私密存储和公开分享链接/年（可滚动更新），适合小团队轻量共享，如果Reputation大于30,可以支付100 aPNTs 获得 1年订阅。
- 订阅 30 元/终生：最多 1000 个公开分享链接/终生，适合长期归档与广泛分享,如果Reputation大于50,可以支付300 aPNTs 获得 1年订阅。
- 计划节奏：
- 当前已提供核心功能（绘制/导出/查看）；登录与成员校验将按后续版本逐步开放

## Say thanks
- 本项目基于 Excalidraw 的开源工作构建与部署，感谢 Excalidraw 团队与社区的贡献：https://github.com/excalidraw/excalidraw
- 许可说明：Excalidraw 使用 MIT License；如涉及分发/二次发布，将保留其版权与许可文本以确保合规

## 开发与运维快捷命令（exdraw.sh）
仓库根目录提供了一个脚本 `./exdraw.sh`，只保留 3 个命令：docker / tunnel / test。

### 常见场景

1) 查看本机服务状态（不 build、不启动）

```bash
./exdraw.sh docker
```

2) Tunnel 重启（让公网域名指向本机服务）

```bash
./exdraw.sh tunnel
```

3) 公网域名健康检查（curl）

```bash
./exdraw.sh test
```

## 发布 Docker 镜像（可被任何人拉取）
https://hub.docker.com/r/aastar/myexdraw-excalidraw  

下面以 Docker Hub 为例（当前仓库发布到 `aastar/myexdraw-excalidraw:latest`）。

```bash
cd /Volumes/UltraDisk/Dev2/tools/MyExdraw

docker login

IMAGE="docker.io/aastar/myexdraw-excalidraw:latest"
docker buildx build --platform linux/amd64,linux/arm64 -t "$IMAGE" --push vendor/excalidraw
```

发布后，任何人可以在本仓库里用 1 条命令拉取并启动（Compose 会自动 pull 镜像）：

```bash
EXDRAW_EXCALIDRAW_IMAGE="docker.io/aastar/myexdraw-excalidraw:latest" docker compose up -d
```

说明：域名默认是 `https://myexdraw.aastar.io`，可用环境变量 `EXDRAW_PUBLIC_DOMAIN_BASE` 覆盖。


## 极简部署方案（无需订阅, FREE 版本）
如果你不需要复杂的实时协作，只想实现“**自建私有画板 + 一键生成只读分享链接**”的功能，部署过程会简单很多。你只需要关注**前端（Frontend）和存储后端（Storage）**。
需要你：
有一个自己的Mac mini
有一个cloudflared的账户
会一点技术

### 1. 核心原理

Excalidraw 的“分享链接”逻辑是：

1. 你在浏览器画好图，点击 **"Save to..." -> "Export to link"**。
2. 浏览器会对你的绘图数据进行 **端到端加密**。
3. 加密后的“密文”被发送并存储到你的自建后端（Storage Server）。
4. 生成的链接中，`#` 号后面的部分是**密钥**。因为 `#` 后的内容不会传给服务器，所以只有拥有完整链接的人才能解密并查看内容，你的服务器管理员也看不见内容。

---

### 2. 极简部署方案（Docker Compose）

由于你不需要协作（Room），我们可以去掉 `excalidraw-room` 镜像。

创建一个目录（如 `my-excalidraw`），编写 `docker-compose.yml`：

```yaml
services:
  web:
    image: nginx:1.27-alpine
    ports:
      - "9887:80"
    depends_on:
      - excalidraw
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    restart: unless-stopped

  excalidraw:
    image: myexdraw-excalidraw:local
    platform: linux/amd64
    expose:
      - "80"
    environment:
      - VITE_APP_BACKEND_V2_GET_URL=${EXDRAW_BACKEND_V2_GET_URL:-https://myexdraw.aastar.io/api/v2/scenes/}
      - VITE_APP_BACKEND_V2_POST_URL=${EXDRAW_BACKEND_V2_POST_URL:-https://myexdraw.aastar.io/api/v2/scenes/}
      - VITE_APP_HTTP_STORAGE_BACKEND_URL=${EXDRAW_HTTP_STORAGE_BACKEND_URL:-https://myexdraw.aastar.io/api/v2}
      - VITE_APP_STORAGE_BACKEND=${EXDRAW_STORAGE_BACKEND:-https}
    restart: unless-stopped

  excalidraw-storage:
    image: alswl/excalidraw-storage-backend:v2023.11.11
    platform: linux/amd64
    ports:
      - "9888:8081"
    depends_on:
      - redis
    environment:
      - PORT=8081
      - STORAGE_URI=redis://redis:6379
    volumes:
      - ./excalidraw_data:/app/storage
    restart: unless-stopped

  redis:
    image: redis:7
    volumes:
      - ./redis_data:/data
    command: ["redis-server", "--appendonly", "yes"]
    restart: unless-stopped

```

**运行命令：**

```bash
docker compose up -d

```

---

### 3. 如何操作实现“只读查看”

1. **编辑**：直接在你的域名或 IP（8080 端口）下画图。数据默认存在你的浏览器里，你随时打开这个网页都能看到上次的画作（只要没清缓存）。
2. **发布只读链接**：
* 点击左上角的 **"Save" (磁盘图标)**。
* 点击 **"Export to link"**。
* 系统会生成一个链接。由于你没有把“协作链接”发给别人，别人拿到这个链接后**只能查看，无法修改**你的原始画布。


3. **更新内容**：
* 如果你修改了画作，需要**重新点击 "Export to link"**。
* **注意**：Excalidraw 的链接分享本质上是“快照”。每次导出都会生成一个新的唯一 ID/链接。



---

### 4. 给 Jason 的特别建议（基于你的 PhD 背景）

既然你在研究 **ERC-4337** 和 **AAStar** 的数字公共物品，你可能会更喜欢这种更“干净”的维护方式：

* **数据确权**：由于数据是端到端加密存储在你的 `excalidraw-storage` 里的，这非常符合 Web3 的隐私逻辑。你的服务器只充当一个“无知的”数据中继（Relay）。
* **多画布管理**：Excalidraw 前端本身不支持“画板列表”。如果你想维护多个画板，建议：
* 把每个画板导出为 `.excalidraw` 文件存在本地。
* 或者利用浏览器的 **"Open"** 功能随时切换。
* **进阶版**：你可以把生成的“只读链接”整理成一个 Markdown 列表（比如在你的 GitHub 或 Notion 里），作为你的画板索引。



**你需要我为你提供一个 Nginx 的配置文件，好让这两个服务能通过 80/443 端口正常工作吗？**
