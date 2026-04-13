import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import '../widgets/omi_device_section.dart';
import '../widgets/server_settings_section.dart';
import '../widgets/transcription_service_section.dart';
import '../widgets/transcription_settings_section.dart';
import '../widgets/about_section.dart';
import '../widgets/settings_card.dart';
import '../widgets/tts_service_section.dart';

/// Settings screen for Parachute Daily v2
///
/// Sections:
/// - Vault Server (URL + API key)
/// - Transcription Mode (auto / server / local)
/// - Transcription Service / Scribe (URL + optional API key)
/// - TTS / Narrate (URL + optional API key)
/// - Omi Device (mobile only)
/// - About
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        elevation: 0,
      ),
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      body: ListView(
        padding: EdgeInsets.all(Spacing.lg),
        children: [
          // Server URL
          SettingsCard(
            isDark: isDark,
            child: const ServerSettingsSection(),
          ),
          SizedBox(height: Spacing.xl),

          // Transcription Mode
          SettingsCard(
            isDark: isDark,
            child: const TranscriptionSettingsSection(),
          ),

          // Transcription Service / Scribe
          SizedBox(height: Spacing.xl),
          SettingsCard(
            isDark: isDark,
            child: const TranscriptionServiceSection(),
          ),

          // TTS / Narrate (Read Aloud)
          SizedBox(height: Spacing.xl),
          SettingsCard(
            isDark: isDark,
            child: const TtsServiceSection(),
          ),

          // Omi Device (iOS/Android only)
          if (Platform.isIOS || Platform.isAndroid) ...[
            SizedBox(height: Spacing.xl),
            SettingsCard(
              isDark: isDark,
              child: const OmiDeviceSection(),
            ),
          ],

          SizedBox(height: Spacing.xl),

          // About
          SettingsCard(
            isDark: isDark,
            child: const AboutSection(),
          ),

          SizedBox(height: Spacing.xxl),
        ],
      ),
    );
  }
}
