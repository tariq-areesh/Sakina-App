// fl_training_page.dart
//
// FL TRAINING PAGE
// ================
// Shows the user:
//   - How many training samples have been collected (with class breakdown)
//   - Window accumulation progress (toward the next 60-sample window)
//   - Controls to run local training (epochs / learning rate)
//   - Last training result (loss, accuracy, FL round)
//   - FL server panel: pull global model, push local weights
//
// Add "package:http/http.dart" to pubspec.yaml:
//   dependencies:
//     http: ^1.2.1

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'fl_local_trainer.dart';

class FLTrainingPage extends StatefulWidget {
  final FLLocalTrainer trainer;

  const FLTrainingPage({super.key, required this.trainer});

  @override
  State<FLTrainingPage> createState() => _FLTrainingPageState();
}

class _FLTrainingPageState extends State<FLTrainingPage> {
  // ── Training hyper-params ──────────────────────────────────
  int _epochs = 3;
  double _learningRate = 0.01;
  int _batchSize = 16;

  // ── State ─────────────────────────────────────────────────
  bool _isTraining  = false;
  bool _isPulling   = false;
  bool _isPushing   = false;
  TrainingResult? _lastResult;
  String? _statusMsg;

  // ── FL Server ─────────────────────────────────────────────
  final _serverUrlCtrl = TextEditingController(text: 'http://192.168.1.100:8080');

  FLLocalTrainer get _t => widget.trainer;

  @override
  void initState() {
    super.initState();
    // Trigger a rebuild whenever a new sample is captured
    _t.onSampleAdded = (_) {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _t.onSampleAdded = null;
    _serverUrlCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> _runTraining() async {
    if (_isTraining || !_t.hasEnoughData) return;
    setState(() { _isTraining = true; _statusMsg = null; });

    try {
      final result = await _t.trainLocal(
        epochs: _epochs,
        learningRate: _learningRate,
        batchSize: _batchSize,
      );
      if (!mounted) return;
      setState(() { _lastResult = result; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _statusMsg = 'Training failed: $e'; });
    } finally {
      if (mounted) setState(() => _isTraining = false);
    }
  }

  /// GET /api/global_model  → { "round": N, "layers": [...] }
  Future<void> _pullGlobalModel() async {
    setState(() { _isPulling = true; _statusMsg = null; });

    try {
      final uri = Uri.parse('${_serverUrlCtrl.text.trimRight()}/api/global_model');
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        _t.importWeights(json);
        if (mounted) {
          setState(() {
            _statusMsg = 'Global model received (round ${json['round'] ?? '?'})';
          });
        }
      } else {
        if (mounted) setState(() => _statusMsg = 'Server error ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _statusMsg = 'Pull failed: $e');
    } finally {
      if (mounted) setState(() => _isPulling = false);
    }
  }

  /// POST /api/local_update  body: { "round": N, "layers": [...], ... }
  Future<void> _pushLocalWeights() async {
    setState(() { _isPushing = true; _statusMsg = null; });

    try {
      final uri = Uri.parse('${_serverUrlCtrl.text.trimRight()}/api/local_update');
      final body = jsonEncode(_t.exportWeights());
      final resp = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: body)
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        if (mounted) setState(() => _statusMsg = 'Local weights sent to server ✓');
      } else {
        if (mounted) setState(() => _statusMsg = 'Server error ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _statusMsg = 'Push failed: $e');
    } finally {
      if (mounted) setState(() => _isPushing = false);
    }
  }

  Future<void> _clearDataset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear training data?'),
        content: const Text('All collected samples will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _t.clearDataset();
      if (mounted) setState(() { _lastResult = null; _statusMsg = 'Dataset cleared'; });
    }
  }

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 360;
        final hp = isSmall ? 10.0 : 14.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hp, 10, hp, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              _sectionTitle('FL Local Training', isSmall),
              const SizedBox(height: 12),

              // ── Data status card ────────────────────────
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardHeader(
                      Icons.storage_outlined,
                      'Collected training data',
                      isSmall,
                    ),
                    const SizedBox(height: 14),

                    // Window progress bar
                    _WindowProgressBar(
                      current: _t.windowProgress,
                      total: FLLocalTrainer.windowSize,
                    ),
                    const SizedBox(height: 16),

                    // Sample counts
                    Row(children: [
                      _statPill('Total', '${_t.sampleCount}',
                          const Color(0xFFC8602A)),
                      const SizedBox(width: 8),
                      _statPill('Normal',  '${_t.normalCount}',
                          const Color(0xFF2E7D32)),
                      const SizedBox(width: 8),
                      _statPill('Stressed', '${_t.stressedCount}',
                          const Color(0xFFC62828)),
                    ]),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'FL round: ${_t.flRound}',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: isSmall ? 12 : 13,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _t.sampleCount == 0 ? null : _clearDataset,
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: Colors.white54),
                          label: const Text('Clear data',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),

                    if (_t.sampleCount < FLLocalTrainer.minTrainSamples)
                      Text(
                        'Need ${FLLocalTrainer.minTrainSamples - _t.sampleCount} '
                        'more samples before training. '
                        'Connect the ESP32 to collect data.',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: isSmall ? 11 : 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Hyper-parameters card ───────────────────
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardHeader(Icons.tune_outlined, 'Training settings', isSmall),
                    const SizedBox(height: 14),
                    _sliderRow(
                      label: 'Epochs',
                      value: _epochs.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      display: '$_epochs',
                      onChanged: (v) => setState(() => _epochs = v.round()),
                    ),
                    const SizedBox(height: 8),
                    _sliderRow(
                      label: 'Learning rate',
                      value: _learningRate,
                      min: 0.001,
                      max: 0.1,
                      divisions: 9,
                      display: _learningRate.toStringAsFixed(3),
                      onChanged: (v) => setState(() =>
                          _learningRate = double.parse(v.toStringAsFixed(3))),
                    ),
                    const SizedBox(height: 8),
                    _sliderRow(
                      label: 'Batch size',
                      value: _batchSize.toDouble(),
                      min: 4,
                      max: 32,
                      divisions: 7,
                      display: '$_batchSize',
                      onChanged: (v) => setState(() => _batchSize = v.round()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Train button ────────────────────────────
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (!_t.hasEnoughData || _isTraining) ? null : _runTraining,
                  icon: _isTraining
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.model_training_outlined),
                  label: Text(_isTraining ? 'Training…' : 'Run local training'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B3A1E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white38,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: TextStyle(
                        fontSize: isSmall ? 14 : 16,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),

              // ── Last training result ────────────────────
              if (_lastResult != null) ...[
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardHeader(Icons.bar_chart_outlined,
                          'Last training result', isSmall),
                      const SizedBox(height: 14),
                      Row(children: [
                        _statPill('Accuracy',
                            '${(_lastResult!.accuracy * 100).toStringAsFixed(1)}%',
                            const Color(0xFF1565C0)),
                        const SizedBox(width: 8),
                        _statPill('Loss',
                            _lastResult!.finalLoss.toStringAsFixed(4),
                            const Color(0xFF6A1B9A)),
                        const SizedBox(width: 8),
                        _statPill('Round',
                            '${_lastResult!.flRound}',
                            const Color(0xFFC8602A)),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        'Trained on ${_lastResult!.samplesUsed} samples '
                        'for ${_lastResult!.epochs} epochs.',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: isSmall ? 11 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // ── FL Server card ──────────────────────────
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardHeader(Icons.cloud_sync_outlined,
                        'Flower FL server', isSmall),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _serverUrlCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Server base URL',
                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                        hintText: 'http://192.168.1.100:8080',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF6A2E14),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        suffixText: '/api/…',
                        suffixStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: _serverBtn(
                          label: 'Pull global model',
                          icon: Icons.download_outlined,
                          loading: _isPulling,
                          onPressed: _pullGlobalModel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _serverBtn(
                          label: 'Push local weights',
                          icon: Icons.upload_outlined,
                          loading: _isPushing,
                          onPressed: _lastResult == null ? null : _pushLocalWeights,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      'Endpoints used:\n'
                      '  GET  /api/global_model\n'
                      '  POST /api/local_update',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: isSmall ? 10 : 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              // ── Status message ──────────────────────────
              if (_statusMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A1A08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF7B3A1E), width: 1.2),
                  ),
                  child: Text(
                    _statusMsg!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isSmall ? 12 : 13,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 80), // nav bar clearance
            ],
          ),
        );
      },
    );
  }

