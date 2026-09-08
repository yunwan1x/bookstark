(function() {
    'use strict';

    function getParam(name, allowed, fallback) {
        var value = '';
        try {
            value = new URLSearchParams(window.location.search).get(name) || '';
        } catch(e) {}
        if (allowed && allowed.length && allowed.indexOf(value) === -1) return fallback || '';
        return value || fallback || '';
    }

    function setParam(name, value, opts) {
        opts = opts || {};
        if (!name || !window.history || !window.history.replaceState) return;
        try {
            var url = new URL(window.location);
            if (value) {
                url.searchParams.set(name, value);
            } else {
                url.searchParams.delete(name);
            }
            if (opts.remove && opts.remove.length) {
                opts.remove.forEach(function(key) { url.searchParams.delete(key); });
            }
            window.history.replaceState(null, '', url.toString());
        } catch(e) {}
    }

    window.BookStarkTabURL = {
        get: getParam,
        set: setParam
    };
})();
