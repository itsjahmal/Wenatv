import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class AppSettings {
  const AppSettings({
    this.defaultQuality = 'Auto',
    this.autoplayNextEpisode = true,
    this.resumePlayback = true,
    this.preferredAudioLanguage = 'English',
    this.subtitlesEnabled = false,
    this.preferredSubtitleLanguage = 'English',
    this.subtitleScale = 1.0,
    this.themeMode = ThemeMode.dark,
  });

  final String defaultQuality;
  final bool autoplayNextEpisode;
  final bool resumePlayback;
  final String preferredAudioLanguage;
  final bool subtitlesEnabled;
  final String preferredSubtitleLanguage;
  final double subtitleScale;
  final ThemeMode themeMode;

  AppSettings copyWith({
    String? defaultQuality,
    bool? autoplayNextEpisode,
    bool? resumePlayback,
    String? preferredAudioLanguage,
    bool? subtitlesEnabled,
    String? preferredSubtitleLanguage,
    double? subtitleScale,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      defaultQuality: defaultQuality ?? this.defaultQuality,
      autoplayNextEpisode: autoplayNextEpisode ?? this.autoplayNextEpisode,
      resumePlayback: resumePlayback ?? this.resumePlayback,
      preferredAudioLanguage:
          preferredAudioLanguage ?? this.preferredAudioLanguage,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      preferredSubtitleLanguage:
          preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      subtitleScale: subtitleScale ?? this.subtitleScale,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'defaultQuality': defaultQuality,
    'autoplayNextEpisode': autoplayNextEpisode,
    'resumePlayback': resumePlayback,
    'preferredAudioLanguage': preferredAudioLanguage,
    'subtitlesEnabled': subtitlesEnabled,
    'preferredSubtitleLanguage': preferredSubtitleLanguage,
    'subtitleScale': subtitleScale,
    'themeMode': themeMode.name,
  };

  static AppSettings fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return const AppSettings();
    return AppSettings(
      defaultQuality: json['defaultQuality']?.toString() ?? 'Auto',
      autoplayNextEpisode: json['autoplayNextEpisode'] != false,
      resumePlayback: json['resumePlayback'] != false,
      preferredAudioLanguage:
          json['preferredAudioLanguage']?.toString() ?? 'English',
      subtitlesEnabled: json['subtitlesEnabled'] == true,
      preferredSubtitleLanguage:
          json['preferredSubtitleLanguage']?.toString() ?? 'English',
      subtitleScale: (json['subtitleScale'] as num?)?.toDouble() ?? 1.0,
      themeMode: _themeModeFromName(json['themeMode']?.toString()),
    );
  }
}

class AppSettingsController extends Notifier<AppSettings> {
  static const _boxKey = 'app_settings';

  @override
  AppSettings build() {
    if (!Hive.isBoxOpen('wenatv_user')) return const AppSettings();
    return AppSettings.fromJson(Hive.box('wenatv_user').get(_boxKey) as Map?);
  }

  Future<void> update(AppSettings settings) async {
    state = settings;
    await _save();
  }

  Future<void> setDefaultQuality(String value) =>
      update(state.copyWith(defaultQuality: value));

  Future<void> setAutoplayNextEpisode(bool value) =>
      update(state.copyWith(autoplayNextEpisode: value));

  Future<void> setResumePlayback(bool value) =>
      update(state.copyWith(resumePlayback: value));

  Future<void> setPreferredAudioLanguage(String value) =>
      update(state.copyWith(preferredAudioLanguage: value));

  Future<void> setSubtitlesEnabled(bool value) =>
      update(state.copyWith(subtitlesEnabled: value));

  Future<void> setPreferredSubtitleLanguage(String value) =>
      update(state.copyWith(preferredSubtitleLanguage: value));

  Future<void> setSubtitleScale(double value) =>
      update(state.copyWith(subtitleScale: value.clamp(.75, 1.35)));

  Future<void> setThemeMode(ThemeMode value) =>
      update(state.copyWith(themeMode: value));

  Future<void> _save() async {
    if (!Hive.isBoxOpen('wenatv_user')) return;
    await Hive.box('wenatv_user').put(_boxKey, state.toJson());
  }
}

ThemeMode _themeModeFromName(String? name) {
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ThemeMode.dark,
  );
}
