// SPDX-License-Identifier: Apache-2.0
//
// NAT 类型选择页 —— 网络 → NAT 类型
//
// 菜单声明：root/usr/share/luci/menu.d/luci-app-natmode.json
//   "admin/network/natmode" → action.path "natmode/mode"
//   → 对应 resources/view/natmode/mode.js（本文件）
//
// 三档说明见 /usr/sbin/natmode-apply 顶部注释。
// 保存后通过 fs.exec 调用 natmode-apply apply 真正生效（ACL 已授权）。

'use strict';
'require view';
'require form';
'require fs';
'require ui';

function parseStatus(text) {
	var st = { mode: '?', effective: '?', fullcone: '0',
	           random_rules: '0', srcnat_chains: '0', offload: 'off',
	           fullcone6: '0', fullcone6_opt: '0',
	           fw_mode: 'restricted', module: '?', synced: '0', healed: '0' };
	(text || '').split('\n').forEach(function(line) {
		var kv = line.split('=');
		if (kv.length >= 2)
			st[kv[0].trim()] = kv.slice(1).join('=').trim();
	});
	return st;
}

function modeLabel(m) {
	switch (m) {
		case 'fullcone':   return _('全锥形NAT') + '（NAT1）';
		case 'restricted': return _('受限型NAT') + '（NAT3）';
		case 'symmetric':  return _('全对称型NAT') + '（NAT4）';
		default:           return m;
	}
}

// =========================================================
// 移动端 / 通用版式优化（真机 Argon 2.4.7 + PonWrt fork 实测定制）
//
// fork 的 CBIListValue.renderWidget → ui.Select(widget='radio') 的 DOM 是
// 扁平重复的  input.cbi-input-radio + label(for,空) + span(选项文字) + <br>；
// 主题只有 .cbi-input-radio{margin-top:.1rem}，没有任何布局规则，
// 而 .cbi-value{line-height:2.4rem} + .cbi-value-title{float:left;width:23rem}
// 在窄屏上直接把页面撕开（行距巨大、标题/描述两栏错位）。
//
// 不能整个换掉控件：fork 的 AbstractValue.formvalue 走
// getUIElement() → dom 绑定的 ui.Select / ui.Checkbox 类实例的
// getValue()/isChecked()。因此只重排框架 div 的子节点 + 注入页面级 CSS，
// 框架 div 的 id / 绑定实例原封不动，取值链路不受影响。
// =========================================================
function pageCss() {
	return [
		'.natmode-page{font-size:.9rem;line-height:1.6}',
		'.natmode-page .cbi-map-descr{line-height:1.6;padding:.1rem .2rem .5rem;opacity:.85}',
		// 选项外框：改为上下堆叠，掐掉 23rem 浮动标题列与 2.4rem 行距
		'.natmode-page .cbi-value{display:block;line-height:1.6;padding:.6rem .9rem}',
		'.natmode-page .cbi-value:nth-of-type(2n){background:transparent}',
		'.natmode-page .cbi-value-title{display:block;float:none;width:auto;text-align:left;padding:0 0 .3rem;font-weight:600;line-height:1.5}',
		'.natmode-page .cbi-value-field{display:block;width:auto}',
		'.natmode-page .cbi-value-description{display:block;padding:.45rem .1rem 0;line-height:1.55;opacity:.62}',
		// NAT 模式卡片式单选（js 后处理把 input/label/span 包进 .nat-opt）
		'.natmode-page .nat-opt{display:flex;align-items:flex-start;margin:.5rem 0;padding:.6rem .75rem;border:1px solid var(--lighter);border-radius:.55rem;background:var(--white);cursor:pointer}',
		'.natmode-page .nat-opt.checked{border-color:var(--primary);box-shadow:inset 0 0 0 1px var(--primary)}',
		'.natmode-page .nat-opt input[type="radio"]{flex:0 0 auto;width:1.1rem;height:1.1rem;margin:.18rem .6rem 0 0}',
		'.natmode-page .nat-opt input[type="radio"]+label{margin:0}',
		'.natmode-page .nat-opt span{flex:1 1 auto;display:block;min-width:0}',
		'.natmode-page .nat-choice strong{display:block;font-weight:600;line-height:1.5}',
		'.natmode-page .nat-choice .nat-choice-desc{display:block;font-size:.78rem;opacity:.6;line-height:1.55;margin-top:.1rem}',
		// Flag：标题移进开关行，整行可点
		'.natmode-page .cbi-checkbox.nat-check{display:flex;align-items:center;margin:.2rem 0;padding:.55rem .75rem;border:1px solid var(--lighter);border-radius:.55rem;background:var(--white);cursor:pointer}',
		'.natmode-page .nat-check-title{flex:1 1 auto;font-weight:500;line-height:1.5}',
		'.natmode-page .nat-check input[type="checkbox"]{flex:0 0 auto;width:1.15rem !important;height:1.15rem !important;margin:0 0 0 .6rem}',
		// 状态表：完全保持主题默认渲染（用户指定不动），不再注入任何规则
		// 应用按钮：通栏大按钮，手机好点
		'.natmode-page .cbi-page-actions{padding:.4rem 0 0}',
		'.natmode-page .cbi-page-actions .cbi-button{width:100%;padding:.75rem 1rem;font-size:1rem;border-radius:.55rem}'
	].join('\n');
}

