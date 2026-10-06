#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Read-only observations. Never enable offload, reset counters or access flash.
export LC_ALL=C
section() { printf '\n--- %s ---\n' "$*"; }
snapshot() {
 section 'offload identity'; date -u; cat /proc/uptime /proc/sys/kernel/random/boot_id
 section 'Clanker firmware build identity'
 if [ -r /lib/firmware/airoha/en7581_MT7916_ClankerNPU_BUILDINFO.txt ]; then
  grep -E '^(Source:|Commit:|Variant:|Host integration candidate:)' \
   /lib/firmware/airoha/en7581_MT7916_ClankerNPU_BUILDINFO.txt
 else
  echo 'buildinfo unavailable (old image or firmware package missing)'
 fi
 section 'verified offload mode (table flags are not packet hits)'
 ucode /usr/share/airoha-clanker-mode.uc
 section 'configured firewall offload (configuration is not evidence of hits)'
 for option in flow_offloading flow_offloading_hw; do
  printf '%s=' "$option"; uci -q get "firewall.@defaults[0].$option" || echo unset
 done
 section 'actual flowtables and forwarding rules'
 nft list flowtables 2>&1
 nft list table bridge fw4 2>&1
 nft list chain inet fw4 forward 2>&1
 section 'software flow handoffs (per CPU, unsigned decimal counters wrap at 32 bits)'
 cat /proc/net/stat/nf_flowtable 2>/dev/null || echo unavailable
 section 'PPE setup and raw QDMA source counters (cpu/fwd labels do not prove PPE hits)'
 cat /sys/kernel/debug/ppe/status /sys/kernel/debug/ppe/config 2>/dev/null || echo unavailable
 section 'PPE bound entries (BND is installation; timestamp movement adds activity evidence)'
 cat /sys/kernel/debug/ppe/bind 2>/dev/null || echo unavailable
 section 'Kite routed admission and datapath evidence'
 cat /sys/kernel/debug/ppe/status 2>/dev/null | grep -E '^(kite_|.*rx_ppe|.*rx_bytes|.*tx_sent|.*tx_bytes|.*hw_submitted|.*hw_reaped)' || echo unavailable
 section 'test conntrack (5201/5202 only; OFFLOAD and HW_OFFLOAD are installation flags)'
 if [ -r /proc/net/nf_conntrack ]; then
  awk '/(sport|dport)=520[12]([ ]|$)/' /proc/net/nf_conntrack
 elif command -v conntrack >/dev/null; then
  conntrack -L 2>/dev/null | awk '/(sport|dport)=520[12]([ ]|$)/'
 else
  echo unavailable
 fi
 section 'topology routes and physical links'
 ip -d -s link; ip route; ip -6 route
 bridge link show 2>&1; bridge vlan show 2>&1; bridge fdb show 2>&1
 section 'per-port driver features and hardware statistics'
 for path in /sys/class/net/*; do
  dev=${path##*/}
  [ "$dev" != lo ] || continue
  printf '\ninterface=%s carrier=' "$dev"; cat "$path/carrier" 2>/dev/null || echo unavailable
  ethtool -k "$dev" 2>&1 | grep -E 'offload|hw-tc|generic|Error|supported'
  ethtool -S "$dev" 2>&1
  # Standard MAC statistics include switch port counters when supported.
  ethtool --include-statistics -a "$dev" 2>&1
 done
 section 'PON registration and data mapping (read-only, identity omitted)'
 if command -v ponctl >/dev/null; then
  timeout 10 ponctl status --json
  timeout 10 ponctl data-path show
 else
  echo unavailable
 fi
 section 'PON public sysfs state (credentials excluded)'
 for path in /sys/class/pon/* /sys/class/net/pon*/device; do
  [ -d "$path" ] || continue
  for attr in state link_state pon_mode mode onu_state registration_state; do
   [ -r "$path/$attr" ] || continue
   printf '%s=' "$path/$attr"; cat "$path/$attr"
  done
 done
 section 'NPU descriptor transport'; airoha-clanker-diag --status
 section 'host CPU and interface counters'; airoha-clanker-diag --perf
}
record() {
 destination=$1; minutes=${2:-10}; expected_mode=${3:-}
 if [ -n "$expected_mode" ]; then
  ucode /usr/share/airoha-clanker-mode.uc "$expected_mode" || return 2
 fi
 case "$minutes" in ''|*[!0-9]*) return 2 ;; esac
 [ "$minutes" -ge 1 ] && [ "$minutes" -le 120 ] || return 2
 [ -n "$destination" ] && (umask 077; mkdir "$destination") || return 2
 umask 077
 trap 'reason=interrupted; [ -z "$wait_pid" ] || kill "$wait_pid" 2>/dev/null' INT TERM HUP
 reason=complete; wait_pid=; count=0
 read -r started junk < /proc/uptime; started=${started%.*}
 printf 'schema=3 minutes=%s interval=10s expected_mode=%s\n' "$minutes" "${expected_mode:-unspecified}" > "$destination/manifest.txt"
 snapshot > "$destination/start.log" 2>&1
 logread -f -F "$destination/system.log" -S 4096 &
 log_pid=$!
 printf 'Recording offload evidence for %s minutes in %s. Ctrl-C stops cleanly.\n' "$minutes" "$destination"
 while [ "$reason" = complete ]; do
  read -r now junk < /proc/uptime
  [ "$(( ${now%.*} - started ))" -lt "$(( minutes * 60 ))" ] || break
  airoha-clanker-diag --perf >> "$destination/perf.log" 2>> "$destination/errors.log"
  {
   section 'TX/RX and PPE sample'; date -u; cat /proc/uptime
   airoha-clanker-diag --status
   cat /sys/kernel/debug/ppe/status 2>/dev/null || echo ppe_status_unavailable
  } >> "$destination/samples.log" 2>&1
  # Table scans occur only once per minute; compact counters are sampled above.
  if [ "$((count % 6))" -eq 0 ]; then
   if [ -n "$expected_mode" ]; then
    ucode /usr/share/airoha-clanker-mode.uc "$expected_mode" >> "$destination/mode.log" 2>&1 || { reason=mode-mismatch; break; }
   fi
   { date -u; cat /proc/uptime; cat /sys/kernel/debug/ppe/bind; } >> "$destination/bind.log" 2>&1
  fi
  count=$((count + 1))
  kill -0 "$log_pid" 2>/dev/null || { reason=logread-exited; break; }
  sleep 10 & wait_pid=$!
  [ "$reason" = complete ] || kill "$wait_pid" 2>/dev/null
  wait "$wait_pid" 2>/dev/null; wait_pid=
 done
 kill "$log_pid" 2>/dev/null; wait "$log_pid" 2>/dev/null
 snapshot > "$destination/finish.log" 2>&1
 if [ -n "$expected_mode" ]; then
  ucode /usr/share/airoha-clanker-mode.uc "$expected_mode" >> "$destination/mode.log" 2>&1 || reason=mode-mismatch
 fi
 printf 'reason=%s samples=%s\n' "$reason" "$count" >> "$destination/manifest.txt"
 trap - INT TERM HUP
 [ "$reason" = complete ]
}
wifi_trace_snapshot() {
 local detail=${1:-1}
 section 'wireless NPU trace sample'; date -u; cat /proc/uptime
 for path in /sys/kernel/debug/ieee80211/phy*/mt76; do
  [ -d "$path" ] || continue
  printf 'debugfs=%s\n' "$path"
  for kind in kite_trace kite_events kite_tx kite_rx; do
   case "$kind:$detail" in kite_trace:0|kite_events:0) continue ;; esac
   [ -r "$path/$kind" ] || continue
   printf '\n[%s]\n' "$kind"; cat "$path/$kind"
  done
  break
 done
 section 'wireless datapath counters'
 : > "$dp_snapshot"
 for path in /sys/kernel/debug/ieee80211/phy*/mt76/kite_datapath; do
  [ -r "$path" ] || continue
  cat "$path" > "$dp_snapshot"; break
 done
 if [ "$detail" -eq 1 ]; then cat "$dp_snapshot"; else
  awk '!/^r63_ps_event / && !/^sta[0-9]+ /' "$dp_snapshot"
 fi
 if [ "$detail" -eq 1 ]; then
 section 'wireless activation'
 airoha-clanker-diag --wifi 2>&1
 for iface in /sys/class/net/*; do
  [ -d "$iface/phy80211" ] || continue
  printf 'interface=%s operstate=' "${iface##*/}"
  cat "$iface/operstate" 2>/dev/null || echo unavailable
 done
 fi
 section 'host CPU and interface counters'
 CLANKER_DP_SNAPSHOT="$dp_snapshot" CLANKER_PERF_DETAIL="$detail" CLANKER_RECORDER_PID="$$" airoha-clanker-diag --perf
}
# Slow readout via native driver interfaces. tx_stats updates the driver's
# cumulative MIB counters under its mutex; never poke hardware registers here.
wifi_radio_snapshot() {
 section 'wireless rate and aggregation'; date -u; cat /proc/uptime
 for name in npu_perf npu_amsdu npu_profile npu_publish_batch; do
  printf '%s=' "$name"
  cat "/sys/module/mt7915e/parameters/$name" 2>/dev/null || echo unavailable
 done
 for iface in /sys/class/net/*; do
  [ -d "$iface/phy80211" ] || continue
  printf '\ninterface=%s\n' "${iface##*/}"
  iw dev "${iface##*/}" station dump
  iw dev "${iface##*/}" survey dump
 done
 echo 'aggregation_scope=AMSDU_sum_both_PHY_deltas_AMPDU_per_band'
 for path in /sys/kernel/debug/ieee80211/phy*/mt76/tx_stats /sys/kernel/debug/ieee80211/phy*/mt76/hw-queues; do
  [ -r "$path" ] || continue
  printf '\ndebugfs=%s\n' "$path"
  cat "$path"
 done
}
record_wifi() {
 destination=$1; seconds=${2:-180}
 case "$seconds" in ''|*[!0-9]*) return 2 ;; esac
 [ "$seconds" -ge 30 ] && [ "$seconds" -le 600 ] || return 2
 [ -n "$destination" ] && (umask 077; mkdir "$destination") || return 2
 umask 077
 reason=complete; wait_pid=; log_pid=; count=0
 dp_snapshot="$destination/.datapath-current"
 read -r started junk < /proc/uptime; started=${started%.*}
 printf 'schema=3 detail_interval=30s single_datapath_read=1 seconds=%s interval=5s pid=%s started_uptime=%s; read-only\nreason=running\n' "$seconds" "$$" "$started" > "$destination/manifest.txt"
 {
  section 'record identity'; date -u
  cat /proc/uptime /proc/sys/kernel/random/boot_id
  ubus call system board
  cat /lib/firmware/airoha/en7581_MT7916_ClankerNPU_BUILDINFO.txt
  section 'offload mode (read-only)'
  ucode /usr/share/airoha-clanker-mode.uc
  section 'IPv4 routes'; ip -4 route
 } > "$destination/identity.log" 2>&1
 wifi_trace_snapshot > "$destination/start.log" 2>&1
 wifi_radio_snapshot > "$destination/radio.log" 2>&1
 logread -f -F "$destination/system.log" -S 4096 &
 log_pid=$!
 trap 'reason=interrupted; [ -z "$wait_pid" ] || kill "$wait_pid" 2>/dev/null' INT TERM HUP
 while [ "$reason" = complete ]; do
  read -r now junk < /proc/uptime
  [ "$(( ${now%.*} - started ))" -lt "$seconds" ] || break
  detail=0; [ "$((count % 6))" -eq 0 ] && detail=1
  wifi_trace_snapshot "$detail" >> "$destination/trace.log" 2>> "$destination/errors.log"
  [ "$((count % 2))" -eq 0 ] && cat /sys/kernel/debug/ppe/status >> "$destination/ppe.log" 2>&1
  [ "$((count % 3))" -eq 0 ] && wifi_radio_snapshot >> "$destination/radio.log" 2>&1
  count=$((count + 1))
  kill -0 "$log_pid" 2>/dev/null || { reason=logread-exited; break; }
  sleep 5 & wait_pid=$!
  [ "$reason" = complete ] || kill "$wait_pid" 2>/dev/null
  wait "$wait_pid" 2>/dev/null; wait_pid=
 done
 kill "$log_pid" 2>/dev/null; wait "$log_pid" 2>/dev/null
 wifi_trace_snapshot > "$destination/finish.log" 2>&1
 wifi_radio_snapshot >> "$destination/radio.log" 2>&1
 rm -f "$dp_snapshot"
 printf 'reason=%s samples=%s\n' "$reason" "$count" >> "$destination/manifest.txt"
 trap - INT TERM HUP
 [ "$reason" = complete ]
}
case "${1:-}" in
 '') snapshot ;;
 --check-mode) ucode /usr/share/airoha-clanker-mode.uc "${2:-invalid}" ;;
 --record-mode) record "${3:-}" "${4:-10}" "${2:-invalid}" ;;
 --record) record "${2:-}" "${3:-10}" ;;
 --record-wifi) record_wifi "${2:-}" "${3:-180}" ;;
 *) echo 'Usage: airoha-clanker-offload [--record NEW_DIR MINUTES | --record-mode MODE NEW_DIR MINUTES | --record-wifi NEW_DIR SECONDS | --check-mode MODE]; MODE=off|software|hardware, MINUTES=1..120, SECONDS=30..600' >&2; exit 2 ;;
esac
