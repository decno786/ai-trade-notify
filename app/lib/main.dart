import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'firebase_config.dart';

// ================================================================ design tokens
const kBg = Color(0xFF0B0E14);
const kPanel = Color(0xFF11151D);
const kPanel2 = Color(0xFF161B25);
const kLine = Color(0xFF1F2633);
const kLine2 = Color(0xFF2A3343);
const kText = Color(0xFFE8ECF3);
const kMuted = Color(0xFF8A94A6);
const kDim = Color(0xFF5B6577);
const kUp = Color(0xFF16C784);
const kDown = Color(0xFFEA3943);
const kWarn = Color(0xFFF0B90B);
const kAccent = Color(0xFF3B82F6);
const kEma21 = Color(0xFFF0B90B);
const kEma50 = Color(0xFFA78BFA);

const appName = 'AI Trade Notify';
const topic = 'signals';
const binance = 'https://data-api.binance.vision/api/v3/';

const tabular = [FontFeature.tabularFigures()];
TextStyle mono(double size, {Color color = kText, FontWeight w = FontWeight.w600}) =>
    TextStyle(fontSize: size, color: color, fontWeight: w, fontFeatures: tabular, letterSpacing: -0.2);

const coinNames = {
  'BTC': 'Bitcoin', 'ETH': 'Ethereum', 'SOL': 'Solana', 'XRP': 'XRP', 'BNB': 'BNB',
  'ADA': 'Cardano', 'DOGE': 'Dogecoin', 'AVAX': 'Avalanche', 'LINK': 'Chainlink', 'DOT': 'Polkadot',
  'TRX': 'TRON', 'LTC': 'Litecoin', 'BCH': 'Bitcoin Cash', 'NEAR': 'NEAR Protocol', 'SUI': 'Sui', 'TON': 'Toncoin',
  'APT': 'Aptos', 'PEPE': 'Pepe', 'AAPL': 'Apple', 'MSFT': 'Microsoft', 'NVDA': 'NVIDIA', 'TSLA': 'Tesla',
  'AMZN': 'Amazon', 'META': 'Meta Platforms', 'GOOGL': 'Alphabet', 'AMD': 'AMD', 'NFLX': 'Netflix',
  'PLTR': 'Palantir', 'COIN': 'Coinbase', 'SPY': 'S&P 500 ETF', 'QQQ': 'Nasdaq 100 ETF', 'GLD': 'Gold ETF',
};
const stockExchange = {'SPY': 'AMEX', 'GLD': 'AMEX'};
const coinColors = {
  'BTC': Color(0xFFF7931A), 'ETH': Color(0xFF627EEA), 'SOL': Color(0xFF9945FF), 'XRP': Color(0xFF23292F),
  'BNB': Color(0xFFF0B90B), 'ADA': Color(0xFF0033AD), 'DOGE': Color(0xFFC2A633), 'AVAX': Color(0xFFE84142),
  'LINK': Color(0xFF2A5ADA), 'DOT': Color(0xFFE6007A), 'TRX': Color(0xFFEF0027), 'LTC': Color(0xFF345D9D),
  'BCH': Color(0xFF0AC18E), 'NEAR': Color(0xFF00A86B), 'SUI': Color(0xFF4DA2FF), 'TON': Color(0xFF0098EA),
  'APT': Color(0xFF2D2D2D), 'PEPE': Color(0xFF3D9B3D), 'AAPL': Color(0xFF555555), 'MSFT': Color(0xFF00A4EF),
  'NVDA': Color(0xFF76B900), 'TSLA': Color(0xFFCC0000), 'AMZN': Color(0xFFFF9900), 'META': Color(0xFF0866FF),
  'GOOGL': Color(0xFF4285F4), 'AMD': Color(0xFFED1C24), 'NFLX': Color(0xFFE50914), 'PLTR': Color(0xFF101113),
  'COIN': Color(0xFF0052FF), 'SPY': Color(0xFF1E3A8A), 'QQQ': Color(0xFF0E7490), 'GLD': Color(0xFFB8860B),
};

/// risk profile -> [risk % per trade, max % of account in one position]
const riskProfiles = <String, List<double>>{'safe': [0.5, 15], 'normal': [1, 25], 'bold': [2, 40]};
const riskNames = {'safe': 'Conservative', 'normal': 'Moderate', 'bold': 'Aggressive'};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kPanel,
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
    OutlineInputBorder border(Color c) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c));
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: kAccent, brightness: Brightness.dark, surface: kPanel),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kPanel,
          indicatorColor: kAccent.withValues(alpha: 0.18),
          elevation: 0,
          height: 64,
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kPanel2,
          contentTextStyle: TextStyle(color: kText, fontSize: 14),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kPanel2,
          labelStyle: const TextStyle(color: kMuted),
          border: border(kLine),
          enabledBorder: border(kLine),
          focusedBorder: border(kAccent),
        ),
        dividerColor: kLine,
      ),
      home: configured ? const HomeShell() : const NotSetUpPage(),
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
            child: Text('$appName is not connected to Firebase yet.',
                textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
          ),
        ),
      );
}

// ================================================================ data
double _d(dynamic v) => v is num ? v.toDouble() : 0;
int _i(dynamic v) => v is num ? v.toInt() : 0;

class Candle {
  Candle(this.t, this.o, this.h, this.l, this.c);
  final int t;
  final double o;
  double h, l, c;
}

