# 安卓预装组件安全审计

对两台小米手机（HyperOS 3 / Android 16、MIUI 13 / Android 12，均已 root）的预装系统组件进行安全与隐私审计，记录各组件的权限、外传端点、反编译结果、设备端抓包证据与卸载处置过程。

| 项目 | 内容 |
|---|---|
| 审计对象 | 15 个预装组件（系统安全栈、运营商定制服务、高通组件） |
| 审计设备 | 2 台，均为本人所有，root 环境 |
| 审计时间 | 2026-11 |
| 审计手段 | manifest 解析、dex 端点提取、jadx 反编译、设备端 tcpdump 抓包、卸载与恢复验证 |
| 主要结论 | 6 个组件具备联网上报结构；1 个组件取到完整外传报文，以明文 HTTP 传输 SIM 卡标识与街道级定位；1 个组件具备通话场景下的录音与录屏能力 |

---

## 一、审计目的

1. 确定每个预装组件在何种条件下主动向外部发送数据；
2. 确定发送的数据内容与传输方式，并取得可复核的报文证据；
3. 确定组件是否具备录音、录屏等采集能力，以及采集的触发条件与持续时长；
4. 确定移除组件后系统的功能影响，并提供可回滚的处置方案。

---

## 二、审计对象

| 组件 | 包名 | 版本（设备 A / 设备 B） |
|---|---|---|
| 手机管家 / 安全中心 | `com.miui.securitycenter` | 12.8.7-260927.0.1 / 12.x |
| 系统安全组件 | `com.miui.guardprovider` | 3.0.7-20260708.0 / — |
| 安全组件（安全中心插件） | `com.miui.securityadd` | 9.12.42-260723.0.1 / — |
| 安全数据上报服务 | `com.xiaomi.security.onetrack` | 1.0.250813 / — |
| SystemHelper（运营商定制） | `com.mobiletools.systemhelper` | 3.0.1-20260313 / 1.2-20200429 |
| RegService（移动 DM） | `com.miui.dmregservice` | — / — |
| 终端自注册（联通、广电） | `com.xiaomi.registration` | — / 不存在 |
| 终端自注册（电信） | `com.qualcomm.qti.autoregistration` | 不存在 / 3.0 |
| QMS Telemetry | `com.qualcomm.qti.qms.service.telemetry` | 不存在 / 1842253 |
| System Helper Service（高通） | `com.qualcomm.qti.services.systemhelper` | 1.1 / 不存在 |
| Log generator | `com.bsp.catchlog` | 1.6.2 / 12 |
| Device Statistics | `com.qualcomm.qti.devicestatisticsservice` | 16 / 12 |
| Device Info | `com.qti.qualcomm.deviceinfo` | 16 / 12 |
| 联通预制应用 | `com.sinovatech.unicom.ui` | — / 不存在 |

设备信息：

| 设备 | 机型 | 系统 | Root | SIM |
|---|---|---|---|---|
| A | Redmi 24117RK2CC（zorn / K80） | Android 16 / HyperOS 3.0.307.0.WOKCNXM，补丁 2026-08-01 | KernelSU | 中国电信 + 中国联通 |
| B | Xiaomi M2002J9E（vangogh / 米 10 青春版） | Android 12 / MIUI 13.0.7.0.SJVCNXM，补丁 2022-09-01 | Magisk | 无 |

---

## 三、审计方法

| 阶段 | 手段 | 产出 |
|---|---|---|
| 静态分析 | apktool 解析 manifest，提取权限、组件、exported、sharedUserId | 权限表、组件表 |
| 端点提取 | 正则扫描 dex，提取 URL、域名、上报字段名 | 域名与接口清单 |
| 代码审计 | jadx 反编译，从 Receiver / Service / Provider 入口沿调用链下钻 | 方法级行为结论 |
| 动态验证 | 设备端 tcpdump 抓包，配合 dumpsys alarm 定位定时器 | pcap 原始报文 |
| 处置验证 | `pm uninstall -k --user 0` 后核查进程、业务功能与系统报错 | 处置记录 |
| 回归验证 | `cmd package install-existing --user 0` 恢复并复测 | 恢复脚本 |

结论按证据强度分三档标注：【实测】为设备上实际观察到的报文与命令回显；【静态】为从 APK 读到的结构与代码；【推断】为由前两者推出、无直接证据的判断。判定口径见 [`docs/00-方法与证据等级.md`](docs/00-方法与证据等级.md)。

---

## 四、检测结果

### 4.1 外传能力与实测证据

