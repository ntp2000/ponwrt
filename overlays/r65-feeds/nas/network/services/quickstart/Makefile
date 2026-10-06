#
# Copyright (C) 2015-2016 OpenWrt.org
# Copyright (C) 2020 jjm2473@gmail.com
#
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=quickstart
PKG_VERSION:=0.13.0
PKG_RELEASE:=4

QUICKSTART_SOURCE_VERSION:=880aeecbb7612799a49073e210d15cc9825e633e
PKG_SOURCE:=quickstart-$(QUICKSTART_SOURCE_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/istoreos/quickstart/tar.gz/$(QUICKSTART_SOURCE_VERSION)?
PKG_HASH:=5c550eb3e5b0282f9f58850e5659605e0fc2345f8c6ba3462ae3db0f5069c6b5

# Extract the repository archive into an isolated backend build root.
PKG_BUILD_DIR:=$(BUILD_DIR)/quickstart-$(QUICKSTART_SOURCE_VERSION)-backend
PKG_UNPACK:=$(TAR) -C "$(PKG_BUILD_DIR)" --strip-components=1 -xzf "$(DL_DIR)/$(PKG_SOURCE)"

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-values.mk

GO_HOST_BIN:=$(STAGING_DIR_HOSTPKG)/lib/go-$(GO_HOST_VERSION)/bin/go

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=Web Servers/Proxies
	TITLE:=Quickstart, the quick start.
	DEPENDS:=@(x86_64||aarch64||arm) +shadow-utils +shadow-useradd +mount-utils +block-mount +lsblk +e2fsprogs +parted \
		+smartmontools +smartd +smartmontools-drivedb +mdadm +ip-full +ubus +uci +bash
	URL:=https://easepi.linkease.com/
endef

define Package/$(PKG_NAME)/description
  Quickstart is a dashboard & user guide
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/quickstart
endef

define Build/Compile
	cd "$(PKG_BUILD_DIR)/backend" && \
		PATH="$(STAGING_DIR_HOSTPKG)/lib/go-$(GO_HOST_VERSION)/bin:$(PATH)" \
		GOOS=linux GOARCH=arm64 GOARM64=v8.0 CGO_ENABLED=0 GOENV=off GOTOOLCHAIN=local \
		GOCACHE="$(GO_BUILD_CACHE_DIR)" GOMODCACHE="$(GO_MOD_CACHE_DIR)" \
		"$(GO_HOST_BIN)" build -mod=mod -trimpath -buildvcs=false \
		-ldflags "-s -w -linkmode internal" \
		-o "$(PKG_BUILD_DIR)/quickstart" ./cmd/backend
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ -f /etc/uci-defaults/09-quickstart ]; then
		chmod 755 /etc/uci-defaults/09-quickstart
		/etc/uci-defaults/09-quickstart && rm -f /etc/uci-defaults/09-quickstart
	fi
	exit 0
fi
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/uci-defaults $(1)/etc/hotplug.d/block $(1)/etc/config $(1)/usr/libexec/quickstart
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/quickstart $(1)/usr/sbin/quickstart
	$(INSTALL_BIN) ./files/quickstart.init $(1)/etc/init.d/quickstart
	$(INSTALL_BIN) ./files/quickstart.uci-default $(1)/etc/uci-defaults/09-quickstart
	$(INSTALL_BIN) ./files/quickstart.hotplug $(1)/etc/hotplug.d/block/09-quickstart
	$(INSTALL_CONF) ./files/quickstart.config $(1)/etc/config/quickstart
	$(INSTALL_BIN) ./files/dhcpvalid.sh $(1)/usr/libexec/quickstart/dhcpvalid.sh
	$(INSTALL_BIN) ./files/startdhns.init $(1)/etc/init.d/startdhns
	$(LN) /usr/sbin/quickstart $(1)/usr/sbin/startdhns
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./files/startdhns.hotplug $(1)/etc/hotplug.d/iface/21-startdhns
	$(INSTALL_DIR) $(1)/usr/share/quickstart
	$(INSTALL_DATA) ./files/manuf $(1)/usr/share/quickstart/manuf
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