class Signal {
  Signal.fromMap(Map<String, dynamic> m)
      : name = (m['name'] ?? '') as String,
        dir = (m['dir'] ?? 'WAIT') as String,
        price = _d(m['price']),
        stop = _d(m['stop']),
        tp1 = _d(m['tp1']),
        tp2 = _d(m['tp2']),
        conf = _i(m['conf']),
        market = (m['market'] ?? 'crypto') as String,
        marketOpen = m['marketOpen'] != false,
        lastPrice = _d(m['lastPrice']),
        validUntil = _i(m['validUntil']),
        issuedAt = _i(m['issuedAt']),
        since = _i(m['since']),
        rsi = m['rsi'] is num ? _d(m['rsi']) : null,
        ema21 = m['ema21'] is num ? _d(m['ema21']) : null,
        ema50 = m['ema50'] is num ? _d(m['ema50']) : null,
        macd = m['macd'] is num ? _d(m['macd']) : null,
        bbPos = m['bbPos'] is num ? _d(m['bbPos']) : null,
        volRatio = m['volRatio'] is num ? _d(m['volRatio']) : null,
        chg24 = m['chg24'] is num ? _d(m['chg24']) : null,
        hi24 = _d(m['hi24']),
        lo24 = _d(m['lo24']),
        vol24 = _d(m['vol24']),
        checks = ((m['checks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        candles = ((m['candles'] as List?) ?? const [])
            .whereType<List>()
            .where((x) => x.length >= 5)
            .map((x) => Candle(_i(x[0]), _d(x[1]), _d(x[2]), _d(x[3]), _d(x[4])))
            .toList();

  final String name, dir;
  final double price, stop, tp1, tp2, hi24, lo24, vol24;
  final double? rsi, ema21, ema50, macd, bbPos, volRatio, chg24;
  final int conf, validUntil, issuedAt, since;
  final String market;
  final bool marketOpen;
  final double lastPrice;
  final List<Map<String, dynamic>> checks;
  final List<Candle> candles;

  bool get isUp => dir == 'UP';
  bool get isWait => dir == 'WAIT';
  bool get isStock => market == 'stock';
  String get pair => isStock ? name : '$name/USDT';
  String get tvSymbol => isStock ? '${stockExchange[name] ?? 'NASDAQ'}:$name' : 'BINANCE:${name}USDT';
  String get action => isWait ? 'WAIT' : (isUp ? 'BUY' : 'SELL');
  Color get color => isWait ? kMuted : (isUp ? kUp : kDown);

  static int compare(Signal a, Signal b) {
    final w = (b.isWait ? 0 : 1) - (a.isWait ? 0 : 1);
    return w != 0 ? w : b.conf - a.conf;
  }
}

class LiveTicker {
  LiveTicker(this.price, this.chg, this.high, this.low, this.quoteVol);
  final double price, chg, high, low, quoteVol;
}

class Plan {
  Plan(this.spend, this.units, this.loss, this.win1, this.win2, this.ratio, this.tooSmall);
  final double spend, units, loss, win1, win2, ratio;
  final bool tooSmall;
}

String strengthLabel(int c) => c >= 75 ? 'Very strong' : c >= 55 ? 'Strong' : c >= 35 ? 'Moderate' : 'Weak';

String _commas(String s) {
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

String fp(double p) {
  if (p.isNaN || p == 0) return '—';
  final a = p.abs();
  return a >= 1000
      ? _commas(p.toStringAsFixed(2))
      : a >= 100
          ? p.toStringAsFixed(2)
          : a >= 1
              ? p.toStringAsFixed(4)
              : p.toStringAsPrecision(4);
}

String money(double x) => '\$${_commas(x.toStringAsFixed(2))}';
String pct(double x) => '${x > 0 ? '+' : ''}${x.toStringAsFixed(2)}%';
String bigNum(double x) => x >= 1e9
    ? '${(x / 1e9).toStringAsFixed(2)}B'
    : x >= 1e6
        ? '${(x / 1e6).toStringAsFixed(2)}M'
        : x >= 1e3
            ? '${(x / 1e3).toStringAsFixed(1)}K'
            : x.toStringAsFixed(0);
String two(int n) => n.toString().padLeft(2, '0');
String hm(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(t.hour)}:${two(t.minute)}';
}
String ago(int ms) {
  final m = math.max(0, (DateTime.now().millisecondsSinceEpoch - ms) ~/ 60000);
  return m < 60 ? '${m}m ago' : '${m ~/ 60}h ${m % 60}m ago';
}

String timeAgo(int ms) {
  if (ms <= 0) return '';
  final m = (DateTime.now().millisecondsSinceEpoch - ms) ~/ 60000;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ago';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[t.weekday - 1]} ${two(t.hour)}:${two(t.minute)}';
}

// ================================================================ app state
class AppState extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;
  final _subs = <StreamSubscription<dynamic>>[];
  SharedPreferences? _p;
  Timer? _poll, _sparkTimer;

  Map<String, Signal> signals = {};
  List<String> order = [];
  Map<String, dynamic>? status, picks;
  List<Map<String, dynamic>> alerts = [];
  Map<String, LiveTicker> live = {};
  Map<String, List<double>> sparks = {};
  bool liveOk = false, loaded = false;
  String? error;

  double balance = 1000, fee = 0.1, minOrder = 10;
  String risk = 'normal', filter = 'all';
  bool alertsOn = false, askedAlerts = false;

  Future<void> start() async {
    final p = await SharedPreferences.getInstance();
    _p = p;
    balance = p.getDouble('bal') ?? 1000;
    fee = p.getDouble('fee') ?? 0.1;
    minOrder = p.getDouble('min') ?? 10;
    risk = p.getString('style') ?? 'normal';
    alertsOn = p.getBool('alerts') ?? false;
    askedAlerts = p.getBool('asked') ?? false;

    _subs.add(_db.collection('signals').snapshots().listen((q) {
      final list = q.docs.map((d) => Signal.fromMap(d.data())).where((s) => s.price > 0).toList()
        ..sort(Signal.compare);
      final firstLoad = signals.isEmpty;
      signals = {for (final s in list) s.name: s};
      order = list.map((s) => s.name).toList();
      loaded = true;
      error = null;
      notifyListeners();
      if (firstLoad && order.isNotEmpty) {
        _pollTickers();
        _loadSparks();
        _poll ??= Timer.periodic(const Duration(seconds: 5), (_) => _pollTickers());
        _sparkTimer ??= Timer.periodic(const Duration(minutes: 10), (_) => _loadSparks());
      }
    }, onError: (Object e) {
      error = '$e';
      loaded = true;
      notifyListeners();
    }));
    _subs.add(_db.collection('status').doc('bot').snapshots().listen((d) {
      status = d.data();
      notifyListeners();
    }, onError: (Object e) {}));
    _subs.add(_db.collection('alerts').orderBy('atMs', descending: true).limit(30).snapshots().listen((q) {
      alerts = q.docs.map((d) => d.data()).toList();
      notifyListeners();
    }, onError: (Object e) {}));
    _subs.add(_db.collection('picks').doc('latest').snapshots().listen((d) {
      picks = d.data();
      notifyListeners();
    }, onError: (Object e) {}));
  }

  Future<void> _pollTickers() async {
    if (order.isEmpty) return;
    final syms = jsonEncode(order.where((n) => !signals[n]!.isStock).map((n) => '${n}USDT').toList());
    try {
      final r = await http
          .get(Uri.parse('${binance}ticker/24hr?symbols=${Uri.encodeComponent(syms)}'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw Exception(r.statusCode);
      for (final t in (jsonDecode(r.body) as List).cast<Map<String, dynamic>>()) {
        final n = (t['symbol'] as String).replaceAll('USDT', '');
        live[n] = LiveTicker(double.parse(t['lastPrice'] as String), double.parse(t['priceChangePercent'] as String),
            double.parse(t['highPrice'] as String), double.parse(t['lowPrice'] as String),
            double.parse(t['quoteVolume'] as String));
      }
      liveOk = true;
    } catch (_) {
      liveOk = false;
    }
    notifyListeners();
  }

  Future<void> _loadSparks() async {
    await Future.wait(order.where((n) => !signals[n]!.isStock).map((n) async {
      try {
        final r = await http
            .get(Uri.parse('${binance}klines?symbol=${n}USDT&interval=1h&limit=48'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          sparks[n] = (jsonDecode(r.body) as List).map((k) => double.parse((k as List)[4] as String)).toList();
        }
      } catch (_) {}
    }));
    notifyListeners();
  }

  double? priceOf(String n) {
    final s = signals[n];
    return live[n]?.price ?? (s == null ? null : (s.lastPrice > 0 ? s.lastPrice : s.price));
  }

  List<String> get visible => order.where((n) => filter == 'all' || (filter == 'stock') == signals[n]!.isStock).toList();
  void setFilter(String f) {
    filter = f;
    notifyListeners();
  }
  double? chgOf(String n) => live[n]?.chg ?? signals[n]?.chg24;
  List<double> sparkOf(String n) => sparks[n] ?? (signals[n]?.candles ?? const []).map((c) => c.c).toList();

  int get lastRunMs => _i(status?['lastRunMs']);
  int get nextRunMs => _i(status?['nextRunMs']);
  bool get stale => lastRunMs > 0 && DateTime.now().millisecondsSinceEpoch - lastRunMs > 3 * 3600000;

  void setBalance(double v) { balance = v; _p?.setDouble('bal', v); notifyListeners(); }
  void setFee(double v) { fee = v; _p?.setDouble('fee', v); notifyListeners(); }
  void setMin(double v) { minOrder = v; _p?.setDouble('min', v); notifyListeners(); }
  void setRisk(String v) { risk = v; _p?.setString('style', v); notifyListeners(); }
  void _setAlertsPref(bool v) {
    alertsOn = v;
    askedAlerts = true;
    _p?.setBool('alerts', v);
    _p?.setBool('asked', true);
    notifyListeners();
  }

  Future<String?> setAlerts(bool on) async {
    final fm = FirebaseMessaging.instance;
    try {
      if (on) {
        final s = await fm.requestPermission();
        if (s.authorizationStatus == AuthorizationStatus.denied) {
          _setAlertsPref(false);
          return 'Notifications are blocked. Allow them in Settings → Apps → $appName.';
        }
        await fm.subscribeToTopic(topic);
      } else {
        await fm.unsubscribeFromTopic(topic);
      }
      _setAlertsPref(on);
      return on ? 'Alerts enabled' : 'Alerts disabled';
    } catch (e) {
      return 'Could not change alerts: $e';
    }
  }

  Plan plan(double entry, double stop, double t1, double t2) {
    final s = riskProfiles[risk]!;
    final perUnit = (entry - stop).abs();
    var qty = perUnit > 0 ? balance * s[0] / 100 / perUnit : 0.0;
    var spend = qty * entry;
    final max = balance * s[1] / 100;
    if (spend > max) {
      spend = max;
      qty = entry > 0 ? max / entry : 0;
    }
    final fees = spend * fee / 100 * 2;
    return Plan(spend, qty, qty * perUnit + fees, qty * (t1 - entry).abs() - fees, qty * (t2 - entry).abs() - fees,
        perUnit > 0 ? (t1 - entry).abs() / perUnit : 0, spend < minOrder);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _poll?.cancel();
    _sparkTimer?.cancel();
    super.dispose();
  }
}

// ================================================================ shell
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final app = AppState();
  StreamSubscription<RemoteMessage>? _msgSub;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    app.start().then((_) {
      if (!app.askedAlerts) app.setAlerts(true);
    });
    _msgSub = FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null || !mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(children: [
          const AppLogo(size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(n.title ?? 'New signal', style: const TextStyle(fontWeight: FontWeight.w700, color: kText)),
              if ((n.body ?? '').isNotEmpty) Text(n.body!, style: mono(12.5, color: kMuted, w: FontWeight.w500)),
            ]),
          ),
        ]),
      ));
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    app.dispose();
    super.dispose();
  }

  void snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void openAsset(String n) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => AssetPage(app: app, symbol: n),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.06, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final recent = app.alerts.where((a) => now - _i(a['atMs']) < 86400000).length;
        Future<void> toggle(bool v) async {
          final m = await app.setAlerts(v);
          if (m != null) snack(m);
        }

        return Scaffold(
          body: IndexedStack(index: tab, children: [
            MarketsPage(app: app, onOpen: openAsset),
            PicksPage(app: app),
            AlertsPage(app: app, onToggle: toggle, onOpen: openAsset),
            ToolsPage(app: app),
          ]),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
            child: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) {
                HapticFeedback.selectionClick();
                setState(() => tab = i);
              },
              destinations: [
                const NavigationDestination(
                    icon: Icon(Icons.candlestick_chart_outlined),
                    selectedIcon: Icon(Icons.candlestick_chart),
                    label: 'Markets'),
                const NavigationDestination(
                    icon: Icon(Icons.auto_graph_outlined), selectedIcon: Icon(Icons.auto_graph), label: 'Picks'),
                NavigationDestination(
                  icon: Badge(
                      isLabelVisible: recent > 0,
                      label: Text('$recent'),
                      child: const Icon(Icons.notifications_none_rounded)),
                  selectedIcon: const Icon(Icons.notifications_rounded),
                  label: 'Alerts',
                ),
                const NavigationDestination(
                    icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate), label: 'Tools'),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ================================================================ building blocks
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF6366F1)]),
        ),
        child: Icon(Icons.trending_up_rounded, color: Colors.white, size: size * 0.62),
      );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.title, this.trailing});
  final Widget child;
  final EdgeInsets padding;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding,
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: title == null
            ? child
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: SectionLabel(title!)),
                  if (trailing != null) trailing!,
                ]),
                const SizedBox(height: 12),
                child,
              ]),
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6));
}

