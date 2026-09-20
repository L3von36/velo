"""v2.8.0 security hardening middleware.

Content-Security-Policy for every console response. The console is fully
self-hosted (all assets come from /static/, no CDN), so the policy is tight:
inline script/style stays allowed because Unfold renders inline JSON state
and theme bootstrapping, but everything else is locked to 'self' — no
external script, font, frame or connect exfiltration paths.
"""

CSP_POLICY = (
    "default-src 'self'; "
    # unsafe-eval is REQUIRED: Unfold is Alpine.js-powered and Alpine
    # evaluates x-show/x-bind expressions with new Function(). Without it
    # Alpine dies silently and Unfold's (normally hidden) modal scaffold
    # stays visible, intercepting every click. unsafe-eval only relaxes
    # JS evaluation for OUR OWN inline scripts — external origins stay
    # fully blocked by default-src/script-src/connect-src/frame-ancestors.
    "script-src 'self' 'unsafe-inline' 'unsafe-eval'; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data:; "
    "font-src 'self' data:; "
    "connect-src 'self'; "
    "frame-ancestors 'none'; "
    "base-uri 'self'; "
    "form-action 'self'; "
    "object-src 'none'"
)


class ContentSecurityPolicyMiddleware:
    """Set a conservative Content-Security-Policy header on every response."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        response.headers.setdefault("Content-Security-Policy", CSP_POLICY)
        return response
