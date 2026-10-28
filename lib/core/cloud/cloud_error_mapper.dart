import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_models.dart';

abstract final class CloudErrorMapper {
  static CloudException map(Object error, {String fallbackCode = 'network'}) {
    if (error is CloudException) return error;
    if (error is FunctionException) {
      final code = switch (error.status) {
        0 => 'offline',
        401 => 'sessionExpired',
        409 => 'deleteBlocked',
        _ => 'delete',
      };
      return CloudException(_message(code), code: code);
    }
    if (error is AuthException) {
      // GoTrue wraps transport failures in this AuthException subtype, so
      // treating every AuthException as bad credentials hides Cloud outages.
      if (error is AuthRetryableFetchException) {
        return const CloudException('Cloud ไม่พร้อมใช้งาน', code: 'offline');
      }
      final status = int.tryParse(error.statusCode ?? '');
      final rawCode = error.code?.toLowerCase();
      final code = switch (rawCode) {
        'email_exists' || 'user_already_exists' => 'emailAlreadyUsed',
        'email_not_confirmed' => 'emailConfirmationRequired',
        'weak_password' => 'weakPassword',
        'signup_disabled' || 'email_provider_disabled' => 'signupDisabled',
        'email_address_invalid' => 'invalidEmail',
        'email_address_not_authorized' => 'emailDeliveryUnavailable',
        'validation_failed' => 'invalidInput',
        'over_email_send_rate_limit' => 'emailRateLimit',
        'over_request_rate_limit' => 'rateLimit',
        'otp_expired' ||
        'flow_state_expired' ||
        'flow_state_not_found' => 'recoveryRequired',
        'same_password' => 'samePassword',
        _ when status == 429 => 'rateLimit',
        _ when status != null && status >= 500 => 'server',
        _ => 'auth',
      };
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
    'passwordReset' => 'กู้รหัสผ่านไม่สำเร็จ กรุณาลองใหม่ภายหลัง',
    'recoveryRequired' =>
      'ลิงก์กู้รหัสผ่านไม่พร้อมหรือหมดอายุ กรุณาขอลิงก์ใหม่',
    'samePassword' => 'กรุณาใช้รหัสผ่านใหม่ที่ต่างจากรหัสผ่านเดิม',
    'emailAlreadyUsed' => 'อีเมลนี้ถูกใช้งานแล้ว',
    'weakPassword' => 'รหัสผ่านไม่ผ่านข้อกำหนดของระบบ',
    'signupDisabled' => 'ขณะนี้ระบบปิดรับสมัครบัญชีใหม่',
    'invalidEmail' => 'อีเมลนี้ใช้สมัครไม่ได้ กรุณาใช้อีเมลที่ใช้งานได้จริง',
    'emailDeliveryUnavailable' => 'ขณะนี้ระบบส่งอีเมลยืนยันไปยังอีเมลนี้ไม่ได้',
    'emailRateLimit' => 'ส่งอีเมลยืนยันถี่เกินไป กรุณารอสักครู่แล้วลองใหม่',
    'invalidInput' => 'ข้อมูลสมัครสมาชิกไม่ถูกต้อง กรุณาตรวจสอบอีกครั้ง',
    'auth' => 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
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
    'delete' => 'ไม่สามารถลบบัญชีได้ กรุณาลองใหม่',
    'deleteBlocked' =>
      'ยังไม่สามารถลบบัญชีนี้ได้ เนื่องจากมีข้อมูลที่ระบบต้องตรวจสอบ',
    'sessionExpired' => 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง',
    _ => 'การเชื่อมต่อ Cloud ไม่สำเร็จ',
  };
}
