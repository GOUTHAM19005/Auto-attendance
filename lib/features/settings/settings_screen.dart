import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/pdf_helper.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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

          // Default shift times
          TimeOfDay shiftIn = const TimeOfDay(hour: 9, minute: 0);
          TimeOfDay shiftOut = const TimeOfDay(hour: 16, minute: 0);

          if (snapshot.hasData && snapshot.data!.exists) {
            var data = snapshot.data!.data() as Map<String, dynamic>;
            name = data['name'] ?? name;
            dept = data['department'] ?? dept;

            // Load saved shift times if available
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
                child: Divider(),
              ),
              _shiftSection(context, user?.uid, shiftIn, shiftOut),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(),
              ),
              _themeSection(themeController),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(),
              ),
              _reportSection(context),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(),
              ),
              _logoutSection(),
            ],
          );
        },
      ),
    );
  }

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

  // ── Shift Timings Section ─────────────────────────────────────────────────
  Widget _shiftSection(BuildContext context, String? uid, TimeOfDay shiftIn,
      TimeOfDay shiftOut) {
    String _fmt(TimeOfDay t) {
      final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      final m = t.minute.toString().padLeft(2, '0');
      final period = t.period == DayPeriod.am ? 'AM' : 'PM';
      return '$h:$m $period';
    }

    return ExpansionTile(
      leading: const Icon(Icons.access_time, color: Colors.indigo),
      title: const Text("Shift Timings"),
      subtitle: Text(
        '${_fmt(shiftIn)} → ${_fmt(shiftOut)}',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      children: [
        // Punch In Time
        ListTile(
          leading: const Icon(Icons.login, color: Colors.green),
          title: const Text('Punch In Time'),
          subtitle: Text(
            _fmt(shiftIn),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Punch In time updated to ${_fmt(picked)}'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
        ),

        // Punch Out Time
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text('Punch Out Time'),
          subtitle: Text(
            _fmt(shiftOut),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Punch Out time updated to ${_fmt(picked)}'),
                  backgroundColor: Colors.indigo,
                ),
              );
            }
          },
        ),

        // Info note
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'ℹ️ Grace time is calculated based on your shift end time. '
            'Full day requires ${_fmtMins()} mins of work.',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  String _fmtMins() => '420'; // 7 hours

  Widget _themeSection(ThemeController controller) {
    return ExpansionTile(
      leading: const Icon(Icons.palette, color: Colors.indigo),
      title: const Text("App Appearance"),
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

  Widget _reportSection(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
      title: const Text('Generate Attendance Report'),
      subtitle: const Text('Offline PDF Export'),
      trailing: const Icon(Icons.download, color: Colors.grey),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Generating PDF from local database..."),
            duration: Duration(seconds: 2),
          ),
        );

        try {
          await PdfExportService.generateAttendancePdf();
        } catch (e) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text("Export failed: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  Widget _logoutSection() {
    return ListTile(
      leading: const Icon(Icons.exit_to_app, color: Colors.red),
      title: const Text('Sign Out',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      onTap: () => FirebaseAuth.instance.signOut(),
    );
  }
}