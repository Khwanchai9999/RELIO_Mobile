import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 210,
                    height: 210,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0x2214B8A6), Color(0x113B82F6)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.groups_2_rounded,
                        size: 100,
                        color: RelioColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: RelioColors.primary,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Center(
                          child: Text(
                            'R',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        'RELIO',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'สื่อสารได้ แม้ไม่มีสัญญาณ',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'เชื่อมต่อผู้คนใกล้กัน เพื่อความปลอดภัยของทุกคน',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  const _Feature(
                    icon: Icons.wifi_off_rounded,
                    title: 'Offline-First',
                    detail: 'สื่อสารได้แม้ไม่มีอินเทอร์เน็ต',
                  ),
                  const _Feature(
                    icon: Icons.radar_rounded,
                    title: 'อุปกรณ์ใกล้เคียง',
                    detail: 'ค้นหาผู้ใช้ RELIO ที่อยู่ใกล้คุณ',
                  ),
                  const _Feature(
                    icon: Icons.shield_outlined,
                    title: 'ฉุกเฉิน SOS',
                    detail: 'ขอความช่วยเหลือได้ทันที',
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('เข้าสู่ระบบ'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('สร้างบัญชีใหม่'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('ใช้งานแบบออฟไลน์'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RelioSpacing.md),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: RelioColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: RelioColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
