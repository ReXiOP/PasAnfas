import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as fow;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ADDED for background service
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

// ------------------- BACKGROUND SERVICE -------------------

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // --- Configuration variables ---
  int selectedMinutes = prefs.getInt('selectedMinutes') ?? 5;
  bool overlayEnabled = prefs.getBool('overlayEnabled') ?? false;
  Timer? timer;

  // Function to start/restart the timer
  void restartTimer() {
    timer?.cancel(); // Cancel any existing timer

    timer = Timer.periodic(Duration(minutes: selectedMinutes), (timer) async {
      // 1. Show standard notification
      await _NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'পাছ আন ফাস',
        body: 'পাছ আন ফাস হচ্ছে?',
      );

      // 2. Show overlay window if enabled
      if (overlayEnabled) {
        // ✅ PERMISSION CHECK: Service can't request, only check.
        // Permission must be granted from the UI.
        final hasPerm = await fow.FlutterOverlayWindow.isPermissionGranted();
        if (hasPerm) {
          fow.FlutterOverlayWindow.showOverlay(
            enableDrag: true,
            flag: fow.OverlayFlag.defaultFlag,
            alignment: fow.OverlayAlignment.center,
            visibility: fow.NotificationVisibility.visibilityPublic,
            overlayTitle: "পাছ আন ফাস চলছে",
            overlayContent: "রিমাইন্ডার সক্রিয় আছে",
          );
        }
      }
    });
  }

  // Initial start
  restartTimer();

  // Listen for configuration changes from the UI
  service.on('setConfiguration').listen((data) {
    if (data != null) {
      if (data['selectedMinutes'] != null) {
        selectedMinutes = data['selectedMinutes'];
        prefs.setInt('selectedMinutes', selectedMinutes);
      }
      if (data['overlayEnabled'] != null) {
        overlayEnabled = data['overlayEnabled'];
        prefs.setBool('overlayEnabled', overlayEnabled);
      }
      restartTimer();
    }
  });

  // Listen for the 'stop' command from the UI
  service.on('stop').listen((event) {
    timer?.cancel();
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// --- End of Background Service Logic ---

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'pasch_service_channel',
      initialNotificationTitle: 'পাছ আন ফাস সার্ভিস',
      initialNotificationContent: 'রিমাইন্ডার সার্ভিস চলছে...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // CRITICAL FIX: Initialize notifications and create channels FIRST
  await _NotificationService().initMain();

  // Now configure the service
  await initializeService();

  runApp(PaschAnFashApp());
}

// ------------------- App -------------------
class PaschAnFashApp extends StatefulWidget {
  @override
  _PaschAnFashAppState createState() => _PaschAnFashAppState();
}

class _PaschAnFashAppState extends State<PaschAnFashApp> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool('darkMode') ?? false;
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> _toggleTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', isDark);
    setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
  }

  void _finishSplash() {
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'পাছ আন ফাস',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green, brightness: Brightness.light),
        textTheme: GoogleFonts.notoSansBengaliTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green, brightness: Brightness.dark),
        textTheme: GoogleFonts.notoSansBengaliTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      themeMode: _themeMode,
      home: _showSplash
          ? SplashScreen(onFinish: _finishSplash)
          : HomeScreen(toggleTheme: _toggleTheme, themeMode: _themeMode),
    );
  }
}

