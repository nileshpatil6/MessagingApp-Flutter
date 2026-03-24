import 'package:flutter/material.dart';
import '../core/local_storage.dart';

class SelfDestructScreen extends StatefulWidget {
  const SelfDestructScreen({super.key});

  @override
  State<SelfDestructScreen> createState() => _SelfDestructScreenState();
}

class _SelfDestructScreenState extends State<SelfDestructScreen> {
  String? _currentValue;
  bool _isLoading = true;

  // Custom hour / custom date inputs
  final _customHourController = TextEditingController();
  DateTime? _customDate;

  static const _presets = [
    _Preset(label: 'Off', value: 'off', icon: Icons.timer_off_outlined),
    _Preset(label: '5 seconds', value: '5s', icon: Icons.timer),
    _Preset(label: '30 seconds', value: '30s', icon: Icons.timer),
    _Preset(label: '1 minute', value: '1m', icon: Icons.timer),
    _Preset(label: '5 minutes', value: '5m', icon: Icons.timer),
    _Preset(label: '30 minutes', value: '30m', icon: Icons.timer),
    _Preset(label: '1 hour', value: '1h', icon: Icons.access_time),
    _Preset(label: '1 day', value: '1d', icon: Icons.calendar_today_outlined),
    _Preset(label: '1 week', value: '7d', icon: Icons.date_range_outlined),
    _Preset(
        label: '1 month',
        value: '30d',
        icon: Icons.calendar_month_outlined),
  ];

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
        const SnackBar(content: Text('Enter a valid number of hours')),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Self-Destruct Timer'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Messages will automatically be deleted after this time for both sides.',
                    style: TextStyle(color: colorScheme.outline, fontSize: 14),
                  ),
                ),
                const Divider(height: 1),
                // Preset options
                ..._presets.map((preset) => RadioListTile<String>(
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
                          decoration: const InputDecoration(
                            labelText: 'Custom (hours)',
                            hintText: 'e.g. 48',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saveCustomHours,
                        child: const Text('Set'),
                      ),
                    ],
                  ),
                ),
                // Custom date
                ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Custom date & time'),
                  subtitle: _customDate != null
                      ? Text(_customDate!.toLocal().toString())
                      : const Text('Pick a specific date and time'),
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
                            'Currently set: $_currentValue',
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
