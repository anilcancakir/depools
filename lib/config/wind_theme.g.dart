// GENERATED: do not edit by hand.
// Regenerate via: dart run magic:artisan design:sync
//
// Source of truth: DESIGN.md

import 'package:flutter/material.dart';

/// Semantic wind alias map generated from DESIGN.md.
///
/// Drop-in for `WindThemeData(aliases: designAliases)`; the
/// keys match the magic_starter token contract.
const Map<String, String> designAliases = <String, String>{
  'bg-surface': 'bg-[#F2F2F7] dark:bg-[#000000]',
  'bg-surface-container': 'bg-[#FFFFFF] dark:bg-[#1C1C1E]',
  'bg-surface-container-high': 'bg-[#E5E5EA] dark:bg-[#2C2C2E]',
  'text-fg': 'text-[#000000] dark:text-[#FFFFFF]',
  'text-fg-muted': 'text-[#5A5A5E] dark:text-[#AEAEB2]',
  'text-fg-disabled': 'text-[#BCBCC0] dark:text-[#545456]',
  'bg-primary': 'bg-[#0040DD] dark:bg-[#409CFF]',
  'text-on-primary': 'text-[#FFFFFF] dark:text-[#00142E]',
  'bg-primary-container': 'bg-[#E3ECFF] dark:bg-[#002357]',
  'bg-accent': 'bg-[#3634A3] dark:bg-[#7D7AFF]',
  'border-color-border': 'border-[#D1D1D6] dark:border-[#3A3A3C]',
  'border-color-border-subtle': 'border-[#E5E5EA] dark:border-[#2C2C2E]',
  'bg-destructive': 'bg-[#D70015] dark:bg-[#FF6961]',
  'text-on-destructive': 'text-[#FFFFFF] dark:text-[#2A0004]',
  'bg-destructive-container': 'bg-[#FFE5E7] dark:bg-[#40000A]',
  'bg-success': 'bg-[#1F7434] dark:bg-[#30DB5B]',
  'bg-warning': 'bg-[#8A3E00] dark:bg-[#FFB340]',
};

/// The brand `primary` color with a generated 50-900 ramp.
///
/// Seeded from the DESIGN.md `primary` light hex; consumed by
/// `WindThemeData.toThemeData()` Material interop.
final Map<String, MaterialColor> designColors =
    <String, MaterialColor>{
  'primary': MaterialColor(
    0xFF0040DD,
    <int, Color>{
      50: Color(0xFFEBF0FC),
      100: Color(0xFFD6E0FA),
      200: Color(0xFFA8BEF3),
      300: Color(0xFF7A9CED),
      400: Color(0xFF4272E6),
      500: Color(0xFF0040DD),
      600: Color(0xFF0038C2),
      700: Color(0xFF0031A8),
      800: Color(0xFF00298D),
      900: Color(0xFF002173),
    }),
};
