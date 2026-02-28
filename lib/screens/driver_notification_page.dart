import 'dart:async';
import 'package:flutter/material.dart';

import '../services/driver_notification_service.dart';
import '../models/driver_notification.dart';
import '../main.dart'; // 🔔 NotificationEventBus

class DriverNotificationPage extends StatefulWidget {
  const DriverNotificationPage({super.key});

  @override
  State<DriverNotificationPage> createState() => _DriverNotificationPageState();
}

class _DriverNotificationPageState extends State<DriverNotificationPage> {
  List<DriverNotification> notifications = [];
  int unreadCount = 0;
  bool loading = true;

  StreamSubscription? _notificationSub;
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
            .map((e) => DriverNotification.fromJson(e))
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
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications'),
            if (unreadCount > 0)
              Text('$unreadCount unread', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
          ? const Center(child: Text('No notifications'))
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final n = notifications[index];
                  final isRead = n.isRead;

                  return Dismissible(
                    key: Key(n.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
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
            ),
    );
  }

  /// ===============================
  /// 🚦 ACTION HANDLER (EXTEND LATER)
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
        // No action
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

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🟦 TYPE STRIP
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
            ),

            /// 🖼 BANNER (OPTIONAL)
            if (notification.bannerUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Image.network(
                  notification.bannerUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// 🔴 UNREAD DOT
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),

                  /// TITLE
                  Text(
                    notification.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  /// BODY
                  Text(
                    notification.body,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),

                  const SizedBox(height: 12),

                  /// TIME
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatTime(notification.createdAt),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'alert':
        return Colors.red;
      case 'trip':
        return Colors.green;
      case 'promotion':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime date) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${date.day} ${months[date.month - 1]}, "
        "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}
