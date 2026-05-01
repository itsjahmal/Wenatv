import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/provider_repository.dart';
import '../../shared/widgets/focusable_scale.dart';
import '../home/navigation_rail.dart';
import '../providers/provider_manager_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
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
                    final inset = TvLayout.horizontalInset(size) * .58;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        inset,
                        AppSpacing.md,
                        inset,
                        AppSpacing.md,
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SettingsMenu(),
                          SizedBox(width: 14),
                          Expanded(child: ProviderManagerPanel()),
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
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu();

  static const items = [
    _SettingsMenuItem(
      'Provider Manager',
      'Manage and configure providers',
      Icons.extension,
      true,
    ),
    _SettingsMenuItem(
      'Playback Settings',
      'Quality, autoplay and more',
      Icons.play_circle_outline,
      false,
    ),
    _SettingsMenuItem(
      'Subtitle Settings',
      'Language and appearance',
      Icons.closed_caption,
      false,
    ),
    _SettingsMenuItem(
      'Audio Settings',
      'Language, output and more',
      Icons.volume_up_outlined,
      false,
    ),
    _SettingsMenuItem(
      'Theme Settings',
      'Theme, colors and UI',
      Icons.stacked_line_chart,
      false,
    ),
    _SettingsMenuItem(
      'Ad Blocking',
      'Manage ad blocking options',
      Icons.shield_outlined,
      false,
    ),
    _SettingsMenuItem(
      'About',
      'App version and information',
      Icons.info_outline,
      false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * .29).clamp(278.0, 330.0).toDouble();
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(fontSize: 30, height: 1),
          ),
          const SizedBox(height: 8),
          const Text(
            'Manage your app preferences',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(right: 2, bottom: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _SettingsCategoryCard(
                item: items[index],
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
  const _SettingsCategoryCard({required this.item, required this.autofocus});

  final _SettingsMenuItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableScale(
      autofocus: autofocus,
      borderRadius: 14,
      scale: 1.015,
      onPressed: () {},
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: item.active
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
            color: item.active
                ? WenaTheme.red
                : Colors.white.withValues(alpha: .08),
          ),
          boxShadow: item.active
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.active
                    ? Colors.black.withValues(alpha: .28)
                    : Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: .05)),
              ),
              child: Icon(
                item.icon,
                color: item.active ? WenaTheme.red : Colors.white70,
                size: 25,
              ),
            ),
            const SizedBox(width: 13),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _SettingsMenuItem {
  const _SettingsMenuItem(this.title, this.subtitle, this.icon, this.active);

  final String title;
  final String subtitle;
  final IconData icon;
  final bool active;
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
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xE5080A0E),
        border: Border.all(color: Colors.white.withValues(alpha: .11)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .46),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ProviderHeader(),
              const SizedBox(height: 18),
              Text(
                'Default Provider',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              _DefaultProviderBox(active: active),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      SizedBox(
                        width: compact ? constraints.maxWidth : 460,
                        child: TextField(
                          controller: _controller,
                          onSubmitted: (_) => _addRepository(),
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Provider repository',
                            hintText: 'vega-org or GitHub provider URL',
                            prefixIcon: const Icon(Icons.link),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: .05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: .08),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 18),
              Text(
                'Installed Providers',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 10),
              if (repos.isEmpty)
                const _EmptyProviderState()
              else
                for (final repo in repos) ...[
                  _ProviderTile(repo: repo),
                  const SizedBox(height: 10),
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
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: WenaTheme.red.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: WenaTheme.red.withValues(alpha: .55)),
          ),
          child: const Icon(Icons.extension, color: WenaTheme.red, size: 31),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Provider Manager',
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 5),
              const Text(
                'Install, manage and configure content providers.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
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
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_border, color: Colors.white, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              active?.displayName ?? 'No provider selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: const Text(
        'No providers bundled. Add a repository to begin.',
        style: TextStyle(color: Colors.white70),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
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
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: statusColor.withValues(alpha: .34)),
                ),
                child: Icon(Icons.extension, color: statusColor, size: 30),
              ),
              const SizedBox(width: 14),
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
                            ).textTheme.headlineMedium?.copyWith(fontSize: 21),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StatusPill(
                          label: repo.enabled ? 'Active' : 'Inactive',
                          color: repo.enabled
                              ? Colors.greenAccent
                              : Colors.white54,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
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
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_vert),
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProviderDetails(repo: repo),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
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
            const SizedBox(height: 12),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(12),
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
          const SizedBox(width: 12),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          if (icon != null) ...[
            Icon(icon, size: 15, color: valueColor ?? Colors.white70),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: valueColor ?? Colors.white, fontSize: 13),
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
      width: 178,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Content Summary',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          const SizedBox(height: 6),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
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
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: repo.availableProviders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
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
            borderRadius: 12,
            scale: 1.02,
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
              width: 196,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: isActive
                    ? WenaTheme.red.withValues(alpha: .18)
                    : Colors.white.withValues(alpha: .045),
                borderRadius: BorderRadius.circular(12),
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
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
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
                            fontSize: 12,
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
      borderRadius: 10,
      scale: 1.025,
      onPressed: onPressed,
      child: Container(
        height: 44,
        constraints: const BoxConstraints(minWidth: 132),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w900,
                fontSize: 14,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
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
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
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
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: WenaTheme.red),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tip: Provider changes take effect immediately across Home, details and playback.',
              style: TextStyle(color: Colors.white70),
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
