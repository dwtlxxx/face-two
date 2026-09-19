<#
.SYNOPSIS
    自动把当前分支已提交但未推送的内容推送到 GitHub。

.DESCRIPTION
    由 Windows 计划任务定期调用。核心原则：

      * 绝不执行 git add / git commit —— 提交内容与提交信息始终由人决定。
      * 只在「本地领先远程」时推送，没有任何待推送内容时什么都不做。
      * 推送失败不抛异常，只记录日志，避免计划任务报错刷屏。

    因此这个脚本不可能把未完成或未打算提交的代码送上 GitHub。

.PARAMETER RepoPath
    仓库根目录。默认取脚本所在目录的上一级。

.PARAMETER Remote
    远程名，默认 origin。

.PARAMETER Branch
    要推送的分支。默认自动识别当前分支。
#>
[CmdletBinding()]
param(
    [string]$RepoPath,
    [string]$Remote  = 'origin',
    [string]$Branch,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'

# ---------- 解析路径 ----------
if (-not $RepoPath) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepoPath  = Split-Path -Parent $scriptDir
}
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path

if (-not $LogFile) { $LogFile = Join-Path $RepoPath '.git-local\autopush.log' }
$logDir = Split-Path -Parent $LogFile
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

# 捕获 git 输出到文件再读取，避免 PowerShell 把 git 写在 stderr 的正常信息
# （例如 "Everything up-to-date"）包装成 NativeCommandError 异常而误判为失败。
function Invoke-Git {
    param([string[]]$Arguments)
    $tmp = Join-Path $env:TEMP ("gitout_{0}_{1}.txt" -f $PID, [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        & $git @Arguments *> $tmp
        $code = $LASTEXITCODE
        $text = if (Test-Path -LiteralPath $tmp) { (Get-Content -LiteralPath $tmp -Raw) } else { '' }
        return [pscustomobject]@{ Code = $code; Output = ($text -as [string]) }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# 日志轮转：超过 256KB 就保留最后 500 行，防止无限增长
try {
    if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt 256KB) {
        $tail = Get-Content -LiteralPath $LogFile -Tail 500
        Set-Content -LiteralPath $LogFile -Value $tail -Encoding UTF8
    }
} catch { }

# ---------- 防止重入 ----------
# 若上一次执行（例如卡在网络上）还没结束，这次直接退出，避免任务堆积。
$lockFile = Join-Path $logDir 'autopush.lock'
if (Test-Path -LiteralPath $lockFile) {
    $stale = $true
    try {
        $raw = (Get-Content -LiteralPath $lockFile -Raw).Trim()
        if ($raw -match '^(\d+)\|(.+)$') {
            $pid0 = [int]$Matches[1]
            $proc = Get-Process -Id $pid0 -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq $Matches[2]) { $stale = $false }
        }
    } catch { }
    if (-not $stale) {
        Write-Log '上一次执行仍在进行，跳过本次。' 'SKIP'
        exit 0
    }
    Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
}
Set-Content -LiteralPath $lockFile -Value ("{0}|{1}" -f $PID, (Get-Process -Id $PID).ProcessName) -Encoding ASCII

try {
    # ---------- 定位 git ----------
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if (-not $git) {
        foreach ($c in @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
            if (Test-Path -LiteralPath $c) { $git = $c; break }
        }
    }
    if (-not $git) { Write-Log '找不到 git，放弃。' 'ERROR'; exit 1 }

    # 关键：禁用交互提示。无人值守场景下绝不能卡在等输入。
    $env:GIT_TERMINAL_PROMPT = '0'

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        # bare 仓库和 worktree 没有 .git 目录，用 rev-parse 复核，不能只靠 Test-Path
        $null = Invoke-Git -Arguments @('-C', $RepoPath, 'rev-parse', '--git-dir')
        if ($LASTEXITCODE -ne 0) {
            Write-Log "目标不是 git 仓库：$RepoPath" 'ERROR'; exit 1
        }
    }

    # ---------- 确认是当前分支 ----------
    if (-not $Branch) {
        $Branch = (& $git -C $RepoPath rev-parse --abbrev-ref HEAD 2>&1 | Out-String).Trim()
    }
    if (-not $Branch -or $Branch -eq 'HEAD') {
        Write-Log '处于游离 HEAD 状态，不自动推送。' 'SKIP'; exit 0
    }

    # 没配 upstream 就补上，否则后面比较不了领先/落后
    $upstream = (& $git -C $RepoPath rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $upstream -like '*fatal*' -or $upstream -like '*no upstream*') {
        Write-Log "分支 $Branch 未设置 upstream，设为 $Remote/$Branch 后继续。"
        & $git -C $RepoPath branch "--set-upstream-to=$Remote/$Branch" $Branch 2>&1 | Out-Null
        $upstream = "$Remote/$Branch"
    }

    # ---------- 有东西要推吗 ----------
    $counts = (& $git -C $RepoPath rev-list --left-right --count "$upstream...$Branch" 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { Write-Log "无法比较 $upstream 与 $Branch：$counts" 'ERROR'; exit 1 }

    $parts   = $counts -split '\s+'
    $behind  = [int]$parts[0]
    $ahead   = [int]$parts[1]

    if ($ahead -eq 0) {
        Write-Log "无待推送内容（领先 0 / 落后 $behind）。" 'SKIP'; exit 0
    }

    Write-Log "发现 $ahead 个待推送提交，开始推送 $Branch -> $Remote …"

    # ---------- 推送 ----------
    # 先 fetch，避免远程有新提交导致 non-fast-forward 被拒
    Invoke-Git -Arguments @('-C', $RepoPath, 'fetch', '--quiet', $Remote) | Out-Null

    $r = Invoke-Git -Arguments @('-C', $RepoPath, 'push', $Remote, "refs/heads/$Branch`:refs/heads/$Branch")

    if ($r.Code -eq 0) {
        Write-Log "推送成功：$ahead 个提交已上传到 $Remote/$Branch。"
    } else {
        Write-Log "推送失败（exit=$($r.Code)）：$($r.Output.Trim())" 'ERROR'
        exit 1
    }
}
catch {
    Write-Log "发生异常：$($_.Exception.Message)" 'ERROR'
    exit 1
}
finally {
    Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
}
