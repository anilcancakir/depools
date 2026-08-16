import '../../../app/models/location_node.dart';


/// The demo location tree.
///
/// **Data, not copy.** These names and their pre-formatted meta lines (`5 ürün · 2 alt konum`)
/// stand in for rows the backend will supply, and a user's own location name is not translated, so
/// neither are these. They lived inside the view until the hardcoded-copy guard flagged them, which
/// was the right catch for the wrong reason: they were correctly untranslated and incorrectly
/// placed, since every other screen keeps its fixtures in a file like this one.
///
/// The meta strings become computed values when the backend lands, at which point they turn into
/// catalogue keys like every other count in the app.
///
/// **The icons and colours are stored NAMES**, matching `locations.icon` and `locations.colour`,
/// and are resolved through `location_appearance.dart`. They were `IconData` constants here until
/// the appearance columns landed, which made this file the only place in the app holding a glyph
/// rather than the name of one. Two nodes deliberately carry no colour, because both columns are
/// nullable and the fallback has to be on screen somewhere to be seen.
const List<LocationNode> locationTree = <LocationNode>[
  LocationNode(
    name: 'Mutfak',
    path: 'Mutfak',
    depth: 0,
    productCount: 5,
    summary: '5 ürün · 2 alt konum',
    icon: 'countertops',
    colour: 'red',
  ),
  LocationNode(
    name: 'Buzdolabı',
    path: 'Mutfak › Buzdolabı',
    depth: 1,
    productCount: 3,
    summary: '3 ürün',
    icon: 'kitchen',
    colour: 'blue',
  ),
  LocationNode(
    name: 'Derin dondurucu',
    path: 'Mutfak › Derin dondurucu',
    depth: 1,
    productCount: 1,
    summary: '1 ürün',
    icon: 'ac_unit',
    colour: 'teal',
  ),
  LocationNode(
    name: 'Kiler',
    path: 'Kiler',
    depth: 0,
    productCount: 4,
    summary: '4 ürün · 3 alt konum',
    icon: 'dining',
    colour: 'amber',
  ),
  LocationNode(
    name: 'Raf 1',
    path: 'Kiler › Raf 1',
    depth: 1,
    productCount: 1,
    summary: '1 ürün',
    icon: 'shelves',
    colour: 'green',
  ),
  LocationNode(
    name: 'Raf 2',
    path: 'Kiler › Raf 2',
    depth: 1,
    productCount: 2,
    summary: '2 ürün',
    icon: 'shelves',
    colour: 'green',
  ),
  LocationNode(
    name: 'Çekmece 2',
    path: 'Kiler › Çekmece 2',
    depth: 1,
    productCount: 1,
    summary: '1 ürün',
    icon: 'inbox',
  ),
  LocationNode(
    name: 'Depo',
    path: 'Depo',
    depth: 0,
    productCount: 2,
    summary: '2 ürün · 1 alt konum',
    icon: 'warehouse',
    colour: 'violet',
  ),
  LocationNode(
    name: 'Raf A',
    path: 'Depo › Raf A',
    depth: 1,
    productCount: 2,
    summary: '2 ürün',
    icon: 'shelves',
    colour: 'red',
  ),
  LocationNode(
    name: 'Raf B',
    path: 'Depo › Raf B',
    depth: 1,
    productCount: 0,
    summary: 'Boş',
    icon: 'shelves',
  ),
];
