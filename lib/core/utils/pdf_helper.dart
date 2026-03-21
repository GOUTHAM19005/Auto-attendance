import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../data/database_helper.dart';

class PdfExportService {
  static Future<void> generateAttendancePdf() async {
    final pdf = pw.Document();

    try {
      final List<Map<String, dynamic>> localData =
          await DatabaseHelper.instance.getAllAttendance();

      if (localData.isEmpty) {
        throw Exception("No attendance records found.");
      }

      // Summary counts
      int full = 0, half = 0, absent = 0, leave = 0, totalGrace = 0;
      for (final row in localData) {
        final type = row['attendance_type']?.toString() ?? '';
        if (type == 'FULL') full++;
        else if (type == 'HALF') half++;
        else if (type == 'ABSENT') absent++;
        else if (type == 'LEAVE') leave++;
        totalGrace += (row['used_grace_minutes'] ?? 0) as int;
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Header
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("ATTENDANCE REPORT",
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue800)),
                    pw.Text(
                        "Generated: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}"),
                  ],
                ),
                pw.Divider(thickness: 2, color: PdfColors.blue800),
              ],
            ),

            pw.SizedBox(height: 16),

            // Summary row
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _summaryItem('Full Days', '$full', PdfColors.green800),
                  _summaryItem('Half Days', '$half', PdfColors.orange800),
                  _summaryItem('Absent', '$absent', PdfColors.red800),
                  _summaryItem('Leave', '$leave', PdfColors.blue800),
                  _summaryItem('Grace Used', '${totalGrace}m', PdfColors.purple800),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Attendance Table
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Punch In', 'Punch Out', 'Duration', 'Type', 'Grace'],
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blue800),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
              data: localData.map((row) {
                final punchIn  = _formatTime(row['punch_in']);
                final punchOut = _formatTime(row['punch_out']);
                final duration = row['duration_minutes'] != null
                    ? '${row['duration_minutes']} min'
                    : '-';
                final type = row['attendance_type']?.toString() ?? '-';
                final grace = '${row['used_grace_minutes'] ?? 0} min';

                return [
                  row['date']?.toString() ?? '-',
                  punchIn,
                  punchOut,
                  duration,
                  type,
                  grace,
                ];
              }).toList(),
            ),

            pw.SizedBox(height: 20),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text("Total Records: ${localData.length}",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
          name: 'Attendance_Report.pdf',
          onLayout: (PdfPageFormat format) async => pdf.save());
    } catch (e) {
      rethrow;
    }
  }

  // Format "2026-03-20 09:16:00" → "09:16"
  static String _formatTime(dynamic raw) {
    if (raw == null) return '-';
    final str = raw.toString();
    if (str.length >= 16) {
      return str.substring(11, 16); // extract HH:mm
    }
    return str;
  }

  static pw.Widget _summaryItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: color)),
        pw.SizedBox(height: 2),
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      ],
    );
  }
}