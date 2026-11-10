# คู่มือพัฒนาและทดสอบ RELIO บน Windows

## เครื่องมือ

- Flutter stable ที่มี Dart ตาม `^3.12.2` ใน [pubspec.yaml](../pubspec.yaml) ตรวจ SDK ด้วย `flutter --version` และ `flutter doctor -v`
- Android SDK และ Platform Tools พร้อม `adb` ค่า compileSdk, targetSdk, minSdk และ NDK ใช้ค่าจาก Flutter Gradle plugin ตาม [build.gradle.kts](../android/app/build.gradle.kts) ให้ติดตั้ง SDK ที่ doctor/build แจ้งสำหรับ Flutter ที่ใช้
- ใช้ JDK 17 ขึ้นไปที่รองรับ Gradle 9.1.0 โปรเจกต์ตั้ง Java source/target เป็น 17, AGP 9.0.1 และ Gradle Wrapper 9.1.0
- โทรศัพท์ Android สำหรับ Nearby จริง ให้เปิด Developer options และ USB Debugging พร้อมอนุญาต RSA ของเครื่องพัฒนา
- Git LFS สำหรับไฟล์แผนที่ และพื้นที่พอสำหรับ SDK, Flutter build และการเตรียมแผนที่บนอุปกรณ์

<a id="map-setup"></a>
## เตรียมแผนที่

ใช้ไฟล์ revision `20261101-z15-v4` ที่พาธ `assets/maps/thailand.pmtiles` ขนาด 601,215,311 bytes การ checkout จาก GitHub ต้องได้รับสิทธิ์อ่าน repository และ LFS object จริง การเตรียม LFS ในเครื่องอย่างเดียวไม่ทำให้ผู้ตรวจดาวน์โหลดไฟล์ได้ ให้ตรวจ hash ก่อน Build หาก LFS ปลายทางยังไม่มีไฟล์ ต้องรับ binary รุ่นเดียวกันผ่านช่องทางที่เจ้าของอนุมัติ

~~~powershell
Set-Location D:\RELIO_Mobile
git lfs install
git lfs pull --include="assets/maps/thailand.pmtiles"
$map = 'assets/maps/thailand.pmtiles'
$expected = 'e4cdca30d3478bf36cdae20218f2000711a357fb03162e221d1e6f01af9d609b'
if (!(Test-Path -LiteralPath $map -PathType Leaf)) { throw 'PMTiles missing' }
if ((Get-FileHash -LiteralPath $map -Algorithm SHA256).Hash -ne $expected) {
    throw 'PMTiles SHA-256 mismatch'
}
~~~

ดู [แหล่งข้อมูลและขอบเขตแผนที่](../assets/maps/README.md) หาก hash ไม่ตรงหรือเห็นไฟล์เป็นข้อความ LFS pointer ให้หยุด Build และตรวจสิทธิ์/โควตา การใช้ไฟล์อื่นแทนจะทำให้ผลการทดสอบไม่ตรงชุดนี้

## รันแอป

~~~powershell
flutter doctor -v
flutter pub get
flutter devices
flutter run --flavor dev --dart-define=RELIO_ENV=development
~~~

Entry point คือ `lib/main.dart` DEV มี package `com.relio.relio_mobile.dev` QA มี `com.relio.relio_mobile.test` และ PROD คือ `com.relio.relio_mobile` ให้ระบุ `-d SERIAL` เมื่อมีหลายเครื่อง Android เป็นเป้าหมายของการทดสอบ Nearby จริง

<a id="android-build"></a>
## สร้าง QA APK และติดตั้งอย่างปลอดภัย

QA ต้องใช้ค่ากำหนด public updater จากสคริปต์ใน repo แม้ทดสอบในเครื่อง เพราะ constructor ตรวจค่าเมื่อเปิด `RELIO_ENV=test` ใช้ VersionCode จาก `pubspec.yaml` และกำหนดข้อมูล About ให้ตรงกับรุ่นปัจจุบัน

~~~powershell
flutter pub get
. .\scripts\public-qa-config.ps1
$qa = Get-RelioPublicQaUpdateConfig
$qaDefines = @(
    '--dart-define=RELIO_ENV=test',
    '--dart-define=RELIO_VERSION=0.9.0',
    '--dart-define=RELIO_BUILD=84',
    "--dart-define=RELIO_PUBLIC_UPDATE_MANIFEST_URL=$($qa.ManifestUrl)",
    "--dart-define=RELIO_PUBLIC_UPDATE_OWNER=$($qa.Owner)",
    "--dart-define=RELIO_PUBLIC_UPDATE_REPO=$($qa.Repository)",
    "--dart-define=RELIO_PUBLIC_UPDATE_CHANNEL=$($qa.Channel)"
)
flutter build apk --flavor qa --debug @qaDefines
flutter build apk --flavor qa --release @qaDefines
~~~

