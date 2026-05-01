enum ProviderStatus { idle, valid, unhealthy, invalid }

class ProviderExtensionModel {
  const ProviderExtensionModel({
    required this.displayName,
    required this.value,
    required this.version,
    required this.type,
    required this.disabled,
    this.installed = false,
    this.compatibility = 'unknown',
    this.compatibilityMessage = '',
  });

  final String displayName;
  final String value;
  final String version;
  final String type;
  final bool disabled;
  final bool installed;
  final String compatibility;
  final String compatibilityMessage;

  factory ProviderExtensionModel.fromJson(Map<String, dynamic> json) {
    return ProviderExtensionModel(
      displayName: (json['display_name'] ?? json['name'] ?? 'Provider')
          .toString(),
      value: (json['value'] ?? '').toString(),
      version: (json['version'] ?? 'unknown').toString(),
      type: (json['type'] ?? 'global').toString(),
      disabled: json['disabled'] == true,
      installed: json['installed'] == true,
      compatibility: (json['compatibility'] ?? 'unknown').toString(),
      compatibilityMessage: (json['compatibility_message'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'display_name': displayName,
      'value': value,
      'version': version,
      'type': type,
      'disabled': disabled,
      'installed': installed,
      'compatibility': compatibility,
      'compatibility_message': compatibilityMessage,
    };
  }

  ProviderExtensionModel copyWith({
    bool? installed,
    String? compatibility,
    String? compatibilityMessage,
  }) {
    return ProviderExtensionModel(
      displayName: displayName,
      value: value,
      version: version,
      type: type,
      disabled: disabled,
      installed: installed ?? this.installed,
      compatibility: compatibility ?? this.compatibility,
      compatibilityMessage: compatibilityMessage ?? this.compatibilityMessage,
    );
  }
}

class ProviderRepositoryModel {
  const ProviderRepositoryModel({
    required this.url,
    required this.sourceUrl,
    required this.name,
    required this.version,
    required this.lastUpdated,
    required this.status,
    this.availableProviders = const [],
    this.installedCount = 0,
    this.enabled = false,
  });

  final String url;
  final String sourceUrl;
  final String name;
  final String version;
  final DateTime lastUpdated;
  final ProviderStatus status;
  final List<ProviderExtensionModel> availableProviders;
  final int installedCount;
  final bool enabled;

  factory ProviderRepositoryModel.fromJson(Map<String, dynamic> json) {
    final providers = ((json['available_providers'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (provider) => ProviderExtensionModel.fromJson(
            Map<String, dynamic>.from(provider),
          ),
        )
        .toList();
    final statusIndex = json['status'] as int? ?? ProviderStatus.idle.index;
    final status =
        statusIndex >= 0 && statusIndex < ProviderStatus.values.length
        ? ProviderStatus.values[statusIndex]
        : ProviderStatus.idle;
    return ProviderRepositoryModel(
      url: (json['url'] ?? '').toString(),
      sourceUrl: (json['source_url'] ?? '').toString(),
      name: (json['name'] ?? 'Repository').toString(),
      version: (json['version'] ?? 'unknown').toString(),
      lastUpdated:
          DateTime.tryParse((json['last_updated'] ?? '').toString()) ??
          DateTime.now(),
      status: status,
      availableProviders: providers,
      installedCount:
          json['installed_count'] as int? ??
          providers.where((provider) => provider.installed).length,
      enabled: json['enabled'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'source_url': sourceUrl,
      'name': name,
      'version': version,
      'last_updated': lastUpdated.toIso8601String(),
      'status': status.index,
      'available_providers': [
        for (final provider in availableProviders) provider.toJson(),
      ],
      'installed_count': installedCount,
      'enabled': enabled,
    };
  }

  ProviderRepositoryModel copyWith({
    String? url,
    String? sourceUrl,
    String? name,
    String? version,
    DateTime? lastUpdated,
    ProviderStatus? status,
    List<ProviderExtensionModel>? availableProviders,
    int? installedCount,
    bool? enabled,
  }) {
    return ProviderRepositoryModel(
      url: url ?? this.url,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      name: name ?? this.name,
      version: version ?? this.version,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      status: status ?? this.status,
      availableProviders: availableProviders ?? this.availableProviders,
      installedCount: installedCount ?? this.installedCount,
      enabled: enabled ?? this.enabled,
    );
  }
}