| 组件 | 包名 | 外传能力 | 实测外传 | 采集内容 | 风险 |
|---|---|---|---|---|---|
| SystemHelper | `com.mobiletools.systemhelper` | 有 | **有，取得完整报文** | SIM ICCID、IMEI、IMSI、精确定位与街道地址、应用列表、信号与 WiFi 状态 | 高 |
| 手机管家 / 安全中心 | `com.miui.securitycenter` | 有 | 窗口内未观测到 | 短信、通话记录、联系人、麦克风、OAID、本地敏感词检测、日志导出 | 高 |
| 系统安全组件 | `com.miui.guardprovider` | 有 | 窗口内未观测到 | 应用清单、设备 ID、通话音频、屏幕与视频帧 | 高 |
| 安全组件（插件） | `com.miui.securityadd` | 有，含 VpnService | 窗口内未观测到 | 短信收发、摄像头、高德定位、热更新 | 高 |
| RegService（移动 DM） | `com.miui.dmregservice` | 有 | 窗口内未观测到 | 基站、SIM 卡、电池、蓝牙、网络、WiFi 列表、屏幕快照开关 | 中高 |
| 终端自注册（电信） | `com.qualcomm.qti.autoregistration` | 有 | 未触发 | IMEI1/2、MEID、MAC、SIM1/2 ICCID 与 IMSI、CELLID/BID/NID/SID | 中高 |
| 终端自注册（联通、广电） | `com.xiaomi.registration` | 有 | 窗口内未观测到 | IMEI、ICCID、IMSI、机型、系统版本、网络类型 | 中 |
| QMS Telemetry | `com.qualcomm.qti.qms.service.telemetry` | 有 | 窗口内未观测到 | MCC、MNC、机型、使用统计 | 中 |
| 安全数据上报服务 | `com.xiaomi.security.onetrack` | 间接 | 无网络权限 | 安全类事件，转交 `com.miui.analytics` 上报 | 中 |
| Device Info | `com.qti.qualcomm.deviceinfo` | 视版本 | 无 | 本地展示 IMEI / MEID / ICCID | 低 |
| Device Statistics | `com.qualcomm.qti.devicestatisticsservice` | 无 | 无 | 本地统计 | 低 |
| System Helper Service | `com.qualcomm.qti.services.systemhelper` | 无 | 无 | 无网络权限 | 低 |
| Log generator | `com.bsp.catchlog` | 无 | 无 | 本地日志文件 | 低 |

逐包字段、权限、端点见 [`data/components.csv`](data/components.csv)、[`data/endpoints.csv`](data/endpoints.csv)。

### 4.2 已取得报文的外部传输

`com.mobiletools.systemhelper` 在开机后 4 分钟、SIM 变更或信号/应用变化时发起上报：

```
POST /register?ver=5.0&model=24117RK2CC&manuf=Xiaomi&sign=... HTTP/1.1
Host: dm.wo.com.cn:18080
Content-Type: application/encrypted-json
Content-Length: 1056
```

| 观察项 | 结果 |
|---|---|
| 传输方式 | 明文 HTTP，端口 18080，无 TLS |
| 报文体 | 加密 JSON，长度 1056 与 1040 字节各一次 |
| 传输字段 | `IMEI1/2`、`ICCID1/2`、`IMSI1/2`、`TAC/CID/PCI`、`BSSID/RSSI/LinkSpeed/Frequency`、`VolteEnabled/5GEnabled/VoNREnable`、`Esim`、`AppInfo`、`RegType`、`SigInfo` 等 40 余项 |
| URL 参数 | `ver`、`model`、`manuf`、`sign`，明文暴露机型、厂商与签名 |
| 服务端响应 | `429 Too Many Requests` |
| 原始文件 | `evidence/pcap/zorn-systemhelper-dm.wo.com.cn.pcap` |

同组件在本地偏好文件中明文留存两张 SIM 的 ICCID 与一次百度逆地理结果（省级、市级、区级、街道级与行政区划码），已按 [`evidence/README.md`](evidence/README.md) 的规则脱敏后记录于 [`docs/01-基础审计.md`](docs/01-基础审计.md) 第 4.4 节。

### 4.3 录制能力与触发条件

具备录音与录屏能力的是 `com.miui.guardprovider`（系统显示名「系统安全组件」），依据为其 `AiGuardService` 与 `com.miui.guardprovider.aiguard` 包内的实现，不属于 `com.miui.securitycenter`。

| 触发场景 | 采集内容 | 依据 |
|---|---|---|
| 普通语音通话（命令值 1） | 麦克风音频 | 【静态】`FOREGROUND_SERVICE_TYPE_MICROPHONE`，启动后录音 |
| 视频通话（命令值 2） | 屏幕画面与音频 | 【静态】前台服务类型掩码 160 = `MEDIA_PROJECTION (32) + MICROPHONE (128)` |
| 仅同步开关（命令值 3） | 不采集 | 【静态】在 `startForeground` 之前返回 |
| 非通话、开关关闭、权限被收回、未知命令 | 不采集，服务自行停止 | 【静态】权限检查失败后记录日志并跳过，未知命令调用 `stopSelf()` |

