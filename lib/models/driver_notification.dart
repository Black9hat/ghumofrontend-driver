// lib/models/driver_notification.dart

class DriverNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;

  /// ✅ FIX: was 'bannerUrl' — field name now matches DB field 'imageUrl'
  final String? imageUrl;

  final String? action;
  final String? tripId;
  final DateTime createdAt;

  DriverNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    this.imageUrl,
    this.action,
    this.tripId,
    required this.createdAt,
  });

  factory DriverNotification.fromJson(Map<String, dynamic> json) {
    return DriverNotification(
      id: json['_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      type: json['type']?.toString() ?? 'general',
      isRead: json['isRead'] == true,

      // ✅ FIX: Read 'imageUrl' (matches Notification.js schema field name)
      imageUrl: json['imageUrl']?.toString(),

      // Action & tripId come from the nested 'data' map
      action: (json['data'] is Map)
          ? (json['data'] as Map)['action']?.toString()
          : null,
      tripId: (json['data'] is Map)
          ? (json['data'] as Map)['tripId']?.toString()
          : null,

      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'body': body,
      'type': type,
      'isRead': isRead,
      'imageUrl': imageUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}