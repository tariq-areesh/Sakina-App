import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

typedef BleStateChanged = void Function({
  BluetoothDevice? device,
  BluetoothCharacteristic? txChar,
  BluetoothCharacteristic? rxChar,
  required bool isConnected,
  String lastMessage,
});

class Blu extends StatefulWidget {
  final BleStateChanged? onBleStateChanged;

  const Blu({
    super.key,
    this.onBleStateChanged,
  });

  @override
  State<Blu> createState() => _BluState();
}

class _BluState extends State<Blu> {
  static final Guid serviceUuid = Guid("12345678-1234-1234-1234-1234567890ab");
  static final Guid txUuid = Guid("12345678-1234-1234-1234-1234567890ac");
  static final Guid rxUuid = Guid("12345678-1234-1234-1234-1234567890ad");

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  final Map<String, ScanResult> _resultsById = {};

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;

  bool _scanning = false;
  bool _isConnected = false;
  String _status = "Please connect a device";
  String _lastMsg = "";

  @override
  void dispose() {
    _notifySub?.cancel();
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  /// Only used on Android. iOS triggers its native Bluetooth prompt
  /// automatically when FlutterBluePlus.startScan is called.
  Future<bool> ensureBlePermissions() async {
    if (Platform.isIOS) return true;

    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    await Permission.locationWhenInUse.request();

    return scan.isGranted && connect.isGranted;
  }

  Future<void> _startScan() async {
    if (_isConnected) {
      setState(() => _status = "Disconnect the current device first");
      return;
    }

    if (!await FlutterBluePlus.isSupported) {
      setState(() => _status = "BLE not supported on this device");
      return;
    }

    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      setState(() => _status = "Please turn Bluetooth ON");
      return;
    }

    setState(() {
      _resultsById.clear();
      _scanning = true;
      _status = "Scanning...";
    });

    _scanSub?.cancel();
    _isScanningSub?.cancel();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        _resultsById[r.device.remoteId.str] = r;
      }
      if (mounted) {
        setState(() {});
      }
    });

    _isScanningSub = FlutterBluePlus.isScanning.listen((isScanning) {
      if (!mounted) return;

      if (!isScanning) {
        setState(() {
          _scanning = false;
          _status = _resultsById.isEmpty
              ? "No devices found"
              : "Tap a device to connect";
        });
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _status = "Scan failed: $e";
      });
    }
  }

  Future<void> _connect(ScanResult r) async {
    final d = r.device;

    setState(() {
      _status =
          "Connecting to ${d.advName.isNotEmpty ? d.advName : d.remoteId.str}...";
      _device = d;
    });

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _connectionSub?.cancel();
    _notifySub?.cancel();

    try {
      await d.connect(timeout: const Duration(seconds: 10));
    } catch (_) {}

    _connectionSub = d.connectionState.listen((state) {
      final isConnected = state == BluetoothConnectionState.connected;

      if (!mounted) return;

      if (!isConnected) {
        setState(() {
          _isConnected = false;
          _status = "Device disconnected";
          _device = null;
          _txChar = null;
          _rxChar = null;
          _lastMsg = "";
        });

        widget.onBleStateChanged?.call(
          device: null,
          txChar: null,
          rxChar: null,
          isConnected: false,
          lastMessage: "",
        );
      }
    });

    try {
      final services = await d.discoverServices();
      final svc = services.firstWhere((s) => s.uuid == serviceUuid);

      _txChar = svc.characteristics.firstWhere((c) => c.uuid == txUuid);
      _rxChar = svc.characteristics.firstWhere((c) => c.uuid == rxUuid);

      await _txChar!.setNotifyValue(true);

      _notifySub = _txChar!.onValueReceived.listen((value) {
        final msg = String.fromCharCodes(value);

        if (mounted) {
          setState(() => _lastMsg = msg);
        }

        widget.onBleStateChanged?.call(
          device: _device,
          txChar: _txChar,
          rxChar: _rxChar,
          isConnected: true,
          lastMessage: msg,
        );
      });

      setState(() {
        _isConnected = true;
        _status = "Connection successful";
      });

      widget.onBleStateChanged?.call(
        device: _device,
        txChar: _txChar,
        rxChar: _rxChar,
        isConnected: true,
        lastMessage: _lastMsg,
      );
    } catch (_) {
      setState(() {
        _isConnected = false;
        _status = "Connection failed";
        _device = null;
        _txChar = null;
        _rxChar = null;
        _lastMsg = "";
      });

      widget.onBleStateChanged?.call(
        device: null,
        txChar: null,
        rxChar: null,
        isConnected: false,
        lastMessage: "",
      );
    }
  }

  Future<void> _disconnect() async {
    final device = _device;
    if (device == null) return;

    setState(() {
      _status = "Disconnecting...";
    });

    try {
      _notifySub?.cancel();
      _notifySub = null;

      _connectionSub?.cancel();
      _connectionSub = null;

      try {
        await device.disconnect();
      } catch (_) {}
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _isConnected = false;
      _status = "Device disconnected";
      _device = null;
      _txChar = null;
      _rxChar = null;
      _lastMsg = "";
    });

    widget.onBleStateChanged?.call(
      device: null,
      txChar: null,
      rxChar: null,
      isConnected: false,
      lastMessage: "",
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _resultsById.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isSmall = width < 360;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            isSmall ? 12 : 16,
            18,
            isSmall ? 12 : 16,
            18,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmall ? 14 : 18,
                    vertical: isSmall ? 16 : 20,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isSmall ? 15 : 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (_scanning || _isConnected)
                                  ? null
                                  : () async {
                                      if (!Platform.isIOS) {
                                        final ok = await ensureBlePermissions();
                                        if (!ok) {
                                          setState(() => _status =
                                              "Bluetooth permission denied");
                                          return;
                                        }
                                      }
                                      await _startScan();
                                    },
                              icon: const Icon(Icons.bluetooth_searching),
                              label: Text(_scanning ? "Scanning..." : "Connect"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color.fromARGB(255, 41, 53, 126),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isConnected ? _disconnect : null,
                              icon: const Icon(Icons.link_off),
                              label: const Text("Disconnect"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7A2E2E),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    Colors.white.withOpacity(0.15),
                                disabledForegroundColor: Colors.white54,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        constraints: BoxConstraints(
                          minHeight: 140,
                          maxHeight: constraints.maxHeight > 500 ? 300 : 220,
                        ),
                        child: results.isEmpty
                            ? Center(
                                child: Text(
                                  _isConnected
                                      ? "Device connected"
                                      : "No devices yet",
                                  style:
                                      const TextStyle(color: Colors.white70),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: results.length,
                                separatorBuilder: (_, __) => Divider(
                                  color: Colors.white.withOpacity(0.15),
                                  height: 1,
                                ),
                                itemBuilder: (context, i) {
                                  final r = results[i];
                                  final name = r.device.advName.isNotEmpty
                                      ? r.device.advName
                                      : "(no name)";

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.bluetooth_audio,
                                      color: Colors.white,
                                    ),
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isSmall ? 14 : 16,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      "${r.device.remoteId.str}\nRSSI ${r.rssi}",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: isSmall ? 11 : 12,
                                      ),
                                    ),
                                    isThreeLine: true,
                                    trailing: _isConnected &&
                                            _device?.remoteId.str ==
                                                r.device.remoteId.str
                                        ? const Icon(
                                            Icons.check_circle,
                                            color: Colors.lightGreenAccent,
                                          )
                                        : const Icon(
                                            Icons.chevron_right,
                                            color: Colors.white70,
                                          ),
                                    onTap: _isConnected ? null : () => _connect(r),
                                  );
                                },
                              ),
                      ),
                      if (_device != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          "Connected: ${_device!.advName.isNotEmpty ? _device!.advName : _device!.remoteId.str}",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmall ? 12 : 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_lastMsg.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          "Last message: $_lastMsg",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: isSmall ? 10 : 11,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}