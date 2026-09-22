import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/roles.dart';

// ---------- parsing helpers ----------
DateTime? tsToDate(Object? v) => v is Timestamp ? v.toDate() : null;
int asInt(Object? v) => v is num ? v.toInt() : 0;
double asDouble(Object? v) => v is num ? v.toDouble() : 0;
String asStr(Object? v) => v is String ? v : '';
bool asBool(Object? v) => v is bool ? v : false;
Map<String, dynamic> asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<String> asStrList(Object? v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

/// Reads {ar, en} maps (or plain strings) and returns the right language.
String localized(Object? v, {required bool arabic}) {
  if (v is String) return v;
  if (v is Map) {
    final primary = v[arabic ? 'ar' : 'en'];
    final other = v[arabic ? 'en' : 'ar'];
    if (primary is String && primary.isNotEmpty) return primary;
    if (other is String) return other;
  }
  return '';
}

typedef Doc = DocumentSnapshot<Map<String, dynamic>>;
typedef QDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

// ---------- users ----------
class AppUser {
  final String id;
  final String displayName;
  final String username;
  final String avatarUrl;
  final String bio;
  final String country;
  final String lang;
  final String? gender;
  final Role role;
  final String status;
  final bool profileComplete;
  final int level;
  final int vipLevel;
  final int followersCount;
  final int followingCount;
  final int friendsCount;
  final int giftsReceived;
  final bool online;
  final DateTime? lastSeen;
  final bool hideOnline;
  final bool dmFriendsOnly;

  const AppUser({
    required this.id,
    this.displayName = '',
    this.username = '',
    this.avatarUrl = '',
    this.bio = '',
    this.country = '',
    this.lang = 'ar',
    this.gender,
    this.role = Role.user,
    this.status = 'active',
    this.profileComplete = false,
    this.level = 1,
    this.vipLevel = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.friendsCount = 0,
    this.giftsReceived = 0,
    this.online = false,
    this.lastSeen,
    this.hideOnline = false,
    this.dmFriendsOnly = false,
  });

  factory AppUser.fromMap(String id, Map<String, dynamic> d) {
    final privacy = asMap(d['privacy']);
    return AppUser(
      id: id,
      displayName: asStr(d['displayName']),
      username: asStr(d['username']),
      avatarUrl: asStr(d['avatarUrl']),
      bio: asStr(d['bio']),
      country: asStr(d['country']),
      lang: asStr(d['lang']).isEmpty ? 'ar' : asStr(d['lang']),
      gender: d['gender'] as String?,
      role: Role.parse(d['role'] as String?),
      status: asStr(d['status']).isEmpty ? 'active' : asStr(d['status']),
      profileComplete: asBool(d['profileComplete']),
      level: asInt(d['level']) == 0 ? 1 : asInt(d['level']),
      vipLevel: asInt(d['vipLevel']),
      followersCount: asInt(d['followersCount']),
      followingCount: asInt(d['followingCount']),
      friendsCount: asInt(d['friendsCount']),
      giftsReceived: asInt(d['giftsReceived']),
      online: asBool(d['online']),
      lastSeen: tsToDate(d['lastSeen']),
      hideOnline: asBool(privacy['hideOnline']),
      dmFriendsOnly: asBool(privacy['dmFriendsOnly']),
    );
  }

  factory AppUser.fromDoc(Doc doc) => AppUser.fromMap(doc.id, doc.data() ?? {});

  bool get isBanned => status == 'banned';
  String get handle => username.isEmpty ? '' : '@$username';
}

class UserLevel {
  final int xp;
  final int level;
  final int streak;
  const UserLevel({this.xp = 0, this.level = 1, this.streak = 0});
  factory UserLevel.fromMap(Map<String, dynamic>? d) {
    final m = d ?? {};
    return UserLevel(xp: asInt(m['xp']), level: asInt(m['level']) == 0 ? 1 : asInt(m['level']), streak: asInt(m['streak']));
  }
}

class UserVip {
  final int level;
  final DateTime? expiresAt;
  const UserVip({this.level = 0, this.expiresAt});
  factory UserVip.fromMap(Map<String, dynamic>? d) {
    final m = d ?? {};
    return UserVip(level: asInt(m['level']), expiresAt: tsToDate(m['expiresAt']));
  }
  bool get active => level > 0 && (expiresAt?.isAfter(DateTime.now()) ?? false);
}

class VipLevel {
  final int level;
  final int price;
  final int durationDays;
  final Map<String, dynamic> perks;
  final bool enabled;
  const VipLevel({required this.level, required this.price, required this.durationDays, required this.perks, required this.enabled});
  factory VipLevel.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return VipLevel(
      level: int.tryParse(d.id) ?? asInt(m['level']),
      price: asInt(m['price']),
      durationDays: asInt(m['durationDays']) == 0 ? 30 : asInt(m['durationDays']),
      perks: asMap(m['perks']),
      enabled: m['enabled'] != false,
    );
  }
  int get giftDiscountPct => asInt(perks['giftDiscountPct']);
}

