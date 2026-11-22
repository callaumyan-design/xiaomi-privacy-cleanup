# 小米隐私组件清理（ADB，免 root，可恢复）

整理于 2026-11-22，依据 2026 年 11 月公开的逆向分析报告和多份社区精简清单（来源见文末）。
适用于小米 / Redmi / POCO 手机，系统为 MIUI 或 HyperOS 1/2/3，国行版和国际版都可以用，手机上没有的包会自动跳过。

原理是 `adb shell pm uninstall --user 0 包名`：只对当前用户卸载，系统分区里的安装包还在，随时能装回来。

---

## 一、准备（大约 10 分钟）

1. **电脑装 ADB**：下载 Google 官方的 Android SDK Platform-Tools。
   - Windows：解压后把 `adb.exe`、`AdbWinApi.dll`、`AdbWinUsbApi.dll` 三个文件复制到本文件夹。
   - Mac：`brew install android-platform-tools`
   - Linux：`sudo apt install adb`
2. **打开开发者模式**：手机 设置 → 我的设备 → 全部参数 → 连续点"OS 版本"（老系统是"MIUI 版本"），直到提示已进入开发者模式。
3. **打开 USB 调试**：设置 → 更多设置 → 开发者选项 → 打开"USB 调试"。
4. **连接电脑**：用能传数据的线连接，手机弹出"允许 USB 调试吗？"时点允许。
5. **建议先备份**重要数据。

## 二、运行

先下载本项目：在 GitHub 页面点 **Code → Download ZIP**，然后解压（或者用 `git clone`）。

- **Windows**：双击 `run_windows.bat`
- **Mac / Linux**：在本文件夹打开终端，执行 `chmod +x xiaomi_privacy.sh && ./xiaomi_privacy.sh`
- **不想用脚本**：打开 `commands.txt`，里面是可以直接复制的命令

建议顺序：
1. 先选 **1 检查**，看看你手机上有哪些
2. 选 **2 删除 A+B**，重启，按第四节测试
3. 需要的话再选 3（运营商组件）和 4（可选功能）
4. E 级放到最后，一次只删一个

想保留某个组件：打开 `packages.txt`，在那一行最前面加 `#`。

## 三、分级说明

| 级别 | 包含 | 风险 |
|---|---|---|
| A 隐私上报 | 联通 SystemHelper、Analytics、MiuiDaemon、MiSight、OneTrack、错误报告、界面事件上报 | 低。SystemHelper 删后要确认两张卡都正常 |
| B 广告推荐 | 系统广告 MSA、快应用、锁屏画报、内容中心、小爱建议 | 低 |
| C 运营商注册 | 中国移动 RegService、中国电信自注册 | 中。有报告称可能影响开机激活、移动网络或支付，删后要测试 |
| D 可选功能 | 小米浏览器、定制输入法、小爱全家桶、Joyose、负一屏、黄页等 | 低，但会失去对应功能。脚本逐个询问 |
| E 高风险 | 系统安全组件（被指录屏的那个）、内容捕获服务 | 高。可能无法安装或更新 App、手机管家报错，个别机型有卡开机报告 |

每个包的详细说明见 `packages.txt`。

## 四、删完后要测试的

- 重启手机
- 两张卡分别：打电话、发短信、移动数据、VoLTE（HD 图标）
- 安装一个 App
- 微信、QQ 等应用的通知
- 用 NFC 刷公交、门禁或付款的，试一下

## 五、出问题怎么办

- **恢复某个组件**：脚本选 6，或执行 `adb shell cmd package install-existing --user 0 包名`
- **卡在开机画面**：保持数据线连接，在电脑上执行恢复命令。USB 调试已授权的话，开机卡住时通常还能连上
- **实在救不回来**：关机后按住 电源键 + 音量上 进入 Recovery → 清除数据。这等于恢复出厂设置，**手机数据会丢**，所有被删组件也会回来

## 六、这个方法做不到的

- **手机管家（com.miui.securitycenter）**：本地反诈记录库在它里面（截屏、安装、通话等记录），但卸了会卡开机，免 root 没有办法。
- **MiSight 底层进程**：系统里另有一个 root 权限的 misight 程序，删 App 关不掉它。
- **系统安全组件**：在 HyperOS 3 上可能免 root 删不掉（会显示 Failure）。可以改用第八节的 DNS 屏蔽。
- **恢复出厂后会全部回来**；系统大版本更新后，建议再用"检查"看一遍。
- **只处理主空间**：用了"手机分身"的话，分身空间是另一个用户，不受影响。

