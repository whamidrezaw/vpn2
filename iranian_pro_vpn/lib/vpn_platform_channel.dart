import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class VpnPlatformChannel {
  static const platform = MethodChannel('com.iranianprovpn.app/vpn');

  static Future<String?> startVpnConnection(String rawConfigLink) async {
    if (kDebugMode) {
      print("Attempting to invoke startVpnService...");
      print("Config Link: $rawConfigLink");
    }
    try {
      final String? result = await platform.invokeMethod(
        'startVpnService',
        {'configLink': rawConfigLink},
      );
      if (kDebugMode) {
        print("VPN Method Result: $result");
      }
      return result;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print("Failed to start VPN via Platform Channel: '${e.message}'.");
      }
      return 'Error: ${e.message}';
    }
  }

  static Future<String?> disconnectVPN() async {
    if (kDebugMode) {
      print("Attempting to invoke stopVpnService...");
    }
    try {
      final String? result = await platform.invokeMethod('stopVpnService');
      return result;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print("Failed to stop VPN: '${e.message}'.");
      }
      return 'Error: ${e.message}';
    }
  }
}