class CoinAvatar extends StatelessWidget {
  const CoinAvatar(this.symbol, {super.key, this.size = 36});
  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: coinColors[symbol] ?? const Color(0xFF334155)),
        child: Text(symbol.length > 4 ? symbol.substring(0, 4) : symbol,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.28)),
      );
}

class SignalBadge extends StatelessWidget {
  const SignalBadge(this.action, {super.key, this.large = false});
  final String action;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = action == 'BUY' ? kUp : action == 'SELL' ? kDown : kMuted;
    final icon = action == 'BUY' ? '▲ ' : action == 'SELL' ? '▼ ' : '';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        color: action == 'WAIT' ? kPanel2 : c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$icon$action',
          style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: large ? 12.5 : 11, letterSpacing: 0.5)),
    );
  }
}

class ChangeChip extends StatelessWidget {
  const ChangeChip(this.value, {super.key, this.solid = false});
  final double? value;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();
    final c = value! >= 0 ? kUp : kDown;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: solid ? c : c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(6)),
      child: Text(pct(value!), style: mono(12, color: solid ? Colors.white : c, w: FontWeight.w700)),
    );
  }
}

class StrengthMeter extends StatelessWidget {
  const StrengthMeter(this.conf, this.color, {super.key});
  final int conf;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final lit = (conf / 5).round();
    return Row(
      children: List.generate(
        20,
        (i) => Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: i < lit ? 1.0 : 0.0),
            duration: Duration(milliseconds: 300 + i * 25),
            builder: (_, v, __) => Container(
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: Color.lerp(kLine, color, v),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key, this.color = kText});
  final String k, v;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: kMuted, fontSize: 13))),
          Text(v, style: mono(13, color: color)),
        ]),
      );
}

class LevelBox extends StatelessWidget {
  const LevelBox(this.label, this.value, this.accent, {super.key, this.sub, this.subColor = kMuted});
  final String label, value;
  final String? sub;
  final Color accent, subColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: kPanel2,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: const TextStyle(color: kMuted, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 3),
          Text(value, style: mono(16, w: FontWeight.w700)),
          if (sub != null) Text(sub!, style: mono(11, color: subColor, w: FontWeight.w500)),
        ]),
      );
}

// ================================================================ charts
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.width = 72, this.height = 28});
  final List<double> values;
  final double width, height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, height: height, child: CustomPaint(painter: _SparkPainter(values)));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v);
  final List<double> v;

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final mn = v.reduce(math.min), mx = v.reduce(math.max), k = (mx - mn) == 0 ? 1.0 : mx - mn;
    final color = v.last >= v.first ? kUp : kDown;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = i / (v.length - 1) * size.width, y = size.height - 2 - (v[i] - mn) / k * (size.height - 4);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.v != v;
}

List<double?> emaOf(List<double> v, int n) {
  final out = <double?>[];
  final k = 2 / (n + 1);
  double? p;
  for (var i = 0; i < v.length; i++) {
    if (i < n - 1) {
      out.add(null);
      continue;
    }
    p = p == null ? v.sublist(0, n).reduce((a, b) => a + b) / n : v[i] * k + p * (1 - k);
    out.add(p);
  }
  return out;
}

class CandleChart extends StatefulWidget {
  const CandleChart({super.key, required this.candles, this.signal, this.daily = false});
  final List<Candle> candles;
  final Signal? signal;
  final bool daily;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  int? hover;
  static const axisW = 62.0;

