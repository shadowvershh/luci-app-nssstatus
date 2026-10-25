include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-nssstatus
PKG_VERSION:=1.1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-nssstatus
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=NSS hardware acceleration status page
  DEPENDS:=+luci-base +luci-compat
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/luci-app-nssstatus/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/nssstatus.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/nssstatus
	$(INSTALL_DATA) ./luasrc/view/nssstatus/status.htm $(1)/usr/lib/lua/luci/view/nssstatus/
endef

$(eval $(call BuildPackage,luci-app-nssstatus))