## 七、千万别删的

| 包名 | 原因 |
|---|---|
| com.miui.securitycenter / com.miui.securitycore / com.miui.securityadd | 手机管家及其组件，卸载可能卡开机 |
| com.lbe.security.miui、com.android.permissioncontroller | 权限管理，卡开机或无法授权 |
| com.miui.packageinstaller（国际版 com.miui.global.packageinstaller） | 安装器，卸了装不了 App 或卡开机 |
| android.ext.services | 卡开机 |
| com.miui.powerkeeper | 电量与性能，刷新率、温控、快充会异常 |
| com.xiaomi.xmsf | 小米推送，国内很多 App 的通知靠它 |
| com.xiaomi.finddevice | 登录小米账号时卸载，可能触发防盗锁机 |
| com.xiaomi.account、com.miui.cloudservice | 小米账号和云服务 |
| com.xiaomi.metoknlp、com.xiaomi.location.fused | 有报告称切换深浅色模式时会卡开机 |
| com.android.htmlviewer、com.miui.home、com.miui.miwallpaper | 卡开机、桌面失效或黑屏 |
| com.android.phone、org.codeaurora.ims | 通话和 VoLTE |
| com.miui.securityinputmethod | 安全键盘，输入密码时用 |
| com.qualcomm.qti.services.systemhelper | 名字里也有 systemhelper，但这是高通的系统服务，**不是**联通那个 |

## 八、可选：用 DNS 屏蔽上报域名

不删组件也能切断上报，适合 E 级删不掉或不敢删的情况。需要支持自定义拦截规则的私人 DNS 服务（如 NextDNS、AdGuard DNS 个人版），把下面的域名加入拦截列表，再在手机的"私人 DNS"里填入它给你的地址。改 hosts 需要 root。

| 域名 | 对应组件 |
|---|---|
| dm.wo.com.cn | 联通 SystemHelper |
| a.fxltsbl.com | 移动 RegService |
| fraud-detection.engine.miui.com | 系统安全组件（上报 App 清单） |
| flash.sec.miui.com | 系统安全组件（屏蔽后手机管家病毒库可能无法更新） |
| detection-aigc.engine.miui.com | AI 通话防诈检测 |
| event-log.cnbj1.mi-fds.com | MiSight 遥测 |

注意：组件如果直接用 IP 地址或自带 DNS 解析，DNS 屏蔽就拦不住。

## 九、手机设置里顺手关掉

- 设置 → 密码与安全（HyperOS 叫"指纹、面部与锁屏"）→ 授权与撤销 → 关掉 **msa**
- 同一菜单 → 隐私 → 广告服务 → 关闭**个性化广告推荐**
- 关闭**用户体验计划**和**诊断数据自动上传**
- 各个系统 App（下载管理、主题、手机管家、应用商店）的设置里关掉"推荐内容"

## 来源

- acxun/hyperos-dm-report：HyperOS 预装 DM 组件调查报告（GitHub）
- evalfun/miui-systemhelper-analyse-report：SystemHelper 逆向分析报告（GitHub）
- Richard8695847/SystemHelper（GitHub）
- Eynnzerr/TelemetryCleaner：运营商组件清单（GitHub）
- 不翻车：《联通 SystemHelper 不只在小米》《中国移动 RegService 是什么》（bufanche.com）
- mcxiaoke：小米 HyperOS 通用 ADB 精简与去广告/遥测命令清单（GitHub Gist）
- 小天の博客：ADB 卸载小米预装系统应用（HyperOS 3）（blog.laughsky.cn）
- clean_hyperos：ADB 手动优化净化小米 HyperOS（GitHub）
- android-debloat-list：com.miui.guardprovider 条目（muntashirakon.github.io）
- 小米手机无 root 通过 ADB 卸载 SystemHelper、RegService、Registration（cheshirex.com）

## 免责

以上是根据公开报告和社区经验整理的，不同机型和系统版本可能有差异。删除系统组件有风险，请自行判断；出问题按第五节恢复。
