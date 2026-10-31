-- 3600wrt: MAC tool (WAN / Wi-Fi MAC random, set, reset) menu entry.
--
-- Backs onto /usr/sbin/tr3600-mac (see that script for the CLI).  The page
-- itself is a ucode view so the buttons can run the tool via fs.exec and
-- refresh in place.

module("luci.controller.tr3600mac", package.seeall)

function index()
	entry({"admin", "network", "tr3600-mac"}, view("tr3600/mac"), _("MAC 工具"), 70).leaf = true
end
