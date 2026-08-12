/// Routing Configuration.
///
/// Controls URL strategy and other routing behavior.
/// See: https://magic.fluttersdk.com/docs/basics/routing#url-strategy
///
/// ### Why `path` rather than the default hash
///
/// `depools.ai/products` instead of `depools.ai/#/products`. The hash form is a browser trick from
/// before the History API and it reads as one: a URL a user copies out of the address bar is part of
/// the product's surface, and `/#/` announces that the page is a single-file app rather than a
/// place. It also puts the whole route beyond the reach of anything that reads a URL server-side.
///
/// **This has a hosting requirement and it is not optional.** With the hash strategy the server only
/// ever sees `/`, so any route could be reloaded. With `path`, reloading `depools.ai/products` sends
/// a real request for `/products`, and a static host answers 404 unless it is told to serve
/// `index.html` for every unmatched path. `web/README.md` carries the rule per host; getting it
/// wrong looks like "the app works until you refresh", which is a report nobody files clearly.
///
/// `flutter run` handles it already, so the failure only ever shows up in a deployment.
Map<String, dynamic> get routingConfig => {
  'routing': {
    'url_strategy': 'path',
  },
};
