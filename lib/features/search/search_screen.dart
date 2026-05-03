import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/wena_button.dart';
import '../home/navigation_rail.dart';

final searchResultsProvider = FutureProvider.family<List<MediaItem>, String>((
  ref,
  query,
) {
  return ref.watch(tmdbRepositoryProvider).search(query);
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => setState(() => _query = value.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider(_query));
    return Scaffold(
      body: Row(
        children: [
          const WenaNavigationRail(active: 'Search'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                TvLayout.safeHorizontal,
                AppSpacing.md,
                TvLayout.safeHorizontal,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Search WenaTV',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: _onChanged,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Movies, series, actors, genres',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      filled: true,
                      fillColor: WenaTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _query.isEmpty
                        ? const Center(
                            child: Text('Type with your TV keyboard to begin.'),
                          )
                        : results.when(
                            data: (items) => items.isEmpty
                                ? Center(
                                    child: WenaButton(
                                      label: 'No results. Retry',
                                      icon: Icons.refresh,
                                      onPressed: () => ref.invalidate(
                                        searchResultsProvider(_query),
                                      ),
                                    ),
                                  )
                                : GridView.builder(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 6,
                                          childAspectRatio: 2 / 3,
                                          mainAxisSpacing: 18,
                                          crossAxisSpacing: 14,
                                        ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return PosterCard(
                                        item: item,
                                        onPressed: () => context.push(
                                          '/details/${item.kind.name}/${item.id}',
                                        ),
                                      );
                                    },
                                  ),
                            loading: () => const Center(
                              child: CircularProgressIndicator(
                                color: WenaTheme.red,
                              ),
                            ),
                            error: (_, __) => Center(
                              child: WenaButton(
                                label: 'Retry',
                                icon: Icons.refresh,
                                primary: true,
                                onPressed: () => ref.invalidate(
                                  searchResultsProvider(_query),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
