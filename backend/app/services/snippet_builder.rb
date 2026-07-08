# Builds the embeddable tracking snippet (JS) for a site. Extracted out of the
# Site model to keep that class within its configured length and to isolate the
# single responsibility of assembling the snippet string.
#
# Metrics/ClassLength is disabled here because the class is a thin wrapper around
# one large JS template literal — the line count is dominated by the embedded
# client code, not by Ruby logic.
# rubocop:disable Metrics/ClassLength
class SnippetBuilder
  PRODUCTION_BASE_URL = 'https://web-insight-api.up.railway.app/api/v1'.freeze
  DEVELOPMENT_BASE_URL = 'http://localhost:3001/api/v1'.freeze

  def initialize(site)
    @site = site
  end

  def build
    base_url = Rails.env.production? ? PRODUCTION_BASE_URL : DEVELOPMENT_BASE_URL
    recaptcha_site_key = ENV['RECAPTCHA_SITE_KEY'].presence

    render(base_url, recaptcha_site_key)
  end

  private

  # rubocop:disable Metrics/MethodLength
  def render(base_url, recaptcha_site_key)
    <<~JAVASCRIPT.strip
      (function() {
        var siteId = #{@site.id.to_json};
        var apiKey = #{@site.api_key.to_json};
        var baseUrl = #{base_url.to_json};
        var recaptchaSiteKey = #{recaptcha_site_key.to_json};
        var fingerprintStorageKey = 'wia_fp';
        var fallbackFingerprint = null;

        function generateFingerprint() {
          if (window.crypto && window.crypto.randomUUID) {
            return window.crypto.randomUUID();
          }
          var bytes = new Uint8Array(16);
          window.crypto.getRandomValues(bytes);
          return Array.from(bytes).map(function(b) {
            return b.toString(16).padStart(2, '0');
          }).join('');
        }

        // Stable per-browser id so sessionization does not fall back to hashing
        // IP + user agent, which merges distinct visitors behind a shared IP
        // (offices, carrier NAT). Persisted in localStorage; when storage is
        // unavailable (private mode) a per-page-load id is used instead.
        function getClientFingerprint() {
          try {
            var existing = window.localStorage.getItem(fingerprintStorageKey);
            if (existing) { return existing; }
            var generated = generateFingerprint();
            window.localStorage.setItem(fingerprintStorageKey, generated);
            return generated;
          } catch (e) {
            if (!fallbackFingerprint) { fallbackFingerprint = generateFingerprint(); }
            return fallbackFingerprint;
          }
        }

        function loadRecaptcha() {
          return new Promise(function(resolve) {
            if (!recaptchaSiteKey || window.grecaptcha) { resolve(); return; }
            var script = document.createElement('script');
            script.src = 'https://www.google.com/recaptcha/api.js?render=' + encodeURIComponent(recaptchaSiteKey);
            script.onload = function() { resolve(); };
            script.onerror = function() { resolve(); };
            document.head.appendChild(script);
          });
        }

        function getRecaptchaToken(action) {
          return new Promise(function(resolve) {
            if (!recaptchaSiteKey || !window.grecaptcha) { resolve(null); return; }
            window.grecaptcha.ready(function() {
              window.grecaptcha.execute(recaptchaSiteKey, { action: action }).then(
                function(token) { resolve(token); },
                function() { resolve(null); }
              );
            });
          });
        }

        // Assembles the collect payload. Shared by the async (WebCrypto) and the
        // synchronous (unload-path) signers so the two never drift.
        function buildCollectPayload(eventType, properties, recaptchaToken) {
          return {
            event_type: eventType,
            page_url: window.location.href,
            referrer: document.referrer,
            user_agent: navigator.userAgent,
            fingerprint: getClientFingerprint(),
            properties: properties || {},
            recaptcha_token: recaptchaToken
          };
        }

        // Wraps a signed body into the request shape sendSignedRequest expects.
        function signedRequest(body, signatureHex, timestamp) {
          return {
            headers: {
              'Content-Type': 'application/json',
              'X-Site-Id': siteId,
              'X-Api-Key': signatureHex,
              'X-Timestamp': timestamp
            },
            body: body
          };
        }

        // Builds the fully HMAC-signed collect request (headers + body) for an
        // event. Split out of trackEvent so the Web Vitals path can sign a
        // request ahead of unload and fire it later with zero awaits.
        async function buildSignedRequest(eventType, properties, recaptchaToken) {
          var body = JSON.stringify(buildCollectPayload(eventType, properties, recaptchaToken));
          var timestamp = Math.floor(Date.now() / 1000).toString();

          var encoder = new TextEncoder();
          var cryptoKey = await crypto.subtle.importKey(
            'raw',
            encoder.encode(apiKey),
            { name: 'HMAC', hash: { name: 'SHA-256' } },
            false,
            ['sign']
          );

          var signatureBuffer = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(timestamp + '.' + body));
          var signatureHex = Array.from(new Uint8Array(signatureBuffer)).map(function(b) {
            return b.toString(16).padStart(2, '0');
          }).join('');

          return signedRequest(body, signatureHex, timestamp);
        }

        // Synchronous HMAC-SHA256 (hex), computing the exact signature the
        // backend verifies: OpenSSL::HMAC.hexdigest('SHA256', apiKey,
        // timestamp + '.' + body). WebCrypto's subtle.sign is async and a
        // browser will not keep an unloading page alive for its promise, so the
        // unload path needs a synchronous signer to re-sign the final vitals AND
        // fire the keepalive fetch with zero awaits. Cross-checked against
        // OpenSSL for equality (incl. block-boundary lengths and >64B keys).
        function sha256Bytes(bytes) {
          var K = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
          ];
          var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a,
              h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
          var l = bytes.length;
          var bitLen = l * 8;
          var withOne = l + 1;
          var pad = (56 - (withOne % 64) + 64) % 64;
          var total = withOne + pad + 8;
          var msg = new Uint8Array(total);
          msg.set(bytes);
          msg[l] = 0x80;
          msg[total - 4] = (bitLen >>> 24) & 0xff;
          msg[total - 3] = (bitLen >>> 16) & 0xff;
          msg[total - 2] = (bitLen >>> 8) & 0xff;
          msg[total - 1] = bitLen & 0xff;

          var w = new Array(64);
          for (var off = 0; off < total; off += 64) {
            for (var i = 0; i < 16; i++) {
              var j = off + i * 4;
              w[i] = ((msg[j] << 24) | (msg[j + 1] << 16) | (msg[j + 2] << 8) | msg[j + 3]) | 0;
            }
            for (i = 16; i < 64; i++) {
              var x = w[i - 15];
              var s0 = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3);
              var y = w[i - 2];
              var s1 = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10);
              w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, hh = h7;
            for (i = 0; i < 64; i++) {
              var big1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
              var ch = (e & f) ^ (~e & g);
              var t1 = (hh + big1 + ch + K[i] + w[i]) | 0;
              var big0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
              var maj = (a & b) ^ (a & c) ^ (b & c);
              var t2 = (big0 + maj) | 0;
              hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
            }
            h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0;
            h4 = (h4 + e) | 0; h5 = (h5 + f) | 0; h6 = (h6 + g) | 0; h7 = (h7 + hh) | 0;
          }

          var out = new Uint8Array(32);
          var hs = [h0, h1, h2, h3, h4, h5, h6, h7];
          for (i = 0; i < 8; i++) {
            out[i * 4] = (hs[i] >>> 24) & 0xff;
            out[i * 4 + 1] = (hs[i] >>> 16) & 0xff;
            out[i * 4 + 2] = (hs[i] >>> 8) & 0xff;
            out[i * 4 + 3] = hs[i] & 0xff;
          }
          return out;
        }

        function hmacSha256Hex(keyStr, msgStr) {
          var enc = new TextEncoder();
          var key = enc.encode(keyStr);
          if (key.length > 64) { key = sha256Bytes(key); }
          var block = new Uint8Array(64);
          block.set(key);
          var ipad = new Uint8Array(64);
          var opad = new Uint8Array(64);
          for (var i = 0; i < 64; i++) {
            ipad[i] = block[i] ^ 0x36;
            opad[i] = block[i] ^ 0x5c;
          }
          var msg = enc.encode(msgStr);
          var inner = new Uint8Array(64 + msg.length);
          inner.set(ipad);
          inner.set(msg, 64);
          var innerHash = sha256Bytes(inner);
          var outer = new Uint8Array(96);
          outer.set(opad);
          outer.set(innerHash, 64);
          var finalHash = sha256Bytes(outer);
          var hex = '';
          for (i = 0; i < finalHash.length; i++) {
            hex += finalHash[i].toString(16).padStart(2, '0');
          }
          return hex;
        }

        // Synchronous counterpart of buildSignedRequest used only on the unload
        // path (see sha256Bytes note). Uses the pre-acquired reCAPTCHA token so
        // no network or WebCrypto await sits before the keepalive fetch.
        function buildSignedRequestSync(eventType, properties, recaptchaToken) {
          var body = JSON.stringify(buildCollectPayload(eventType, properties, recaptchaToken));
          var timestamp = Math.floor(Date.now() / 1000).toString();
          var signatureHex = hmacSha256Hex(apiKey, timestamp + '.' + body);
          return signedRequest(body, signatureHex, timestamp);
        }

        // Fires an already-signed request. keepalive lets it outlive the page,
        // so this is safe to call synchronously from the unload/pagehide path.
        function sendSignedRequest(request, options) {
          options = options || {};
          return fetch(baseUrl + '/events/collect', {
            method: 'POST',
            headers: request.headers,
            body: request.body,
            keepalive: options.keepalive === true
          });
        }

        async function trackEvent(eventType, properties, options) {
          options = options || {};
          var recaptchaToken;
          // A pre-acquired token (may be null) lets callers skip the reCAPTCHA
          // round-trip — required on the unload path where a network await could
          // be abandoned mid-flight.
          if (Object.prototype.hasOwnProperty.call(options, 'recaptchaToken')) {
            recaptchaToken = options.recaptchaToken;
          } else {
            await loadRecaptcha();
            recaptchaToken = await getRecaptchaToken(eventType);
          }

          try {
            var request = await buildSignedRequest(eventType, properties, recaptchaToken);
            var response = await sendSignedRequest(request, options);
            return await response.json();
          } catch (e) {
            console.error('Failed to track event:', e);
          }
        }

        // Collects Core Web Vitals natively (no external library) and reports
        // them once as a custom event, so the default install populates
        // WebVital rows and the performance report is not empty. Metrics arrive
        // asynchronously (LCP/FID/CLS finalize over the page's life), so values
        // are accumulated and flushed a single time when the page is hidden.
        function reportWebVitals() {
          if (!('PerformanceObserver' in window)) { return; }

          // cls_score starts at null (not measured). It only becomes a number
          // once the layout-shift entry type is confirmed supported below, so
          // browsers that lack it report null instead of a misleading "good" 0.
          var vitals = { lcp_ms: null, fid_ms: null, cls_score: null, ttfb_ms: null, fcp_ms: null };
          var reported = false;
          var observed = [];

          function observe(type, callback) {
            try {
              var observer = new PerformanceObserver(function(list) {
                list.getEntries().forEach(callback);
              });
              observer.observe({ type: type, buffered: true });
              // Keep the callback alongside the observer so flush() can apply it
              // to any records still queued when takeRecords() drains them.
              observed.push({ observer: observer, callback: callback });
              return true;
            } catch (e) {
              // Entry type unsupported in this browser — skip that metric only.
              return false;
            }
          }

          observe('largest-contentful-paint', function(entry) {
            vitals.lcp_ms = Math.round(entry.startTime);
            signalVitalsChanged();
          });
          observe('first-input', function(entry) {
            if (vitals.fid_ms === null) {
              vitals.fid_ms = Math.round(entry.processingStart - entry.startTime);
              signalVitalsChanged();
            }
          });

          // CLS per the Core Web Vitals spec: the maximum session-window sum,
          // where a window breaks on a >1s gap between shifts or after 5s total.
          // A naive lifetime sum overstates CLS on long-lived pages.
          var sessionValue = 0;
          var sessionEntries = [];
          var clsSupported = observe('layout-shift', function(entry) {
            if (entry.hadRecentInput) { return; }
            var first = sessionEntries[0];
            var last = sessionEntries[sessionEntries.length - 1];
            if (sessionEntries.length &&
                entry.startTime - last.startTime < 1000 &&
                entry.startTime - first.startTime < 5000) {
              sessionValue += entry.value;
              sessionEntries.push(entry);
            } else {
              sessionValue = entry.value;
              sessionEntries = [entry];
            }
            if (sessionValue > vitals.cls_score) { vitals.cls_score = sessionValue; }
            signalVitalsChanged();
          });
          // Supported but no shift yet means a real CLS of 0; unsupported stays null.
          if (clsSupported) { vitals.cls_score = 0; }

          observe('paint', function(entry) {
            if (entry.name === 'first-contentful-paint') {
              vitals.fcp_ms = Math.round(entry.startTime);
              signalVitalsChanged();
            }
          });

          try {
            var nav = performance.getEntriesByType('navigation')[0];
            if (nav) { vitals.ttfb_ms = Math.round(nav.responseStart); }
          } catch (e) {
            // Navigation Timing unavailable — leave ttfb_ms null.
          }

          function currentVitals() {
            return {
              lcp_ms: vitals.lcp_ms,
              fid_ms: vitals.fid_ms,
              cls_score: vitals.cls_score === null ? null : Math.round(vitals.cls_score * 10000) / 10000,
              ttfb_ms: vitals.ttfb_ms,
              fcp_ms: vitals.fcp_ms,
              // Tags this ping as the internal vitals event so traffic
              // aggregation can exclude it (its unload-time session must not
              // count as a zero-pageview session). Key kept in sync server-side.
              #{EventCollector::INTERNAL_VITALS_PROPERTY.to_json}: true
            };
          }

          // Keep a fully-signed request ready ahead of unload so flush() can
          // fire it with ZERO awaits — no reCAPTCHA round-trip and no crypto in
          // the unload path, where an await could be abandoned mid-flight. The
          // reCAPTCHA token is pre-acquired (and periodically refreshed, since v3
          // tokens expire ~2min), and the request is re-signed whenever a metric
          // changes so the pre-signed snapshot stays current.
          var vitalsToken = null;
          var preparedRequest = null;
          var preparing = false;
          var dirty = false;

          async function refreshVitalsToken() {
            try {
              await loadRecaptcha();
              vitalsToken = await getRecaptchaToken('custom');
            } catch (e) {
              // Keep the previous token; a stale token still beats no report.
            }
          }

          // Re-signs the pending request from the latest vitals using the already
          // acquired token. Coalesces overlapping calls via the dirty flag so a
          // burst of layout shifts does not spawn parallel signings.
          async function prepareVitalsRequest() {
            if (reported) { return; }
            if (preparing) { dirty = true; return; }
            preparing = true;
            dirty = false;
            try {
              preparedRequest = await buildSignedRequest('custom', currentVitals(), vitalsToken);
            } catch (e) {
              // Keep any previously prepared request; a later change retries.
            } finally {
              preparing = false;
              if (dirty && !reported) { prepareVitalsRequest(); }
            }
          }

          function signalVitalsChanged() {
            prepareVitalsRequest();
          }

          refreshVitalsToken().then(prepareVitalsRequest);
          // Refresh the token before it can expire, then re-sign with it.
          var tokenTimer = setInterval(function() {
            refreshVitalsToken().then(prepareVitalsRequest);
          }, 90000);

          function flush() {
            if (reported) { return; }
            reported = true;
            clearInterval(tokenTimer);
            // Drain records still queued at hide time THROUGH the metric callback
            // so the final LCP candidate / layout shifts update `vitals`, then
            // stop observing. Note whether the drain delivered anything: those
            // callbacks fire signalVitalsChanged(), but it can no longer re-sign
            // now that `reported` is set, so preparedRequest predates any drained
            // value and must be rebuilt from the final vitals below.
            var drainedNewRecords = false;
            observed.forEach(function(pair) {
              try {
                var records = pair.observer.takeRecords();
                if (records.length) { drainedNewRecords = true; }
                records.forEach(pair.callback);
                pair.observer.disconnect();
              } catch (e) {}
            });

            if (drainedNewRecords || preparing || dirty) {
              // preparedRequest is not current: either the drain advanced vitals,
              // or an async re-sign is still in flight (preparing) / pending
              // (dirty) from a metric that changed just before hide, so the last
              // pre-signed snapshot predates it. Re-sign SYNCHRONOUSLY from the
              // last-instant vitals so those metrics are not lost, and fire with
              // ZERO awaits — no WebCrypto/reCAPTCHA promise sits before the
              // keepalive fetch where an unloading page would abandon it. Fall
              // back to the pre-signed snapshot if the sync sign throws.
              try {
                sendSignedRequest(buildSignedRequestSync('custom', currentVitals(), vitalsToken), { keepalive: true });
              } catch (e) {
                if (preparedRequest) {
                  try { sendSignedRequest(preparedRequest, { keepalive: true }); } catch (e2) {}
                }
              }
            } else if (preparedRequest) {
              // Nothing pending and no new records: the continuously re-signed
              // request is current. Fire it with ZERO awaits.
              try { sendSignedRequest(preparedRequest, { keepalive: true }); } catch (e) {}
            } else {
              // Nothing prepared yet (very early hide). Best-effort async path
              // with the pre-acquired token; may be dropped during unload, but
              // better than sending nothing.
              trackEvent('custom', currentVitals(), { keepalive: true, recaptchaToken: vitalsToken });
            }
          }

          document.addEventListener('visibilitychange', function() {
            if (document.visibilityState === 'hidden') { flush(); }
          });
          window.addEventListener('pagehide', flush);
        }

        if (document.readyState === 'complete') {
          trackEvent('pageview');
        } else {
          window.addEventListener('load', function() {
            trackEvent('pageview');
          });
        }

        reportWebVitals();
      })();
    JAVASCRIPT
  end
  # rubocop:enable Metrics/MethodLength
end
# rubocop:enable Metrics/ClassLength
