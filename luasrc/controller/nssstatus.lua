module("luci.controller.nssstatus", package.seeall)

function index()
    entry({"admin", "status", "nssstatus"}, template("nssstatus/status"), _("NSS Status"), 90)
    entry({"admin", "status", "nssstatus", "data"}, call("nss_data")).leaf = true
end

-- 采集一次 NSS/ECM 状态, 输出 JSON 供页面轮询 (每 2 秒)
function nss_data()
    local fs = require "nixio.fs"
    local sys = require "luci.sys"
    local util = require "luci.util"

    local function rf(p)
        local s = fs.readfile(p)
        return s and util.trim(s) or nil
    end

    local out = { conn = 0, conn_tcp = 0, conn_udp = 0, conn_other = 0, ecm_mods = 0, nss_cpu = -1, nss_cpu_min = -1, nss_cpu_max = -1, n2h_rx_byts = 0, n2h_tx_byts = 0, n2h_rx_pkts = 0, n2h_tx_pkts = 0, fw = "?", ports = {} }

    -- ECM 已卸载到硬件的会话数
    out.conn = tonumber(rf("/sys/kernel/debug/ecm/ecm_db/connection_count") or "") or 0

    -- 按协议分解: connection_count_simple 输出 "tcp N udp N other N total N"
    -- (qca-nss-ecm/ecm_db/ecm_db_connection.c:4543 snprintf 格式)
    local cs = fs.readfile("/sys/kernel/debug/ecm/ecm_db/connection_count_simple")
    if cs then
        out.conn_tcp = tonumber(cs:match("tcp%s+(%d+)")) or 0
        out.conn_udp = tonumber(cs:match("udp%s+(%d+)")) or 0
        out.conn_other = tonumber(cs:match("other%s+(%d+)")) or 0
    end

    -- 已加载的 ECM 引擎模块数
    local fm = io.open("/proc/modules", "r")
    if fm then
        for line in fm:lines() do
            if line:sub(1, 3) == "ecm" then out.ecm_mods = out.ecm_mods + 1 end
        end
        fm:close()
    end

    -- NSS 硬件加速吞吐: 取 n2h (NSS core <-> host) 数据面累计计数, 速率由页面按差值算。
    -- 实测: 该计数随转发流量实时增长, 是"NSS 确实在硬件转发"的可靠证据。
    local n2h = fs.readfile("/sys/kernel/debug/qca-nss-drv/stats/n2h")
    if n2h then
        out.n2h_rx_byts = tonumber(n2h:match("n2h_rx_byts%s*=%s*(%d+)")) or 0
        out.n2h_tx_byts = tonumber(n2h:match("n2h_tx_byts%s*=%s*(%d+)")) or 0
        out.n2h_rx_pkts = tonumber(n2h:match("n2h_rx_pkts%s*=%s*(%d+)")) or 0
        out.n2h_tx_pkts = tonumber(n2h:match("n2h_tx_pkts%s*=%s*(%d+)")) or 0
    end

    -- 调频驱动上报的 CPU 负载 (仅作诊断用):
    -- cpu_load_ubi 由 nss_freq_stats.c 注册, 依赖 NSS 固件周期性上报指令数。
    -- 实测本版本固件不上报, nss_freq_compute_cpu_usage() 在 inst_cnt==0 时直接 return,
    -- 导致 used 永远停在开机初值(8%), min/avg/max 恒等 —— 不能反映真实负载,
    -- 因此卡片区改用 n2h 吞吐, 这里只保留原始值备查。
    local raw = fs.readfile("/sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi")
    if raw then
        local mn, av, mx = raw:match("(%d+)%%%s+(%d+)%%%s+(%d+)%%")
        if mn then
            out.nss_cpu_min = tonumber(mn)
            out.nss_cpu = tonumber(av) or -1
            out.nss_cpu_max = tonumber(mx)
        end
    end

    -- NSS 固件版本:
    --   包版本(opkg control)只是 OpenWrt 打包版本, 与芯片内实际运行的固件不是一回事。
    --   真实版本要从固件二进制里读, 同上游 nss_diag.sh 的做法:
    --   grep -h -m1 -a -o 'Version:.[^[:cntrl:]]*' /lib/firmware/qca*.bin
    local ctl = fs.readfile("/usr/lib/opkg/info/nss-firmware-ipq60xx.control")
    if ctl then out.fw = ctl:match("Version:%s*([^\r\n]+)") or "?" end
    local fwraw = sys.exec("grep -h -m1 -a -o 'Version:.[^[:cntrl:]]*' /lib/firmware/qca*.bin 2>/dev/null | head -1") or ""
    local fwreal = fwraw:match("Version:%s*([^\r\n]+)")
    if fwreal then out.fwreal = util.trim(fwreal) end

    -- /proc/net/dev 的累计字节数 (速率交给页面按差值算, 服务端不存状态)
    local bytes = {}
    for line in (fs.readfile("/proc/net/dev") or ""):gmatch("[^\r\n]+") do
        local name, rest = line:match("^%s*([%w%.%-]+):%s*(.+)$")
        if name then
            local nums = {}
            for n in rest:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
            if #nums >= 9 then bytes[name] = { nums[1], nums[9] } end
        end
    end

    -- 真实物理网口: 只有交换机端口在 /sys/class/net/<n>/ 下有 device 软链。
    -- br-lan / dheth0 / dummy0 / gre0 这些虚拟接口没有 device, 但它们也有 speed 文件,
    -- 所以不能用 speed 判断, 否则端口列表会混进一堆虚拟接口。
    local names = {}
    for n in (sys.exec("ls -1 /sys/class/net 2>/dev/null") or ""):gmatch("[%w%.%-]+") do
        if fs.access("/sys/class/net/" .. n .. "/device") then names[#names + 1] = n end
    end
    table.sort(names)
    for _, n in ipairs(names) do
        local b = bytes[n] or { 0, 0 }
        out.ports[#out.ports + 1] = {
            name  = n,
            up    = (rf("/sys/class/net/" .. n .. "/operstate") == "up"),
            speed = tonumber(rf("/sys/class/net/" .. n .. "/speed") or "") or 0,
            rx    = b[1],
            tx    = b[2]
        }
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json(out)
end
