class DriverNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  DriverNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.data,
    required this.createdAt,
  });

  /// ---------------------------
  /// 🧠 FACTORY
  /// ---------------------------
  factory DriverNotification.fromJson(Map<String, dynamic> json) {
    return DriverNotification(
      id: json['_id']?.toString() ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      type: json['type'] ?? 'general',
      isRead: json['isRead'] ?? false,
      data: json['data'] != null
          ? Map<String, dynamic>.from(json['data'])
          : <String, dynamic>{},
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  /// ---------------------------
  /// 🎯 HELPERS (FOR UI / ACTIONS)
  /// ---------------------------

  /// Action like: open_trip, open_wallet, open_notifications
  String? get action => data['action'];

  /// Banner image URL (optional)
  String? get bannerUrl => data['bannerUrl'];

  /// Trip ID if notification is trip-related
  String? get tripId => data['tripId'];

  /// Convenience flags
  bool get isTrip => type == 'trip';
  bool get isAlert => type == 'alert';
  bool get isPromotion => type == 'promotion';
}
