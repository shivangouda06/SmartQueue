import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.load();
  runApp(SmartQueueApp(store: store));
}

class AppStore extends ChangeNotifier {
  AppStore._(this.prefs);

  final SharedPreferences prefs;

  String? phone;
  String name = '';
  String email = '';
  String? profilePath;

  bool notificationsEnabled = true;
  bool darkMode = false;
  bool locationEnabled = false;

  ActiveQueue? activeQueue;

  final List<QueueRecord> history = [];
  final List<AppNotification> notifications = [];
  final Set<String> favourites = {};

  static Future<AppStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppStore._(prefs);

    s.phone = prefs.getString('phone');
    s.name = prefs.getString('name') ?? '';
    s.email = prefs.getString('email') ?? '';
    s.profilePath = prefs.getString('profilePath');

    s.notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;

    s.darkMode = prefs.getBool('darkMode') ?? false;

    s.locationEnabled = prefs.getBool('locationEnabled') ?? false;

    final active = prefs.getString('activeQueue');

    if (active != null) {
      s.activeQueue = ActiveQueue.decode(active);
    }

    final favs = prefs.getStringList('favourites') ?? [];
    s.favourites.addAll(favs);

    final historyData = prefs.getStringList('history') ?? [];

    for (final item in historyData) {
      final q = QueueRecord.decode(item);

      if (q != null) {
        s.history.add(q);
      }
    }

    return s;
  }

  bool get loggedIn => phone != null;

  Future<void> login(String mobile, {String? userName}) async {
    phone = mobile;

    if (userName != null && userName.trim().isNotEmpty) {
      name = userName.trim();

      await prefs.setString('name', name);
    }

    await prefs.setString('phone', mobile);

    notifyListeners();
  }

  Future<void> logout() async {
    phone = null;
    activeQueue = null;

    await prefs.remove('phone');
    await prefs.remove('activeQueue');

    notifyListeners();
  }

  Future<void> saveProfile({
    required String newName,
    required String newEmail,
    String? newProfilePath,
  }) async {
    name = newName.trim();
    email = newEmail.trim();

    profilePath = newProfilePath ?? profilePath;

    await prefs.setString('name', name);
    await prefs.setString('email', email);

    if (profilePath != null) {
      await prefs.setString('profilePath', profilePath!);
    }

    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;

    await prefs.setBool('darkMode', value);

    notifyListeners();
  }

  Future<void> setNotifications(bool value) async {
    notificationsEnabled = value;

    await prefs.setBool('notificationsEnabled', value);

    notifyListeners();
  }

  Future<void> setLocationEnabled(bool value) async {
    locationEnabled = value;

    await prefs.setBool('locationEnabled', value);

    notifyListeners();
  }

  Future<void> joinQueue(ActiveQueue queue) async {
    activeQueue = queue;

    await prefs.setString('activeQueue', queue.encode());

    addNotification(
      'Queue joined',
      'Your token ${queue.token} is confirmed at '
          '${queue.businessName}.',
      Icons.confirmation_number,
    );

    notifyListeners();
  }

  Future<void> updateQueue({
    required int peopleAhead,
    required int estimatedMinutes,
  }) async {
    if (activeQueue == null) return;

    activeQueue = activeQueue!.copyWith(
      peopleAhead: peopleAhead,
      estimatedMinutes: estimatedMinutes,
    );

    await prefs.setString('activeQueue', activeQueue!.encode());

    notifyListeners();
  }

  Future<void> leaveQueue() async {
    final q = activeQueue;

    if (q != null) {
      history.insert(
        0,
        QueueRecord(
          businessName: q.businessName,
          serviceName: q.serviceName,
          token: q.token,
          joinedAt: q.joinedAt,
          status: 'Cancelled',
        ),
      );

      await _saveHistory();

      addNotification(
        'Queue cancelled',
        'You left the queue at ${q.businessName}.',
        Icons.cancel_outlined,
      );
    }

    activeQueue = null;

    await prefs.remove('activeQueue');

    notifyListeners();
  }

  Future<void> completeQueue() async {
    final q = activeQueue;

    if (q == null) return;

    history.insert(
      0,
      QueueRecord(
        businessName: q.businessName,
        serviceName: q.serviceName,
        token: q.token,
        joinedAt: q.joinedAt,
        status: 'Completed',
      ),
    );

    await _saveHistory();

    activeQueue = null;

    await prefs.remove('activeQueue');

    addNotification(
      'Queue completed',
      'Your visit at ${q.businessName} has been completed.',
      Icons.check_circle_outline,
    );

    notifyListeners();
  }

  Future<void> _saveHistory() async {
    await prefs.setStringList(
      'history',
      history.take(30).map((e) => e.encode()).toList(),
    );
  }

  Future<void> toggleFavourite(String id) async {
    if (favourites.contains(id)) {
      favourites.remove(id);
    } else {
      favourites.add(id);
    }

    await prefs.setStringList('favourites', favourites.toList());

    notifyListeners();
  }

  void addNotification(String title, String body, IconData icon) {
    notifications.insert(
      0,
      AppNotification(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        body: body,
        icon: icon,
        time: DateTime.now(),
      ),
    );

    if (notifications.length > 50) {
      notifications.removeLast();
    }

    notifyListeners();
  }

  void clearNotifications() {
    notifications.clear();

    notifyListeners();
  }
}

class ActiveQueue {
  final String businessName;
  final String serviceName;
  final String token;
  final int peopleAhead;
  final int estimatedMinutes;
  final DateTime joinedAt;

  ActiveQueue({
    required this.businessName,
    required this.serviceName,
    required this.token,
    required this.peopleAhead,
    required this.estimatedMinutes,
    required this.joinedAt,
  });

