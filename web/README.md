# Serving the web build

`lib/config/routing.dart` sets `'url_strategy': 'path'`, so the app's URLs are
`depools.ai/products` rather than `depools.ai/#/products`.

**That choice moves a requirement onto whatever serves this build, and it is not optional.**

With the hash strategy the server only ever sees `/`: everything after the `#` stays in the browser
and is never sent, so any route could be reloaded and any host worked. With the path strategy,
reloading `depools.ai/products` sends a real request for `/products`, and there is no such file. A
static host answers 404 and the app disappears.

**The failure only ever shows up in a deployment**, and development is worse than silent about it: it
looks like it already works.

Measured against `flutter run -d web-server` on this branch. Requesting a deep path returns the app's
own HTML, so a browser opening `localhost:3142/stock-take` cold boots straight into that screen. The
status line, though, is not what a correctly configured host sends:

```
$ curl -sI http://localhost:3142/products/019ff574-e4a1-70b0-86c1-843b2b209ef2
HTTP/1.1 404 Not Found          <- the BODY is index.html; the STATUS is not 200
```

A browser renders a 404 body, so the app appears. A CDN, a health check, a crawler and an error-page
rule do not agree with the browser about what that response means. So "it works locally" is evidence
about the router and no evidence at all about the host: the production rule below has to produce a
**200**, and that is what the check at the bottom of this file asserts.

## The rule: serve `index.html` for every unmatched path

Real files (`main.dart.js`, `assets/`, `canvaskit/`) still have to be served as themselves, so the
fallback goes LAST, after the file lookup.

### nginx

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

### Caddy

```
try_files {path} /index.html
```

### Apache

```apache
<Directory "/var/www/depools">
    RewriteEngine On
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule ^ index.html [L]
</Directory>
```

### Netlify (`_redirects`)

```
/*  /index.html  200
```

### Vercel (`vercel.json`)

```json
{ "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }] }
```

## Checking it rather than assuming it

Build, serve, and request a nested path directly. A 200 carrying HTML is the answer; a 404 or a
directory listing means the rewrite is not in force:

```sh
flutter build web
curl -sI https://depools.ai/products | head -1        # HTTP/2 200
curl -s  https://depools.ai/products | head -c 40     # <!DOCTYPE html>
```

Do it against a nested path (`/products/some-uuid`) as well as a top-level one. A rewrite scoped to
one segment passes the first check and fails the second.

## `<base href>`

`index.html` carries `<base href="$FLUTTER_BASE_HREF">`, which `flutter build web` substitutes.
Serving from a subdirectory means passing it: `flutter build web --base-href /app/`. Left at `/`
while the app is served from `/app/`, every asset request goes to the wrong place and the page
renders blank with no error a user could describe.
