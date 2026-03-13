# 设置控制台输出编码为 UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 检查 curl 是否可用（如果可用则使用 curl，否则使用 .NET WebClient）
$useCurl = $null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)

# 生成测试数据的函数
function New-TestData {
    param([double]$sizeMB)
    $bytes = [math]::Round($sizeMB * 1024 * 1024)  # 四舍五入取整
    $data = New-Object byte[] $bytes
    # 填充数据（可自定义，此处全填 0）
    # 若需特定模式，可修改循环，例如 for ($i=0; $i -lt $bytes; $i++) { $data[$i] = $i % 256 }
    return $data
}

# 生成三个测试数据块（只生成一次，后续复用）
Write-Host "生成测试数据..." -ForegroundColor Cyan
$data01 = New-TestData -sizeMB 0.1
$data1  = New-TestData -sizeMB 1
$data10 = New-TestData -sizeMB 10
Write-Host "测试数据准备完成。" -ForegroundColor Green

# 获取线路列表
Write-Host "获取线路信息..." -ForegroundColor Cyan
$linesJson = Invoke-RestMethod -Uri 'https://member.bilibili.com/preupload?r=ping&file=lines.json' -ErrorAction Stop
# 提取需要的字段：bref 和 url（注意 url 以 // 开头）
$lines = $linesJson | Select-Object @{Name='bref'; Expression={$_.bref}}, @{Name='base_url'; Expression={$_.url}}

Write-Host "获取到 $($lines.Count) 条线路：" -ForegroundColor Yellow
$lines | ForEach-Object { Write-Host "  - $($_.bref)" }

# 定义函数：执行一次请求并返回耗时（秒）
function Measure-Request {
    param(
        [string]$url,
        [string]$method = 'GET',
        [byte[]]$body = $null
    )
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($useCurl) {
            # 使用 curl.exe（更接近原版）
            $tempFile = [System.IO.Path]::GetTempFileName()
            if ($method -eq 'POST') {
                # 将 body 写入临时文件，供 curl --data-binary 使用
                [System.IO.File]::WriteAllBytes($tempFile, $body)
                $arguments = '-s', '-o', 'nul', '-w', '%{time_total}', '--max-time', '30', '-X', 'POST', "--data-binary", "@$tempFile", $url
            } else {
                $arguments = '-s', '-o', 'nul', '-w', '%{time_total}', '--max-time', '30', $url
            }
            $result = & curl.exe @arguments 2>$null
            Remove-Item $tempFile -ErrorAction SilentlyContinue
            if ($LASTEXITCODE -eq 0 -and $result -match '^[\d\.]+$') {
                return [double]$result
            } else {
                return $null
            }
        } else {
            # 使用 .NET WebClient
            $wc = New-Object System.Net.WebClient
            if ($method -eq 'POST') {
                $null = $wc.UploadData($url, 'POST', $body)
            } else {
                $null = $wc.DownloadData($url)
            }
            $stopwatch.Stop()
            return $stopwatch.Elapsed.TotalSeconds
        }
    } catch {
        Write-Host "请求异常: $_" -ForegroundColor Red
        return $null  # 失败返回 $null
    } finally {
        if ($stopwatch.IsRunning) { $stopwatch.Stop() }
    }
}

# 格式化时间的函数（保留两位小数，失败显示 "Error"）
function Format-Time {
    param($time)
    if ($null -ne $time -and $time -is [double]) {
        return "{0:F2}" -f $time
    } else {
        return "Error"
    }
}

# 用于存储每条线路的原始结果（数值，用于后续比较）
$results = @()

# 打印表头（左对齐）
Write-Host
Write-Host ("{0,-4} {1,-20} {2,-12} {3,-12} {4,-12} {5,-12}" -f "No.", "Line", "Post 0.1 MB", "Post 1 MB", "Post 10 MB", "Get")
Write-Host ("{0,-4} {1,-20} {2,-12} {3,-12} {4,-12} {5,-12}" -f "----", "--------------------", "------------", "------------", "------------", "------------")

$index = 1
foreach ($line in $lines) {
    $bref = $line.bref
    $base_url = $line.base_url
    # 补全协议
    $full_base_url = "https:" + $base_url

    # POST 0.1 MB
    $url = $full_base_url + '?line=0.1'
    $t01_val = Measure-Request -url $url -method POST -body $data01
    $t01 = Format-Time $t01_val

    # POST 1 MB
    $url = $full_base_url + '?line=1'
    $t1_val = Measure-Request -url $url -method POST -body $data1
    $t1 = Format-Time $t1_val

    # POST 10 MB
    $url = $full_base_url + '?line=10'
    $t10_val = Measure-Request -url $url -method POST -body $data10
    $t10 = Format-Time $t10_val

    # GET 请求
    $tget_val = Measure-Request -url $full_base_url -method GET
    $tget = Format-Time $tget_val

    # 输出本行结果（序号、线路左对齐，其他列右对齐）
    Write-Host ("{0,-4} {1,-20} {2,12} {3,12} {4,12} {5,12}" -f $index, $bref, $t01, $t1, $t10, $tget)

    # 保存原始数值（用于后续统计）
    $results += [PSCustomObject]@{
        Line = $bref
        Post01 = $t01_val
        Post1  = $t1_val
        Post10 = $t10_val
        Get    = $tget_val
    }

    $index++
}
Write-Host
Write-Host "测速完成。" -ForegroundColor Green

# 找出每个测试项耗时最少的线路
Write-Host "`n耗时最少的线路：" -ForegroundColor Cyan

# 定义测试项及其显示名称
$testItems = @(
    @{Name="Post 0.1 MB"; Property="Post01"},
    @{Name="Post 1 MB";   Property="Post1"},
    @{Name="Post 10 MB";  Property="Post10"},
    @{Name="Get";         Property="Get"}
)

foreach ($item in $testItems) {
    $prop = $item.Property
    $displayName = $item.Name

    # 筛选有效数值（不为 $null）
    $valid = $results | Where-Object { $null -ne $_.$prop }

    if ($valid.Count -eq 0) {
        Write-Host ("{0,-12} : 无有效数据" -f $displayName)
        continue
    }

    # 找出最小值及其对应的线路
    $minValue = ($valid | Measure-Object -Property $prop -Minimum).Minimum
    $bestLine = ($valid | Where-Object { $_.$prop -eq $minValue } | Select-Object -First 1).Line

    Write-Host ("{0,-12} : {1} ({2:F2} 秒)" -f $displayName, $bestLine, $minValue)
}