  void _touch(Offset p, double w) {
    final cw = w - axisW, n = widget.candles.length;
    if (n == 0) return;
    setState(() => hover = p.dx < cw ? (p.dx / (cw / n)).floor().clamp(0, n - 1) : null);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candles;
    final h = hover != null && hover! < c.length ? c[hover!] : null;
    return LayoutBuilder(builder: (context, box) {
      return Stack(children: [
        GestureDetector(
          onHorizontalDragStart: (d) => _touch(d.localPosition, box.maxWidth),
          onHorizontalDragUpdate: (d) => _touch(d.localPosition, box.maxWidth),
          onHorizontalDragEnd: (_) => setState(() => hover = null),
          onTapDown: (d) => _touch(d.localPosition, box.maxWidth),
          onTapUp: (_) => Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => hover = null);
          }),
          child: CustomPaint(
            size: Size(box.maxWidth, box.maxHeight),
            painter: _CandlePainter(c, widget.signal, hover, widget.daily),
          ),
        ),
        if (h != null)
          Positioned(
            left: 4,
            top: 2,
            child: Text(
              'O ${fp(h.o)}  H ${fp(h.h)}  L ${fp(h.l)}  C ${fp(h.c)}',
              style: mono(10.5, color: kMuted, w: FontWeight.w500),
            ),
          ),
      ]);
    });
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.c, this.s, this.hover, this.daily);
  final List<Candle> c;
  final Signal? s;
  final int? hover;
  final bool daily;

  void _text(Canvas cv, String t, Offset o, {Color color = kDim, double size = 10, FontWeight w = FontWeight.w500}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: color, fontSize: size, fontWeight: w, fontFeatures: tabular)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(cv, o.translate(0, -tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (c.isEmpty) {
      _text(canvas, 'Loading chart…', const Offset(8, 20), color: kMuted, size: 13);
      return;
    }
    const axisW = _CandleChartState.axisW, top = 16.0, bottom = 20.0;
    final cw = size.width - axisW, ch = size.height - top - bottom;
    final showLv = s != null && !s!.isWait && !daily;
    var lo = c.map((e) => e.l).reduce(math.min), hi = c.map((e) => e.h).reduce(math.max);
    if (showLv) {
      lo = [lo, s!.stop, s!.tp1].reduce(math.min);
      hi = [hi, s!.stop, s!.tp1].reduce(math.max);
    }
    final pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;
    if (hi == lo) hi = lo + 1;
    double y(double v) => top + (hi - v) / (hi - lo) * ch;
    final n = c.length, step = cw / n, bw = math.max(1.0, step * 0.62);
    final grid = Paint()..color = const Color(0xFF1A2030);
    for (var i = 0; i <= 4; i++) {
      final v = lo + (hi - lo) * i / 4, yy = y(v);
      canvas.drawLine(Offset(0, yy), Offset(cw, yy), grid);
      _text(canvas, fp(v), Offset(cw + 6, yy));
    }
    final every = (n / 4).ceil();
    for (var i = 0; i < n; i += every) {
      final d = DateTime.fromMillisecondsSinceEpoch(c[i].t);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final lab = daily ? '${months[d.month - 1]} ${d.day}' : '${two(d.hour)}:${two(d.minute)}';
      _text(canvas, lab, Offset(math.min(i * step, cw - 34), size.height - 8));
    }
    for (var i = 0; i < n; i++) {
      final k = c[i], x = i * step + step / 2, up = k.c >= k.o;
      final p = Paint()..color = up ? kUp : kDown;
      canvas.drawLine(Offset(x, y(k.h)), Offset(x, y(k.l)), p..strokeWidth = 1);
      final t = y(math.max(k.o, k.c)), b = y(math.min(k.o, k.c));
      canvas.drawRect(Rect.fromLTWH(x - bw / 2, t, bw, math.max(1.0, b - t)), p);
    }
    final closes = c.map((e) => e.c).toList();
    for (final e in [[21, kEma21], [50, kEma50]]) {
      final ema = emaOf(closes, e[0] as int);
      final path = Path();
      var started = false;
      for (var i = 0; i < ema.length; i++) {
        final v = ema[i];
        if (v == null) continue;
        final pt = Offset(i * step + step / 2, y(v));
        if (started) {
          path.lineTo(pt.dx, pt.dy);
        } else {
          path.moveTo(pt.dx, pt.dy);
        }
        started = true;
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = e[1] as Color
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke);
    }
    void level(double v, Color col, String tag, {bool dashed = true}) {
      final yy = y(v);
      final p = Paint()
        ..color = col
        ..strokeWidth = 1;
      if (dashed) {
        for (var x = 0.0; x < cw; x += 9) {
          canvas.drawLine(Offset(x, yy), Offset(math.min(x + 5, cw), yy), p);
        }
      } else {
        canvas.drawLine(Offset(0, yy), Offset(cw, yy), p);
      }
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cw + 1, yy - 9, axisW - 1, 18), const Radius.circular(3)),
          Paint()..color = col);
      _text(canvas, fp(v), Offset(cw + 5, yy), color: Colors.white, w: FontWeight.w700);
      if (tag.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
              text: tag, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
          textDirection: TextDirection.ltr,
        )..layout();
        final w = tp.width + 10;
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(cw - w - 4, yy - 9, w, 18), const Radius.circular(3)),
            Paint()..color = col);
        tp.paint(canvas, Offset(cw - w + 1, yy - tp.height / 2));
      }
    }

    if (showLv) {
      level(s!.price, kAccent, 'ENTRY');
      level(s!.tp1, kUp, 'TP1');
      level(s!.stop, kDown, 'SL');
    }
    final last = c.last;
    level(last.c, last.c >= last.o ? kUp : kDown, '', dashed: false);
    if (hover != null && hover! < n) {
      final x = hover! * step + step / 2;
      final p = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      for (var yy = top; yy < top + ch; yy += 6) {
        canvas.drawLine(Offset(x, yy), Offset(x, yy + 3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) => true;
}

// ================================================================ markets
class MarketsPage extends StatelessWidget {
  const MarketsPage({super.key, required this.app, required this.onOpen});
  final AppState app;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final top = app.order.isEmpty ? null : app.signals[app.order.first];
    final active = app.order.where((n) => !app.signals[n]!.isWait).length;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              const AppLogo(size: 30),
              const SizedBox(width: 10),
              const Text(appName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              const Spacer(),
              StatusPill(app: app),
            ]),
          ),
        ),
        if (!app.loaded)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (app.error != null)
          SliverFillRemaining(
              child: Center(child: Text('Could not load signals.\n${app.error}',
                  textAlign: TextAlign.center, style: const TextStyle(color: kMuted))))
        else if (app.order.isEmpty)
          const SliverFillRemaining(
              child: Center(child: Text('Waiting for the first signals…', style: TextStyle(color: kMuted))))
        else ...[
          if (app.stale)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Notice('Signals have not updated for over 3 hours. Prices are still live.'),
              ),
            ),
          SliverToBoxAdapter(child: TickerTape(app: app, onOpen: onOpen)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                _Stat('Assets', '${app.order.length}'),
                _Stat('Active signals', '$active'),
                _Stat('Next update', '', countdown: app.nextRunMs),
              ]),
            ),
          ),
          if (top != null && !top.isWait)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TopSignalCard(app: app, s: top, onTap: () => onOpen(top.name)),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Row(children: [
                const Text('Markets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                for (final f in const [['all', 'All'], ['crypto', 'Crypto'], ['stock', 'Stocks']])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(f[1]),
                      selected: app.filter == f[0],
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelStyle: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: app.filter == f[0] ? kText : kMuted),
                      side: const BorderSide(color: kLine),
                      backgroundColor: kPanel2,
                      selectedColor: kLine2,
                      onSelected: (_) => app.setFilter(f[0]),
                    ),
                  ),
              ]),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(children: [
                Expanded(flex: 5, child: _Head('Asset')),
                Expanded(flex: 3, child: _Head('48h')),
                Expanded(flex: 4, child: _Head('Price', right: true)),
                Expanded(flex: 3, child: _Head('Signal', right: true)),
              ]),
            ),
          ),
          SliverList.builder(
            itemCount: app.visible.length,
            itemBuilder: (_, i) => MarketRow(app: app, symbol: app.visible[i], onTap: () => onOpen(app.visible[i])),
          ),
          const SliverToBoxAdapter(child: Disclaimer()),
        ],
      ]),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.t, {this.right = false});
  final String t;
  final bool right;

  @override
  Widget build(BuildContext context) => Text(t.toUpperCase(),
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: const TextStyle(color: kDim, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6));
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.countdown});
  final String label, value;
  final int? countdown;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: kPanel, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
            const SizedBox(height: 2),
            countdown != null ? Countdown(targetMs: countdown!) : Text(value, style: mono(17, w: FontWeight.w700)),
          ]),
        ),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final ok = app.liveOk && !app.stale;
    final c = app.stale ? kWarn : ok ? kUp : kMuted;
    final label = app.stale ? 'Delayed' : app.liveOk ? 'Live' : 'Hourly';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        PulseDot(color: c, pulse: ok),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.pulse = true});
  final Color color;
  final bool pulse;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: widget.pulse
                ? [BoxShadow(color: widget.color.withValues(alpha: 0.6 * (1 - _c.value)), spreadRadius: 6 * _c.value)]
                : null,
          ),
        ),
      );
}

class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.targetMs});
  final int targetMs;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var t = widget.targetMs;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (t <= now) t = (now ~/ 3600000 + 1) * 3600000 + 300000;
    final s = (t - now) ~/ 1000;
    return Text('${two(s ~/ 60)}:${two(s % 60)}', style: mono(17, w: FontWeight.w700));
  }
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.color = kWarn});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
      );
}

class TickerTape extends StatefulWidget {
  const TickerTape({super.key, required this.app, required this.onOpen});
  final AppState app;
  final void Function(String) onOpen;

  @override
  State<TickerTape> createState() => _TickerTapeState();
}

