# Выполняет команду на сервере (ssh apex) и пишет команду + вывод в server-log.md.
# Пример: .\tools\apex.ps1 -Cmd "hostname" -Why "проверка доступа"
param(
    [Parameter(Mandatory = $true)][string]$Cmd,
    [string]$Why = ''
)

$log = Join-Path $PSScriptRoot '..\server-log.md'

function Write-Log([string]$line) {
    $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

Write-Log ''
Write-Log "## $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if ($Why) { Write-Log "**Зачем:** $Why" }
Write-Log '```'
Write-Log "[root@apex]# $Cmd"

# Команда уходит через stdin, а не аргументом: Windows PowerShell 5.1 ломает вложенные кавычки в аргументах ssh.
# На сервере: sed убирает BOM, который PowerShell 5.1 ставит в начало stdin, tr убирает CR из CRLF.
$OutputEncoding = New-Object Text.UTF8Encoding $false
$Cmd | ssh -o BatchMode=yes -o ConnectTimeout=10 apex "sed '1s/^\xEF\xBB\xBF//' | tr -d '\r' | bash -s" 2>&1 | ForEach-Object { Write-Log "$_" }
$code = $LASTEXITCODE

Write-Log '```'
Write-Log "exit code: $code"
exit $code
