import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/driver_notification_service.dart';
import '../models/driver_notification.dart';
import '../main.dart'; // 🔔 NotificationEventBus

// ============================================================================
// THEME COLORS & STYLES
// ============================================================================
class _AppTheme {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color primaryLight = Color(0xFFD97706);
  static const Color background = Color(0xFFF7F8FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF667085);
  static const Color border = Color(0xFFE4E7EC);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF0284C7);

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    color: text,
  );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: text,
  );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static TextStyle get badge => GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xFFFFFFFF),
  );

  /// 🕐 Format time helper
  static String formatTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      const months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
      ];
      return "${date.day} ${months[date.month - 1]}";
    }
  }
}

class DriverNotificationPage extends StatefulWidget {
  const DriverNotificationPage({super.key});

  @override
  State<DriverNotificationPage> createState() => _DriverNotificationPageState();
}

class _DriverNotificationPageState extends State<DriverNotificationPage> {
  List<DriverNotification> notifications = [];
  int unreadCount = 0;
  bool loading = true;

  StreamSubscription<void>? _notificationSub;
  bool _mounted = false;

  @override
  void initState() {
    super.initState();
    _mounted = true;

    _loadNotifications();

    /// 🔔 Global refresh (FCM / in-app)
    _notificationSub = NotificationEventBus.stream.listen((_) {
      if (_mounted) _loadNotifications(silent: true);
    });
  }

  @override
  void dispose() {
    _mounted = false;
    _notificationSub?.cancel();
    super.dispose();
  }

  /// ===============================
  /// 🔄 LOAD
  /// ===============================
  Future<void> _loadNotifications({bool silent = false}) async {
    if (!_mounted) return;

    try {
      if (!silent) setState(() => loading = true);

      final data = await DriverNotificationService.fetchNotifications();
      final List list = data['notifications'] ?? [];

      if (!_mounted) return;

      setState(() {
        notifications = list
            .map((e) => DriverNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        unreadCount = data['unreadCount'] ?? 0;
        loading = false;
      });
    } catch (e) {
      debugPrint('❌ Notification load error: $e');
      if (_mounted) setState(() => loading = false);
    }
  }

  /// ===============================
  /// 👁 ACTIONS
  /// ===============================
  Future<void> _markRead(String id) async {
    await DriverNotificationService.markAsRead(id);
    NotificationEventBus.refresh();
  }

  Future<void> _markAllRead() async {
    await DriverNotificationService.markAllAsRead();
    NotificationEventBus.refresh();
  }

  Future<void> _delete(String id) async {
    await DriverNotificationService.deleteNotification(id);
    NotificationEventBus.refresh();
  }

  /// ===============================
  /// 🧱 UI
  /// ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppTheme.background,
      appBar: AppBar(
        backgroundColor: _AppTheme.surface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _AppTheme.text),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications',
              style: _AppTheme.heading2,
            ),
            if (unreadCount > 0)
              Text('$unreadCount unread',
                  style: _AppTheme.caption),
          ],
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _AppTheme.primary,
                ),
              ),
            ),
        ],
      ),
      body: _buildNotificationsView(),
    );
  }

  /// ====================
  /// NOTIFICATIONS VIEW
  /// ====================
  Widget _buildNotificationsView() {
    // Show loading spinner only if no notifications AND still loading
    if (notifications.isEmpty && loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return notifications.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _AppTheme.border,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_none,
                      size: 32,
                      color: _AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Notifications',
                    style: _AppTheme.body1,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check back later for offers and updates',
                    textAlign: TextAlign.center,
                    style: _AppTheme.body2,
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _loadNotifications,
            color: _AppTheme.primary,
            child: Stack(
              children: [
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length + (loading ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Show loading indicator at bottom while fetching
                    if (index == notifications.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            height: 40,
                            width: 40,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _AppTheme.primary.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final n = notifications[index];
                    final isRead = n.isRead;

                    return Dismissible(
                      key: Key(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: _AppTheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _delete(n.id),
                      child: _NotificationCard(
                        notification: n,
                        isRead: isRead,
                        onTap: () {
                          if (!isRead) _markRead(n.id);
                          _handleAction(n);
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          );
  }

  /// ===============================
  /// 🚦 ACTION HANDLER
  /// ===============================
  void _handleAction(DriverNotification n) {
    switch (n.action) {
      case 'open_trip':
        // TODO: Navigator.push to trip page with n.tripId
        break;
      case 'open_wallet':
        // TODO: Open wallet page
        break;
      default:
        break;
    }
  }
}

/// =====================================================
/// 🧩 NOTIFICATION CARD (INTERNAL)
/// =====================================================
class _NotificationCard extends StatelessWidget {
  final DriverNotification notification;
  final bool isRead;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(notification.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: _AppTheme.primary.withOpacity(0.1),
          child: Container(
            decoration: BoxDecoration(
              color: _AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isRead ? _AppTheme.border : color.withOpacity(0.3),
                width: isRead ? 1 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 🖼 BANNER IMAGE WITH OFFER OVERLAY
                if (notification.imageUrl != null &&
                    notification.imageUrl!.isNotEmpty)
                  Stack(
                    children: [
                      /// Image
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                          child: Image.network(
                            notification.imageUrl!,
                            height: 450,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 240,
                                color: _AppTheme.background,
                                child: Center(
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: _AppTheme.textSecondary,
                                    size: 32,
                                  ),
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                height: 240,
                                color: _AppTheme.background,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        /// Offer Badge
                        if (notification.type == 'promotion')
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _AppTheme.primary,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: _AppTheme.primary.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.local_offer,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'OFFER',
                                    style: _AppTheme.badge,
                                  ),
                                ],
                              ),
                            ),
                          ),

                        /// Unread dot overlay
                        if (!isRead)
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _typeColor(notification.type),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _typeColor(notification.type).withOpacity(0.4),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                /// 📝 CONTENT
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getTypeLabel(notification.type),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      /// TITLE
                      Text(
                        notification.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight:
                              isRead ? FontWeight.w600 : FontWeight.w800,
                          color: _AppTheme.text,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 6),

                      /// BODY
                      Text(
                        notification.body,
                        style: _AppTheme.caption.copyWith(
                          color: _AppTheme.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 10),

                      /// TIME
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _AppTheme.formatTime(notification.createdAt),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'alert':
        return 'ALERT';
      case 'trip':
        return 'TRIP';
      case 'promotion':
        return 'SPECIAL OFFER';
      case 'payment':
        return 'PAYMENT';
      case 'system':
        return 'SYSTEM';
      default:
        return 'UPDATE';
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'alert':
        return _AppTheme.error;
      case 'trip':
        return _AppTheme.success;
      case 'promotion':
        return _AppTheme.primary;
      case 'payment':
        return _AppTheme.info;
      case 'system':
        return Color(0xFF7C3AED);
      default:
        return _AppTheme.textSecondary;
    }
  }
}
