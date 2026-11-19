<#
  一键恢复被卸载的预装组件
  用法:
    powershell -ExecutionPolicy Bypass -File .\restore-security-packages.ps1 -Serial <设备序列号>

  说明:
    - 本机不存在的包会由系统回一句 "Package ... doesn't exist"，无害，脚本无需预判;
    - 只对 user 0 执行 install-existing，不改系统分区，不重新下载任何东西;
    - 恢复安全栈后建议重启一次，让 system_server 重新初始化依赖;
    - 若应用锁总开关为 0，恢复安全中心后应用锁仍是关闭状态。
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Serial,
    [string]$Adb = "adb"
)

$pkgs = @(
    "com.miui.securitycenter",                          # 手机管家 / 安全中心（应用锁密码界面宿主）
    "com.miui.securityadd",                             # 安全组件（安全中心插件）
    "com.miui.guardprovider",                           # 系统安全组件（查杀引擎 / AI 防诈）
    "com.xiaomi.security.onetrack",                     # 安全数据上报
    "com.mobiletools.systemhelper",                     # 运营商定制服务（联通渠道）
    "com.miui.dmregservice",                            # 运营商 DM（移动渠道）
    "com.xiaomi.registration",                          # 终端自注册（联通 / 广电）
    "com.bsp.catchlog",                                 # 日志抓取
    "com.qualcomm.qti.autoregistration",                # 终端自注册（电信）
    "com.qualcomm.qti.qms.service.telemetry",           # 高通遥测
    "com.qualcomm.qti.devicestatisticsservice",         # 本地设备统计
    "com.qti.qualcomm.deviceinfo"                       # 设备信息
)

Write-Host "target: $Serial`n" -ForegroundColor Cyan

foreach ($p in $pkgs) {
    Write-Host "== restore $p ==" -ForegroundColor Cyan
    & $Adb -s $Serial shell "su -c 'cmd package install-existing --user 0 $p'"
    if ($LASTEXITCODE -ne 0) {
        & $Adb -s $Serial shell "su -c 'pm install-existing --user 0 $p'"
    }
}

Write-Host "`n== state ==" -ForegroundColor Green
& $Adb -s $Serial shell "pm list packages --user 0 | grep -E 'miui.securitycenter|miui.securityadd|miui.guardprovider|xiaomi.security.onetrack|mobiletools.systemhelper|miui.dmregservice|xiaomi.registration|bsp.catchlog'"

Write-Host "`nreboot recommended: & `"$Adb`" -s $Serial reboot" -ForegroundColor Green
Write-Host "app lock master switch: adb shell `"su -c 'settings put secure access_control_lock_enabled 1'`"" -ForegroundColor Yellow
