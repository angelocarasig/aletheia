//
//  WebRenderer+Capture.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation

extension WebRenderer {
    // taps the page's own traffic - a source whose responses are encrypted on the
    // wire gets nothing useful here and has to hook its own decryption boundary
    // through a preload instead
    enum Capture {
        static func take(from bridge: Bridge) async throws -> String? {
            try await bridge.string("return window.__sniff_take ? window.__sniff_take() : null")
        }

        static func wait(from bridge: Bridge, timeout: Duration) async throws -> String? {
            var waited: Duration = .zero
            var delay: Duration = .milliseconds(200)
            while waited < timeout {
                if let body = try await take(from: bridge) { return body }
                try await Task.sleep(for: delay)
                waited += delay
                delay = min(delay * 2, .seconds(1))
            }
            return nil
        }

        static func storage(_ values: [String: String]) -> String {
            let sets =
                values
                .map { "localStorage.setItem(\(literal($0.key)), \(literal($0.value)));" }
                .joined(separator: " ")
            return "(function(){ try { \(sets) } catch(e){} })();"
        }

        static func literal(_ value: String) -> String {
            let escaped =
                value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }

        // the fetch branch reads a clone(), so the page still gets an unconsumed
        // body. an install guard makes re-injection on the same document a no-op
        static func script(matching pattern: String) -> String {
            """
            (function(){
              if (window.__sniff_installed) return;
              window.__sniff_installed = true;
              var q = [];
              window.__sniff_take = function(){ return q.length ? q.shift() : null; };
              var hit = function(u){ return typeof u === 'string' && u.indexOf('\(pattern)') !== -1; };
              var of = window.fetch;
              window.fetch = function(){
                var a = arguments;
                var u = (a[0] && a[0].url) ? a[0].url : a[0];
                return of.apply(this, a).then(function(r){
                  try { if (hit(u)) r.clone().text().then(function(t){ q.push(t); }); } catch(e){}
                  return r;
                });
              };
              var oo = XMLHttpRequest.prototype.open;
              var os = XMLHttpRequest.prototype.send;
              XMLHttpRequest.prototype.open = function(m, u){ this.__u = u; return oo.apply(this, arguments); };
              XMLHttpRequest.prototype.send = function(){
                var x = this;
                x.addEventListener('load', function(){ try { if (hit(x.__u)) q.push(x.responseText); } catch(e){} });
                return os.apply(this, arguments);
              };
            })();
            """
        }
    }
}
