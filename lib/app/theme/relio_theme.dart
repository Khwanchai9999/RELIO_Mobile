import 'package:flutter/material.dart';

import 'relio_colors.dart';
import 'relio_typography.dart';

// รวมการตั้งค่า ThemeData ของแอปไว้ที่เดียว เพื่อให้ทุกหน้าจอใช้สีและรูปแบบร่วมกัน
abstract final class RelioTheme {
  // เรียกตัวสร้างธีมชุดเดียวกันโดยเลือกความสว่างสำหรับโหมด light
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  // สร้างค่าธีมตาม Brightness ที่แอปเลือก แล้วส่งให้ MaterialApp ใช้ทั้งระบบ
  static ThemeData _build(Brightness brightness) {
    // ใช้ค่านี้เลือกคู่สีของ dark/light ให้แต่ละองค์ประกอบไปในทิศทางเดียวกัน
    final dark = brightness == Brightness.dark;
    // ColorScheme เป็นแหล่งสีมาตรฐานของ Material widget; seed ใช้สร้างสีเริ่มต้น
    final scheme =
        ColorScheme.fromSeed(
          seedColor: RelioColors.primary,
          brightness: brightness,
          // สี surface ใช้กับพื้นผิวของ widget; โหมดมืดเลือกสีเฉพาะ ส่วนโหมดสว่างใช้สีอ่อน
          surface: dark
              ? RelioColors.darkSurface
              : const Color.fromARGB(255, 251, 251, 251),
          // ปรับสีหลักและสี error ให้ตรงกับ semantic colors ของ RELIO หลังสร้าง scheme
        ).copyWith(
          primary: dark ? const Color(0xFF2DD4BF) : RelioColors.primary,
          error: dark ? const Color(0xFFF87171) : RelioColors.sos,
        );
    // เลือกสีและรูปแบบตัวอักษรให้สอดคล้องกับโหมดเดียวกับ ColorScheme
    final textTheme = RelioTypography.textTheme(brightness);

    // ตั้งค่า Material 3 เป็นฐาน ก่อนกำหนดหน้าตาของส่วนประกอบที่ RELIO ใช้
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // สีพื้นหลังหลักของ Scaffold ทุกหน้าที่ไม่ได้กำหนดพื้นหลังเฉพาะเอง
      scaffoldBackgroundColor: dark
          ? RelioColors.darkBackground
          : RelioColors.lightBackground,
      textTheme: textTheme,
      // AppBar ใช้สี surface และสีข้อความจาก scheme เพื่อแยกจากพื้นหลังหน้า
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 18,
        ),
      ),
      // การ์ดใช้ surface แบบเรียบ และเส้นขอบเปลี่ยนตามโหมดเพื่อให้เห็นขอบชัด
      cardTheme: CardThemeData(
        color: dark ? RelioColors.darkSurface : RelioColors.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: dark ? RelioColors.darkBorder : RelioColors.border,
          ),
        ),
      ),
      // กำหนดพื้นหลังและเส้นขอบของช่องกรอกข้อมูลให้เหมือนกันทั้งแอป
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? RelioColors.darkSurface : RelioColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? RelioColors.darkBorder : RelioColors.border,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? RelioColors.darkBorder : RelioColors.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RelioColors.primary, width: 1.5),
        ),
      ),
      // Navigation bar ใช้พื้นผิวยกขึ้นเล็กน้อย พร้อมสี indicator แยกสถานะที่เลือก
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: dark
            ? RelioColors.darkRaised
            : RelioColors.lightSurface,
        elevation: 8,
        shadowColor: (dark ? Colors.black : RelioColors.brandNavy).withValues(
          alpha: dark ? 0.22 : 0.08,
        ),
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark
            ? RelioColors.primary.withValues(alpha: 0.18)
            : RelioColors.primary.withValues(alpha: 0.12),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        // สีไอคอนเปลี่ยนตามสถานะ selected; สถานะอื่นใช้สีรองที่อ่านได้บน surface
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: selected ? 25 : 23,
          );
        }),
      ),
      // Badge ใช้สี SOS เพื่อให้ตัวนับหรือเครื่องหมายแจ้งเตือนเด่นจากพื้นหลัง
      badgeTheme: const BadgeThemeData(
        backgroundColor: RelioColors.sos,
        textColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 5),
      ),
      // เลือกสีเส้นคั่นให้มองเห็นชัดทั้งในโหมดสว่างและโหมดมืด
      dividerColor: dark ? RelioColors.darkBorder : RelioColors.border,
      // Dialog ใช้ surface เดียวกับการ์ดเพื่อให้หน้าตาสอดคล้องกัน
      dialogTheme: DialogThemeData(
        backgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      // Bottom sheet ทั้งแบบปกติและ modal ใช้ surface เดียวกัน
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        modalBackgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      // SnackBar ลอยเหนือเนื้อหาและใช้มุมโค้งตามรูปแบบส่วนกลางของแอป
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
