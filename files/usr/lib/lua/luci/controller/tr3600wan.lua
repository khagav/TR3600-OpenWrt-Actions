-- 3600wrt: WAN interface selector (eth0 / eth1 / 4G tether) menu entry.
--
-- Backs onto /usr/sbin/tr3600-wan (see that script for the CLI + modes).
-- The page is a ucode view so the dropdown can run the tool via fs.exec and
-- refresh in place.

module("luci.controller.tr3600wan", package.seeall)

function index()
	entry({"admin", "network", "tr3600-wan"}, view("tr3600/wan"), _("WAN 选择"), 71).leaf = true
end
