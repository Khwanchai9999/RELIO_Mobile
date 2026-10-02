import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/environment.dart';

class DiagnosticsLogService {
  DiagnosticsLogService({this.directory});

  static const _channel = MethodChannel('relio/diagnostics');
  static const _maxFileBytes = 1024 * 1024;
  static const _fileCount = 5;
  Directory? directory;
  Future<void> _writeQueue = Future<void>.value();
  int _eventCount = 0;
  DateTime? _oldest;
  DateTime? _newest;

  bool get enabled => RelioBuildInfo.developerDiagnosticsEnabled;
  int get eventCount => _eventCount;
  DateTime? get oldestEvent => _oldest;
  DateTime? get newestEvent => _newest;

  Future<void> flush() => _writeQueue;

  Future<Directory> get _root async => directory ??= Directory(
    '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}diagnostics',
  );

  Future<void> initialize() async {
    if (!enabled) return;
    try {
      final root = await _root;
      await root.create(recursive: true);
      await _refreshStats();
      record(
        'app',
        'diagnostics_started',
        fields: {'build': RelioBuildInfo.buildLabel},
      );
    } on Object {
      // Diagnostics must never block startup.
    }
  }

  static String peerAlias(String identifier) =>
      sha256.convert(utf8.encode(identifier)).toString().substring(0, 12);

