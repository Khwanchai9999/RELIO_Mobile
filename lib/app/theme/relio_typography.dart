import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class RelioTypography {
  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    return GoogleFonts.promptTextTheme(base).copyWith(
      titleLarge: GoogleFonts.prompt(fontWeight: FontWeight.w700),
      titleMedium: GoogleFonts.prompt(fontWeight: FontWeight.w600),
      bodyMedium: GoogleFonts.prompt(fontSize: 14),
      labelLarge: GoogleFonts.prompt(fontWeight: FontWeight.w600),
    );
  }
}
