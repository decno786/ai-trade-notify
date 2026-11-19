import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';

// ================================================================ look & feel
const kBg = Color(0xFF0A0F1E);
const kBg2 = Color(0xFF111833);
const kSurface = Color(0xFF131A2F);
const kSurface2 = Color(0xFF1B2442);
const kBorder = Color(0xFF263052);
const kText = Color(0xFFEAF0FF);
const kMuted = Color(0xFF8C98BC);
const kUp = Color(0xFF22C55E);
const kDown = Color(0xFFF0445A);
const kWait = Color(0xFFF5A524);
const kAccent = Color(0xFF5B7CFF);
const kAccent2 = Color(0xFFA35CFF);
const kStar = Color(0xFFFFC53D);
const kGradient = LinearGradient(
  colors: [kAccent, kAccent2],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const kBgGradient = LinearGradient(
  colors: [kBg2, kBg, kBg],
  stops: [0, 0.45, 1],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);

const appName = 'AI Trade Notify';
const topic = 'signals';

/// style -> [risk % per trade, max % of money in one trade]
const styles = <String, List<double>>{
  'safe': [0.5, 15],
  'normal': [1, 25],
  'bold': [2, 40],
};
const styleNames = {'safe': 'Safe', 'normal': 'Normal', 'bold': 'Bold'};
const styleInfo = {
  'safe': 'Risk 0.5% per trade',
  'normal': 'Risk 1% per trade',
  'bold': 'Risk 2% per trade',
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kSurface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final configured = !fbApiKey.startsWith('PASTE');
  if (configured) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: fbApiKey,
        appId: fbAndroidAppId,
        messagingSenderId: fbSenderId,
        projectId: fbProjectId,
        storageBucket: fbStorageBucket,
      ),
    );
  }
  runApp(AiTradeApp(configured: configured));
}

class AiTradeApp extends StatelessWidget {
  const AiTradeApp({super.key, required this.configured});
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kAccent,
      brightness: Brightness.dark,
      surface: kSurface,
    );
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBg,
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kSurface,
          indicatorColor: kAccent.withValues(alpha: 0.22),
          elevation: 0,
          height: 68,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kSurface2,
          contentTextStyle: TextStyle(color: kText, fontSize: 14),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface2,
          labelStyle: const TextStyle(color: kMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kAccent, width: 1.6),
          ),
        ),
      ),
      home: configured ? const SplashScreen() : const NotSetUpPage(),
    );
  }
}

class NotSetUpPage extends StatelessWidget {
  const NotSetUpPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              '$appName is not connected to Firebase yet.\n\n'
              'Add google-services.json to the app folder on GitHub and build the app again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted),
            ),
          ),
        ),
      );
}

// ================================================================ data
double _d(dynamic v) => v is num ? v.toDouble() : 0;
int _i(dynamic v) => v is num ? v.toInt() : 0;

