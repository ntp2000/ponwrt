include $(TOPDIR)/rules.mk

LUCI_TITLE:=PON optics status
LUCI_DESCRIPTION:=LuCI PON optics status card for the overview page
LUCI_DEPENDS:=+airoha-ponctl +jsonfilter +luci-base +luci-mod-status
LUCI_PKGARCH:=all

PKG_VERSION:=0.2.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_URL:=https://github.com/pbs05/openwrt-pon-userspace

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage (luci.mk builds the package)
