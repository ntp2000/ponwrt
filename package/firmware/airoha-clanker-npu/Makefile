include $(TOPDIR)/rules.mk

PKG_NAME:=airoha-clanker-npu
PKG_RELEASE:=65
PKG_BUILD_DEPENDS:=airoha-riscv-toolchain/host
PKG_BUILD_PARALLEL:=1
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ClankerConstruction/ClankerNPU.git
PKG_SOURCE_VERSION:=735529c10d5120e10f7e4a6ddf97fb384fce9903
PKG_MIRROR_HASH:=e115d22e0e49fa8060f8d94ae78d65dcac0460e89ce5fa2d09500bf482408215
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_SOURCE_VERSION)
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_FILE_DEPENDS:=$(TOPDIR)/scripts/airoha-clanker-dhcp-repair.sh $(TOPDIR)/scripts/airoha-clanker-dhcp-diag.sh $(TOPDIR)/scripts/airoha-clanker-mode.uc $(TOPDIR)/scripts/airoha-clanker-offload.sh $(TOPDIR)/scripts/airoha-clanker-perf.uc $(TOPDIR)/scripts/airoha-clanker-diag.sh $(TOPDIR)/scripts/airoha-clanker-wifi-status.uc $(TOPDIR)/scripts/airoha-clanker-diag.init

PKG_LICENSE:=NOASSERTION
PKG_LICENSE_FILES:=README.md
PKG_MAINTAINER:=ponwrt contributors

include $(INCLUDE_DIR)/package.mk

define Package/airoha-en7581-clanker-mt7916-npu
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=ClankerNPU firmware for AN7581 and MT7916 Kite
  DEPENDS:=@TARGET_airoha_an7581 +ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus
endef

define Package/airoha-en7581-clanker-mt7916-npu/description
  Open-source ClankerNPU AN7581/MT7916 firmware from commit
  $(PKG_SOURCE_VERSION). The upstream repository does not currently carry
  a separate SPDX license file; the source README is installed alongside
  the firmware. Redistribution follows the upstream permission confirmed
  for this integration.
endef

# Native host dependency downloads, verifies and stages the r65 compiler.
# An explicit override is useful for toolchain experiments, but equivalence
# to r65 must then be checked again. Normal builds need no shell setup.
CLANKER_RISCV_BIN ?= $(STAGING_DIR_HOSTPKG)/libexec/airoha-riscv/usr/bin
CLANKER_CROSS ?= $(CLANKER_RISCV_BIN)/riscv64-unknown-elf-