class Signal {
  Signal.fromMap(Map<String, dynamic> m)
      : name = (m['name'] ?? '') as String,
        dir = (m['dir'] ?? 'WAIT') as String,
        price = _d(m['price']),
        stop = _d(m['stop']),
        tp1 = _d(m['tp1']),
        tp2 = _d(m['tp2']),
        conf = _i(m['conf']),
        stars = _i(m['stars']),
        checks = ((m['checks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

  final String name, dir;
  final double price, stop, tp1, tp2;
  final int conf, stars;
  final List<Map<String, dynamic>> checks;

  bool get isUp => dir == 'UP';
  bool get isWait => dir == 'WAIT';
  Color get color => isWait ? kWait : (isUp ? kUp : kDown);
  String get verb => isWait ? 'Wait' : (isUp ? 'Buy' : 'Sell');
  IconData get icon => isWait
      ? Icons.remove_rounded
      : (isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded);

  static int compare(Signal a, Signal b) {
    final w = (b.isWait ? 0 : 1) - (a.isWait ? 0 : 1);
    return w != 0 ? w : b.conf - a.conf;
  }
}

class Plan {
  Plan(this.spend, this.max, this.loss, this.win1, this.win2, this.ratio, this.tooSmall);
  final double spend, max, loss, win1, win2, ratio;
  final bool tooSmall;
}

class SettingsModel extends ChangeNotifier {
  SharedPreferences? _p;
  double balance = 1000, fee = 0.1, minOrder = 10;
  String style = 'normal';
  bool alertsOn = false, askedAlerts = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _p = p;
    balance = p.getDouble('bal') ?? 1000;
    fee = p.getDouble('fee') ?? 0.1;
    minOrder = p.getDouble('min') ?? 10;
    style = p.getString('style') ?? 'normal';
    alertsOn = p.getBool('alerts') ?? false;
    askedAlerts = p.getBool('asked') ?? false;
    notifyListeners();
  }

  void setBalance(double v) {
    balance = v;
    _p?.setDouble('bal', v);
    notifyListeners();
  }

  void setFee(double v) {
    fee = v;
    _p?.setDouble('fee', v);
    notifyListeners();
  }

  void setMin(double v) {
    minOrder = v;
    _p?.setDouble('min', v);
    notifyListeners();
  }

  void setStyle(String v) {
    style = v;
    _p?.setString('style', v);
    notifyListeners();
  }

  void setAlerts(bool v) {
    alertsOn = v;
    askedAlerts = true;
    _p?.setBool('alerts', v);
    _p?.setBool('asked', true);
    notifyListeners();
  }

  Plan plan(double entry, double stop, double t1, double t2) {
    final s = styles[style]!;
    final perUnit = (entry - stop).abs();
    var qty = perUnit > 0 ? balance * s[0] / 100 / perUnit : 0.0;
    var spend = qty * entry;
    final max = balance * s[1] / 100;
    if (spend > max) {
      spend = max;
      qty = entry > 0 ? max / entry : 0;
    }
    final fees = spend * fee / 100 * 2;
    return Plan(
      spend,
      max,
      qty * perUnit + fees,
      qty * (t1 - entry).abs() - fees,
      qty * (t2 - entry).abs() - fees,
      perUnit > 0 ? (t1 - entry).abs() / perUnit : 0,
      spend < minOrder,
    );
  }
}

String _commas(String s) {
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

String fp(double p) => p >= 100
    ? _commas(p.toStringAsFixed(2))
    : p >= 1
        ? p.toStringAsFixed(4)
        : p.toStringAsPrecision(4);

String money(double x) => '\$${_commas(x.toStringAsFixed(2))}';

String two(int n) => n.toString().padLeft(2, '0');

String timeAgo(int ms) {
  if (ms <= 0) return '';
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  final m = diff ~/ 60000;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h < 24) return '$h h ago';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[t.weekday - 1]} ${two(t.hour)}:${two(t.minute)}';
}

// ================================================================ splash
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (context, a, b) => const HomeShell(),
        transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = _c.value;
              final pop = Curves.easeOutBack.transform(v.clamp(0.0, 1.0).toDouble());
              final fade = Curves.easeOut.transform((v * 1.6).clamp(0.0, 1.0).toDouble());
              final text = Curves.easeOut.transform(((v - 0.35) / 0.65).clamp(0.0, 1.0).toDouble());
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: fade,
                    child: Transform.scale(
                      scale: 0.55 + 0.45 * pop,
                      child: Transform.rotate(angle: (1 - pop) * -0.5, child: const AppLogo(size: 104)),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Opacity(
                    opacity: text,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - text)),
                      child: const Column(children: [
                        Text(appName,
                            style: TextStyle(color: kText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                        SizedBox(height: 6),
                        Text('Smart crypto signals, live', style: TextStyle(color: kMuted, fontSize: 15)),
                      ]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: kGradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [
            BoxShadow(color: kAccent.withValues(alpha: 0.45), blurRadius: size * 0.4, offset: Offset(0, size * 0.12)),
          ],
        ),
        child: Icon(Icons.show_chart_rounded, color: Colors.white, size: size * 0.6),
      );
}

// ================================================================ app shell
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _db = FirebaseFirestore.instance;
  final settings = SettingsModel();
  final _subs = <StreamSubscription<dynamic>>[];
  List<Signal>? signals;
  Map<String, dynamic>? status;
  Map<String, dynamic>? picksDoc;
  List<Map<String, dynamic>> alerts = [];
  String? error;
  String? picked;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    settings.addListener(_changed);
    settings.load().then((_) {
      if (!settings.askedAlerts) _setAlerts(true, quiet: true);
    });
    _subs.add(_db.collection('signals').snapshots().listen((q) {
      final list = q.docs.map((d) => Signal.fromMap(d.data())).where((s) => s.price > 0).toList()
        ..sort(Signal.compare);
      setState(() {
        signals = list;
        error = null;
      });
    }, onError: (Object e) => setState(() => error = '$e')));
    _subs.add(_db.collection('status').doc('bot').snapshots().listen((d) {
      setState(() => status = d.data());
    }, onError: (Object e) {}));
    _subs.add(_db.collection('alerts').orderBy('atMs', descending: true).limit(30).snapshots().listen((q) {
      setState(() => alerts = q.docs.map((d) => d.data()).toList());
    }, onError: (Object e) {}));
    _subs.add(_db.collection('picks').doc('latest').snapshots().listen((d) {
      setState(() => picksDoc = d.data());
    }, onError: (Object e) {}));
    _subs.add(FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null || !mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(children: [
          const AppLogo(size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(n.title ?? 'New signal', style: const TextStyle(fontWeight: FontWeight.w700, color: kText)),
              if ((n.body ?? '').isNotEmpty) Text(n.body!, style: const TextStyle(color: kMuted, fontSize: 13)),
            ]),
          ),
        ]),
      ));
    }));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    settings.removeListener(_changed);
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _setAlerts(bool on, {bool quiet = false}) async {
    final fm = FirebaseMessaging.instance;
    try {
      if (on) {
        final s = await fm.requestPermission();
        if (s.authorizationStatus == AuthorizationStatus.denied) {
          settings.setAlerts(false);
          if (!quiet) _snack('Notifications are blocked. Allow them in phone Settings → Apps → $appName.');
          return;
        }
        await fm.subscribeToTopic(topic);
      } else {
        await fm.unsubscribeFromTopic(topic);
      }
      settings.setAlerts(on);
      HapticFeedback.lightImpact();
      if (!quiet) _snack(on ? '🔔 Alerts are on' : 'Alerts are off');
    } catch (e) {
      if (!quiet) _snack('Could not change alerts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final recent = alerts.where((a) => now - _i(a['atMs']) < 86400000).length;
    final pages = <Widget>[
      SignalsPage(
        signals: signals,
        status: status,
        error: error,
        settings: settings,
        picked: picked,
        onPick: (n) => setState(() => picked = n),
        alertsOn: settings.alertsOn,
        onToggleAlerts: () => _setAlerts(!settings.alertsOn),
        onEditPlan: () => setState(() => tab = 4),
      ),
      PicksPage(doc: picksDoc),
      AlertsPage(alerts: alerts, alertsOn: settings.alertsOn, onToggleAlerts: (v) => _setAlerts(v)),
      CheckTradePage(signals: signals ?? const [], settings: settings),
      SettingsPage(settings: settings, onToggleAlerts: (v) => _setAlerts(v)),
    ];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey<int>(tab), child: pages[tab]),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => tab = i);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.show_chart_rounded),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Signals',
          ),
          const NavigationDestination(
            icon: Icon(Icons.trending_up),
            selectedIcon: Icon(Icons.trending_up_rounded),
            label: 'Picks',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: recent > 0,
              label: Text('$recent'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            selectedIcon: const Icon(Icons.notifications_rounded),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate_rounded),
            label: 'My trade',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ================================================================ reusable pieces
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.dy = 18});
  final Widget child;
  final int index;
  final double dy;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(Duration(milliseconds: 70 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (context, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, widget.dy * (1 - _a.value)), child: child),
        ),
        child: widget.child,
      );
}