class _TickerTapeState extends State<TickerTape> {
  final _sc = ScrollController();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!_sc.hasClients) return;
      final max = _sc.position.maxScrollExtent;
      if (max <= 0) return;
      final next = _sc.offset + 0.8;
      _sc.jumpTo(next >= max / 2 ? next - max / 2 : next);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = [...widget.app.order, ...widget.app.order];
    return Container(
      height: 34,
      decoration: const BoxDecoration(
          color: kPanel, border: Border.symmetric(horizontal: BorderSide(color: kLine))),
      child: ListView.builder(
        controller: _sc,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final n = items[i], c = widget.app.chgOf(n);
          return GestureDetector(
            onTap: () => widget.onOpen(n),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Text(n, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text(fp(widget.app.priceOf(n) ?? 0), style: mono(12, w: FontWeight.w500)),
                const SizedBox(width: 6),
                if (c != null) Text(pct(c), style: mono(12, color: c >= 0 ? kUp : kDown, w: FontWeight.w600)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class TopSignalCard extends StatelessWidget {
  const TopSignalCard({super.key, required this.app, required this.s, required this.onTap});
  final AppState app;
  final Signal s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = app.plan(s.price, s.stop, s.tp1, s.tp2);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: s.color.withValues(alpha: 0.45)),
          gradient: LinearGradient(
            colors: [s.color.withValues(alpha: 0.14), kPanel],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SectionLabel('Top signal'),
            const Spacer(),
            ValidFor(app: app, s: s),
            const SizedBox(width: 8),
            SignalBadge(s.action, large: true),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            CoinAvatar(s.name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.isUp ? 'BUY' : 'SELL'} ${s.pair}',
                    style: TextStyle(color: s.color, fontSize: 19, fontWeight: FontWeight.w800)),
                Text('Strength ${s.conf}/100 · ${strengthLabel(s.conf)}',
                    style: mono(12.5, color: kMuted, w: FontWeight.w500)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: kMuted),
          ]),
          const SizedBox(height: 12),
          StrengthMeter(s.conf, s.color),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _MiniLevel('Entry', fp(s.price), kText)),
            Expanded(child: _MiniLevel('Target', fp(s.tp1), kUp)),
            Expanded(child: _MiniLevel('Stop', fp(s.stop), kDown)),
            Expanded(child: _MiniLevel('R:R', '1:${p.ratio.toStringAsFixed(1)}', kText)),
          ]),
        ]),
      ),
    );
  }
}

class _MiniLevel extends StatelessWidget {
  const _MiniLevel(this.k, this.v, this.c);
  final String k, v;
  final Color c;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(color: kMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(v, style: mono(13.5, color: c, w: FontWeight.w700)),
      ]);
}

class MarketRow extends StatelessWidget {
  const MarketRow({super.key, required this.app, required this.symbol, required this.onTap});
  final AppState app;
  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = app.signals[symbol]!, c = app.chgOf(symbol);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Row(children: [
              CoinAvatar(symbol, size: 32),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(symbol, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text('${coinNames[symbol] ?? ''}${s.isStock ? (s.marketOpen ? ' · Open' : ' · Closed') : ''}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 11.5)),
                ]),
              ),
            ]),
          ),
          Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: Sparkline(app.sparkOf(symbol), width: 60))),
          Expanded(
            flex: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              AnimatedPrice(app.priceOf(symbol) ?? 0, style: mono(14)),
              if (c != null) Text(pct(c), style: mono(11.5, color: c >= 0 ? kUp : kDown)),
            ]),
          ),
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              SignalBadge(s.action),
              if (!s.isWait) Text('${s.conf}/100', style: mono(11, color: kMuted, w: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Price text that briefly flashes green/red when it changes.
class AnimatedPrice extends StatefulWidget {
  const AnimatedPrice(this.value, {super.key, required this.style});
  final double value;
  final TextStyle style;

  @override
  State<AnimatedPrice> createState() => _AnimatedPriceState();
}

class _AnimatedPriceState extends State<AnimatedPrice> {
  Color? flash;
  Timer? _t;

  @override
  void didUpdateWidget(AnimatedPrice old) {
    super.didUpdateWidget(old);
    if (old.value != 0 && widget.value != old.value) {
      flash = widget.value > old.value ? kUp : kDown;
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => flash = null);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 250),
        style: widget.style.copyWith(color: flash ?? widget.style.color),
        child: Text(fp(widget.value)),
      );
}

class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Text(
          'Signals come from technical indicators on past prices. Signal strength shows how strongly the indicators '
          'agree; it is not a probability of profit. Always use a stop loss, risk at most 1–2% per trade, and '
          'paper-trade first. Not financial advice. Market data: Binance.',
          style: TextStyle(color: kDim, fontSize: 11, height: 1.5),
        ),
      );
}

// ================================================================ asset detail
class AssetPage extends StatefulWidget {
  const AssetPage({super.key, required this.app, required this.symbol});
  final AppState app;
  final String symbol;

  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  String interval = '1h';
  List<Candle> candles = [];
  Timer? _refresh;
  int _loadId = 0;
  WebSocket? _ws;
  bool liveChart = false;
  late bool tv = widget.app.signals[widget.symbol]?.isStock ?? false;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) => _load());
    widget.app.addListener(_onLive);
  }

  void _onLive() {
    final p = widget.app.live[widget.symbol]?.price;
    if (p != null && candles.isNotEmpty && !liveChart) {
      final k = candles.last;
      k.c = p;
      k.h = math.max(k.h, p);
      k.l = math.min(k.l, p);
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final id = ++_loadId;
    final sig = widget.app.signals[widget.symbol];
    if (sig != null && sig.isStock) {
      candles = sig.candles;
      if (id > 1 && mounted) setState(() {});
      return;
    }
    if (_ws != null) return; // live stream already running
    try {
      final r = await http
          .get(Uri.parse('${binance}klines?symbol=${widget.symbol}USDT&interval=$interval&limit=80'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw Exception(r.statusCode);
      final list = (jsonDecode(r.body) as List)
          .map((x) => x as List)
          .map((x) => Candle((x[0] as num).toInt(), double.parse(x[1] as String), double.parse(x[2] as String),
              double.parse(x[3] as String), double.parse(x[4] as String)))
          .toList();
      if (mounted && id == _loadId) {
        setState(() => candles = list);
        _startWs();
      }
    } catch (_) {
      final s = widget.app.signals[widget.symbol];
      if (mounted && id == _loadId && candles.isEmpty && s != null) setState(() => candles = s.candles);
    }
  }

  Future<void> _startWs() async {
    _stopWs();
    final iv = interval;
    try {
      final ws = await WebSocket.connect(
          'wss://data-stream.binance.vision/ws/${widget.symbol.toLowerCase()}usdt@kline_$iv');
      if (!mounted || iv != interval) {
        ws.close();
        return;
      }
      _ws = ws;
      setState(() => liveChart = true);
      ws.listen((msg) {
        final k = (jsonDecode(msg as String) as Map)['k'] as Map?;
        if (k == null || !mounted) return;
        final nc = Candle((k['t'] as num).toInt(), double.parse(k['o'] as String), double.parse(k['h'] as String),
            double.parse(k['l'] as String), double.parse(k['c'] as String));
        setState(() {
          if (candles.isNotEmpty && candles.last.t == nc.t) {
            candles.last
              ..h = nc.h
              ..l = nc.l
              ..c = nc.c;
          } else if (candles.isEmpty || nc.t > candles.last.t) {
            candles = [...candles, nc];
            if (candles.length > 120) candles = candles.sublist(candles.length - 120);
          }
        });
      }, onDone: () {
        if (_ws == ws) {
          _ws = null;
          if (mounted) setState(() => liveChart = false);
        }
      }, onError: (Object _) {});
    } catch (_) {
      if (mounted) setState(() => liveChart = false);
    }
  }

  void _stopWs() {
    final w = _ws;
    _ws = null;
    liveChart = false;
    w?.close();
  }

  @override
  void dispose() {
    _stopWs();
    _refresh?.cancel();
    widget.app.removeListener(_onLive);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, n = widget.symbol, s = app.signals[n];
    final t = app.live[n], price = app.priceOf(n) ?? 0, chg = app.chgOf(n);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          CoinAvatar(n, size: 28),
          const SizedBox(width: 10),
          Text('$n', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(s?.isStock == true ? '  US STOCK' : '/USDT',
              style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: StatusPill(app: app))],
      ),
      body: s == null
          ? const Center(child: Text('No data', style: TextStyle(color: kMuted)))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text(coinNames[n] ?? n, style: const TextStyle(color: kMuted, fontSize: 13)),
              const SizedBox(height: 2),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                AnimatedPrice(price, style: mono(30, w: FontWeight.w700)),
                const SizedBox(width: 10),
                Padding(padding: const EdgeInsets.only(bottom: 6), child: ChangeChip(chg)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _HeadStat('24h High', fp(t?.high ?? s.hi24)),
                _HeadStat('24h Low', fp(t?.low ?? s.lo24)),
                _HeadStat('24h Vol', '\$${bigNum(t?.quoteVol ?? s.vol24)}'),
                _HeadStat('RSI 14', s.rsi == null ? '—' : s.rsi!.toStringAsFixed(1)),
              ]),
              const SizedBox(height: 14),
              Panel(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
                child: Column(children: [
                  Row(children: [
                    const SizedBox(width: 4),
                    const SectionLabel('Chart'),
                    const SizedBox(width: 8),
                    LiveBadge(
                        on: tv || liveChart,
                        label: tv ? 'LIVE' : liveChart ? 'LIVE' : (s.isStock ? 'HOURLY' : 'CONNECTING')),
                    const Spacer(),
                    for (final m in const [[false, 'Signal'], [true, 'TradingView']])
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: ChoiceChip(
                          label: Text(m[1] as String),
                          selected: tv == m[0],
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: tv == m[0] ? kText : kMuted),
                          side: const BorderSide(color: kLine),
                          backgroundColor: kPanel2,
                          selectedColor: kLine2,
                          onSelected: (_) {
                            final v = m[0] as bool;
                            setState(() {
                              tv = v;
                              if (v) _stopWs();
                            });
                            if (!v) _load();
                          },
                        ),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Spacer(),
                    for (final iv in ['15m', '1h', '4h', '1d'])
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: ChoiceChip(
                          label: Text(iv == '15m' ? '15m' : iv.toUpperCase()),
                          selected: interval == iv,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: interval == iv ? kText : kMuted),
                          side: const BorderSide(color: kLine),
                          backgroundColor: kPanel2,
                          selectedColor: kLine2,
                          onSelected: (_) {
                            setState(() {
                              interval = iv;
                              candles = [];
                            });
                            _stopWs();
                            _load();
                          },
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: tv ? 400 : 280,
                    child: tv
                        ? TradingViewChart(symbol: s.tvSymbol, interval: interval)
                        : CandleChart(candles: candles, signal: s, daily: interval == '1d'),
                  ),
                  if (!tv) const SizedBox(height: 8),
                  if (!tv) const Wrap(spacing: 14, runSpacing: 4, children: [
                    _Legend(kEma21, 'EMA 21'),
                    _Legend(kEma50, 'EMA 50'),
                    _Legend(kAccent, 'Entry'),
                    _Legend(kUp, 'Target'),
                    _Legend(kDown, 'Stop'),
                  ]),
                ]),
              ),
              SignalPanel(app: app, s: s),
              TechnicalPanel(s: s),
              const Disclaimer(),
            ]),
    );
  }
}