// 单选选项富文本：加粗标题 + 小字描述（fork 的 value() 支持 DOM 元素，
// 最终被塞进 span.nat-choice 里）
function radioChoice(title, desc) {
	return E('span', { 'class': 'nat-choice' }, [
		E('strong', {}, title),
		E('span', { 'class': 'nat-choice-desc' }, desc)
	]);
}

// 渲染后处理：卡片化单选 + Flag 标题内联。只动框架 div 的子节点，
// 不碰框架 div 本身（formvalue 依赖其上的控件类实例绑定）。
function beautifyPage(root) {
	// --- 1. NAT 模式单选卡片化 ---
	var frame = root.querySelector('[id="cbid.natmode.main.mode"]');
	if (frame) {
		var brs = frame.querySelectorAll(':scope > br');
		Array.prototype.forEach.call(brs, function(br) { br.parentNode.removeChild(br); });

		var inputs = frame.querySelectorAll(':scope > input[type="radio"]');
		Array.prototype.forEach.call(inputs, function(input) {
			var label = input.nextElementSibling;       // fork 生成的空 label(for)
			var span = label ? label.nextElementSibling : null;  // 选项文字
			var card = E('div', { 'class': 'nat-opt' + (input.checked ? ' checked' : '') });
			frame.insertBefore(card, input);
			card.appendChild(input);
			if (label) card.appendChild(label);
			if (span) card.appendChild(span);
			// 点击卡片任意处即选中（input/label 自带浏览器原生行为，跳过防重复）
			card.addEventListener('click', function(ev) {
				if (ev.target === input || ev.target.tagName === 'LABEL') return;
				if (!input.checked) input.click();
			});
		});

		frame.addEventListener('change', function() {
			var cards = frame.querySelectorAll('.nat-opt');
			Array.prototype.forEach.call(cards, function(c) {
				var i = c.querySelector('input[type="radio"]');
				c.classList.toggle('checked', !!(i && i.checked));
			});
		});
	}

	// --- 2. Flag：标题并入开关行，整行可点 ---
	[ 'cbid.natmode.main.fullcone6', 'cbid.natmode.main.auto_offload' ]
		.forEach(function(cbid) {
			var cb = root.querySelector('[id="' + cbid + '"]');
			if (!cb || !cb.classList.contains('cbi-checkbox'))
				return;
			var optDiv = cb.closest('.cbi-value');
			var title = optDiv ? optDiv.querySelector('.cbi-value-title') : null;
			if (title) {
				cb.insertBefore(E('strong', { 'class': 'nat-check-title' },
					[ title.textContent ]), cb.firstChild);
				title.style.display = 'none';
			}
			cb.classList.add('nat-check');
			cb.addEventListener('click', function(ev) {
				var input = cb.querySelector('input[type="checkbox"]');
				// input 自带原生行为；label(for) 也会触发浏览器转发，跳过防双重切换
				if (!input || ev.target === input || ev.target.tagName === 'LABEL')
					return;
				input.click();
			});
		});
}

function offloadLabel(v) {
	switch (v) {
		case 'hw':  return _('硬件卸载');
		case 'sw':  return _('软件卸载');
		default:    return _('关闭');
	}
}

// 防火墙页（网络 → 防火墙 → 常规设置）此刻的显示状态。
// 那个「启用 FullCone NAT」复选框读的就是 firewall.@defaults[0].fullcone，
// 与本插件同一个 UCI 键 —— 所以本页改动后防火墙页会同步反映。
//
// 但要注意：防火墙页只能表达「开 / 关 fullcone」两种状态，
// 无法表达 NAT4（随机端口）。故 NAT4 与「受限型」在防火墙页看起来一样
// （都是未勾选），真正的差异只在本页的「随机端口规则」上。
function fwPageLabel(st) {
	if (st.fw_mode === 'fullcone')
		return _('已勾选「启用 FullCone NAT」');
	if (st.effective === 'symmetric')
		return _('未勾选（防火墙页无法表达 NAT4，随机端口仅本页可见）');
	return _('未勾选「启用 FullCone NAT」');
}

