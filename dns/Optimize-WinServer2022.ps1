# ============================================================
# Windows Server 2022 Azure 低配优化 + 简体中文切换脚本
# 适用：2核1G，Server 2022 Datacenter（英文原版）
# 执行方式：以管理员身份运行 PowerShell，整体粘贴执行
# ============================================================

Write-Host "=== 开始优化 ===" -ForegroundColor Cyan

# ── 1. 禁用不必要服务 ──────────────────────────────────────
$services = @(
    "Spooler",            # 打印后台处理（无打印机不需要）
    "Fax",                # 传真服务
    "WSearch",            # Windows Search 索引（很耗资源）
    "SysMain",            # Superfetch 预加载（低内存反而有害）
    "DiagTrack",          # 诊断跟踪/遥测（后台上传数据）
    "dmwappushservice",   # WAP 推送（遥测相关）
    "MapsBroker",         # 下载地图管理器
    "lfsvc",              # 地理位置服务
    "SharedAccess",       # Internet 连接共享
    "RemoteRegistry",     # 远程注册表（安全风险）
    "TabletInputService", # 触控/手写板输入
    "WerSvc",             # Windows 错误报告
    "wercplsupport",      # 错误报告控制面板
    "PcaSvc",             # 程序兼容性助手
    "BDESVC",             # BitLocker（Azure VM 不需要）
    "EFS",                # 加密文件系统
    "TrkWks",             # 分布式链接跟踪客户端
    "wisvc",              # Windows 预览体验计划
    "WbioSrvc",           # Windows 生物特征（指纹等）
    "icssvc",             # Windows 移动热点
    "PhoneSvc",           # 电话服务
    "RmSvc",              # 无线电管理服务
    "SCardSvr",           # 智能卡
    "ScDeviceEnum",       # 智能卡设备枚举
    "SCPolicySvc",        # 智能卡移除策略
    "UevAgentService",    # 用户体验虚拟化
    "WMPNetworkSvc",      # Windows Media Player 网络共享
    "Themes",             # 主题服务（关闭后界面变经典样式）
    "XblAuthManager",     # Xbox 认证
    "XblGameSave",        # Xbox 游戏存档
    "XboxNetApiSvc",      # Xbox 网络
    "XboxGipSvc"          # Xbox 配件
)

foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        try {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled
            Write-Host "  [OK] 已禁用: $svc" -ForegroundColor Green
        } catch {
            Write-Host "  [跳过] $svc : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [不存在] $svc" -ForegroundColor DarkGray
    }
}

# ── 2. 关闭视觉特效（改为最佳性能模式）────────────────────
Write-Host "`n=== 关闭视觉特效 ===" -ForegroundColor Cyan
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "VisualFXSetting" -Value 2

$advPath = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $advPath -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00))
Set-ItemProperty -Path $advPath -Name "DragFullWindows" -Value "0"
Set-ItemProperty -Path $advPath -Name "FontSmoothing" -Value "2"
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
Write-Host "  [OK] 视觉特效已设为最佳性能" -ForegroundColor Green

# ── 3. 配置虚拟内存（系统管理，确保不被限死）──────────────
Write-Host "`n=== 检查虚拟内存 ===" -ForegroundColor Cyan
$cs = Get-WmiObject -Class Win32_ComputerSystem
if ($cs.AutomaticManagedPagefile -eq $false) {
    $cs.AutomaticManagedPagefile = $true
    $cs.Put() | Out-Null
    Write-Host "  [OK] 虚拟内存已设为系统自动管理" -ForegroundColor Green
} else {
    Write-Host "  [已是] 虚拟内存已由系统自动管理" -ForegroundColor DarkGray
}

# ── 4. 调整系统性能偏向后台服务 ───────────────────────────
$perfPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
Set-ItemProperty -Path $perfPath -Name "Win32PrioritySeparation" -Value 24
Write-Host "`n  [OK] 处理器调度已确认为后台服务优先" -ForegroundColor Green