class _HeadStat extends StatelessWidget {
  const _HeadStat(this.k, this.v);
  final String k, v;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(),
              style: const TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
          const SizedBox(height: 2),
          Text(v, style: mono(12.5)),
        ]),
      );
}

class _Legend extends StatelessWidget {
  const _Legend(this.c, this.t);
  final Color c;
  final String t;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 2, color: c),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(color: kMuted, fontSize: 11)),
      ]);
}

class SignalPanel extends StatelessWidget {
  const SignalPanel({super.key, required this.app, required this.s});
  final AppState app;
  final Signal s;

  @override
  Widget build(BuildContext context) {
    final head = Row(children: [
      const Expanded(child: SectionLabel('AI signal · 1H')),
      SignalBadge(s.action, large: true),
    ]);
    if (s.isWait) {
      return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          const SizedBox(height: 12),
          SignalBanner(app: app, s: s),
          const SizedBox(height: 10),
          const Text('Indicators disagree. Staying out is a valid position.',
              style: TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 14),
          StrengthMeter(s.conf, kMuted),
          const SizedBox(height: 6),
          Text('Signal strength ${s.conf}/100 · ${strengthLabel(s.conf)}', style: mono(12, color: kMuted)),
        ]),
      );
    }
    final p = app.plan(s.price, s.stop, s.tp1, s.tp2);
    final now = app.priceOf(s.name) ?? s.price, moved = (now / s.price - 1) * 100 * (s.isUp ? 1 : -1);
    String d(double x) => pct((x / s.price - 1) * 100);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        const SizedBox(height: 12),
        SignalBanner(app: app, s: s),
        const SizedBox(height: 10),
        Text.rich(TextSpan(style: mono(12.5, color: kMuted, w: FontWeight.w500), children: [
          TextSpan(text: 'Signal at ${fp(s.price)} · now '),
          TextSpan(text: '${fp(now)} (${pct(moved)})', style: TextStyle(color: moved >= 0 ? kUp : kDown)),
        ])),
        const SizedBox(height: 14),
        StrengthMeter(s.conf, s.color),
        const SizedBox(height: 6),
        Row(children: [
          const Expanded(child: Text('Signal strength', style: TextStyle(color: kMuted, fontSize: 12))),
          Text('${s.conf}/100 · ${strengthLabel(s.conf)}', style: mono(12, color: kMuted)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: LevelBox('Entry', fp(s.price), kAccent, sub: 'Market')),
          const SizedBox(width: 8),
          Expanded(child: LevelBox('Stop loss', fp(s.stop), kDown, sub: d(s.stop), subColor: kDown)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: LevelBox('Target 1', fp(s.tp1), kUp, sub: d(s.tp1), subColor: kUp)),
          const SizedBox(width: 8),
          Expanded(child: LevelBox('Target 2', fp(s.tp2), kUp, sub: d(s.tp2), subColor: kUp)),
        ]),
        const SizedBox(height: 10),
        KV('Risk / reward', '1 : ${p.ratio.toStringAsFixed(2)}'),
        KV('Position size', '${money(p.spend)} · ${p.units.toStringAsPrecision(4)} ${s.name}'),
        KV('Max loss at stop', '−${money(p.loss)}', color: kDown),
        KV('Profit at target 1 / 2', '+${money(p.win1)} / +${money(p.win2)}', color: kUp),
        if (!s.isUp)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Short positions need a futures or margin account. On a spot account, treat this as "avoid buying".',
                style: TextStyle(color: kMuted, fontSize: 12, height: 1.4)),
          ),
        if (p.tooSmall)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Position is below your exchange minimum order.', style: TextStyle(color: kDown, fontSize: 12)),
          ),
      ]),
    );
  }
}

class _NextUpdate extends StatelessWidget {
  const _NextUpdate({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: kPanel2, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Expanded(child: Text('Next signal update', style: TextStyle(color: kMuted, fontSize: 12))),
          Countdown(targetMs: app.nextRunMs),
        ]),
      );
}

class TechnicalPanel extends StatelessWidget {
  const TechnicalPanel({super.key, required this.s});
  final Signal s;

