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
  if [ "$detail" -eq 0 ] && [ -r "${path}_light" ]; then path="${path}_light"; fi
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
 CLANKER_DP_SNAPSHOT="$dp_snapshot" CLANKER_PERF_DETAIL="$detail" CLANKER_RECORDER_PID="${CLANKER_RECORDER_PID:-$$}" airoha-clanker-diag --perf
}
# Slow readout via native driver interfaces. tx_stats updates the driver's
# cumulative MIB counters under its mutex; never poke hardware registers here.
wifi_radio_snapshot() {
 section 'wireless rate and aggregation'; date -u; cat /proc/uptime
 for name in wed_enable npu_cached_hdr npu_perf npu_amsdu npu_profile npu_publish_batch; do
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
 for path in /sys/kernel/debug/ieee80211/phy*/mt76/tx_stats /sys/kernel/debug/ieee80211/phy*/mt76/hw-queues /sys/kernel/debug/ieee80211/phy0/mt76/kite_aggregation; do
  [ -r "$path" ] || continue
  printf '\ndebugfs=%s\n' "$path"
  cat "$path"
 done
}
# r71: include internal LAN ports and conduit CPU-port private PAUSE.
wifi_ports_snapshot() {
 section 'r71 physical ports'; date -u; cat /proc/uptime
 for port in lan4 lan2 lan3 eth0 lan1; do
  printf '\nport=%s\n' "$port"
  if [ ! -d "/sys/class/net/$port" ]; then echo 'available=0'; continue; fi
  for group in private eth-ctrl eth-mac; do
   printf 'query=ethtool-S port=%s group=%s\n' "$port" "$group"
   # Fixed argument list; never accept external shell command text.
   set -- -S "$port"
   [ "$group" = private ] || set -- "$@" --groups "$group"
   read -r query_start unused < /proc/uptime
   printf 'query_begin=%s\n' "$query_start"
   timeout -k 1 2 ethtool "$@" 2>&1
   rc=$?
   read -r query_end unused < /proc/uptime
   printf 'query_end=%s\n' "$query_end"
    printf 'query_status=%s (nonzero=unsupported/error/timeout; not zero traffic)\n' "$rc"
  done
 done
 cat /proc/uptime
}
# Low-rate adjacent queue evidence. Cached NPU sysfs; no live mailbox from
# readers, no FOE walk, counter clearing, control writes or raw /dev/mem.
wifi_network_snapshot() {
 section 'r73 network sample'; date -u
 read -r stamp unused < /proc/uptime; echo "network_begin=$stamp"
 for path in /sys/bus/platform/devices/*/clanker_host_status /sys/bus/platform/devices/*/clanker_path_status /sys/bus/platform/devices/*/clanker_cost_status /sys/bus/platform/devices/*/switch_status /sys/kernel/debug/ppe/frame_status /sys/kernel/debug/ppe/queue_status; do
  printf '\nnode=%s\n' "$path"
  if [ -r "$path" ]; then cat "$path"; else echo unavailable; fi
 done
 if [ -r /sys/kernel/debug/clk/clk_summary ]; then
  echo 'clock_source=CCF_reported_rate'; awk 'NR<=3 || /gsw|sys_bus|cpu/' /sys/kernel/debug/clk/clk_summary
 else echo clock=unavailable; fi
 section 'BQL bytes (individual gauges, not packet completion counters)'
 for port in eth0 lan1 lan2 lan3 lan4; do
  for queue in /sys/class/net/"$port"/queues/tx-*; do
   [ -d "$queue" ] || continue
   printf 'bql port=%s queue=%s' "$port" "${queue##*/}"
   for field in inflight limit; do
    printf ' %s=' "$field"
    if [ -r "$queue/byte_queue_limits/$field" ]; then
     tr -d '\n' < "$queue/byte_queue_limits/$field"
    else printf unavailable; fi
   done
   printf '\n'
  done
 done
 wifi_forwarding_snapshot
 section 'softnet'; cat /proc/net/softnet_stat
 section 'IRQ'; cat /proc/interrupts
 section 'software flow handoffs'; cat /proc/net/stat/nf_flowtable 2>/dev/null || echo unavailable
 read -r stamp unused < /proc/uptime; echo "network_end=$stamp"
}
wifi_forwarding_snapshot() {
 section 'r72 forwarding: kernel bridge + driver self FDB, neighbours'
 cat /proc/uptime
 timeout -k 1 2 bridge -s fdb show
 printf 'fdb_query_status=%s\n' "$?"
 timeout -k 1 2 ip neigh show
 printf 'neigh_query_status=%s\n' "$?"
 # The default PF_BRIDGE dump includes both bridge-master and DSA self FDB.
 # Keep "self" vs "master" in raw output; do not infer offload from one row.
}
wifi_flow_snapshot() {
 section 'r72 bound FOE and test conntrack (low frequency)'; date -u; cat /proc/uptime
 timeout -k 1 4 cat /sys/kernel/debug/ppe/bind
 printf 'bind_query_status=%s\n' "$?"
 if [ -r /proc/net/nf_conntrack ]; then
  awk '/(sport|dport)=520[12]([ ]|$)/' /proc/net/nf_conntrack
 elif command -v conntrack >/dev/null; then
  timeout -k 1 3 conntrack -L 2>/dev/null | awk '/(sport|dport)=520[12]([ ]|$)/'
 else echo conntrack_unavailable; fi
 cat /proc/uptime
}
wifi_fdb_events() {
 ulimit -f 4096
 exec timeout -k 2 "$1" bridge -t monitor fdb
}
wifi_topology_snapshot() {
 section 'r72 topology (lan1 role is not changed)'; date -u; cat /proc/uptime
 timeout -k 1 3 ip -d -s link
 timeout -k 1 2 ip -4 route
 for kind in link vlan fdb; do timeout -k 1 2 bridge "$kind" show; done
 for port in lan4 lan2 lan3 eth0 lan1; do
  [ -d "/sys/class/net/$port" ] || continue
  printf '\nport=%s\n' "$port"
  timeout -k 1 2 ethtool "$port"
  timeout -k 1 2 ethtool --show-eee "$port"
  timeout -k 1 2 ethtool -a "$port"
  timeout -k 1 2 ethtool -k "$port"
  timeout -k 1 2 tc -s qdisc show dev "$port"
  timeout -k 1 2 tc -s class show dev "$port"
 done
 timeout -k 1 3 nft list table bridge fw4
 cat /proc/uptime
}
wifi_link_timeline() {
 local duration=$1 begin now unused
 ulimit -f 8192
 read -r begin unused < /proc/uptime; begin=${begin%.*}
 while :; do
  read -r now unused < /proc/uptime
  [ "$(( ${now%.*} - begin ))" -lt "$duration" ] || break
  printf 'sample_begin=%s\n' "$now"
  cat /proc/net/dev /proc/stat
  read -r now unused < /proc/uptime
  printf 'sample_end=%s\n' "$now"
  sleep 1
 done
}
wifi_bounded() (
 # Child-only limit: failure preserves the recorder and its existing files.
 ulimit -f 16384
 timeout -k 2 25 "$0" "$@"
)
record_wifi() {
 destination=$1; seconds=${2:-180}
 case "$seconds" in ''|*[!0-9]*) return 2 ;; esac
 [ "$seconds" -ge 30 ] && [ "$seconds" -le 600 ] || return 2
 command -v timeout >/dev/null || { echo 'timeout is required' >&2; return 2; }
 [ -n "$destination" ] && (umask 077; mkdir "$destination") || return 2
 umask 077
 reason=complete; wait_pid=; log_pid=; link_pid=; fdb_pid=; count=0
 trap 'reason=interrupted; [ -z "$wait_pid" ] || kill "$wait_pid" 2>/dev/null' INT TERM HUP
 dp_snapshot="$destination/.datapath-current"
 export CLANKER_RECORDER_PID=$$
 read -r started junk < /proc/uptime; started=${started%.*}
 printf 'schema=7 cost_KC1=1 aggregation=1 switch_PHY=1 fdb_events=1 forwarding_every=2_samples network_every=2_samples topology_start_end=1 bind_every=6_samples detail_every=6_samples single_datapath_read=1 seconds=%s sleep_seconds=5 fast_sleep_seconds=1 pid=%s started_uptime=%s max_total_kib=32768; read-only\nreason=running\n' "$seconds" "$$" "$started" > "$destination/manifest.txt"
 {
  section 'record identity'; date -u
  cat /proc/uptime /proc/sys/kernel/random/boot_id
  timeout -k 1 3 ubus call system board
  cat /lib/firmware/airoha/en7581_MT7916_ClankerNPU_BUILDINFO.txt
  section 'offload mode (read-only)'
  timeout -k 1 5 ucode /usr/share/airoha-clanker-mode.uc
  section 'IPv4 routes'; ip -4 route
 } > "$destination/identity.log" 2>&1
 wifi_bounded --wifi-flows > "$destination/flows.log" 2>&1 || echo flows_start_failed >> "$destination/errors.log"
 wifi_bounded --wifi-topology > "$destination/topology-start.log" 2>&1 || echo topology_start_failed >> "$destination/errors.log"
 wifi_bounded --wifi-network > "$destination/network.log" 2>&1 || echo network_start_failed >> "$destination/errors.log"
 wifi_bounded --wifi-sample "$dp_snapshot" 1 > "$destination/start.log" 2>&1 || reason=start-failed
 wifi_bounded --wifi-radio > "$destination/radio.log" 2>&1 || echo radio_start_failed >> "$destination/errors.log"
 wifi_bounded --wifi-ports > "$destination/ports.log" 2>&1 || echo ports_start_failed >> "$destination/errors.log"
 if [ "$reason" = complete ]; then
  logread -f -F "$destination/system.log" -S 4096 &
  log_pid=$!
  timeout -k 2 "$seconds" "$0" --link-timeline "$seconds" > "$destination/link-timeline.log" 2>&1 &
  link_pid=$!
  "$0" --fdb-events "$seconds" > "$destination/fdb-events.log" 2>&1 &
  fdb_pid=$!
 fi
 while [ "$reason" = complete ]; do
  read -r now junk < /proc/uptime
  [ "$(( ${now%.*} - started ))" -lt "$seconds" ] || break
  printf 'sample=%s begin=%s\n' "$count" "$now" >> "$destination/timing.log"
  detail=0; [ "$((count % 6))" -eq 0 ] && detail=1
  wifi_bounded --wifi-sample "$dp_snapshot" "$detail" >> "$destination/trace.log" 2>> "$destination/errors.log" || { reason=sample-failed; break; }
  [ "$((count % 2))" -ne 0 ] || wifi_bounded --wifi-network >> "$destination/network.log" 2>&1 || echo network_sample_failed >> "$destination/errors.log"
  [ "$((count % 2))" -ne 0 ] || wifi_bounded --wifi-ports >> "$destination/ports.log" 2>&1 || echo ports_sample_failed >> "$destination/errors.log"
  [ "$((count % 6))" -ne 0 ] || wifi_bounded --wifi-flows >> "$destination/flows.log" 2>&1 || echo flows_sample_failed >> "$destination/errors.log"
  [ "$((count % 3))" -ne 0 ] || wifi_bounded --wifi-radio >> "$destination/radio.log" 2>&1 || echo radio_sample_failed >> "$destination/errors.log"
  read -r now junk < /proc/uptime
  printf 'sample=%s end=%s\n' "$count" "$now" >> "$destination/timing.log"
  count=$((count + 1))
  set -- $(du -sk "$destination")
  [ "$1" -lt 32768 ] || { reason=size-limit; break; }
  kill -0 "$log_pid" 2>/dev/null || { reason=logread-exited; break; }
  kill -0 "$link_pid" 2>/dev/null || { reason=timeline-exited; break; }
  sleep 5 & wait_pid=$!
  [ "$reason" = complete ] || kill "$wait_pid" 2>/dev/null
  wait "$wait_pid" 2>/dev/null; wait_pid=
 done
 [ -z "$fdb_pid" ] || kill "$fdb_pid" 2>/dev/null
 [ -z "$log_pid" ] || kill "$log_pid" 2>/dev/null
 [ -z "$link_pid" ] || kill "$link_pid" 2>/dev/null
 [ -z "$fdb_pid" ] || wait "$fdb_pid" 2>/dev/null
 [ -z "$log_pid" ] || wait "$log_pid" 2>/dev/null
 [ -z "$link_pid" ] || wait "$link_pid" 2>/dev/null
 wifi_bounded --wifi-sample "$dp_snapshot" 1 > "$destination/finish.log" 2>&1 || echo finish_failed >> "$destination/errors.log"
 wifi_bounded --wifi-radio >> "$destination/radio.log" 2>&1 || echo radio_finish_failed >> "$destination/errors.log"
 wifi_bounded --wifi-ports >> "$destination/ports.log" 2>&1 || echo ports_finish_failed >> "$destination/errors.log"
 wifi_bounded --wifi-network >> "$destination/network.log" 2>&1 || echo network_finish_failed >> "$destination/errors.log"
 wifi_bounded --wifi-flows >> "$destination/flows.log" 2>&1 || echo flows_finish_failed >> "$destination/errors.log"
 wifi_bounded --wifi-topology > "$destination/topology-finish.log" 2>&1 || echo topology_finish_failed >> "$destination/errors.log"
 rm -f "$dp_snapshot"
 read -r now junk < /proc/uptime
 printf 'reason=%s samples=%s finished_uptime=%s\n' "$reason" "$count" "$now" >> "$destination/manifest.txt"
 trap - INT TERM HUP
 [ "$reason" = complete ]
}
case "${1:-}" in
 '') snapshot ;;
 --check-mode) ucode /usr/share/airoha-clanker-mode.uc "${2:-invalid}" ;;
 --record-mode) record "${3:-}" "${4:-10}" "${2:-invalid}" ;;
 --record) record "${2:-}" "${3:-10}" ;;
 --wifi-sample) dp_snapshot=$2; wifi_trace_snapshot "$3" ;;
 --wifi-radio) wifi_radio_snapshot ;;
 --wifi-network) wifi_network_snapshot ;;
 --wifi-topology) wifi_topology_snapshot ;;
 --wifi-flows) wifi_flow_snapshot ;;
 --wifi-ports) wifi_ports_snapshot ;;
 --link-timeline) case "$2" in ''|*[!0-9]*) exit 2;; esac; [ "$2" -le 600 ] || exit 2; wifi_link_timeline "$2" ;;
 --fdb-events) case "$2" in ''|*[!0-9]*) exit 2;; esac; [ "$2" -ge 30 ] && [ "$2" -le 600 ] || exit 2; wifi_fdb_events "$2" ;;
 --record-wifi|--record-lan) record_wifi "${2:-}" "${3:-180}" ;;
 *) echo 'Usage: airoha-clanker-offload [--record NEW_DIR MINUTES | --record-mode MODE NEW_DIR MINUTES | --record-wifi NEW_DIR SECONDS | --record-lan NEW_DIR SECONDS | --check-mode MODE]; MODE=off|software|hardware, MINUTES=1..120, SECONDS=30..600' >&2; exit 2 ;;
esac
