#!/usr/bin/env bash
# 小米 / Redmi / POCO 隐私组件清理脚本（Mac / Linux，免 root，可恢复）
#
# 用法：
#   ./xiaomi_privacy.sh                 进入菜单
#   ./xiaomi_privacy.sh check           只检查，不做任何改动
#   ./xiaomi_privacy.sh basic           删除 A + B 级（隐私上报 + 广告推荐）
#   ./xiaomi_privacy.sh carrier         删除 C 级（运营商注册组件）
#   ./xiaomi_privacy.sh optional        逐个询问 D 级（可选功能）
#   ./xiaomi_privacy.sh risky           逐个询问 E 级（高风险）
#   ./xiaomi_privacy.sh restore [包名]  恢复清单里所有已删的包，或只恢复指定的包
#
# 原理：adb shell pm uninstall --user 0 <包名>
#   只对当前用户卸载，系统分区里的安装包还在，随时能用 restore 装回；
#   恢复出厂设置后这些组件也会全部回来。

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
LIST="$DIR/packages.txt"
LOG="$DIR/removed_$(date +%Y%m%d_%H%M%S).log"
REMOVED_COUNT=0

# ---------- 找 adb ----------
if [ -x "$DIR/adb" ]; then
  ADB="$DIR/adb"
elif command -v adb >/dev/null 2>&1; then
  ADB="adb"
else
  echo "找不到 adb。请先安装 Android Platform Tools："
  echo "  Mac:   brew install android-platform-tools"
  echo "  Linux: sudo apt install adb   （或从 developer.android.com 下载 platform-tools）"
  exit 1
fi

# 在手机上执行命令；stdin 接 /dev/null，避免 adb 吃掉键盘输入
adb_sh() { "$ADB" shell "$@" </dev/null 2>/dev/null | tr -d '\r'; }

# ---------- 读清单 ----------
T=(); P=(); N=(); D=()
load_list() {
  if [ ! -f "$LIST" ]; then
    echo "找不到 packages.txt，它要和本脚本放在同一个文件夹里。"
    exit 1
  fi
  local t p n d
  while IFS='|' read -r t p n d || [ -n "$t" ]; do
    t="${t//[[:space:]]/}"
    p="${p//[[:space:]]/}"
    case "$t" in A|B|C|D|E) ;; *) continue ;; esac
    [ -z "$p" ] && continue
    d="${d%$'\r'}"
    T+=("$t"); P+=("$p"); N+=("$n"); D+=("$d")
  done < "$LIST"
}

# ---------- 连接检查 ----------
check_device() {
  local devs ok unauth
  devs="$("$ADB" devices </dev/null 2>/dev/null | tr -d '\r')"
  ok="$(printf '%s\n' "$devs" | awk -F'\t' '$2=="device"' | wc -l | tr -d ' ')"
  unauth="$(printf '%s\n' "$devs" | awk -F'\t' '$2=="unauthorized"' | wc -l | tr -d ' ')"
  if [ "$ok" -eq 0 ]; then
    if [ "$unauth" -gt 0 ]; then
      echo "手机上应该弹出了“允许 USB 调试吗？”，请点允许（建议勾选“始终允许”），然后重新运行。"
    else
      echo "没检测到手机。请检查："
      echo "  1. 数据线能传数据（有些线只能充电）"
      echo "  2. 设置 → 更多设置 → 开发者选项 → USB 调试 已打开"
      echo "  3. 手机连接方式选“传输文件”"
    fi
    exit 1
  fi
  if [ "$ok" -gt 1 ] && [ -z "${ANDROID_SERIAL:-}" ]; then
    echo "检测到多台设备，请只连一台手机后再运行。"
    exit 1
  fi

  local brand model osver miui android moddev region
  brand="$(adb_sh getprop ro.product.brand)"
  model="$(adb_sh getprop ro.product.marketname)"
  [ -z "$model" ] && model="$(adb_sh getprop ro.product.model)"
  osver="$(adb_sh getprop ro.mi.os.version.incremental)"
  miui="$(adb_sh getprop ro.miui.ui.version.name)"
  android="$(adb_sh getprop ro.build.version.release)"
  moddev="$(adb_sh getprop ro.product.mod_device)"
  case "$moddev" in
    *_global*) region="国际版" ;;
    *_eea*|*_ru*|*_in*|*_id*|*_tw*|*_jp*|*_tr*) region="海外版" ;;
    "") region="未知" ;;
    *) region="国行（推测）" ;;
  esac
  case "$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')" in
    "$(printf '%s' "$brand" | tr '[:upper:]' '[:lower:]')"*) ;;
    *) model="$brand $model" ;;
  esac
  echo "已连接：$model｜Android $android｜${osver:-${miui:-系统版本未知}}｜$region"
  case "$(printf '%s' "$brand" | tr '[:upper:]' '[:lower:]')" in
    xiaomi|redmi|poco) ;;
    *) echo "提醒：这台手机看起来不是小米/Redmi/POCO，本清单是按小米系统整理的。" ;;
  esac
}

