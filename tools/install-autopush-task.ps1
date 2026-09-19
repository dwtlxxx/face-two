# =====================================================================
#  一次性的安装脚本 —— 注册「自动推送」计划任务
#
#  用法（必须用管理员身份运行）：
#    1. 开始菜单搜索 "PowerShell"
#    2. 右键 -> "以管理员身份运行"
#    3. 粘贴执行：
#         & "D:\desktop\Face two\tools\install-autopush-task.ps1"
#
#  这个脚本只做一件事：往 Windows 任务计划程序里注册一个任务。
#  它不会修改任何代码，也不会碰你的 git 历史。
#
#  卸载（同样需要管理员）：
#      Unregister-ScheduledTask -TaskName 'FaceTwo-Git-AutoPush' -Confirm:$false
# =====================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$repoPath = 'D:\desktop\Face two'
$script   = Join-Path $repoPath 'tools\git-autopush.ps1'
$taskName = 'FaceTwo-Git-AutoPush'

Write-Host ''
Write-Host '=== 自动推送计划任务安装 ===' -ForegroundColor Cyan

# ---------- 前置检查 ----------
if (-not (Test-Path -LiteralPath $script)) {
    Write-Host "找不到脚本：$script" -ForegroundColor Red
    exit 1
}
Write-Host "[1/4] 脚本存在: $script"

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = "$env:ProgramFiles\Git\cmd\git.exe" }
Write-Host "[2/4] git: $git"

# ---------- 先跑一次，确认能正常工作 ----------
Write-Host '[3/4] 先手动执行一次脚本，确认可正常推送 …' -ForegroundColor Yellow
try {
    & $script
    Write-Host '      脚本执行完成（结果见上方日志或 .git-local\autopush.log）'
} catch {
    Write-Host "      脚本执行出错：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '      继续注册任务，但请先看日志排查。' -ForegroundColor Yellow
}

# ---------- 注册任务 ----------
Write-Host "[4/4] 注册计划任务 '$taskName' …"

$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script) `
    -WorkingDirectory $repoPath

$logon = New-ScheduledTaskTrigger -AtLogOn
$logon.Delay = 'PT2M'

$every10 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
    -RepetitionInterval (New-TimeSpan -Minutes 10)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

# 以当前用户身份、交互式令牌运行 —— 这样能复用 Windows 凭据管理器里已保存的
# GitHub 凭据，不会卡在登录提示上。
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName `
    -Action $action -Trigger $logon, $every10 `
    -Settings $settings -Principal $principal `
    -Description 'Auto-push committed work in D:\desktop\Face two to GitHub. Never commits; only pushes what a human already committed.' `
    -Force | Out-Null

Write-Host ''
Write-Host '注册成功。' -ForegroundColor Green
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName, State | Format-Table -AutoSize

Write-Host '可用以下命令立即测试一次（不必等定时触发）：' -ForegroundColor Cyan
Write-Host "    Start-ScheduledTask -TaskName '$taskName'"
Write-Host '查看运行结果：'
Write-Host "    Get-Content '$repoPath\.git-local\autopush.log' -Tail 20"
Write-Host ''
Write-Host '它只会推送你【已经 git commit 过】的内容，永远不会自动提交。' -ForegroundColor Cyan
Write-Host ''
