# 华南农业大学校园网自动登陆（OpenWrt）

本目录包含路由器上正在使用的门户网页登录脚本、每 5 分钟运行一次的监测循环，以及 OpenWrt `procd` 服务定义。服务已配置为开机启动；检测到网络正常时不会重复登录，发现门户跳转时才提交网页登录请求。

## 文件

- `login.sh`：检查互联网连接；如果被校园网门户拦截，则模拟浏览器获取会话并提交登录。
- `campus-login-watchdog.sh`：常驻循环，每 300 秒调用一次登录检查。
- `campus-login.init`：OpenWrt `procd` 服务定义，负责开机启动和异常退出后拉起。

## 部署到 OpenWrt

以下示例假设本目录在电脑的 `~/scau-campus-login`，路由器地址是 `192.168.1.1`。

1. 复制文件到路由器（此路由器使用 Dropbear；`scp -O` 使用其兼容的旧 SCP 协议）：

   ```sh
   scp -O -r ~/scau-campus-login root@192.168.1.1:/root/
   ```

2. SSH 登录路由器并安装脚本：

   ```sh
   ssh root@192.168.1.1
   cp /root/scau-campus-login/login.sh /root/login.sh
   cp /root/scau-campus-login/campus-login-watchdog.sh /root/campus-login-watchdog.sh
   cp /root/scau-campus-login/campus-login.init /etc/init.d/campus-login
   chmod 700 /root/login.sh /root/campus-login-watchdog.sh /etc/init.d/campus-login
   ```

3. 如需更换校园网账号，在路由器上编辑 `/root/login.sh` 中的 `USERNAME` 和 `PASSWORD`，然后启用并启动服务：

   ```sh
   vi /root/login.sh
   /etc/init.d/campus-login enable
   /etc/init.d/campus-login restart
   ```

## 检查运行状态

```sh
/etc/init.d/campus-login status
ps w | grep campus-login-watchdog
logread | grep campus-login
wget --no-check-certificate -q -T 10 -O /dev/null https://www.baidu.com
echo $?
```

联网正常时，`wget` 的退出码应为 `0`。服务每轮间隔 300 秒；服务启动后会先立即进行一次检查。校园网门户或认证流程发生变化时，可查看 `logread` 输出定位问题。

停止或取消开机启动：

```sh
/etc/init.d/campus-login stop
/etc/init.d/campus-login disable
```

路由器上的脚本权限应保持为仅 root 可读写执行（`chmod 700`）。
