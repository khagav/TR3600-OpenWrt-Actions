-- 3600wrt: first-run setup wizard (menu entry).
--
-- The wizard is only useful before the device is configured.  Once
-- setup.done=1 the CBI model redirects every hit to the overview page, so
-- the menu entry is pure noise.  Hide it here (keep the controller + CBI so a
-- factory reset can bring the wizard back), instead of registering a menu
-- entry that just bounces the user to the status page.

module("luci.controller.tr3600setup", package.seeall)

function index()
	-- If the device is already configured, do not register the menu entry at
	-- all.  A factory reset clears setup.done (or it is nil on a brand-new
	-- box), so the wizard reappears only when it is genuinely useful.
	local uci = require "luci.model.uci".cursor()
	if uci:get("tr3600", "setup", "done") == "1" then
		return
	end
	entry({"admin", "tr3600-setup"}, cbi("tr3600-setup"), _("設置向導"), 95).leaf = true
end