采集行为特征：

- 非连续录制，仅在通话期间启动，录制片段用于判定后上传，文件名为 `clip.mp4`；
- 上传路径为 `Files.readAllBytes` → Base64 → `{"streamName":"clip.mp4","fileBase64":...,"requestId":UUID}` → `detection-aigc.engine.miui.com`；
- 运行期间为前台服务，通知栏存在常驻通知；
- 视频通话录制需用户授予屏幕录制权限，授权弹窗可拒绝。

发起采集指令的调用方未定位到具体组件，现有结论由命令值语义反推。

### 4.4 权限与组件风险

| 发现 | 组件 | 依据 |
|---|---|---|
| 以 `android.uid.system` 身份运行 | `com.miui.securitycenter`、`com.bsp.catchlog` | 【静态】sharedUserId |
| 持有 `BIND_VPN_SERVICE` | `com.miui.securityadd`（`LinkBoostService`，用途网络加速） | 【静态】manifest；两台设备均未启用 VPN 通道 |
| exported Provider 无调用方限制以外的保护 | `SensitiveWordDetectProvider`、`DumpLogProvider` | 【静态】需签名级权限方可调用 |
| 具备 OAID 授权入口 | `com.miui.idprovider.ui.GrantPermissionActivity` | 【静态】action `miui.intent.action.REQUEST_PERMISSIONS_FOR_OAID` |

### 4.5 代码级问题

| 编号 | 问题 | 组件 | 等级 |
|---|---|---|---|
| P1 | `toString()` 输出访问令牌 | `com.miui.securityadd` | 高 |
| P2 | 内嵌明文 API Key | `com.miui.securitycenter` | 高 |
| P3 | 日志输出密码长度 | `com.miui.guardprovider` | 高 |
| P4 | 上报字段构成完整设备画像 | `com.mobiletools.systemhelper` | 高 |
| P5 | 采集范围为同类组件最广 | `com.qualcomm.qti.autoregistration` | 高 |
| P6 | 通用上传管道无内容约束 | `com.qualcomm.qti.qms.service.telemetry` | 高 |
| P7 | 内嵌腾讯 TMSDK | `com.miui.securityadd` | 中 |
| P8 | 加速注册请求携带设备标识 | `com.miui.securityadd` | 中 |
| P9 | 误报反馈上传通话内容 | `com.miui.guardprovider` | 中 |
| P10 | 上报带延迟策略以规避即时观测 | `com.mobiletools.systemhelper` | 中 |
| P11 | 广告与 OAID 链路 | `com.miui.securitycenter` | 中 |

明细见 [`docs/02-逆向与行为结论.md`](docs/02-逆向与行为结论.md) 第十三节。其中 M1、M2 两项经代码核查后由中风险下调：`securitycenter` 的敏感词检测使用本地词表，`onetrack` 上报的是设备完整性状态。

### 4.6 横向结论

1. 15 个组件中，具备联网上报结构的有 6 个：`systemhelper`、`guardprovider`、`securitycenter`、`securityadd`、`autoregistration`、`telemetry`。
2. 取得完整报文证据的仅 `com.mobiletools.systemhelper` 一个。
3. 4 个组件无 `INTERNET` 权限：`catchlog`、`qti.services.systemhelper`、`devicestatisticsservice`、`deviceinfo`，移除不减少外传面。
4. 无任何组件具备全量流量采集实现；唯一持有 `BIND_VPN_SERVICE` 的组件在两台设备上均未启用。
5. 系统层存在 init 托管的 tcpdump 守护进程（`/vendor/bin/tcpdump -i any -W 2 -C 2 -s 134`），仅记录报文头，写入本地 `/data/vendor/wlan_logs/`，不对外发送，非本次审计所创建。
6. 运营商 DM 组件按制式分属不同包：移动 46000 → `com.miui.dmregservice`；联通 46001 → `com.mobiletools.systemhelper`；电信 46003/46013 → `com.qualcomm.qti.autoregistration`；广电 46015 → `com.xiaomi.registration`。移除其中一家不影响其余三家。

---

## 五、处置与验证

处置方式统一为 `pm uninstall -k --user 0`：仅对当前用户卸载，不修改系统分区，保留应用数据，可经 `cmd package install-existing --user 0` 完整恢复。

| 设备 | 已卸载 | 保留 |
|---|---|---|
| A | 9 个（安全栈 4 个、运营商与注册 3 个、日志与高通 2 个） | `deviceinfo`、`devicestatisticsservice`（无 INTERNET，移除不减少外传面）、`com.sinovatech.unicom.ui` |
| B | 11 个（安全栈 4 个、运营商与注册 3 个、高通 4 个） | — |

