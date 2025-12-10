import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'dart:convert';
import 'vpn_platform_channel.dart';
import 'vpn_platform_channel.dart'; // ✅ فایل محلی

// =============================================================================
// UTILITY CLASSES & FUNCTIONS
// =============================================================================

class VpnConfig {
  final String serverAddress;
  final String serverPort;
  final String protocol;
  final String alias;
  final String fullConfig;
  final String location;

  VpnConfig({
    required this.serverAddress,
    required this.serverPort,
    required this.protocol,
    this.alias = 'بدون نام',
    required this.fullConfig,
    this.location = 'نامشخص',
  });
}

VpnConfig? parseVpnLink(String link) {
  try {
    if (link.startsWith('vless://')) {
      final uri = Uri.parse(link);
      final host = uri.host;
      final port = uri.port.toString();
      final alias = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : 'Vless Config';

      String locationGuess = host.contains('de') ? 'آلمان' : 'نامشخص';

      return VpnConfig(
        serverAddress: host,
        serverPort: port,
        protocol: 'Vless',
        alias: alias,
        fullConfig: link,
        location: locationGuess,
      );
    } else if (link.startsWith('vmess://')) {
      final base64Encoded = link.substring(8);
      final correctedBase64 =
          base64Encoded.padRight((base64Encoded.length + 3) & ~3, '=');

      final decodedJson = utf8.decode(base64.decode(correctedBase64));
      final configMap = jsonDecode(decodedJson);

      String locationGuess =
          configMap['add'].contains('pve.top') ? 'آلمان' : 'نامشخص';

      return VpnConfig(
        serverAddress: configMap['add'],
        serverPort: configMap['port'].toString(),
        protocol: 'VMess',
        alias: configMap['ps'] ?? 'VMess Config',
        fullConfig: decodedJson,
        location: locationGuess,
      );
    } else {
      return null;
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error parsing VPN link: $e');
    }
    return null;
  }
}

const platform = MethodChannel('com.iranianprovpn.app/vpn');

