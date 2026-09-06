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
		announcementLocales: ['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa'],

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
			'acdc.editor.new': { url: 'accounts/{accountId}/queues/editor', verb: 'GET', generateError: false },
			'acdc.editor.get': { url: 'accounts/{accountId}/queues/{queueId}/editor', verb: 'GET', generateError: false },
			'acdc.editor.create': { url: 'accounts/{accountId}/queues/editor', verb: 'PUT', generateError: false },
			'acdc.editor.update': { url: 'accounts/{accountId}/queues/{queueId}/editor', verb: 'PATCH', generateError: false },
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
			'acdc.agents.queueMemberships': {
				url: 'accounts/{accountId}/agents/{agentId}/queue_status', verb: 'GET', generateError: false
			},
			'acdc.agents.queueLogin': {
				url: 'accounts/{accountId}/agents/{agentId}/queue_status', verb: 'POST', generateError: false
			},
			'acdc.agents.queueLoginStatus': {
				url: 'accounts/{accountId}/agents/{agentId}/queue_status?runtime_only=true&queue_id={queueId}&action=login',
				verb: 'GET', generateError: false
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

			self.clearLiveDashboardTimer();
			self.closeAgentQueueLogin();
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

				if (item.is_prompt && match && item.language === match[1] && match[2].indexOf('acdc-number-') !== 0) {
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

		requiredLanguagePromptIds: function() {
			return _.map(_.range(10), function(key) { return 'acdc-callback-offer-' + key; })
				.concat(_.map(['menu-current', 'menu-alternate', 'number-readback', 'confirmation', 'success', 'returned-confirmation'],
					function(name) { return 'acdc-callback-' + name; }))
				.concat(_.map(['your-current-position-is', 'you_are_at_position', 'in_the_queue', 'increase_in_call_volume',
					'the_estimated_wait_time_is', 'less_than_1_minute', 'about_5_minutes', 'about_10_minutes',
					'about_15_minutes', 'about_30_minutes', 'about_45_minutes', 'about_1_hour', 'at_least_1_hour'],
				function(name) { return 'acdc-queue-' + name; }));
		},

		validLanguageCapabilities: function(manifest) {
			var self = this,
				required = self.requiredLanguagePromptIds().sort(),
				flags = ['ready', 'position', 'wait_time', 'callback', 'native_speaker_review'],
				legacy = _.get(manifest, 'backend_mode') === 'legacy';

			return _.isPlainObject(manifest) && manifest.schema_version === 1
				&& (manifest.backend_mode === undefined || legacy)
				&& (!legacy || _.isEqual(_.keys(manifest).sort(), ['schema_version', 'backend_mode', 'generated_at', 'languages'].sort()))
				&& typeof manifest.generated_at === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$/.test(manifest.generated_at)
				&& isFinite(Date.parse(manifest.generated_at))
				&& _.isPlainObject(manifest.languages)
				&& _.isEqual(_.keys(manifest.languages).sort(), self.announcementLocales.slice().sort())
				&& _.every(self.announcementLocales, function(locale) {
					var entry = manifest.languages[locale], prerecorded = locale === 'ar-sa' || locale === 'he-il';

					if (!_.isPlainObject(entry) || !_.every(flags,
						function(key) { return typeof entry[key] === 'boolean'; })) { return false; }
					if (legacy) {
						return _.isEqual(_.keys(entry).sort(), flags.slice().sort())
							&& _.every(flags, function(key) { return entry[key] === false; });
					}
					if (!entry.ready) { return true; }
					return entry.position && entry.wait_time && entry.callback
						&& entry.numbers === (prerecorded ? 'prerecorded' : 'native_say')
						&& _.isEqual(entry.number_range, [0, 999999999])
						&& entry.numeric_prompt_count === (prerecorded ? 2999 : 0)
						&& _.isArray(entry.required_prompt_ids) && _.every(entry.required_prompt_ids, function(id) { return typeof id === 'string'; })
						&& _.isEqual(entry.required_prompt_ids.slice().sort(), required)
						&& /^[a-f0-9]{64}$/.test(entry.source_catalog_sha256 || '')
						&& /^[a-f0-9]{64}$/.test(entry.installed_media_sha256 || '');
				});
		},

		loadLanguageCapabilities: function(callback) {
			var self = this;

			$.ajax({ url: self.appPath + '/language-capabilities.json',
				dataType: 'json',
				cache: false,
				timeout: 10000,
				success: function(manifest) {
					callback(self.validLanguageCapabilities(manifest) ? null : self.i18n.active().acdc.dropdowns.capabilitiesUnavailable, manifest);
				},
				error: function() {
					// Absence and runtime failures are not proof of a legacy backend.
					callback(self.i18n.active().acdc.dropdowns.capabilitiesUnavailable, null);
				}
			});
		},

		// These records are projected only after server-side immutable document
		// provenance checks. A purpose name by itself is never an alias or proof.
		verifiedGeminiEnglishPurposes: function(media) {
			var self = this, required = self.requiredBuiltinCallbackPromptIds(),
				mapHash = 'a316e74ff278ae53750781e57fe49fca0e61f50c626ef84278afc470fb02f974';

			return _.map(_.filter(media, function(item) {
				return _.isPlainObject(item) && item.language === 'en-us' && item.has_attachments === true
					&& item.import_metadata_verified === true
					&& item.source_type === 'kazoo5_acdc_gemini_voice_installer'
					&& item.source_map_sha256 === mapHash
					&& typeof item.sha256 === 'string' && /^[a-f0-9]{64}$/.test(item.sha256)
					&& required.indexOf(item.canonical_prompt_id) >= 0
					&& item.prompt_id === item.canonical_prompt_id + '-gemini-sulafat-' + item.sha256.slice(0, 16)
					&& item.id === 'en-us/' + item.prompt_id;
			}), 'canonical_prompt_id');
		},

		requiredBuiltinFixedPromptIds: function() {
			return this.requiredLanguagePromptIds().concat(['acdc-callback-unavailable',
				'acdc-callback-invalid-entry', 'acdc-callback-enter-number']);
		},

		requiredBuiltinCallbackPromptIds: function() {
			return this.requiredBuiltinFixedPromptIds().concat(_.map(_.range(10), function(digit) {
				return 'acdc-number-' + digit;
			}));
		},

		editableSystemMedia: function(media) {
			// Keep all ten digit projections available to readiness checks, but
			// never offer internal numeric chunks in hold/pre-connect selectors.
			return _.filter(media, function(item) {
				return !/\/acdc-number-/.test(item.id || '') && !/^acdc-number-/.test(item.canonical_prompt_id || '');
			});
		},

		languageCapabilityOptions: function(manifest, media, loadError) {
			var self = this, labels = self.i18n.active().acdc.dropdowns,
				ids = _.map(media, 'id'),
				valid = self.validLanguageCapabilities(manifest),
				legacy = valid && manifest.backend_mode === 'legacy',
				fixedRequired = self.requiredLanguagePromptIds(),
				geminiPurposes = self.verifiedGeminiEnglishPurposes(media),
				legacyRequired = _.map(_.filter(fixedRequired, function(id) {
					return id.indexOf('acdc-queue-') === 0 && id !== 'acdc-queue-your-current-position-is';
				}), function(id) { return id.slice(5); }).concat(['agent-invalid_choice', 'menu-invalid_entry', 'cf-enter_number']),
				legacyIds = _.map(_.filter(media, function(item) {
					return _.isPlainObject(item) && item.language === 'en-us' && item.has_attachments === true;
				}), 'id');

			return _.map(self.announcementLocales, function(locale) {
				var entry = valid ? manifest.languages[locale] : null,
					ready = !loadError && valid && (legacy ? locale === 'en-us' && _.every(legacyRequired, function(id) {
						return legacyIds.indexOf('en-us/' + id) >= 0;
					}) && _.every(self.requiredBuiltinCallbackPromptIds(), function(id) { return geminiPurposes.indexOf(id) >= 0; })
						: entry.ready && _.every(entry.required_prompt_ids, function(id) {
						return ids.indexOf(locale + '/' + id) >= 0;
					})),
					reviewPending = ready && locale !== 'en-us' && entry.native_speaker_review === false;

				return { value: locale,
					disabled: !ready,
					ready: Boolean(ready),
					label: labels.languages[locale] + ' — ' + (ready ? labels.languageReady : labels.languageNotInstalled)
						+ (reviewPending ? ' — ' + labels.nativeReviewPending : '') };
			});
		},

		selectionOptions: function(items, current, emptyLabel, currentLabel) {
			var options = [{ value: '', label: emptyLabel }].concat(items),
				value = current === undefined || current === null ? '' : String(current);

			if (value && !_.some(options, function(item) { return item.value === value; })) {
				options.push({ value: value, label: currentLabel, preserved: true });
			}
			return _.map(options, function(item) {
				var selected = item.value === value;

				return _.assign({}, item, { selected: selected }, selected && item.disabled
					? { disabled: false, preserved: true, label: item.label + ' — ' + currentLabel } : {});
			});
		},

		queueLanguageOptions: function(items, current) {
			var selected = this.announcementLocales.indexOf(current) >= 0 ? current : 'en-us';
			// Never add an inherit/custom sixth option or re-enable an unready pack.
			return _.map(this.announcementLocales, function(locale) {
				return _.assign({ label: locale, ready: false, disabled: true },
					_.find(items, { value: locale }), { value: locale, selected: locale === selected });
			});
		},

		queueLanguageSelection: function(items, current, original) {
			var options = this.queueLanguageOptions(items, current),
				selected = _.find(options, { selected: true }).value,
				ready = _.map(_.filter(options, function(item) {
					return item.ready === true && item.disabled === false;
				}), 'value');
			return { original: original, selected: selected, ready: ready, adopt: ready.indexOf(selected) >= 0 };
		},

		populateQueueDropdowns: function(view, queue, results, errors, isEdit) {
			var self = this,
				labels = self.i18n.active().acdc.dropdowns,
				form = view.find('.acdc-queue-form'),
				systemMedia = results.verifiedSystemMedia || [],
				media = _.map(results.media || [], function(item) {
					return { value: item.id, label: labels.accountMedia + ': ' + (item.name || item.id) };
				}).concat(_.chain(self.editableSystemMedia(systemMedia))
					.groupBy(function(item) { return item.id.split('/').slice(1).join('/'); })
					.map(function(entries, id) {
						return { value: id,
							label: labels.systemPrompt + ': ' + (entries[0].name || id)
							+ ' (' + _.uniq(_.map(entries, 'language')).sort().join(', ') + ')' };
					}).value()),
				languages = self.languageCapabilityOptions(results.languageCapabilities === undefined ? null : results.languageCapabilities,
					systemMedia, errors.languageCapabilities || errors.systemMedia),
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
							.prop('disabled', Boolean(item.disabled))
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
			var languageSelect = form.find('[name="announcements.language"]'),
				languageOptions = self.queueLanguageOptions(languages, _.get(queue, 'announcements.language'));

			languageSelect.empty();
			_.each(languageOptions, function(item) {
				$('<option>').val(item.value).text(item.label).prop('selected', item.selected)
					.prop('disabled', Boolean(item.disabled)).appendTo(languageSelect);
			});
			languageSelect.prop('disabled', Boolean(errors.systemMedia || errors.languageCapabilities));
			form.data('queue-language-selection', self.queueLanguageSelection(languages,
				_.get(queue, 'announcements.language'), _.get(results.queue, 'announcements.language')));
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
			form.data('catalog-errors', Boolean(errors.media || errors.systemMedia || errors.numbers || errors.languageCapabilities));
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
				_.each([{ direction: -1, label: labels.moveEarlier }, { direction: 1, label: labels.moveLater }], function(action) {
					$('<button>').attr({ type: 'button', 'data-direction': action.direction, 'aria-label': action.label + ': ' + name })
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
			this.renderLiveDashboard(null, pGeneration);
		},

		clearLiveDashboardTimer: function() {
			if (this.appFlags.acdc.liveDashboardTimer) {
				clearTimeout(this.appFlags.acdc.liveDashboardTimer);
				delete this.appFlags.acdc.liveDashboardTimer;
			}
		},

		// Isolated read seam. The current API is a recent, single-responder subset,
		// NOT the complete live collector. No history/performance or write requests.
		requestLiveDashboard: function(queueId, callback) {
			var self = this, results = {}, errors = {},
				requests = [{ key: 'queues', resource: 'acdc.queues.list', complete: true },
					{ key: 'queueStats', resource: 'acdc.queues.stats', envelope: true }], pending;

			if (queueId) {
				requests = requests.concat([{ key: 'roster', resource: 'acdc.queues.roster', complete: true, data: { queueId: encodeURIComponent(queueId) } },
					{ key: 'agents', resource: 'acdc.agents.list', complete: true },
					{ key: 'statuses', resource: 'acdc.agents.statuses' }]);
			}
			pending = requests.length;
			_.each(requests, function(item) {
				var request = item.complete ? self.requestCompleteList : (item.envelope ? self.requestEnvelope : self.request);
				request.call(self, item.resource, item.data || {}, function(error, data) {
					if (item.envelope && !error) {
						if (!data || (data.status && data.status !== 'success')
							|| _.some(['next_start_key', 'next_cursor'], function(key) {
								return data[key] !== undefined && data[key] !== null && data[key] !== '';
							})) { error = true; }
						data = _.get(data, 'data');
					}
					if (error) { errors[item.key] = true; } else { results[item.key] = data; }
					if (--pending === 0) { callback(errors, results); }
				});
			});
		},

		liveQueueInventoryValid: function(queues) {
			return _.isArray(queues) && queues.length <= 1000
				&& _.every(queues, function(queue) {
					return _.isPlainObject(queue) && typeof queue.id === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(queue.id);
				}) && _.uniq(_.map(queues, 'id')).length === queues.length;
		},

		liveQueueName: function(queue) {
			return typeof queue.name === 'string' && queue.name.trim() && queue.name.length <= 256 ? queue.name : queue.id;
		},

		liveStatsSnapshot: function(raw, failed) {
			var self = this, seen = {}, valid = !failed && _.isPlainObject(raw)
				&& _.isArray(raw.stats) && raw.stats.length <= 10000
				&& typeof raw.current_timestamp === 'number' && isFinite(raw.current_timestamp)
				&& Math.floor(raw.current_timestamp) === raw.current_timestamp
				&& raw.current_timestamp >= self.kazooEpochOffsetSeconds
				&& raw.current_timestamp <= Math.floor(Date.now() / 1000) + self.kazooEpochOffsetSeconds + 60;

			valid = valid && _.every(raw.stats, function(row) {
				var key;
				if (!_.isPlainObject(row) || typeof row.queue_id !== 'string' || typeof row.call_id !== 'string'
					|| !row.call_id || !row.queue_id || row.call_id.length > 256 || row.queue_id.length > 128
					|| ['waiting', 'handled', 'processed', 'abandoned'].indexOf(row.status) < 0) { return false; }
				key = JSON.stringify([row.queue_id, row.call_id]);
				if (Object.prototype.hasOwnProperty.call(seen, key)) { return false; }
				seen[key] = true;
				return true;
			});
			return { available: Boolean(valid), rows: valid ? raw.stats : [], asOf: valid ? raw.current_timestamp : null };
		},

		liveDuration: function(start, end) {
			if (typeof start !== 'number' || typeof end !== 'number' || !isFinite(start) || !isFinite(end)
				|| Math.floor(start) !== start || Math.floor(end) !== end || start < this.kazooEpochOffsetSeconds || end < start) { return '—'; }
			var seconds = end - start, minutes = Math.floor(seconds / 60);
			return (minutes < 60 ? minutes : Math.floor(minutes / 60) + ':' + ('0' + minutes % 60).slice(-2))
				+ ':' + ('0' + seconds % 60).slice(-2);
		},

		formatLiveDashboard: function(results, errors, meta) {
			var self = this, labels = self.i18n.active().acdc.dashboard, queueId = meta.queueId,
				stats = self.liveStatsSnapshot(results.queueStats, errors.queueStats),
				queues = _.sortBy(_.map(results.queues, function(queue) {
					return { id: queue.id, name: self.liveQueueName(queue) };
				}), function(queue) { return queue.name.toLowerCase(); }),
				selected = _.find(queues, { id: queueId }), statuses = !errors.statuses && _.isPlainObject(results.statuses)
					? self.normalizeStatuses(results.statuses) : {},
				agents = !errors.agents && _.isArray(results.agents) ? results.agents : [],
				rosterValid = !errors.roster && _.isArray(results.roster) && results.roster.length <= 1000
					&& _.every(results.roster, function(id) { return typeof id === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(id); })
					&& _.uniq(results.roster).length === results.roster.length,
				rows = _.filter(stats.rows, function(row) { return row.queue_id === queueId && ['waiting', 'handled'].indexOf(row.status) >= 0; }),
				cards = _.map(queues, function(queue) {
					var own = _.filter(stats.rows, { queue_id: queue.id });
					return { id: queue.id, name: queue.name || queue.id,
						waiting: stats.available ? _.filter(own, { status: 'waiting' }).length : '—',
						handling: stats.available ? _.filter(own, { status: 'handled' }).length : '—' };
				}), age = Math.max(Date.now() - meta.receivedAt, stats.asOf === null ? 0
					: Date.now() - (stats.asOf - self.kazooEpochOffsetSeconds) * 1000),
				stale = Boolean(meta.refreshFailed || age >= 30000),
				warnings = [];

			if (!stats.available) { warnings.push(labels.statsUnavailable); }
			if (queueId && !rosterValid) { warnings.push(labels.rosterUnavailable); }
			if (queueId && (errors.agents || !_.isArray(results.agents))) { warnings.push(labels.namesUnavailable); }
			if (queueId && (errors.statuses || !_.isPlainObject(results.statuses))) { warnings.push(labels.statusUnavailable); }
			return {
				queueRows: cards, queueCount: queues.length, hasQueues: queues.length > 0,
				queue: selected, detail: Boolean(queueId), queueMissing: Boolean(queueId && !selected),
				selectedCard: _.find(cards, { id: queueId }), available: stats.available,
				updating: Boolean(meta.updating), stale: stale, refreshFailed: Boolean(meta.refreshFailed),
				freshness: meta.updating ? labels.refreshing : (stale ? labels.stale : labels.snapshot),
				retrievedAt: new Date(meta.receivedAt).toLocaleTimeString(),
				responseTime: stats.asOf === null ? '—' : new Date((stats.asOf - self.kazooEpochOffsetSeconds) * 1000).toLocaleTimeString(),
				staleAfter: Math.max(1, 30000 - age),
				warnings: warnings, hasWarnings: warnings.length > 0, rosterAvailable: rosterValid,
				rosterCount: rosterValid ? results.roster.length : '—',
				callsTruncated: rows.length > 200, membersTruncated: rosterValid && results.roster.length > 200,
				members: rosterValid ? _.map(results.roster.slice(0, 200), function(id) {
					var agent = _.find(agents, function(item) { return item && (item.id || item._id) === id; }),
						status = statuses[id];
					return { id: id, name: agent ? self.getAgentName(agent) : id,
						status: typeof status === 'string' && Object.prototype.hasOwnProperty.call(labels.statuses, status)
							? labels.statuses[status] : labels.statuses.unknown };
				}) : [],
				calls: _.map(_.sortBy(rows, 'entered_timestamp').slice(0, 200), function(row) {
					var agent = _.find(agents, function(item) { return item && (item.id || item._id) === row.agent_id; });
					return { status: labels.callStatuses[row.status], statusClass: row.status === 'waiting' ? 'waiting' : 'handling',
						caller: [row.caller_id_name, row.caller_id_number].filter(function(value) { return typeof value === 'string' && value; }).join(' · ') || '—',
						agent: agent ? self.getAgentName(agent) : (row.agent_id || '—'),
						wait: self.liveDuration(row.entered_timestamp, row.status === 'waiting' ? stats.asOf : row.handled_timestamp),
						talk: row.status === 'handled' ? self.liveDuration(row.handled_timestamp, stats.asOf) : '—' };
				})
			};
		},

		renderLiveDashboard: function(queueId, pGeneration) {
			var self = this, generation = self.newGeneration(pGeneration), accountId = self.accountId,
				cache = self.appFlags.acdc.liveDashboardSnapshot,
				previous = cache && cache.accountId === accountId && cache.queueId === queueId ? cache : null;

			self.clearLiveDashboardTimer();
			if (previous) { self.mountLiveDashboard(previous, generation, { updating: true }); }
			else { self.renderLoading(self.i18n.active().acdc.states.loadingDashboard); }
			self.requestLiveDashboard(queueId, function(errors, results) {
				if (!self.isCurrentView(generation, 'dashboard', accountId)) { return; }
				if (errors.queues || !self.liveQueueInventoryValid(results.queues)) {
					if (previous) { self.mountLiveDashboard(previous, generation, { refreshFailed: true }); }
					else { self.renderError(self.i18n.active().acdc.dashboard.inventoryUnavailable, function() { self.renderLiveDashboard(queueId); }); }
					return;
				}
				var snapshot = { accountId: accountId, queueId: queueId, receivedAt: Date.now(), results: results, errors: errors };
				self.appFlags.acdc.liveDashboardSnapshot = snapshot;
				self.mountLiveDashboard(snapshot, generation, {});
			});
		},

		mountLiveDashboard: function(snapshot, generation, state) {
			var self = this, labels = self.i18n.active().acdc.dashboard,
				model = self.formatLiveDashboard(snapshot.results, snapshot.errors, _.assign({}, snapshot, state)),
				view = $(self.getTemplate({ name: snapshot.queueId ? 'dashboard-detail' : 'dashboard', data: model }));

			self.clearLiveDashboardTimer();
			view.find('.acdc-refresh').on('click', function() { self.renderLiveDashboard(snapshot.queueId); });
			view.find('.acdc-live-back').on('click', function() { self.renderDashboard(); });
			view.find('.acdc-open-live-queue').on('click', function() {
				var id = $(this).attr('data-queue-id');
				if (_.some(snapshot.results.queues, { id: id })) { self.renderLiveDashboard(id); }
			});
			view.find('.acdc-live-edit, .acdc-live-add').on('click', function() {
				self.clearLiveDashboardTimer();
				self.appFlags.acdc.currentTab = 'queues';
				self.appFlags.acdc.container.find('.acdc-tab').removeClass('active');
				self.appFlags.acdc.container.find('.acdc-tab[data-tab="queues"]').addClass('active');
				self.renderQueueForm($(this).hasClass('acdc-live-add') ? undefined : snapshot.queueId);
			});
			view.find('.acdc-live-agents').on('click', function() { self.renderSection('agents'); });
			view.find('.acdc-live-search').on('input', function() {
				var query = $(this).val().toLowerCase().trim(), visible = 0;
				view.find('.acdc-live-queue-card').each(function() {
					var show = $(this).find('.acdc-live-queue-name').text().toLowerCase().indexOf(query) >= 0;
					$(this).prop('hidden', !show); if (show) { visible++; }
				});
				view.find('.acdc-live-no-match').prop('hidden', visible > 0 || !model.hasQueues);
			});
			self.getContentContainer().empty().append(view);
			if (!model.stale) {
				self.appFlags.acdc.liveDashboardTimer = setTimeout(function() {
					if (!self.isCurrentView(generation, 'dashboard', snapshot.accountId)) { return; }
					view.find('.acdc-live-freshness').addClass('is-stale').text(labels.stale);
					view.find('.acdc-live-stale-note').prop('hidden', false);
				}, model.staleAfter);
			}
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
				status_label: reconciliationRequired
					? (labels.reconciliation_required || 'Recovery pending') : underlyingStatusLabel,
				status_class: reconciliationRequired ? 'reconciling' : 'neutral',
				reconciliation_required: reconciliationRequired,
				reconciliation_detail: reconciliationRequired
					? (reasonLabels[item.reconciliation_reason] || callbackI18n.reconciliationGeneric
						|| 'Call state is being verified; no new attempt will be placed.') : '',
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

		renderQueueForm: function(queueId, draft, preloaded) {
			var self = this,
				generation = ++self.appFlags.acdc.requestGeneration,
				accountId = self.accountId,
				editorRevisions,
				baseErrors,
				baseResults,
				inventoryError,
				inventory,
				languageCapabilities,
				languageCapabilitiesError,
				pending = 1,
				finish;

			self.renderLoading(self.i18n.active().acdc.states.loadingQueue);
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
				results.languageCapabilities = languageCapabilities;
				if (languageCapabilitiesError) { errors.languageCapabilities = languageCapabilitiesError; }
				queue = self.normalizeQueueCallback(_.merge(self.defaultQueue(), results.queue || {}));
				if (draft) { queue = _.merge(self.defaultQueue(), self.mergeEditorDraft(queue, draft.queue)); }
				roster = results.roster || queue.agents || [];
				if (draft && draft.roster !== null) { roster = draft.roster; }
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
						self.renderQueueForm(queueId, draft);
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
						legacyPromptOverrides: self.hasLegacyPromptOverrides(queue),
						users: users,
						rosterWarning: rosterState.warning,
						rosterReadOnly: rosterReadOnly,
						routeExtension: draft && draft.route !== null ? draft.route.extension : _.get(ownedRoute, 'numbers[0]', ''),
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
				view.data('editor-revisions', editorRevisions);
				self.populateQueueDropdowns(view, queue, results, errors, Boolean(queueId));
				if (_.get(draft, 'queue.announcements.media') === null && _.get(draft, 'queue.callback.media') === null) {
					var draftLanguage = view.find('.acdc-queue-form').data('queue-language-selection');
					draftLanguage.adopt = draftLanguage.ready.indexOf(draftLanguage.selected) >= 0;
				}
				self.renderAgentOrder(view, queue.agent_order || []);
				self.bindQueueForm(view, queueId, generation, accountId);
				self.getContentContainer().empty().append(view);
				if (draft) { self.showFormError(view, 'Saved state reloaded. Your unsaved entries were retained; review them before saving again.'); }
			};

			var receive = function(error, result) {
				var state = self.queueEditorState(result, error);

				baseErrors = state.errors;
				baseResults = state.results;
				inventory = _.get(result, 'callflows');
				inventoryError = state.errors.callflows;
				languageCapabilities = _.get(result, 'language_capabilities');
				languageCapabilitiesError = state.errors.systemMedia;
				editorRevisions = _.get(result, 'revisions');
				finish();
			};
			if (preloaded) { receive(null, preloaded); }
			else { self.request(queueId ? 'acdc.editor.get' : 'acdc.editor.new', queueId ? { queueId: queueId } : {}, receive); }
		},

		queueEditorState: function(data, loadError) {
			var errors = {}, results = {}, unavailable = loadError || 'The complete queue editor data is unavailable. Reload before making changes.';

			if (loadError || !_.isPlainObject(data) || !_.isPlainObject(data.queue) || !_.isArray(data.roster)
				|| !_.isPlainObject(data.revisions) || !_.isPlainObject(data.revisions.users)
				|| !_.isPlainObject(data.revisions.callflows) || !_.has(data.revisions, 'queue')) {
				return { errors: { queue: unavailable, users: unavailable }, results: {} };
			}
			_.each({ users: 'users', media: 'media', numbers: 'numbers', system_media: 'systemMedia', callflows: 'callflows' }, function(target, source) {
				if (_.get(data, ['catalogs', source, 'complete']) !== true
					|| (source === 'callflows' ? !_.isArray(_.get(data, 'callflows.summaries')) || !_.isArray(_.get(data, 'callflows.routes')) : !_.isArray(data[source]))) {
					errors[target] = unavailable + ' (' + source + ': ' + _.get(data, ['catalogs', source, 'reason'], 'invalid') + ')';
				}
			});
			results = { queue: data.queue, roster: data.roster, users: data.users, media: data.media,
				numbers: data.numbers, verifiedSystemMedia: data.system_media };
			if (errors.users) { errors.roster = errors.users; }
			return { errors: errors, results: results };
		},

		mergeEditorDraft: function(current, patch) {
			var self = this, merged = _.cloneDeep(current);

			_.each(patch, function(value, key) {
				if (value === null) { delete merged[key]; }
				else if (_.isPlainObject(value)) {
					merged[key] = self.mergeEditorDraft(_.isPlainObject(merged[key]) ? merged[key] : {}, value);
				} else { merged[key] = _.cloneDeep(value); }
			});
			return merged;
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
					announcement: {
						enabled: true,
						initial_delay: 30,
						interval: 60
					},
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

		hasLegacyPromptOverrides: function(queue) {
			var defaults = this.defaultQueue().announcements.media;

			return _.some(defaults, function(value, key) {
				var current = _.get(queue, 'announcements.media.' + key);

				return Boolean(current && current !== value);
			}) || _.some(_.get(queue, 'callback.media', {}), function(value) { return Boolean(value); });
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
			form.find('[name="announcements.language"]').on('change', function() {
				var selection = form.data('queue-language-selection'), value = $(this).val();
				if (selection && selection.ready.indexOf(value) >= 0) {
					selection.selected = value;
					selection.adopt = true;
				}
			});
			form.find('[name="callback.enabled"], [name="callback.caller_id_source"], [name="callback.announcement.enabled"]').on('change', function() {
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
				callbackError = self.queueLanguageSelectionError(form, Boolean(view.data('queue-id') || queueId))
					|| self.callbackKeyError(form) || self.callbackSelectionError(form);
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
				announcementEnabled = form.find('[name="callback.announcement.enabled"]').is(':checked'),
				custom = form.find('[name="callback.caller_id_source"]').val() === 'custom',
				inherit = form.find('[name="callback.caller_id_source"]').val() === 'inherit';

			form.find('.acdc-callback-required').prop('required', enabled);
			form.find('.acdc-callback-number').prop('required', enabled && custom);
			form.find('.acdc-callback-announcement-timing').prop('disabled', !enabled || !announcementEnabled);
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

		queueLanguageSelectionError: function(form, isEdit) {
			var selection = form.data('queue-language-selection');
			return selection && !isEdit && selection.ready.indexOf(selection.selected) < 0
				? this.i18n.active().acdc.dropdowns.languageNotInstalled : null;
		},

		serializeQueue: function(form, isEdit) {
			var announcementDefaults = this.defaultQueue().announcements.media,
				announcementMedia = function(key) {
					// The queue schema requires all four media keys. An empty legacy
					// value means the backend's standard prompt, not empty audio.
					return $.trim(form.find('[name="announcements.media.' + key + '"]').val())
						|| announcementDefaults[key];
				},
				integerValue = function(name) {
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
					announcement: {
						enabled: form.find('[name="callback.announcement.enabled"]').is(':checked')
					},
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
							you_are_at_position: announcementMedia('you_are_at_position'),
							in_the_queue: announcementMedia('in_the_queue'),
							the_estimated_wait_time_is: announcementMedia('the_estimated_wait_time_is'),
							increase_in_call_volume: announcementMedia('increase_in_call_volume')
						}
					},
					callback: callbackConfig
				},
				moh = optionalMedia('moh'),
				announce = optionalMedia('announce'),
				announcementLanguage = optionalMedia('announcements.language');

			if (callbackConfig.enabled && callbackConfig.announcement.enabled) {
				callbackConfig.announcement.initial_delay = integerValue('callback.announcement.initial_delay');
				callbackConfig.announcement.interval = integerValue('callback.announcement.interval');
			}
			// Disabled timing fields are omitted so PATCH preserves the stored
			// schedule; schema defaults supply a new queue's 30/60 second timing.
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
			var languageSelection = form.data('queue-language-selection');
			if (languageSelection) {
				// Saving a ready selected language adopts built-ins, including the
				// same language. Unready legacy settings survive unrelated edits.
				var queueLanguage = languageSelection.adopt || !isEdit
					? languageSelection.selected : languageSelection.original;
				if (queueLanguage === undefined) { delete payload.announcements.language; }
				else { payload.announcements.language = queueLanguage; }
				if (languageSelection.adopt && languageSelection.ready.indexOf(queueLanguage) >= 0) {
					// PATCH null is a deletion tombstone, consumed by Crossbar before
					// validation/storage; it is not a stored prompt value. No media
					// document or attachment is deleted, only obsolete queue references.
					if (isEdit) {
						payload.announcements.media = null;
						callbackConfig.media = null;
						callbackConfig.return_confirmation_prompt = null;
					} else {
						delete payload.announcements.media;
						delete callbackConfig.media;
					}
				}
			}
			if (payload.strategy === 'in_order' && !form.data('agent-order-read-only')) {
				payload.agent_order = (form.data('agent-order') || []).slice();
			}

			return payload;
		},

		saveQueue: function(queueId, payload, agentIds, routeExtension, view, generation, accountId) {
			var self = this,
				body = { queue: payload, roster: agentIds, route: routeExtension === null ? null : { extension: routeExtension },
					revisions: view.data('editor-revisions') },
				fingerprint = JSON.stringify(body), pending = view.data('editor-pending'), data;

			if (view.data('editor-recovery-pending')) { return; }
			if (!_.isPlainObject(body.revisions)) {
				self.showFormError(view, 'A complete revision snapshot is required. Reload the queue editor before saving.');
				return;
			}
			if (pending && pending.fingerprint !== fingerprint) {
				self.showFormError(view, 'The previous save outcome must be resolved first. Retry that request or reload saved state using the recovery button; your entries remain in this form.');
				return;
			}
			if (!pending) {
				body.request_id = self.newEditorRequestId();
				pending = { fingerprint: fingerprint, body: body };
				view.data('editor-pending', pending);
			}
			data = { data: pending.body };
			if (queueId) { data.queueId = queueId; }
			self.setFormBusy(view, true);
			self.requestQueueEditor(queueId ? 'acdc.editor.update' : 'acdc.editor.create', data, function(error, result) {
				var operation, savedId;

				if (!self.isCurrentView(generation, 'queues', accountId)) {
					return;
				}
				self.setFormBusy(view, false);
				if (error) {
					operation = _.get(error, 'data', {});
					savedId = queueId || (/^[a-f0-9]{32}$/.test(operation.queue_id || '') ? operation.queue_id : null);
					self.showFormError(view, 'Save was not finalized. ' + self.formatApiError(error)
						+ (operation.phase ? ' Stopped at: ' + operation.phase + '. Some changes may already be saved.' : '')
						+ ' Your entries are retained. No rollback or automatic retry was performed.');
					view.find('.acdc-editor-recovery').remove();
					$('<button>').attr('type', 'button').addClass('monster-button-secondary acdc-editor-recovery')
						.text(savedId ? 'Reload saved state and keep my edits' : 'Retry the identical save safely')
						.on('click', function() {
							if (view.data('editor-recovery-pending')) { return; }
							if (savedId) {
								view.data('editor-recovery-pending', true);
								view.find('[type="submit"], .acdc-editor-recovery').prop('disabled', true);
								// A lost create reply may name a queue that never committed.
								// Prove the replacement editor can load before removing this
								// form or changing its request generation.
								self.request('acdc.editor.get', { queueId: savedId }, function(loadError, snapshot) {
									var state, currentForm, draft;

									if (!self.isCurrentView(generation, 'queues', accountId)
										|| !view[0] || !$.contains(document.documentElement, view[0])) { return; }
									view.removeData('editor-recovery-pending');
									view.find('[type="submit"], .acdc-editor-recovery').prop('disabled', false);
									state = self.queueEditorState(snapshot, loadError);

									if (state.errors.queue || state.errors.users) {
										self.showFormError(view, 'Saved state could not be verified. Your current entries are still here. ' + (state.errors.queue || state.errors.users));
										return;
									}
									// The form stays editable during the GET. Capture its latest
									// values only when the verified replacement is ready.
									currentForm = view.find('.acdc-queue-form');
									if (currentForm.length !== 1) { return; }
									draft = { queue: self.serializeQueue(currentForm, true),
										roster: view.data('roster-read-only') ? null : view.find('.acdc-roster').val() || [],
										route: view.data('route-read-only') ? null : { extension: $.trim(currentForm.find('[name="route_extension"]').val()) } };
									self.renderQueueForm(savedId, draft, snapshot);
								});
							} else { self.saveQueue(queueId, payload, agentIds, routeExtension, view, generation, accountId); }
						}).insertAfter(view.find('.acdc-form-error'));
					return;
				}
				if (!result || result.state !== 'complete' || !/^[a-f0-9]{32}$/.test(result.queue_id || '')) {
					self.showFormError(view, self.i18n.active().acdc.queues.savedMissingId);
					return;
				}
				view.removeData('editor-pending');
				self.toastSuccess(self.i18n.active().acdc.queues.saved);
				self.renderQueues();
			});
		},

		newEditorRequestId: function() {
			var bytes = new Uint8Array(16);

			window.crypto.getRandomValues(bytes);
			return Array.prototype.map.call(bytes, function(value) { return ('0' + value.toString(16)).slice(-2); }).join('');
		},

		requestQueueEditor: function(resource, data, callback) {
			monster.request({ resource: resource, data: _.merge({ accountId: this.accountId }, data),
				success: function(response) { callback(null, response && response.data); },
				error: function(response) { callback(response || { message: 'Queue editor request failed' }); }
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
				this.syncCallbackForm(view.find('.acdc-queue-form'));
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

			self.closeAgentQueueLogin();
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

				view.data('agent-inventory', results.agents || []);
				view.data('queue-inventory', results.queues || []);
				self.bindAgentEvents(view, generation, accountId);
				self.renderAgentQueueSessions(view);
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

		queueLoginChoices: function(memberships, queues) {
			var validId = function(id) { return _.isString(id) && /^[a-f0-9]{32}$/.test(id); },
				queueIds = _.map(queues, function(queue) { return queue && (queue.id || queue._id); });

			if (!_.isArray(memberships) || !_.isArray(queues) || memberships.length > 1000 || queues.length > 1000
				|| !_.every(memberships, validId) || !_.every(queueIds, validId)
				|| _.uniq(memberships).length !== memberships.length || _.uniq(queueIds).length !== queueIds.length
				|| !_.every(memberships, function(id) { return _.includes(queueIds, id); })) {
				return { valid: false, choices: [] };
			}
			return { valid: true, choices: _.map(memberships, function(id) {
				var queue = queues[_.indexOf(queueIds, id)];
				return { id: id, name: queue.name || id };
			}) };
		},

		queueLoginProof: function(data, agentId, queueId) {
			if (!_.isPlainObject(data) || data.agent_id !== agentId || data.queue_id !== queueId || data.action !== 'login'
				|| data.account_id !== this.accountId || data.runtime_only !== true
				|| !_.isBoolean(data.confirmed) || !_.isBoolean(data.runtime_member) || !_.isBoolean(data.runtime_observed)
				|| !_.isString(data.agent_status)) {
				return null;
			}
			if (data.state === 'confirmed' && data.confirmed === true && data.runtime_member === true && data.runtime_observed === true) {
				return { state: 'confirmed', agentStatus: data.agent_status };
			}
			if (data.state === 'pending' && data.confirmed === false) {
				return { state: 'pending', agentStatus: data.agent_status };
			}
			return null;
		},

		agentQueueSession: function(agentId, queueId, value) {
			var flags = this.appFlags.acdc,
				key = this.accountId + ':' + agentId + ':' + queueId,
				entry;

			flags.queueLogins = flags.queueLogins || {};
			if (value) { flags.queueLogins[key] = _.assign({}, value, { checkedAt: Date.now() }); }
			entry = flags.queueLogins[key];
			if (!entry || (entry.state === 'confirmed' && Date.now() - entry.checkedAt > 30000)) {
				return { state: 'unconfirmed' };
			}
			return _.assign({}, entry);
		},

		renderAgentQueueSessions: function(view) {
			var self = this,
				labels = self.i18n.active().acdc.agents,
				queues = _.keyBy(view.data('queue-inventory') || [], 'id'),
				generation = self.appFlags.acdc.requestGeneration,
				accountId = self.accountId,
				hasConfirmed = false;

			_.each(view.data('agent-inventory') || [], function(agent) {
				var agentId = agent.id || agent._id,
					items = _.map(agent.queues || [], function(queueId) {
						var state = self.agentQueueSession(agentId, queueId).state;
						hasConfirmed = hasConfirmed || state === 'confirmed';
						return { name: _.get(queues, [queueId, 'name'], queueId), state: state,
							label: labels[state === 'confirmed' ? 'queueConfirmed' : state === 'pending' ? 'queuePending' : 'queueUnconfirmed'] };
					});

				view.find('.acdc-agent-queue-sessions').filter(function() { return $(this).data('agent-id') === agentId; })
					.html(self.getTemplate({ name: 'agent-queue-sessions', data: { items: items } }));
			});
			clearTimeout(self.appFlags.acdc.queueSessionExpiryTimer);
			if (hasConfirmed) {
				self.appFlags.acdc.queueSessionExpiryTimer = setTimeout(function() {
					if (self.isCurrentView(generation, 'agents', accountId)) { self.renderAgentQueueSessions(view); }
				}, 31000);
			}
		},

		checkAgentQueueLogin: function(agentId, queueId, callback) {
			var self = this,
				accountId = self.accountId;

			self.request('acdc.agents.queueLoginStatus', { agentId: agentId, queueId: queueId }, function(error, data) {
				var proof;
				if (self.accountId !== accountId) { return; }
				proof = !error && self.queueLoginProof(data, agentId, queueId);
				if (!proof) { callback(error || self.i18n.active().acdc.agents.queueProofUnavailable); return; }
				if (proof.state === 'pending' && self.agentQueueSession(agentId, queueId).state !== 'pending') {
					proof.state = 'unconfirmed';
				}
				self.agentQueueSession(agentId, queueId, proof);
				callback(null, proof);
			});
		},

		sendAgentQueueLogin: function(agentId, queueId, callback) {
			var self = this,
				accountId = self.accountId;

			// This is the only Login mutation. Never use global setStatus, roster
			// update, legacy unflagged queue_status, or any other agent's endpoint.
			self.agentQueueSession(agentId, queueId, { state: 'pending' });
			self.request('acdc.agents.queueLogin', { agentId: agentId,
				data: { action: 'login', queue_id: queueId, runtime_only: true }
			}, function(error, data) {
				if (self.accountId !== accountId) { return; }
				if (error) { callback(error); return; }
				if (!_.isPlainObject(data) || data.agent_id !== agentId || data.queue_id !== queueId || data.action !== 'login'
					|| data.account_id !== accountId || data.runtime_only !== true || data.state !== 'pending' || data.confirmed !== false) {
					callback(self.i18n.active().acdc.agents.queueProofUnavailable); return;
				}
				// An accepted command is not confirmation. Only the GET runtime
				// proof can move the selected queue's display to confirmed.
				callback(null);
			});
		},

		closeAgentQueueLogin: function() {
			var dialog = this.appFlags.acdc.queueLoginDialog;
			if (dialog) { dialog.dialog('close'); }
		},

		openAgentQueueLogin: function(view, agentId, generation, accountId) {
			var self = this,
				labels = self.i18n.active().acdc.agents,
				agent = _.find(view.data('agent-inventory') || [], function(item) { return (item.id || item._id) === agentId; }),
				content,
				dialog,
				closed = false,
				choices = [],
				busy = true,
				proofAvailable = false,
				pollTimer,
				selection = 0;

			if (!agent || !/^[a-f0-9]{32}$/.test(agentId) || !self.isCurrentView(generation, 'agents', accountId)) { return; }
			self.closeAgentQueueLogin();
			content = $(self.getTemplate({ name: 'agent-queue-login', data: { agentName: self.getAgentName(agent) } }));
			function active() { return !closed && self.isCurrentView(generation, 'agents', accountId); }
			function selected() { return content.find('.acdc-login-queue').val(); }
			function display(message) {
				var queueId = selected(), state = self.agentQueueSession(agentId, queueId).state;
				content.find('.acdc-login-message').text(message || labels[state === 'confirmed' ? 'queueConfirmed' : state === 'pending' ? 'queuePending' : 'queueUnconfirmed']);
				content.find('.acdc-confirm-queue-login').prop('disabled', busy || !proofAvailable || !queueId || state === 'pending' || state === 'confirmed');
				content.find('.acdc-check-queue-login').prop('disabled', busy || !queueId);
				content.find('.acdc-login-queue').prop('disabled', busy);
				self.renderAgentQueueSessions(view);
			}
			function check(remaining) {
				var queueId = selected(), token = selection;
				if (!active() || busy || !_.some(choices, { id: queueId })) { return; }
				busy = true; display();
				self.checkAgentQueueLogin(agentId, queueId, function(error, proof) {
					if (!active() || token !== selection) { return; }
					busy = false;
					proofAvailable = !error;
					if (error) { display(labels.queueProofUnavailable); return; }
					display();
					if (proof.state === 'confirmed') {
						// Even a closed dialog must expire the visible table proof.
						setTimeout(function() {
							if (self.isCurrentView(generation, 'agents', accountId)) { self.renderAgentQueueSessions(view); }
							if (active() && token === selection) { proofAvailable = false; display(); }
						}, 31000);
					} else if (remaining > 0) {
						pollTimer = setTimeout(function() { check(remaining - 1); }, 1000);
					} else if (proof.state === 'pending') { display(labels.queuePendingCheckAgain); }
				});
			}
			dialog = monster.ui.dialog(content, { title: labels.queueLoginTitle, width: 520, onClose: function() {
				closed = true; clearTimeout(pollTimer);
				if (self.appFlags.acdc.queueLoginDialog === dialog) { self.appFlags.acdc.queueLoginDialog = null; }
			} });
			self.appFlags.acdc.queueLoginDialog = dialog;
			content.find('.acdc-cancel-queue-login').on('click', function() { dialog.dialog('close'); });
			content.find('.acdc-login-queue').on('change', function() {
				selection++; proofAvailable = false; clearTimeout(pollTimer); display(); check(0);
			});
			content.find('.acdc-check-queue-login').on('click', function() { clearTimeout(pollTimer); check(0); });
			content.find('.acdc-confirm-queue-login').on('click', function() {
				var queueId = selected();
				if (!active() || busy || !proofAvailable || !_.some(choices, { id: queueId }) || self.agentQueueSession(agentId, queueId).state !== 'unconfirmed') { return; }
				busy = true; display(labels.queuePending);
				self.sendAgentQueueLogin(agentId, queueId, function(error) {
					if (!active()) { return; }
					busy = false;
					display(error ? labels.queueRequestUncertain : labels.queuePending);
					// Polling only reads; never re-send a login after a timeout.
					if (!error) { check(5); }
				});
			});
			self.requestCompleteList('acdc.agents.queueMemberships', { agentId: agentId }, function(error, memberships) {
				if (!active()) { return; }
				if (error) { display(labels.queueInventoryUnavailable); return; }
				self.requestCompleteList('acdc.queues.list', {}, function(queueError, queues) {
					var inventory = !queueError && self.queueLoginChoices(memberships, queues);
					if (!active()) { return; }
					if (!inventory || !inventory.valid) { display(labels.queueInventoryUnavailable); return; }
					choices = inventory.choices;
					_.each(choices, function(queue) { $('<option>').val(queue.id).text(queue.name).appendTo(content.find('.acdc-login-queue')); });
					busy = false;
					display(choices.length ? labels.chooseQueueHelp : labels.noEligibleQueues);
				});
			});
		},

		bindAgentEvents: function(view, generation, accountId) {
			var self = this;

			view.find('.acdc-refresh').on('click', function() {
				self.renderAgents();
			});
			view.find('.acdc-agent-queue-login').on('click', function() {
				self.openAgentQueueLogin(view, $(this).data('id'), generation, accountId);
			});
			view.find('.acdc-agent-action').on('click', function() {
				var button = $(this),
					row = button.closest('tr'),
					agentId = button.data('id'),
					status = button.data('status'),
					payload = { status: status },
					timeout;

				if (['logout', 'pause', 'resume'].indexOf(status) < 0) { return; }
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
