import 'package:flutter/material.dart' show Icons;

import 'location_index_view.dart' show LocationNode;

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
const List<LocationNode> locationTree = <LocationNode>[
  LocationNode(
    name: 'Mutfak',
    path: 'Mutfak',
    depth: 0,
    productCount: 5,
    summary: '5 ürün · 2 alt konum',
    icon: Icons.kitchen_outlined,
  ),
  LocationNode(
    name: 'Buzdolabı',
    path: 'Mutfak › Buzdolabı',
    depth: 1,
    productCount: 3,
    summary: '3 ürün',
    icon: Icons.kitchen_outlined,
  ),
  LocationNode(
    name: 'Derin dondurucu',
    path: 'Mutfak › Derin dondurucu',
    depth: 1,
    productCount: 1,
    summary: '1 ürün',
    icon: Icons.ac_unit_outlined,
  ),
  LocationNode(
    name: 'Kiler',
    path: 'Kiler',
    depth: 0,
    productCount: 4,
    summary: '4 ürün · 3 alt konum',
    icon: Icons.shelves,
  ),
  LocationNode(
    name: 'Raf 1',
    path: 'Kiler › Raf 1',
    depth: 1,
    productCount: 1,
    summary: '1 ürün',
    icon: Icons.shelves,
  ),
  LocationNode(
    name: 'Raf 2',
    path: 'Kiler › Raf 2',
    depth: 1,
    productCount: 2,
    summary: '2 ürün',
    icon: Icons.shelves,
  ),
  LocationNode(
    name: 'Çekmece 2',
    path: 'Kiler › Çekmece 2',
    depth: 1,
    productCount: 1,
    summary: '1 ürün',
    icon: Icons.inbox_outlined,
  ),
  LocationNode(
    name: 'Depo',
    path: 'Depo',
    depth: 0,
    productCount: 2,
    summary: '2 ürün · 1 alt konum',
    icon: Icons.warehouse_outlined,
  ),
  LocationNode(
    name: 'Raf A',
    path: 'Depo › Raf A',
    depth: 1,
    productCount: 2,
    summary: '2 ürün',
    icon: Icons.shelves,
  ),
  LocationNode(
    name: 'Raf B',
    path: 'Depo › Raf B',
    depth: 1,
    productCount: 0,
    summary: 'Boş',
    icon: Icons.shelves,
  ),
];