function renderStatus(st) {
	var rows = [
		_('当前模式'),        modeLabel(st.effective),
		_('FullCone 开关'),   (st.fullcone === '1' ? _('已启用') : _('已关闭')),
		_('IPv6 FullCone'),   (st.fullcone6 === '1' ? _('已启用') : _('已关闭'))
			+ (st.effective === 'fullcone' ? '' : _('（仅全锥形时生效）')),
		_('防火墙页对应状态'), fwPageLabel(st),
		_('随机端口规则'),    (st.random_rules !== '0'
			? _('已注入 ') + st.random_rules + _(' 条') : _('无')),
		_('srcnat 链'),       st.srcnat_chains + _(' 个'),
		_('路由/NAT 卸载'),   offloadLabel(st.offload),
		_('fullcone 内核模块'), (st.module === 'loaded' ? _('已加载') : _('未加载'))
	];

	var notice = [];  // 蓝色提示
	var warn = [];    // 黄色警告

	// 反向同步提示：natmode-apply status 发现 firewall 侧被改过时，
	// 会把实际生效的模式写回 natmode.main.mode（synced=1）。
	if (st.synced === '1')
		notice.push(E('p', {}, _('已与防火墙同步：检测到你在「网络 → 防火墙 → 常规设置」'
			+ '改动过 FullCone 开关，本页已按实际生效状态更新为 ')
			+ modeLabel(st.effective) + _('。')));

	// 自愈提示：NAT4 的 nft 规则被 fw4 reload 冲掉后，status 会自动补回
	if (st.healed === '1')
		notice.push(E('p', {}, _('已自动修复：NAT4 的随机端口规则此前被防火墙重载清除，现已重新注入。')));

	// 残留随机端口规则：非 NAT4 模式却存在规则，实际行为不干净
	if (st.effective !== 'symmetric' && st.random_rules !== '0')
		warn.push(E('p', {}, _('检测到残留的随机端口规则 ')
			+ st.random_rules + _(' 条，但当前不是全对称型NAT（NAT4）。'
			+ '这会让实际 NAT 行为既不是干净的 NAT3 也不是 NAT4。'
			+ '下次打开本页或执行 natmode-apply status 会自动清理。')));

	if (st.module !== 'loaded' && st.effective === 'fullcone')
		warn.push(E('p', {}, _('未检测到 nft_fullcone 模块，全锥形可能不生效。')));

	// NAT4 与卸载互斥 —— 这是「NAT4 设置了却不生效」最常见的原因
	if (st.effective === 'symmetric' && st.offload !== 'off')
		warn.push(E('p', {}, _('NAT4 与路由/NAT 卸载互斥：卸载流量绕过 conntrack，'
			+ '随机端口规则不参与转发，实测仍是 NAT3。'
			+ '请关闭卸载，或勾选下方「应用 NAT4 时自动关闭卸载」后重新保存。')));
	else if (st.effective === 'fullcone' && st.offload !== 'off')
		warn.push(E('p', {}, _('已开启路由/NAT 卸载，卸载流量绕过 conntrack，'
			+ '可能使全锥形行为不稳定。测 NAT 类型时建议临时关闭卸载。')));

	if (st.effective === 'symmetric' && st.srcnat_chains === '0')
		warn.push(E('p', {}, _('未找到 fw4 的 srcnat_<zone> 链：'
			+ 'WAN 区域可能未启用 MASQUERADE，随机端口规则无处可插。')));

	var table = E('table', { 'class': 'table' });
	for (var i = 0; i < rows.length; i += 2) {
		table.appendChild(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td left', 'width': '33%' }, [ rows[i] ]),
			E('td', { 'class': 'td left' }, [ rows[i + 1] || '?' ])
		]));
	}

	var children = [ E('h3', _('当前状态')), table ];
	notice.forEach(function(w) {
		children.push(E('div', { 'class': 'alert-message notice' }, [ w ]));
	});
	warn.forEach(function(w) {
		children.push(E('div', { 'class': 'alert-message warning' }, [ w ]));
	});

	return E('div', { 'class': 'cbi-section' }, children);
}

