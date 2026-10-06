include $(TOPDIR)/rules.mk

LUCI_TITLE:=NAT mode selector
LUCI_DESCRIPTION:=LuCI NAT mode selector (Full Cone / Restricted / Symmetric)
LUCI_DEPENDS:=+firewall4 +kmod-nft-fullcone +luci-base
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.3
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKG_URL:=https://github.com/pbs05/ponwrt

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage (luci.mk builds the package)
