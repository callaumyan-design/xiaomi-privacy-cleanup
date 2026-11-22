# 小米 / Redmi / POCO 隐私组件清理脚本（Windows，免 root，可恢复）
#
# 推荐双击 run_windows.bat 运行。也可以在 PowerShell 里：
#   powershell -ExecutionPolicy Bypass -File .\xiaomi_privacy.ps1 [check|basic|carrier|optional|risky|restore] [包名]
#
# 原理：adb shell pm uninstall --user 0 <包名>
#   只对当前用户卸载，系统分区里的安装包还在，随时能用 restore 装回；
#   恢复出厂设置后这些组件也会全部回来。

param(
  [string]$Mode = '',
  [string]$Target = ''
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Dir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$List = Join-Path $Dir 'packages.txt'
$Log  = Join-Path $Dir ('removed_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:RemovedCount = 0
$script:Installed = @{}
$script:AllPkgs = @{}

# ---------- 找 adb ----------
$Adb = $null
$localAdb = Join-Path $Dir 'adb.exe'
if (Test-Path -LiteralPath $localAdb) {
  $Adb = $localAdb
} else {
  $cmd = Get-Command adb -ErrorAction SilentlyContinue
  if ($cmd) { $Adb = $cmd.Source }
}
if (-not $Adb) {
  Write-Host '找不到 adb。请下载 Android SDK Platform-Tools（Windows 版），'
  Write-Host '解压后把 adb.exe、AdbWinApi.dll、AdbWinUsbApi.dll 三个文件复制到本文件夹，再重新运行。'
  exit 1
}

# 在手机上执行一条命令，返回文本（多行用 `n 连接）
function Invoke-AdbShell([string]$Command) {
  $out = & $Adb shell $Command 2>$null
  if ($null -eq $out) { return '' }
  return (@($out) | ForEach-Object { "$_".TrimEnd("`r") }) -join "`n"
}

# ---------- 读清单 ----------
function Get-PackageList {
  if (-not (Test-Path -LiteralPath $List)) {
    Write-Host '找不到 packages.txt，它要和本脚本放在同一个文件夹里。'
    exit 1
  }
  $result = @()
  foreach ($line in (Get-Content -LiteralPath $List -Encoding UTF8)) {
    $parts = $line.Split('|')
    if ($parts.Count -lt 2) { continue }
    $tier = $parts[0].Trim()
    if (@('A','B','C','D','E') -notcontains $tier) { continue }
    $pkg = $parts[1].Trim()
    if ($pkg -eq '') { continue }
    $name = ''; if ($parts.Count -gt 2) { $name = $parts[2].Trim() }
    $note = ''; if ($parts.Count -gt 3) { $note = $parts[3].Trim() }
    $result += [pscustomobject]@{ Tier = $tier; Pkg = $pkg; Name = $name; Note = $note }
  }
  return $result
}

# ---------- 连接检查 ----------
function Test-Device {
  $lines = @(& $Adb devices 2>$null | ForEach-Object { "$_".TrimEnd() })
  $ok     = @($lines | Where-Object { $_ -match '\tdevice$' })
  $unauth = @($lines | Where-Object { $_ -match '\tunauthorized$' })
  if ($ok.Count -eq 0) {
    if ($unauth.Count -gt 0) {
      Write-Host '手机上应该弹出了“允许 USB 调试吗？”，请点允许（建议勾选“始终允许”），然后重新运行。'
    } else {
      Write-Host '没检测到手机。请检查：'
      Write-Host '  1. 数据线能传数据（有些线只能充电）'
      Write-Host '  2. 设置 → 更多设置 → 开发者选项 → USB 调试 已打开'
      Write-Host '  3. 手机连接方式选“传输文件”；仍不行就装一下小米 USB 驱动'
    }
    exit 1
  }
  if ($ok.Count -gt 1 -and -not $env:ANDROID_SERIAL) {
    Write-Host '检测到多台设备，请只连一台手机后再运行。'
    exit 1
  }

  $brand   = Invoke-AdbShell 'getprop ro.product.brand'
  $model   = Invoke-AdbShell 'getprop ro.product.marketname'
  if (-not $model) { $model = Invoke-AdbShell 'getprop ro.product.model' }
  if (-not $model.ToLower().StartsWith($brand.ToLower())) { $model = "$brand $model" }
  $osver   = Invoke-AdbShell 'getprop ro.mi.os.version.incremental'
  if (-not $osver) { $osver = Invoke-AdbShell 'getprop ro.miui.ui.version.name' }
  if (-not $osver) { $osver = '系统版本未知' }
  $android = Invoke-AdbShell 'getprop ro.build.version.release'
  $moddev  = Invoke-AdbShell 'getprop ro.product.mod_device'
  if ($moddev -match '_global') { $region = '国际版' }
  elseif ($moddev -match '_(eea|ru|in|id|tw|jp|tr)') { $region = '海外版' }
  elseif (-not $moddev) { $region = '未知' }
  else { $region = '国行（推测）' }
  Write-Host ("已连接：{0}｜Android {1}｜{2}｜{3}" -f $model, $android, $osver, $region)
  if (@('xiaomi','redmi','poco') -notcontains $brand.ToLower()) {
    Write-Host '提醒：这台手机看起来不是小米/Redmi/POCO，本清单是按小米系统整理的。'
  }
}

# ---------- 包状态 ----------
function Update-PackageState {
  $script:Installed = @{}
  $script:AllPkgs = @{}
  foreach ($l in ((Invoke-AdbShell 'pm list packages --user 0') -split "`n")) {
    if ($l -match '^package:(.+)$') { $script:Installed[$Matches[1].Trim()] = $true }
  }
  foreach ($l in ((Invoke-AdbShell 'pm list packages -u --user 0') -split "`n")) {
    if ($l -match '^package:(.+)$') { $script:AllPkgs[$Matches[1].Trim()] = $true }
  }
}

function Get-PkgStatus([string]$Pkg) {
  if ($script:Installed.ContainsKey($Pkg)) { return 'present' }
  if ($script:AllPkgs.ContainsKey($Pkg)) { return 'removed' }
  return 'absent'
}

function Get-TierTitle([string]$Tier) {
  switch ($Tier) {
    'A' { return 'A 隐私上报（建议删）' }
    'B' { return 'B 广告推荐（建议删）' }
    'C' { return 'C 运营商注册组件（按需删，删后测试通话上网）' }
    'D' { return 'D 可选功能（不用就删）' }
    'E' { return 'E 高风险（默认不动）' }
  }
}

# ---------- 删除 / 恢复 ----------
function Remove-Pkg($Item) {
  $pkg = $Item.Pkg
  $st = Get-PkgStatus $pkg
  if ($st -eq 'absent')  { Write-Host ("  [跳过] {0}  这台手机上没有" -f $pkg); return }
  if ($st -eq 'removed') { Write-Host ("  [已删] {0}  之前已经删过" -f $pkg); return }
  $ime = Invoke-AdbShell 'settings get secure default_input_method'
  if ($ime.Trim().StartsWith($pkg + '/')) {
    Write-Host ("  [跳过] {0}  这是你正在用的输入法，请先在设置里切换到别的输入法" -f $pkg) -ForegroundColor Yellow
    return
  }
  $r = Invoke-AdbShell ("pm uninstall --user 0 {0} 2>&1" -f $pkg)
  if ($r -match 'Success') {
    Write-Host ("  [成功] {0}  {1}" -f $pkg, $Item.Name) -ForegroundColor Green
    Add-Content -LiteralPath $Log -Value $pkg
    $script:Installed.Remove($pkg)
    $script:RemovedCount++
  } else {
    if (-not $r) { $r = '没有返回信息' }
    Write-Host ("  [失败] {0}  {1}" -f $pkg, $r.Trim()) -ForegroundColor Yellow
  }
}

function Restore-Pkg([string]$Pkg) {
  $r = Invoke-AdbShell ("cmd package install-existing --user 0 {0} 2>&1" -f $Pkg)
  if ($r -match 'installed for user') {
    Write-Host ("  [已恢复] {0}" -f $Pkg) -ForegroundColor Green
  } else {
    if (-not $r) { $r = '没有返回信息' }
    Write-Host ("  [失败] {0}  {1}" -f $Pkg, $r.Trim()) -ForegroundColor Yellow
  }
}

function Confirm-Yes([string]$Question) {
  $a = Read-Host ($Question + ' [y/N]')
  return ($a -match '^(y|yes)$')
}

# ---------- 各模式 ----------
function Invoke-Check {
  Update-PackageState
  foreach ($tier in @('A','B','C','D','E')) {
    Write-Host ''
    Write-Host ("== {0} ==" -f (Get-TierTitle $tier))
    foreach ($it in ($script:Items | Where-Object { $_.Tier -eq $tier })) {
      switch (Get-PkgStatus $it.Pkg) {
        'present' { $mark = '[还在]' }
        'removed' { $mark = '[已删]' }
        default   { $mark = '[没有]' }
      }
      Write-Host ("  {0} {1}  {2}" -f $mark, $it.Pkg, $it.Name)
    }
  }
  Write-Host ''
  Write-Host '[还在] = 手机上装着；[已删] = 已对当前用户卸载；[没有] = 你的系统里本来就没有这个包'
}

function Invoke-Batch([string[]]$Tiers) {
  Update-PackageState
  $todo = @($script:Items | Where-Object { ($Tiers -contains $_.Tier) -and ((Get-PkgStatus $_.Pkg) -eq 'present') })
  if ($todo.Count -eq 0) {
    Write-Host '这些级别里的组件，你的手机上都没有或已经删过了。'
    return
  }
  Write-Host ''
  Write-Host ("将要删除以下 {0} 个组件：" -f $todo.Count)
  foreach ($it in $todo) {
    Write-Host ("  - {0}  {1}" -f $it.Pkg, $it.Name)
    Write-Host ("      {0}" -f $it.Note)
  }
  Write-Host ''
  if (-not (Confirm-Yes '确认删除？')) { Write-Host '已取消。'; return }
  foreach ($it in $todo) { Remove-Pkg $it }
}

function Invoke-Optional {
  Update-PackageState
  $todo = @($script:Items | Where-Object { $_.Tier -eq 'D' -and ((Get-PkgStatus $_.Pkg) -eq 'present') })
  if ($todo.Count -eq 0) { Write-Host 'D 级组件你的手机上都没有或已经删过了。'; return }
  Write-Host ''
  Write-Host '逐个询问 D 级可选功能（直接回车 = 不删）：'
  foreach ($it in $todo) {
    Write-Host ''
    Write-Host ("{0}（{1}）" -f $it.Name, $it.Pkg)
    Write-Host ("  {0}" -f $it.Note)
    if (Confirm-Yes '  删除？') { Remove-Pkg $it } else { Write-Host '  已跳过' }
  }
}

function Invoke-Risky {
  Update-PackageState
  $todo = @($script:Items | Where-Object { $_.Tier -eq 'E' -and ((Get-PkgStatus $_.Pkg) -eq 'present') })
  if ($todo.Count -eq 0) { Write-Host 'E 级组件你的手机上都没有或已经删过了。'; return }
  Write-Host ''
  Write-Host '!!! E 级是高风险组件。建议先只删一个，重启后测试“安装一个 App”和手机管家是否正常，' -ForegroundColor Red
  Write-Host '!!! 有问题马上用“恢复”。卡在开机画面时，保持数据线连接，用恢复命令通常还能救回。' -ForegroundColor Red
  foreach ($it in $todo) {
    Write-Host ''
    Write-Host ("{0}（{1}）" -f $it.Name, $it.Pkg)
    Write-Host ("  {0}" -f $it.Note)
    $a = Read-Host '  确定要删除，请输入大写 YES（其他任意输入 = 跳过）'
    if ($a -ceq 'YES') { Remove-Pkg $it } else { Write-Host '  已跳过' }
  }
}

function Invoke-Restore([string]$Pkg) {
  Update-PackageState
  if ($Pkg) { Restore-Pkg $Pkg; return }
  $todo = @($script:Items | Where-Object { (Get-PkgStatus $_.Pkg) -eq 'removed' })
  if ($todo.Count -eq 0) { Write-Host '清单里没有已删除的组件需要恢复。'; return }
  foreach ($it in $todo) { Restore-Pkg $it.Pkg }
}

function Invoke-Finish {
  Write-Host ''
  if ($script:RemovedCount -gt 0) {
    Write-Host ("本次共删除 {0} 个组件，记录在：{1}" -f $script:RemovedCount, $Log)
    Write-Host '重启后请测试：两张卡打电话 / 发短信 / 移动数据 / 安装一个 App / 微信等通知。'
    Write-Host '要恢复某个包：重新运行本脚本选 6，或执行 adb shell cmd package install-existing --user 0 包名'
    if (Confirm-Yes '现在重启手机？') { & $Adb reboot }
  }
}

function Show-Menu {
  while ($true) {
    Write-Host ''
    Write-Host '================ 小米隐私组件清理 ================'
    Write-Host '  1) 检查：看看手机上有哪些（不做改动，建议先选这个）'
    Write-Host '  2) 删除 A + B：隐私上报 + 广告推荐（推荐）'
    Write-Host '  3) 删除 C：运营商注册组件（移动 / 电信）'
    Write-Host '  4) 逐个选择 D：可选功能'
    Write-Host '  5) 逐个选择 E：高风险组件'
    Write-Host '  6) 恢复'
    Write-Host '  0) 退出'
    $c = Read-Host '请选择'
    switch ($c) {
      '1' { Invoke-Check }
      '2' { Invoke-Batch @('A','B') }
      '3' { Write-Host ''; Write-Host '提醒：删后请测试通话、上网和支付，有问题选 6 恢复。'; Invoke-Batch @('C') }
      '4' { Invoke-Optional }
      '5' { Invoke-Risky }
      '6' { $p = Read-Host '输入要恢复的包名（直接回车 = 恢复清单里所有已删的）'; Invoke-Restore $p.Trim() }
      '0' { return }
      default { Write-Host '请输入 0-6。' }
    }
  }
}

# ---------- 主流程 ----------
$script:Items = @(Get-PackageList)
Test-Device
switch ($Mode.ToLower()) {
  ''         { Show-Menu }
  'check'    { Invoke-Check }
  'basic'    { Invoke-Batch @('A','B') }
  'carrier'  { Invoke-Batch @('C') }
  'optional' { Invoke-Optional }
  'risky'    { Invoke-Risky }
  'restore'  { Invoke-Restore $Target }
  default    { Write-Host ("未知参数：{0}（可用：check / basic / carrier / optional / risky / restore [包名]）" -f $Mode); exit 1 }
}
Invoke-Finish
