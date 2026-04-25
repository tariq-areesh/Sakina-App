// homePage.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class HomePage extends StatefulWidget {
  final BluetoothDevice? device;
  final bool isDeviceConnected;
  final String latestBleMessage;
  final VoidCallback? onOpenStressHistory;

  const HomePage({
    super.key,
    this.device,
    required this.isDeviceConnected,
    required this.latestBleMessage,
    this.onOpenStressHistory,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String stressStatus = "--";
  String medicalAdvice = "Connect ESP32 to view live data.";
  String skinTemp = "--";
  String heartRate = "--";

  @override
  void initState() {
    super.initState();
    _syncFromBleState();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isDeviceConnected != widget.isDeviceConnected ||
        oldWidget.latestBleMessage != widget.latestBleMessage) {
      _syncFromBleState();
    }
  }

  void _syncFromBleState() {
    if (!widget.isDeviceConnected || widget.latestBleMessage.trim().isEmpty) {
      setState(() {
        stressStatus = "--";
        medicalAdvice = "Connect ESP32 to view live data.";
        skinTemp = "--";
        heartRate = "--";
      });
      return;
    }

    _parseEsp32Message(widget.latestBleMessage);
  }

  void _parseEsp32Message(String msg) {
    try {
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

      setState(() {
        stressStatus =
            data.containsKey('stress') && data['stress']!.isNotEmpty
                ? data['stress']!
                : "--";

        skinTemp =
            data.containsKey('temp') && data['temp']!.isNotEmpty
                ? "${data['temp']}°C"
                : "--";

        heartRate =
            data.containsKey('hr') && data['hr']!.isNotEmpty
                ? "${data['hr']} bpm"
                : "--";

        medicalAdvice =
            data.containsKey('advice') && data['advice']!.isNotEmpty
                ? data['advice']!
                : "Waiting for ESP32 data...";
      });
    } catch (_) {
      setState(() {
        stressStatus = "--";
        medicalAdvice = "Waiting for valid ESP32 data...";
        skinTemp = "--";
        heartRate = "--";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceName =
        widget.isDeviceConnected &&
                widget.device != null &&
                widget.device!.advName.isNotEmpty
            ? widget.device!.advName
            : "No device connected";

    return _HomePageContent(
      deviceName: deviceName,
      stressStatus: stressStatus,
      medicalAdvice: medicalAdvice,
      skinTemp: skinTemp,
      heartRate: heartRate,
      lastMessage: widget.isDeviceConnected ? widget.latestBleMessage : "",
      isDeviceConnected: widget.isDeviceConnected,
      onOpenStressHistory: widget.onOpenStressHistory,
    );
  }
}

class _HomePageContent extends StatelessWidget {
  final String deviceName;
  final String stressStatus;
  final String medicalAdvice;
  final String skinTemp;
  final String heartRate;
  final String lastMessage;
  final bool isDeviceConnected;
  final VoidCallback? onOpenStressHistory;

  const _HomePageContent({
    required this.deviceName,
    required this.stressStatus,
    required this.medicalAdvice,
    required this.skinTemp,
    required this.heartRate,
    required this.lastMessage,
    required this.isDeviceConnected,
    this.onOpenStressHistory,
  });

  @override
  Widget build(BuildContext context) {
    const lightCard = Color(0xFFFDF0E4); // warm cream for stress status value box

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isSmall = width < 360;
        final horizontalPadding = isSmall ? 10.0 : 14.0;
        final gap = isSmall ? 10.0 : 12.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            10,
            horizontalPadding,
            16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 26,
            ),
            child: Column(
              children: [
                _roundedCard(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmall ? 12 : 18,
                    vertical: isSmall ? 14 : 16,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isDeviceConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Device Name: $deviceName",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmall ? 15 : 17,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                _roundedCard(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: isSmall ? 10 : 12,
                          horizontal: 12,
                        ),
                        child: Text(
                          "Stress Status",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmall ? 18 : 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: const Color(0xFF4A1A08),
                      ),
                      Padding(
                        padding: EdgeInsets.all(isSmall ? 12 : 16),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmall ? 14 : 18,
                                vertical: isSmall ? 14 : 16,
                              ),
                              decoration: BoxDecoration(
                                color: lightCard,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                stressStatus,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFF4A1A08),
                                  fontSize: isSmall ? 16 : 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SizedBox(height: isSmall ? 12 : 14),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: onOpenStressHistory,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 4,
                                      children: [
                                        Text(
                                          "Check Stress History",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: isSmall ? 11 : 12,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: Colors.white,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                _roundedCard(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmall ? 12 : 14,
                    vertical: isSmall ? 12 : 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.medical_information_outlined,
                            color: Colors.white,
                            size: isSmall ? 18 : 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Advice",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSmall ? 15 : 16,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isSmall ? 14 : 18),
                      Text(
                        medicalAdvice,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmall ? 15 : 17,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                Row(
                  children: [
                    Expanded(
                      child: _metricCard(
                        title: "Current\nSkin Temperature",
                        value: skinTemp,
                        icon: Icons.device_thermostat_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricCard(
                        title: "Current\nHeart Rate",
                        value: heartRate,
                        icon: Icons.favorite_outline,
                      ),
                    ),
                  ],
                ),
                if (lastMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    "BLE: $lastMessage",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: isSmall ? 10 : 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _roundedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _roundedCard({
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF4A1A08), width: 1.5),
      ),
      child: child,
    );
  }
}

class _metricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _metricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isSmall = width < 360;

    return Container(
      height: isSmall ? 150 : 165,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF4A1A08), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 8 : 12,
          vertical: isSmall ? 10 : 14,
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white60, size: isSmall ? 20 : 24),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmall ? 11 : 13,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmall ? 18 : 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}