  List<String> _row(Map<String, dynamic> c) {
    switch (c['label']) {
      case 'Trend':
        return ['Trend (EMA 21/50)', s.ema21 == null ? '—' : '${fp(s.ema21!)} / ${fp(s.ema50 ?? 0)}'];
      case 'Short trend':
        return ['Momentum (EMA 9/21)', '—'];
      case 'Strength':
        return ['RSI (14)', s.rsi?.toStringAsFixed(1) ?? '—'];
      case 'Speed':
        return ['MACD histogram', s.macd?.toStringAsPrecision(3) ?? '—'];
      case 'Range':
        return ['Bollinger %B', s.bbPos?.toStringAsFixed(2) ?? '—'];
      case 'Volume':
        return ['Volume vs 50h avg', s.volRatio == null ? '—' : '${s.volRatio!.toStringAsFixed(2)}×'];
      default:
        return ['${c['label'] ?? ''}', '—'];
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = s.checks.fold<double>(0, (a, c) => a + _d(c['score']).sign);
    final pos = s.checks.isEmpty ? 0.5 : 0.5 + total / s.checks.length / 2;
    return Panel(
      title: 'Technical analysis',
      child: Column(children: [
        Row(children: [
          const Text('Sell', style: TextStyle(color: kDown, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (_, b) => SizedBox(
                height: 14,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: const LinearGradient(colors: [kDown, kLine2, kUp]),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    left: (b.maxWidth * pos - 1.5).clamp(0.0, b.maxWidth - 3).toDouble(),
                    top: 0,
                    child: Container(
                        width: 3,
                        height: 14,
                        decoration:
                            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text('Buy', style: TextStyle(color: kUp, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        for (final c in s.checks)
          Builder(builder: (_) {
            final r = _row(c), sc = _d(c['score']);
            final (label, col) = sc > 0 ? ('Bullish', kUp) : sc < 0 ? ('Bearish', kDown) : ('Neutral', kMuted);
            return Tooltip(
              message: '${c['note'] ?? ''}',
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
                child: Row(children: [
                  Expanded(flex: 5, child: Text(r[0], style: const TextStyle(fontSize: 13))),
                  Expanded(flex: 4, child: Text(r[1], textAlign: TextAlign.right, style: mono(12.5, color: kMuted))),
                  const SizedBox(width: 10),
                  Container(
                    width: 64,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: sc == 0 ? kPanel2 : col.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(label, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            );
          }),
      ]),
    );
  }
}

// ================================================================ picks
class PicksPage extends StatelessWidget {
  const PicksPage({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final d = app.picks;
    final m = (d?['model'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final picks = ((d?['picks'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final acc = _d(m['confident_accuracy']) * 100, base = _d(m['baseline']) * 100, edge = acc - base;
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        const Text('5-day picks', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('S&P 500 + crypto · machine learning · ${d?['generatedAt'] ?? 'daily 09:00 Doha'}',
            style: const TextStyle(color: kMuted, fontSize: 12.5)),
        const SizedBox(height: 14),
        if (d == null)
          const Panel(child: Text('Waiting for the first daily scan…', style: TextStyle(color: kMuted)))
        else ...[
          Row(children: [
            Expanded(child: _Kpi('Exam accuracy', '${acc.toStringAsFixed(1)}%')),
            const SizedBox(width: 8),
            Expanded(child: _Kpi('Baseline', '${base.toStringAsFixed(1)}%', color: kMuted)),
            const SizedBox(width: 8),
            Expanded(
                child: _Kpi('Edge', '${edge >= 0 ? '+' : ''}${edge.toStringAsFixed(1)} pts',
                    color: edge >= 2 ? kUp : kWarn)),
          ]),
          const SizedBox(height: 8),
          Text('Model: ${m['name'] ?? '—'} · tested on data it never saw while learning',
              style: const TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 12),
          if (m['has_edge'] != true)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Notice('No edge today: the model did not beat simple guessing on its exam. Do not trade these picks.'),
            ),
          if (picks.isEmpty)
            const Panel(child: Text('No trade today. No asset passed the accuracy filters.', style: TextStyle(color: kMuted))),
          for (final p in picks) _PickCard(p: p),
        ],
        const Disclaimer(),
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.k, this.v, {this.color = kText});
  final String k, v;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(),
              style: const TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
          const SizedBox(height: 3),
          Text(v, style: mono(17, color: color, w: FontWeight.w700)),
        ]),
      );
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final buy = p['signal'] == 'BUY', color = buy ? kUp : kDown;
    final plan = (p['plan'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final hours = (p['hours'] as Map?)?.cast<String, dynamic>();
    final ticker = '${p['ticker'] ?? ''}', prob = _d(p['probability']);
    final entry = _d(plan['entry']);
    String d(double x) => entry == 0 ? '' : pct((x / entry - 1) * 100);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CoinAvatar(ticker.replaceAll('-USD', ''), size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ticker, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const Text('5-day outlook', style: TextStyle(color: kMuted, fontSize: 11.5)),
            ]),
          ),
          SignalBadge(buy ? 'BUY' : 'SELL', large: true),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: prob),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
                value: v, minHeight: 6, backgroundColor: kLine, valueColor: AlwaysStoppedAnimation(color)),
          ),
        ),
        const SizedBox(height: 5),
        Row(children: [
          Expanded(
              child: Text('Model probability (${buy ? 'up' : 'down'})',
                  style: const TextStyle(color: kMuted, fontSize: 12))),
          Text('${(prob * 100).round()}%', style: mono(12, color: kMuted)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: LevelBox('Entry', fp(entry), kAccent)),
          const SizedBox(width: 8),
          Expanded(
              child: LevelBox('Stop', fp(_d(plan['stop'])), kDown, sub: d(_d(plan['stop'])), subColor: kDown)),
          const SizedBox(width: 8),
          Expanded(
              child: LevelBox('Target', fp(_d(plan['target'])), kUp, sub: d(_d(plan['target'])), subColor: kUp)),
        ]),
        const SizedBox(height: 8),
        KV('Backtest hit rate', '${(_d(p['accuracy']) * 100).round()}% · ${_i(p['samples'])} signals'),
        if (hours != null) KV('Best entry / exit (Doha)', '${hours['buy_hour']} / ${hours['sell_hour']}'),
      ]),
    );
  }
}

// ================================================================ alerts
class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key, required this.app, required this.onToggle, required this.onOpen});
  final AppState app;
  final Future<void> Function(bool) onToggle;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        const Text('Alerts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Panel(
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.notifications_active_outlined, color: kAccent),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Push notifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 2),
                Text('Strong signals only (strength 55+), max 3 per hour',
                    style: TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ),
            Switch(value: app.alertsOn, activeTrackColor: kAccent, onChanged: onToggle),
          ]),
        ),
        Panel(
          title: 'History',
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: app.alerts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('No alerts yet.', style: TextStyle(color: kMuted)),
                )
              : Column(children: [
                  for (final a in app.alerts)
                    InkWell(
                      onTap: () => onOpen('${a['name']}'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
                        child: Row(children: [
                          CoinAvatar('${a['name']}', size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${a['dir'] == 'UP' ? 'BUY' : 'SELL'} ${a['market'] == 'stock' ? a['name'] : '${a['name']}/USDT'}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                  'Entry ${fp(_d(a['price']))} · TP ${fp(_d(a['tp1']))} · SL ${fp(_d(a['stop']))}',
                                  style: mono(11.5, color: kMuted, w: FontWeight.w500)),
                            ]),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            SignalBadge(a['dir'] == 'UP' ? 'BUY' : 'SELL'),
                            const SizedBox(height: 3),
                            Text(timeAgo(_i(a['atMs'])), style: const TextStyle(color: kMuted, fontSize: 11)),
                          ]),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ================================================================ tools
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.app});
  final AppState app;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  late final bal = TextEditingController(text: widget.app.balance.toStringAsFixed(0));
  late final fee = TextEditingController(text: '${widget.app.fee}');
  late final minO = TextEditingController(text: widget.app.minOrder.toStringAsFixed(0));
  final sym = TextEditingController(), entry = TextEditingController(), tp = TextEditingController(),
      sl = TextEditingController();
  bool long = true;
  Widget? result;

  @override
  void dispose() {
    for (final c in [bal, fee, minO, sym, entry, tp, sl]) {
      c.dispose();
    }
    super.dispose();
  }

  double _v(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  void _analyse() {
    FocusScope.of(context).unfocus();
    final e = _v(entry), t = _v(tp), s = _v(sl), sd = long ? 1 : -1;
    if (e <= 0 || t <= 0 || s <= 0) {
      setState(() => result = const Text('Enter entry, take-profit and stop-loss prices.', style: TextStyle(color: kDown)));
      return;
    }
    if ((s - e) * sd >= 0 || (t - e) * sd <= 0) {
      setState(() => result = Text(
          long ? 'For a long: stop loss below entry, take profit above.' : 'For a short: stop loss above entry, take profit below.',
          style: const TextStyle(color: kDown)));
      return;
    }
    final app = widget.app, p = app.plan(e, s, t, t);
    final key = sym.text.toUpperCase().replaceAll(RegExp(r'USDT?$'), '').trim(), m = app.signals[key];
    final grade = p.ratio >= 2 ? ('Good setup', kUp) : p.ratio >= 1.5 ? ('Acceptable', kWarn) : ('Poor risk/reward', kDown);
    setState(() => result = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: grade.$2.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(6)),
              child: Text(grade.$1, style: TextStyle(color: grade.$2, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          ),
          const SizedBox(height: 8),
          KV('Risk / reward', '1 : ${p.ratio.toStringAsFixed(2)}'),
          KV('Position size', money(p.spend)),
          KV('Profit at target', '+${money(p.win1)}', color: kUp),
          KV('Loss at stop', '−${money(p.loss)}', color: kDown),
          if (m != null)
            KV(
              'AI signal',
              m.isWait
                  ? 'Neutral'
                  : ((m.isUp && long) || (!m.isUp && !long))
                      ? 'Agrees (${m.action} ${m.conf}/100)'
                      : 'Disagrees (${m.action} ${m.conf}/100)',
              color: m.isWait ? kMuted : ((m.isUp && long) || (!m.isUp && !long)) ? kUp : kDown,
            ),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    InputDecoration dec(String l) => InputDecoration(labelText: l, isDense: true);
    const numKb = TextInputType.numberWithOptions(decimal: true);
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        const Text('Tools', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Panel(
          title: 'Account & risk',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: bal,
              keyboardType: numKb,
              decoration: dec('Account balance (USD)'),
              onChanged: (_) => app.setBalance(_v(bal)),
            ),
            const SizedBox(height: 12),
            const Text('Risk per trade', style: TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final k in riskProfiles.keys)
                  ButtonSegment(
                    value: k,
                    label: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(riskNames[k]!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('${riskProfiles[k]![0]}%', style: mono(11, color: kMuted, w: FontWeight.w500)),
                    ]),
                  ),
              ],
              selected: {app.risk},
              onSelectionChanged: (v) => app.setRisk(v.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: minO,
                    keyboardType: numKb,
                    decoration: dec('Min. order (USD)'),
                    onChanged: (_) => app.setMin(_v(minO))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                    controller: fee,
                    keyboardType: numKb,
                    decoration: dec('Fee per side (%)'),
                    onChanged: (_) => app.setFee(_v(fee))),
              ),
            ]),
            const SizedBox(height: 10),
            const Text(
                'Position sizes on every signal use these settings, so a stop-loss hit never costs more than your chosen risk.',
                style: TextStyle(color: kMuted, fontSize: 12, height: 1.4)),
          ]),
        ),
        Panel(
          title: 'Trade planner',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: TextField(controller: sym, decoration: dec('Asset (e.g. BTC)'))),
              const SizedBox(width: 10),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Long')),
                  ButtonSegment(value: false, label: Text('Short')),
                ],
                selected: {long},
                onSelectionChanged: (v) => setState(() => long = v.first),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: entry, keyboardType: numKb, decoration: dec('Entry'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: tp, keyboardType: numKb, decoration: dec('Take profit'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: sl, keyboardType: numKb, decoration: dec('Stop loss'))),
            ]),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _analyse,
              child: const Text('Analyse trade', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (result != null) ...[const SizedBox(height: 12), result!],
          ]),
        ),
        const Disclaimer(),
      ]),
    );
  }
}

