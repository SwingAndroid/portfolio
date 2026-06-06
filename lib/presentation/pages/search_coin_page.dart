import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../domain/entities/crypto_entity.dart';
import '../../injection_container.dart';
import '../bloc/portfolio/portfolio_bloc.dart';
import '../bloc/portfolio/portfolio_event.dart';
import '../bloc/search/coin_search_cubit.dart';
import '../bloc/search/coin_search_state.dart';

class SearchCoinPage extends StatefulWidget {
  const SearchCoinPage({super.key});

  @override
  State<SearchCoinPage> createState() => _SearchCoinPageState();
}

class _SearchCoinPageState extends State<SearchCoinPage> {
  final _controller = TextEditingController();
  late CoinSearchCubit _searchCubit;
  String? _debounceQuery;

  @override
  void initState() {
    super.initState();
    _searchCubit = CoinSearchCubit(repository: sl());
    _controller.addListener(_onSearch);
  }

  void _onSearch() {
    final query = _controller.text.trim();
    if (query == _debounceQuery) return;
    _debounceQuery = query;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_controller.text.trim() == query && mounted) {
        _searchCubit.searchCoins(query);
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onSearch);
    _controller.dispose();
    _searchCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return BlocProvider.value(
      value: _searchCubit,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: AppTheme.textPrimary, size: 20),
            onPressed: () => context.go('/'),
          ),
          title: const Text('Add Crypto',
              style: TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          elevation: 0,
        ),
        body: Center(
          child: ConstrainedBox(
            // Cap width on wide screens so search results don't stretch wall-to-wall
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 680 : double.infinity,
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isDesktop ? 0 : 16,
                    isDesktop ? 24 : 16,
                    isDesktop ? 0 : 16,
                    isDesktop ? 16 : 8,
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search Bitcoin, Ethereum, Solana...',
                      prefixIcon: const Icon(Icons.search,
                          color: AppTheme.textSecondary),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: AppTheme.textSecondary, size: 18),
                              onPressed: () {
                                _controller.clear();
                                _searchCubit.clear();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                Expanded(
                  child: BlocBuilder<CoinSearchCubit, CoinSearchState>(
                    builder: (context, state) {
                      if (state is CoinSearchInitial) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search,
                                  color: AppTheme.textTertiary, size: 48),
                              SizedBox(height: 12),
                              Text('Search for a cryptocurrency',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 15)),
                            ],
                          ),
                        );
                      }
                      if (state is CoinSearchLoading) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.primary),
                        );
                      }
                      if (state is CoinSearchError) {
                        return Center(
                          child: Text(state.message,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary)),
                        );
                      }
                      if (state is CoinSearchLoaded) {
                        if (state.results.isEmpty) {
                          return const Center(
                            child: Text('No results found',
                                style: TextStyle(
                                    color: AppTheme.textSecondary)),
                          );
                        }
                        return ListView.separated(
                          itemCount: state.results.length,
                          separatorBuilder: (_, __) => const Divider(
                              color: AppTheme.divider, height: 1),
                          itemBuilder: (ctx, i) {
                            final coin = state.results[i];
                            return _CoinResultTile(
                              coin: coin,
                              onTap: () => _addCoin(context, coin),
                            );
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addCoin(BuildContext context, Map<String, dynamic> coin) {
    final portfolioBloc = context.read<PortfolioBloc>();
    final crypto = CryptoEntity(
      id: const Uuid().v4(),
      coinId: coin['id'] as String,
      name: coin['name'] as String,
      symbol: (coin['symbol'] as String? ?? '').toUpperCase(),
      imageUrl: coin['large'] as String? ?? coin['thumb'] as String?,
      transactions: const [],
    );
    portfolioBloc.add(AddCryptoEvent(crypto));
    context.go('/crypto/${crypto.id}');
  }
}

class _CoinResultTile extends StatelessWidget {
  final Map<String, dynamic> coin;
  final VoidCallback onTap;

  const _CoinResultTile({required this.coin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = coin['large'] as String? ?? coin['thumb'] as String?;
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: imageUrl != null
            ? Image.network(imageUrl, width: 40, height: 40,
                errorBuilder: (_, __, ___) => _fallbackIcon())
            : _fallbackIcon(),
      ),
      title: Text(
        coin['name'] as String? ?? '',
        style: const TextStyle(
            color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        (coin['symbol'] as String? ?? '').toUpperCase(),
        style:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: const Text('Add',
            style: TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(Icons.currency_bitcoin,
          color: AppTheme.primary, size: 20),
    );
  }
}
