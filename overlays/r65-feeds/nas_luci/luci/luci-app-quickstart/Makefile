# Copyright (C) 2016 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for quickstart 
LUCI_DEPENDS:=+quickstart +luci-app-store
LUCI_PKGARCH:=all

QUICKSTART_SOURCE_VERSION:=880aeecbb7612799a49073e210d15cc9825e633e
PKG_SOURCE:=quickstart-$(QUICKSTART_SOURCE_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/istoreos/quickstart/tar.gz/$(QUICKSTART_SOURCE_VERSION)?
PKG_HASH:=5c550eb3e5b0282f9f58850e5659605e0fc2345f8c6ba3462ae3db0f5069c6b5
PKG_BUILD_DEPENDS:=node/host
# luci.mk performs its BuildPackage evaluation while it is included below.
# Keep its standard build directory and use its package hooks for the source build.
PKG_UNPACK:=true

define Build/Prepare/luci-app-quickstart
	$(TAR) -C "$(PKG_BUILD_DIR)" --strip-components=1 -xzf "$(DL_DIR)/$(PKG_SOURCE)"
	test -f "$(PKG_BUILD_DIR)/web/package-lock.json" || { echo "ERROR: QuickStart source archive is missing web/package-lock.json" >&2; exit 1; }
endef

NODE_HOST_BIN:=$(STAGING_DIR_HOSTPKG)/bin/node
ZIP_HOST_BIN:=$(STAGING_DIR_HOST)/bin/zip
define QuickStart/Build
	@test -x "$(NODE_HOST_BIN)" || { echo "ERROR: QuickStart source build requires node/host in $(NODE_HOST_BIN)" >&2; exit 1; }; \
	test -x "$(ZIP_HOST_BIN)" || { echo "ERROR: QuickStart source build requires tools/zip in $(ZIP_HOST_BIN)" >&2; exit 1; }; \
	export PATH="$(STAGING_DIR_HOST)/bin:$(STAGING_DIR_HOSTPKG)/bin:/usr/bin:/bin:$$PATH"; \
	command -v npm >/dev/null 2>&1 || { echo "ERROR: QuickStart source build requires host npm" >&2; exit 1; }; \
	command -v zip >/dev/null 2>&1 || { echo "ERROR: QuickStart source build requires staged host zip" >&2; exit 1; }; \
	cd "$(PKG_BUILD_DIR)/web" && \
	npm ci --ignore-scripts --no-audit --no-fund --prefer-offline && \
	npm run build
	$(INSTALL_DIR) "$(PKG_BUILD_DIR)/htdocs/luci-static"
	rm -rf "$(PKG_BUILD_DIR)/htdocs/luci-static/quickstart"
	$(CP) "$(PKG_BUILD_DIR)/web/dist/luci-static/quickstart" "$(PKG_BUILD_DIR)/htdocs/luci-static/"
endef
Hooks/Compile/Pre += QuickStart/Build

PKG_VERSION:=0.12.10-r5
# PKG_RELEASE MUST be empty for luci.mk
PKG_RELEASE:=

LUCI_MINIFY_CSS:=0
LUCI_MINIFY_JS:=0

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - Openwrt buildroot signature

