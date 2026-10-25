# luci-app-nssstatus

OpenWrt LuCI 插件: NSS 硬件加速状态页(qca-nss, qualcommax/ipq60xx)。

- ECM 硬件加速连接数(TCP/UDP 分解 + 60 秒趋势图)
- NSS↔主机吞吐(n2h 计数)与 NSS CPU 负载(驱动上报)
- 物理网口实时速率(自动过滤虚拟接口)
- NSS 固件版本识别
- 适配 Argon 主题明暗模式: 运行时探测 body 背景亮度自动切换配色,
  跟随主题色(--primary), 毛玻璃卡片 + 渐变趋势图 + 动画速率条

零依赖纯 Lua(uci-compat), 由 wrt_release 构建时生成到 package/emortal/ 下编译。
