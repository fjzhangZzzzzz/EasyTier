# 固定官方客户端，使用官方 CLI 注册 Windows 服务；不修改防火墙；TUN 使用官方包内 Wintun。
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigUrl)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw '请在管理员 PowerShell 执行管理页命令。' }
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { throw '当前已验证安装入口仅支持 Windows x64。' }
$uri = [Uri]$ConfigUrl
if ($uri.Scheme -ne 'wss' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -notmatch '^/config/[^/]+$') { throw '接入地址不符合要求。' }
$origin = 'https://' + $uri.Authority
$base = Join-Path $env:ProgramFiles 'Homelab\EasyTier'
$state = Join-Path $env:ProgramData 'Homelab\EasyTier'
$serviceName = 'homelab-easytier-client'
$version = '2.7.0-318a0b06'
if ((Test-Path -LiteralPath $base) -or (Test-Path -LiteralPath $state) -or (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) { throw '发现既有安装；拒绝覆盖身份，请先核对原安装。' }
if (Get-Process -Name easytier-core -ErrorAction SilentlyContinue) { throw '发现 EasyTier Core 正在运行，请先核对已有实例。' }
$probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,15989)
try { $probe.Start() } catch { throw '本机 RPC 端口已占用，拒绝覆盖现有实例。' } finally { $probe.Stop() }
$tmp = Join-Path $env:TEMP ('homelab-et-install-' + [Guid]::NewGuid().ToString())
[void](New-Item -ItemType Directory -Path $tmp)
try {
    $archive = Join-Path $tmp 'core.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri ($origin + '/install/artifacts/easytier-windows-x86_64-318a0b06.zip') -OutFile $archive
    $stream = [IO.File]::OpenRead($archive)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() } finally { $stream.Dispose(); $sha.Dispose() }
    if ($actual -ne '26342c2026c384f368fa83eae109999faf38f26bc4f88a70b3b8ce0894d11a09') { throw '官方发布包校验失败。' }
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $tmp 'unpacked')
    $cores = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'unpacked') -Recurse -Filter easytier-core.exe)
    if ($cores.Count -ne 1) { throw '发布包目录结构异常。' }
    $source = $cores[0].Directory.FullName
    $coreVersion = & $cores[0].FullName --version
    if ($LASTEXITCODE -ne 0 -or $coreVersion -notmatch [Regex]::Escape($version)) { throw '官方 Core 版本不符。' }
    $release = Join-Path $base ('releases\' + $version)
    [void](New-Item -ItemType Directory -Path $release)
    [void](New-Item -ItemType Directory -Path (Join-Path $state 'config'))
    # 仅 SYSTEM 和本机管理员可读取持久网络配置。
    & icacls.exe $state /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' *> $null
    if ($LASTEXITCODE -ne 0) { throw '持久目录权限设置失败。' }
    foreach ($name in @('easytier-core.exe','easytier-cli.exe','wintun.dll','Packet.dll')) { Copy-Item -LiteralPath (Join-Path $source $name) -Destination $release }
    $machineId = [Guid]::NewGuid().ToString()
    @{machine_id=$machineId;version=$version;service=$serviceName} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $state 'installation.json') -Encoding UTF8
    $cli = Join-Path $release 'easytier-cli.exe'
    # 官方 CLI 输出含 Token，禁止透传到终端或持续日志。
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $installOutput = & $cli service --name $serviceName install --core-path (Join-Path $release 'easytier-core.exe') --service-work-dir $state --core-args --config-server $ConfigUrl --config-dir (Join-Path $state 'config') --machine-id $machineId --disable-env-parsing --rpc-portal 127.0.0.1:15989 2>&1
    $installCode = $LASTEXITCODE
    $ErrorActionPreference = $savedPreference
    if ($installCode -ne 0) { throw '官方服务注册失败；保留受限目录供排障。' }
    $installOutput = $null
    $ErrorActionPreference = 'Continue'
    $startOutput = & $cli service --name $serviceName start 2>&1
    $startCode = $LASTEXITCODE
    $ErrorActionPreference = $savedPreference
    if ($startCode -ne 0) { throw '服务启动失败；保留身份供排障。' }
    $startOutput = $null
    (Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
    Write-Output ('安装完成。设备 UUID：' + $machineId + '；请在管理页核对并批准加入网络。')
} finally {
    # 精确检查本次临时目录，使用同一 PowerShell 删除，不递归操作生产路径。
    $resolved = [IO.Path]::GetFullPath($tmp)
    $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^homelab-et-install-[0-9a-f-]+$') { throw '临时路径越界，拒绝删除。' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
