import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/cloud/cloud_models.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

class CloudDiagnosticsScreen extends StatelessWidget {
  const CloudDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
    return Scaffold(
      appBar: RelioAppBar(
        title: 'Cloud Diagnostics',
        onBack: () => context.pop(),
      ),
      body: StreamBuilder<CloudState>(
        stream: dependencies.cloudDataSource.watchCloudState(),
        initialData: dependencies.cloudDataSource.cloudState,
        builder: (context, cloudSnapshot) => StreamBuilder<AuthState>(
          stream: dependencies.authService.watchState(),
          initialData: dependencies.authService.state,
          builder: (context, authSnapshot) {
            final state = cloudSnapshot.data ?? CloudState.notConfigured;
            final auth = authSnapshot.data ?? AuthState.guest;
            final configured =
                dependencies.cloudDataSource.configuration.isConfigured;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      state == CloudState.ready
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                    ),
                    title: Text(_label(state)),
                    subtitle: Text(
                      configured
                          ? 'Supabase configuration detected'
                          : 'ไม่พบ SUPABASE_URL / SUPABASE_ANON_KEY',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Authentication'),
                        subtitle: Text(auth.name),
                      ),
                      ListTile(
                        title: const Text('Storage bucket'),
                        subtitle: Text(
                          configured ? 'relio-media (private)' : 'รอตั้งค่า',
                        ),
                      ),
                      ListTile(
                        title: const Text('Identity'),
                        subtitle: Text(
                          dependencies.authService.identity?.userId ??
                              'Guest / local-only',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Cloud เป็นปลายทางเสริมของข้อมูลในเครื่องเท่านั้น หน้าหลัก แชท SOS และ Nearby ยังทำงานผ่าน Drift ได้เมื่อไม่มีอินเทอร์เน็ต',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'ไม่แสดง URL เต็มหรือคีย์ เพื่อป้องกันการเปิดเผยข้อมูลลับ',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _label(CloudState state) => switch (state) {
    CloudState.notConfigured => 'ยังไม่ได้ตั้งค่า Cloud',
    CloudState.signedOut => 'Cloud พร้อมใช้งาน แต่ยังไม่ได้เข้าสู่ระบบ',
    CloudState.ready => 'Cloud พร้อมใช้งาน',
    CloudState.offline => 'ออฟไลน์',
    CloudState.error => 'Cloud มีข้อผิดพลาด',
  };
}