return view.extend({
	load: function() {
		return L.resolveDefault(fs.exec_direct('/usr/sbin/natmode-apply', ['status']), '');
	},

	render: function(statusText) {
		var st = parseStatus(statusText);

		// =========================================================
		// 必须用 form.Map，不能用 form.JSONMap！
		//
		// form.js 中 CBIJSONMap 的实现：
		//   __init__(data, ...) { this.config='json';
		//                        this.data = new CBIJSONConfig(data); }
		// 它把第一个参数当作「JSON 数据对象」而非文件名，
		// 且 parsechain=['json'] —— 用于 JSON 配置文件（如 luci 的
		// 某些 js 配置），不是 UCI。
		// /etc/config/natmode 是标准 UCI 文件，必须用 form.Map，
		// 否则解析失败、保存也写不回去。
		// =========================================================
		var m = new form.Map('natmode', _('NAT 类型'),
			_('选择路由器对内网出向连接的 NAT 行为。数字越小越宽松，P2P / 游戏 / PT 体验越好。')
			+ _('改动后请点击下方「应用 NAT 模式」按钮立即生效。'));

		var s = m.section(form.NamedSection, 'main', 'natmode');
		s.anonymous = false;

		// =========================================================
		// 必须用 form.ListValue + widget='radio'，不能用 form.RadioValue！
		//
		// luci-base 的 form.js 里根本没有 RadioValue 这个类：
		//   可选类只有 Value / DynamicList / ListValue / RichListValue /
		//   RangeSliderValue / Flag / MultiValue / TextValue / DummyValue /
		//   Button / HiddenValue / FileUpload / DirectoryPicker / SectionValue
		// 传 undefined 进去，AbstractSection.option() 做
		//   L.Class.isSubclass(...) 检查失败 → 抛
		//   TypeError: Class must be a descendant of CBIAbstractValue
		//
		// ListValue 支持 widget='select'（默认）或 'radio'，
		// 配合 orientation='vertical' 就是竖排单选按钮。
		// =========================================================
		var o = s.option(form.ListValue, 'mode', _('NAT 类型'));
		o.widget = 'radio';
		o.orientation = 'vertical';
		// 选项用富文本（fork 的 value() 接受 DOM 节点）：
		// 标题加粗单独一行，长描述变成小字第二行 —— 手机上不再挤成一坨
		o.value('fullcone', radioChoice(
			_('全锥形NAT') + '（NAT1）',
			_('最宽松，端点无关映射 + 端点无关过滤。游戏联机、PT 做种、PCDN 最优。')));
		o.value('restricted', radioChoice(
			_('受限型NAT') + '（NAT3）',
			_('系统默认。端点无关映射 + 地址端口相关过滤，日常上网无影响。')));
		o.value('symmetric', radioChoice(
			_('全对称型NAT') + '（NAT4）',
			_('端口完全随机，映射不可预测，打洞基本不可用。仅用于特殊合规场景。')));
		o.default = 'fullcone';

		// IPv6 FullCone 独立开关，默认【不勾选】。
		//
		// form.Flag 对应 UCI 里的 '0'/'1'；未设置时回落到 default。
		// 默认值必须是字符串 '0'，不能是数字 0 ——
		// form.js 的 Flag 用 === '1' 判定，数字会落到 false 分支但
		// 写入时可能出现类型不一致，统一用字符串最稳。
		var o6 = s.option(form.Flag, 'fullcone6',
			_('同时开启 IPv6 FullCone NAT（fullcone6）'),
			_('对应 firewall.@defaults[0].fullcone6。'
			+ 'IPv6 通常有公网前缀、不做 NAT，收益有限；'
			+ '少数环境下反而会导致 IPv6 连接异常，故默认关闭。'
			+ '仅在选择「全锥形NAT（NAT1）」时生效，其余模式下该键会被删除。'));
		o6.default = '0';

		var oc = s.option(form.Flag, 'auto_offload',
			_('应用 NAT4 时自动关闭路由/NAT 卸载'),
			_('NAT4 的随机端口依赖 nft masquerade，而卸载（尤其硬件卸载走 PPE）'
			+ '会把流量绕过 conntrack 直接转发 —— 两者互斥，开着卸载 NAT4 实测仍是 NAT3。'
			+ '勾选后，选择「全对称型NAT」时会自动关闭卸载（代价：吞吐下降）。'));
		oc.default = '1';

		// =========================================================
		// 应用逻辑 —— 三条路径全覆盖（真机踩坑定案，勿删注释）：
		//
		// 核心事实：这个 LuCI 分支（PonWrt fork）的 form.js 根本没有
		// 「保存并应用」按钮（全文无 handleSaveApply / cbi-button-apply），
		// 地图页脚只有「保存」和「复位」。用户点「保存」只会把 UCI 改动
		// 暂存/提交，natmode-apply 从头到尾不会被执行；随后 do_sync 按
		// firewall 里的旧 fullcone 状态反向同步，把模式改回去 ——
		// 这才是「怎么点都不生效」的最终根因（真机浏览器实测确认）。
		//
		// 因此：
		//   1) 页面自带醒目的「应用 NAT 模式」按钮（主路径），
		//      直接读表单点选值，显式传参调 natmode-apply —— 脚本是
		//      唯一权威写入方（写 UCI + firewall，幂等），不依赖任何
		//      表单/uci 提交时序。
		//   2) 钩住 ui.changes.apply：覆盖「保存后点全局未保存更改条的
		//      保存并应用」的路径 —— 先跑脚本再放行原 apply，避免
		//      firewall reload 回调 do_sync 时两边不一致而打架。
		//      （标准 LuCI 的地图「保存并应用」按钮最终也走
		//      ui.changes.apply，同样被此钩子覆盖。）
		// =========================================================
		function readSelection() {
			return {
				mode: o.formvalue('main') || 'fullcone',
				fc6:  o6.formvalue('main') || '0',
				off:  oc.formvalue('main') || '1'
			};
		}

		function runApply(sel) {
			return fs.exec('/usr/sbin/natmode-apply',
				['apply', sel.mode, sel.fc6, sel.off])
				.then(function(res) {
					if (res && typeof res.code === 'number' && res.code !== 0)
						throw new Error((res.stderr || res.stdout ||
							'natmode-apply 退出码 ' + res.code).trim());
				});
		}

		// 兜底钩子：任何 ui.changes.apply（全局红条 / 标准 LuCI 的保存并应用）
		// 之前，先把当前点选的模式落地，保证 firewall 与 natmode 一致
		var origApply = (ui.changes && typeof ui.changes.apply === 'function')
			? ui.changes.apply : null;

		if (origApply && !ui.changes.__natmodeHooked) {
			ui.changes.__natmodeHooked = true;
			ui.changes.apply = function() {
				var args = arguments;
				var sel = readSelection();
				return runApply(sel)
					.catch(function(e) {
						ui.addNotification(null,
							E('p', _('应用 NAT 模式失败：')
								+ (e && e.message ? e.message : e)), 'error');
					})
					.then(function() {
						return origApply.apply(ui.changes, args);
					});
			};
		}

		// 主路径按钮：放在表单下方，点了立即生效。
		// 已自行跑过 runApply，所以这里直接用未挂钩的原始 apply 提交
		// 暂存改动（若有），避免脚本重复执行两遍。
		var applyBtn = E('button', {
			'class': 'cbi-button cbi-button-apply important',
			'click': ui.createHandlerFn(m, function(ev) {
				var sel = readSelection();
				return runApply(sel)
					.then(function() {
						if (origApply)
							return origApply.call(ui.changes);
						return null;
					})
					.then(function() {
						ui.addNotification(null,
							E('p', _('NAT 模式已应用，防火墙已重载。')), 'success');
						window.setTimeout(function() {
							window.location.reload();
						}, 1500);
					})
					.catch(function(e) {
						ui.addNotification(null,
							E('p', _('应用失败：')
								+ (e && e.message ? e.message : e)), 'error');
					});
			})
		}, _('应用 NAT 模式'));

		// =========================================================
		// m.render() 返回的是 Promise，不是 DOM 节点！
		//
		// form.js: CBIMap.prototype.render()
		//   render() { return this.load().then(this.renderContents.bind(this)); }
		// 而 renderContents() → renderChildren().then(nodes => ...)
		//
		// 若直接 E('div', {}, [ 状态块, m.render() ])，Promise 不会被 E()
		// 解析，页面上就显示 "[object Promise]" —— 表单（单选按钮）
		// 根本没渲染出来，于是无法更改 NAT 类型。
		//
		// 正确做法：等 Promise resolve 拿到节点数组，再组装。
		// =========================================================
		return m.render().then(function(nodes) {
			var kids = [ E('style', { 'type': 'text/css' }, [ pageCss() ]), renderStatus(st) ];
			if (Array.isArray(nodes))
				kids = kids.concat(nodes);
			else if (nodes != null)
				kids.push(nodes);
			kids.push(E('div', { 'class': 'cbi-page-actions' }, [ applyBtn ]));
			var root = E('div', { 'class': 'natmode-page' }, kids);
			// 表格/单选/开关的移动端卡片化（在 DOM 就绪后做后处理）
			beautifyPage(root);
			return root;
		});
	}
});
