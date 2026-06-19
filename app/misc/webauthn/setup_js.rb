# frozen_string_literal: true

module Webauthn
  # Drop-in replacement for Rodauth's built-in webauthn setup JS, served via
  # `webauthn_setup_js`. Identical credential ceremony, but the catch block gives
  # a friendly message when the authenticator refuses a duplicate
  # (`InvalidStateError` — this device already holds a passkey for the account;
  # Rodauth sends excludeCredentials to trigger this) instead of a raw error.
  module SetupJs
    SOURCE = <<~JS
      (function() {
        var pack = function(v) { return btoa(String.fromCharCode.apply(null, new Uint8Array(v))).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=/g, ''); };
        var unpack = function(v) { return Uint8Array.from(atob(v.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)); };
        var element = document.getElementById('webauthn-setup-form');
        var button = document.getElementById('webauthn-setup-button');
        var f = function(e) {
          e.preventDefault();
          if (navigator.credentials) {
            var opts = JSON.parse(element.getAttribute("data-credential-options"));
            opts.challenge = unpack(opts.challenge);
            opts.user.id = unpack(opts.user.id);
            opts.excludeCredentials.forEach(function(cred) { cred.id = unpack(cred.id); });
            navigator.credentials.create({publicKey: opts}).
              then(function(cred){
                var rawId = pack(cred.rawId);
                document.getElementById('webauthn-setup').value = JSON.stringify({
                  type: cred.type,
                  id: rawId,
                  rawId: rawId,
                  response: {
                    attestationObject: pack(cred.response.attestationObject),
                    clientDataJSON: pack(cred.response.clientDataJSON)
                  }
                });
                // Remember on this browser that it registered this passkey, so
                // the manage page can badge it "This device" and hide "Add".
                try {
                  var key = "move.passkeys." + (element.getAttribute("data-account-key") || "");
                  var ids = JSON.parse(localStorage.getItem(key) || "[]");
                  if (ids.indexOf(rawId) === -1) { ids.push(rawId); }
                  localStorage.setItem(key, JSON.stringify(ids));
                } catch (err) { /* localStorage unavailable — server badge still works */ }
                element.removeEventListener("submit", f);
                element.submit();
              }).
              catch(function(e){
                if (e && e.name === "InvalidStateError") {
                  button.innerHTML = "This device already has a passkey for your account \\u2014 use it to sign in, or add a different device.";
                } else {
                  button.innerHTML = "Couldn't add a passkey on this device: " + e;
                }
              });
          } else {
            button.innerHTML = "WebAuthn not supported by browser, or browser has disabled it on this page";
          }
        };
        element.addEventListener("submit", f);
      })();
    JS
  end
end
