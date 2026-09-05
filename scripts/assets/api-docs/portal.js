'use strict';
// No operations, external validation, analytics, OAuth, or persisted credentials.
(() => {
    const allowed = new Set(['openapi.json', 'planned.openapi.json']);
    function show(file) {
        if (!allowed.has(file)) throw new Error('Unknown local catalog');
        const planned = file === 'planned.openapi.json';
        document.getElementById('current').setAttribute('aria-pressed', String(!planned));
        document.getElementById('planned').setAttribute('aria-pressed', String(planned));
        document.getElementById('catalog-status').textContent = planned
            ? 'PLANNED ONLY — these routes are not implemented or deployed. Do not call them.'
            : 'Source catalog selected. Some upstream contracts are generic; inspect per-operation review labels.';
        window.kazooApiDocs = SwaggerUIBundle({
            url: new URL(file, window.location.href).href, dom_id: '#swagger-ui',
            presets: [SwaggerUIBundle.presets.apis], layout: 'BaseLayout',
            plugins: [() => ({statePlugins: {auth: {wrapActions: {
                authorize: () => () => {}, authorizeOauth2: () => () => {},
                showDefinitions: () => () => {}
            }}}})],
            deepLinking: false, queryConfigEnabled: false, supportedSubmitMethods: [],
            tryItOutEnabled: false, validatorUrl: null, persistAuthorization: false,
            withCredentials: false, displayRequestDuration: false, docExpansion: 'none',
            defaultModelsExpandDepth: -1, showExtensions: true,
            requestInterceptor(request) {
                const url = new URL(request.url, window.location.href);
                const permitted = [...allowed].some(name => url.href === new URL(name, window.location.href).href);
                if (String(request.method || 'GET').toUpperCase() !== 'GET' || url.origin !== window.location.origin || !permitted) {
                    throw new Error('This documentation viewer cannot execute API requests.');
                }
                request.credentials = 'omit';
                delete request.headers.Authorization;
                delete request.headers['X-Auth-Token'];
                return request;
            }
        });
    }
    document.getElementById('current').addEventListener('click', () => show('openapi.json'));
    document.getElementById('planned').addEventListener('click', () => show('planned.openapi.json'));
    show('openapi.json');
})();