// ------------------- Splash Screen -------------------
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const SplashScreen({super.key, required this.onFinish});
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _patternAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
    _patternAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.02, 0.02),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      widget.onFinish();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade200, Colors.green.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SlideTransition(
            position: _patternAnimation,
            child: Opacity(
              opacity: 0.1,
              child: Image.asset(
                'assets/images/islamic_pattern.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "মহাসম্মানিত  সাইয়্যিদুল আ'ইয়াদ শরীফ উনার সম্মানার্থে",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansBengali(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black),
                ),
                const SizedBox(height: 20),
                Image.asset(
                  'assets/images/islamic_logo.jpg',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 20),
                Text(
                  "পাছ আন ফাস",
                  style: GoogleFonts.notoSansBengali(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
                const SizedBox(height: 10),
                Text(
                  "জিকির রিমাইন্ডার",
                  style: GoogleFonts.notoSansBengali(
                      fontSize: 16, color: Colors.green[900]),
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.green[100],
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------- Home Screen -------------------
class HomeScreen extends StatefulWidget {
  final Function(bool) toggleTheme;
  final ThemeMode themeMode;
  const HomeScreen(
      {super.key, required this.toggleTheme, required this.themeMode});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedMinutes = 5;
  bool _running = false;
  bool _overlayEnabled = false;
  final _customController = TextEditingController();
  final List<int> _presetMinutes = const [1, 5, 15, 30];
  final _service = FlutterBackgroundService();

  @override
  void initState() {
    super.initState();
    _loadStateFromPrefs();

    _service.on('running').listen((event) {
      if (!mounted) return;
      setState(() {
        _running = event?['is_running'] ?? false;
      });
    });
  }

  Future<void> _loadStateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedMinutes = prefs.getInt('selectedMinutes') ?? 5;
      _overlayEnabled = prefs.getBool('overlayEnabled') ?? false;
    });

    final isRunning = await _service.isRunning();
    if (!mounted) return;
    setState(() {
      _running = isRunning;
    });
  }

  // ✅ FIXED: Robust start reminders with permission check
  void _startReminders() async {
    // Check permission FIRST if overlay is enabled
    if (_overlayEnabled) {
      final hasPerm = await fow.FlutterOverlayWindow.isPermissionGranted();
      if (!hasPerm) {
        // We MUST request permission from the UI
        await fow.FlutterOverlayWindow.requestPermission();
        final nowHasPerm = await fow.FlutterOverlayWindow.isPermissionGranted();

        // If user still denied it, show a warning and do not start
        if (!nowHasPerm) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
              Text('Overlay permission is required to start.'),
              backgroundColor: Colors.red,
            ),
          );
          return; // Do not start the service
        }
      }
    }

    // --- Permission is granted (or not needed), proceed with starting ---
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selectedMinutes', _selectedMinutes);
    await prefs.setBool('overlayEnabled', _overlayEnabled);

    await _service.startService();
    _service.invoke('setConfiguration', {
      'selectedMinutes': _selectedMinutes,
      'overlayEnabled': _overlayEnabled
    });

    if (!mounted) return;
    setState(() {
      _running = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('রিমাইন্ডার চালু হয়েছে! প্রতি $_selectedMinutes মিনিট।'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _stopReminders() {
    _service.invoke('stop');
    if (!mounted) return;
    setState(() {
      _running = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('রিমাইন্ডার বন্ধ করা হয়েছে।'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _toggleOverlayPermission() async {
    bool newOverlayState;

    final granted = await fow.FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      // If permission isn't granted, requesting it will set the switch
      await fow.FlutterOverlayWindow.requestPermission();
      final now = await fow.FlutterOverlayWindow.isPermissionGranted();
      newOverlayState = now;
    } else {
      // If permission is already granted, just toggle the switch state
      newOverlayState = !_overlayEnabled;
      if (!newOverlayState) fow.FlutterOverlayWindow.closeOverlay();
    }

    if (!mounted) return;
    setState(() => _overlayEnabled = newOverlayState);

    // Save to prefs and update service
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlayEnabled', newOverlayState);
    if (_running) {
      _service.invoke('setConfiguration', {'overlayEnabled': newOverlayState});
    }
  }

  // ✅ FIXED: Robust "Test Now" with permission check
  Future<void> _testOverlay() async {
    final has = await fow.FlutterOverlayWindow.isPermissionGranted();
    if (!has) {
      await fow.FlutterOverlayWindow.requestPermission();
      // Check again after requesting
      final nowHas = await fow.FlutterOverlayWindow.isPermissionGranted();
      if (!nowHas) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Overlay permission was denied.'),
            backgroundColor: Colors.red,
          ),
        );
        return; // Don't show
      }
    }

    // Permission is granted, show the overlay
    fow.FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      flag: fow.OverlayFlag.defaultFlag,
      alignment: fow.OverlayAlignment.center,
      visibility: fow.NotificationVisibility.visibilityPublic,
      overlayTitle: "টেস্ট ওভারলে",
      overlayContent: "এটি একটি পরীক্ষা",
    );
  }

  // ✅ FIXED: Robust "5s Test" with permission check
  Future<void> _runOneTimeTest(Duration duration) async {
    bool showOverlay = _overlayEnabled;

    // If overlay is enabled, check permission *before* starting the timer
    if (_overlayEnabled) {
      final has = await fow.FlutterOverlayWindow.isPermissionGranted();
      if (!has) {
        await fow.FlutterOverlayWindow.requestPermission();
        final nowHas = await fow.FlutterOverlayWindow.isPermissionGranted();
        if (!nowHas) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Overlay permission denied. Test will run without overlay.'),
              backgroundColor: Colors.orange,
            ),
          );
          showOverlay = false; // Run test with overlay explicitly off
        }
      }
    }

    // Permission is granted (or overlay is off), run the test as normal
    _runTimerTest(duration, showOverlay);
  }

  // Helper function for the 5s test
  void _runTimerTest(Duration duration, bool showOverlay) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${duration.inSeconds} সেকেন্ডের টেস্ট শুরু...'),
        backgroundColor: Colors.blue,
      ),
    );

    Timer(duration, () async {
      // 1. Show standard notification
      await _NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'টেস্ট রিমাইন্ডার',
        body: 'এটি একটি ${duration.inSeconds} সেকেন্ডের টেস্ট।',
      );

      // 2. Show overlay window if enabled *and* permission was granted
      if (showOverlay) {
        // We already checked permission, but one last check
        final hasPerm = await fow.FlutterOverlayWindow.isPermissionGranted();
        if (hasPerm) {
          fow.FlutterOverlayWindow.showOverlay(
            enableDrag: true,
            flag: fow.OverlayFlag.defaultFlag,
            alignment: fow.OverlayAlignment.center,
            visibility: fow.NotificationVisibility.visibilityPublic,
            overlayTitle: "টেস্ট ওভারলে",
            overlayContent: "এটি একটি পরীক্ষা",
          );
        }
      }
    });
  }

  void _setCustomMinutes() async {
    final v = int.tryParse(_customController.text);
    if (v != null && v > 0) {
      if (!mounted) return;
      setState(() => _selectedMinutes = v);
      FocusScope.of(context).unfocus();
      _customController.clear();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('selectedMinutes', v);
      if (_running) {
        _service.invoke('setConfiguration', {'selectedMinutes': v});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeMode == ThemeMode.dark;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('পাছ আন ফাস',
            style:
            TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade700, Colors.green.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode_outlined),
            color: Colors.white,
            tooltip: isDark ? "Switch to Light Mode" : "Switch to Dark Mode",
            onPressed: () => widget.toggleTheme(!isDark),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                'ইন্টার্ভাল নির্বাচন করুন',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SegmentedButton<int>(
                segments: _presetMinutes
                    .map((minutes) => ButtonSegment<int>(
                  value: minutes,
                  label: Text('${minutes}m'),
                  icon: const Icon(Icons.timer_outlined),
                ))
                    .toList(),
                selected: _presetMinutes.contains(_selectedMinutes)
                    ? {_selectedMinutes}
                    : {},
                onSelectionChanged: (Set<int> newSelection) async {
                  final newMinutes = newSelection.first;
                  setState(() {
                    _selectedMinutes = newMinutes;
                  });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('selectedMinutes', newMinutes);
                  if (_running) {
                    _service.invoke(
                        'setConfiguration', {'selectedMinutes': newMinutes});
                  }
                },
                showSelectedIcon: true,
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _customController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Custom (minutes)',
                      hintText: 'e.g. 45',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _setCustomMinutes,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 20)),
                  child: const Text('Set'),
                )
              ]),
              const SizedBox(height: 24),
              Card.filled(
                child: SwitchListTile(
                  title: const Text('Overlay Reminder',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('অন্যান্য অ্যাপের উপর ভেসে উঠবে',
                      style: theme.textTheme.bodySmall),
                  value: _overlayEnabled,
                  onChanged: (val) => _toggleOverlayPermission(),
                  secondary: Icon(
                    _overlayEnabled
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _running ? _stopReminders : _startReminders,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  backgroundColor: _running ? theme.colorScheme.error : null,
                  foregroundColor:
                  _running ? theme.colorScheme.onError : null,
                ),
                icon: Icon(_running ? Icons.stop_circle : Icons.play_circle),
                label: Text(_running ? 'Stop Reminders' : 'Start Reminders'),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _testOverlay,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Test Overlay Now'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => _runOneTimeTest(const Duration(seconds: 5)),
                icon: const Icon(Icons.hourglass_empty_rounded),
                label: const Text('Test Reminder (5s)'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: theme.colorScheme.primary),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------- Notification Service -------------------
class _NotificationService {
  static final _instance = _NotificationService._internal();
  factory _NotificationService() => _instance;
  _NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  Future<void> initMain() async {
    // Channel for regular reminders
    const channelReminders = AndroidNotificationChannel(
      'pasch_channel', // id
      'Pasch Ann Fash Reminders', // title
      description: 'Zikir reminder notifications', // description
      importance: Importance.max,
    );

    // Channel for the persistent background service
    const channelService = AndroidNotificationChannel(
      'pasch_service_channel', // id
      'Pasch Ann Fash Service', // title
      description: 'Service for keeping reminders active', // description
      importance: Importance.low, // Low importance so it's less intrusive
    );

    final androidPlugin = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channelReminders);
    await androidPlugin?.createNotificationChannel(channelService);

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: iOS);

    await _plugin.initialize(settings);
  }

  Future<void> showNotification(
      {required int id, String? title, String? body}) async {
    const androidDetails = AndroidNotificationDetails(
      'pasch_channel', // Use the reminder channel
      'Pasch Ann Fash Reminders',
      channelDescription: 'Zikir reminder notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
    NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _plugin.show(id, title, body, details);
  }
}

// ------------------- Overlay -------------------
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green, brightness: Brightness.light),
        textTheme: GoogleFonts.notoSansBengaliTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(child: OverlayWidget()),
      ),
    );
  }
}

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  double top = 250;
  double left = 50;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          left += details.delta.dx;
          top += details.delta.dy;
        });
      },
      child: Stack(children: [
        Positioned(
          left: left,
          top: top,
          child: Card(
            color: theme.colorScheme.surfaceContainerHigh.withOpacity(0.95),
            elevation: 8.0,
            child: Padding(
              padding: const EdgeInsets.only(
                  left: 16, right: 8, top: 10, bottom: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'ছবকের নিয়ত করুন',
                    style: GoogleFonts.notoSansBengali(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'পাছ আন ফাস হচ্ছে কি?',
                    style: GoogleFonts.notoSansBengali(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                ]),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
                  iconSize: 20.0,
                  onPressed: () async {
                    await fow.FlutterOverlayWindow.closeOverlay();
                  },
                ),
              ]),
            ),
          ),
        )
      ]),
    );
  }
}