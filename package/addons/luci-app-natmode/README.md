# luci-app-natmode

这是从 `luci-app-natmode-0.1.3-r2.apk` 恢复出的 OpenWrt 25.12 LuCI
应用源码。

## 功能

- `fullcone`：通过 `firewall.@defaults[0].fullcone=1` 使用 Full Cone NAT
  （NAT1）。
- `restricted`：关闭 Full Cone，使用 firewall4 默认的 masquerade
  （脚本标记为 NAT3）。
- `symmetric`：关闭 Full Cone，并在每个 `srcnat_<zone>` 链插入
  `meta nfproto ipv4 masquerade fully-random`，实现随机源端口行为
  （脚本标记为 NAT4）。
- 可选开启 `fullcone6`。
- 应用 NAT4 时可自动关闭软件和硬件 flow offload。

## 运行逻辑

`/usr/sbin/natmode-apply` 是唯一的应用入口：

```text
apply [mode] [fullcone6] [auto_offload]
reapply
status
sync
cleanup
```

`/etc/init.d/natmode` 在 firewall4 之后启动，并通过 procd 监听 firewall
和 natmode 的重载事件。firewall4 重载后，服务会重新插入 NAT4 的 nft 规则。
LuCI 页面打开时也会调用 `status`，因此会执行状态同步和规则自愈。

## 目录

```text
root/etc/config/natmode
root/etc/init.d/natmode
root/usr/sbin/natmode-apply
root/usr/share/luci/menu.d/luci-app-natmode.json
root/usr/share/rpcd/acl.d/luci-app-natmode.json
htdocs/luci-static/resources/view/natmode/mode.js
```

## 构建

将目录放入 LuCI 应用包目录后，使用 OpenWrt 25.12 的标准构建系统：

```sh
make menuconfig
# 选择 LuCI -> Applications -> luci-app-natmode
make package/luci-app-natmode/compile V=s
```

运行时需要目标固件提供 firewall4、nftables、`nft_fullcone` 内核模块和
LuCI/rpcd 的 file exec 能力。
