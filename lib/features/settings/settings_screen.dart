import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/pdf_helper.dart';
import '../../core/services/dropbox_backup_service.dart';
import '../dropbox/dropbox_login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DropboxBackupService _dropbox = DropboxBackupService();

  bool _autoBackupEnabled = false;
  bool _isConnected = false;
  bool _isUploading = false;
  String? _connectedEmail;

  @override
  void initState() {
    super.initState();
    _loadDropboxState();
  }

  Future<void> _loadDropboxState() async {
    final connected = await _dropbox.isConnected();
    final enabled = await _dropbox.isAutoBackupEnabled();
    final email = await _dropbox.getConnectedEmail();
    if (mounted) {
      setState(() {
        _isConnected = connected;
        _autoBackupEnabled = enabled;
        _connectedEmail = email;
      });
    }
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          String name = "Faculty Member";
          String dept = "Department";
          TimeOfDay shiftIn = const TimeOfDay(hour: 9, minute: 0);
          TimeOfDay shiftOut = const TimeOfDay(hour: 16, minute: 0);

          if (snapshot.hasData && snapshot.data!.exists) {
            var data = snapshot.data!.data() as Map<String, dynamic>;
            name = data['name'] ?? name;
            dept = data['department'] ?? dept;

            if (data['shift_in'] != null) {
              final parts = (data['shift_in'] as String).split(':');
              shiftIn = TimeOfDay(
                  hour: int.parse(parts[0]), minute: int.parse(parts[1]));
            }
            if (data['shift_out'] != null) {
              final parts = (data['shift_out'] as String).split(':');
              shiftOut = TimeOfDay(
                  hour: int.parse(parts[0]), minute: int.parse(parts[1]));
            }
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              _profileSection(name, dept),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider()),
              _shiftSection(context, user?.uid, shiftIn, shiftOut),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider()),
              _dropboxSection(context),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider()),
              _themeSection(themeController),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider()),
              _reportSection(context),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider()),
              _logoutSection(),
            ],
          );
        },
      ),
    );
  }

  // ── Profile ───────────────────────────────────────────────────────────────
  Widget _profileSection(String name, String dept) {
    return Column(
      children: [
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.indigo,
            child: Icon(Icons.person, color: Colors.white),
          ),
          title: const Text('Faculty Name',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          subtitle: Text(name,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
        ),
        ListTile(
          leading: const Icon(Icons.business, color: Colors.indigo),
          title: const Text('Department',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          subtitle: Text(dept,
              style: const TextStyle(fontSize: 16, color: Colors.black87)),
        ),
      ],
    );
  }

  // ── Shift Timings ─────────────────────────────────────────────────────────
  Widget _shiftSection(BuildContext context, String? uid,
      TimeOfDay shiftIn, TimeOfDay shiftOut) {
    return ExpansionTile(
      leading: const Icon(Icons.access_time, color: Colors.indigo),
      title: const Text('Shift Timings'),
      subtitle: Text(
        '${_fmtTime(shiftIn)} → ${_fmtTime(shiftOut)}',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      children: [
        ListTile(
          leading: const Icon(Icons.login, color: Colors.green),
          title: const Text('Punch In Time'),
          subtitle: Text(_fmtTime(shiftIn),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          trailing: const Icon(Icons.edit, size: 18, color: Colors.grey),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: shiftIn,
              helpText: 'Select Shift Start Time',
            );
            if (picked != null && uid != null) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .update({
                'shift_in':
                    '${picked.hour}:${picked.minute.toString().padLeft(2, '0')}',
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('Punch In time updated to ${_fmtTime(picked)}'),
                  backgroundColor: Colors.green,
                ));
              }
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text('Punch Out Time'),
          subtitle: Text(_fmtTime(shiftOut),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          trailing: const Icon(Icons.edit, size: 18, color: Colors.grey),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: shiftOut,
              helpText: 'Select Shift End Time',
            );
            if (picked != null && uid != null) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .update({
                'shift_out':
                    '${picked.hour}:${picked.minute.toString().padLeft(2, '0')}',
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('Punch Out time updated to ${_fmtTime(picked)}'),
                  backgroundColor: Colors.indigo,
                ));
              }
            }
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'ℹ️ Grace time is calculated based on your shift timings.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  // ── Dropbox Backup ────────────────────────────────────────────────────────
  Widget _dropboxSection(BuildContext context) {
    return ExpansionTile(
      leading: Icon(
        Icons.backup,
        color: _isConnected ? Colors.green : Colors.indigo,
      ),
      title: const Text('Dropbox Backup'),
      subtitle: Text(
        _isConnected
            ? (_connectedEmail != null
                ? 'Connected: $_connectedEmail'
                : 'Connected to Dropbox')
            : 'Not connected',
        style: TextStyle(
          fontSize: 12,
          color: _isConnected ? Colors.green : Colors.grey,
        ),
      ),
      children: [
        // Connect / Disconnect
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: _isConnected
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.link_off, color: Colors.red),
                    label: const Text('Disconnect Dropbox',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _doDisconnect(context),
                  )
                : ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_queue),
                    label: const Text('Connect Dropbox'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _doConnect(context),
                  ),
          ),
        ),

        // Auto backup toggle
        if (_isConnected) ...[
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync, color: Colors.indigo),
            title: const Text('Auto Backup'),
            subtitle: const Text(
                'Automatically upload to Dropbox after every punch'),
            value: _autoBackupEnabled,
            activeColor: Colors.indigo,
            onChanged: (val) async {
              await _dropbox.setAutoBackup(val);
              setState(() => _autoBackupEnabled = val);
            },
          ),

          // Backup by month
          ListTile(
            leading: const Icon(Icons.upload_file, color: Colors.teal),
            title: const Text('Backup Monthly Report'),
            subtitle: const Text('Upload a month\'s attendance as PDF to Dropbox'),
            trailing: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf, color: Colors.red),
            onTap: _isUploading ? null : () => _doBackupMonth(context),
          ),

          // Backup all months
          ListTile(
            leading: const Icon(Icons.cloud_upload, color: Colors.indigo),
            title: const Text('Backup All Months'),
            subtitle: const Text('Upload every month as a separate PDF'),
            trailing: const Icon(Icons.upload, color: Colors.grey),
            onTap: _isUploading ? null : () => _doBackupAll(context),
          ),
        ],

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'ℹ️ Each punch is saved as a CSV in your Dropbox under '
            '/attendance_backup/{your_id}/{date}.csv',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Future<void> _doConnect(BuildContext context) async {
    // Open in-app WebView login screen
    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const DropboxLoginScreen()),
    );

    if (success == true) {
      await _loadDropboxState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connected to Dropbox successfully!'),
          backgroundColor: Colors.green,
        ));
      }
    }
  }

  Future<void> _doDisconnect(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Dropbox'),
        content: const Text(
            'This will stop auto-backup. Your existing files in Dropbox will not be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Disconnect',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );

    if (confirm != true) return;

    await _dropbox.disconnect();
    if (mounted) {
      await _loadDropboxState();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Dropbox disconnected'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  Future<void> _doBackupMonth(BuildContext context) async {
    final now = DateTime.now();
    // Show month/year picker dialog
    int selectedYear = now.year;
    int selectedMonth = now.month;

    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    final picked = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Select Month'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Year selector
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () =>
                        setDlgState(() => selectedYear--),
                  ),
                  Text('$selectedYear',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () =>
                        setDlgState(() => selectedYear++),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Month grid
              GridView.builder(
                shrinkWrap: true,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: 12,
                itemBuilder: (_, i) {
                  final isSelected = selectedMonth == i + 1;
                  return GestureDetector(
                    onTap: () =>
                        setDlgState(() => selectedMonth = i + 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.indigo
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        months[i].substring(0, 3),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, {'year': selectedYear, 'month': selectedMonth}),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo),
              child: const Text('Upload PDF',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (picked == null) return;

    setState(() => _isUploading = true);
    final result = await _dropbox.backupMonth(
      year: picked['year']!,
      month: picked['month']!,
    );
    if (mounted) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.success
            ? result.message ?? 'Upload complete'
            : 'Upload failed: ${result.error}'),
        backgroundColor: result.success ? Colors.teal : Colors.red,
      ));
    }
  }

  Future<void> _doBackupAll(BuildContext context) async {
    setState(() => _isUploading = true);
    final result = await _dropbox.backupAll();
    if (mounted) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.success
            ? result.message ?? 'Backup complete'
            : 'Backup failed: ${result.error}'),
        backgroundColor: result.success ? Colors.teal : Colors.red,
      ));
    }
  }

  // ── Theme ─────────────────────────────────────────────────────────────────
  Widget _themeSection(ThemeController controller) {
    return ExpansionTile(
      leading: const Icon(Icons.palette, color: Colors.indigo),
      title: const Text('App Appearance'),
      children: [
        RadioListTile<ThemeMode>(
          title: const Text('Light Mode'),
          value: ThemeMode.light,
          groupValue: controller.themeMode,
          onChanged: (_) => controller.setLightMode(),
        ),
        RadioListTile<ThemeMode>(
          title: const Text('Dark Mode'),
          value: ThemeMode.dark,
          groupValue: controller.themeMode,
          onChanged: (_) => controller.setDarkMode(),
        ),
      ],
    );
  }

  // ── Report ────────────────────────────────────────────────────────────────
  Widget _reportSection(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
      title: const Text('Generate Attendance Report'),
      subtitle: const Text('Offline PDF Export'),
      trailing: const Icon(Icons.download, color: Colors.grey),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(const SnackBar(
          content: Text('Generating PDF from local database...'),
          duration: Duration(seconds: 2),
        ));
        try {
          await PdfExportService.generateAttendancePdf();
        } catch (e) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ));
        }
      },
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Widget _logoutSection() {
    return ListTile(
      leading: const Icon(Icons.exit_to_app, color: Colors.red),
      title: const Text('Sign Out',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      onTap: () => FirebaseAuth.instance.signOut(),
    );
  }
}