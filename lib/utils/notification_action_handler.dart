import 'package:flutter/material.dart';

void handleNotificationAction(
  BuildContext context,
  String? action,
  Map<String, dynamic> data,
) {
  switch (action) {
    case 'open_notifications':
      Navigator.pushNamed(context, '/notifications');
      break;

    case 'open_trip':
      final tripId = data['tripId'];
      if (tripId != null) {
        Navigator.pushNamed(context, '/trip', arguments: tripId);
      }
      break;

    case 'open_wallet':
      Navigator.pushNamed(context, '/wallet');
      break;

    case 'open_offer':
      Navigator.pushNamed(context, '/offers');
      break;

    default:
      // Do nothing
      break;
  }
}