处置后验证结果：`dumpsys telephony.registry` 中 `mServiceState` 为 `IN_SERVICE`，通话、短信与数据业务正常；系统分区 APK 完好；残留进程经 `kill -9` 清理后不再重启。

副作用一项：移除安全中心会导致应用锁验证界面缺失，被锁应用无法启动。处置顺序为先恢复安全中心、关闭 `access_control_lock_enabled`、再执行卸载。详见 [`docs/05-卸载与恢复.md`](docs/05-卸载与恢复.md)。

---

## 六、证据文件

| 类型 | 位置 | 内容 |
|---|---|---|
| 抓包 | `evidence/pcap/` | 5 个 pcap，含 SystemHelper 明文上报、安全中心两轮观测、无卡空白对照 |
| 哈希 | [`evidence/apk-sha256.txt`](evidence/apk-sha256.txt) | 23 个被审计 APK 的 SHA-256 与体积 |
| 脱敏规则 | [`evidence/README.md`](evidence/README.md) | 8 条规则与复核命令 |

APK 本体不入库（累计约 400 MB，属厂商版权物）。凭哈希核对版本后，本仓库的静态结论可直接对应。

---

## 七、审计局限

| 项目 | 说明 |
|---|---|
| 反编译覆盖 | `securitycenter` 12674 类中逐类阅读 3 个；`securityadd` 16510 类仅做结构级判定；`guardprovider` 5596 类中阅读 AI 防诈子集；`mobiletools.systemhelper` 549 类全部阅读 |
| 敏感词表 | 已解出白名单与解密链路，词表本体未取得，见 [`docs/03-敏感词表提取.md`](docs/03-敏感词表提取.md) |
| 录制指令来源 | 未定位发起 `COMMAND=1/2` 的具体组件 |
| 未观测到外传的组件 | 表示抓包窗口内无该组件的对外连接，不代表其他条件下不会上报 |
| 版本适用性 | 结论对应表中标注的系统与组件版本，其他版本实现可能不同 |
| 未纳入范围 | 厂商服务器侧行为、报文体内层加密内容、其他厂商设备 |

---

## 八、仓库结构

```
.
├── README.md                        本文件，审计报告主体
├── docs/
│   ├── 00-方法与证据等级.md           环境、流程、证据分级、实现约束、判定口径、覆盖范围
│   ├── 01-基础审计.md                章一至十一：对象、方法、风险表、逐组件、抓包、加固建议
│   ├── 02-逆向与行为结论.md           章十二至十四：反编译结果、代码级问题清单、行为模型、开机时序
│   ├── 03-敏感词表提取.md             章十五：词表格式、解密链路、受阻原因
│   ├── 04-运营商与安全中心补审计.md    章十六至十八：RegService、安全中心定向逆向、AI 防诈录制
│   ├── 05-卸载与恢复.md              处置原则、两台设备处置结果、副作用、验证与恢复
│   ├── 05a-操作日志-设备A.md          原始执行记录
│   └── 05b-操作日志-设备B.md          原始执行记录
├── data/
│   ├── components.csv               组件总表
│   ├── endpoints.csv                外传端点
│   └── uninstalled.csv              逐包处置明细
├── tools/
│   ├── restore-security-packages.ps1 一键恢复
│   ├── collect-inventory.sh         设备端清单与权限采集
│   └── audit-apk.sh                 单包 manifest 解析与端点提取
└── evidence/
    ├── README.md                    证据说明与脱敏规则
    ├── apk-sha256.txt               被审计 APK 哈希
    └── pcap/                        抓包原始文件
```

---

## 九、复现

```bash
adb shell pm list packages -3 > packages.txt          # 包清单
bash tools/collect-inventory.sh <序列号>               # 权限与端点采集
bash tools/audit-apk.sh base.apk                       # 单包解析
adb shell su -c "tcpdump -i any -s 0 -w /sdcard/cap.pcap"   # 抓包
```

需要 adb、apktool、jadx（可选）、设备端 tcpdump 与 root。流程细节与实现约束见 [`docs/00-方法与证据等级.md`](docs/00-方法与证据等级.md)。

---

## 十、授权与许可

审计设备均为作者本人所有，操作前已备份、操作后可回滚，未修改分区、未写入开机脚本、未安装系统级模块。

报告不含 ICCID、IMSI、IMEI、手机号、WiFi MAC、精确坐标与住址，抓包文件按既定规则剔除。厂商名称、包名、端点为客观标识，用于安全研究与用户知情。

许可：[GPL-3.0](LICENSE)。文档、数据表、脚本、证据文件统一采用同一许可，可自由使用、修改、再分发，衍生作品需同样以 GPL-3.0 开放。厂商名称与商标不随本许可授权。