ผลลัพธ์อยู่ที่ `build/app/outputs/flutter-apk/app-qa-debug.apk` และ `app-qa-release.apk` ตรวจ APK manifest ด้วย `aapt2 dump badging` และ certificate ด้วย `apksigner verify --print-certs` จาก Android SDK Build Tools ก่อนใช้งาน Debug ใช้ signer ตาม variant ที่ Gradle เลือก Release ต้องมี signing ที่ใช้งานได้ตาม config QA ของทีม ให้เตรียม `android/key.properties` จากตัวอย่างและใช้ keystore ที่อนุมัติในเครื่อง สำหรับ QA release ที่ต้องใช้ public updater หรือ Supabase ให้ดู [ขั้นตอน deploy](../scripts/deploy-test.ps1) และ [TEST_DEPLOYMENT](TEST_DEPLOYMENT.md) สคริปต์ `-NoUpload` ทำ quality gates และสร้าง APK โดยข้าม upload ใช้ environment variables ของ QA ตามคู่มือ และห้ามใส่ service-role key ใน client defines

~~~powershell
adb devices -l
$serial = 'REPLACE_WITH_DEVICE_SERIAL'
$apk = 'build/app/outputs/flutter-apk/app-qa-debug.apk'
adb -s $serial shell dumpsys package com.relio.relio_mobile.test |
    Select-String 'versionCode|versionName'
# หลังเทียบ package, versionCode และ certificate ของรุ่นเดิมกับ APK ใหม่แล้ว
adb -s $serial install -r $apk
~~~

ตรวจ signer ของ installed base APK ด้วย `adb -s SERIAL shell pm path com.relio.relio_mobile.test` และดึงเฉพาะ APK ไปยังพาธ local ที่ปลอดภัยเพื่อใช้ apksigner หากจำเป็น ทำทีละเครื่องและตรวจผลก่อนทำเครื่องถัดไป `install -r` ขอแทนที่แอปพร้อมรักษาข้อมูลเมื่อ Android ยอมรับ package/signing/versionCode หาก signature ไม่ตรงหรือ versionCode ต่ำกว่า ให้หยุดและใช้ APK ที่เข้ากันได้ หลีกเลี่ยง uninstall หรือ clear data เพราะทำให้สูญเสียข้อมูลในเครื่อง

<a id="test-cases"></a>
## การทดสอบ

หากเปิด PowerShell ใหม่ ให้กำหนด `$qaDefines` ตามบล็อก QA Build ก่อนรันทดสอบ Relay

~~~powershell
flutter analyze --no-pub
flutter test --no-pub test/conversation_reconciliation_test.dart
flutter test --no-pub test/automatic_relay_integration_test.dart @qaDefines
flutter test --no-pub test/packaged_thailand_map_test.dart
~~~

| กรณี | วิธีตรวจและผลที่คาดหวัง |
| --- | --- |
| เครื่องเดียว | เปิด Guest ขณะออฟไลน์ เปลี่ยนธีม ปิดและเปิดแอป ตรวจข้อมูลที่เขียนในเครื่อง |
| Direct สองเครื่อง | อนุญาต permission เปิด discovery/advertising จับคู่ ยืนยัน handshake ส่งข้อความและตรวจ ACK/ข้อความซ้ำ |
| Relay สามเครื่อง | ใช้ QA ที่รองรับ ปิดลิงก์ตรง A–C ให้ A–B และ B–C ใช้งานได้ ตรวจ A ส่ง B เก็บ C รับ และ ACK ย้อนกลับ แยก stored กับ delivered |
| SOS / Rescue | ใช้สถานการณ์สมมติ ยืนยัน SOS ตรวจเวลา/พิกัดหรือสถานะไม่พร้อม ตรวจการตอบรับและหยุด SOS หลีกเลี่ยงการโทรจริง |
| Offline Map | ตัด Internet เปิดแผนที่ครั้งแรกและรอเตรียมไฟล์ ตรวจแผนที่และ Nearby list แยกกัน |
| Cloud | ใช้ FakeCloud สำหรับ automated tests ส่วน live ใช้ backend QA และบัญชีทดสอบที่ได้รับอนุญาต ตรวจคิว offline, retry และ owner isolation |
| Developer Mode | เปิดจาก Settings ใน DEV/TEST ตรวจ diagnostics แยก demo และข้อมูลอุปกรณ์จริง ปิดตัวช่วย QA หลังทดสอบ |

คำว่า “ผลที่คาดหวัง” เป็นขั้นตอนตรวจ ไม่ใช่ผลรับรอง Build 84 ดู [แผนทดสอบอุปกรณ์](MANUAL_DEVICE_TESTS.md) และ [ผล Build 39](AUTOMATIC_TEXT_RELAY_BUILD39_ACCEPTANCE.md) สำหรับหลักฐานแยกตามรุ่น

## แก้ปัญหาที่พบบ่อย

- ADB ขึ้น unauthorized ให้ปลดล็อกโทรศัพท์และอนุญาต RSA จากคอมพิวเตอร์ที่รู้จัก
- Nearby ไม่พบเพื่อน ให้ตรวจสิทธิ์และสถานะวิทยุของทั้งคู่ ดู diagnostic เฉพาะ DEV/TEST
- Map ยังไม่ขึ้น ให้ตรวจ SHA-256 และพื้นที่ว่างบนโทรศัพท์ การเปิดครั้งแรกต้องเตรียมไฟล์ในเครื่อง
- Gradle หรือ analyzer แจ้ง Access Denied ให้ตรวจสิทธิ์ workspace/SDK และโปรแกรมที่จับไฟล์อยู่ แล้วบันทึกข้อความผิดพลาดก่อนลองใหม่
- Cloud notConfigured ให้ตรวจเฉพาะ environment ที่ต้องการทดสอบ DEV/Guest local ยังใช้ได้แม้ไม่ตั้ง Cloud