class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color});
  final Color color;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            return Stack(alignment: Alignment.center, children: [
              Container(
                width: 8 + 10 * v,
                height: 8 + 10 * v,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.5 * (1 - v))),
              ),
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
            ]);
          },
        ),
      );
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [(color ?? kSurface2).withValues(alpha: 0.85), kSurface.withValues(alpha: 0.9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kBorder),
        ),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          Text(text, style: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: const TextStyle(color: kMuted, fontSize: 13)),
        ]),
      );
}

class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: kGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: FadeSlideIn(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, color: kSurface2, border: Border.all(color: kBorder)),
                child: Icon(icon, color: kAccent, size: 38),
              ),
              const SizedBox(height: 18),
              Text(title, style: const TextStyle(color: kText, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, height: 1.4)),
            ]),
          ),
        ),
      );
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.p);
  final double p;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * p - 1), 0, 0);
}

class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            colors: const [kSurface2, Color(0xFF2A3560), kSurface2],
            stops: const [0.3, 0.5, 0.7],
            transform: _SlideGradient(_c.value),
          ).createShader(rect),
          child: child,
        ),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  Widget _box(double h, {double? w}) => Container(
        height: h,
        width: w,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(20)),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Shimmer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _box(44, w: 220),
            _box(64),
            _box(330),
            _box(110),
          ]),
        ),
      );
}

class ConfidenceRing extends StatelessWidget {
  const ConfidenceRing({super.key, required this.value, required this.color, this.size = 88});
  final double value, size;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(v, color),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(v * 100).round()}%',
                    style: const TextStyle(color: kText, fontSize: 21, fontWeight: FontWeight.w800)),
                const Text('sure', style: TextStyle(color: kMuted, fontSize: 11)),
              ]),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color);
  final double v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = kBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    if (v <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * v,
      false,
      Paint()
        ..shader = SweepGradient(
          colors: [color.withValues(alpha: 0.35), color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color;
}

class CoinAvatar extends StatelessWidget {
  const CoinAvatar(this.name, {super.key, this.size = 34});
  final String name;
  final double size;

  static const _colors = [
    [Color(0xFFF7931A), Color(0xFFFFB547)],
    [Color(0xFF627EEA), Color(0xFF8FA4FF)],
    [Color(0xFF14F195), Color(0xFF9945FF)],
    [Color(0xFF23292F), Color(0xFF5A6772)],
    [Color(0xFFF3BA2F), Color(0xFFFFD86B)],
    [Color(0xFF0033AD), Color(0xFF3A6BFF)],
    [Color(0xFFC2A633), Color(0xFFE8D27A)],
    [Color(0xFFE84142), Color(0xFFFF7A7B)],
    [Color(0xFF2A5ADA), Color(0xFF5C86FF)],
    [Color(0xFFE6007A), Color(0xFFFF5CAD)],
  ];

  @override
  Widget build(BuildContext context) {
    final i = name.codeUnits.fold<int>(0, (a, b) => a + b) % _colors.length;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: _colors[i])),
      alignment: Alignment.center,
      child: Text(
        name.length > 3 ? name.substring(0, 3) : name,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.3),
      ),
    );
  }
}

