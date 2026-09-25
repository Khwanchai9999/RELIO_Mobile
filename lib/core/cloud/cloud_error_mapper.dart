import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_models.dart';

abstract final class CloudErrorMapper {
  static CloudException map(Object error, {String fallbackCode = 'network'}) {
    if (error is CloudException) return error;
    if (error is AuthException) {
      final status = int.tryParse(error.statusCode ?? '');
      final rawCode = error.code?.toLowerCase();
      final code = rawCode == 'email_not_confirmed'
          ? 'emailConfirmationRequired'
          : status == 429
          ? 'rateLimit'
          : status != null && status >= 500
          ? 'server'
          : 'auth';
      return CloudException(_message(code), code: code);
    }
    if (error is PostgrestException) {
      final code = switch (error.code) {
        '42501' || '401' || '403' => 'permissionDenied',
        '404' => 'notFound',
        '23505' => 'conflict',
        _ => fallbackCode,
      };
      return CloudException(_message(code), code: code);
    }
    if (error is StorageException) {
      final status = int.tryParse(error.statusCode ?? '');
      final code = status == 401 || status == 403
          ? 'permissionDenied'
          : status == 404
          ? 'notFound'
          : status != null && status >= 500
          ? 'server'
          : 'storage';
      return CloudException(_message(code), code: code);
    }
    if (error is SocketException || error is TimeoutException) {
      return const CloudException('Cloud ไม่พร้อมใช้งาน', code: 'offline');
    }
    return CloudException(_message(fallbackCode), code: fallbackCode);
  }

  static String messageFor(String code) => _message(code);

  static String _message(String code) => switch (code) {
    'auth' => 'การยืนยันตัวตนไม่สำเร็จ',
    'emailConfirmationRequired' => 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ',
    'permissionDenied' => 'บัญชีนี้ไม่มีสิทธิ์เข้าถึงข้อมูลดังกล่าว',
    'notFound' => 'ไม่พบข้อมูลบน Cloud',
    'conflict' => 'ข้อมูลบน Cloud ขัดแย้งกับรายการในเครื่อง',
    'rateLimit' => 'Cloud ขอให้ลองใหม่ภายหลัง',
    'server' => 'Cloud ขัดข้องชั่วคราว',
    'storage' => 'การจัดการไฟล์บน Cloud ไม่สำเร็จ',
    'offline' => 'Cloud ไม่พร้อมใช้งาน',
    'notConfigured' => 'ยังไม่ได้ตั้งค่า Supabase',
    'signedOut' => 'กรุณาเข้าสู่ระบบก่อนใช้งาน Cloud',
    _ => 'การเชื่อมต่อ Cloud ไม่สำเร็จ',
  };
}