define Build/Compile
	+$(MAKE) -C $(PKG_BUILD_DIR) \
		CROSS="$(CLANKER_CROSS)" SOC=AN7581 WIFI=MT7916 \
		GITREV=$(PKG_SOURCE_VERSION) \
		CLANKER=0 MAILTRACE=0 NPUDBG=0 PROF=0 NPUTX=1
	test -s $(PKG_BUILD_DIR)/build/AN7581_MT7916/npu_rv32.bin
	test -s $(PKG_BUILD_DIR)/build/AN7581_MT7916/npu_data.bin
	test `wc -c < $(PKG_BUILD_DIR)/build/AN7581_MT7916/npu_rv32.bin` -le 2097152
	test `wc -c < $(PKG_BUILD_DIR)/build/AN7581_MT7916/npu_data.bin` -le 65536
	( printf '%s\n' \
		'Source: $(PKG_SOURCE_URL)' \
		'Commit: $(PKG_SOURCE_VERSION)' \
		'Variant: SOC=AN7581 WIFI=MT7916 CLANKER=0 MAILTRACE=0 NPUDBG=0 PROF=0 NPUTX=1' \
		'Local firmware changes: 100 RX validation; 101 diagnostics and transactional RX init; 102 extended control/BA and TDMA ownership; 103 ARM physical addresses and live control-only mode; 104 explicit host-ring lifetime and DMA quarantine; 105 DATA_STOP/DATA_RECOVER drain and retained-ring rearm; 106 host-ring consumption proof; 107 raw RX handoff for host reorder/PN; 108 security fallback metadata, mode-2 reorder candidate and generation fencing; 109 live-update reorder fence with raw-host downgrade; 110 completed security/fallback telemetry and reorder fences; 111 full-width host metadata; 112 AN7581 PCIe windows and RX ring observation; 113 unsupported-control metadata stub; 114 stopped-host sentinel consumption, producer-index rearm and SEC_MODE-only encrypted counters; 115 MT7916 dual-band NPU TX descriptor transport, negotiated hart4 fencing and validated DDR/MMIO publication; 116 complete PPE ingress/return, shared PN/BA security, native MT7916 downlink and lifetime fences; 117 whole-MPDU injection guard and identity-valid protocol-fault stop; 118 cfg80211 QoS map and validated single-TID BAR window; 120 native MT7916 token/PID contract; 119 preserve firmware fault identity on host WA errors; 121 RX policy-hit/miss and TDMA-full evidence; 122 restore DMA alignment with reserved statistics and ABI4 layout assertions; 123 publish accepted PN proof before encrypted RX policy lookup; 124 bridge L2 capture, NPU L4 policy hit/miss and host-adaptor software TX fallback; 126 fallback session/generation/key-generation fence; 127 allow open-network key_generation=0; 128 explicit bridge capture authorization and normalized bridge L4 hash; 129 self-contained Kite firmware type interfaces; 130 transactional bridge capture lookup version fence; 131 hart3-only bridge fallback copy, canonical single-frame descriptor, fault10 proven-stop contract; 132 RX early-admission and TX gate-drop diagnostics (reserved statistics, unchanged ABI4); 133 ABI5 tail quality counters and retired bridge capture guard; 137 H3C-derived ABI8 TDMA/rearm/publish/DMA/ready/fallback stage counters' \
		'Release52 scope: remove optional proxy/tunnel packages from image; reduce healthy summaries only (DP/TX 60s, NPU 120s); unchanged NPU binary logic, ABI5, DMA memory layout and r51 datapath' \
		'Release51 quality: fully revalidated identical flow refresh reuse; shared capture refs and retired deny guards; native L2 representative promotion; quality_band and dp_pause evidence; uplink acceleration deferred' \
		'Kite GET31 legacy ownership ABI: 1; legacy capabilities: 0 (not DATAPATH state); lifecycle capability: 128 (development data mode); security fallback/meta/reorder capabilities: 256/1024/512' \
		'Kite read-only diagnostics: GET32 ABI 1; 3 pages; 248-byte payload; page1 words43..58 completed-frame security/fallback counters, 59..60 reorder active/fences, 61 telemetry magic; page2 PCIe windows and WFDMA RX rings' \
		'Kite control: SET33/GET33 ABI 2; TX capability 2048, DATAPATH capability 4096; commands 14/15 TX bind/unbind, 16/17 DP bind/unbind, 18 RX purge; worker mask 0x1e' \
		'Kite datapath: shared ABI 12 (tail-only PS/pressure/idle observations; DMA offsets preserved), TX ownership ABI 2; host/NPU shared RX PN authority; exact Linux flow admission; hardware FOE learning; TDMA PPE downlink, native TXD/TXP, WTBL TX PN/SN, DMA+WA completion' \
		'Release65: 145/179/983; ABI12 batch16 single hart4; exact last-policy probe; candidate-only learning; NAPI-batched PS progress; batched FE readout, bounded PPE/static cache, single-read lightweight collector' \
		'Release64: 144/178/982; ABI12 unchanged; same-cookie L2 index refresh, exact suspended-rule retention, restartable learning, SRAM transition observation and batched counters, stage-coalesced PS progress, native authorized host fallback; batch16 single hart4' \
		'Release63: 143/177/981; ABI12; native flow reauthorization after PS, progress-driven bounded drain, gate hold, private-key-first lookup and idle-token backpressure, batched WFDMA ownership fence, bounded cause/PS observations; full128 TXWI, batch16, single hart4' \
		'Release62: 142; single-pass owned IPv4 word parser, compact held-token retry without payload reread, cold STA-fill/host-reap separation; exact live policies, full128-byte TXWI and DMA+WA ownership unchanged; host driver remains r61, ABI11, batch16, single hart4' \
		'Release61: 176 + mac80211 605; bounded software backlog probe without RCU wait or AQL-zero requirement; fixed native WFDMA prefix on PS wake, exact handoff/identity checks and r61_ps reason/timing telemetry; NPU patches 100-141 unchanged, ABI11, batch16, single hart4' \
		'Release60: 141/175/980 + mac80211 604; wire-order keys, separate generic path, exact PS suspend records, ordered host handoff and queue drain, TDMA bind readback and actual-traffic ingress fallback; default batch16, single hart4' \
		'Review repair: 117/139/945; PN rejection enforced at delivery; exact nft bridge L4 policy uses software fallback; routed PPE candidate requires hardware validation' \
		'Release55: 136/170/976 + mac80211 603; ABI8; private word-prefix/exact-policy/STA cache, complete word TXWI, 8-packet TDMA/WFDMA publication, event completion with bounded rescue, native BA TX activity, whole-loop and split wire latency; unchanged payload offsets and security contracts' \
		'Release59: 140/174/979 ABI10; single-hart compact IPv4 exact-key and validated STA context; bounded 8-slot per-band HOST-owned fallback FIFO and PS wake/revoke coalescing; 32-token WA completion batches, stage/age/PS/WA/NAPI/aggregation observations; old DMA offsets and double-completion retained' \
		'Release58: 139/173/978 ABI9; single-hart snapshot completion, pending bitmap rescue, version-proven WAN domain cache, 8/16 publish selector, acknowledged per-STA/TID BA drain and stage/pressure telemetry; old DMA offsets preserved' \
		'Release57: 138/172; private hart4 performance counters, word-prefix IPv4 parser, pure L2 hash cache with live policy scans, submit/other loop observation; ABI8 and all ownership/security/recovery contracts unchanged' \
		'Release56: 137/171; ABI8 unchanged; H3C-derived stage counters and host WA producer publication suppression when no new events; no descriptor, token, PN, recovery or reserved-memory contract changes' \
		'Release54: 135/169/975 ABI7; QoS-map-compatible IPv4 parser; eight bounded positive hints per band; sampled hart4 cycles and DMA/WA ages; gate durations and PPE errno classes; native survey/queue aggregation evidence; npu_profile=6 by default, 0 disables sampling' \
		'Performance candidate r53: 134/168/974; boot-only npu_perf and npu_amsdu controls; exact IPv4 hints and held-parse reuse; single-writer free/completion queues; native MCU-acknowledged A-MSDU length and per-TID BA contract; no broad L2 authorization' \
		'Kite datapath limits: AN7581 MT7916 AP, open/CCMP unicast; unsupported security/4addr/PS/TWT/ACM use host paths; configured DSCP maps are supported; rx_free_only and tx_freed are ownership completion, not endpoint delivery proof' \
		'Host integration candidate: firmware package release65; kernel patches 952-983; mt76 patches 120-179/release51; mac80211 release8/605; exact pre-route Ethernet matches use the reverse route gateway and peer, independently resolving DIRECT/NEIGH and post-NAT neighbors; native Ethernet MANGLE actions supply PPE output MACs; cookie replacements fully revalidate; identical live policies reuse; changed or invalid policies revoke, failed fences retain ownership; LAN bridge L2 capture publishes a separate capture authorization, NPU bridge policy carries IPv4/IPv6 TCP/UDP and ports, policy misses and non-L4/control frames use host fallback; bridge L4 and routed L4 hashes normalize wire IPv4/IPv6 types; fallback descriptors are fenced by session, band, station generation, key generation, DP authorization and VIF binding; 165 selects the station band PHY for host fallback and reports rejection reasons; WAN-routed PPE fast path remains unchanged; exact MAC-only bridge L2B egress is admitted by kernel patches 965-966; mt7915 recovery proof, idempotent reset, radio retry, persistent proven-stop retry with exponential backoff, timeout status resolution, transition snapshots, bounded event history and low-rate NPU/PPE/TX telemetry are patches 147-152/158-163; PPE learning scans are coalesced and serialized by kernel patches 963-964'; \
		printf '%s\n' 'Patch set: 100-145 (applied by ImmortalWrt package prepare); host trace/recovery/performance patches 162-179 are applied by ImmortalWrt mt76 package prepare; Linux/Airoha patches 981-983 supply ABI12, resume/soft-owner lifetime and candidate learning/batched FE observation; 978 publishes bucket sequences'; \
		find $(CURDIR)/patches -maxdepth 1 -type f -printf '%f\n' | sort; \
		$(CLANKER_CROSS)gcc --version | head -n 1; \
		cd $(PKG_BUILD_DIR)/build/AN7581_MT7916 && sha256sum npu_rv32.bin npu_data.bin \
	) > $(PKG_BUILD_DIR)/ponwrt-buildinfo.txt
