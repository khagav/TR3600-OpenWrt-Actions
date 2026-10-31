-- 3600wrt: first-run setup wizard (menu entry)
module("luci.controller.tr3600setup", package.seeall)

function index()
	entry({"admin", "tr3600-setup"}, cbi("tr3600-setup"), _("設置向導"), 95).leaf = true
end
