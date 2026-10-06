module("luci.controller.wizard", package.seeall)

local uci = luci.model.uci.cursor()
local http = require "luci.http"
local fs = require "nixio.fs"

local function hide_home_menu()
	local landing_page = uci:get("wizard", "default", "landing_page")

	if luci.sys.call("pgrep routergo >/dev/null") == 0 and landing_page == "routerdog" then
		return false
	end

	if not fs.access("/usr/sbin/quickstart") then
		return false
	end

	return landing_page ~= "nas"
		and landing_page ~= "next-nas"
		and landing_page ~= "router"
end

function index()
	local page = entry({"admin", "index"}, call("landing_page"))
	page.dependent = false
	if not hide_home_menu() then
		page.title = _("Home")
		page.order = 1
	end
end

function landing_page()
	local landing_page = uci:get("wizard", "default", "landing_page")
	if (luci.sys.call("pgrep routergo >/dev/null") == 0 and landing_page == "routerdog") then
		http.redirect(luci.dispatcher.build_url("admin","routerdog"));
	elseif fs.access("/usr/sbin/quickstart") then
		if landing_page == "nas" then
			http.redirect(luci.dispatcher.build_url("admin","istorex","nas"));
		elseif landing_page == "next-nas" then
			http.redirect(luci.dispatcher.build_url("admin","istorex","next-nas"));
		elseif landing_page == "router" then
			http.redirect(luci.dispatcher.build_url("admin","istorex","router"));
		else
			http.redirect(luci.dispatcher.build_url("admin","quickstart"));
		end
	else
		http.redirect(luci.dispatcher.build_url("admin","status"))
	end
		
end