Future<String?> disconnectVPN() async {
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

// =============================================================================
// MAIN APP WIDGETS
// =============================================================================

void main() {
  runApp(const VipVpnApp());
}

class VipVpnApp extends StatelessWidget {
  const VipVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vip Pro VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1E38),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF673AB7),
          secondary: Color(0xFF9C27B0),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
        fontFamily: 'Vazir',
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  void _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final String? subLink = prefs.getString('sub_link');

    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    if (subLink != null && subLink.isNotEmpty) {
      setState(() {
        _isLoggedIn = true;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await disconnectVPN();

    await prefs.remove('sub_link');
    await prefs.remove('server_location');
    await prefs.remove('protocol_type');
    await prefs.remove('config_alias');

    if (mounted) {
      setState(() {
        _isLoggedIn = false;
      });
    }
  }

  void _login(String link) {
    setState(() {
      _isLoggedIn = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return _isLoggedIn
        ? VpnHomePage(onLogout: _logout)
        : LoginPage(onLogin: _login);
  }
}

class LoginPage extends StatefulWidget {
  final Function(String) onLogin;
  const LoginPage({super.key, required this.onLogin});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _linkController = TextEditingController();
  String _errorMessage = '';

  void _saveAndLogin() async {
    final link = _linkController.text.trim();

    if (link.isEmpty) {
      setState(() {
        _errorMessage = 'لینک اشتراک نمی‌تواند خالی باشد.';
      });
      return;
    }

    final config = parseVpnLink(link);
    if (config == null) {
      setState(() {
        _errorMessage = 'لینک وارد شده معتبر (Vless/Vmess) نیست.';
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sub_link', link);
    await prefs.setString('server_location', config.location);
    await prefs.setString('protocol_type', config.protocol);
    await prefs.setString('config_alias', config.alias);

    if (mounted) {
      widget.onLogin(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Vip Pro VPN',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.vpn_key_sharp,
                color: Theme.of(context).colorScheme.primary,
                size: 80,
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _linkController,
                decoration: InputDecoration(
                  labelText: 'لینک اشتراک VLESS/VMESS',
                  hintText: 'لینک اشتراک خود را اینجا کپی کنید...',
                  errorText: _errorMessage.isNotEmpty ? _errorMessage : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.secondary,
                        width: 3),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                maxLines: 5,
                minLines: 3,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _saveAndLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 5,
                ),
                child: const Text(
                  'ذخیره و ورود',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'فقط لینک‌های Vless و Vmess معتبر هستند.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VpnHomePage extends StatefulWidget {
  final VoidCallback onLogout;
  const VpnHomePage({super.key, required this.onLogout});

  @override
  State<VpnHomePage> createState() => _VpnHomePageState();
}

class _VpnHomePageState extends State<VpnHomePage> {
  bool _isConnected = false;
  bool _isConnecting = false;
  String _statusMessage = 'قطع شده';
  double usedGigabytes = 0.0;
  double totalGigabytes = 0.0;
  String serverLocation = 'نامشخص';
  String protocolType = 'ناشناس';
  String configAlias = 'هیچ کانفیگی انتخاب نشده';
  int daysLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadConfigAndSubscription();

    _timer = Timer.periodic(const Duration(hours: 1), (timer) {
      _updateSubscription();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _loadConfigAndSubscription() async {
    final prefs = await SharedPreferences.getInstance();

    serverLocation = prefs.getString('server_location') ?? 'نامشخص';
    protocolType = prefs.getString('protocol_type') ?? 'ناشناس';
    configAlias = prefs.getString('config_alias') ?? 'هیچ کانفیگی انتخاب نشده';

    if (mounted) {
      setState(() {});
    }
    _updateSubscription();
  }

  void _updateSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    final String? subscriptionLink = prefs.getString('sub_link');

    if (subscriptionLink == null) {
      if (mounted) {
        widget.onLogout();
      }
      return;
    }
    try {
      final response = await http.get(Uri.parse(subscriptionLink));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            usedGigabytes = 25.5;
            totalGigabytes = 100.0;
            daysLeft = 50;
          });
        }
      } else {
        if (mounted) {
          _showSnackbar(context,
              'خطا در دریافت اطلاعات اشتراک. وضعیت: ${response.statusCode}',
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackbar(context, 'خطا در اتصال به سرور: $e', isError: true);
      }
    }
  }

Future<void> startVPNConnection(String rawLink) async {
  if (kIsWeb) {
    // Web: فقط simulation
    print('🌐 Web VPN simulation: $rawLink');
    return;
  }
  
  try {
    await VpnPlatformChannel.startVpnConnection(rawLink);
    print('✅ VPN requested: $rawLink');
  } catch (e) {
    print('❌ VPN Error: $e');
    rethrow;
  }
}


  void _toggleVpn() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _statusMessage = 'در حال اتصال...';
    });

    if (_isConnected) {
      await disconnectVPN();

      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _statusMessage = 'قطع شد';
        });
        _showSnackbar(context, 'اتصال قطع شد.', isError: false);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final String? rawLink = prefs.getString('sub_link');

      if (rawLink == null || rawLink.isEmpty) {
        if (mounted) {
          _showSnackbar(
              context, 'لینک اشتراک یافت نشد. لطفاً دوباره وارد شوید.',
              isError: true);
          widget.onLogout();
        }
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _statusMessage = 'قطع شده';
          });
        }
        return;
      }

      try {
        await startVPNConnection(rawLink);

        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          setState(() {
            _isConnected = true;
            _isConnecting = false;
            _statusMessage = 'متصل شد';
          });
          _showSnackbar(context, 'VPN متصل شد ✅', isError: false);
        }
      } catch (e) {
        if (mounted) {
          _showSnackbar(context, 'خطا در اتصال VPN: $e', isError: true);
          setState(() {
            _isConnecting = false;
            _statusMessage = 'خطا در اتصال';
          });
        }
      }
    }
  }

  void _showSnackbar(BuildContext context, String message,
      {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.right),
        backgroundColor: isError ? Colors.red.shade900 : Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final percent = totalGigabytes > 0 ? usedGigabytes / totalGigabytes : 0.0;

    final buttonColor =
        _isConnected ? const Color(0xFF4CAF50) : const Color(0xFF673AB7);
    final shadowColor = _isConnected
        ? Colors.green.shade900.withAlpha(153)
        : Colors.deepPurple.shade900.withAlpha(153);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vip Pro VPN'),
        backgroundColor: const Color(0xFF0F1E38),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _updateSubscription,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
            tooltip: 'خروج و تغییر لینک',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildConnectionButton(buttonColor, shadowColor, percent),
              const SizedBox(height: 40),
              _buildStatusCard(percent),
              const SizedBox(height: 15),
              _buildConfigInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionButton(
      Color buttonColor, Color shadowColor, double percent) {
    return Column(
      children: [
        GestureDetector(
          onTap: _isConnecting ? null : _toggleVpn,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [buttonColor, buttonColor.withAlpha(204)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 25,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: _isConnecting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Icon(
                      _isConnected ? Icons.lock_open : Icons.lock,
                      size: 80,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _statusMessage,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(double percent) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('حجم استفاده شده:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 15),
          LinearPercentIndicator(
            lineHeight: 14.0,
            percent: percent,
            backgroundColor: Colors.white.withAlpha(25),
            progressColor: percent > 0.8 ? Colors.redAccent : Colors.lightBlue,
            barRadius: const Radius.circular(7),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('باقی‌مانده اشتراک:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '$daysLeft روز',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.amber),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.vpn_lock,
            label: 'نام کانفیگ:',
            value: configAlias,
            color: Colors.cyanAccent,
          ),
          const Divider(color: Colors.white10, height: 20),
          _buildInfoRow(
            icon: Icons.public,
            label: 'مکان سرور:',
            value: serverLocation,
            color: Colors.lightGreenAccent,
          ),
          const Divider(color: Colors.white10, height: 20),
          _buildInfoRow(
            icon: Icons.security,
            label: 'پروتکل:',
            value: protocolType,
            color: Colors.orangeAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
