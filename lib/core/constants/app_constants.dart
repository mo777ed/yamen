/// App-wide constants. Firestore paths live here so a typo can never hide in a widget.
class Col {
  static const users = 'users';
  static const wallets = 'wallets';
  static const userLevels = 'user_levels';
  static const userVip = 'user_vip';
  static const rooms = 'rooms';
  static const gifts = 'gifts';
  static const giftTransactions = 'gift_transactions';
  static const vipLevels = 'vip_levels';
  static const games = 'games';
  static const chats = 'chats';
  static const follows = 'follows';
  static const blocks = 'blocks';
  static const friendRequests = 'friend_requests';
  static const friends = 'friends';
  static const posts = 'posts';
  static const notifications = 'notifications';
  static const agencies = 'agencies';
  static const agencyMembers = 'agency_members';
  static const hosts = 'hosts';
  static const rankings = 'rankings';
  static const events = 'events';
  static const banners = 'banners';
  static const settings = 'settings';
  static const reports = 'reports';
  static const auditLogs = 'audit_logs';
}

/// Callable Cloud Function names.
class Fn {
  static const completeProfile = 'completeProfile';
  static const claimDailyLogin = 'claimDailyLogin';
  static const deleteAccount = 'deleteAccount';
  static const createRoom = 'createRoom';
  static const joinRoom = 'joinRoom';
  static const leaveRoom = 'leaveRoom';
  static const manageSeat = 'manageSeat';
  static const roomModeration = 'roomModeration';
  static const setRoomPassword = 'setRoomPassword';
  static const closeRoom = 'closeRoom';
  static const sendGift = 'sendGift';
  static const verifyPurchase = 'verifyPurchase';
  static const purchaseVip = 'purchaseVip';
  static const playGame = 'playGame';
  static const respondFriendRequest = 'respondFriendRequest';
  static const removeFriend = 'removeFriend';
  static const markChatRead = 'markChatRead';
  static const agencyAddHost = 'agencyAddHost';
  static const adminBanUser = 'adminBanUser';
  static const adminUnbanUser = 'adminUnbanUser';
  static const adminSetRole = 'adminSetRole';
  static const adminSearchUsers = 'adminSearchUsers';
  static const adminAdjustWallet = 'adminAdjustWallet';
  static const adminUpsert = 'adminUpsert';
  static const adminDelete = 'adminDelete';
  static const adminResolveReport = 'adminResolveReport';
  static const adminStats = 'adminStats';
  static const adminCreateAgency = 'adminCreateAgency';
  static const adminSetAgencyStatus = 'adminSetAgencyStatus';
}

class RoomCategory {
  static const all = [
    'chat', 'music', 'games', 'friends', 'entertainment',
    'private', 'arabic', 'yemen', 'gulf', 'international',
  ];
}

class AppLimits {
  static const pageSize = 20;
  static const roomChatMaxLength = 300;
}