  void record(
    String category,
    String event, {
    String severity = 'info',
    String? connectionTraceId,
    String? operation,
    String? stateFrom,
    String? stateTo,
    int? attempt,
    int? sdk,
    String? peerIdentifier,
    Object? nativeCode,
    String? nativeMessage,
    String? detailsSummary,
    String? reason,
    Map<String, Object?> fields = const {},
  }) {
    if (!enabled) return;
    final now = DateTime.now().toUtc();
    final entry = <String, Object?>{
      'timestamp': now.toIso8601String(),
      'category': _clean(category),
      'event': _clean(event),
      'severity': severity,
      if (connectionTraceId case final traceId?)
        'connectionTraceId': _clean(traceId),
      if (operation case final operationName?)
        'operation': _clean(operationName),
      if (stateFrom case final from?) 'stateFrom': _clean(from),
      if (stateTo case final to?) 'stateTo': _clean(to),
      ...?_optionalField('attempt', attempt),
      ...?_optionalField('sdk', sdk),
      if (peerIdentifier case final identifier?)
        'peerAlias': peerAlias(identifier),
      if (nativeCode case final code?) 'nativeCode': _clean(code.toString()),
      if (nativeMessage case final message?) 'nativeMessage': _clean(message),
      if (detailsSummary case final details?) 'detailsSummary': _clean(details),
      if (reason case final reasonText?) 'reason': _clean(reasonText),
      for (final item in fields.entries)
        if (!_sensitiveKey(item.key)) item.key: _safeValue(item.value),
    };
    final line = '${jsonEncode(entry)}\n';
    _eventCount++;
    _oldest ??= now;
    _newest = now;
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _append(line);
      } on Object {
        // File IO failure is intentionally isolated from application behavior.
      }
    });
  }

  Future<void> _append(String line) async {
    final root = await _root;
    await root.create(recursive: true);
    var active = File('${root.path}${Platform.pathSeparator}diagnostics.jsonl');
    if (await active.exists() &&
        await active.length() + utf8.encode(line).length > _maxFileBytes) {
      for (var index = _fileCount - 1; index >= 1; index--) {
        final from = File(
          '${root.path}${Platform.pathSeparator}diagnostics.$index.jsonl',
        );
        final to = File(
          '${root.path}${Platform.pathSeparator}diagnostics.${index + 1}.jsonl',
        );
        if (index == _fileCount - 1 && await from.exists()) {
          await from.delete();
        }
        if (index < _fileCount - 1 && await from.exists()) {
          await from.rename(to.path);
        }
      }
      if (await active.exists()) {
        await active.rename(
          '${root.path}${Platform.pathSeparator}diagnostics.1.jsonl',
        );
      }
      active = File('${root.path}${Platform.pathSeparator}diagnostics.jsonl');
    }
    await active.writeAsString(line, mode: FileMode.append, flush: false);
  }

  Future<int> get storageBytes async {
    try {
      final root = await _root;
      if (!await root.exists()) return 0;
      return (await root.list().where((item) => item is File).toList())
          .cast<File>()
          .fold<int>(0, (sum, file) => sum + file.lengthSync());
    } on Object {
      return 0;
    }
  }

  Future<void> _refreshStats() async {
    final root = await _root;
    if (!await root.exists()) return;
    final files =
        (await root.list().where((item) => item is File).toList()).cast<File>()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      if (!file.path.endsWith('.jsonl')) continue;
      for (final line in await file.readAsLines()) {
        if (line.isEmpty) continue;
        try {
          final value = jsonDecode(line) as Map<String, dynamic>;
          final date = DateTime.tryParse(value['timestamp'] as String? ?? '');
          if (date == null) continue;
          _eventCount++;
          if (_oldest == null || date.isBefore(_oldest!)) _oldest = date;
          if (_newest == null || date.isAfter(_newest!)) _newest = date;
        } on Object {
          continue;
        }
      }
    }
  }

  Future<File> exportZip({
    required Map<String, Object?> appInfo,
    required Map<String, Object?> deviceState,
    required String summary,
  }) async {
    await _writeQueue;
    final root = await _root;
    final archive = Archive();
    if (await root.exists()) {
      for (final entry
          in await root.list().where((item) => item is File).toList()) {
        final file = entry as File;
        if (!file.path.endsWith('.jsonl')) continue;
        final data = await file.readAsBytes();
        archive.addFile(
          ArchiveFile(file.uri.pathSegments.last, data.length, data),
        );
      }
    }
    archive.addFile(
      ArchiveFile(
        'summary.txt',
        utf8.encode(summary).length,
        utf8.encode(summary),
      ),
    );
    for (final item in {
      'app_info.json': appInfo,
      'device_state.json': deviceState,
    }.entries) {
      final data = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(item.value),
      );
      archive.addFile(ArchiveFile(item.key, data.length, data));
    }
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) {
      throw const FileSystemException('Could not encode diagnostics archive');
    }
    final stamp = DateTime.now().toLocal();
    final filename =
        'relio-diagnostics-${stamp.year.toString().padLeft(4, '0')}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}-${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}${stamp.second.toString().padLeft(2, '0')}.zip';
    final temp = await getTemporaryDirectory();
    final exportDirectory = Directory(
      '${temp.path}${Platform.pathSeparator}diagnostics',
    );
    await exportDirectory.create(recursive: true);
    return File(
      '${exportDirectory.path}${Platform.pathSeparator}$filename',
    ).writeAsBytes(bytes, flush: true);
  }

  Future<void> share(File file) async {
    if (!enabled) return;
    await _channel.invokeMethod<void>('shareDiagnosticsZip', {
      'path': file.path,
    });
  }

  Future<Map<String, Object?>> deviceInfo() async {
    if (!enabled) return const {};
    try {
      return Map<String, Object?>.from(
        await _channel.invokeMapMethod<String, Object?>(
              'getDiagnosticsDeviceInfo',
            ) ??
            const {},
      );
    } on Object {
      return const {'platform': 'unavailable'};
    }
  }

  Future<void> clearLogs() async {
    if (!enabled) return;
    await _writeQueue;
    try {
      final root = await _root;
      if (await root.exists()) {
        await for (final item in root.list()) {
          if (item is File && item.path.endsWith('.jsonl')) await item.delete();
        }
      }
      _eventCount = 0;
      _oldest = null;
      _newest = null;
    } on Object {
      // Clearing diagnostics never touches app data and is best effort.
    }
  }

  static bool _sensitiveKey(String key) => RegExp(
    r'(token|password|secret|authorization|private.?key|message.?body|content|credential|service.?role|conversation.?id|user.?id|device.?id)',
    caseSensitive: false,
  ).hasMatch(key);

  static Object? _safeValue(Object? value) {
    if (value is String) return _clean(value);
    if (value is num || value is bool || value == null) return value;
    if (value is Iterable) return value.take(20).map(_safeValue).toList();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (!_sensitiveKey(entry.key.toString()))
            entry.key.toString(): _safeValue(entry.value),
      };
    }
    return _clean(value.toString());
  }

  static String _clean(String value) {
    var clean = value.replaceAll(
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      '[REDACTED]',
    );
    clean = clean.replaceAll(
      RegExp(
        r'(access|refresh|fcm|github|vercel)[_-]?token\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '[REDACTED]',
    );
    clean = clean.replaceAll(
      RegExp(
        r'(service_role|password|secret|authorization|private[_ ]?key)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '[REDACTED]',
    );
    clean = clean.replaceAll(
      RegExp(r'message[_ ]?body\s*[:=]\s*[^\r\n]+', caseSensitive: false),
      'message_body=[REDACTED]',
    );
    clean = clean.replaceAll(
      RegExp(
        r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
      ),
      '[REDACTED_PRIVATE_KEY]',
    );
    clean = clean.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'),
      '[REDACTED_JWT]',
    );
    return clean.length > 240 ? '${clean.substring(0, 240)}…' : clean;
  }

  static Map<String, Object?>? _optionalField(String name, Object? value) =>
      value == null ? null : {name: value};
}