  // ── Helper widgets ─────────────────────────────────────────

  Widget _sectionTitle(String text, bool isSmall) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      color: Colors.white,
      fontSize: isSmall ? 19 : 21,
      fontWeight: FontWeight.w500,
    ),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF4A1A08), width: 1.5),
    ),
    child: child,
  );

  Widget _cardHeader(IconData icon, String label, bool isSmall) => Row(
    children: [
      Icon(icon, color: Colors.white70, size: isSmall ? 18 : 20),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(
            color: Colors.white,
            fontSize: isSmall ? 14 : 16,
            fontWeight: FontWeight.w500,
          )),
    ],
  );

  Widget _statPill(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.25),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.5)),
    ),
    child: Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    ),
  );

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) =>
      Row(children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              activeTrackColor: const Color(0xFFC8602A),
              inactiveTrackColor: Colors.white24,
              thumbColor: const Color(0xFFC8602A),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(display,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ]);

  Widget _serverBtn({
    required String label,
    required IconData icon,
    required bool loading,
    required VoidCallback? onPressed,
  }) =>
      ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5A2510),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white10,
          disabledForegroundColor: Colors.white30,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}

// ── Window progress bar ─────────────────────────────────────

class _WindowProgressBar extends StatelessWidget {
  final int current;
  final int total;

  const _WindowProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = (current / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Window accumulation',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text('$current / $total samples',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.white12,
            color: pct >= 1.0
                ? const Color(0xFF43A047) // green when full
                : const Color(0xFFC8602A),
            minHeight: 8,
          ),
        ),
        if (pct >= 1.0) ...[
          const SizedBox(height: 4),
          const Text('Window full — capturing training samples',
              style: TextStyle(color: Color(0xFF81C784), fontSize: 11)),
        ],
      ],
    );
  }
}