// ---------- rooms ----------
class Room {
  final String id;
  final String name;
  final String coverUrl;
  final String category;
  final String type;
  final String description;
  final String ownerId;
  final String ownerName;
  final String ownerAvatar;
  final String country;
  final int memberCount;
  final int maxUsers;
  final int seatCount;
  final String status;
  final bool featured;
  final DateTime? createdAt;

  const Room({
    required this.id,
    required this.name,
    this.coverUrl = '',
    this.category = 'chat',
    this.type = 'public',
    this.description = '',
    this.ownerId = '',
    this.ownerName = '',
    this.ownerAvatar = '',
    this.country = '',
    this.memberCount = 0,
    this.maxUsers = 200,
    this.seatCount = 8,
    this.status = 'live',
    this.featured = false,
    this.createdAt,
  });

  factory Room.fromMap(String id, Map<String, dynamic> d) => Room(
        id: id,
        name: asStr(d['name']),
        coverUrl: asStr(d['coverUrl']),
        category: asStr(d['category']).isEmpty ? 'chat' : asStr(d['category']),
        type: asStr(d['type']).isEmpty ? 'public' : asStr(d['type']),
        description: asStr(d['description']),
        ownerId: asStr(d['ownerId']),
        ownerName: asStr(d['ownerName']),
        ownerAvatar: asStr(d['ownerAvatar']),
        country: asStr(d['country']),
        memberCount: asInt(d['memberCount']),
        maxUsers: asInt(d['maxUsers']) == 0 ? 200 : asInt(d['maxUsers']),
        seatCount: asInt(d['seatCount']) == 0 ? 8 : asInt(d['seatCount']),
        status: asStr(d['status']),
        featured: asBool(d['featured']),
        createdAt: tsToDate(d['createdAt']),
      );

  factory Room.fromDoc(Doc d) => Room.fromMap(d.id, d.data() ?? {});
  bool get isPrivate => type == 'private';
  bool get isLive => status == 'live';
}

class Seat {
  final int index;
  final String? userId;
  final bool locked;
  final bool micMuted;
  const Seat({required this.index, this.userId, this.locked = false, this.micMuted = false});
  factory Seat.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return Seat(
      index: int.tryParse(d.id) ?? 0,
      userId: m['userId'] as String?,
      locked: asBool(m['locked']),
      micMuted: asBool(m['micMuted']),
    );
  }
  bool get empty => userId == null || userId!.isEmpty;
}

class RoomMember {
  final String uid;
  final RoomRole role;
  final String username;
  final String displayName;
  final String avatarUrl;
  final int level;
  final int vipLevel;
  final bool left;
  final DateTime? mutedUntil;
  const RoomMember({
    required this.uid,
    this.role = RoomRole.listener,
    this.username = '',
    this.displayName = '',
    this.avatarUrl = '',
    this.level = 1,
    this.vipLevel = 0,
    this.left = false,
    this.mutedUntil,
  });
  factory RoomMember.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return RoomMember(
      uid: d.id,
      role: RoomRole.parse(m['role'] as String?),
      username: asStr(m['username']),
      displayName: asStr(m['displayName']),
      avatarUrl: asStr(m['avatarUrl']),
      level: asInt(m['level']) == 0 ? 1 : asInt(m['level']),
      vipLevel: asInt(m['vipLevel']),
      left: asBool(m['left']),
      mutedUntil: tsToDate(m['mutedUntil']),
    );
  }
  bool get chatMuted => mutedUntil?.isAfter(DateTime.now()) ?? false;
}

class RoomMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final int senderLevel;
  final String text;
  final String type; // text | system | gift | join
  final String receiverId;
  final String receiverName;
  final Object? giftNameRaw;
  final String giftIcon;
  final String giftAnimation;
  final String giftTier;
  final int qty;
  final DateTime? createdAt;

  const RoomMessage({
    required this.id,
    required this.senderId,
    this.senderName = '',
    this.senderAvatar = '',
    this.senderLevel = 1,
    this.text = '',
    this.type = 'text',
    this.receiverId = '',
    this.receiverName = '',
    this.giftNameRaw,
    this.giftIcon = '',
    this.giftAnimation = '',
    this.giftTier = 'small',
    this.qty = 1,
    this.createdAt,
  });

  factory RoomMessage.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return RoomMessage(
      id: d.id,
      senderId: asStr(m['senderId']),
      senderName: asStr(m['senderName']),
      senderAvatar: asStr(m['senderAvatar']),
      senderLevel: asInt(m['senderLevel']) == 0 ? 1 : asInt(m['senderLevel']),
      text: asStr(m['text']),
      type: asStr(m['type']).isEmpty ? 'text' : asStr(m['type']),
      receiverId: asStr(m['receiverId']),
      receiverName: asStr(m['receiverName']),
      giftNameRaw: m['giftName'],
      giftIcon: asStr(m['giftIcon']),
      giftAnimation: asStr(m['giftAnimation']),
      giftTier: asStr(m['giftTier']).isEmpty ? 'small' : asStr(m['giftTier']),
      qty: asInt(m['qty']) == 0 ? 1 : asInt(m['qty']),
      createdAt: tsToDate(m['createdAt']),
    );
  }

  String giftName(bool arabic) => localized(giftNameRaw, arabic: arabic);
  bool get isGift => type == 'gift';
  bool get isSystem => type == 'system' || type == 'join';
}

// ---------- economy ----------
class Gift {
  final String id;
  final Object? nameRaw;
  final String iconUrl;
  final String animationUrl;
  final int price;
  final String category;
  final String tier; // small | medium | big
  final bool enabled;
  const Gift({
    required this.id,
    this.nameRaw,
    this.iconUrl = '',
    this.animationUrl = '',
    required this.price,
    this.category = 'general',
    this.tier = 'small',
    this.enabled = true,
  });
  factory Gift.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return Gift(
      id: d.id,
      nameRaw: m['name'],
      iconUrl: asStr(m['iconUrl']),
      animationUrl: asStr(m['animationUrl']),
      price: asInt(m['price']),
      category: asStr(m['category']).isEmpty ? 'general' : asStr(m['category']),
      tier: asStr(m['tier']).isEmpty ? 'small' : asStr(m['tier']),
      enabled: m['enabled'] != false,
    );
  }
  String name(bool arabic) => localized(nameRaw, arabic: arabic);
  bool get isBig => tier == 'big';
}

class WalletData {
  final int coins;
  final int diamonds;
  const WalletData({this.coins = 0, this.diamonds = 0});
  factory WalletData.fromMap(Map<String, dynamic>? d) =>
      WalletData(coins: asInt(d?['coins']), diamonds: asInt(d?['diamonds']));
}

class WalletTx {
  final String id;
  final String type;
  final String currency;
  final int amount;
  final int balanceAfter;
  final DateTime? createdAt;
  const WalletTx({required this.id, required this.type, required this.currency, required this.amount, required this.balanceAfter, this.createdAt});
  factory WalletTx.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return WalletTx(
      id: d.id,
      type: asStr(m['type']),
      currency: asStr(m['currency']),
      amount: asInt(m['amount']),
      balanceAfter: asInt(m['balanceAfter']),
      createdAt: tsToDate(m['createdAt']),
    );
  }
}

class CoinPackage {
  final String productId;
  final int coins;
  final int bonus;
  final double priceUsd;
  const CoinPackage({required this.productId, required this.coins, required this.bonus, required this.priceUsd});
  factory CoinPackage.fromMap(Map<String, dynamic> m) => CoinPackage(
        productId: asStr(m['productId']),
        coins: asInt(m['coins']),
        bonus: asInt(m['bonus']),
        priceUsd: asDouble(m['priceUsd']),
      );
}

class GameConfig {
  final String id;
  final Object? nameRaw;
  final bool enabled;
  final int minBet;
  final int maxBet;
  const GameConfig({required this.id, this.nameRaw, this.enabled = true, this.minBet = 10, this.maxBet = 10000});
  String name(bool arabic) => localized(nameRaw, arabic: arabic);
}

// ---------- social ----------
class ChatSummary {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final String lastSender;
  final DateTime? lastAt;
  final Map<String, dynamic> unread;
  const ChatSummary({required this.id, required this.participants, this.lastMessage = '', this.lastSender = '', this.lastAt, this.unread = const {}});
  factory ChatSummary.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return ChatSummary(
      id: d.id,
      participants: asStrList(m['participants']),
      lastMessage: asStr(m['lastMessage']),
      lastSender: asStr(m['lastSender']),
      lastAt: tsToDate(m['lastAt']),
      unread: asMap(m['unread']),
    );
  }
  String otherId(String me) => participants.firstWhere((p) => p != me, orElse: () => '');
  int unreadFor(String me) => asInt(unread[me]);
}

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final String imageUrl;
  final List<String> readBy;
  final DateTime? createdAt;
  const ChatMessage({required this.id, required this.senderId, this.text = '', this.imageUrl = '', this.readBy = const [], this.createdAt});
  factory ChatMessage.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return ChatMessage(
      id: d.id,
      senderId: asStr(m['senderId']),
      text: asStr(m['text']),
      imageUrl: asStr(m['imageUrl']),
      readBy: asStrList(m['readBy']),
      createdAt: tsToDate(m['createdAt']),
    );
  }
}

