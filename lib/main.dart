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
          seedColor: const Color(0xFF2E7D32), // A deep, professional green
          brightness: Brightness.light,
          background: const Color(0xFFF7F9FC), // A slightly cool off-white
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.notoSansBengaliTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66BB6A), // A more vibrant green for dark mode
          brightness: Brightness.dark,
          background: const Color(0xFF121212), // Material standard dark background
          surface: const Color(0xFF1E1E1E), // Slightly lighter surface for cards
        ),
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
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        widget.onFinish();
      }
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
          // Layer 1: Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF66BB6A), // Lighter green
                  Color(0xFF2E7D32), // Deeper green
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Layer 2: Pattern Image with Opacity
          Opacity(
            opacity: 0.1,
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/islamic_pattern.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // Layer 3: Frosted Glass Effect for a modern look
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
            child: Container(
              color: Colors.black.withOpacity(0.1),
            ),
          ),
          // Layer 4: Main Content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      "মহাসম্মানিত  সাইয়্যিদুল আ'ইয়াদ শরীফ উনার সম্মানার্থে",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansBengali(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          shadows: [
                            const Shadow(
                              blurRadius: 10.0,
                              color: Colors.black26,
                              offset: Offset(2.0, 2.0),
                            ),
                          ]),
                    ),
                  ),
                  const Spacer(flex: 1),
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 25,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/islamic_logo.jpg',
                              width: 120,
                              height: 120,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "পবিত্র পাস আনফাস",
                          style: GoogleFonts.notoSansBengali(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                const Shadow(
                                  blurRadius: 15.0,
                                  color: Colors.black45,
                                  offset: Offset(2.0, 3.0),
                                ),
                              ]),
                        ),
                        const SizedBox(height: 8),
                        Text("জিকির রিমাইন্ডার",
                            style: GoogleFonts.notoSansBengali(
                                fontSize: 18,
                                color: Colors.white.withOpacity(0.9),
                                shadows: [
                                  const Shadow(
                                    blurRadius: 10.0,
                                    color: Colors.black38,
                                    offset: Offset(1.0, 1.0),
                                  ),
                                ])),
                      ],
                    ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
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
            const SnackBar(
              content: Text('Overlay permission is required to start.'),
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
      const SnackBar(
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
          const SnackBar(
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
            const SnackBar(
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

  // --- ⬇️ MODIFIED HELPER FUNCTION ⬇️ ---
  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final ScrollController scrollController = ScrollController();
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title),
          content: Scrollbar(
            controller: scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: scrollController,
              child: Text(
                content,
                style: GoogleFonts.notoSansBengali(
                  // Ensure font is applied
                    fontSize: 15,
                    height: 1.6 // Added line height for readability
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বন্ধ করুন'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeMode == ThemeMode.dark;
    final theme = Theme.of(context);

    // --- ⬇️ NEW STRING CONTENT ⬇️ ---
    const String zikirInfo = '''
পবিত্র পাস আনফাস যিকির মুবারক

পাস আনফাস হচ্ছে শ্বাস প্রশ্বাসের যিকির। প্রতিবার শ্বাস নেয়ার সময় ও ছাড়ার সময় মনে মনে খেয়াল করে এই পবিত্র যিকির করতে হয়। অর্থাৎ মুখে শব্দ করে নয় বরং শ্বাস-প্রশ্বাসের সাথে খেয়ালের দ্বারা করতে হয়। প্রতিবার খেয়াল ছুটে যাওয়ার পর নতুন করে স্বরণ করতে হয়। 

এই স্বরণ করে দেয়ার উদ্দেশ্যেই পাস আনফাস এ্যাপটি করা হয়েছে। 

পাস আনফাস করার নিয়ম: 
পবিত্র পাস আনফাস যিকির মুবারক- মহাসম্মানিত ও মহাপবিত্র সাইয়্যিদুনা হযরত শায়েখ আলাইহিস সালাম উনার দিকে রুজু হয়ে, সালিকগণ সকল সময়, সর্বাবস্থায় এই পবিত্র যিকির করতে থাকবে।

শ্বাস ফেলবার সময় لَا اِلٰهَ  (লা-ইলাহা) এবং শ্বাস টানবার সময় اِلَّا اللّٰهُ (ইল্লাল্লাহ) খেয়াল করবে। 
শ্বাস ছেড়ে দেয়ার সময় লা-ইলাহা। এর দ্বারা দুনিয়ার মুহব্বত, নাস্তিকতা অন্তর থেকে বের হয়ে যাবে।
শ্বাস টানার সময় ইল্লাল্লাহ খেয়াল করতে হবে। এর দ্বারা মহান আল্লাহ পাক উনার মুহব্বত, মা’রিফত, তাওয়াল্লুক নিছবত মুবারক অন্তরে প্রবেশ করবে। 

অর্থাৎ পবিত্র পাস-আনফাস যিকির মুবারক দ্বারা অন্তরে মহান আল্লাহ পাক উনার মুহব্বত মুবারক পয়দা হবে, দুনিয়ার মুহব্বত দূর হবে, বিপদ-আপদ ও বালা-মুছীবত দূর হবে, রিযিক্বে বরকত হবে, মৃত্যুর সময় ঈমান নছীব হবে। সুবহানাল্লাহ!
''';

    const String appGuide = '''
এ্যাপটি ব্যবহারের নির্দেশিকা

ইন্টার্ভাল/সময় নির্বাচন : 
কতক্ষণ পর পর স্বরণ করতে চান সেই সময়টা নির্বাচন করুন। এখানে ১ মিনিট, ৫ মিনিট, ১৫ মিনিট ও ৩০ মিনিট অপশন হিসেবে দেয়া আছে। আপনি চাইলে Custom (Minutes) ঘরে  আপনার পছন্দ মতো সময় (মিনিট) লিখে Set বাটন চাপুন। যেমন- ১০ মিনিট পর পর চাইলে 10 (ইংরেজিতে) লিখে Set বাটন চাপুন।

Overlay Reminder (ওভারলে রিমাইন্ডার):
আপনি ফোন ব্যবহারকালীন যে কোন এ্যাপের উপর বার্তা ভেসে ওঠবে। সেটি (x) ক্লোজ চেপে বন্ধ করতে হবে। আপনি যদি এটি না চান তাহলে ওভারলে রিমাইন্ডার অপশনটি বন্ধ করতে পারবেন। 

স্টার্ট রিমাইন্ডার:
সময় নির্ধারণ করার পর Start Reminder বাটনে চাপুন। রিমাইন্ডার বন্ধ করতে চাইলে Stop Reminder চাপুন। 

নাইট মুড/ডে মুড:
নাইট মুড চালু করতে উপরের ডান কোণায় (আইকন) অপশন চাপুন।
''';

    return Scaffold(
      appBar: AppBar(
        title: const Text('পাছ আন ফাস',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: theme.colorScheme.primary,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_outlined),
            color: Colors.white,
            tooltip: isDark ? "Switch to Light Mode" : "Switch to Dark Mode",
            onPressed: () => widget.toggleTheme(!isDark),
          )
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.background,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.2, 0.2],
          ),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- MAIN ACTION BUTTON ---
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _running ? _stopReminders : _startReminders,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        vertical: 30, horizontal: 20),
                    decoration: BoxDecoration(
                      color: _running
                          ? theme.colorScheme.errorContainer
                          : theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _running
                              ? theme.colorScheme.error.withOpacity(0.3)
                              : theme.colorScheme.primary.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(
                            _running
                                ? Icons.stop_circle_rounded
                                : Icons.play_circle_fill_rounded,
                            size: 48,
                            color: _running
                                ? theme.colorScheme.onErrorContainer
                                : theme.colorScheme.onPrimaryContainer),
                        const SizedBox(height: 12),
                        Text(
                            _running
                                ? 'রিমাইন্ডার বন্ধ করুন'
                                : 'রিমাইন্ডার চালু করুন',
                            style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _running
                                    ? theme.colorScheme.onErrorContainer
                                    : theme.colorScheme.onPrimaryContainer)),
                      ],
                    ),
                  ),
                ),

                // --- INTERVAL CARD ---
                const SizedBox(height: 24),
                _buildSectionCard(
                  theme: theme,
                  icon: Icons.timer_rounded,
                  title: 'ইন্টার্ভাল/সময়  নির্বাচন করুন',
                  child: Column(
                    children: [
                      SegmentedButton<int>(
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        segments: _presetMinutes
                            .map((minutes) => ButtonSegment<int>(
                          value: minutes,
                          label: Text('${minutes} মি.'),
                        ))
                            .toList(),
                        selected: _presetMinutes.contains(_selectedMinutes)
                            ? {_selectedMinutes}
                            : {},
                        onSelectionChanged: (Set<int> newSelection) async {
                          final newMinutes = newSelection.first;
                          setState(() => _selectedMinutes = newMinutes);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('selectedMinutes', newMinutes);
                          if (_running) {
                            _service.invoke('setConfiguration',
                                {'selectedMinutes': newMinutes});
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _customController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'অন্যান্য সময় (মিনিট)',
                              hintText: 'e.g. 45',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: _setCustomMinutes,
                          icon: const Icon(Icons.check_rounded),
                          tooltip: 'Set Custom Time',
                          iconSize: 24,
                          padding: const EdgeInsets.all(16),
                        )
                      ]),
                    ],
                  ),
                ),

                // --- OVERLAY CARD ---
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme: theme,
                  icon: Icons.layers_rounded,
                  title: 'ওভারলে রিমাইন্ডার',
                  child: Column(
                    children: [
                      SwitchListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        title: const Text('সক্রিয় করুন',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('অন্যান্য অ্যাপের উপর ভেসে উঠবে'),
                        value: _overlayEnabled,
                        onChanged: (val) => _toggleOverlayPermission(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _testOverlay,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('এখনই টেস্ট'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                _runOneTimeTest(const Duration(seconds: 5)),
                            icon: const Icon(Icons.hourglass_bottom_rounded),
                            label: const Text('৫ সেকেন্ড টেস্ট'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // --- INFO SECTION ---
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.info_outline),
                      label: const Text('যিকির সম্পর্কে জানুন'),
                      onPressed: () =>
                          _showInfoDialog('পাস আনফাস যিকির', zikirInfo),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.help_outline),
                      label: const Text('অ্যাপ গাইড'),
                      onPressed: () =>
                          _showInfoDialog('ব্যবহারের নির্দেশিকা', appGuide),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
      {required ThemeData theme,
        required IconData icon,
        required String title,
        required Widget child}) {
    return Card(
      elevation: 2,
      shadowColor: theme.colorScheme.shadow.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
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
    NotificationDetails(android: androidDetails, iOS: iosDetails,);
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
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green, brightness: Brightness.dark),
      ),
      home: const Scaffold(
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
  @override
  Widget build(BuildContext context) {
    // Using MediaQuery to adapt to different screen sizes and themes
    final theme = Theme.of(context);
    final isDarkMode = MediaQuery.of(context).platformBrightness == Brightness.dark;

    final cardColor = isDarkMode
        ? const Color(0xFF1E1E1E)
        : Colors.white;
    final textColor = isDarkMode
        ? Colors.white.withOpacity(0.9)
        : Colors.black87;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10.0,
                spreadRadius: 2.0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_active,
                  color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ছবকের নিয়ত করুন',
                    style: GoogleFonts.notoSansBengali(
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'পাছ আন ফাস হচ্ছে কি?',
                    style: GoogleFonts.notoSansBengali(
                      fontSize: 14,
                      color: textColor.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () async {
                  await fow.FlutterOverlayWindow.closeOverlay();
                },
                child: Icon(Icons.close, color: textColor.withOpacity(0.7), size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