# ---------- 包状态 ----------
INSTALLED=""; ALLPKG=""
refresh_pkgs() {
  INSTALLED="$(adb_sh pm list packages --user 0 | sed -n 's/^package://p')"
  ALLPKG="$(adb_sh pm list packages -u --user 0 | sed -n 's/^package://p')"
}
has() { printf '%s\n' "$2" | grep -qxF "$1"; }
status_of() {
  if has "$1" "$INSTALLED"; then echo present
  elif has "$1" "$ALLPKG"; then echo removed
  else echo absent; fi
}

tier_title() {
  case "$1" in
    A) echo "A 隐私上报（建议删）" ;;
    B) echo "B 广告推荐（建议删）" ;;
    C) echo "C 运营商注册组件（按需删，删后测试通话上网）" ;;
    D) echo "D 可选功能（不用就删）" ;;
    E) echo "E 高风险（默认不动）" ;;
  esac
}

# ---------- 删除 / 恢复 ----------
remove_one() { # $1=序号
  local i="$1" pkg="${P[$1]}" st out ime
  st="$(status_of "$pkg")"
  if [ "$st" = absent ]; then echo "  [跳过] $pkg  这台手机上没有"; return; fi
  if [ "$st" = removed ]; then echo "  [已删] $pkg  之前已经删过"; return; fi
  ime="$(adb_sh settings get secure default_input_method)"
  case "$ime" in
    "$pkg"/*) echo "  [跳过] $pkg  这是你正在用的输入法，请先在设置里切换到别的输入法"; return ;;
  esac
  out="$(adb_sh "pm uninstall --user 0 $pkg 2>&1")"
  if printf '%s' "$out" | grep -q 'Success'; then
    echo "  [成功] $pkg  ${N[$i]}"
    echo "$pkg" >> "$LOG"
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
    INSTALLED="$(printf '%s\n' "$INSTALLED" | grep -vxF "$pkg")"
  else
    echo "  [失败] $pkg  ${out:-没有返回信息}"
  fi
}

restore_one() { # $1=包名
  local out
  out="$(adb_sh "cmd package install-existing --user 0 $1 2>&1")"
  if printf '%s' "$out" | grep -q 'installed for user'; then
    echo "  [已恢复] $1"
  else
    echo "  [失败] $1  ${out:-没有返回信息}"
  fi
}

ask() { local a; read -r -p "$1 [y/N] " a; case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }

# ---------- 各模式 ----------
do_check() {
  refresh_pkgs
  local tier i st mark
  for tier in A B C D E; do
    echo
    echo "== $(tier_title "$tier") =="
    for i in "${!P[@]}"; do
      [ "${T[$i]}" = "$tier" ] || continue
      st="$(status_of "${P[$i]}")"
      case "$st" in
        present) mark="[还在]" ;;
        removed) mark="[已删]" ;;
        absent)  mark="[没有]" ;;
      esac
      echo "  $mark ${P[$i]}  ${N[$i]}"
    done
  done
  echo
  echo "[还在] = 手机上装着；[已删] = 已对当前用户卸载；[没有] = 你的系统里本来就没有这个包"
}

# 批量删除：$1 = 级别列表，例如 "A B"
do_batch() {
  refresh_pkgs
  local tiers="$1" idx=() i tier
  for tier in $tiers; do
    for i in "${!P[@]}"; do
      [ "${T[$i]}" = "$tier" ] || continue
      [ "$(status_of "${P[$i]}")" = present ] && idx+=("$i")
    done
  done
  if [ "${#idx[@]}" -eq 0 ]; then
    echo "这些级别里的组件，你的手机上都没有或已经删过了。"
    return
  fi
  echo
  echo "将要删除以下 ${#idx[@]} 个组件："
  for i in "${idx[@]}"; do
    echo "  - ${P[$i]}  ${N[$i]}"
    echo "      ${D[$i]}"
  done
  echo
  ask "确认删除？" || { echo "已取消。"; return; }
  for i in "${idx[@]}"; do remove_one "$i"; done
}

do_optional() {
  refresh_pkgs
  local i any=0
  echo
  echo "逐个询问 D 级可选功能（直接回车 = 不删）："
  for i in "${!P[@]}"; do
    [ "${T[$i]}" = D ] || continue
    [ "$(status_of "${P[$i]}")" = present ] || continue
    any=1
    echo
    echo "${N[$i]}（${P[$i]}）"
    echo "  ${D[$i]}"
    if ask "  删除？"; then remove_one "$i"; else echo "  已跳过"; fi
  done
  [ "$any" -eq 0 ] && echo "D 级组件你的手机上都没有或已经删过了。"
}

do_risky() {
  refresh_pkgs
  local i any=0 a
  echo
  echo "!!! E 级是高风险组件。建议先只删一个，重启后测试“安装一个 App”和手机管家是否正常，"
  echo "!!! 有问题马上用 restore 恢复。卡在开机画面时，保持数据线连接，用 restore 命令通常还能救回。"
  for i in "${!P[@]}"; do
    [ "${T[$i]}" = E ] || continue
    [ "$(status_of "${P[$i]}")" = present ] || continue
    any=1
    echo
    echo "${N[$i]}（${P[$i]}）"
    echo "  ${D[$i]}"
    read -r -p "  确定要删除，请输入大写 YES（其他任意输入 = 跳过）： " a
    if [ "$a" = YES ]; then remove_one "$i"; else echo "  已跳过"; fi
  done
  [ "$any" -eq 0 ] && echo "E 级组件你的手机上都没有或已经删过了。"
}

do_restore() { # $1 = 可选包名
  refresh_pkgs
  if [ -n "${1:-}" ]; then
    restore_one "$1"
    return
  fi
  local i any=0
  for i in "${!P[@]}"; do
    if [ "$(status_of "${P[$i]}")" = removed ]; then
      any=1
      restore_one "${P[$i]}"
    fi
  done
  [ "$any" -eq 0 ] && echo "清单里没有已删除的组件需要恢复。"
}

finish() {
  echo
  if [ "$REMOVED_COUNT" -gt 0 ]; then
    echo "本次共删除 $REMOVED_COUNT 个组件，记录在：$LOG"
    echo "重启后请测试：两张卡打电话 / 发短信 / 移动数据 / 安装一个 App / 微信等通知。"
    echo "要恢复某个包：./xiaomi_privacy.sh restore 包名"
    if ask "现在重启手机？"; then "$ADB" reboot </dev/null; fi
  fi
}

menu() {
  local c pkg
  while :; do
    echo
    echo "================ 小米隐私组件清理 ================"
    echo "  1) 检查：看看手机上有哪些（不做改动，建议先选这个）"
    echo "  2) 删除 A + B：隐私上报 + 广告推荐（推荐）"
    echo "  3) 删除 C：运营商注册组件（移动 / 电信）"
    echo "  4) 逐个选择 D：可选功能"
    echo "  5) 逐个选择 E：高风险组件"
    echo "  6) 恢复"
    echo "  0) 退出"
    read -r -p "请选择： " c || break
    case "$c" in
      1) do_check ;;
      2) do_batch "A B" ;;
      3) echo; echo "提醒：删后请测试通话、上网和支付，有问题选 6 恢复。"; do_batch "C" ;;
      4) do_optional ;;
      5) do_risky ;;
      6) read -r -p "输入要恢复的包名（直接回车 = 恢复清单里所有已删的）： " pkg; do_restore "$pkg" ;;
      0|q|Q) break ;;
      *) echo "请输入 0-6。" ;;
    esac
  done
}

# ---------- 主流程 ----------
load_list
check_device
case "${1:-}" in
  "")       menu ;;
  check)    do_check ;;
  basic)    do_batch "A B" ;;
  carrier)  do_batch "C" ;;
  optional) do_optional ;;
  risky)    do_risky ;;
  restore)  do_restore "${2:-}" ;;
  *) echo "未知参数：$1（可用：check / basic / carrier / optional / risky / restore [包名]）"; exit 1 ;;
esac
finish
