// appShell.dart  (updated — adds FL local training)
//
// Changes from original:
//   1. Instantiates FLLocalTrainer and calls init() in initState
//   2. Feeds every BLE packet into the trainer via _feedTrainer()
//   3. Adds a 5th bottom nav tab "Train" → FLTrainingPage

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'blu.dart';
import 'homePage.dart';
import 'healthDashboardPage.dart';
import 'stressHistoryPage.dart';
import 'fl_local_trainer.dart';
import 'fl_training_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const String _historyStorageKey = 'stress_history_items';

  int _selectedIndex = 1; // default: Home tab

  BluetoothDevice?         _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  bool   _isBleConnected    = false;
  String _latestBleMessage  = "";
  int    _bleSequence       = 0;
  int    _historyVersion    = 0;

  String _lastSavedFingerprint = "";

  // ── FL Trainer ─────────────────────────────────────────────
  final FLLocalTrainer _flTrainer = FLLocalTrainer();

  @override
  void initState() {
    super.initState();
    _flTrainer.init(); // loads persisted weights + dataset
  }

  // ── BLE callback ───────────────────────────────────────────

  Future<void> _handleBleStateChanged({
    BluetoothDevice?         device,
    BluetoothCharacteristic? txChar,
    BluetoothCharacteristic? rxChar,
    required bool isConnected,
    String lastMessage = "",
  }) async {
    setState(() {
      _device           = device;
      _txChar           = txChar;
      _rxChar           = rxChar;
      _isBleConnected   = isConnected;
      _latestBleMessage = lastMessage;
      _bleSequence++;
    });

    if (isConnected && lastMessage.trim().isNotEmpty) {
      await _persistStressEntryFromBle(lastMessage);
      _feedTrainer(lastMessage); // ← new: feed FL pipeline
    }
  }

  // ── FL: parse BLE → trainer ────────────────────────────────

  void _feedTrainer(String message) {
    try {
      final data = _parseBleMessage(message);

      final bvpStr    = data['bvp']    ?? '';
      final tempStr   = data['temp']   ?? '';
      final stressStr = data['stress'] ?? '';

      if (bvpStr.isEmpty || tempStr.isEmpty || stressStr.isEmpty) return;

      final bvp  = double.tryParse(bvpStr);
      final temp = double.tryParse(tempStr);
      if (bvp == null || temp == null) return;

      // onBleData is rate-limited internally (~1 Hz) and returns true
      // only when a full 60-sample window completes.
      _flTrainer.onBleData(
        bvp:         bvp,
        tempCelsius: temp,
        stressLabel: stressStr, // "Normal" or "Stressed" from ESP32 inference
        // userLabel: null  — set to a non-null value if the user manually
        //                    labels their current state (e.g. via a dialog).
      );

      // NOTE: if your ESP32 also sends pre-computed features (bvp_mean etc.),
      // you could parse them here and call _flTrainer.onBleData with them
      // directly instead of reconstructing via the rolling window.
    } catch (_) {
      // ignore malformed packets
    }
  }

  // ── Stress history persistence (unchanged from original) ───

  Future<void> _persistStressEntryFromBle(String message) async {
    try {
      final data = _parseBleMessage(message);

      final stress = (data['stress'] ?? '').trim();
      if (stress.isEmpty) return;

      final score = (data['score'] ?? '').trim();
      final temp  = (data['temp']  ?? '').trim();
      final hr    = (data['hr']    ?? '').trim();

      final fingerprint = '$stress|$score|$temp|$hr';
      if (fingerprint == _lastSavedFingerprint) return;
      _lastSavedFingerprint = fingerprint;

      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_historyStorageKey) ?? [];

      final item = {
        'status':    stress,
        'score':     score,
        'temp':      temp,
        'hr':        hr,
        'timestamp': DateTime.now().toIso8601String(),
      };

      existing.insert(0, jsonEncode(item));
      if (existing.length > 500) existing.removeRange(500, existing.length);
      await prefs.setStringList(_historyStorageKey, existing);

      if (mounted) setState(() => _historyVersion++);
    } catch (_) {}
  }

  Map<String, String> _parseBleMessage(String msg) {
    final parts = msg.split(',');
    final data  = <String, String>{};
    for (final part in parts) {
      final kv = part.split(':');
      if (kv.length >= 2) {
        final key   = kv.first.trim().toLowerCase();
        final value = kv.sublist(1).join(':').trim();
        data[key] = value;
      }
    }
    return data;
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const topColor    = Color(0xFFC8602A);
    const bottomColor = Color(0xFFD4855A);

    final pages = [
      // 0 — Health Dashboard
      HealthDashboardPage(
        isDeviceConnected: _isBleConnected,
        latestBleMessage:  _latestBleMessage,
        bleSequence:       _bleSequence,
      ),
      // 1 — Home (default)
      HomePage(
        device:            _device,
        isDeviceConnected: _isBleConnected,
        latestBleMessage:  _latestBleMessage,
        onOpenStressHistory: () => setState(() => _selectedIndex = 2),
      ),
      // 2 — Stress History
      StressHistoryPage(
        historyVersion: _historyVersion,
      ),
      // 3 — BLE Connect
      Blu(
        onBleStateChanged: _handleBleStateChanged,
      ),
      // 4 — FL Local Training  ← new
      FLTrainingPage(
        trainer: _flTrainer,
      ),
    ];

    final screenWidth  = MediaQuery.of(context).size.width;
    final isSmall      = screenWidth < 360;
    final titleFontSize = isSmall ? 34.0 : 42.0;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        toolbarHeight:   isSmall ? 76 : 88,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'سَكينة',
          style: TextStyle(
            color:      Colors.white,
            fontSize:   titleFontSize,
            fontWeight: FontWeight.w500,
            fontFamily: "Aldhabi",
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [topColor, bottomColor],
              begin:  Alignment.topCenter,
              end:    Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: Container(
        width:  double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [topColor, bottomColor],
            begin:  Alignment.topCenter,
            end:    Alignment.bottomCenter,
            stops:  [0.2, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [bottomColor, topColor],
            begin:  Alignment.topCenter,
            end:    Alignment.bottomCenter,
          ),
        ),
        child: BottomNavigationBar(
          currentIndex:    _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          type:            BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation:       0,
          selectedItemColor:   Colors.white,
          unselectedItemColor: Colors.white70,
          selectedFontSize:   isSmall ? 10 : 11,
          unselectedFontSize: isSmall ?  9 : 10,
          iconSize: isSmall ? 22 : 24,
          items: const [
            BottomNavigationBarItem(
              icon:  Icon(Icons.monitor_heart_outlined),
              label: "Dashboard",
            ),
            BottomNavigationBarItem(
              icon:  Icon(Icons.home),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon:  Icon(Icons.auto_graph_outlined),
              label: "History",
            ),
            BottomNavigationBarItem(
              icon:  Icon(Icons.bluetooth),
              label: "Connect",
            ),
            // ── new tab ──────────────────────────
            BottomNavigationBarItem(
              icon:  Icon(Icons.model_training_outlined),
              label: "Train",
            ),
          ],
        ),
      ),
    );
  }
}
