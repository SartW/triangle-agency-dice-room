# 三角机构 · 分部公共骰房

当前使用腾讯云 CloudBase 的 React + Vite 实现。无需注册，通过行动代号及六位房间代号进入。

## 功能

- 公开投掷 6D4，只统计 3 的数量，不计算总和或判定成功。
- 使用 @3d-dice/dice-box-threejs 的 Three.js / Cannon ES 物理骰盘。
- 灰色骰面、白色数字、数字 3 对应的红色顶角。
- 动画按云端生成的点数落定，公共记录保持一致。
- 玩家自选 1–6 枚、D2–D100 私人暗骰，可附加到明骰或单独投掷。
- 私人结果按当前浏览器设备身份返回；清除浏览器存储或更换设备不会继承原设备的私人记录。

## 恢复与开发

安装 Node.js 和 pnpm 后，在此目录运行：

```sh
pnpm install --frozen-lockfile
pnpm dev
pnpm build
```

src/PhysicsDice.tsx 是骰子引擎与红角纹理的适配器；src/cloudbase.ts 是匿名认证与 RPC 客户端；schema.sql 是数据库表、权限及函数的初始化来源。

## 腾讯云部署

1. 在 CloudBase 控制台启用「身份认证 → 登录方式 → 允许匿名登入」。
2. 仅在新建环境初始化时执行 schema.sql；已有环境更新网页不需要重跑数据库初始化。
3. 如迁移环境，修改 src/cloudbase.ts 的 ENV_ID 和 cloudbaserc.json。
4. 运行 pnpm build，在现有静态网站服务里上传 dist 文件夹。
5. 使用「其他」框架，目标及构建产物目录均为 ./，安装和构建命令留空，部署路径为 /triangle-agency-dice-room。

Vite 使用相对资源路径，兼容子目录部署。源码中环境 ID 是公开客户端配置，不包含云账户密钥。

## 存档说明

这个仓库保存源码、锁文件、数据库初始化 SQL 和部署说明，不保存云端房间、投骰记录或用户数据。数据库数据需通过 CloudBase 单独备份。

源码存档不会包含 node_modules、构建缓存、浏览器凭证、环境变量文件、角色卡或规则书。legacy-sites 保存迁移前版本的源码供参考。

## 第三方许可

骰子引擎来自 https://github.com/3d-dice/dice-box-threejs，采用 MIT 许可证。原版权声明保存在 public/licenses/dice-box-threejs.txt，并随构建发布。其他依赖许可由对应包保留。
