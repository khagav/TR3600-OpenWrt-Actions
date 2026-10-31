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

		return this.showState().then(function(stateHtml) {
			var wanInput = E('input', { 'class': 'cbi-input-text', 'placeholder': 'aa:bb:cc:dd:ee:ff', 'style': 'width:180px', 'spellcheck': 'false' });
			var wifiInput = E('input', { 'class': 'cbi-input-text', 'placeholder': 'aa:bb:cc:dd:ee:ff', 'style': 'width:180px', 'spellcheck': 'false' });

			var btn = function(cls, label, fn) {
				return E('button', { 'class': 'btn cbi-button ' + cls, 'click': fn }, label);
			};

			return E('div', { 'class': 'cbi-section' }, [
				E('h3', _('当前 MAC 地址')),
				E('div', { 'id': 'tr3600-mac-state' }, [ stateHtml ]),

				E('h3', _('WAN 接口')),
				E('div', { 'class': 'cbi-section-node' }, [
					btn('cbi-button-action', _('随机 WAN MAC'), self.handler(self, 'wan', 'random')),
					btn('cbi-button-reset', _('重置 WAN MAC'), self.handler(self, 'wan', 'reset')),
					' ',
					wanInput,
					' ',
					btn('cbi-button-apply', _('设置 WAN MAC'), self.handlerSet(self, 'wan', wanInput))
				]),

				E('h3', _('Wi-Fi 接口')),
				E('div', { 'class': 'cbi-section-node' }, [
					btn('cbi-button-action', _('随机 Wi-Fi MAC'), self.handler(self, 'wifi', 'random')),
					btn('cbi-button-reset', _('重置 Wi-Fi MAC'), self.handler(self, 'wifi', 'reset')),
					' ',
					wifiInput,
					' ',
					btn('cbi-button-apply', _('设置 Wi-Fi MAC'), self.handlerSet(self, 'wifi', wifiInput))
				]),

				E('h3', _('全部接口')),
				E('div', { 'class': 'cbi-section-node' }, [
					btn('cbi-button-action', _('全部随机'), self.handler(self, 'all', 'random')),
					btn('cbi-button-reset', _('全部重置'), self.handler(self, 'all', 'reset'))
				])
			]);
		});
	},

	showState: function() {
		return fs.exec('/usr/sbin/tr3600-mac', ['show']).then(function(r) {
			var lines = (r.stdout || '').split('\n').filter(function(l) { return l.trim(); });
			if (!lines.length)
				return E('em', _('无法读取 MAC 信息（tr3600-mac 是否存在？）'));
			var rows = lines.map(function(l) {
				var i = l.indexOf(':');
				var label = i > 0 ? l.substring(0, i).trim() : l;
				var rest = i > 0 ? l.substring(i + 1).trim() : '';
				return E('tr', {}, [
					E('td', { 'class': 'td', 'style': 'width:200px' }, label),
					E('td', { 'class': 'td' }, rest)
				]);
			});
			return E('table', { 'class': 'table' }, rows);
		});
	},

	handler: function(self, scope, action) {
		return function(ev) {
			ev.preventDefault();
			return self.run(scope, action, null);
		};
	},

	handlerSet: function(self, scope, input) {
		return function(ev) {
			ev.preventDefault();
			var mac = (input.value || '').trim();
			if (!mac) {
				ui.addNotification(null, E('p', _('请输入 MAC 地址（aa:bb:cc:dd:ee:ff）')));
				return;
			}
			return self.run(scope, 'set', mac);
		};
	},

	run: function(scope, action, mac) {
		var self = this;
		var args = [scope, action];
		if (mac) args.push(mac);

		return fs.exec('/usr/sbin/tr3600-mac', args).then(function(r) {
			var msg = (r.stdout || r.stderr || '').trim() || _('已执行');
			ui.addNotification(null, E('p', msg));

			// refresh the state block in place
			return self.showState().then(function(newState) {
				var el = document.getElementById('tr3600-mac-state');
				if (el)
					el.replaceChildren(newState);
			});
		});
	}
});
