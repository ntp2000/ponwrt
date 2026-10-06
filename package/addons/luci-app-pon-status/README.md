# luci-app-pon-status

这是从 `luci-app-pon-status-0.2.0-r1.apk` 恢复出的 OpenWrt 25.12 LuCI
应用源码。

## 功能

该应用不是独立菜单页，而是通过 `status/include` 机制向 LuCI 概览页
插入一个 PON 光模块状态卡片。文件名 `15_pon.js` 使它排在系统卡片之后、
内存卡片之前。

页面执行以下数据链路：

```text
/etc/config/pon
    -> xpon section 的 device
    -> /usr/sbin/ponctl --device <device> status --json
    -> schema_version == 1 的 snapshot.frontend
    -> LuCI 概览页卡片
```

显示字段：

| 标签 | JSON 字段 | 单位 |
| --- | --- | --- |
| 收光功率 | `rx_power_dbm` | dBm，2 位小数 |
| 发光功率 | `tx_power_dbm` | dBm，2 位小数 |
| 光模块温度 | `temperature_celsius` | °C，2 位小数 |
| 偏置电流 | `tx_bias_ma` | mA，2 位小数 |
| 供电电压 | `voltage_volts` | V，4 位小数 |

## 目录

```text
root/usr/share/rpcd/acl.d/luci-app-pon-status.json
htdocs/luci-static/resources/view/status/include/15_pon.js
```

## 构建

将目录放入 LuCI 应用包目录后，使用 OpenWrt 25.12 的标准构建系统：

```sh
make menuconfig
# 选择 LuCI -> Applications -> luci-app-pon-status
make package/luci-app-pon-status/compile V=s
```

运行时需要 `airoha-ponctl` 提供 `/usr/sbin/ponctl`，并需要 `pon` UCI
配置中存在带 `device` 选项的 `xpon` section。
