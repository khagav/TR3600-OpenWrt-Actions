'use strict';
'require view';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return Promise.resolve();
	},

	render: function() {
		var self = this;

		return self.getMode().then(function(cur) {
			var modeSel = E('select', { 'class': 'cbi-input-select', 'style': 'width:280px' }, [
				E('option', { 'value': 'eth0' }, _('eth0 — 2.5G 有线（默认）')),
				E('option', { 'value': 'eth1' }, _('eth1 — 千兆有线')),
				E('option', { 'value': 'tether' }, _('tether — 4G 蜂窝（主）'))
			]);
			modeSel.value = cur;

			var btn = function(cls, label, fn) {
				return E('button', { 'class': 'btn cbi-button ' + cls, 'click': fn }, label);
			};

			return E('div', { 'class': 'cbi-section' }, [
				E('h3', _('WAN 接口选择')),
				E('p', { 'class': 'cbi-section-descr' },
					_('选择 TR3600 的主 WAN 来源。eth0=2.5G 口，eth1=千兆口，tether=4G 蜂窝网卡。' +
					  '有线模式下另一个有线口自动作 LAN、4G 作备用；4G 模式下蜂窝为主、eth0 备用。' +
					  'Wi-Fi 不受影响。')),

				E('h3', _('当前状态')),
				E('div', { 'id': 'tr3600-wan-state' }, [ self.showState() ]),

				E('div', { 'class': 'cbi-section-node' }, [
					modeSel,
					' ',
					btn('cbi-button-apply', _('应用 WAN 选择'), self.apply(self, modeSel))
				])
			]);
		});
	},

	getMode: function() {
		return fs.exec('/usr/sbin/tr3600-wan', ['show']).then(function(r) {
			var m = /当前 WAN 模式\s*:\s*(\S+)/.exec(r.stdout || '');
			return m ? m[1] : 'eth0';
		});
	},

	showState: function() {
		return fs.exec('/usr/sbin/tr3600-wan', ['show']).then(function(r) {
			var lines = (r.stdout || '').split('\n').filter(function(l) { return l.trim(); });
			if (!lines.length)
				return E('em', _('无法读取 WAN 信息（tr3600-wan 是否存在？）'));

			var rows = lines.map(function(l) {
				var i = l.indexOf(':');
				var label = i > 0 ? l.substring(0, i).trim() : l;
				var rest = i > 0 ? l.substring(i + 1).trim() : '';
				return E('tr', {}, [
					E('td', { 'class': 'td', 'style': 'width:220px' }, label),
					E('td', { 'class': 'td' }, rest)
				]);
			});
			return E('table', { 'class': 'table' }, rows);
		});
	},

	apply: function(self, sel) {
		return function(ev) {
			ev.preventDefault();
			var mode = sel.value;

			return fs.exec('/usr/sbin/tr3600-wan', ['set', mode]).then(function(r) {
				var msg = (r.stdout || r.stderr || '').trim() || _('已应用');
				ui.addNotification(null, E('p', msg));

				// refresh the state block in place
				return self.showState().then(function(newState) {
					var el = document.getElementById('tr3600-wan-state');
					if (el)
						el.replaceChildren(newState);
				});
			}).catch(function(e) {
				ui.addNotification(null, E('p', _('执行失败：') + (e.message || e)));
			});
		};
	}
});
