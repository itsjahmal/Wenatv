import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/provider_repository.dart';
import '../../shared/widgets/focusable_scale.dart';
import '../home/navigation_rail.dart';
import '../providers/provider_manager_controller.dart';
import 'app_settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _SettingsSection _section = _SettingsSection.providers;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_section != _SettingsSection.providers) {
          setState(() => _section = _SettingsSection.providers);
          return;
        }
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      child: Scaffold(
        body: Row(
          children: [
            const WenaNavigationRail(active: 'Settings'),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.15,
                    colors: [Color(0x221A2B42), WenaTheme.black],
                  ),
                ),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final inset = TvLayout.horizontalInset(size) * .38;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SettingsMenu(
                              selected: _section,
                              onSelected: (value) =>
                                  setState(() => _section = value),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: _SettingsDetail(section: _section)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.selected, required this.onSelected});

  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelected;

  static const items = [
    _SettingsMenuItem(
      _SettingsSection.providers,
      'Provider Manager',
      'Manage and configure providers',
      Icons.extension,
    ),
    _SettingsMenuItem(
      _SettingsSection.playback,
      'Playback Settings',
      'Quality, autoplay and more',
      Icons.play_circle_outline,
    ),
    _SettingsMenuItem(
      _SettingsSection.subtitles,
      'Subtitle Settings',
      'Language and appearance',
      Icons.closed_caption,
    ),
    _SettingsMenuItem(
      _SettingsSection.audio,
      'Audio Settings',
      'Language, output and more',
      Icons.volume_up_outlined,
    ),
    _SettingsMenuItem(
      _SettingsSection.theme,
      'Theme Settings',
      'Theme, colors and UI',
      Icons.palette_outlined,
    ),
    _SettingsMenuItem(
      _SettingsSection.about,
      'About',
      'App version and information',
      Icons.info_outline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * .205).clamp(196.0, 238.0).toDouble();
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(fontSize: 19, height: 1),
          ),
          const SizedBox(height: 5),
          const Text(
            'Manage your app preferences',
            style: TextStyle(color: Colors.white70, fontSize: 10.5),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(right: 2, bottom: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 5),
              itemBuilder: (context, index) => _SettingsCategoryCard(
                item: items[index],
                selected: selected == items[index].section,
                onPressed: () => onSelected(items[index].section),
                autofocus: index == 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCategoryCard extends StatelessWidget {
  const _SettingsCategoryCard({
    required this.item,
    required this.selected,
    required this.onPressed,
    required this.autofocus,
  });

  final _SettingsMenuItem item;
  final bool selected;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableScale(
      autofocus: autofocus,
      borderRadius: 12,
      scale: 1.015,
      onPressed: onPressed,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: selected
              ? LinearGradient(
                  colors: [
                    WenaTheme.red.withValues(alpha: .82),
                    WenaTheme.red.withValues(alpha: .24),
                  ],
                )
              : const LinearGradient(
                  colors: [Color(0xFF111418), Color(0xFF090B0E)],
                ),
          border: Border.all(
            color: selected
                ? WenaTheme.red
                : Colors.white.withValues(alpha: .08),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: WenaTheme.red.withValues(alpha: .18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.black.withValues(alpha: .28)
                    : Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: .05)),
              ),
              child: Icon(
                item.icon,
                color: selected ? WenaTheme.red : Colors.white70,
                size: 17,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SettingsMenuItem {
  const _SettingsMenuItem(this.section, this.title, this.subtitle, this.icon);

  final _SettingsSection section;
  final String title;
  final String subtitle;
  final IconData icon;
}

enum _SettingsSection { providers, playback, subtitles, audio, theme, about }

class _SettingsDetail extends StatelessWidget {
  const _SettingsDetail({required this.section});

  final _SettingsSection section;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      _SettingsSection.providers => const ProviderManagerPanel(),
      _SettingsSection.playback => const _PlaybackSettingsPanel(),
      _SettingsSection.subtitles => const _SubtitleSettingsPanel(),
      _SettingsSection.audio => const _AudioSettingsPanel(),
      _SettingsSection.theme => const _ThemeSettingsPanel(),
      _SettingsSection.about => const _AboutSettingsPanel(),
    };
  }
}

class _SettingsPanelShell extends StatelessWidget {
  const _SettingsPanelShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xE5080A0E),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: WenaTheme.red.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: WenaTheme.red.withValues(alpha: .46),
                    ),
                  ),
                  child: Icon(icon, color: WenaTheme.red, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineLarge?.copyWith(fontSize: 19),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PlaybackSettingsPanel extends ConsumerWidget {
  const _PlaybackSettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    return _SettingsPanelShell(
      icon: Icons.play_circle_outline,
      title: 'Playback Settings',
      subtitle: 'Quality, autoplay, resume and player behavior.',
      children: [
        _OptionGroup(
          title: 'Default video quality',
          options: const ['Auto', '4K', '1080P', '720P', '480P'],
          value: settings.defaultQuality,
          onChanged: controller.setDefaultQuality,
        ),
        _SwitchSettingRow(
          title: 'Autoplay next episode',
          subtitle: 'Continue to the next episode when one is available.',
          value: settings.autoplayNextEpisode,
          onChanged: controller.setAutoplayNextEpisode,
        ),
        _SwitchSettingRow(
          title: 'Resume playback',
          subtitle: 'Keep continue-watching and resume behavior enabled.',
          value: settings.resumePlayback,
          onChanged: controller.setResumePlayback,
        ),
      ],
    );
  }
}