# ── 5. 关闭 IPv6（减少协议栈开销）────────────────────────
Write-Host "`n=== 禁用 IPv6 ===" -ForegroundColor Cyan
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $adapters) {
    Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    Write-Host "  [OK] 已在 $($adapter.Name) 上禁用 IPv6" -ForegroundColor Green
}

# ── 6. 关闭 Windows Update 自动重启 ───────────────────────
Write-Host "`n=== 关闭自动重启 ===" -ForegroundColor Cyan
$wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
Set-ItemProperty -Path $wuPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1
Write-Host "  [OK] 已禁止有用户登录时自动重启" -ForegroundColor Green

# ============================================================
# 简体中文切换
# ============================================================

Write-Host "`n=== 开始切换系统语言为简体中文 ===" -ForegroundColor Cyan

# ── 步骤 1：安装简体中文语言包 ─────────────────────────────
Write-Host "`n[步骤1] 安装简体中文语言包..." -ForegroundColor Yellow

$installed = $false

# 方式A：Install-Language（Server 2022 推荐，来自 LanguagePackManagement 模块）
if (Get-Command Install-Language -ErrorAction SilentlyContinue) {
    try {
        Write-Host "  使用 Install-Language 安装 zh-CN..." -ForegroundColor Gray
        Install-Language -Language zh-CN -CopyToSettings
        Write-Host "  [OK] 语言包安装完成（方式A）" -ForegroundColor Green
        $installed = $true
    } catch {
        Write-Host "  [警告] Install-Language 失败: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# 方式B：DISM Add-Capability（不依赖版本号，联网从 Windows Update 拉取）
if (-not $installed) {
    try {
        Write-Host "  使用 DISM Add-Capability 安装 zh-CN 基础语言包..." -ForegroundColor Gray
        dism /Online /Add-Capability /CapabilityName:Language.Basic~~~zh-CN~0.0.1.0 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] 语言包安装完成（方式B）" -ForegroundColor Green
            $installed = $true
        } else {
            Write-Host "  [警告] DISM Add-Capability 失败，退出码: $LASTEXITCODE" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [警告] DISM 执行异常: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# 方式C：lpksetup 静默安装（最后兜底）
if (-not $installed) {
    Write-Host "  使用 lpksetup 安装 zh-CN..." -ForegroundColor Gray
    # 参数说明：/i 安装，/r 不自动重启，/s 静默无界面
    & lpksetup /i zh-CN /r /s
    Write-Host "  [注意] lpksetup 已触发，可能需要等待后台下载完成再重启" -ForegroundColor Yellow
}

# ── 步骤 2：设置当前用户 UI 语言为 zh-CN ───────────────────
Write-Host "`n[步骤2] 设置当前用户界面语言..." -ForegroundColor Yellow

# 关键：必须先读取现有列表再插入，直接 Set 会清空列表
$langList = Get-WinUserLanguageList
$zhExists = $langList | Where-Object { $_.LanguageTag -eq "zh-CN" }

if (-not $zhExists) {
    $newLang = New-WinUserLanguageList "zh-CN"
    $langList.Insert(0, $newLang[0])
    Set-WinUserLanguageList $langList -Force
    Write-Host "  [OK] 已将 zh-CN 插入语言列表首位" -ForegroundColor Green
} else {
    $langList.Remove($zhExists[0]) | Out-Null
    $langList.Insert(0, $zhExists)
    Set-WinUserLanguageList $langList -Force
    Write-Host "  [OK] zh-CN 已存在，已移至首位" -ForegroundColor Green
}

Set-WinUILanguageOverride -Language "zh-CN"
Write-Host "  [OK] UI 显示语言已覆盖为 zh-CN" -ForegroundColor Green

# ── 步骤 3：设置系统区域、格式、地理位置 ──────────────────
Write-Host "`n[步骤3] 设置区域和格式..." -ForegroundColor Yellow

Set-WinSystemLocale -SystemLocale "zh-CN"    # 影响非 Unicode 程序编码，需重启生效
Set-WinHomeLocation -GeoId 45                # 地理位置：中国 (GeoId=45)
Set-Culture -CultureInfo "zh-CN"             # 当前用户的日期/数字/货币格式

Write-Host "  [OK] 系统区域已设为 zh-CN" -ForegroundColor Green
Write-Host "  [OK] 地理位置已设为中国" -ForegroundColor Green
Write-Host "  [OK] 文化格式已设为 zh-CN" -ForegroundColor Green

# ── 步骤 4：将语言设置复制到欢迎屏幕和新用户 ──────────────
# 原理：上述设置只影响当前登录用户，欢迎屏幕运行在独立系统账户下
# 必须将设置传播过去，否则登录界面仍是英文
Write-Host "`n[步骤4] 将语言设置复制到欢迎屏幕和新用户..." -ForegroundColor Yellow

# 方式A：官方 cmdlet（Server 2022 首选，最可靠）
if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
    try {
        Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
        Write-Host "  [OK] 已通过官方 cmdlet 复制设置到欢迎屏幕和新用户" -ForegroundColor Green
    } catch {
        Write-Host "  [警告] 官方 cmdlet 失败: $($_.Exception.Message)，尝试注册表方式..." -ForegroundColor Yellow
        # 方式B：直接写 .DEFAULT 注册表（兜底）
        $defaultHive = "REGISTRY::HKEY_USERS\.DEFAULT\Control Panel\International"
        if (Test-Path $defaultHive) {
            Set-ItemProperty -Path $defaultHive -Name "Locale"     -Value "0804"
            Set-ItemProperty -Path $defaultHive -Name "sLanguage"  -Value "CHS"
            Set-ItemProperty -Path $defaultHive -Name "sCountry"   -Value "China"
            Set-ItemProperty -Path $defaultHive -Name "LocaleName" -Value "zh-CN"
            Write-Host "  [OK] 已通过注册表写入欢迎屏幕语言设置" -ForegroundColor Green
        } else {
            Write-Host "  [警告] 无法访问 .DEFAULT hive，欢迎屏幕语言未自动修改" -ForegroundColor Yellow
            Write-Host "  [提示] 重启后请手动：控制面板 → Region → Administrative → Copy Settings" -ForegroundColor Yellow
        }
    }
} else {
    # cmdlet 不存在时直接走注册表方式
    Write-Host "  Copy-UserInternationalSettingsToSystem 不可用，使用注册表方式..." -ForegroundColor Yellow
    $defaultHive = "REGISTRY::HKEY_USERS\.DEFAULT\Control Panel\International"
    if (Test-Path $defaultHive) {
        Set-ItemProperty -Path $defaultHive -Name "Locale"     -Value "0804"
        Set-ItemProperty -Path $defaultHive -Name "sLanguage"  -Value "CHS"
        Set-ItemProperty -Path $defaultHive -Name "sCountry"   -Value "China"
        Set-ItemProperty -Path $defaultHive -Name "LocaleName" -Value "zh-CN"
        Write-Host "  [OK] 已通过注册表写入欢迎屏幕语言设置" -ForegroundColor Green
    } else {
        Write-Host "  [警告] 无法访问 .DEFAULT hive，欢迎屏幕语言未自动修改" -ForegroundColor Yellow
        Write-Host "  [提示] 重启后请手动：控制面板 → Region → Administrative → Copy Settings" -ForegroundColor Yellow
    }
}

# ── 步骤 5：设置时区为中国标准时间 ────────────────────────
Write-Host "`n[步骤5] 设置时区为中国标准时间 (UTC+8)..." -ForegroundColor Yellow
Set-TimeZone -Id "China Standard Time"
Write-Host "  [OK] 时区已设为 UTC+8 中国标准时间" -ForegroundColor Green

# ── 全部完成 ──────────────────────────────────────────────
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  全部优化和语言设置已完成" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host @"

  后续步骤：
  1. 立即重启：Restart-Computer -Force
  2. 重新 RDP 登录后检查界面是否为中文

  如果重启后界面仍为英文（Step4 未成功时的手动兜底）：
    控制面板 → Region → Administrative 标签
    → [Copy Settings] 按钮
    → 勾选 "Welcome screen and system accounts"
    → 勾选 "New user accounts"
    → OK → 再次重启

"@ -ForegroundColor White