class FriendRequest {
  final String id;
  final String from;
  final String to;
  final String status;
  final String fromName;
  final String fromAvatar;
  const FriendRequest({required this.id, required this.from, required this.to, required this.status, this.fromName = '', this.fromAvatar = ''});
  factory FriendRequest.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return FriendRequest(
      id: d.id,
      from: asStr(m['from']),
      to: asStr(m['to']),
      status: asStr(m['status']),
      fromName: asStr(m['fromName']),
      fromAvatar: asStr(m['fromAvatar']),
    );
  }
}

class AppNotification {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final bool read;
  final DateTime? createdAt;
  const AppNotification({required this.id, required this.type, required this.payload, required this.read, this.createdAt});
  factory AppNotification.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return AppNotification(id: d.id, type: asStr(m['type']), payload: asMap(m['payload']), read: asBool(m['read']), createdAt: tsToDate(m['createdAt']));
  }
}

class Post {
  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String text;
  final DateTime? createdAt;
  const Post({required this.id, required this.authorId, this.authorName = '', this.authorAvatar = '', required this.text, this.createdAt});
  factory Post.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return Post(id: d.id, authorId: asStr(m['authorId']), authorName: asStr(m['authorName']), authorAvatar: asStr(m['authorAvatar']), text: asStr(m['text']), createdAt: tsToDate(m['createdAt']));
  }
}

// ---------- agencies / hosts / rankings / events ----------
class Agency {
  final String id;
  final String name;
  final String ownerId;
  final String status;
  final int commissionPct;
  final int earnings;
  final int hostsCount;
  const Agency({required this.id, required this.name, this.ownerId = '', this.status = 'pending', this.commissionPct = 0, this.earnings = 0, this.hostsCount = 0});
  factory Agency.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return Agency(id: d.id, name: asStr(m['name']), ownerId: asStr(m['ownerId']), status: asStr(m['status']), commissionPct: asInt(m['commissionPct']), earnings: asInt(m['earnings']), hostsCount: asInt(m['hostsCount']));
  }
}

class Host {
  final String uid;
  final String agencyId;
  final String displayName;
  final String avatarUrl;
  final int level;
  final double totalHours;
  final int giftsReceived;
  final int earnings;
  const Host({required this.uid, this.agencyId = '', this.displayName = '', this.avatarUrl = '', this.level = 1, this.totalHours = 0, this.giftsReceived = 0, this.earnings = 0});
  factory Host.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return Host(
      uid: d.id,
      agencyId: asStr(m['agencyId']),
      displayName: asStr(m['displayName']),
      avatarUrl: asStr(m['avatarUrl']),
      level: asInt(m['level']) == 0 ? 1 : asInt(m['level']),
      totalHours: asDouble(m['totalHours']),
      giftsReceived: asInt(m['giftsReceived']),
      earnings: asInt(m['earnings']),
    );
  }
}

class RankEntry {
  final String id;
  final String name;
  final String avatar;
  final int score;
  const RankEntry({required this.id, required this.name, required this.avatar, required this.score});
  factory RankEntry.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return RankEntry(id: d.id, name: asStr(m['name']), avatar: asStr(m['avatar']), score: asInt(m['score']));
  }
}

class EventItem {
  final String id;
  final Object? titleRaw;
  final Object? descRaw;
  final String imageUrl;
  final String kind; // daily | weekly | seasonal
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool active;
  const EventItem({required this.id, this.titleRaw, this.descRaw, this.imageUrl = '', this.kind = 'daily', this.startsAt, this.endsAt, this.active = true});
  factory EventItem.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return EventItem(
      id: d.id,
      titleRaw: m['title'],
      descRaw: m['description'],
      imageUrl: asStr(m['imageUrl']),
      kind: asStr(m['kind']).isEmpty ? 'daily' : asStr(m['kind']),
      startsAt: tsToDate(m['startsAt']),
      endsAt: tsToDate(m['endsAt']),
      active: m['active'] != false,
    );
  }
  String title(bool ar) => localized(titleRaw, arabic: ar);
  String description(bool ar) => localized(descRaw, arabic: ar);
}

class BannerItem {
  final String id;
  final String imageUrl;
  final String link;
  const BannerItem({required this.id, required this.imageUrl, this.link = ''});
  factory BannerItem.fromDoc(Doc d) {
    final m = d.data() ?? {};
    return BannerItem(id: d.id, imageUrl: asStr(m['imageUrl']), link: asStr(m['link']));
  }
}