class _SubtitleSettingsPanel extends ConsumerWidget {
  const _SubtitleSettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    return _SettingsPanelShell(
      icon: Icons.closed_caption,
      title: 'Subtitle Settings',
      subtitle: 'Defaults are applied when a stream exposes subtitle files.',
      children: [
        _SwitchSettingRow(
          title: 'Enable subtitles by default',
          subtitle: 'Automatically select your preferred subtitle language.',
          value: settings.subtitlesEnabled,
          onChanged: controller.setSubtitlesEnabled,
        ),
        _OptionGroup(
          title: 'Preferred subtitle language',
          options: const ['English', 'Hindi', 'Spanish', 'French', 'Auto'],
          value: settings.preferredSubtitleLanguage,
          onChanged: controller.setPreferredSubtitleLanguage,
        ),
        _SliderSettingRow(
          title: 'Subtitle size',
          value: settings.subtitleScale,
          min: .75,
          max: 1.35,
          label: '${(settings.subtitleScale * 100).round()}%',
          onChanged: controller.setSubtitleScale,
        ),
      ],
    );
  }
}

class _AudioSettingsPanel extends ConsumerWidget {
  const _AudioSettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return _SettingsPanelShell(
      icon: Icons.volume_up_outlined,
      title: 'Audio Settings',
      subtitle: 'Preferred audio is selected after tracks are detected.',
      children: [
        _OptionGroup(
          title: 'Preferred audio language',
          options: const ['English', 'Hindi', 'Spanish', 'French', 'Auto'],
          value: settings.preferredAudioLanguage,
          onChanged: ref
              .read(appSettingsProvider.notifier)
              .setPreferredAudioLanguage,
        ),
        const _InfoSettingRow(
          title: 'Track switching',
          subtitle:
              'When a stream has multiple audio tracks, the player keeps position and switches without leaving playback.',
        ),
      ],
    );
  }
}

class _ThemeSettingsPanel extends ConsumerWidget {
  const _ThemeSettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return _SettingsPanelShell(
      icon: Icons.palette_outlined,
      title: 'Theme Settings',
      subtitle: 'Choose the app theme preference.',
      children: [
        _OptionGroup<ThemeMode>(
          title: 'Theme mode',
          options: ThemeMode.values,
          value: settings.themeMode,
          labelBuilder: (mode) => switch (mode) {
            ThemeMode.system => 'System',
            ThemeMode.light => 'Light',
            ThemeMode.dark => 'Dark',
          },
          onChanged: ref.read(appSettingsProvider.notifier).setThemeMode,
        ),
      ],
    );
  }
}

class _AboutSettingsPanel extends StatelessWidget {
  const _AboutSettingsPanel();