class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.status});
  final Map<String, dynamic>? status;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var target = _i(widget.status?['nextRunMs']);
    if (target < now) target = (now ~/ 3600000 + 1) * 3600000 + 5 * 60000;
    final secs = ((target - now) / 1000).floor();
    final frac = (1 - secs / 3600).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kBg.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.schedule_rounded, color: kMuted, size: 18),
          const SizedBox(width: 8),
          const Text('Next signal update', style: TextStyle(color: kMuted)),
          const Spacer(),
          Text('${two(secs ~/ 60)}:${two(secs % 60)}',
              style: const TextStyle(
                  color: kText, fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: frac, end: frac),
            duration: const Duration(milliseconds: 900),
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: kBorder,
              valueColor: const AlwaysStoppedAnimation<Color>(kAccent),
            ),
          ),
        ),
      ]),
    );
  }
}

// ================================================================ signals page
class SignalsPage extends StatelessWidget {
  const SignalsPage({
    super.key,
    required this.signals,
    required this.status,
    required this.error,
    required this.settings,
    required this.picked,
    required this.onPick,
    required this.alertsOn,
    required this.onToggleAlerts,
    required this.onEditPlan,
  });

  final List<Signal>? signals;
  final Map<String, dynamic>? status;
  final String? error;
  final SettingsModel settings;
  final String? picked;
  final ValueChanged<String> onPick;
  final bool alertsOn;
  final VoidCallback onToggleAlerts;
  final VoidCallback onEditPlan;

  @override
  Widget build(BuildContext context) {
    final header = _Header(status: status, alertsOn: alertsOn, onToggleAlerts: onToggleAlerts);
    if (error != null) {
      return Column(children: [
        header,
        const Expanded(
          child: EmptyView(
            icon: Icons.cloud_off_rounded,
            title: "Can't load signals",
            text: 'Check your internet connection and try again.',
          ),
        ),
      ]);
    }
    final list = signals;
    if (list == null) return Column(children: [header, const Expanded(child: LoadingView())]);
    if (list.isEmpty) {
      return Column(children: [
        header,
        const Expanded(
          child: EmptyView(
            icon: Icons.hourglass_top_rounded,
            title: 'First signals are on the way',
            text: 'The bot checks the market every hour. Signals appear here automatically.',
          ),
        ),
      ]);
    }
    final current = list.firstWhere((s) => s.name == picked, orElse: () => list.first);
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FadeSlideIn(index: 1, child: _PlanBar(settings: settings, onEdit: onEditPlan)),
            const SizedBox(height: 14),
            FadeSlideIn(
              index: 2,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(a), child: child),
                ),
                child: SignalHero(
                  key: ValueKey('${current.name}-${current.dir}-${current.price}'),
                  s: current,
                  settings: settings,
                  status: status,
                ),
              ),
            ),
            const SizedBox(height: 22),
            FadeSlideIn(index: 3, child: SectionTitle('All coins', trailing: '${list.length} tracked')),
            const SizedBox(height: 12),
          ]),
        ),
        FadeSlideIn(
          index: 4,
          child: SizedBox(
            height: 124,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (context, i) => const SizedBox(width: 10),
              itemBuilder: (context, i) => CoinTile(
                s: list[i],
                selected: list[i].name == current.name,
                onTap: () => onPick(list[i].name),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const FadeSlideIn(
          index: 5,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Signals come from past price patterns and can be wrong. Practise with no real money first. Not financial advice.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontSize: 12, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status, required this.alertsOn, required this.onToggleAlerts});
  final Map<String, dynamic>? status;
  final bool alertsOn;
  final VoidCallback onToggleAlerts;

  @override
  Widget build(BuildContext context) {
    final last = _i(status?['lastRunMs']);
    final fresh = last > 0 && DateTime.now().millisecondsSinceEpoch - last < 3 * 3600000;
    final t = DateTime.fromMillisecondsSinceEpoch(last);
    final text = last == 0
        ? 'Waiting for the bot'
        : fresh
            ? 'Live · updated ${two(t.hour)}:${two(t.minute)}'
            : 'Paused · last update ${timeAgo(last)}';
    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        child: Row(children: [
          const AppLogo(size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(appName, style: TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Row(children: [
                PulseDot(color: fresh ? kUp : kWait),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(text,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 13)),
                ),
              ]),
            ]),
          ),
          IconButton(
            onPressed: onToggleAlerts,
            tooltip: alertsOn ? 'Alerts on' : 'Alerts off',
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => RotationTransition(
                turns: Tween<double>(begin: -0.1, end: 0).animate(a),
                child: ScaleTransition(scale: a, child: c),
              ),
              child: Icon(
                alertsOn ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                key: ValueKey<bool>(alertsOn),
                color: alertsOn ? kAccent : kMuted,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PlanBar extends StatelessWidget {
  const _PlanBar({required this.settings, required this.onEdit});
  final SettingsModel settings;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: kSurface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_rounded, color: kAccent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'My money  ', style: TextStyle(color: kMuted)),
                TextSpan(
                    text: money(settings.balance),
                    style: const TextStyle(color: kText, fontWeight: FontWeight.w800, fontSize: 16)),
              ])),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(gradient: kGradient, borderRadius: BorderRadius.circular(20)),
              child: Text(styleNames[settings.style]!,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: kMuted),
          ]),
        ),
      );
}

