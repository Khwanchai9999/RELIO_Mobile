import 'package:flutter/services.dart';

class AppUpdateApkInfo {
  const AppUpdateApkInfo({
    required this.packageName,
    required this.versionCode,
    required this.signingCertSha256,
  });

  final String packageName;
  final int versionCode;
  final String signingCertSha256;
}

abstract interface class AppUpdateInstaller {
  Future<bool> canRequestPackageInstalls();

  Future<void> openInstallPermissionSettings();

  Future<AppUpdateApkInfo> inspectApk(String path);

  Future<String> getInstalledSigningFingerprint();

  Future<void> launchInstaller(String path);
}

class MethodChannelAppUpdateInstaller implements AppUpdateInstaller {
  MethodChannelAppUpdateInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('relio/app_update');

  final MethodChannel _channel;

  @override
  Future<bool> canRequestPackageInstalls() async {
    final value = await _channel.invokeMethod<Object?>(
      'canRequestPackageInstalls',
    );
    return value == true;
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  @override
  Future<AppUpdateApkInfo> inspectApk(String path) async {
    final raw = await _channel.invokeMethod<Object?>(
      'inspectApk',
      <String, Object?>{'path': path},
    );
    if (raw is! Map) throw PlatformException(code: 'invalidApkInfo');
    final versionCode = raw['versionCode'];
    final packageName = raw['packageName'];
    final fingerprint = raw['signingCertSha256'];
    if (packageName is! String ||
        versionCode is! int ||
        fingerprint is! String) {
      throw PlatformException(code: 'invalidApkInfo');
    }
    return AppUpdateApkInfo(
      packageName: packageName,
      versionCode: versionCode,
      signingCertSha256: fingerprint,
    );
  }

  @override
  Future<String> getInstalledSigningFingerprint() async {
    final value = await _channel.invokeMethod<Object?>(
      'getInstalledSigningFingerprint',
    );
    if (value is! String || value.isEmpty) {
      throw PlatformException(code: 'installedSignerUnavailable');
    }
    return value;
  }

  @override
  Future<void> launchInstaller(String path) async {
    await _channel.invokeMethod<void>('launchInstaller', <String, Object?>{
      'path': path,
    });
  }
}