  @override
  Widget build(BuildContext context) {
    return const _SettingsPanelShell(
      icon: Icons.info_outline,
      title: 'About WenaTV',
      subtitle: 'App information and disclaimer.',
      children: [
        _InfoSettingRow(title: 'App name', subtitle: 'WenaTV'),
        _InfoSettingRow(title: 'Version', subtitle: '1.0.0'),
        _InfoSettingRow(title: 'Build', subtitle: '1'),
        _InfoSettingRow(
          title: 'Description',
          subtitle:
              'A cinematic Android TV streaming interface with TMDB metadata and user-managed content providers.',
        ),
        _InfoSettingRow(
          title: 'Developer',
          subtitle: 'Made with love by Steven Collins',
        ),
        _SupportDeveloperCard(),
        _InfoSettingRow(
          title: 'Disclaimer',
          subtitle:
              'Providers are user-managed. WenaTV does not bundle provider sources or host media streams.',
        ),
      ],
    );
  }
}

class _OptionGroup<T> extends StatelessWidget {
  const _OptionGroup({
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelBuilder,
  });

  final String title;
  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T value)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return _SettingBlock(
      title: title,
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final option in options)
            _ChoicePill(
              label: labelBuilder?.call(option) ?? option.toString(),
              selected: option == value,
              onPressed: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}

