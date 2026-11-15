import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static BuildContext? get context => navigatorKey.currentContext;

  /// Transfer id from a notification tap received before the user reached
  /// the home screen (cold start or still on splash).
  static String? pendingTransferId;

  static void openTransfers() => _openFromHome(RoutesName.transfers);

  static void openTransfer(String? transferId) => transferId == null
      ? openTransfers()
      : _openFromHome(RoutesName.transferDetails, transferId);

  /// Rebuilds the stack as Home → [route] so repeated taps never pile up
  /// duplicate screens.
  static void _openFromHome(String route, [Object? arguments]) {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      route,
      ModalRoute.withName(RoutesName.home),
      arguments: arguments,
    );
  }
}
