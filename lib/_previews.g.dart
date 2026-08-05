// GENERATED: do not edit by hand.
// Regenerate via: dart run magic:artisan previews:refresh
//
// Source: *.preview.dart files discovered under the scan dir.

import 'package:magic_devtools/preview.dart';
import 'preview/bottom_menu.preview.dart';
import 'preview/dashboard_screen.preview.dart';
import 'preview/foundations.preview.dart';
import 'preview/login_screen.preview.dart';
import 'preview/profile_screen.preview.dart';
import 'preview/register_screen.preview.dart';
import 'preview/settings_screen.preview.dart';
import 'preview/sidebar_menu.preview.dart';
import 'preview/teams_screen.preview.dart';
import 'ui/components/callout/callout.preview.dart';
import 'ui/components/stat_card/stat_card.preview.dart';
import 'ui/components/tag/tag.preview.dart';

List<PreviewEntry> previewEntries() {
  return <PreviewEntry>[
    PreviewEntry(
      label: 'BottomMenu',
      slug: 'bottom_menu',
      builder: (_) => const BottomMenuPreview(),
    ),
    PreviewEntry(
      label: 'Callout',
      slug: 'callout',
      builder: (_) => const CalloutPreview(),
    ),
    PreviewEntry(
      label: 'DashboardScreen',
      slug: 'dashboard_screen',
      builder: (_) => const DashboardScreenPreview(),
    ),
    PreviewEntry(
      label: 'Foundations',
      slug: 'foundations',
      builder: (_) => const FoundationsPreview(),
    ),
    PreviewEntry(
      label: 'LoginScreen',
      slug: 'login_screen',
      builder: (_) => const LoginScreenPreview(),
    ),
    PreviewEntry(
      label: 'ProfileScreen',
      slug: 'profile_screen',
      builder: (_) => const ProfileScreenPreview(),
    ),
    PreviewEntry(
      label: 'RegisterScreen',
      slug: 'register_screen',
      builder: (_) => const RegisterScreenPreview(),
    ),
    PreviewEntry(
      label: 'SettingsScreen',
      slug: 'settings_screen',
      builder: (_) => const SettingsScreenPreview(),
    ),
    PreviewEntry(
      label: 'SidebarMenu',
      slug: 'sidebar_menu',
      builder: (_) => const SidebarMenuPreview(),
    ),
    PreviewEntry(
      label: 'StatCard',
      slug: 'stat_card',
      builder: (_) => const StatCardPreview(),
    ),
    PreviewEntry(
      label: 'Tag',
      slug: 'tag',
      builder: (_) => const TagPreview(),
    ),
    PreviewEntry(
      label: 'TeamsScreen',
      slug: 'teams_screen',
      builder: (_) => const TeamsScreenPreview(),
    ),
  ];
}

