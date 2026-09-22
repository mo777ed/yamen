import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/debouncer.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/components/user_tile.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/user_repository.dart';
import '../../rooms/data/room_repository.dart';
import '../../rooms/presentation/room_card.dart';

enum _Tab { users, rooms, hosts, agencies }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _debounce = Debouncer(const Duration(milliseconds: 400));
  _Tab _tab = _Tab.users;
  String _query = '';
  bool _loading = false;
  Object? _error;
  List<Object> _results = [];

  @override
  void dispose() {
    _debounce.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _query = v;
    _debounce.run(_search);
  }

  Future<void> _search() async {
    final q = _query.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = ref.read(userRepositoryProvider);
      final List<Object> res;
      switch (_tab) {
        case _Tab.users:
          res = await users.searchUsers(q);
          break;
        case _Tab.rooms:
          res = await ref.read(roomRepositoryProvider).searchRooms(q);
          break;
        case _Tab.hosts:
          res = await users.searchHosts(q);
          break;
        case _Tab.agencies:
          res = await users.searchAgencies(q);
          break;
      }
      if (mounted && q == _query.trim()) setState(() => _results = res);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(myUidProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: InputDecoration(hintText: context.tr('search.hint'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in _Tab.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(context.tr('search.${t.name}')),
                      selected: _tab == t,
                      onSelected: (_) {
                        setState(() {
                          _tab = t;
                          _results = [];
                        });
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body(myUid)),
        ],
      ),
    );
  }

  Widget _body(String myUid) {
    if (_query.trim().length < 2) return EmptyState(message: context.tr('search.type_more'), icon: Icons.search_rounded);
    if (_loading) return const SkeletonList(count: 5);
    if (_error != null) return ErrorState(error: _error!, onRetry: _search);
    if (_results.isEmpty) return EmptyState(message: context.tr('search.no_results'), icon: Icons.search_off_rounded);
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final r = _results[i];
        if (r is AppUser) return UserTile(user: r);
        if (r is Room) {
          return ListTile(
            leading: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 48, height: 48, child: UserAvatar(url: r.coverUrl, name: r.name, size: 48))),
            title: Text(r.name),
            subtitle: Text('${context.tr('cat.${r.category}')} · ${r.memberCount}'),
            trailing: r.isPrivate ? const Icon(Icons.lock_rounded, size: 18) : null,
            onTap: () => openRoom(context, r, myUid: myUid),
          );
        }
        if (r is Host) {
          return ListTile(
            leading: UserAvatar(url: r.avatarUrl, name: r.displayName, size: 48),
            title: Text(r.displayName),
            subtitle: Text('Lv.${r.level}'),
            onTap: () => context.push('/profile/${r.uid}'),
          );
        }
        if (r is Agency) {
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.business_rounded)),
            title: Text(r.name),
            subtitle: Text(context.tr('agency.hosts_count', {'n': r.hostsCount})),
            onTap: () => context.push('/agency/${r.id}'),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

