import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StressHistoryPage extends StatefulWidget {
  final int historyVersion;

  const StressHistoryPage({
    super.key,
    required this.historyVersion,
  });

  @override
  State<StressHistoryPage> createState() => _StressHistoryPageState();
}

class _StressHistoryPageState extends State<StressHistoryPage> {
  static const String _historyStorageKey = 'stress_history_items';

  final TextEditingController _searchController = TextEditingController();

  List<StressHistoryItem> _allItems = [];

  String _selectedTimeUnit = "Second";
  String _selectedStatus = "Both";
  String _searchText = "";
  bool _isLoading = true;

  List<StressHistoryItem> get _filteredItems {
    return _allItems.where((item) {
      final matchesSearch =
          _searchText.isEmpty ||
          item.formattedTimestamp.toLowerCase().contains(_searchText.toLowerCase()) ||
          item.status.toLowerCase().contains(_searchText.toLowerCase()) ||
          item.score.toLowerCase().contains(_searchText.toLowerCase()) ||
          item.hr.toLowerCase().contains(_searchText.toLowerCase()) ||
          item.temp.toLowerCase().contains(_searchText.toLowerCase());

      final matchesStatus =
          _selectedStatus == "Both" || item.status == _selectedStatus;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant StressHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.historyVersion != widget.historyVersion) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_historyStorageKey) ?? [];

    final items = <StressHistoryItem>[];

    for (final raw in stored) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final timestampString = (map['timestamp'] ?? '').toString();
        final timestamp = DateTime.tryParse(timestampString);

        if (timestamp == null) continue;

        items.add(
          StressHistoryItem(
            status: (map['status'] ?? '--').toString(),
            timestamp: timestamp,
            score: (map['score'] ?? '--').toString(),
            hr: (map['hr'] ?? '--').toString(),
            temp: (map['temp'] ?? '--').toString(),
          ),
        );
      } catch (_) {
        // skip malformed records
      }
    }

    if (!mounted) return;

    setState(() {
      _allItems = items;
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyStorageKey);

    if (!mounted) return;

    setState(() {
      _allItems = [];
    });
  }

  void _openFilterDialog() {
    String tempTimeUnit = _selectedTimeUnit;
    String tempStatus = _selectedStatus;

    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white, // burnt orange matching poster
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: StatefulBuilder(
                builder: (context, setLocalState) {
                  Widget filterOption({
                    required String label,
                    required bool selected,
                    required VoidCallback onTap,
                  }) {
                    return GestureDetector(
                      onTap: onTap,
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 38),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFA85530)
                              : const Color(0xFF4A1A08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white60,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 320;

                            if (stacked) {
                              return Column(
                                children: [
                                  _FilterSection(
                                    title: "View Data By:",
                                    children: [
                                      filterOption(
                                        label: "MiliSeconds",
                                        selected: tempTimeUnit == "MiliSeconds",
                                        onTap: () => setLocalState(() {
                                          tempTimeUnit = "MiliSeconds";
                                        }),
                                      ),
                                      filterOption(
                                        label: "Second",
                                        selected: tempTimeUnit == "Second",
                                        onTap: () => setLocalState(() {
                                          tempTimeUnit = "Second";
                                        }),
                                      ),
                                      filterOption(
                                        label: "Hours",
                                        selected: tempTimeUnit == "Hours",
                                        onTap: () => setLocalState(() {
                                          tempTimeUnit = "Hours";
                                        }),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _FilterSection(
                                    title: "Viewed Status",
                                    children: [
                                      filterOption(
                                        label: "Normal",
                                        selected: tempStatus == "Normal",
                                        onTap: () => setLocalState(() {
                                          tempStatus = "Normal";
                                        }),
                                      ),
                                      filterOption(
                                        label: "Stressed",
                                        selected: tempStatus == "Stressed",
                                        onTap: () => setLocalState(() {
                                          tempStatus = "Stressed";
                                        }),
                                      ),
                                      filterOption(
                                        label: "Both",
                                        selected: tempStatus == "Both",
                                        onTap: () => setLocalState(() {
                                          tempStatus = "Both";
                                        }),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _FilterSection(
                                    title: "View Data By:",
                                    children: [
                                      filterOption(
                                        label: "MiliSeconds",
                                        selected: tempTimeUnit == "MiliSeconds",
                                        onTap: () => setLocalState(() {
                                          tempTimeUnit = "MiliSeconds";
                                        }),
                                      ),
                                      filterOption(
                                        label: "Second",
                                        selected: tempTimeUnit == "Second",
                                        onTap: () => setLocalState(() {
                                          tempTimeUnit = "Second";
                                        }),
                                      ),
                                      filterOption(
                                        label: "Hours",
                                        selected: tempTimeUnit == "Hours",
                                        onTap: () => setLocalState(() {
                                          tempTimeUnit = "Hours";
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _FilterSection(
                                    title: "Viewed Status",
                                    children: [
                                      filterOption(
                                        label: "Normal",
                                        selected: tempStatus == "Normal",
                                        onTap: () => setLocalState(() {
                                          tempStatus = "Normal";
                                        }),
                                      ),
                                      filterOption(
                                        label: "Stressed",
                                        selected: tempStatus == "Stressed",
                                        onTap: () => setLocalState(() {
                                          tempStatus = "Stressed";
                                        }),
                                      ),
                                      filterOption(
                                        label: "Both",
                                        selected: tempStatus == "Both",
                                        onTap: () => setLocalState(() {
                                          tempStatus = "Both";
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: 110,
                          height: 38,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _selectedTimeUnit = tempTimeUnit;
                                _selectedStatus = tempStatus;
                              });
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text("Apply"),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');

    return "$year-$month-$day $hour:$minute:$second";
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 360;

        return Padding(
          padding: EdgeInsets.fromLTRB(isSmall ? 10 : 12, 10, isSmall ? 10 : 12, 10),
          child: Column(
            children: [
              const SizedBox(height: 6),
              Text(
                "Stress History",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmall ? 18 : 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: _openFilterDialog,
                        icon: const Icon(
                          Icons.filter_alt_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        label: const Text(
                          "Filter",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A2E14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: _allItems.isEmpty ? null : _clearHistory,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                        label: const Text(
                          "Clear",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A2E14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                onChanged: (value) {
                  setState(() {
                    _searchText = value.trim();
                  });
                },
                decoration: InputDecoration(
                  hintText: "Search status, score, HR, temp, time",
                  hintStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF6A2E14),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: const Color(0xFFA85530),
                      width: 1.2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.white,
                      width: 1.3,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmall ? 8 : 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        "Status",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmall ? 12 : 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        "Score",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmall ? 12 : 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        "HR",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmall ? 12 : 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        "Temp",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmall ? 12 : 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        "Time Stamp",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmall ? 12 : 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _filteredItems.isEmpty
                        ? const Center(
                            child: Text(
                              "No saved history",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 6),
                            itemCount: _filteredItems.length,
                            separatorBuilder: (_, __) => Container(
                              height: 1,
                              color: const Color(0xFFA85530),
                            ),
                            itemBuilder: (context, index) {
                              final item = _filteredItems[index];
                              return Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isSmall ? 4 : 6,
                                  vertical: 10,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item.status,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isSmall ? 12 : 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item.score,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isSmall ? 12 : 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item.hr,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isSmall ? 12 : 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item.temp,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isSmall ? 12 : 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        _formatTimestamp(item.timestamp),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isSmall ? 12 : 14,
                                        ),
                                        softWrap: true,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FilterSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i != children.length - 1) {
        spaced.add(const SizedBox(height: 12));
      }
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...spaced,
      ],
    );
  }
}

class StressHistoryItem {
  final String status;
  final DateTime timestamp;
  final String score;
  final String hr;
  final String temp;

  StressHistoryItem({
    required this.status,
    required this.timestamp,
    required this.score,
    required this.hr,
    required this.temp,
  });

  String get formattedTimestamp {
    final year = timestamp.year.toString().padLeft(4, '0');
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return "$year-$month-$day $hour:$minute:$second";
  }
}