class SignalHero extends StatelessWidget {
  const SignalHero({super.key, required this.s, required this.settings, required this.status});
  final Signal s;
  final SettingsModel settings;
  final Map<String, dynamic>? status;

  @override
  Widget build(BuildContext context) {
    final color = s.color;
    final strong = s.stars >= 4 && !s.isWait;
    final p = settings.plan(s.price, s.stop, s.tp1, s.tp2);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.22), kSurface.withValues(alpha: 0.95), kSurface],
          stops: const [0, 0.55, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 32, offset: const Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(s.icon, color: color, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    s.isWait ? 'NO CLEAR TRADE' : '${strong ? 'STRONG ' : ''}${s.verb.toUpperCase()} SIGNAL',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                CoinAvatar(s.name, size: 38),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    s.isWait ? 'Wait on ${s.name}' : '${s.verb} ${s.name}',
                    style: const TextStyle(color: kText, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text('★' * s.stars + '☆' * (5 - s.stars),
                  style: const TextStyle(color: kStar, fontSize: 18, letterSpacing: 2)),
            ]),
          ),
          ConfidenceRing(value: s.conf / 100, color: color),
        ]),
        const SizedBox(height: 18),
        if (s.isWait)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              "The signals disagree, so there's no good trade here right now. Not trading is also a smart move. Tap another coin below.",
              style: TextStyle(color: kMuted, height: 1.45),
            ),
          )
        else ...[
          FadeSlideIn(
            index: 3,
            child: _StepRow(
              icon: Icons.bolt_rounded,
              color: kAccent,
              title: '${s.verb} at about ${fp(s.price)}',
              sub: 'Put in ${money(p.spend)}  ·  max ${money(p.max)}',
            ),
          ),
          FadeSlideIn(
            index: 4,
            child: _StepRow(
              icon: Icons.flag_rounded,
              color: kUp,
              title: 'Take profit at ${fp(s.tp1)}',
              sub: 'You make about +${money(p.win1)}  ·  bonus target ${fp(s.tp2)} (+${money(p.win2)})',
            ),
          ),
          FadeSlideIn(
            index: 5,
            child: _StepRow(
              icon: Icons.shield_rounded,
              color: kDown,
              title: 'Exit if it reaches ${fp(s.stop)}',
              sub: 'Most you can lose: −${money(p.loss)}',
            ),
          ),
          if (!s.isUp)
            const _Note("Selling a coin you don't own needs a futures account. With a normal account, just don't buy it now."),
          if (p.tooSmall) const _Note("This amount is below your exchange's minimum. Skip it or add money.", color: kDown),
        ],
        const SizedBox(height: 14),
        Countdown(status: status),
        _WhyTile(checks: s.checks),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.icon, required this.color, required this.title, required this.sub});
  final IconData icon;
  final Color color;
  final String title, sub;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kBg.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder.withValues(alpha: 0.7)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(color: kMuted, fontSize: 13, height: 1.3)),
            ]),
          ),
        ]),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.color = kMuted});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.35))),
        ]),
      );
}

class _WhyTile extends StatelessWidget {
  const _WhyTile({required this.checks});
  final List<Map<String, dynamic>> checks;

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          childrenPadding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
          iconColor: kAccent,
          collapsedIconColor: kMuted,
          title: const Text('Why this signal?', style: TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 15)),
          children: [
            for (final c in checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(
                    _d(c['score']) > 0
                        ? Icons.arrow_upward_rounded
                        : _d(c['score']) < 0
                            ? Icons.arrow_downward_rounded
                            : Icons.remove_rounded,
                    size: 18,
                    color: _d(c['score']) > 0
                        ? kUp
                        : _d(c['score']) < 0
                            ? kDown
                            : kMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${c['note'] ?? ''}', style: const TextStyle(color: kText, fontSize: 14))),
                ]),
              ),
          ],
        ),
      );
}