class _SwitchSettingRow extends StatelessWidget {
  const _SwitchSettingRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FocusableSettingRow(
      onPressed: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: _SettingText(title: title, subtitle: subtitle),
          ),
          Switch(
            value: value,
            activeThumbColor: WenaTheme.red,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SliderSettingRow extends StatelessWidget {
  const _SliderSettingRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FocusableSettingRow(
      child: Row(
        children: [
          Expanded(
            child: _SettingText(title: title, subtitle: label),
          ),
          SizedBox(
            width: 220,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: 6,
              activeColor: WenaTheme.red,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportDeveloperCard extends StatelessWidget {
  const _SupportDeveloperCard();

  @override
  Widget build(BuildContext context) {
    return FocusableScale(
      borderRadius: 12,
      scale: 1.012,
      onPressed: () {},
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              WenaTheme.red.withValues(alpha: .14),
              Colors.white.withValues(alpha: .045),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WenaTheme.red.withValues(alpha: .28)),
          boxShadow: [
            BoxShadow(
              color: WenaTheme.red.withValues(alpha: .08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: WenaTheme.red.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: WenaTheme.red.withValues(alpha: .32)),
              ),
              child: const Icon(
                Icons.local_cafe_outlined,
                color: WenaTheme.red,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Support the Developer',
                    style: TextStyle(
                      fontSize: 12.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Enjoying WenaTV? You can support future improvements by buying the developer a coffee.',
                    style: TextStyle(color: Colors.white70, fontSize: 10.5),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'PayPal',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 9.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'radiomagik62@gmail.com',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSettingRow extends StatelessWidget {
  const _InfoSettingRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _FocusableSettingRow(
      child: _SettingText(title: title, subtitle: subtitle),
    );
  }
}

class _SettingBlock extends StatelessWidget {
  const _SettingBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _FocusableSettingRow extends StatelessWidget {
  const _FocusableSettingRow({required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FocusableScale(
      borderRadius: 10,
      scale: 1.012,
      onPressed: onPressed ?? () {},
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: child,
      ),
    );
  }
}

class _SettingText extends StatelessWidget {
  const _SettingText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FocusableScale(
      borderRadius: 999,
      scale: 1.018,
      onPressed: onPressed,
      child: Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected ? WenaTheme.red : Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? WenaTheme.red
                : Colors.white.withValues(alpha: .1),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(fontSize: 10.8, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class ProviderManagerPanel extends ConsumerStatefulWidget {
  const ProviderManagerPanel({super.key});

  @override
  ConsumerState<ProviderManagerPanel> createState() =>
      _ProviderManagerPanelState();
}

class _ProviderManagerPanelState extends ConsumerState<ProviderManagerPanel> {
  final _controller = TextEditingController(text: 'vega-org');
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addRepository() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await ref
          .read(providerManagerProvider.notifier)
          .addRepository(_controller.text);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repos = ref.watch(providerManagerProvider);
    final active = ref.watch(activeProviderProvider);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xE5080A0E),
        border: Border.all(color: Colors.white.withValues(alpha: .11)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .46),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ProviderHeader(),
              const SizedBox(height: 9),
              Text(
                'Default Provider',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 11.2,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 5),
              _DefaultProviderBox(active: active),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  return Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      SizedBox(
                        width: compact ? constraints.maxWidth : 330,
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(fontSize: 12),
                          onSubmitted: (_) => _addRepository(),
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Provider repository',
                            hintText: 'vega-org or GitHub provider URL',
                            prefixIcon: const Icon(Icons.link, size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: .05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: .08),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: .08),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _CompactActionButton(
                        label: _adding ? 'Checking' : 'Add Provider',
                        icon: _adding ? Icons.sync : Icons.add,
                        primary: true,
                        onPressed: _addRepository,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Installed Providers',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 13.5),
              ),
              const SizedBox(height: 7),
              if (repos.isEmpty)
                const _EmptyProviderState()
              else
                for (final repo in repos) ...[
                  _ProviderTile(repo: repo),
                  const SizedBox(height: 7),
                ],
              const _ProviderTip(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 37,
          height: 37,
          decoration: BoxDecoration(
            color: WenaTheme.red.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: WenaTheme.red.withValues(alpha: .55)),
          ),
          child: const Icon(Icons.extension, color: WenaTheme.red, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Provider Manager',
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 2),
              const Text(
                'Install, manage and configure content providers.',
                style: TextStyle(color: Colors.white70, fontSize: 10.8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DefaultProviderBox extends StatelessWidget {
  const _DefaultProviderBox({required this.active});

  final ActiveProviderSelection? active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_border, color: Colors.white, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              active?.displayName ?? 'No provider selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white70,
            size: 19,
          ),
        ],
      ),
    );
  }
}

class _EmptyProviderState extends StatelessWidget {
  const _EmptyProviderState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: const Text(
        'No providers bundled. Add a repository to begin.',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }
}

class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({required this.repo});

  final ProviderRepositoryModel repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeProviderProvider);
    final statusColor = _statusColor(repo.status);
    final installedProviders = repo.availableProviders
        .where((provider) => provider.installed)
        .length;
    final activeForRepo = active?.sourceUrl == repo.sourceUrl;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activeForRepo
              ? WenaTheme.red
              : Colors.white.withValues(alpha: .08),
        ),
        gradient: const LinearGradient(
          colors: [Color(0xFF101317), Color(0xFF080A0D)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: .34)),
                ),
                child: Icon(Icons.extension, color: statusColor, size: 19),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            repo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.headlineMedium?.copyWith(fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _StatusPill(
                          label: repo.enabled ? 'Active' : 'Inactive',
                          color: repo.enabled
                              ? Colors.greenAccent
                              : Colors.white54,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      children: [
                        _InlineStat(
                          Icons.view_list_outlined,
                          '${repo.availableProviders.length} Providers',
                        ),
                        _InlineStat(
                          Icons.download_done,
                          '$installedProviders Installed',
                        ),
                        _InlineStat(
                          Icons.schedule,
                          'Updated ${_relativeTime(repo.lastUpdated)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_vert),
                color: Colors.white70,
                iconSize: 19,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _ProviderDetails(repo: repo),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              _CompactActionButton(
                label: 'Refresh',
                icon: Icons.refresh,
                onPressed: () => ref
                    .read(providerManagerProvider.notifier)
                    .refresh(repo.sourceUrl),
              ),
              _CompactActionButton(
                label: repo.enabled ? 'Disable' : 'Enable',
                icon: repo.enabled ? Icons.pause : Icons.check,
                onPressed: () =>
                    ref.read(providerManagerProvider.notifier).toggle(repo.url),
              ),
              _CompactActionButton(
                label: 'Remove',
                icon: Icons.delete_outline,
                primary: true,
                onPressed: () => ref
                    .read(providerManagerProvider.notifier)
                    .remove(repo.sourceUrl),
              ),
            ],
          ),
          if (repo.availableProviders.isNotEmpty) ...[
            const SizedBox(height: 6),
            _ProviderExtensionStrip(repo: repo),
          ],
        ],
      ),
    );
  }
}

class _ProviderDetails extends StatelessWidget {
  const _ProviderDetails({required this.repo});

  final ProviderRepositoryModel repo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _DetailRow(
                  'API Endpoint',
                  repo.sourceUrl,
                  icon: Icons.lock_outline,
                  maxLines: 1,
                ),
                _DetailRow(
                  'Status',
                  _statusText(repo.status),
                  icon: Icons.check_circle,
                  valueColor: _statusColor(repo.status),
                ),
                _DetailRow('Version', repo.version),
                _DetailRow(
                  'Last Updated',
                  DateFormat.yMMMd().add_jm().format(repo.lastUpdated),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          _ContentSummary(repo: repo),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(
    this.label,
    this.value, {
    this.icon,
    this.valueColor,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10.3),
            ),
          ),
          if (icon != null) ...[
            Icon(icon, size: 12, color: valueColor ?? Colors.white70),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 10.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentSummary extends StatelessWidget {
  const _ContentSummary({required this.repo});

  final ProviderRepositoryModel repo;

  @override
  Widget build(BuildContext context) {
    final movieLike = repo.availableProviders
        .where((provider) => provider.type.toLowerCase().contains('movie'))
        .length;
    final seriesLike = repo.availableProviders
        .where((provider) => provider.type.toLowerCase().contains('serie'))
        .length;
    return Container(
      width: 130,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Content Summary',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10.4),
          ),
          const SizedBox(height: 3),
          _SummaryLine('Movies', movieLike == 0 ? 'mixed' : '$movieLike'),
          _SummaryLine('TV Shows', seriesLike == 0 ? 'mixed' : '$seriesLike'),
          _SummaryLine('Providers', '${repo.availableProviders.length}'),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _ProviderExtensionStrip extends ConsumerWidget {
  const _ProviderExtensionStrip({required this.repo});

  final ProviderRepositoryModel repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeProviderProvider);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: repo.availableProviders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final provider = repo.availableProviders[index];
          final isActive =
              active?.sourceUrl == repo.sourceUrl &&
              active?.value == provider.value;
          final canSelect = !provider.disabled;
          final color = isActive
              ? WenaTheme.red
              : provider.installed
              ? Colors.greenAccent
              : Colors.white70;
          return FocusableScale(
            borderRadius: 10,
            scale: 1.015,
            onPressed: canSelect
                ? () async {
                    final manager = ref.read(providerManagerProvider.notifier);
                    if (!provider.installed) {
                      await manager.installProvider(
                        repo.sourceUrl,
                        provider.value,
                      );
                    }
                    await manager.setActiveProvider(
                      repo.sourceUrl,
                      provider.value,
                    );
                  }
                : () {},
            child: Container(
              width: 150,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? WenaTheme.red.withValues(alpha: .18)
                    : Colors.white.withValues(alpha: .045),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: .34)),
              ),
              child: Row(
                children: [
                  Icon(
                    isActive
                        ? Icons.radio_button_checked
                        : provider.installed
                        ? Icons.download_done
                        : Icons.download,
                    color: color,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 10.8,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          isActive
                              ? 'default provider'
                              : provider.installed
                              ? _providerCompatibilityLabel(provider)
                              : provider.disabled
                              ? 'disabled'
                              : 'install',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final background = primary
        ? WenaTheme.red
        : Colors.white.withValues(alpha: .075);
    final foreground = primary ? Colors.white : Colors.white;
    return FocusableScale(
      borderRadius: 9,
      scale: 1.018,
      onPressed: onPressed,
      child: Container(
        height: 31,
        constraints: const BoxConstraints(minWidth: 96),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: foreground, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w900,
                fontSize: 10.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10.3),
        ),
      ],
    );
  }
}

class _ProviderTip extends StatelessWidget {
  const _ProviderTip();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: WenaTheme.red, size: 18),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Tip: Provider changes take effect immediately across Home, details and playback.',
              style: TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(ProviderStatus status) {
  return switch (status) {
    ProviderStatus.valid => Colors.greenAccent,
    ProviderStatus.unhealthy => Colors.orangeAccent,
    ProviderStatus.invalid => Colors.redAccent,
    ProviderStatus.idle => Colors.white54,
  };
}

String _statusText(ProviderStatus status) {
  return switch (status) {
    ProviderStatus.valid => 'Working properly',
    ProviderStatus.unhealthy => 'Needs attention',
    ProviderStatus.invalid => 'Invalid manifest',
    ProviderStatus.idle => 'Checking',
  };
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}

String _providerCompatibilityLabel(ProviderExtensionModel provider) {
  return switch (provider.compatibility) {
    'playable' => 'playable',
    'catalog' => 'catalog only',
    'needs adapter' => 'needs adapter',
    _ => provider.installed ? 'installed' : 'install',
  };
}