endef

define Package/airoha-en7581-clanker-mt7916-npu/install
	$(INSTALL_DIR) $(1)/lib/firmware/airoha $(1)/usr/sbin $(1)/usr/share $(1)/etc/init.d
	$(INSTALL_BIN) $(TOPDIR)/scripts/airoha-clanker-dhcp-repair.sh $(1)/usr/sbin/airoha-clanker-dhcp-repair
	$(INSTALL_BIN) $(TOPDIR)/scripts/airoha-clanker-dhcp-diag.sh $(1)/usr/sbin/airoha-clanker-dhcp-diag
	$(INSTALL_BIN) $(TOPDIR)/scripts/airoha-clanker-offload.sh $(1)/usr/sbin/airoha-clanker-offload
	$(INSTALL_BIN) $(TOPDIR)/scripts/airoha-clanker-diag.sh $(1)/usr/sbin/airoha-clanker-diag
	$(INSTALL_DATA) $(TOPDIR)/scripts/airoha-clanker-mode.uc $(1)/usr/share/airoha-clanker-mode.uc
	$(INSTALL_DATA) $(TOPDIR)/scripts/airoha-clanker-perf.uc $(1)/usr/share/airoha-clanker-perf.uc
	$(INSTALL_DATA) $(TOPDIR)/scripts/airoha-clanker-wifi-status.uc $(1)/usr/share/airoha-clanker-wifi-status.uc
	$(INSTALL_BIN) $(TOPDIR)/scripts/airoha-clanker-diag.init $(1)/etc/init.d/airoha-clanker-diag
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/build/AN7581_MT7916/npu_rv32.bin \
		$(1)/lib/firmware/airoha/en7581_MT7916_npu_rv32.bin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/build/AN7581_MT7916/npu_data.bin \
		$(1)/lib/firmware/airoha/en7581_MT7916_npu_data.bin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/README.md \
		$(1)/lib/firmware/airoha/en7581_MT7916_ClankerNPU_SOURCE.md
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ponwrt-buildinfo.txt \
		$(1)/lib/firmware/airoha/en7581_MT7916_ClankerNPU_BUILDINFO.txt
endef

$(eval $(call BuildPackage,airoha-en7581-clanker-mt7916-npu))