class CoinTile extends StatelessWidget {
  const CoinTile({super.key, required this.s, required this.selected, required this.onTap});
  final Signal s;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedScale(
          scale: selected ? 1 : 0.95,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: 116,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? kSurface2 : kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? s.color : kBorder, width: selected ? 1.6 : 1),
              boxShadow: selected
                  ? [BoxShadow(color: s.color.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 6))]
                  : const [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  CoinAvatar(s.name, size: 30),
                  const Spacer(),
                  Icon(s.icon, color: s.color, size: 22),
                ]),
                Text(s.name, style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                  s.isWait ? 'Wait' : '${s.verb} · ${s.conf}%',
                  style: TextStyle(color: s.color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
}

// ================================================================ alerts page
class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key, required this.alerts, required this.alertsOn, required this.onToggleAlerts});
  final List<Map<String, dynamic>> alerts;
  final bool alertsOn;
  final ValueChanged<bool> onToggleAlerts;

  @override
  Widget build(BuildContext context) {
    final toggle = FadeSlideIn(
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: alertsOn,
          onChanged: onToggleAlerts,
          secondary: Icon(alertsOn ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
              color: alertsOn ? kAccent : kMuted),
          title: const Text('Push alerts', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
          subtitle: const Text('Strong signals (4★+), max 3 per hour', style: TextStyle(color: kMuted, fontSize: 13)),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 14),
          child: Text('Alerts', style: TextStyle(color: kText, fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        toggle,
        const SizedBox(height: 18),
        if (alerts.isEmpty)
          const SizedBox(
            height: 320,
            child: EmptyView(
              icon: Icons.notifications_none_rounded,
              title: 'No alerts yet',
              text: 'When a coin becomes a strong signal, it shows up here and on your phone.',
            ),
          )
        else
          for (var i = 0; i < alerts.length; i++)
            FadeSlideIn(index: math.min(i + 1, 10), child: _AlertTile(a: alerts[i])),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final up = a['dir'] == 'UP';
    final color = up ? kUp : kDown;
    final stars = _i(a['stars']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
          child: Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${up ? 'BUY' : 'SELL'} ${a['name'] ?? ''}',
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text('at ${fp(_d(a['price']))}  ·  ${'★' * stars}', style: const TextStyle(color: kMuted, fontSize: 13)),
          ]),
        ),
        Text(timeAgo(_i(a['atMs'])), style: const TextStyle(color: kMuted, fontSize: 12)),
      ]),
    );
  }
}

// ================================================================ my trade page
class CheckTradePage extends StatefulWidget {
  const CheckTradePage({super.key, required this.signals, required this.settings});
  final List<Signal> signals;
  final SettingsModel settings;

  @override
  State<CheckTradePage> createState() => _CheckTradePageState();
}

class _CheckTradePageState extends State<CheckTradePage> {
  final _sym = TextEditingController();
  final _in = TextEditingController();
  final _tp = TextEditingController();
  final _sl = TextEditingController();
  int _side = 1;
  Widget? _result;
  int _resultKey = 0;

