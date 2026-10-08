# RELIO — Final Repository Structure and Cleanup Audit

ตรวจเมื่อ 7 ต.ค. 2026 ที่ `D:\RELIO_Mobile` หลัง Week 3 runtime acceptance
และ cleanup ที่ผู้ใช้ยืนยันให้ดำเนินการ

## โครงสร้างหลัก

```text
D:\RELIO_Mobile\
├── android/                 Android flavors, manifests, Gradle และ native bridge
├── assets/                  branding และสื่อของแอป
├── build/                   Flutter/Android output ปัจจุบัน (generated; เก็บไว้)
├── .dart_tool/              Dart package/build metadata (generated; เก็บไว้)
├── dist/public-qa/           Build 36 QA APK และ SHA256SUMS.txt (คงไว้)
├── docs/                    architecture, QA และ Week 3 presentation guides
├── firebase_hosting/        Firebase Hosting templates/source
├── lib/                     Flutter application source
├── public_update/hosting/qa/ latest.json และ QA page สำหรับ Hosting
├── release_notes/           source release notes
├── scripts/                 build, QA, deploy และ presentation scripts
├── supabase/                migrations, functions/configuration
├── test/                    automated tests
├── third_party/             project dependencies/assets maintained in-repo
├── tool/                    repository tooling
├── .qa-local/               local QA service account (ignored; secret)
├── .firebase/               Firebase CLI cache (generated; เก็บไว้)
├── .idea/                   local IDE project metadata (เก็บไว้)
├── AGENTS.md / README.md
├── pubspec.yaml / pubspec.lock
├── firebase.json / .firebaserc
└── .env.qa.local            local QA configuration (ignored; secret)
```

`artifacts/` ถูกลบออกจากดิสก์ตามคำยืนยันเฉพาะเจาะจง ไม่ได้ย้ายหรือนำไปเก็บ
ที่อื่น; ภาพ/ไฟล์หลักฐานในโฟลเดอร์นั้นจึงไม่อยู่ใน workspace แล้ว

## Inventory และการจัดประเภท

- หลัง cleanup: 11,489 files; logical file size รวม 18,980,966,623 bytes
  (รวมไฟล์ generated/cache ที่เก็บไว้)
- ลบใน cleanup รอบสุดท้าย 329 ไฟล์ รวม 277,203,089 bytes:
  `artifacts/` 323 ไฟล์ / 75,772,995 bytes และหกไฟล์ APK/release-notes
  ซ้ำหรือเก่าจาก root `dist/` / 201,430,094 bytes.
- `KEEP_SOURCE`, `KEEP_TEST`, `KEEP_BUILD`, `KEEP_DOCUMENTATION`: source,
  tests, migrations, scripts, docs, `build/`, `.dart_tool/` และ Gradle caches
- `KEEP_SECRET_LOCAL`: `.env.qa.local`,
  `.qa-local/relio-qa-fcm-service-account.json`, `android/key.properties`,
  `android/relio-test.keystore`; ยืนยันว่า ignored และไม่แสดงค่า secret
- `KEEP_PUBLIC_QA`: `dist/public-qa/relio-test-0.9.0+36.apk` และ
  `dist/public-qa/SHA256SUMS.txt` คงอยู่; APK 68,335,905 bytes
- `KEEP_DEVELOPMENT`: `.idea/` และ `relio_mobile.iml` คงไว้เป็น metadata
- Huawei notes สองไฟล์คงเดิม เพราะ `final-qa-preflight.ps1` และ
  `release-public-qa.ps1` อ้างถึงโดยตรง; ไม่แก้หรือย้าย

## ลบออกจากดิสก์

- `artifacts/`: หลักฐาน ignored จำนวน 323 ไฟล์ / 75,772,995 bytes
- ไฟล์ root `dist/` หกรายการ: APK Build 22, Build 24, Build 36 ที่ซ้ำกับ
  สำเนาใน `dist/public-qa/` และ release notes ของ Build 22/24/36
- สำเนาใน `dist/public-qa/` ที่ไม่ใช่ Build 36 ถูกลบใน cleanup ก่อนหน้า;
  Build 36 และ checksum ปัจจุบันยังอยู่
- ไม่มี tracked source/documentation ถูกลบโดยการ cleanup นี้
- `build/`, `.dart_tool/`, Firebase/Gradle caches, secrets และ Huawei notes
  ไม่ถูกลบ

## Git และ secret status

- ไม่ commit, push หรือ publish
- Cleanup รอบนี้ลบเฉพาะ ignored files; ไม่มี Git-tracked deletion จาก cleanup
  รอบนี้ (มี staged `huawei-build12-installed.apk` deletion อยู่ก่อนหน้าและคงไว้)
- `android/app/src/qa/google-services.json` ยังคง tracked ตาม architecture;
  เป็น Firebase client identifiers สำหรับ QA package ไม่ใช่ service credential
- QA env, service-account, keystore และ `key.properties` ยังคง local/ignored;
  `.vscode/settings.json` ซ่อนรายการ secret และ generated paths จาก workspace
- Huawei note files ไม่แก้ ไม่ย้าย และไม่ลบ
- Working tree มี source/test/doc changes อื่นจากงานก่อนหน้า; คงไว้โดยไม่
  stage หรือทิ้ง changes ที่ไม่เกี่ยวกับ cleanup นี้

## Validation

- `flutter analyze --no-pub`: PASS
- `flutter test test/auth_startup_navigation_test.dart test/widget_test.dart`:
  13/13 PASS
- Huawei Build 38 QA candidate install แบบ `adb install -r` สำเร็จและ app
  เปิดได้; ไม่ได้ uninstall หรือ clear data
- ปิด RELIO ผ่าน Recent Apps แล้วเปิดใหม่บน Huawei: authenticated Home และ
  Profile ของ QA User A แสดงหลังเปิดใหม่ (physical session restore PASS)
- `git diff --check`: exit 0; Git แสดงเฉพาะคำเตือน line-ending conversion
- Direct read-only Supabase row/RLS verification ยังทำไม่ได้จาก workstation:
  HTTPS client ล้มก่อน HTTP response และไม่มี authenticated table-browser
  fallback ที่ใช้งานได้; ห้ามถือ local `synced` state เป็นหลักฐานว่า row มีอยู่
  จริงบน remote