// ================================================================ signal timer + live chart widgets
/// (ms left, fraction of validity left) for a signal; ms <= 0 means it is waiting for the next update.
(int, double) validity(AppState app, Signal s) {
  final now = DateTime.now().millisecondsSinceEpoch;
  var until = s.validUntil > 0 ? s.validUntil : app.nextRunMs;
  if (until <= 0) until = (now ~/ 3600000 + 1) * 3600000 + 300000;
  final start = s.issuedAt > 0 ? s.issuedAt : until - 3600000;
  final left = until - now;
  return (left, left <= 0 ? 0.0 : (left / math.max(1, until - start)).clamp(0.0, 1.0).toDouble());
}

String clock(int ms) {
  final sec = ms ~/ 1000;
  return '${sec >= 3600 ? '${sec ~/ 3600}:' : ''}${two((sec ~/ 60) % 60)}:${two(sec % 60)}';
}

mixin _EverySecond<T extends StatefulWidget> on State<T> {
  Timer? _sec;

  @override
  void initState() {
    super.initState();
    _sec = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sec?.cancel();
    super.dispose();
  }
}

class SignalBanner extends StatefulWidget {
  const SignalBanner({super.key, required this.app, required this.s});
  final AppState app;
  final Signal s;

  @override
  State<SignalBanner> createState() => _SignalBannerState();
}

class _SignalBannerState extends State<SignalBanner> with _EverySecond<SignalBanner> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s, closed = s.isStock && !s.marketOpen;
    final (left, frac) = validity(widget.app, s);
    final neutral = closed || s.isWait;
    final c = neutral ? kText : s.color;
    final big = closed ? 'MARKET CLOSED' : s.isWait ? 'NO TRADE' : s.isUp ? 'BUY NOW' : 'SELL NOW';
    final sub = closed
        ? 'Last signal ${s.action} · resumes at the US market open'
        : s.isWait
            ? '${s.pair} · wait for a clearer setup'
            : '${s.pair} at market · ${fp(widget.app.priceOf(s.name) ?? s.price)}';
    final label = closed ? 'Signal paused' : s.isWait ? 'Next check in' : 'Valid for';
    final time = closed ? '—' : left <= 0 ? 'Updating…' : clock(left);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: neutral ? kPanel2 : s.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: neutral ? kLine : s.color.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(big, style: TextStyle(color: c, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              const SizedBox(height: 2),
              Text(sub, style: mono(11.5, color: kMuted, w: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(label.toUpperCase(),
                style: const TextStyle(color: kMuted, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            Text(time, style: mono(left <= 0 && !closed ? 15 : 22, w: FontWeight.w700)),
          ]),
        ]),
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
            value: frac, minHeight: 4, backgroundColor: kLine, valueColor: const AlwaysStoppedAnimation(kAccent)),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Text('Issued ${s.issuedAt > 0 ? hm(s.issuedAt) : '—'}', style: const TextStyle(color: kMuted, fontSize: 11.5)),
        const Spacer(),
        if (!s.isWait && s.since > 0)
          Text('${s.action} since ${hm(s.since)} · ${ago(s.since)}',
              style: const TextStyle(color: kMuted, fontSize: 11.5)),
      ]),
    ]);
  }
}

class ValidFor extends StatefulWidget {
  const ValidFor({super.key, required this.app, required this.s});
  final AppState app;
  final Signal s;

  @override
  State<ValidFor> createState() => _ValidForState();
}

class _ValidForState extends State<ValidFor> with _EverySecond<ValidFor> {
  @override
  Widget build(BuildContext context) {
    final (left, _) = validity(widget.app, widget.s);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.timer_outlined, size: 14, color: kMuted),
      const SizedBox(width: 3),
      Text(left <= 0 ? 'updating' : clock(left), style: mono(12, color: kMuted)),
    ]);
  }
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, required this.on, required this.label});
  final bool on;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        PulseDot(color: on ? kUp : kDim, pulse: on),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: on ? kUp : kMuted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ]);
}

/// Live TradingView chart (real-time crypto, 15-minute delayed US stocks).
class TradingViewChart extends StatefulWidget {
  const TradingViewChart({super.key, required this.symbol, required this.interval});
  final String symbol, interval;

  @override
  State<TradingViewChart> createState() => _TradingViewChartState();
}

class _TradingViewChartState extends State<TradingViewChart> {
  final _c = WebViewController();

  @override
  void initState() {
    super.initState();
    _c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kPanel)
      ..loadHtmlString(_html(), baseUrl: 'https://decno786.github.io/');
  }

  @override
  void didUpdateWidget(TradingViewChart old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol || old.interval != widget.interval) {
      _c.loadHtmlString(_html(), baseUrl: 'https://decno786.github.io/');
    }
  }

  String _html() {
    final iv = const {'15m': '15', '1h': '60', '4h': '240', '1d': 'D'}[widget.interval] ?? '60';
    final cfg = jsonEncode({
      'autosize': true, 'symbol': widget.symbol, 'interval': iv, 'timezone': 'Asia/Qatar', 'theme': 'dark',
      'style': '1', 'locale': 'en', 'backgroundColor': '#11151D', 'gridColor': 'rgba(31,38,51,1)',
      'hide_side_toolbar': true, 'allow_symbol_change': false, 'save_image': false, 'calendar': false,
      'studies': ['STD;EMA'], 'support_host': 'https://www.tradingview.com',
    });
    return '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#11151D}</style></head><body>'
        '<div class="tradingview-widget-container" style="height:100%;width:100%">'
        '<div class="tradingview-widget-container__widget" style="height:100%;width:100%"></div>'
        '<script type="text/javascript" src="https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js" async>'
        '$cfg</script></div></body></html>';
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: WebViewWidget(
          controller: _c,
          gestureRecognizers: {Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer())},
        ),
      );
}