  @override
  void dispose() {
    for (final c in [_sym, _in, _tp, _sl]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _num(TextEditingController c, String label, IconData icon) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: kText, fontWeight: FontWeight.w600),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: kMuted, size: 20)),
      );

  void _check() {
    FocusScope.of(context).unfocus();
    final e = double.tryParse(_in.text) ?? 0;
    final t = double.tryParse(_tp.text) ?? 0;
    final s = double.tryParse(_sl.text) ?? 0;
    Widget r;
    if (e <= 0 || t <= 0 || s <= 0) {
      r = const _Note('Please fill in all three prices.', color: kWait);
    } else if ((s - e) * _side >= 0 || (t - e) * _side <= 0) {
      r = _Note(
        _side > 0
            ? 'For "up": the exit price must be below your entry, and the profit price above it.'
            : 'For "down": the exit price must be above your entry, and the profit price below it.',
        color: kWait,
      );
    } else {
      final p = widget.settings.plan(e, s, t, t);
      final grade = p.ratio >= 2
          ? ('Good trade', kUp)
          : p.ratio >= 1.5
              ? ('OK trade', kWait)
              : ('Weak trade', kDown);
      final sym = _sym.text.toUpperCase().replaceAll(RegExp(r'USDT?$'), '').trim();
      final match = widget.signals.where((x) => x.name == sym).toList();
      String? agree;
      Color agreeColor = kMuted;
      if (match.isNotEmpty) {
        final x = match.first;
        if (x.isWait) {
          agree = 'The signals see no clear direction.';
          agreeColor = kWait;
        } else if (x.isUp == (_side > 0)) {
          agree = 'The signals agree with you.';
          agreeColor = kUp;
        } else {
          agree = 'The signals point the other way. Be careful.';
          agreeColor = kDown;
        }
      }
      r = GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: grade.$2.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
              child: Text(grade.$1, style: TextStyle(color: grade.$2, fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            Text('Reward : risk  ${p.ratio.toStringAsFixed(2)} : 1',
                style: const TextStyle(color: kMuted, fontSize: 13)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: (p.ratio / 3).clamp(0.0, 1.0).toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: kBorder,
                valueColor: AlwaysStoppedAnimation<Color>(grade.$2),
              ),
            ),
          ),
          if (agree != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(agreeColor == kUp ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: agreeColor, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(agree, style: TextStyle(color: agreeColor, fontWeight: FontWeight.w600))),
            ]),
          ],
          const SizedBox(height: 14),
          Row(children: [
            _Stat('Put in', money(p.spend), kText),
            const SizedBox(width: 8),
            _Stat('If right', '+${money(p.win1)}', kUp),
            const SizedBox(width: 8),
            _Stat('If wrong', '−${money(p.loss)}', kDown),
          ]),
          if (p.tooSmall) const _Note("Below your exchange's minimum order.", color: kDown),
        ]),
      );
    }
    setState(() {
      _result = r;
      _resultKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 4),
          child: Text('Check my trade', style: TextStyle(color: kText, fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text('Have your own idea? See how much to put in and what you could win or lose.',
              style: TextStyle(color: kMuted, height: 1.4)),
        ),
        FadeSlideIn(
          child: GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _sym,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: kText, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  labelText: 'Coin (e.g. BTC)',
                  prefixIcon: Icon(Icons.currency_bitcoin_rounded, color: kMuted, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Going up'), icon: Icon(Icons.trending_up_rounded)),
                  ButtonSegment(value: -1, label: Text('Going down'), icon: Icon(Icons.trending_down_rounded)),
                ],
                selected: {_side},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _side = s.first),
              ),
              const SizedBox(height: 12),
              _num(_in, "I'll get in at", Icons.login_rounded),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _num(_tp, 'Take profit at', Icons.flag_rounded)),
                const SizedBox(width: 10),
                Expanded(child: _num(_sl, 'Exit if wrong at', Icons.shield_rounded)),
              ]),
              const SizedBox(height: 16),
              GradientButton(label: 'Check it', icon: Icons.auto_awesome_rounded, onTap: _check),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(a),
              child: c,
            ),
          ),
          child: KeyedSubtree(key: ValueKey<int>(_resultKey), child: _result ?? const SizedBox.shrink()),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kBg.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );
}

