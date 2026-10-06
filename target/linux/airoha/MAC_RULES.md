# AN7581 HG5585F、XG-040G MD/TF MAC 公式

## 输入

| 输入 | 来源 |
| --- | --- |
| B | HG5585F：`factory-1m[0x2000..0x2005]`（旧资料中的 M）；040G：RI `[0x3e..0x43]` |
| W0 | HG5585F：`factory-1m[0x1004..0x1009]` |
| W1 | HG5585F：`factory-1m[0x100a..0x100f]`，独立读取，不从 W0 推算 |

`Add48(X,n)` 是六字节大端 MAC 加法，向高位进位。本规则包仅适用于
AN7581；MF/AN7583 不在此次构建、镜像核对或实机验证范围内。

## HG5585F

| 地址 | CT | CU |
| --- | --- | --- |
| DSA 上联 GDM1 (`eth0`)、PON GDM2 (`pon0`) | B | B |
| `lan1`（CT 外部 GDM4 / CU DSA port1） | `Add48(B,0x21)` | 同 CT |
| `lan2` / `lan3` / `lan4` | `Add48(B,0x22)` / `Add48(B,0x23)` / `Add48(B,0x24)` | 同 CT |
| `ra0` / `ra8` 的工厂地址 | W0 / W1 | W0 / W1 |

USB-SFP 变体：CT 的 `lan1=B+0x21`、`lan5=B+0x25`；
CU 的 `lan5=B+0x25`、`lan6=B+0x26`。
Wi-Fi 仍按现有 EEPROM 初始化，W0/W1 是工厂字段，最终无线 MAC
须实机核对。VEIP 的业务偏移不由 B 唯一决定。

## XG-040G MD/TF（AN7581）

| 地址 | 公式 |
| --- | --- |
| DSA 上联 GDM1 (`eth0`)、PON GDM2 (`pon0`) | B |
| `lan1`（GDM4） / `lan2` / `lan3` / `lan4` | `Add48(B,0x21)` / `Add48(B,0x22)` / `Add48(B,0x23)` / `Add48(B,0x24)` |
| MD USB-SFP 变体的 `lan5` | `Add48(B,0x25)` |

这些是镜像内 DTS 的初始化规则，不是在线地址的实测值。
`br-lan=B` 是目标，但软件桥无法仅靠 DTS 固定，需实机核对；
`omci0` 不在此处赋址。WAN 池、LLID、其它运行时业务 MAC 未更改。
同一 LAN GDM 组需保持 MAC 前三字节一致；B 接近低 24 位边界时，
加 `0x21` 可能跨前缀，需检查 FE/PPE 卸载。
