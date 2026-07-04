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

        async function trackEvent(eventType, properties) {
          await loadRecaptcha();
          var recaptchaToken = await getRecaptchaToken(eventType);

          var payload = {
            event_type: eventType,
            page_url: window.location.href,
            referrer: document.referrer,
            user_agent: navigator.userAgent,
            fingerprint: getClientFingerprint(),
            properties: properties || {},
            recaptcha_token: recaptchaToken
          };

          var body = JSON.stringify(payload);
          var timestamp = Math.floor(Date.now() / 1000).toString();
          var message = timestamp + '.' + body;

          var encoder = new TextEncoder();
          var keyData = encoder.encode(apiKey);
          var messageData = encoder.encode(message);

          try {
            var cryptoKey = await crypto.subtle.importKey(
              'raw',
              keyData,
              { name: 'HMAC', hash: { name: 'SHA-256' } },
              false,
              ['sign']
            );

            var signatureBuffer = await crypto.subtle.sign(
              'HMAC',
              cryptoKey,
              messageData
            );

            var signatureArray = Array.from(new Uint8Array(signatureBuffer));
            var signatureHex = signatureArray.map(function(b) {
              return b.toString(16).padStart(2, '0');
            }).join('');

            var response = await fetch(baseUrl + '/events/collect', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'X-Site-Id': siteId,
                'X-Api-Key': signatureHex,
                'X-Timestamp': timestamp
              },
              body: body
            });

            return await response.json();
          } catch (e) {
            console.error('Failed to track event:', e);
          }
        }

        if (document.readyState === 'complete') {
          trackEvent('pageview');
        } else {
          window.addEventListener('load', function() {
            trackEvent('pageview');
          });
        }
      })();
    JAVASCRIPT
  end
  # rubocop:enable Metrics/MethodLength
end
# rubocop:enable Metrics/ClassLength
