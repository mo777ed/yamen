enum Role {
  user,
  host,
  agencyManager,
  moderator,
  admin,
  superAdmin;

  static Role parse(String? v) {
    switch (v) {
      case 'host':
        return Role.host;
      case 'agency_manager':
        return Role.agencyManager;
      case 'moderator':
        return Role.moderator;
      case 'admin':
        return Role.admin;
      case 'super_admin':
        return Role.superAdmin;
      default:
        return Role.user;
    }
  }

  String get wire {
    switch (this) {
      case Role.agencyManager:
        return 'agency_manager';
      case Role.superAdmin:
        return 'super_admin';
      default:
        return name;
    }
  }

  /// Same ordering as the Cloud Functions ROLE_RANK table.
  int get rank {
    switch (this) {
      case Role.user:
        return 0;
      case Role.host:
        return 1;
      case Role.agencyManager:
        return 2;
      case Role.moderator:
        return 3;
      case Role.admin:
        return 4;
      case Role.superAdmin:
        return 5;
    }
  }

  bool atLeast(Role other) => rank >= other.rank;
  bool get isStaff => atLeast(Role.moderator);
  bool get isAdmin => atLeast(Role.admin);
}

/// Role inside a voice room (not the same as the account role).
enum RoomRole {
  listener,
  speaker,
  mod,
  admin,
  owner;

  static RoomRole parse(String? v) {
    for (final r in RoomRole.values) {
      if (r.name == v) return r;
    }
    return RoomRole.listener;
  }

  bool atLeast(RoomRole other) => index >= other.index;
  bool get canManage => atLeast(RoomRole.mod);
}
