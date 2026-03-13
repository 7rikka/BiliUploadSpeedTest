# BiliUploadSpeedTest

哔哩哔哩上传速度测试工具，用于测试不同 CDN 线路的上传速度。

## 使用方法

### Linux / macOS

使用 `wget`：

```bash
wget -qO- https://raw.githubusercontent.com/7rikka/BiliUploadSpeedTest/master/bili_speedtest.sh | bash
```

或使用 `curl`：

```bash
curl -Lso- https://raw.githubusercontent.com/7rikka/BiliUploadSpeedTest/master/bili_speedtest.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/7rikka/BiliUploadSpeedTest/master/bili_speedtest.ps1 | iex
```

## 测试说明

脚本会自动获取 B 站所有可用的上传线路，并对每条线路执行以下测试：

| 测试项         | 说明             |
|-------------|----------------|
| Post 0.1 MB | 上传 0.1 MB 数据耗时 |
| Post 1 MB   | 上传 1 MB 数据耗时   |
| Post 10 MB  | 上传 10 MB 数据耗时  |
| Get         | 下载请求耗时         |

测试完成后，会自动推荐每个测试项中耗时最少的线路。

## 依赖要求

### Linux / macOS
- `curl`
- `jq`
- `bc`

### Windows
- PowerShell 3.0+
- 可选：`curl.exe`（Windows 10 1803+ 自带）

## 输出示例

```
No.  Line                 Post 0.1 MB  Post 1 MB    Post 10 MB   Get
---- -------------------- ------------ ------------ ------------ ------------
1    cs-txa                       1.55         2.65         5.65         0.82
2    cs-alia                      2.42         5.58         7.90         1.26

测速完成。

耗时最少的线路：
Post 0.1 MB  : cs-txa (1.55 秒)
Post 1 MB    : cs-txa (2.65 秒)
Post 10 MB   : cs-txa (5.65 秒)
Get          : cs-txa (0.82 秒)
```

## 注意事项

- 测试需要访问 B 站接口，请确保网络畅通
- 单个请求超时时间为 30 秒
- 测试会消耗少量流量
