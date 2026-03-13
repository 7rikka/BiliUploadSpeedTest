#!/bin/bash

set -euo pipefail

# 检查必需命令
for cmd in curl jq bc; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误: 未找到 $cmd，请先安装。"
        exit 1
    fi
done

# 清理临时文件
cleanup() {
    rm -f /tmp/speedtest_*.bin
}
trap cleanup EXIT

# 生成测试数据文件（全零填充）
echo "生成测试数据..."
bytes_0_1=$(awk "BEGIN {printf \"%.0f\", 0.1 * 1024 * 1024}")   # 0.1 MB 取整
bytes_1=$((1 * 1024 * 1024))
bytes_10=$((10 * 1024 * 1024))

head -c "$bytes_0_1" /dev/zero > /tmp/speedtest_0.1M.bin
head -c "$bytes_1"   /dev/zero > /tmp/speedtest_1M.bin
head -c "$bytes_10"  /dev/zero > /tmp/speedtest_10M.bin
echo "测试数据准备完成。"

# 获取线路列表
echo "获取线路信息..."
lines_json=$(curl -s "https://member.bilibili.com/preupload?r=ping&file=lines.json")
# 解析为 bref 和 url 的制表符分隔列表
mapfile -t lines < <(echo "$lines_json" | jq -r '.[] | [.bref, .url] | @tsv')

if [ ${#lines[@]} -eq 0 ]; then
    echo "错误: 未能获取到任何线路信息。"
    exit 1
fi

echo "获取到 ${#lines[@]} 条线路："
for line in "${lines[@]}"; do
    IFS=$'\t' read -r bref _ <<< "$line"
    echo "  - $bref"
done

# 格式化时间的函数（用于表格输出）
format_time() {
    local t=$1
    if [ -z "$t" ] || [ "$t" = "Error" ]; then
        echo -n "Error"
        return
    fi
    if [[ $t =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf "%.2f" "$t"
    else
        echo -n "$t"
    fi
}

# 用于存储线路名和原始测试值的数组
line_names=()
post01_vals=()
post1_vals=()
post10_vals=()
get_vals=()
echo
# 打印表头（序号列左对齐）
printf "%-4s %-20s %-12s %-12s %-12s %-12s\n" "No." "Line" "Post 0.1 MB" "Post 1 MB" "Post 10 MB" "Get"
printf "%-4s %-20s %-12s %-12s %-12s %-12s\n" "----" "--------------------" "------------" "------------" "------------" "------------"
index=1
for line in "${lines[@]}"; do
    IFS=$'\t' read -r bref base_url <<< "$line"
    full_base_url="https:${base_url}"

    # 存储当前线路的原始测试结果
    t01=""
    t1=""
    t10=""
    tget=""

    # POST 0.1 MB
    url="${full_base_url}?line=0.1"
    time=$(curl -s -o /dev/null -w "%{time_total}" --max-time 30 \
        -X POST --data-binary @/tmp/speedtest_0.1M.bin "$url" 2>/dev/null) || time="Error"
    t01="$time"
    post_0_1=$(format_time "$time")

    # POST 1 MB
    url="${full_base_url}?line=1"
    time=$(curl -s -o /dev/null -w "%{time_total}" --max-time 30 \
        -X POST --data-binary @/tmp/speedtest_1M.bin "$url" 2>/dev/null) || time="Error"
    t1="$time"
    post_1=$(format_time "$time")

    # POST 10 MB
    url="${full_base_url}?line=10"
    time=$(curl -s -o /dev/null -w "%{time_total}" --max-time 30 \
        -X POST --data-binary @/tmp/speedtest_10M.bin "$url" 2>/dev/null) || time="Error"
    t10="$time"
    post_10=$(format_time "$time")

    # GET 请求
    time=$(curl -s -o /dev/null -w "%{time_total}" --max-time 30 "$full_base_url" 2>/dev/null) || time="Error"
    tget="$time"
    get_time=$(format_time "$time")

    # 打印结果行（序号列左对齐）
    printf "%-4d %-20s %12s %12s %12s %12s\n" \
        "$index" "$bref" "$post_0_1" "$post_1" "$post_10" "$get_time"

    # 保存数据用于后续统计
    line_names+=("$bref")
    post01_vals+=("$t01")
    post1_vals+=("$t1")
    post10_vals+=("$t10")
    get_vals+=("$tget")

    ((index++))
done

echo -e "\n测速完成。"

# 统计每个测试项的最优线路
echo -e "\n耗时最少的线路："

# 定义测试项及其对应的数组
declare -A tests=(
    ["Post 0.1 MB"]="post01_vals"
    ["Post 1 MB"]="post1_vals"
    ["Post 10 MB"]="post10_vals"
    ["Get"]="get_vals"
)

for name in "Post 0.1 MB" "Post 1 MB" "Post 10 MB" "Get"; do
    arr_name="${tests[$name]}"
    # 使用 nameref 间接引用数组
    declare -n vals="$arr_name"

    min_val=""
    min_line=""
    for i in "${!line_names[@]}"; do
        val="${vals[$i]}"
        # 检查是否为有效数字
        if [[ $val =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            if [ -z "$min_val" ] || (( $(echo "$val < $min_val" | bc -l) )); then
                min_val="$val"
                min_line="${line_names[$i]}"
            fi
        fi
    done

    if [ -n "$min_val" ]; then
        printf "%-12s : %s (%.2f 秒)\n" "$name" "$min_line" "$min_val"
    else
        printf "%-12s : 无有效数据\n" "$name"
    fi
done