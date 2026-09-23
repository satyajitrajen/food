import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';

/// Attendance board (manager view): on-duty staff first, then the full
/// clock-in/out log with hours. Entries are recorded on this terminal when
/// staff sign in and out.
class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  String _hours(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '$m min';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final log = provider.attendanceLog;
    final onDuty = log.where((a) => a.isOnDuty).toList();
    final offDuty = log.where((a) => !a.isOnDuty).toList();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Staff Attendance',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: log.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fact_check_outlined, size: 48, color: AppColors.textLight),
                      SizedBox(height: 12),
                      Text('No attendance recorded yet',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      SizedBox(height: 6),
                      Text(
                        'Entries appear automatically when staff sign in and out on this device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('On duty now',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  if (onDuty.isEmpty)
                    const Text('Nobody is clocked in right now.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13))
                  else
                    ...onDuty.map((a) => _card(
                          context,
                          a.staffName,
                          'In ${DateFormat('hh:mm a').format(a.clockIn)}',
                          'On duty · ${_hours(a.minutesWorked)}',
                          AppColors.vegGreen,
                          Icons.circle,
                        )),
                  const SizedBox(height: 18),
                  const Text('Full log',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  ...offDuty.map((a) => _card(
                        context,
                        a.staffName,
                        '${DateFormat('dd MMM, hh:mm a').format(a.clockIn)} → '
                            '${a.clockOut == null ? '' : DateFormat('hh:mm a').format(a.clockOut!)}',
                        'Clocked out · ${_hours(a.minutesWorked)}',
                        AppColors.textMuted,
                        Icons.check_circle_outline,
                      )),
                ],
              ),
      ),
    );
  }

  Widget _card(BuildContext context, String name, String timeLine,
      String status, Color statusColor, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryGreenLight,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: AppColors.primaryGreen, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(timeLine,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: statusColor),
              const SizedBox(width: 6),
              Text(status,
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
