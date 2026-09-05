/*
 * Kazoo ACDC Call Center for Monster UI
 * SPDX-License-Identifier: MPL-2.0
 */
define(function(require) {
	var $ = require('jquery'),
		_ = require('lodash'),
		monster = require('monster');

	var app = {
		name: 'acdc',
		callStatsWindowSeconds: 24 * 60 * 60,
		kazooEpochOffsetSeconds: 62167219200,
		managedRouteFlag: 'talkchief-acdc-managed',
		managedRouteQueueFlagPrefix: 'talkchief-acdc-queue:',

		css: ['app'],

		i18n: {
			'en-US': { customCss: false }
		},

		appFlags: {
			acdc: {
				container: null,
				currentTab: 'dashboard',
				requestGeneration: 0
			}
		},

		requests: {
			'acdc.media.list': { url: 'accounts/{accountId}/media?paginate=false', verb: 'GET', generateError: false },
			'acdc.media.system': { url: 'media?paginate=false', verb: 'GET', generateError: false },
			'acdc.media.prompt': { url: 'media/prompts/{promptId}?paginate=false', verb: 'GET', generateError: false },
			'acdc.numbers.list': { url: 'accounts/{accountId}/phone_numbers?paginate=false', verb: 'GET', generateError: false },
			'acdc.queues.list': {
				url: 'accounts/{accountId}/queues?paginate=false',
				verb: 'GET',
				generateError: false
			},
			'acdc.queues.create': {
				url: 'accounts/{accountId}/queues',
				verb: 'PUT',
				generateError: false
			},
			'acdc.queues.get': {
				url: 'accounts/{accountId}/queues/{queueId}',
				verb: 'GET',
				generateError: false
			},
			'acdc.queues.update': {
				url: 'accounts/{accountId}/queues/{queueId}',
				verb: 'PATCH',
				generateError: false
			},
			'acdc.queues.delete': {
				url: 'accounts/{accountId}/queues/{queueId}',
				verb: 'DELETE',
				generateError: false
			},
			'acdc.queues.roster': {
				url: 'accounts/{accountId}/queues/{queueId}/roster?paginate=false',
				verb: 'GET',
				generateError: false
			},
			'acdc.queues.updateRoster': {
				url: 'accounts/{accountId}/queues/{queueId}/roster?paginate=false',
				verb: 'POST',
				generateError: false
			},
			'acdc.queues.stats': {
				url: 'accounts/{accountId}/queues/stats',
				verb: 'GET',
				generateError: false
			},
			'acdc.callbacks.list': {
				url: 'accounts/{accountId}/queues/{queueId}/callbacks?page_size={pageSize}&cursor={cursor}',
				verb: 'GET',
				generateError: false
			},
			'acdc.callbacks.cancel': {
				url: 'accounts/{accountId}/queues/{queueId}/callbacks/{callbackId}',
				verb: 'DELETE',
				generateError: false
			},
			'acdc.agents.list': {
				url: 'accounts/{accountId}/agents?paginate=false',
				verb: 'GET',
				generateError: false
			},
			'acdc.agents.statuses': {
				url: 'accounts/{accountId}/agents/status',
				verb: 'GET',
				generateError: false
			},
			'acdc.agents.stats': {
				url: 'accounts/{accountId}/agents/stats',
				verb: 'GET',
				generateError: false
			},
			'acdc.agents.setStatus': {
				url: 'accounts/{accountId}/agents/{agentId}/status',
				verb: 'POST',
				generateError: false
			},
			'acdc.users.list': {
				url: 'accounts/{accountId}/users?paginate=false',
				verb: 'GET',
				generateError: false
			},
			'acdc.callStats.list': {
				url: 'accounts/{accountId}/acdc_call_stats?page_size=20&created_from={createdFrom}&created_to={createdTo}',
				verb: 'GET',
				generateError: false
			},
			'acdc.callflows.list': {
				url: 'accounts/{accountId}/callflows?paginate=false',
				verb: 'GET',
				generateError: false
			},
			'acdc.callflows.get': {
				url: 'accounts/{accountId}/callflows/{callflowId}',
				verb: 'GET',
				generateError: false
			},
			'acdc.callflows.create': {
				url: 'accounts/{accountId}/callflows',
				verb: 'PUT',
				generateError: false
			},
			'acdc.callflows.update': {
				url: 'accounts/{accountId}/callflows/{callflowId}',
				verb: 'PATCH',
				generateError: false
			},
			'acdc.callflows.delete': {
				url: 'accounts/{accountId}/callflows/{callflowId}',
				verb: 'DELETE',
				generateError: false
			}
		},

		subscribe: {},

		load: function(callback) {
			var self = this;

			monster.pub('auth.initApp', {
				app: self,
				callback: function() {
					callback && callback(self);
				}
			});
		},

		render: function(container) {
			var self = this,
				parent = _.isEmpty(container) ? $('#monster_content') : container,
				template = $(self.getTemplate({
					name: 'layout',
					data: {
						accountName: _.get(monster, 'apps.auth.currentAccount.name', '')
					}
				}));

			self.appFlags.acdc.container = template;
			self.bindLayout(template);
			parent.empty().append(template);
			self.renderSection(self.appFlags.acdc.currentTab);
		},

		bindLayout: function(template) {
			var self = this;

			template.find('.acdc-tab').on('click', function() {
				self.renderSection($(this).data('tab'));
			});
		},

		renderSection: function(tab) {
			var self = this,
				template = self.appFlags.acdc.container,
				generation = ++self.appFlags.acdc.requestGeneration;

			self.appFlags.acdc.currentTab = tab;
			template.find('.acdc-tab').removeClass('active');
			template.find('.acdc-tab[data-tab="' + tab + '"]').addClass('active');

			if (tab === 'queues') {
				self.renderQueues(generation);
			} else if (tab === 'agents') {
				self.renderAgents(generation);
			} else {
				self.renderDashboard(generation);
			}
		},

		newGeneration: function(generation) {
			return generation || ++this.appFlags.acdc.requestGeneration;
		},

		isCurrentView: function(generation, tab, accountId) {
			return generation === this.appFlags.acdc.requestGeneration
				&& tab === this.appFlags.acdc.currentTab
				&& accountId === this.accountId;
		},

		getContentContainer: function() {
			return this.appFlags.acdc.container.find('.acdc-content');
		},

		renderLoading: function(message) {
			var self = this;

			self.getContentContainer().html(self.getTemplate({
				name: 'state',
				data: {
					loading: true,
					message: message || self.i18n.active().acdc.states.loading
				}
			}));
		},

		renderError: function(message, retry) {
			var self = this,
				template = $(self.getTemplate({
					name: 'state',
					data: {
						error: true,
						message: message || self.i18n.active().acdc.states.error
					}
				}));

			template.find('.acdc-retry').on('click', retry);
			self.getContentContainer().empty().append(template);
		},

		request: function(resource, data, callback) {
			var self = this;

			self.requestEnvelope(resource, data, function(error, response) {
				callback(error, response ? response.data : null);
			});
		},

		requestEnvelope: function(resource, data, callback) {
			var self = this;

			monster.request({
				resource: resource,
				data: _.merge({
					accountId: self.accountId
				}, data || {}),
				success: function(response) {
					callback(null, response || {});
				},
				error: function(error) {
					callback(self.formatApiError(error));
				}
			});
		},

		requestCompleteList: function(resource, data, callback) {
			var self = this;

			self.requestEnvelope(resource, data, function(error, response) {
				if (error) {
					callback(error);
					return;
				}
				if (!response || !_.isArray(response.data)
					|| (response.status && response.status !== 'success')
					|| (response.next_start_key !== undefined && response.next_start_key !== null && response.next_start_key !== '')
					|| (response.next_cursor !== undefined && response.next_cursor !== null && response.next_cursor !== '')) {
					callback(self.i18n.active().acdc.queues.incompleteInventory);
					return;
				}
				callback(null, response.data);
			});
		},

		requestOwnedNumbers: function(resource, data, callback) {
			var self = this;

			self.requestEnvelope(resource, data, function(error, response) {
				var numbers = _.get(response, 'data.numbers');

				if (error || !_.isPlainObject(numbers) || (response.status && response.status !== 'success')
					|| (response.next_start_key !== undefined && response.next_start_key !== null && response.next_start_key !== '')
					|| (response.next_cursor !== undefined && response.next_cursor !== null && response.next_cursor !== '')) {
					callback(error || self.i18n.active().acdc.dropdowns.incomplete);
					return;
				}
				callback(null, _.map(_.toPairs(numbers), function(pair) {
					return { number: pair[0], state: _.get(pair[1], 'state'), name: _.get(pair[1], 'caller_id.name', '') };
				}));
			});
		},

		verifySystemMedia: function(media, callback) {
			var self = this,
				cache = self.appFlags.acdc.verifiedSystemMedia,
				prompts = {},
				verified = {},
				index = 0,
				active = 0,
				finished = false,
				keys,
				pump;

			if (cache && Date.now() - cache.time < 60000 && _.isEqual(cache.inventory, media)) {
				callback(null, cache.media);
				return;
			}
			_.each(media, function(item) {
				var match = typeof item.id === 'string' && item.id.match(/^([a-z]{2,3}(?:-[a-z0-9]{2,8})*)\/([A-Za-z0-9_.-]+)$/);

				if (item.is_prompt && match && item.language === match[1]) {
					prompts[match[2]] = true;
				}
			});
			keys = _.keys(prompts);
			if (keys.length > 1000) {
				callback(self.i18n.active().acdc.dropdowns.incomplete);
				return;
			}
			pump = function() {
				if (finished) { return; }
				if (index === keys.length && active === 0) {
					var result = _.filter(media, function(item) { return verified[item.id] === true; });

					finished = true;
					self.appFlags.acdc.verifiedSystemMedia = { time: Date.now(), inventory: _.cloneDeep(media), media: result };
					callback(null, result);
					return;
				}
				while (active < 8 && index < keys.length && !finished) {
					active++;
					self.requestCompleteList('acdc.media.prompt', { promptId: encodeURIComponent(keys[index++]) }, function(error, entries) {
						active--;
						if (finished) { return; }
						if (error) { finished = true; callback(error); return; }
						_.each(entries, function(item) { if (item.has_attachments === true) { verified[item.id] = true; } });
						pump();
					});
				}
			};
			pump();
		},

		selectionOptions: function(items, current, emptyLabel, currentLabel) {
			var options = [{ value: '', label: emptyLabel }].concat(items),
				value = current === undefined || current === null ? '' : String(current);

			if (value && !_.some(options, function(item) { return item.value === value; })) {
				options.push({ value: value, label: currentLabel, preserved: true });
			}
			return _.map(options, function(item) { return _.assign({}, item, { selected: item.value === value }); });
		},

		populateQueueDropdowns: function(view, queue, results, errors, isEdit) {
			var self = this,
				labels = self.i18n.active().acdc.dropdowns,
				form = view.find('.acdc-queue-form'),
				systemMedia = results.verifiedSystemMedia || [],
				media = _.map(results.media || [], function(item) {
					return { value: item.id, label: labels.accountMedia + ': ' + (item.name || item.id) };
				}).concat(_.map(systemMedia, function(item) {
					return { value: item.id.split('/').slice(1).join('/'), label: labels.systemPrompt + ': ' + item.name + ' (' + item.language + ')' };
				})),
				languages = _.map(_.uniq(_.map(systemMedia, 'language')).sort(), function(language) {
					return { value: language, label: _.get(labels, ['languages', language], language) };
				}),
				authority = _.get(queue, 'callback.outbound_authority', {}),
				users = _.map(_.filter(results.users || [], function(user) { return user.enabled !== false; }), function(user) {
					return { value: user.id || user._id, label: self.getAgentName(user), authorityType: 'user' };
				}),
				numbers = _.chain(results.numbers || [])
					.filter(function(item) { return /^\+?[0-9]{1,15}$/.test(item.number) && item.state === 'in_service'; })
					.map(function(item) { return { value: item.number, label: item.number }; }).sortBy('label').value(),
				source = _.get(queue, 'callback.caller_id_source') || (isEdit ? 'legacy' : 'inherit'),
				setSelect = function(name, choices, value, emptyLabel, readOnly) {
					var select = form.find('[name="' + name + '"]');

					select.empty();
					_.each(self.selectionOptions(choices, value, emptyLabel, labels.currentPreserved), function(item) {
						$('<option>').val(item.value).text(item.label).prop('selected', item.selected)
							.attr('data-authority-type', item.authorityType || (item.preserved ? authority.type : ''))
							.attr('data-preserved', item.preserved ? 'true' : 'false')
							.appendTo(select);
					});
					select.toggleClass('acdc-catalog-readonly', Boolean(readOnly)).prop('disabled', Boolean(readOnly));
				};

			media = _.sortBy(_.uniqBy(media, 'value'), 'label');
			form.find('.acdc-media-select').each(function() {
				var name = $(this).attr('name');

				setSelect(name, media, _.get(queue, name), labels.useDefault, errors.media || errors.systemMedia);
			});
			setSelect('announcements.language', languages, _.get(queue, 'announcements.language'), labels.inheritLanguage, errors.systemMedia);
			if (authority.type === 'device' && authority.id) {
				users.push({ value: authority.id, label: labels.legacyDevice, authorityType: 'device' });
			}
			setSelect('callback.outbound_authority.id', users, authority.id, labels.chooseUser, errors.users);
			form.find('[name="callback.outbound_authority.type"]').val(authority.type || 'user');
			setSelect('callback.outbound_caller_id.number', numbers, _.get(queue, 'callback.outbound_caller_id.number'), labels.chooseNumber, errors.numbers);
			form.find('[name="callback.outbound_caller_id.name"]').val(_.get(queue, 'callback.outbound_caller_id.name', ''));
			form.data('original-caller-id-number', _.get(queue, 'callback.outbound_caller_id.number', ''));
			form.data('original-caller-id-name', _.get(queue, 'callback.outbound_caller_id.name', ''));
			if (source === 'legacy') {
				form.find('[name="callback.caller_id_source"]').append($('<option>').val('legacy').text(labels.keepCallerId));
			}
			form.find('[name="callback.caller_id_source"]').val(source);
			form.data('original-caller-id-source', source);
			form.data('catalog-errors', Boolean(errors.media || errors.systemMedia || errors.numbers));
			view.find('.acdc-catalog-warning').toggleClass('hidden', !form.data('catalog-errors'));
		},

		orderedAgentIds: function(selectedIds, preferredOrder) {
			var selected = _.uniq(selectedIds).sort();

			return _.uniq(_.filter(preferredOrder || [], function(id) { return selected.indexOf(id) >= 0; }).concat(selected));
		},

		renderAgentOrder: function(view, preferredOrder) {
			var self = this,
				form = view.find('.acdc-queue-form'),
				roster = view.find('.acdc-roster'),
				list = view.find('.acdc-agent-order'),
				labels = self.i18n.active().acdc.queues,
				knownIds = roster.find('option').map(function() { return $(this).val(); }).get(),
				readOnly = Boolean(view.data('roster-read-only') || !_.isArray(preferredOrder)
					|| _.some(preferredOrder, function(id) { return knownIds.indexOf(id) < 0; })),
				order = self.orderedAgentIds(roster.val() || [], _.isArray(preferredOrder) ? preferredOrder : []);

			form.data('agent-order-read-only', readOnly);
			form.data('agent-order', readOnly ? preferredOrder : order);
			list.empty();
			_.each(order, function(id, index) {
				var item = $('<li>').addClass('acdc-agent-order-item').attr('data-agent-id', id),
					name = roster.find('option').filter(function() { return $(this).val() === id; }).text();

				$('<span>').addClass('acdc-agent-order-name').text((index + 1) + '. ' + name).appendTo(item);
				_.each([{direction: -1, label: labels.moveEarlier}, {direction: 1, label: labels.moveLater}], function(action) {
					$('<button>').attr({type: 'button', 'data-direction': action.direction, 'aria-label': action.label + ': ' + name})
						.addClass('monster-button-secondary acdc-agent-order-move')
						.toggleClass('acdc-catalog-readonly', readOnly).prop('disabled', readOnly).text(action.label).appendTo(item);
				});
				list.append(item);
			});
			view.find('.acdc-agent-order-warning').toggleClass('hidden', !readOnly);
			view.find('.acdc-agent-order-section').toggleClass('hidden', form.find('[name="strategy"]').val() !== 'in_order');
		},

		rosterInventoryState: function(users, roster, loadError) {
			var self = this,
				userIds = _.map(users, function(user) { return user && (user.id || user._id); }),
				complete = _.isArray(roster) && _.every(roster, function(id) {
					return typeof id === 'string' && id.length > 0 && userIds.indexOf(id) >= 0;
				});

			return {
				readOnly: Boolean(loadError || !complete),
				warning: loadError || (!complete ? self.i18n.active().acdc.queues.incompleteInventory : null)
			};
		},

		requestMany: function(requests, callback) {
			var self = this,
				keys = _.keys(requests),
				pending = keys.length,
				results = {},
				errors = {};

			if (!pending) {
				callback(errors, results);
				return;
			}

			_.each(requests, function(request, key) {
				var dispatch = request.ownedNumbers ? self.requestOwnedNumbers : (request.completeList ? self.requestCompleteList : self.request);

				dispatch.call(self, request.resource, request.data, function(error, data) {
					if (error) {
						errors[key] = error;
					} else {
						results[key] = data;
					}

					pending--;
					if (!pending) {
						callback(errors, results);
					}
				});
			});
		},

		loadAcdcCallflowInventory: function(callback) {
			var self = this;

			self.request('acdc.callflows.list', {}, function(listError, summaries) {
				var candidates,
					requests = {};

				if (listError) {
					callback(listError);
					return;
				}

				summaries = summaries || [];
				candidates = _.filter(summaries, function(summary) {
					return _.includes(summary.modules || [], 'acdc_member')
						|| _.includes(summary.flags || [], self.managedRouteFlag);
				});
				_.each(candidates, function(summary) {
					if (summary.id) {
						requests[summary.id] = {
							resource: 'acdc.callflows.get',
							data: { callflowId: summary.id }
						};
					}
				});

				self.requestMany(requests, function(errors, routesById) {
					if (!_.isEmpty(errors)) {
						callback(_.values(errors)[0]);
						return;
					}
					callback(null, {
						summaries: summaries,
						routes: _.values(routesById)
					});
				});
			});
		},

		hasOnlyKeys: function(value, allowedKeys) {
			return _.isPlainObject(value)
				&& _.every(_.keys(value), function(key) {
					return _.includes(allowedKeys, key);
				});
		},

		isStrictManagedRoute: function(route, queueId) {
			var flow = _.get(route, 'flow'),
				data = _.get(flow, 'data'),
				children = _.get(flow, 'children'),
				numbers = _.get(route, 'numbers'),
				flags = _.get(route, 'flags'),
				queueFlag = this.managedRouteQueueFlagPrefix + queueId;

			return _.isString(route.id)
				&& route.id.length > 0
				&& _.isArray(numbers)
				&& numbers.length === 1
				&& _.isString(numbers[0])
				&& /^\+?[0-9*#]+$/.test(numbers[0])
				&& _.isEqual(flags, [this.managedRouteFlag, queueFlag])
				&& this.hasOnlyKeys(flow, ['module', 'data', 'children'])
				&& flow.module === 'acdc_member'
				&& this.hasOnlyKeys(data, ['id'])
				&& data.id === queueId
				&& _.isPlainObject(children)
				&& _.isEmpty(children)
				&& (_.isUndefined(route.patterns) || (_.isArray(route.patterns) && _.isEmpty(route.patterns)));
		},

		isAcdcQueueReference: function(flow, queueId) {
			var self = this;

			if (!_.isPlainObject(flow)) {
				return false;
			}
			if (flow.module === 'acdc_member' && _.get(flow, 'data.id') === queueId) {
				return true;
			}

			return _.some(_.values(flow.children || {}), function(child) {
				return self.isAcdcQueueReference(child, queueId);
			});
		},

		findExtensionCollision: function(summaries, extension, ignoredCallflowId) {
			return _.find(summaries || [], function(summary) {
				return summary.id !== ignoredCallflowId
					&& _.includes(summary.numbers || [], extension);
			});
		},

		buildManagedRoute: function(queueId, queueName, extension) {
			return {
				name: queueName + ' (ACDC)',
				numbers: [extension],
				patterns: [],
				flags: [this.managedRouteFlag, this.managedRouteQueueFlagPrefix + queueId],
				flow: {
					module: 'acdc_member',
					data: { id: queueId },
					children: {}
				}
			};
		},

		queueWriteResource: function(queueId) {
			return queueId ? 'acdc.queues.update' : 'acdc.queues.create';
		},

		rememberSavedQueueId: function(view, queueId, queue) {
			var savedId = queueId || _.get(queue, 'id') || _.get(queue, '_id');

			if (savedId) {
				view.data('queue-id', savedId);
			}
			return savedId;
		},

		formatApiError: function(error) {
			var fallback = this.i18n.active().acdc.states.error;

			if (!error) {
				return fallback;
			}

			return error.message
				|| _.get(error, 'data.message')
				|| _.get(error, 'data.error')
				|| fallback;
		},

		renderDashboard: function(pGeneration) {
			var self = this,
				generation = self.newGeneration(pGeneration),
				accountId = self.accountId,
				now = Math.floor(Date.now() / 1000) + self.kazooEpochOffsetSeconds;

			self.renderLoading(self.i18n.active().acdc.states.loadingDashboard);
			self.requestMany({
				queues: { resource: 'acdc.queues.list' },
				agents: { resource: 'acdc.agents.list' },
				statuses: { resource: 'acdc.agents.statuses' },
				queueStats: { resource: 'acdc.queues.stats' },
				agentStats: { resource: 'acdc.agents.stats' },
				callStats: {
					resource: 'acdc.callStats.list',
					data: {
						createdFrom: now - self.callStatsWindowSeconds,
						createdTo: now
					}
				}
			}, function(errors, results) {
				var view;

				if (!self.isCurrentView(generation, 'dashboard', accountId)) {
					return;
				}

				if (errors.queues || errors.agents) {
					self.renderError(errors.queues || errors.agents, function() {
						self.renderDashboard();
					});
					return;
				}

				view = $(self.getTemplate({
					name: 'dashboard',
					data: self.formatDashboard(results, errors)
				}));
				view.find('.acdc-refresh').on('click', function() {
					self.renderDashboard();
				});
				self.getContentContainer().empty().append(view);
			});
		},

		formatDashboard: function(results, errors) {
			var self = this,
				queues = results.queues || [],
				agents = results.agents || [],
				statuses = self.normalizeStatuses(results.statuses || {}),
				queueStats = _.get(results, 'queueStats.stats', []),
				calls = _.isArray(results.callStats) ? results.callStats : [],
				queueNames = _.keyBy(queues, 'id'),
				agentNames = _.keyBy(agents, 'id'),
				waiting = _.filter(queueStats, { status: 'waiting' }).length,
				handling = _.filter(queueStats, function(stat) {
					return stat.status === 'handled' || stat.status === 'handling';
				}).length,
				online = _.filter(_.values(statuses), function(status) {
					return ['logout', 'logged_out', 'unknown'].indexOf(status) < 0;
				}).length,
				warnings = _.map(errors, function(message, key) {
					return self.i18n.active().acdc.dashboard.partial[key] || message;
				});

			calls = _.chain(calls)
				.sortBy(function(call) {
					return -(parseInt(call.handled_timestamp, 10) || 0);
				})
				.take(20)
				.map(function(call) {
					return _.merge({}, call, {
						queue_name: _.get(queueNames, [call.queue_id, 'name'], call.queue_id || '-'),
						agent_name: self.getAgentName(agentNames[call.agent_id])
					});
				})
				.value();

			return {
				summary: {
					queues: queues.length,
					agents: agents.length,
					online: online,
					waiting: waiting,
					handling: handling
				},
				queueRows: self.buildQueueStats(queues, queueStats),
				calls: calls,
				hasCalls: calls.length > 0,
				warnings: warnings,
				hasWarnings: warnings.length > 0
			};
		},

		buildQueueStats: function(queues, stats) {
			return _.map(queues, function(queue) {
				var matching = _.filter(stats, { queue_id: queue.id });

				return {
					id: queue.id,
					name: queue.name,
					waiting: _.filter(matching, { status: 'waiting' }).length,
					handling: _.filter(matching, function(stat) {
						return stat.status === 'handled' || stat.status === 'handling';
					}).length,
					abandoned: _.filter(matching, { status: 'abandoned' }).length,
					processed: _.filter(matching, { status: 'processed' }).length
				};
			});
		},

		renderQueues: function(pGeneration) {
			var self = this,
				generation = self.newGeneration(pGeneration),
				accountId = self.accountId;

			self.renderLoading(self.i18n.active().acdc.states.loadingQueues);
			self.requestMany({
				queues: { resource: 'acdc.queues.list' },
				queueStats: { resource: 'acdc.queues.stats' }
			}, function(errors, results) {
				var queues,
					view;

				if (!self.isCurrentView(generation, 'queues', accountId)) {
					return;
				}

				if (errors.queues) {
					self.renderError(errors.queues, function() {
						self.renderQueues();
					});
					return;
				}

				queues = self.buildQueueStats(results.queues || [], _.get(results, 'queueStats.stats', []));
				view = $(self.getTemplate({
					name: 'queues',
					data: {
						queues: queues,
						hasQueues: queues.length > 0,
						statsWarning: errors.queueStats
					}
				}));

				self.bindQueueList(view, generation, accountId);
				self.getContentContainer().empty().append(view);
			});
		},

		renderCallbacks: function(queueId, queueName, cursor, cursorHistory) {
			var self = this,
				generation = ++self.appFlags.acdc.requestGeneration,
				accountId = self.accountId,
				history = cursorHistory || [];

			self.renderLoading(self.i18n.active().acdc.states.loadingCallbacks);
			self.requestEnvelope('acdc.callbacks.list', {
				queueId: queueId,
				pageSize: 100,
				cursor: cursor || ''
			}, function(error, response) {
				var callbacks,
					view,
					nextCursor;

				if (!self.isCurrentView(generation, 'queues', accountId)) {
					return;
				}
				if (error) {
					self.renderError(error, function() {
						self.renderCallbacks(queueId, queueName, cursor, history);
					});
					return;
				}

				callbacks = _.map(response.data || [], function(item) {
					return self.formatCallback(item);
				});
				nextCursor = response.next_cursor || _.get(response, 'metadata.next_cursor');
				view = $(self.getTemplate({
					name: 'callbacks',
					data: {
						queueName: queueName,
						callbacks: callbacks,
						hasCallbacks: callbacks.length > 0,
						hasPrevious: history.length > 0,
						hasNext: Boolean(nextCursor)
					}
				}));

				view.find('.acdc-callbacks-back').on('click', function() {
					self.renderQueues();
				});
				view.find('.acdc-callbacks-refresh').on('click', function() {
					self.renderCallbacks(queueId, queueName, cursor, history);
				});
				view.find('.acdc-callbacks-next').on('click', function() {
					self.renderCallbacks(queueId, queueName, nextCursor, history.concat([cursor || '']));
				});
				view.find('.acdc-callbacks-previous').on('click', function() {
					var previous = history[history.length - 1] || '';

					self.renderCallbacks(queueId, queueName, previous, history.slice(0, -1));
				});
				view.find('.acdc-callback-cancel').on('click', function() {
					self.cancelCallback(queueId, queueName, $(this).data('id'), cursor, history,
						generation, accountId);
				});
				self.getContentContainer().empty().append(view);
			});
		},

		formatCallback: function(item) {
			var terminal = ['completed', 'cancelled', 'failed', 'expired'],
				status = item.status || 'unknown',
				callbackI18n = this.i18n.active().acdc.callbacks || {},
				labels = callbackI18n.statuses || {},
				reasonLabels = callbackI18n.reconciliationReasons || {},
				reconciliationRequired = item.reconciliation_required === true,
				underlyingStatusLabel = labels[status] || status;

			return _.merge({}, item, {
				status_label: reconciliationRequired ?
					(labels.reconciliation_required || 'Recovery pending') : underlyingStatusLabel,
				status_class: reconciliationRequired ? 'reconciling' : 'neutral',
				reconciliation_required: reconciliationRequired,
				reconciliation_detail: reconciliationRequired ?
					(reasonLabels[item.reconciliation_reason] || callbackI18n.reconciliationGeneric ||
						'Call state is being verified; no new attempt will be placed.') : '',
				underlying_status_label: underlyingStatusLabel,
				enqueued_label: this.formatKazooTimestamp(item.enqueued_at),
				expires_label: this.formatKazooTimestamp(item.expires_at),
				cancellable: terminal.indexOf(status) < 0 && status !== 'cancelling'
			});
		},

		formatKazooTimestamp: function(value) {
			var seconds = parseInt(value, 10),
				date;

			if (!seconds) {
				return '-';
			}
			date = new Date((seconds - this.kazooEpochOffsetSeconds) * 1000);
			return isNaN(date.getTime()) ? '-' : date.toLocaleString();
		},

		cancelCallback: function(queueId, queueName, callbackId, cursor, history, generation, accountId) {
			var self = this;

			monster.ui.confirm(self.i18n.active().acdc.callbacks.confirmCancel, function() {
				self.request('acdc.callbacks.cancel', {
					queueId: queueId,
					callbackId: callbackId,
					data: {}
				}, function(error) {
					if (!self.isCurrentView(generation, 'queues', accountId)) {
						return;
					}
					if (error) {
						self.toastError(error);
						return;
					}
					self.toastSuccess(self.i18n.active().acdc.callbacks.cancelled);
					self.renderCallbacks(queueId, queueName, cursor, history);
				});
			});
		},

		bindQueueList: function(view, generation, accountId) {
			var self = this;

			view.find('.acdc-add-queue').on('click', function() {
				self.renderQueueForm();
			});
			view.find('.acdc-edit-queue').on('click', function() {
				self.renderQueueForm($(this).data('id'));
			});
			view.find('.acdc-view-callbacks').on('click', function() {
				self.renderCallbacks($(this).data('id'), $(this).data('name'), '', []);
			});
			view.find('.acdc-delete-queue').on('click', function() {
				var queueId = $(this).data('id'),
					queueName = $(this).data('name');

				monster.ui.confirm(self.getTemplate({
					name: '!' + self.i18n.active().acdc.queues.confirmDelete,
					data: { name: queueName }
				}), function() {
					self.deleteQueueSafely(queueId, generation, accountId);
				});
			});
			view.find('.acdc-refresh').on('click', function() {
				self.renderQueues();
			});
		},

		deleteQueueSafely: function(queueId, generation, accountId) {
			var self = this;

			self.loadAcdcCallflowInventory(function(error, inventory) {
				var references,
					ownedRoutes,
					externalRoutes,
					deleteQueue;

				if (!self.isCurrentView(generation, 'queues', accountId)) {
					return;
				}
				if (error) {
					self.toastError(self.i18n.active().acdc.queues.routeUnavailable);
					return;
				}

				references = _.filter(inventory.routes, function(route) {
					return self.isAcdcQueueReference(route.flow, queueId);
				});
				ownedRoutes = _.filter(references, function(route) {
					return self.isStrictManagedRoute(route, queueId);
				});
				externalRoutes = _.filter(references, function(route) {
					return !_.some(ownedRoutes, { id: route.id });
				});
				if (externalRoutes.length) {
					self.toastError(self.i18n.active().acdc.queues.externalRouteDeleteBlocked);
					return;
				}
				if (ownedRoutes.length > 1) {
					self.toastError(self.i18n.active().acdc.queues.multipleManagedRoutes);
					return;
				}

				deleteQueue = function() {
					self.request('acdc.queues.delete', {
						queueId: queueId,
						data: {}
					}, function(queueError) {
						if (!self.isCurrentView(generation, 'queues', accountId)) {
							return;
						}
						if (queueError) {
							self.toastError(queueError);
							return;
						}
						self.toastSuccess(self.i18n.active().acdc.queues.deleted);
						self.renderQueues();
					});
				};

				if (!ownedRoutes.length) {
					deleteQueue();
					return;
				}
				self.request('acdc.callflows.delete', {
					callflowId: ownedRoutes[0].id,
					data: {}
				}, function(routeError) {
					if (!self.isCurrentView(generation, 'queues', accountId)) {
						return;
					}
					if (routeError) {
						self.toastError(routeError);
						return;
					}
					deleteQueue();
				});
			});
		},

		renderQueueForm: function(queueId) {
			var self = this,
				generation = ++self.appFlags.acdc.requestGeneration,
				accountId = self.accountId,
				requests = {
					users: { resource: 'acdc.users.list', completeList: true },
					media: { resource: 'acdc.media.list', completeList: true },
					systemMedia: { resource: 'acdc.media.system', completeList: true },
					numbers: { resource: 'acdc.numbers.list', ownedNumbers: true }
				},
				baseErrors,
				baseResults,
				inventoryError,
				inventory,
				pending = 2,
				finish;

			self.renderLoading(self.i18n.active().acdc.states.loadingQueue);
			if (queueId) {
				requests.queue = {
					resource: 'acdc.queues.get',
					data: { queueId: queueId }
				};
				requests.roster = {
					resource: 'acdc.queues.roster',
					completeList: true,
					data: { queueId: queueId }
				};
			}

			finish = function() {
				var errors,
					results,
					queue,
					roster,
					rosterState,
					rosterReadOnly,
					routes,
					references,
					ownedRoutes,
					ownedRoute,
					externalRoutes,
					routeReadOnly,
					users,
					view;

				pending--;
				if (pending) {
					return;
				}

				errors = baseErrors || {};
				results = baseResults || {};
				queue = self.normalizeQueueCallback(_.merge(self.defaultQueue(), results.queue || {}));
				roster = results.roster || queue.agents || [];
				rosterState = self.rosterInventoryState(results.users || [], roster, errors.roster);
				rosterReadOnly = Boolean(queueId && rosterState.readOnly);
				roster = _.isArray(roster) ? roster : [];
				routes = _.get(inventory, 'routes', []);
				references = queueId ? _.filter(routes, function(route) {
					return self.isAcdcQueueReference(route.flow, queueId);
				}) : [];
				ownedRoutes = _.filter(references, function(route) {
					return self.isStrictManagedRoute(route, queueId);
				});
				ownedRoute = ownedRoutes.length === 1 ? ownedRoutes[0] : null;
				externalRoutes = _.filter(references, function(route) {
					return !ownedRoute || route.id !== ownedRoute.id;
				});
				routeReadOnly = Boolean(inventoryError || ownedRoutes.length > 1);

				if (!self.isCurrentView(generation, 'queues', accountId)) {
					return;
				}

				if (errors.users || errors.queue) {
					self.renderError(errors.users || errors.queue, function() {
						self.renderQueueForm(queueId);
					});
					return;
				}

				users = _.map(results.users || [], function(user) {
					var userId = user.id || user._id;

					return {
						id: userId,
						name: self.getAgentName(user),
						selected: roster.indexOf(userId) >= 0
					};
				});
				view = $(self.getTemplate({
					name: 'queue-form',
					data: {
						queue: queue,
						queueId: queueId,
						isEdit: Boolean(queueId),
						users: users,
						rosterWarning: rosterState.warning,
						rosterReadOnly: rosterReadOnly,
						routeExtension: _.get(ownedRoute, 'numbers[0]', ''),
						routeWarning: Boolean(inventoryError || ownedRoutes.length > 1),
						routeReadOnly: routeReadOnly,
						externalExtensions: _.chain(externalRoutes)
							.flatMap('numbers')
							.compact()
							.uniq()
							.join(', ')
							.value(),
						hasExternalRoutes: externalRoutes.length > 0
					}
				}));

				view.data('roster-read-only', rosterReadOnly);
				view.data('route-read-only', routeReadOnly);
				view.data('callflow-summaries', _.get(inventory, 'summaries', []));
				view.data('owned-route', ownedRoute);
				self.populateQueueDropdowns(view, queue, results, errors, Boolean(queueId));
				self.renderAgentOrder(view, queue.agent_order || []);
				self.bindQueueForm(view, queueId, generation, accountId);
				self.getContentContainer().empty().append(view);
			};

			self.requestMany(requests, function(errors, results) {
				baseErrors = errors;
				baseResults = results;
				if (errors.systemMedia) { finish(); return; }
				self.verifySystemMedia(results.systemMedia || [], function(error, media) {
					if (error) { baseErrors.systemMedia = error; }
					baseResults.verifiedSystemMedia = media || [];
					finish();
				});
			});
			self.loadAcdcCallflowInventory(function(error, result) {
				inventoryError = error;
				inventory = result;
				finish();
			});
		},

		defaultQueue: function() {
			return {
				name: '',
				strategy: 'round_robin',
				agent_ring_timeout: 15,
				agent_wrapup_time: 0,
				connection_timeout: 3600,
				max_queue_size: 0,
				ring_simultaneously: 1,
				caller_exit_key: '#',
				enter_when_empty: true,
				record_caller: false,
				moh: '',
				announce: '',
				announcements: {
					interval: 30,
					initial_delay: 30,
					position_announcements_enabled: false,
					wait_time_announcements_enabled: false,
					media: {
						you_are_at_position: 'queue-you_are_at_position',
						in_the_queue: 'queue-in_the_queue',
						the_estimated_wait_time_is: 'queue-the_estimated_wait_time_is',
						increase_in_call_volume: 'queue-increase_in_call_volume'
					}
				},
				callback: {
					enabled: false,
					entry_key: '6',
					allow_alternate_number: false,
					use_local_resources: false,
					max_attempts: 3,
					retry_delay: 60,
					ttl: 3600,
					originate_timeout: 60,
					ready_ack_timeout: 5,
					confirmation_timeout: 10,
					handoff_timeout: 5,
					menu_timeout_ms: 30000,
					success_timeout_ms: 10000,
					outbound_authority: {
						id: '',
						type: 'user'
					},
					outbound_caller_id: {
						number: '',
						name: ''
					},
					media: {
						offer: '',
						menu: '',
						number_readback: '',
						confirmation: '',
						success: '',
						returned_confirmation: ''
					}
				}
			};
		},

		normalizeQueueCallback: function(queue) {
			var legacyReturnedPrompt = _.get(queue, 'callback.return_confirmation_prompt');

			if (!_.get(queue, 'callback.media.returned_confirmation') && legacyReturnedPrompt) {
				_.set(queue, 'callback.media.returned_confirmation', legacyReturnedPrompt);
			}
			return queue;
		},

		bindQueueForm: function(view, queueId, generation, accountId) {
			var self = this,
				form = view.find('.acdc-queue-form'),
				roster = view.find('.acdc-roster');

			monster.ui.chosen(roster, { width: '100%' });
			roster.on('change', function() {
				self.renderAgentOrder(view, form.data('agent-order') || []);
			});
			form.find('[name="strategy"]').on('change', function() {
				view.find('.acdc-agent-order-section').toggleClass('hidden', $(this).val() !== 'in_order');
			});
			view.on('click', '.acdc-agent-order-move', function() {
				var id = $(this).closest('.acdc-agent-order-item').attr('data-agent-id'),
					order = (form.data('agent-order') || []).slice(),
					index = order.indexOf(id),
					next = index + Number($(this).attr('data-direction'));

				if (form.data('agent-order-read-only') || index < 0 || next < 0 || next >= order.length) { return; }
				order.splice(index, 1);
				order.splice(next, 0, id);
				self.renderAgentOrder(view, order);
			});
			self.syncCallbackForm(form);
			form.find('[name="callback.enabled"], [name="callback.caller_id_source"]').on('change', function() {
				self.syncCallbackForm(form);
			});
			form.find('[name="callback.outbound_authority.id"]').on('change', function() {
				var type = $(this).find('option:selected').attr('data-authority-type') || 'user';

				form.find('[name="callback.outbound_authority.type"]').val(type);
				if (type === 'user') {
					form.find('[name="callback.caller_id_source"]').val('inherit');
				}
				self.syncCallbackForm(form);
			});
			form.find('[name="callback.outbound_caller_id.number"]').on('change', function() {
				form.find('[name="callback.outbound_caller_id.name"]').val(
					$(this).val() === form.data('original-caller-id-number') ? form.data('original-caller-id-name') : ''
				);
			});
			view.find('.acdc-cancel').on('click', function() {
				self.renderQueues();
			});
			form.on('submit', function(event) {
				var payload,
					agentIds,
					routeExtension,
					ownedRoute,
					collision,
					callbackError;

				event.preventDefault();
				if (form[0].checkValidity && !form[0].checkValidity()) {
					form[0].reportValidity && form[0].reportValidity();
					return;
				}
				callbackError = self.callbackKeyError(form) || self.callbackSelectionError(form);
				if (callbackError) {
					self.showFormError(view, callbackError);
					return;
				}

				payload = self.serializeQueue(form, Boolean(view.data('queue-id') || queueId));
				agentIds = view.data('roster-read-only') ? null : roster.val() || [];
				routeExtension = view.data('route-read-only')
					? null
					: $.trim(form.find('[name="route_extension"]').val());
				ownedRoute = view.data('owned-route');
				collision = routeExtension && self.findExtensionCollision(
					view.data('callflow-summaries'),
					routeExtension,
					_.get(ownedRoute, 'id')
				);
				if (collision) {
					self.showFormError(view, self.i18n.active().acdc.queues.routeCollision);
					return;
				}
				self.saveQueue(view.data('queue-id') || queueId, payload, agentIds, routeExtension, view, generation, accountId);
			});
		},

		syncCallbackForm: function(form) {
			var enabled = form.find('[name="callback.enabled"]').is(':checked'),
				custom = form.find('[name="callback.caller_id_source"]').val() === 'custom',
				inherit = form.find('[name="callback.caller_id_source"]').val() === 'inherit';

			form.find('.acdc-callback-required').prop('required', enabled);
			form.find('.acdc-callback-number').prop('required', enabled && custom);
			form.find('.acdc-caller-number-row').toggleClass('hidden', inherit);
			form.find('.acdc-callback-settings').toggleClass('acdc-disabled-section', !enabled);
		},

		callbackKeyError: function(form) {
			var enabled = form.find('[name="callback.enabled"]').is(':checked'),
				entryKey = form.find('[name="callback.entry_key"]').val(),
				exitKey = form.find('[name="caller_exit_key"]').val(),
				alternate = form.find('[name="callback.allow_alternate_number"]').is(':checked');

			if (!enabled) {
				return null;
			}
			if (entryKey === exitKey || exitKey === '1' || (alternate && exitKey === '2')) {
				return this.i18n.active().acdc.callbacks.keyConflict;
			}
			if (entryKey === '1' || (alternate && entryKey === '2')) {
				return this.i18n.active().acdc.callbacks.keyConflict;
			}
			return null;
		},

		callbackSelectionError: function(form) {
			var source = form.find('[name="callback.caller_id_source"]').val(),
				number = form.find('[name="callback.outbound_caller_id.number"]'),
				authority = form.find('[name="callback.outbound_authority.id"]'),
				labels = this.i18n.active().acdc.dropdowns;

			if (!form.find('[name="callback.enabled"]').is(':checked')) { return null; }
			if (!authority.val()) { return labels.chooseUser; }
			if (source === 'inherit' && form.find('[name="callback.outbound_authority.type"]').val() !== 'user') {
				return labels.chooseUser;
			}
			if (source === 'custom' && (!number.val()
				|| (number.find('option:selected').attr('data-preserved') === 'true'
					&& form.data('original-caller-id-source') !== 'custom'))) {
				return labels.chooseNumber;
			}
			return null;
		},

		serializeQueue: function(form, isEdit) {
			var integerValue = function(name) {
					return parseInt(form.find('[name="' + name + '"]').val(), 10) || 0;
				},
				optionalMedia = function(name) {
					var value = $.trim(form.find('[name="' + name + '"]').val());

					return value || (isEdit ? null : undefined);
				},
				callbackMedia = {},
				callbackMediaKeys = ['offer', 'menu', 'number_readback', 'confirmation', 'success', 'returned_confirmation'],
				authorityId = $.trim(form.find('[name="callback.outbound_authority.id"]').val()),
				callerIdNumber = $.trim(form.find('[name="callback.outbound_caller_id.number"]').val()),
				callerIdName = $.trim(form.find('[name="callback.outbound_caller_id.name"]').val()),
				callerIdSource = form.find('[name="callback.caller_id_source"]').val(),
				callbackConfig = {
					enabled: form.find('[name="callback.enabled"]').is(':checked'),
					entry_key: form.find('[name="callback.entry_key"]').val(),
					allow_alternate_number: form.find('[name="callback.allow_alternate_number"]').is(':checked'),
					use_local_resources: form.find('[name="callback.use_local_resources"]').is(':checked'),
					max_attempts: integerValue('callback.max_attempts'),
					retry_delay: integerValue('callback.retry_delay'),
					ttl: integerValue('callback.ttl'),
					originate_timeout: integerValue('callback.originate_timeout'),
					ready_ack_timeout: integerValue('callback.ready_ack_timeout'),
					confirmation_timeout: integerValue('callback.confirmation_timeout'),
					handoff_timeout: integerValue('callback.handoff_timeout'),
					menu_timeout_ms: integerValue('callback.menu_timeout_ms'),
					success_timeout_ms: integerValue('callback.success_timeout_ms')
				},
				payload = {
					name: $.trim(form.find('[name="name"]').val()),
					strategy: form.find('[name="strategy"]').val(),
					agent_ring_timeout: integerValue('agent_ring_timeout'),
					agent_wrapup_time: integerValue('agent_wrapup_time'),
					connection_timeout: integerValue('connection_timeout'),
					max_queue_size: integerValue('max_queue_size'),
					ring_simultaneously: integerValue('ring_simultaneously'),
					caller_exit_key: form.find('[name="caller_exit_key"]').val(),
					enter_when_empty: form.find('[name="enter_when_empty"]').is(':checked'),
					record_caller: form.find('[name="record_caller"]').is(':checked'),
					announcements: {
						interval: integerValue('announcements.interval'),
						initial_delay: integerValue('announcements.initial_delay'),
						position_announcements_enabled: form.find('[name="announcements.position_announcements_enabled"]').is(':checked'),
						wait_time_announcements_enabled: form.find('[name="announcements.wait_time_announcements_enabled"]').is(':checked'),
						media: {
							you_are_at_position: $.trim(form.find('[name="announcements.media.you_are_at_position"]').val()),
							in_the_queue: $.trim(form.find('[name="announcements.media.in_the_queue"]').val()),
							the_estimated_wait_time_is: $.trim(form.find('[name="announcements.media.the_estimated_wait_time_is"]').val()),
							increase_in_call_volume: $.trim(form.find('[name="announcements.media.increase_in_call_volume"]').val())
						}
					},
					callback: callbackConfig
				},
				moh = optionalMedia('moh'),
				announce = optionalMedia('announce'),
				announcementLanguage = optionalMedia('announcements.language');

			_.each(callbackMediaKeys, function(key) {
				var value = optionalMedia('callback.media.' + key);

				if (value !== undefined) {
					callbackMedia[key] = value;
				}
			});
			if (!_.isEmpty(callbackMedia)) {
				callbackConfig.media = callbackMedia;
			}
			if (authorityId) {
				callbackConfig.outbound_authority = {
					id: authorityId,
					type: form.find('[name="callback.outbound_authority.type"]').val()
				};
			} else if (isEdit) {
				callbackConfig.outbound_authority = null;
			}
			if (callerIdSource === 'inherit' || callerIdSource === 'custom') {
				callbackConfig.caller_id_source = callerIdSource;
			}
			if (callerIdSource === 'inherit') {
				// PATCH removes a former override; the server resolves the selected
				// user's current identity on every callback, never a stale UI copy.
				if (isEdit) { callbackConfig.outbound_caller_id = null; }
			} else if (callerIdNumber || callerIdName) {
				callbackConfig.outbound_caller_id = {
					number: callerIdNumber
				};
				if (callerIdName) {
					callbackConfig.outbound_caller_id.name = callerIdName;
				} else if (isEdit && callerIdSource === 'custom') {
					callbackConfig.outbound_caller_id.name = null;
				}
			} else if (isEdit) {
				callbackConfig.outbound_caller_id = null;
			}
			if (isEdit) {
				// PATCH null removes the obsolete field after its value has been
				// normalized into callback.media.returned_confirmation.
				callbackConfig.return_confirmation_prompt = null;
			}

			if (moh !== undefined) {
				payload.moh = moh;
			}
			if (announce !== undefined) {
				payload.announce = announce;
			}
			if (announcementLanguage !== undefined) {
				payload.announcements.language = announcementLanguage;
			}
			if (payload.strategy === 'in_order' && !form.data('agent-order-read-only')) {
				payload.agent_order = (form.data('agent-order') || []).slice();
			}

			return payload;
		},

		saveQueue: function(queueId, payload, agentIds, routeExtension, view, generation, accountId) {
			var self = this,
				resource = self.queueWriteResource(queueId),
				data = { data: payload };

			if (queueId) {
				data.queueId = queueId;
			}
			self.setFormBusy(view, true);
			self.request(resource, data, function(error, queue) {
				var savedId;

				if (!self.isCurrentView(generation, 'queues', accountId)) {
					return;
				}

				if (error) {
					self.setFormBusy(view, false);
					self.showFormError(view, error);
					return;
				}

				savedId = self.rememberSavedQueueId(view, queueId, queue);
				if (!savedId) {
					self.setFormBusy(view, false);
					self.showFormError(view, self.i18n.active().acdc.queues.savedMissingId);
					return;
				}
				if (agentIds === null) {
					self.finishQueueSave(savedId, payload.name, routeExtension, true, view, generation, accountId);
					return;
				}
				self.request('acdc.queues.updateRoster', {
					queueId: savedId,
					data: agentIds
				}, function(rosterError) {
					if (!self.isCurrentView(generation, 'queues', accountId)) {
						return;
					}
					if (rosterError) {
						self.setFormBusy(view, false);
						self.showFormError(view, self.i18n.active().acdc.queues.savedRosterFailed + ' ' + rosterError);
						return;
					}
					self.finishQueueSave(savedId, payload.name, routeExtension, false, view, generation, accountId);
				});
			});
		},

		finishQueueSave: function(queueId, queueName, routeExtension, rosterPreserved, view, generation, accountId) {
			var self = this;

			self.syncManagedRoute(queueId, queueName, routeExtension, view, function(error, routePreserved) {
				if (!self.isCurrentView(generation, 'queues', accountId)) {
					return;
				}
				self.setFormBusy(view, false);
				if (error) {
					self.showFormError(view, self.i18n.active().acdc.queues.routeSavedFailed + ' ' + error);
					return;
				}
				if (rosterPreserved) {
					self.toastSuccess(self.i18n.active().acdc.queues.savedSettingsOnly);
				} else if (routePreserved) {
					self.toastSuccess(self.i18n.active().acdc.queues.savedRoutePreserved);
				} else {
					self.toastSuccess(self.i18n.active().acdc.queues.saved);
				}
				self.renderQueues();
			});
		},

		syncManagedRoute: function(queueId, queueName, extension, view, callback, ownedRouteVerified) {
			var self = this,
				ownedRoute = view.data('owned-route'),
				collision,
				resource,
				data,
				payload;

			if (extension === null) {
				callback(null, true);
				return;
			}
			if (ownedRoute && !ownedRouteVerified) {
				self.request('acdc.callflows.get', {
					callflowId: ownedRoute.id
				}, function(error, currentRoute) {
					if (error) {
						callback(error);
						return;
					}
					if (!self.isStrictManagedRoute(currentRoute, queueId)) {
						callback(self.i18n.active().acdc.queues.routeOwnershipChanged);
						return;
					}
					view.data('owned-route', currentRoute);
					self.syncManagedRoute(queueId, queueName, extension, view, callback, true);
				});
				return;
			}
			if (ownedRoute && !self.isStrictManagedRoute(ownedRoute, queueId)) {
				callback(self.i18n.active().acdc.queues.routeOwnershipChanged);
				return;
			}

			collision = extension && self.findExtensionCollision(
				view.data('callflow-summaries'),
				extension,
				_.get(ownedRoute, 'id')
			);
			if (collision) {
				callback(self.i18n.active().acdc.queues.routeCollision);
				return;
			}

			if (!extension && !ownedRoute) {
				callback(null, false);
				return;
			}
			if (!extension) {
				self.request('acdc.callflows.delete', {
					callflowId: ownedRoute.id,
					data: {}
				}, function(error) {
					callback(error, false);
				});
				return;
			}

			payload = self.buildManagedRoute(queueId, queueName, extension);
			resource = ownedRoute ? 'acdc.callflows.update' : 'acdc.callflows.create';
			data = {
				data: ownedRoute ? {
					name: payload.name,
					numbers: payload.numbers
				} : payload
			};
			if (ownedRoute) {
				data.callflowId = ownedRoute.id;
			}
			self.request(resource, data, function(error, route) {
				if (!error && route) {
					view.data('owned-route', route);
				}
				callback(error, false);
			});
		},

		setFormBusy: function(view, busy) {
			view.find('button, input, select').prop('disabled', busy);
			if (!busy && view.data('roster-read-only')) {
				view.find('.acdc-roster').prop('disabled', true);
			}
			if (!busy && view.data('route-read-only')) {
				view.find('.acdc-route-extension').prop('disabled', true);
			}
			if (!busy) {
				view.find('.acdc-catalog-readonly').prop('disabled', true);
			}
			view.find('.acdc-save-spinner').toggle(busy);
		},

		showFormError: function(view, message) {
			view.find('.acdc-form-error').text(message).removeClass('hidden');
		},

		renderAgents: function(pGeneration) {
			var self = this,
				generation = self.newGeneration(pGeneration),
				accountId = self.accountId;

			self.renderLoading(self.i18n.active().acdc.states.loadingAgents);
			self.requestMany({
				agents: { resource: 'acdc.agents.list' },
				statuses: { resource: 'acdc.agents.statuses' },
				agentStats: { resource: 'acdc.agents.stats' },
				queues: { resource: 'acdc.queues.list' }
			}, function(errors, results) {
				var agents,
					view;

				if (!self.isCurrentView(generation, 'agents', accountId)) {
					return;
				}

				if (errors.agents || errors.queues) {
					self.renderError(errors.agents || errors.queues, function() {
						self.renderAgents();
					});
					return;
				}

				agents = self.formatAgents(results.agents || [], results.queues || [], results.statuses || {}, results.agentStats || {});
				view = $(self.getTemplate({
					name: 'agents',
					data: {
						agents: agents,
						hasAgents: agents.length > 0,
						statsWarning: errors.statuses || errors.agentStats
					}
				}));

				self.bindAgentEvents(view, generation, accountId);
				self.getContentContainer().empty().append(view);
			});
		},

		formatAgents: function(agents, queues, rawStatuses, stats) {
			var self = this,
				queueNames = _.keyBy(queues, 'id'),
				statuses = self.normalizeStatuses(rawStatuses);

			return _.map(agents, function(agent) {
				var agentId = agent.id || agent._id,
					status = statuses[agentId] || 'unknown',
					agentStats = stats[agentId] || {},
					queueLabels = _.map(agent.queues || [], function(queueId) {
						return _.get(queueNames, [queueId, 'name'], queueId);
					});

				return {
					id: agentId,
					name: self.getAgentName(agent),
					status: status,
					statusClass: self.statusClass(status),
					queues: queueLabels.join(', '),
					answered: agentStats.answered_calls || 0,
					missed: agentStats.missed_calls || 0,
					total: agentStats.total_calls || 0
				};
			});
		},

		normalizeStatuses: function(rawStatuses) {
			var normalized = {};

			_.each(rawStatuses || {}, function(value, agentId) {
				var candidates;

				if (_.isString(value)) {
					normalized[agentId] = value;
					return;
				}
				if (value && value.status) {
					normalized[agentId] = value.status;
					return;
				}

				candidates = _.values(value || {});
				candidates = _.sortBy(candidates, function(candidate) {
					return -(parseInt(candidate.timestamp, 10) || 0);
				});
				normalized[agentId] = _.get(candidates, '[0].status', 'unknown');
			});

			return normalized;
		},

		statusClass: function(status) {
			if (status === 'pause' || status === 'paused') {
				return 'paused';
			}
			if (status === 'logout' || status === 'logged_out' || status === 'unknown') {
				return 'offline';
			}
			return 'online';
		},

		getAgentName: function(agent) {
			var name;

			if (!agent) {
				return '-';
			}
			name = $.trim((agent.first_name || '') + ' ' + (agent.last_name || ''));
			return name || agent.username || agent.email || agent.id || agent._id || '-';
		},

		bindAgentEvents: function(view, generation, accountId) {
			var self = this;

			view.find('.acdc-refresh').on('click', function() {
				self.renderAgents();
			});
			view.find('.acdc-agent-action').on('click', function() {
				var button = $(this),
					row = button.closest('tr'),
					agentId = button.data('id'),
					status = button.data('status'),
					payload = { status: status },
					timeout;

				if (status === 'pause') {
					timeout = parseInt(row.find('.acdc-pause-timeout').val(), 10);
					payload.timeout = timeout > 0 ? timeout : 300;
				}
				row.find('button').prop('disabled', true);
				self.request('acdc.agents.setStatus', {
					agentId: agentId,
					data: payload
				}, function(error) {
					if (!self.isCurrentView(generation, 'agents', accountId)) {
						return;
					}
					if (error) {
						row.find('button').prop('disabled', false);
						self.toastError(error);
						return;
					}
					self.toastSuccess(self.i18n.active().acdc.agents.statusSent);
					setTimeout(function() {
						if (self.isCurrentView(generation, 'agents', accountId)) {
							self.renderAgents();
						}
					}, 500);
				});
			});
		},

		toastSuccess: function(message) {
			monster.ui.toast({ type: 'success', message: message });
		},

		toastError: function(message) {
			monster.ui.toast({ type: 'error', message: message });
		}
	};

	return app;
});