  ActiveQueue copyWith({int? peopleAhead, int? estimatedMinutes}) =>
      ActiveQueue(
        businessName: businessName,
        serviceName: serviceName,
        token: token,
        peopleAhead: peopleAhead ?? this.peopleAhead,
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
        joinedAt: joinedAt,
      );

  String encode() => [
    businessName,
    serviceName,
    token,
    peopleAhead,
    estimatedMinutes,
    joinedAt.millisecondsSinceEpoch,
  ].join('|');

  static ActiveQueue decode(String value) {
    final p = value.split('|');

    return ActiveQueue(
      businessName: p[0],
      serviceName: p[1],
      token: p[2],
      peopleAhead: int.tryParse(p[3]) ?? 0,
      estimatedMinutes: int.tryParse(p[4]) ?? 0,
      joinedAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(p[5]) ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class QueueRecord {
  final String businessName;
  final String serviceName;
  final String token;
  final DateTime joinedAt;
  final String status;

  QueueRecord({
    required this.businessName,
    required this.serviceName,
    required this.token,
    required this.joinedAt,
    required this.status,
  });

  String encode() => [
    businessName,
    serviceName,
    token,
    joinedAt.millisecondsSinceEpoch,
    status,
  ].join('|');

  static QueueRecord? decode(String value) {
    final p = value.split('|');

    if (p.length < 5) return null;

    return QueueRecord(
      businessName: p[0],
      serviceName: p[1],
      token: p[2],
      joinedAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse(p[3]) ?? 0),
      status: p[4],
    );
  }
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final DateTime time;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.time,
  });
}

class Business {
  final String id;
  final String name;
  final String category;
  final String address;
  final double rating;
  final int reviews;
  final int peopleWaiting;
  final int avgMinutes;
  final IconData icon;
  final Color color;
  final bool open;

  const Business({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.rating,
    required this.reviews,
    required this.peopleWaiting,
    required this.avgMinutes,
    required this.icon,
    required this.color,
    this.open = true,
  });
}

const businesses = <Business>[
  Business(
    id: 'city-care',
    name: 'City Care Hospital',
    category: 'Hospital',
    address: 'Station Road',
    rating: 4.6,
    reviews: 1280,
    peopleWaiting: 12,
    avgMinutes: 6,
    icon: Icons.local_hospital,
    color: Colors.red,
  ),

  Business(
    id: 'royal-spice',
    name: 'Royal Spice Restaurant',
    category: 'Restaurant',
    address: 'Main Market',
    rating: 4.5,
    reviews: 860,
    peopleWaiting: 7,
    avgMinutes: 5,
    icon: Icons.restaurant,
    color: Colors.orange,
  ),

  Business(
    id: 'style-studio',
    name: 'Style Studio',
    category: 'Salon & Spa',
    address: 'City Center',
    rating: 4.7,
    reviews: 540,
    peopleWaiting: 4,
    avgMinutes: 10,
    icon: Icons.content_cut,
    color: Colors.pink,
  ),

  Business(
    id: 'medicare',
    name: 'MediCare Pharmacy',
    category: 'Pharmacy',
    address: 'Gandhi Chowk',
    rating: 4.3,
    reviews: 410,
    peopleWaiting: 5,
    avgMinutes: 4,
    icon: Icons.local_pharmacy,
    color: Colors.green,
  ),

  Business(
    id: 'city-bank',
    name: 'City Bank',
    category: 'Bank',
    address: 'MG Road',
    rating: 4.2,
    reviews: 720,
    peopleWaiting: 9,
    avgMinutes: 8,
    icon: Icons.account_balance,
    color: Colors.blue,
  ),

  Business(
    id: 'autocare',
    name: 'AutoCare Service',
    category: 'Vehicle Service',
    address: 'Industrial Area',
    rating: 4.4,
    reviews: 290,
    peopleWaiting: 3,
    avgMinutes: 12,
    icon: Icons.directions_car,
    color: Colors.indigo,
  ),
];

class SmartQueueApp extends StatelessWidget {
  final AppStore store;

