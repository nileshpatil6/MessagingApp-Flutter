import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/local_storage.dart';
import '../l10n/app_strings.dart';
import '../providers/locale_provider.dart';

class SelfDestructScreen extends ConsumerStatefulWidget {
  const SelfDestructScreen({super.key});

  @override
  ConsumerState<SelfDestructScreen> createState() => _SelfDestructScreenState();
}

class _SelfDestructScreenState extends ConsumerState<SelfDestructScreen> {
  AppStrings get _s => AppStrings(ref.read(localeProvider));

  String? _currentValue;
  bool _isLoading = true;

  // Custom hour / custom date inputs
  final _customHourController = TextEditingController();
  DateTime? _customDate;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final prefs = await LocalStorage.getSelfDestruct();
    if (mounted) {
      setState(() {
        _currentValue = prefs?['dead_time'] ?? 'off';
        _isLoading = false;
      });
    }
  }

  Future<void> _save(String value) async {
    await LocalStorage.saveSelfDestruct({'dead_time': value});
    if (mounted) Navigator.pop(context, value);
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    final dateTime = DateTime(
        picked.year, picked.month, picked.day, time.hour, time.minute);
    _customDate = dateTime;
    await _save(dateTime.toIso8601String());
  }

  Future<void> _saveCustomHours() async {
    final hours = int.tryParse(_customHourController.text.trim());
    if (hours == null || hours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.enterValidHours)),
      );
      return;
    }
    await _save('${hours}h');
  }

  @override
  void dispose() {
    _customHourController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final s = _s;
    final colorScheme = Theme.of(context).colorScheme;

    final presets = [
      _Preset(label: s.off, value: 'off', icon: Icons.timer_off_outlined),
      _Preset(label: s.fiveSeconds, value: '5s', icon: Icons.timer),
      _Preset(label: s.thirtySeconds, value: '30s', icon: Icons.timer),
      _Preset(label: s.oneMinute, value: '1m', icon: Icons.timer),
      _Preset(label: s.fiveMinutes, value: '5m', icon: Icons.timer),
      _Preset(label: s.thirtyMinutes, value: '30m', icon: Icons.timer),
      _Preset(label: s.oneHour, value: '1h', icon: Icons.access_time),
      _Preset(label: s.oneDay, value: '1d', icon: Icons.calendar_today_outlined),
      _Preset(label: s.oneWeek, value: '7d', icon: Icons.date_range_outlined),
      _Preset(label: s.oneMonth, value: '30d', icon: Icons.calendar_month_outlined),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(s.selfDestructTimerTitle),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    s.selfDestructDescription,
                    style: TextStyle(color: colorScheme.outline, fontSize: 14),
                  ),
                ),
                const Divider(height: 1),
                // Preset options
                ...presets.map((preset) => RadioListTile<String>(
                      value: preset.value,
                      groupValue: _currentValue,
                      title: Text(preset.label),
                      secondary: Icon(preset.icon),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _currentValue = val);
                          _save(val);
                        }
                      },
                    )),
                const Divider(),
                // Custom hours
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_empty),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _customHourController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: s.customHours,
                            hintText: s.customHoursHint,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saveCustomHours,
                        child: Text(s.set),
                      ),
                    ],
                  ),
                ),
                // Custom date
                ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(s.customDateTime),
                  subtitle: _customDate != null
                      ? Text(_customDate!.toLocal().toString())
                      : Text(s.pickDateTime),
                  onTap: _pickCustomDate,
                  trailing: const Icon(Icons.chevron_right),
                ),
                const SizedBox(height: 32),
                // Current selection indicator
                if (_currentValue != null && _currentValue != 'off')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer,
                              color: colorScheme.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Text(
                            s.currentlySet(_currentValue!),
                            style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _Preset {
  final String label;
  final String value;
  final IconData icon;

  const _Preset(
      {required this.label, required this.value, required this.icon});
}
