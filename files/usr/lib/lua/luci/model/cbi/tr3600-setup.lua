-- 3600wrt: first-run setup wizard.
--
-- Sets the root password and the Wi-Fi credentials, then clears
-- /etc/tr3600-setup-pending so nginx stops redirecting "/" here.
--
-- SECURITY: neither the admin password nor the Wi-Fi key is ever written to
-- /etc/config/tr3600.  Every sensitive field is a CBI write no-op; the values
-- are read straight from the submitted form inside on_after_commit.  After a
-- successful commit the whole "setup" section is pruned down to done=1, so
-- nothing (password, password2, ssid, key) survives on disk.  A stale wizard
-- tab that re-submits after done=1 is bounced to the overview page.

local sys  = require "luci.sys"
local uci  = require "luci.model.uci".cursor()
local disp = require "luci.dispatcher"

local m, s, o

-- make sure the section exists even on an upgraded system
if uci:get("tr3600", "setup", "done") == nil then
	uci:set("tr3600", "setup", "setup")
	uci:set("tr3600", "setup", "done", "0")
	uci:commit("tr3600")
end

-- Already configured: send the user away.  This also stops an old, still-open
-- wizard tab from re-submitting and overwriting the admin password.  CBI will
-- still try to render whatever we return, so hand back an empty map - the 302
-- goes out first and the body is irrelevant.
if uci:get("tr3600", "setup", "done") == "1" then
	luci.http.redirect(disp.build_url("admin/status/overview"))
	m = Map("tr3600")
	m.title = translate("設置向導")
	m.message = translate("設置已完成，正在跳轉…")
	return m
end

m = Map("tr3600", translate("設置向導"),
	translate("首次使用請完成以下設置。管理員密碼與 Wi-Fi 會立即生效，完成後本頁不再自動彈出。"))

-- current Wi-Fi values, used as defaults
local cur_ssid, cur_key
uci:foreach("wireless", "wifi-iface", function(sec)
	if not cur_ssid and sec.mode == "ap" then
		cur_ssid = sec.ssid
		cur_key  = sec.key
	end
end)

local err = luci.http.formvalue("err")
if err == "pw" then
	m.message = translate("管理員密碼至少 8 位，請重新輸入。")
elseif err == "pw2" then
	m.message = translate("兩次輸入的管理員密碼不一致。")
elseif err == "ssid" then
	m.message = translate("Wi-Fi 名稱不能為空（最多 32 個字元）。")
elseif err == "key" then
	m.message = translate("Wi-Fi 密碼至少 8 位。")
end

s = m:section(NamedSection, "setup", "setup", translate("管理員與 Wi-Fi"))
s.anonymous = true
s.addremove = false

-- NOTE: every option below is a write no-op.  The real values are read from
-- luci.http.formvalue() in on_after_commit, so they are never persisted under
-- tr3600.setup.  The datatype/rmempty validation still runs before write.

o = s:option(Value, "password", translate("管理員密碼"),
	translate("用於 LuCI 與 SSH（root）。至少 8 位。"))
o.password = true
o.rmempty = false
o.datatype = "minlength(8)"
o.write = function() end

o = s:option(Value, "password2", translate("確認密碼"))
o.password = true
o.rmempty = false
o.datatype = "minlength(8)"
o.write = function() end

o = s:option(Value, "ssid", translate("Wi-Fi 名稱 (SSID)"),
	translate("2.4G / 5G 使用同一個名稱。"))
o.default = cur_ssid or "wrt"
o.rmempty = false
o.datatype = "maxlength(32)"
o.write = function() end

o = s:option(Value, "key", translate("Wi-Fi 密碼"),
	translate("WPA2-PSK，至少 8 位。"))
o.password = true
o.default = cur_key or ""
o.rmempty = false
o.datatype = "minlength(8)"
o.write = function() end

function m.on_after_commit(self)
	local cb  = "cbid.tr3600.setup."
	local pw   = luci.http.formvalue(cb .. "password")
	local pw2  = luci.http.formvalue(cb .. "password2")
	local ssid = luci.http.formvalue(cb .. "ssid")
	local key  = luci.http.formvalue(cb .. "key")

	local function fail(code)
		luci.http.redirect(disp.build_url("admin/tr3600-setup") .. "?err=" .. code)
	end

	if not pw or #pw < 8 then return fail("pw") end
	if pw ~= pw2 then return fail("pw2") end
	if not ssid or ssid == "" then return fail("ssid") end
	if not key or #key < 8 then return fail("key") end

	-- 1. admin password (LuCI + SSH)
	sys.user.setpasswd("root", pw)

	-- 2. Wi-Fi on every AP interface, same SSID on all bands
	local w = require("luci.model.uci").cursor()
	w:foreach("wireless", "wifi-iface", function(sec)
		if sec.mode == "ap" then
			local enc = (sec.encryption == "sae") and "sae" or "psk2"
			w:set("wireless", sec[".name"], "ssid", ssid)
			w:set("wireless", sec[".name"], "encryption", enc)
			w:set("wireless", sec[".name"], "key", key)
			w:set("wireless", sec[".name"], "disabled", "0")
		end
	end)
	w:foreach("wireless", "wifi-device", function(sec)
		w:set("wireless", sec[".name"], "disabled", "0")
	end)
	w:commit("wireless")

	-- 3. mark done, prune the section down to done=1, stop the redirect.
	w:set("tr3600", "setup", "done", "1")
	local sec = w:get("tr3600", "setup")
	if type(sec) == "table" then
		for k in pairs(sec) do
			if k ~= "done" then
				w:delete("tr3600", "setup", k)
			end
		end
	end
	w:commit("tr3600")

	os.remove("/etc/tr3600-setup-pending")
	-- uhttpd base: point "/" back at LuCI (the uci-defaults had set it to the
	-- wizard while pending).  nginx base (Kwrt) ignores this and uses its
	-- conf.d redirect, so the write is harmless there too.
	local fh = io.open("/www/index.html", "w")
	if fh then
		fh:write('<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0; url=/cgi-bin/luci/"></head><body></body></html>\n')
		fh:close()
	end
	sys.call("wifi reload >/dev/null 2>&1")

	luci.http.redirect(disp.build_url("admin/status/overview"))
end

return m
