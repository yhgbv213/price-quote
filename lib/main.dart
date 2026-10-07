// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/product_provider.dart';
import 'providers/quote_provider.dart';
import 'providers/api_source_provider.dart';
import 'providers/settings_provider.dart';
import 'pages/home_page.dart';

import 'providers/cache_provider.dart';

import 'pages/disclaimer_gate.dart';
import 'utils/app_toast.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProductProvider()..loadProducts(),
        ),
        ChangeNotifierProvider(create: (_) => QuoteProvider()),
        ChangeNotifierProvider(create: (_) => ApiSourceProvider()..loadAll()),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => SettingsProvider()..load(),
        ),
        ChangeNotifierProvider(create: (_) => CacheProvider()..load()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听设置变化，实时切换主题
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: '商品报价',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: false,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: false,
        brightness: Brightness.dark,
      ),
      home: const DisclaimerGate(child: HomePage()),
    );
  }
}