// ================================================================ settings page
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.onToggleAlerts});
  final SettingsModel settings;
  final ValueChanged<bool> onToggleAlerts;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _bal = TextEditingController(text: widget.settings.balance.toStringAsFixed(0));
  late final _fee = TextEditingController(text: widget.settings.fee.toString());
  late final _min = TextEditingController(text: widget.settings.minOrder.toStringAsFixed(0));

  @override
  void dispose() {
    _bal.dispose();
    _fee.dispose();
    _min.dispose();
    super.dispose();
  }

  Widget _styleOption(String key) {
    final on = widget.settings.style == key;
    final icon = key == 'safe'
        ? Icons.shield_moon_rounded
        : key == 'normal'
            ? Icons.balance_rounded
            : Icons.local_fire_department_rounded;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.settings.setStyle(key);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            gradient: on ? kGradient : null,
            color: on ? null : kSurface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? Colors.transparent : kBorder),
            boxShadow: on ? [BoxShadow(color: kAccent.withValues(alpha: 0.35), blurRadius: 16)] : const [],
          ),
          child: Column(children: [
            Icon(icon, color: on ? Colors.white : kMuted),
            const SizedBox(height: 6),
            Text(styleNames[key]!,
                style: TextStyle(color: on ? Colors.white : kText, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(styleInfo[key]!.replaceAll(' per trade', ''),
                style: TextStyle(color: on ? Colors.white70 : kMuted, fontSize: 11)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text('Settings', style: TextStyle(color: kText, fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        FadeSlideIn(
          index: 0,
          child: GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('My trading money', style: TextStyle(color: kMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _bal,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(prefixText: '\$ '),
                onChanged: (v) {
                  final x = double.tryParse(v);
                  if (x != null) st.setBalance(x);
                },
              ),
              const SizedBox(height: 16),
              const Text('Trading style', style: TextStyle(color: kMuted)),
              const SizedBox(height: 8),
              Row(children: [
                _styleOption('safe'),
                const SizedBox(width: 8),
                _styleOption('normal'),
                const SizedBox(width: 8),
                _styleOption('bold'),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideIn(
          index: 1,
          child: GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Exchange minimum (\$)'),
                    onChanged: (v) {
                      final x = double.tryParse(v);
                      if (x != null) st.setMin(x);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _fee,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Fee per trade (%)'),
                    onChanged: (v) {
                      final x = double.tryParse(v);
                      if (x != null) st.setFee(x);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: st.alertsOn,
                onChanged: widget.onToggleAlerts,
                title: const Text('Push alerts', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
                subtitle: const Text('Strong signals only', style: TextStyle(color: kMuted, fontSize: 13)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        const FadeSlideIn(
          index: 2,
          child: GlassCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppLogo(size: 40),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(appName, style: TextStyle(color: kText, fontWeight: FontWeight.w800, fontSize: 16)),
                  SizedBox(height: 4),
                  Text(
                    'Checks 10 crypto coins every hour with 6 market indicators. It never trades for you. '
                    'Signals come from past price patterns and can be wrong. Not financial advice.',
                    style: TextStyle(color: kMuted, fontSize: 13, height: 1.4),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ================================================================ 5-day picks page
class PicksPage extends StatelessWidget {
  const PicksPage({super.key, required this.doc});
  final Map<String, dynamic>? doc;

  @override
  Widget build(BuildContext context) {
    final d = doc;
    final model = (d?['model'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final picks = ((d?['picks'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final hasEdge = model['has_edge'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 4),
          child: Text('5-day picks', style: TextStyle(color: kText, fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text('Stocks (S&P 500) + crypto · machine learning · updated daily 09:00 Doha',
              style: TextStyle(color: kMuted, height: 1.4)),
        ),
        if (d == null)
          const SizedBox(
            height: 320,
            child: EmptyView(
              icon: Icons.trending_up_rounded,
              title: 'First daily scan is on the way',
              text: 'The model scans the market every day at 09:00 Doha time.',
            ),
          )
        else ...[
          if (!hasEdge) const FadeSlideIn(child: _EdgeWarning()),
          if (picks.isEmpty)
            const FadeSlideIn(
              index: 1,
              child: GlassCard(
                child: Text('No trade today. Nothing passed the accuracy filters. Waiting is a position too.',
                    style: TextStyle(color: kText, height: 1.4)),
              ),
            ),
          for (var i = 0; i < picks.length; i++) FadeSlideIn(index: i + 1, child: _PickCard(p: picks[i])),
          const SizedBox(height: 6),
          FadeSlideIn(index: picks.length + 1, child: _ModelCard(m: model, generated: '${d['generatedAt'] ?? ''}')),
        ],
      ],
    );
  }
}

class _EdgeWarning extends StatelessWidget {
  const _EdgeWarning();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kWait.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kWait.withValues(alpha: 0.6)),
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, color: kWait),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "No edge today: the model did not beat simple guessing on its exam. Don't trade on these picks.",
              style: TextStyle(color: kWait, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ]),
      );
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final buy = p['signal'] == 'BUY';
    final color = buy ? kUp : kDown;
    final plan = (p['plan'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final hours = (p['hours'] as Map?)?.cast<String, dynamic>();
    final ticker = '${p['ticker'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.18), kSurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CoinAvatar(ticker.replaceAll('-USD', ''), size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${buy ? 'BUY' : 'SELL'} $ticker',
                  style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
              Text('Past accuracy ${(_d(p['accuracy']) * 100).round()}% of ${_i(p['samples'])} signals',
                  style: const TextStyle(color: kMuted, fontSize: 13)),
            ]),
          ),
          ConfidenceRing(value: _d(p['probability']), color: color, size: 74),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _Stat('Entry', fp(_d(plan['entry'])), kText),
          const SizedBox(width: 8),
          _Stat('Stop', fp(_d(plan['stop'])), kDown),
          const SizedBox(width: 8),
          _Stat('Target', fp(_d(plan['target'])), kUp),
        ]),
        if (hours != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.schedule_rounded, size: 16, color: kMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Best buy ${hours['buy_hour']} · best sell ${hours['sell_hour']} (Doha time)',
                  style: const TextStyle(color: kMuted, fontSize: 13)),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.m, required this.generated});
  final Map<String, dynamic> m;
  final String generated;

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Text(
          'Model: ${m['name'] ?? '-'} · ${(_d(m['confident_accuracy']) * 100).round()}% right on its exam '
          'vs ${(_d(m['baseline']) * 100).round()}% by guessing · $generated\n\n'
          'Signals are probabilities, not guarantees. Use the stop-loss, risk max 1-2% per trade, '
          'paper-trade first. Not financial advice.',
          style: const TextStyle(color: kMuted, fontSize: 13, height: 1.4),
        ),
      );
}
