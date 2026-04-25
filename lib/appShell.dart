import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'blu.dart';
import 'homePage.dart';
import 'healthDashboardPage.dart';
import 'stressHistoryPage.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const String _historyStorageKey = 'stress_history_items';

  int _selectedIndex = 1;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  bool _isBleConnected = false;
  String _latestBleMessage = "";
  int _bleSequence = 0;
  int _historyVersion = 0;

  String _lastSavedFingerprint = "";

  Future<void> _handleBleStateChanged({
    BluetoothDevice? device,
    BluetoothCharacteristic? txChar,
    BluetoothCharacteristic? rxChar,
    required bool isConnected,
    String lastMessage = "",
  }) async {
    setState(() {
      _device = device;
      _txChar = txChar;
      _rxChar = rxChar;
      _isBleConnected = isConnected;
      _latestBleMessage = lastMessage;
      _bleSequence++;
    });

    if (isConnected && lastMessage.trim().isNotEmpty) {
      await _persistStressEntryFromBle(lastMessage);
    }
  }

  Future<void> _persistStressEntryFromBle(String message) async {
    try {
      final data = _parseBleMessage(message);

      final stress = (data['stress'] ?? '').trim();
      if (stress.isEmpty) return;

      final score = (data['score'] ?? '').trim();
      final temp = (data['temp'] ?? '').trim();
      final hr = (data['hr'] ?? '').trim();

      // fingerprint prevents saving the exact same packet repeatedly
      final fingerprint = '$stress|$score|$temp|$hr';
      if (fingerprint == _lastSavedFingerprint) return;
      _lastSavedFingerprint = fingerprint;

      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_historyStorageKey) ?? [];

      final item = {
        'status': stress,
        'score': score,
        'temp': temp,
        'hr': hr,
        'timestamp': DateTime.now().toIso8601String(),
      };

      existing.insert(0, jsonEncode(item));

      // keep the newest 500 only
      if (existing.length > 500) {
        existing.removeRange(500, existing.length);
      }

      await prefs.setStringList(_historyStorageKey, existing);

      if (mounted) {
        setState(() {
          _historyVersion++;
        });
      }
    } catch (_) {
      // ignore malformed BLE packets
    }
  }

  Map<String, String> _parseBleMessage(String msg) {
    final parts = msg.split(',');
    final Map<String, String> data = {};

    for (final part in parts) {
      final kv = part.split(':');
      if (kv.length >= 2) {
        final key = kv.first.trim().toLowerCase();
        final value = kv.sublist(1).join(':').trim();
        data[key] = value;
      }
    }

    return data;
  }

  @override
  Widget build(BuildContext context) {
    const topColor    = Color(0xFFC8602A); // rust orange — AppBar & Nav
    const bottomColor = Color(0xFFD4855A); // warm sand — body bottom

    final pages = [
      HealthDashboardPage(
        isDeviceConnected: _isBleConnected,
        latestBleMessage: _latestBleMessage,
        bleSequence: _bleSequence,
      ),
      HomePage(
        device: _device,
        isDeviceConnected: _isBleConnected,
        latestBleMessage: _latestBleMessage,
        onOpenStressHistory: () => setState(() => _selectedIndex = 2),
      ),
      StressHistoryPage(
        historyVersion: _historyVersion,
      ),
      Blu(
        onBleStateChanged: _handleBleStateChanged,
      ),
    ];

    final screenWidth = MediaQuery.of(context).size.width;
    final titleFontSize = screenWidth < 360 ? 34.0 : 42.0;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: screenWidth < 360 ? 76 : 88,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'سَكينة',
          style: TextStyle(
            color: Colors.white,
            fontSize: titleFontSize,
            fontWeight: FontWeight.w500,
            fontFamily: "Aldhabi",
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [topColor, bottomColor],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [topColor, bottomColor],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.2, 1.0],
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
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white70,
            selectedFontSize: screenWidth < 360 ? 10 : 11,
            unselectedFontSize: screenWidth < 360 ? 9 : 10,
            iconSize: screenWidth < 360 ? 22 : 24,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.monitor_heart_outlined),
                label: "Dashboard",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: "Home",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.auto_graph_outlined),
                label: "History",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bluetooth),
                label: "Connect",
              ),
            ],
          ),
      ),
    );
  }
}