  const SmartQueueApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SmartQueue',
          themeMode: store.darkMode ? ThemeMode.dark : ThemeMode.light,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: store.loggedIn
              ? HomeShell(store: store)
              : AuthPage(store: store),
        );
      },
    );
  }
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF6F8FC),

      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF60A5FA),
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B1220),

      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF151F32),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: const Color(0xFF151F32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class AuthPage extends StatefulWidget {
  final AppStore store;

  const AuthPage({super.key, required this.store});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final phone = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();

  bool register = false;
  bool loading = false;

  @override
  void dispose() {
    phone.dispose();
    name.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> startOtp() async {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length != 10) {
      showMessage(context, 'Enter a valid 10-digit mobile number.');
      return;
    }

    if (register && name.text.trim().length < 2) {
      showMessage(context, 'Enter your full name.');
      return;
    }

    setState(() => loading = true);

    await Future.delayed(const Duration(milliseconds: 650));

    if (!mounted) return;

    setState(() => loading = false);

    final otpCode = (Random().nextInt(900000) + 100000).toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpPage(
          store: widget.store,
          mobile: digits,
          otpCode: otpCode,
          userName: register ? name.text.trim() : null,
          email: register ? email.text.trim() : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 62,
                    width: 62,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.queue_play_next_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    register ? 'Create your account' : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    register
                        ? 'Join SmartQueue and skip unnecessary waiting.'
                        : 'Sign in to manage your queues and appointments.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 28),

                  if (register) ...[
                    TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline),
                        labelText: 'Full name',
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.email_outlined),
                        labelText: 'Email (optional)',
                      ),
                    ),

                    const SizedBox(height: 14),
                  ],

                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.phone_android_outlined),
                      prefixText: '+91 ',
                      labelText: 'Mobile number',
                      counterText: '',
                    ),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: loading ? null : startOtp,
                      child: loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'CONTINUE WITH OTP',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => register = !register),
                      child: Text(
                        register
                            ? 'Already have an account? Login'
                            : 'New to SmartQueue? Create account',
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  _InfoStrip(
                    icon: Icons.verified_user_outlined,
                    title: 'Secure sign-in',
                    text:
                        'Your account is protected by mobile OTP verification.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OtpPage extends StatefulWidget {
  final AppStore store;
  final String mobile;
  final String otpCode;
  final String? userName;
  final String? email;

  const OtpPage({
    super.key,
    required this.store,
    required this.mobile,
    required this.otpCode,
    this.userName,
    this.email,
  });

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final otp = TextEditingController();

  Timer? timer;

  late String currentOtp;

  int seconds = 30;

  bool verifying = false;

  @override
  void initState() {
    super.initState();

    currentOtp = widget.otpCode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showMessage(context, 'Development OTP: $currentOtp');
      }
    });

    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      if (seconds > 0) {
        setState(() => seconds--);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    otp.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    if (otp.text.trim() != currentOtp) {
      showMessage(context, 'Invalid OTP. Check the development OTP message.');
      return;
    }

    setState(() => verifying = true);

    await widget.store.login(widget.mobile, userName: widget.userName);

    if (widget.email != null && widget.email!.isNotEmpty) {
      await widget.store.saveProfile(
        newName: widget.userName ?? widget.store.name,
        newEmail: widget.email!,
      );
    }

    widget.store.addNotification(
      'Welcome to SmartQueue',
      'Your account is ready. Find a queue near you.',
      Icons.waving_hand_outlined,
    );

    if (!mounted) return;

    setState(() => verifying = false);

    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void resend() {
    currentOtp = (Random().nextInt(900000) + 100000).toString();
    otp.clear();
    setState(() => seconds = 30);
    showMessage(context, 'Development OTP: $currentOtp');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify mobile')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                const SizedBox(height: 30),

                const Icon(Icons.sms_outlined, size: 70),

                const SizedBox(height: 20),

                const Text(
                  'Enter verification code',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),

                const SizedBox(height: 8),

                Text(
                  'We sent a 6-digit OTP to '
                  '+91 ${widget.mobile}.',
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 28),

                TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    counterText: '',
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: verifying ? null : verify,
                    child: verifying
                        ? const CircularProgressIndicator()
                        : const Text('VERIFY & CONTINUE'),
                  ),
                ),

                const SizedBox(height: 12),

                TextButton(
                  onPressed: seconds == 0
                      ? resend
                      : null,
                  child: Text(
                    seconds == 0
                        ? 'Resend OTP'
                        : 'Resend OTP in '
                              '${seconds}s',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final AppStore store;

  const HomeShell({super.key, required this.store});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(store: widget.store),
      MyQueuesPage(store: widget.store),
      FavouritesPage(store: widget.store),
      ProfilePage(store: widget.store),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),

      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),

        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),

          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'My Queues',
          ),

          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Saved',
          ),

          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final AppStore store;

  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.store.name.trim().isEmpty
        ? 'there'
        : widget.store.name.trim().split(' ').first;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good day, $firstName ■',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),

                        const SizedBox(height: 3),

                        Text(
                          'Skip the queue.',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NotificationsPage(store: widget.store),
                      ),
                    ),
                    icon: Badge(
                      isLabelVisible: widget.store.notifications.isNotEmpty,
                      child: const Icon(Icons.notifications_none_rounded),
                    ),
                  ),

                  ProfileAvatar(store: widget.store, radius: 21),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            sliver: SliverToBoxAdapter(
              child: TextField(
                controller: search,

                onSubmitted: (value) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SearchPage(store: widget.store, query: value),
                    ),
                  );
                },

                decoration: InputDecoration(
                  hintText: 'Search hospitals, restaurants, salons...',

                  prefixIcon: const Icon(Icons.search),

                  suffixIcon: IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SearchPage(store: widget.store, query: search.text),
                      ),
                    ),
                    icon: const Icon(Icons.tune),
                  ),
                ),
              ),
            ),
          ),

          if (widget.store.activeQueue != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              sliver: SliverToBoxAdapter(
                child: ActiveQueueCard(store: widget.store),
              ),
            ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Browse categories',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),

                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AllCategoriesPage(store: widget.store),
                      ),
                    ),
                    child: const Text('View all'),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: 98,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    categoryItem('Hospital', Icons.local_hospital, Colors.red),

                    categoryItem('Restaurant', Icons.restaurant, Colors.orange),

                    categoryItem('Bank', Icons.account_balance, Colors.blue),

                    categoryItem('Salon & Spa', Icons.content_cut, Colors.pink),

                    categoryItem(
                      'Pharmacy',
                      Icons.local_pharmacy,
                      Colors.green,
                    ),

                    categoryItem(
                      'Vehicle Service',
                      Icons.directions_car,
                      Colors.indigo,
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 10),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Popular near you',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),

                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SearchPage(store: widget.store, query: ''),
                      ),
                    ),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BusinessCard(
                    store: widget.store,
                    business: businesses[index],
                  ),
                ),
                childCount: businesses.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget categoryItem(String title, IconData icon, Color color) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchPage(store: widget.store, query: title),
        ),
      ),
      child: Container(
        width: 88,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color.withOpacity(.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- SEARCH / BUSINESS ----------------

class SearchPage extends StatefulWidget {
  final AppStore store;
  final String query;

  const SearchPage({super.key, required this.store, required this.query});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController controller;

  bool nearMe = false;
  Position? position;

  @override
  void initState() {
    super.initState();

    controller = TextEditingController(text: widget.query);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> enableNearMe() async {
    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showMessage(context, 'Location permission is required.');
        return;
      }

      final service = await Geolocator.isLocationServiceEnabled();

      if (!service) {
        showMessage(context, 'Turn on location services and try again.');
        return;
      }

      final p = await Geolocator.getCurrentPosition();

      setState(() {
        position = p;
        nearMe = true;
      });

      await widget.store.setLocationEnabled(true);
    } catch (_) {
      showMessage(context, 'Could not get your location.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = controller.text.trim().toLowerCase();

    final filtered = businesses.where((b) {
      if (q.isEmpty) return true;

      return b.name.toLowerCase().contains(q) ||
          b.category.toLowerCase().contains(q) ||
          b.address.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a place'),

        actions: [
          IconButton(
            onPressed: enableNearMe,
            icon: Icon(nearMe ? Icons.my_location : Icons.location_searching),
          ),
        ],
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),

            child: TextField(
              controller: controller,
              autofocus: widget.query.isEmpty,

              onChanged: (_) => setState(() {}),

              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),

          if (nearMe)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),

              child: Align(
                alignment: Alignment.centerLeft,

                child: Chip(
                  avatar: const Icon(Icons.my_location, size: 17),

                  label: const Text('Near me enabled'),

                  onDeleted: () => setState(() => nearMe = false),
                ),
              ),
            ),

          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'No results',
                    message: 'Try another name or category.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),

                    itemCount: filtered.length,

                    separatorBuilder: (_, __) => const SizedBox(height: 12),

                    itemBuilder: (_, i) => BusinessCard(
                      store: widget.store,
                      business: filtered[i],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class BusinessCard extends StatelessWidget {
  final AppStore store;
  final Business business;

  const BusinessCard({super.key, required this.store, required this.business});

  @override
  Widget build(BuildContext context) {
    final fav = store.favourites.contains(business.id);

    return InkWell(
      borderRadius: BorderRadius.circular(20),

      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessDetailsPage(store: store, business: business),
        ),
      ),

      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),

          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,

                decoration: BoxDecoration(
                  color: business.color.withOpacity(.11),
                  borderRadius: BorderRadius.circular(17),
                ),

                child: Icon(business.icon, color: business.color, size: 30),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      business.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(business.category),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: Colors.amber,
                        ),

                        const SizedBox(width: 2),

                        Text('${business.rating}'),

                        const SizedBox(width: 8),

                        Flexible(
                          child: Text(
                            '${business.peopleWaiting} waiting • '
                            '~${business.avgMinutes} min',

                            overflow: TextOverflow.ellipsis,

                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              IconButton(
                onPressed: () => store.toggleFavourite(business.id),

                icon: Icon(
                  fav ? Icons.favorite : Icons.favorite_border,

                  color: fav ? Colors.red : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LegacyBusinessDetailsPage extends StatelessWidget {
  final AppStore store;
  final Business business;

  const LegacyBusinessDetailsPage({
    super.key,
    required this.store,
    required this.business,
  });

  Future<void> join(BuildContext context) async {
    final result = await Navigator.push<ActiveQueue>(
      context,
      MaterialPageRoute(
        builder: (_) => JoinQueuePage(store: store, business: business),
      ),
    );

    if (result != null && context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business'),

        actions: [
          IconButton(
            onPressed: () => store.toggleFavourite(business.id),

            icon: Icon(
              store.favourites.contains(business.id)
                  ? Icons.favorite
                  : Icons.favorite_border,
            ),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),

        children: [
          Container(
            height: 170,

            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  business.color.withOpacity(.18),

                  Theme.of(context).colorScheme.surface,
                ],
              ),

              borderRadius: BorderRadius.circular(28),
            ),

            child: Center(
              child: Icon(business.icon, size: 72, color: business.color),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            business.name,

            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),

          const SizedBox(height: 6),

          Text(
            '${business.category} • '
            '${business.address}',
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber),

              const SizedBox(width: 5),

              Text(
                '${business.rating} '
                '(${business.reviews} reviews)',

                style: const TextStyle(fontWeight: FontWeight.w700),
              ),

              const Spacer(),

              Text(
                business.open ? 'OPEN' : 'CLOSED',

                style: TextStyle(
                  color: business.open ? Colors.green : Colors.red,

                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: StatBox(
                  title: 'Waiting',
                  value: '${business.peopleWaiting}',
                  icon: Icons.people_outline,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: StatBox(
                  title: 'Est. wait',
                  value: '${business.peopleWaiting * business.avgMinutes}m',
                  icon: Icons.timer_outlined,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          const Text(
            'About',

            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 8),

          Text(
            'Join the digital queue before you arrive. '
            'Track your token and estimated waiting time '
            'from SmartQueue.',

            style: TextStyle(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 54,

            child: FilledButton.icon(
              onPressed: business.open ? () => join(context) : null,

              icon: const Icon(Icons.confirmation_number_outlined),

              label: const Text('JOIN QUEUE'),
            ),
          ),
        ],
      ),
    );
  }
}

class LegacyJoinQueuePage extends StatefulWidget {
  final AppStore store;
  final Business business;

  const LegacyJoinQueuePage({
    super.key,
    required this.store,
    required this.business,
  });

  @override
  State<LegacyJoinQueuePage> createState() => _LegacyJoinQueuePageState();
}

class _LegacyJoinQueuePageState extends State<LegacyJoinQueuePage> {
  bool loading = false;

  String selectedService = 'General service';

  @override
  Widget build(BuildContext context) {
    return JoinQueuePage(store: widget.store, business: widget.business);
  }

  Future<void> join() async {
    if (widget.store.activeQueue != null) {
      final replace = await showDialog<bool>(
        context: context,

        builder: (_) => AlertDialog(
          title: const Text('Active queue exists'),

          content: const Text(
            'You already have an active queue. '
            'Leave it and join this queue?',
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),

              child: const Text('Keep current'),
            ),

            FilledButton(
              onPressed: () => Navigator.pop(context, true),

              child: const Text('Leave & join'),
            ),
          ],
        ),
      );

      if (replace != true) return;

      await widget.store.leaveQueue();
    }

    setState(() => loading = true);

    await Future.delayed(const Duration(milliseconds: 550));

    final seed = Random().nextInt(89) + 1;

    final queue = ActiveQueue(
      businessName: widget.business.name,

      serviceName: selectedService,

      token: 'SQ-${100 + seed}',

      peopleAhead: widget.business.peopleWaiting,

      estimatedMinutes:
          widget.business.peopleWaiting * widget.business.avgMinutes,

      joinedAt: DateTime.now(),
    );

    await widget.store.joinQueue(queue);

    if (!mounted) return;

    setState(() => loading = false);

    Navigator.pop(context, queue);
  }
}

class BusinessDetailsPage extends StatelessWidget {
  final AppStore store;
  final Business business;

  const BusinessDetailsPage({
    super.key,
    required this.store,
    required this.business,
  });

  Future<void> join(BuildContext context) async {
    final result = await Navigator.push<ActiveQueue>(
      context,
      MaterialPageRoute(
        builder: (_) => JoinQueuePage(store: store, business: business),
      ),
    );

    if (result != null && context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business'),
        actions: [
          IconButton(
            onPressed: () => store.toggleFavourite(business.id),
            icon: Icon(
              store.favourites.contains(business.id)
                  ? Icons.favorite
                  : Icons.favorite_border,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
        children: [
          Container(
            height: 170,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  business.color.withOpacity(.18),
                  Theme.of(context).colorScheme.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: Icon(business.icon, size: 72, color: business.color),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            business.name,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),

          const SizedBox(height: 6),

          Text(
            '${business.category} • '
            '${business.address}',
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber),

              const SizedBox(width: 5),

              Text(
                '${business.rating} '
                '(${business.reviews} reviews)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),

              const Spacer(),

              Text(
                business.open ? 'OPEN' : 'CLOSED',
                style: TextStyle(
                  color: business.open ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: StatBox(
                  title: 'Waiting',
                  value: '${business.peopleWaiting}',
                  icon: Icons.people_outline,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: StatBox(
                  title: 'Est. wait',
                  value: '${business.peopleWaiting * business.avgMinutes}m',
                  icon: Icons.timer_outlined,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          const Text(
            'About',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 8),

          Text(
            'Join the digital queue before you arrive. '
            'Track your token and estimated waiting time '
            'from SmartQueue.',
            style: TextStyle(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: business.open ? () => join(context) : null,
              icon: const Icon(Icons.confirmation_number_outlined),
              label: const Text('JOIN QUEUE'),
            ),
          ),
        ],
      ),
    );
  }
}

class JoinQueuePage extends StatefulWidget {
  final AppStore store;
  final Business business;

  const JoinQueuePage({super.key, required this.store, required this.business});

  @override
  State<JoinQueuePage> createState() => _JoinQueuePageState();
}

class _JoinQueuePageState extends State<JoinQueuePage> {
  bool loading = false;

  String selectedService = 'General service';

  Future<void> join() async {
    if (widget.store.activeQueue != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Active queue exists'),
          content: const Text(
            'You already have an active queue. '
            'Leave it and join this queue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep current'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave & join'),
            ),
          ],
        ),
      );

      if (replace != true) return;

      await widget.store.leaveQueue();
    }

    setState(() => loading = true);

    await Future.delayed(const Duration(milliseconds: 550));

    final seed = Random().nextInt(89) + 1;

    final queue = ActiveQueue(
      businessName: widget.business.name,
      serviceName: selectedService,
      token: 'SQ-${100 + seed}',
      peopleAhead: widget.business.peopleWaiting,
      estimatedMinutes:
          widget.business.peopleWaiting * widget.business.avgMinutes,
      joinedAt: DateTime.now(),
    );

    await widget.store.joinQueue(queue);

    if (!mounted) return;

    setState(() => loading = false);

    Navigator.pop(context, queue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join queue')),

      body: ListView(
        padding: const EdgeInsets.all(18),

        children: [
          Text(
            widget.business.name,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),

          const SizedBox(height: 6),

          Text(widget.business.address),

          const SizedBox(height: 24),

          const Text(
            'Select service',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 10),

          DropdownButtonFormField<String>(
            value: selectedService,

            decoration: const InputDecoration(labelText: 'Service'),

            items: const [
              DropdownMenuItem(
                value: 'General service',
                child: Text('General service'),
              ),
              DropdownMenuItem(
                value: 'Consultation',
                child: Text('Consultation'),
              ),
              DropdownMenuItem(value: 'Billing', child: Text('Billing')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],

            onChanged: (value) {
              if (value != null) {
                setState(() => selectedService = value);
              }
            },
          ),

          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),

              child: Column(
                children: [
                  const Icon(Icons.people_alt_outlined, size: 42),

                  const SizedBox(height: 12),

                  Text(
                    '${widget.business.peopleWaiting} people '
                    'currently waiting',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Estimated waiting time: '
                    '${widget.business.peopleWaiting * widget.business.avgMinutes} minutes',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 54,

            child: FilledButton(
              onPressed: loading ? null : join,

              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('CONFIRM & JOIN QUEUE'),
            ),
          ),
        ],
      ),
    );
  }
}
// ---------------- ACTIVE / MY QUEUES ----------------

class ActiveQueueCard extends StatelessWidget {
  final AppStore store;

  const ActiveQueueCard({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final q = store.activeQueue!;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),

        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ActiveQueuePage(store: store)),
        ),

        child: Container(
          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),

            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,

                Theme.of(context).colorScheme.primaryContainer,
              ],
            ),
          ),

          child: Row(
            children: [
              Container(
                height: 64,
                width: 64,

                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.16),

                  borderRadius: BorderRadius.circular(18),
                ),

                child: const Icon(
                  Icons.confirmation_number,
                  color: Colors.white,
                  size: 32,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'ACTIVE QUEUE',

                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        q.businessName,

                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,

                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        '${q.token} • '
                        '${q.peopleAhead} people ahead',
                      ),
                    ],
                  ),
                ),
              ),

              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActiveQueuePage extends StatefulWidget {
  final AppStore store;

  const ActiveQueuePage({super.key, required this.store});

  @override
  State<ActiveQueuePage> createState() => _ActiveQueuePageState();
}

class _ActiveQueuePageState extends State<ActiveQueuePage> {
  Timer? timer;

  @override
  void initState() {
    super.initState();

    timer = Timer.periodic(const Duration(seconds: 20), (_) async {
      final q = widget.store.activeQueue;

      if (q == null) return;

      if (q.peopleAhead > 0) {
        await widget.store.updateQueue(
          peopleAhead: q.peopleAhead - 1,

          estimatedMinutes: max(0, q.estimatedMinutes - 5),
        );
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> leave() async {
    final ok = await showDialog<bool>(
      context: context,

      builder: (_) => AlertDialog(
        title: const Text('Leave queue?'),

        content: const Text('Your current token will be cancelled.'),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),

            child: const Text('No'),
          ),

          FilledButton(
            onPressed: () => Navigator.pop(context, true),

            child: const Text('Leave queue'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await widget.store.leaveQueue();

      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.store.activeQueue;

    if (q == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.confirmation_number_outlined,
          title: 'No active queue',
          message: 'Join a queue to see it here.',
        ),
      );
    }

    final progress = q.peopleAhead <= 0 ? 1.0 : 1 / (q.peopleAhead + 1);

    return Scaffold(
      appBar: AppBar(title: const Text('Active queue')),

      body: ListView(
        padding: const EdgeInsets.all(18),

        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),

              child: Column(
                children: [
                  Text(
                    q.businessName,

                    textAlign: TextAlign.center,

                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(q.serviceName),

                  const SizedBox(height: 28),

                  Text(
                    q.token,

                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,

                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text('YOUR TOKEN'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: StatBox(
                  title: 'Ahead',
                  value: '${q.peopleAhead}',
                  icon: Icons.people_outline,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: StatBox(
                  title: 'Wait',
                  value: '${q.estimatedMinutes}m',
                  icon: Icons.timer_outlined,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,

                    children: [
                      const Text(
                        'Queue progress',

                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),

                      Text(
                        q.peopleAhead == 0 ? 'You are next' : 'In line',

                        style: TextStyle(
                          color: q.peopleAhead == 0
                              ? Colors.green
                              : Theme.of(context).colorScheme.primary,

                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  LinearProgressIndicator(value: progress),

                  const SizedBox(height: 12),

                  Text(
                    q.peopleAhead == 0
                        ? 'Please stay ready. '
                              'Your turn is next.'
                        : 'SmartQueue updates '
                              'your position automatically.',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          if (q.peopleAhead == 0)
            SizedBox(
              height: 52,

              child: FilledButton.icon(
                onPressed: () async {
                  await widget.store.completeQueue();

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },

                icon: const Icon(Icons.check_circle_outline),

                label: const Text('MARK AS COMPLETED'),
              ),
            ),

          const SizedBox(height: 10),

          OutlinedButton(onPressed: leave, child: const Text('LEAVE QUEUE')),
        ],
      ),
    );
  }
}

class MyQueuesPage extends StatelessWidget {
  final AppStore store;

  const MyQueuesPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),

        children: [
          const Text(
            'My Queues',

            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),

          const SizedBox(height: 5),

          Text(
            'Track active and previous queues '
            'in one place.',

            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 20),

          if (store.activeQueue != null) ...[
            const Text(
              'Active now',

              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 10),

            ActiveQueueCard(store: store),

            const SizedBox(height: 26),
          ],

          const Text(
            'History',

            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 10),

          if (store.history.isEmpty)
            const EmptyState(
              icon: Icons.history,
              title: 'No queue history',
              message:
                  'Your completed and cancelled '
                  'queues will appear here.',
            )
          else
            ...store.history.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: 10),

                child: Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.confirmation_number_outlined),
                    ),

                    title: Text(
                      q.businessName,

                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),

                    subtitle: Text(
                      '${q.token} • '
                      '${formatDate(q.joinedAt)}',
                    ),

                    trailing: Text(
                      q.status,

                      style: TextStyle(
                        fontSize: 12,

                        color: q.status == 'Completed'
                            ? Colors.green
                            : Colors.orange,

                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
// ---------------- FAVOURITES ----------------

class FavouritesPage extends StatelessWidget {
  final AppStore store;

  const FavouritesPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final saved = businesses
        .where((b) => store.favourites.contains(b.id))
        .toList();

    return SafeArea(
      child: saved.isEmpty
          ? const EmptyState(
              icon: Icons.favorite_border,
              title: 'No saved places',
              message:
                  'Tap the heart on a business '
                  'to save it here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),

              children: [
                const Text(
                  'Saved places',

                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                ),

                const SizedBox(height: 18),

                ...saved.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),

                    child: BusinessCard(store: store, business: b),
                  ),
                ),
              ],
            ),
    );
  }
}
// ---------------- PROFILE ----------------

class ProfilePage extends StatelessWidget {
  final AppStore store;

  const ProfilePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  ProfileAvatar(store: store, radius: 34),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.name.isEmpty ? 'SmartQueue user' : store.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text('+91 ${store.phone ?? ''}'),

                        if (store.email.isNotEmpty) Text(store.email),
                      ],
                    ),
                  ),

                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfilePage(store: store),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          SettingsTile(
            icon: Icons.confirmation_number_outlined,
            title: 'My Queues',
            subtitle: 'Active queue and history',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MyQueuesStandalonePage(store: store),
              ),
            ),
          ),

          SettingsTile(
            icon: Icons.business_outlined,
            title: 'Register your business',
            subtitle: 'Create a SmartQueue business profile',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BusinessRegistrationPage(store: store),
              ),
            ),
          ),

          SettingsTile(
            icon: Icons.notifications_none,
            title: 'Notifications',
            subtitle: 'Queue alerts and updates',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationsPage(store: store),
              ),
            ),
          ),

          SettingsTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Privacy, theme and preferences',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsPage(store: store)),
            ),
          ),

          const SizedBox(height: 14),

          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('You can sign in again anytime.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );

              if (ok == true) {
                await store.logout();
              }
            },

            icon: const Icon(Icons.logout),

            label: const Text('LOG OUT'),
          ),
        ],
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  final AppStore store;

  const EditProfilePage({super.key, required this.store});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController name;
  late final TextEditingController email;

  String? photo;

  @override
  void initState() {
    super.initState();

    name = TextEditingController(text: widget.store.name);

    email = TextEditingController(text: widget.store.email);

    photo = widget.store.profilePath;
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 900,
    );

    if (image != null) {
      setState(() => photo = image.path);
    }
  }

  Future<void> save() async {
    if (name.text.trim().length < 2) {
      showMessage(context, 'Please enter your name.');
      return;
    }

    await widget.store.saveProfile(
      newName: name.text,
      newEmail: email.text,
      newProfilePath: photo,
    );

    if (mounted) {
      showMessage(context, 'Profile updated.');

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),

      body: ListView(
        padding: const EdgeInsets.all(18),

        children: [
          Center(
            child: Stack(
              children: [
                ProfileAvatar(
                  store: widget.store,
                  radius: 55,
                  overridePath: photo,
                ),

                Positioned(
                  right: 0,
                  bottom: 0,

                  child: FloatingActionButton.small(
                    onPressed: pickPhoto,

                    child: const Icon(Icons.camera_alt_outlined),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,

            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),

          const SizedBox(height: 14),

          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,

            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),

          const SizedBox(height: 14),

          TextField(
            enabled: false,

            controller: TextEditingController(
              text: '+91 ${widget.store.phone ?? ''}',
            ),

            decoration: const InputDecoration(
              labelText: 'Mobile',
              prefixIcon: Icon(Icons.phone_android_outlined),
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 52,

            child: FilledButton(
              onPressed: save,

              child: const Text('SAVE CHANGES'),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final AppStore store;

  const SettingsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),

      body: ListView(
        padding: const EdgeInsets.all(18),

        children: [
          const Text(
            'Preferences',

            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 10),

          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_none),

                  title: const Text('Queue notifications'),

                  subtitle: const Text('Receive important queue updates'),

                  value: store.notificationsEnabled,

                  onChanged: store.setNotifications,
                ),

                const Divider(height: 1),

                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),

                  title: const Text('Dark mode'),

                  value: store.darkMode,

                  onChanged: store.setDarkMode,
                ),

                const Divider(height: 1),

                ListTile(
                  leading: const Icon(Icons.location_on_outlined),

                  title: const Text('Location'),

                  subtitle: Text(
                    store.locationEnabled
                        ? 'Location access enabled'
                        : 'Location access not enabled',
                  ),

                  trailing: const Icon(Icons.chevron_right),

                  onTap: () async {
                    final enabled = await Geolocator.isLocationServiceEnabled();

                    if (context.mounted) {
                      showMessage(
                        context,
                        enabled
                            ? 'Location services are enabled.'
                            : 'Turn on device location services.',
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'Support',

            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 10),

          SettingsTile(
            icon: Icons.help_outline,
            title: 'Help & support',
            subtitle: 'Get help with SmartQueue',
            onTap: () => showMessage(context, 'Support centre coming soon.'),
          ),

          SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy',
            subtitle: 'Review privacy information',
            onTap: () => showMessage(context, 'Privacy centre coming soon.'),
          ),

          SettingsTile(
            icon: Icons.info_outline,
            title: 'About SmartQueue',
            subtitle: 'Version 1.0.0',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'SmartQueue',
              applicationVersion: '1.0.0',
              applicationLegalese: 'Digital queue management',
            ),
          ),
        ],
      ),
    );
  }
}

class BusinessRegistrationPage extends StatefulWidget {
  final AppStore store;

  const BusinessRegistrationPage({super.key, required this.store});

  @override
  State<BusinessRegistrationPage> createState() =>
      _BusinessRegistrationPageState();
}

class _BusinessRegistrationPageState extends State<BusinessRegistrationPage> {
  final business = TextEditingController();

  final owner = TextEditingController();

  final phone = TextEditingController();

  final address = TextEditingController();

  String category = 'Hospital';

  bool submitting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register your business')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Business details',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: business,
            decoration: const InputDecoration(
              labelText: 'Business name',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: owner,
            decoration: const InputDecoration(
              labelText: 'Owner name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Business phone',
              prefixIcon: Icon(Icons.phone_android_outlined),
              prefixText: '+91 ',
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(
              labelText: 'Category',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'Hospital', child: Text('Hospital')),
              DropdownMenuItem(
                value: 'Restaurant',
                child: Text('Restaurant'),
              ),
              DropdownMenuItem(value: 'Salon & Spa', child: Text('Salon & Spa')),
              DropdownMenuItem(value: 'Pharmacy', child: Text('Pharmacy')),
              DropdownMenuItem(value: 'Bank', child: Text('Bank')),
              DropdownMenuItem(
                value: 'Vehicle Service',
                child: Text('Vehicle Service'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => category = value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: address,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Address',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: submitting ? null : submit,
              child: submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('SUBMIT FOR REVIEW'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    business.dispose();
    owner.dispose();
    phone.dispose();
    address.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (business.text.trim().length < 2 ||
        owner.text.trim().length < 2 ||
        phone.text.replaceAll(RegExp(r'\D'), '').length != 10 ||
        address.text.trim().length < 3) {
      showMessage(context, 'Please complete all required details.');
      return;
    }

    setState(() => submitting = true);

    await Future.delayed(const Duration(milliseconds: 700));

    widget.store.addNotification(
      'Business registration submitted',
      '${business.text.trim()} was submitted for review.',
      Icons.business_outlined,
    );

    if (!mounted) return;

    setState(() => submitting = false);

    await showDialog(
      context: context,

      builder: (_) => AlertDialog(
        title: const Text('Submitted'),

        content: const Text(
          'Your business details are saved locally in this demo. '
          'Connect Firebase/backend approval to make registration live.',
        ),

        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),

            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (mounted) {
      Navigator.pop(context);
    }
  }
}

class NotificationsPage extends StatelessWidget {
  final AppStore store;

  const NotificationsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),

        actions: [
          if (store.notifications.isNotEmpty)
            TextButton(
              onPressed: store.clearNotifications,

              child: const Text('Clear'),
            ),
        ],
      ),

      body: store.notifications.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none,
              title: 'You are all caught up',
              message: 'Important queue updates will appear here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(18),

              itemCount: store.notifications.length,

              separatorBuilder: (_, __) => const SizedBox(height: 8),

              itemBuilder: (_, i) {
                final n = store.notifications[i];

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(n.icon)),

                    title: Text(
                      n.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),

                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),

                      child: Text(n.body),
                    ),

                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}

class AllCategoriesPage extends StatelessWidget {
  final AppStore store;

  const AllCategoriesPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final cats = <Map<String, dynamic>>[
      {'n': 'Hospital', 'i': Icons.local_hospital, 'c': Colors.red},

      {'n': 'Restaurant', 'i': Icons.restaurant, 'c': Colors.orange},

      {'n': 'Bank', 'i': Icons.account_balance, 'c': Colors.blue},

      {'n': 'Salon & Spa', 'i': Icons.content_cut, 'c': Colors.pink},

      {'n': 'Pharmacy', 'i': Icons.local_pharmacy, 'c': Colors.green},

      {'n': 'Hotel', 'i': Icons.hotel, 'c': Colors.purple},

      {'n': 'Vehicle Service', 'i': Icons.directions_car, 'c': Colors.indigo},

      {'n': 'Government', 'i': Icons.account_balance, 'c': Colors.teal},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('All categories')),

      body: GridView.builder(
        padding: const EdgeInsets.all(18),

        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),

        itemCount: cats.length,

        itemBuilder: (_, i) {
          final c = cats[i];

          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),

              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SearchPage(store: store, query: c['n']),
                ),
              ),

              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [
                  Icon(c['i'], color: c['c'], size: 36),

                  const SizedBox(height: 10),

                  Text(
                    c['n'],
                    textAlign: TextAlign.center,

                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class MyQueuesStandalonePage extends StatelessWidget {
  final AppStore store;

  const MyQueuesStandalonePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Queues')),

      body: MyQueuesPage(store: store),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  final AppStore store;
  final double radius;
  final String? overridePath;

  const ProfileAvatar({
    super.key,
    required this.store,
    required this.radius,
    this.overridePath,
  });

  @override
  Widget build(BuildContext context) {
    final path = overridePath ?? store.profilePath;

    if (path != null && path.isNotEmpty) {
      final file = File(path);

      if (file.existsSync()) {
        return CircleAvatar(radius: radius, backgroundImage: FileImage(file));
      }
    }

    return CircleAvatar(
      radius: radius,

      backgroundColor: Theme.of(context).colorScheme.primaryContainer,

      child: Icon(
        Icons.person,
        size: radius,

        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),

      child: ListTile(
        onTap: onTap,

        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,

          child: Icon(icon),
        ),

        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),

        subtitle: Text(subtitle),

        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),

            const SizedBox(height: 16),

            Text(
              title,
              textAlign: TextAlign.center,

              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 7),

            Text(
              message,
              textAlign: TextAlign.center,

              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InfoStrip({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.55),

        borderRadius: BorderRadius.circular(17),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(icon),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),

                const SizedBox(height: 3),

                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatBox extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const StatBox({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

String formatDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');

  final m = date.month.toString().padLeft(2, '0');

  return '$d/$m/${date.year}';
}
