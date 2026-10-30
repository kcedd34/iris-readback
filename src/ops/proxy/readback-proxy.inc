# Shared by every forwarded location. The request is stateless: no cookie goes up, none comes back, and the headers
# that name the server product are dropped. The platform's own Authorization challenge is dropped so a browser never
# shows its native sign-in dialog.
# One upstream connection per request (HTTP/1.0 to the platform): the platform web server answered 404 to a correctly
# authenticated request that followed one with other credentials on the same kept-alive connection (observed in
# feature 5, the proxy check and the sign-in).
proxy_http_version 1.0;
proxy_set_header Host $host;
proxy_set_header Cookie "";
proxy_set_header Connection "close";
proxy_hide_header Set-Cookie;
proxy_hide_header Server;
proxy_hide_header WWW-Authenticate;
proxy_hide_header X-Powered-By;
proxy_hide_header Content-Security-Policy;
proxy_read_timeout 15s;
proxy_connect_timeout 5s;

# Errors of the platform are replaced by fixed bodies. Code 400 is left out on purpose: a 400 from the product is its own
# short English validation message (the server level covers 400 for errors nginx itself raises).
error_page 401 = @e401;
error_page 403 = @e403;
error_page 404 = @e404;
error_page 405 = @e405;
error_page 413 = @e413;
error_page 414 = @e414;
error_page 429 = @e429;
error_page 500 501 502 503 504 = @e5xx;
