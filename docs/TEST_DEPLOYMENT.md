# RELIO Test Deployment — v0.8.6

## Public QA channel — v0.8.6+12

The normal QA distribution path is a Firebase Hosting metadata page plus a
GitHub Releases APK, not tester enrollment.
From `D:\RELIO_Mobile` run:

```powershell
.\scripts\release-public-qa.ps1 -NoDeploy
.\scripts\release-public-qa.ps1
```

The script derives the project root from `$PSScriptRoot`, requires version
`0.8.6+12`, runs quality/build/signing gates, prepares isolated
`public_update\hosting\qa\` metadata, creates or verifies the immutable
`qa-v0.8.6-b12` release in the authenticated owner's public
`RELIO-Android-Updates` repository, deploys only Hosting in Firebase project
`relio-17dc0`, and verifies both public origins. The public page is
`https://relio-17dc0.web.app/qa/`; ordinary download needs no Firebase tester
account or Google sign-in.

The app validates schema, channel, exact QA package, monotonic versionCode,
HTTPS Hosting `/qa/` path, SHA-256, file size, and QA signing fingerprint
before invoking Android Package Installer. Android user confirmation remains
mandatory. Firebase App Distribution Build 11 (`0.8.5+11`) remains intact as
an internal/fallback channel. This script never deploys App Distribution,
Functions, Firestore, Realtime Database, Storage, or Supabase resources.

เอกสารนี้อธิบายทั้ง public Firebase Hosting QA channel และ Firebase App
Distribution fallback ของ RELIO Test โดย Supabase ยังคงเป็น cloud backend ของ
แอป และไม่ได้เพิ่ม Firebase Auth, Firestore, Storage หรือ Realtime Database

## ช่องทางของแอป

| Channel | Application ID | ใช้สำหรับ |
| --- | --- | --- |
| DEV | `com.relio.relio_mobile.dev` | USB debugging และ developer diagnostics |
| TEST | `com.relio.relio_mobile.test` | Firebase Hosting public QA; App Distribution fallback |
| PROD | `com.relio.relio_mobile` | production ในอนาคต ยังไม่ publish |

DEV และ TEST เป็นคนละแอป จึงมี SQLite/app data คนละชุดโดยตั้งใจ ข้อมูลจาก
การติดตั้ง DEV จะไม่ย้ายไป TEST อัตโนมัติ

## One-time setup สำหรับผู้พัฒนา

1. ใช้ Flutter, Dart, JDK และ Android SDK ที่โปรเจกต์ต้องการ
2. สร้าง test signing files:

   ```powershell
   .\scripts\setup-test-signing.ps1
   ```

   คำสั่งนี้สร้าง `android/relio-test.keystore` และ
   `android/key.properties` ที่ถูก ignore โดย Git รหัสผ่านจะไม่ถูกพิมพ์ออกมา
3. สำรอง keystore และรหัสผ่านไว้ใน password manager ที่ปลอดภัย
4. สร้าง Firebase Android app ที่มี package name
   `com.relio.relio_mobile.test` และจด Firebase App ID ไว้
5. ติดตั้ง Firebase CLI และล็อกอินครั้งเดียวด้วย `firebase login`
6. สร้าง tester group เช่น `relio-testers` ใน Firebase console หรือเพิ่ม
   tester emails ตามระบบของทีม
7. ติดตั้ง GitHub CLI ทางการและล็อกอินด้วย `gh auth login` สำหรับเจ้าของ
   repository ที่อนุมัติเท่านั้น; script จะสร้างหรือใช้ public repository
   `RELIO-Android-Updates` โดยไม่ push source หรือ secret ใด ๆ

Firebase CLI distribution ใช้ Firebase App ID, release notes และ testers/groups
สำหรับการอัปโหลด ส่วน Android runtime ใช้ API-only library ทุก variant และ
full App Distribution SDK เฉพาะ `qaImplementation`; repository มี real
`android/app/src/qa/google-services.json` สำหรับ package เดียวกันเท่านั้น และ
ไม่เพิ่ม Firebase Auth, Firestore, Storage หรือ Analytics โดย deployment script
จะอ่าน App ID จากไฟล์นี้เมื่อไม่มี `FIREBASE_APP_ID`

## Quality gate และการแจก

จาก active root `D:\RELIO_Mobile` เท่านั้น:

```powershell
.\scripts\deploy-test.ps1
```

สคริปต์จะ:

1. ตรวจ workspace, tools, version และ test signing
2. รัน `dart format --output=none --set-exit-if-changed .`
3. รัน `flutter analyze`
4. รัน `flutter test`
5. สร้าง TEST APK ด้วย Android flavor ภายในชื่อ `qa` (`--flavor qa`; AGP 9
   ไม่อนุญาตชื่อ flavor ที่ขึ้นต้นด้วย `test`)
6. ตรวจ package/version/signature และคัดลอกไป
   `dist\relio-test-0.8.5+11.apk`
7. ใช้ release notes จาก `release_notes\0.8.5.md` เมื่อมีไฟล์ release notes ของ
   milestone นี้
8. อัปโหลดเมื่อ Firebase CLI, `FIREBASE_APP_ID` และ tester/group config พร้อม

ถ้าไม่ส่ง `FIREBASE_GROUPS` หรือ `FIREBASE_TESTERS`, script จะใช้ group มาตรฐาน
`relio-testers` และจะสร้าง group ว่างชื่อ `RELIO Testers` ได้ต่อเมื่อ account ที่
login อยู่พิสูจน์สิทธิ์ใน Firebase project เดียวกับ QA config แล้วเท่านั้น

ถ้า format, analyze, test หรือ build ไม่ผ่าน สคริปต์จะหยุดและไม่ upload

ถ้าต้องการสร้าง artifact โดยยังไม่ upload:

```powershell
.\scripts\deploy-test.ps1 -NoUpload
```

กำหนดค่า upload ได้โดยไม่เก็บ secret ใน source control:

```powershell
$env:FIREBASE_APP_ID = '1:...:android:...'
$env:FIREBASE_GROUPS = 'relio-testers'
.\scripts\deploy-test.ps1
```

หรือส่ง `-FirebaseAppId`, `-Groups`, `-Testers` ให้สคริปต์โดยตรง

App ID ที่ส่งผ่าน parameter หรือ environment ต้องตรงกับ `mobilesdk_app_id` ใน
QA config เสมอ ถ้าไม่ตรง script จะหยุดก่อน upload และจะไม่อ่านหรือพิมพ์ API key

## Historical Build 11 and public Build 12

Build 11 ใช้เป็น historical/internal App Distribution release ส่วน Build 12
เป็น public hybrid first-install baseline. APK อยู่ใน GitHub Releases และ
Firebase Hosting มีเฉพาะ metadata/page จึงไม่ต้อง upgrade billing หรือเปลี่ยน
ไปใช้ Firebase Storage โดยอัตโนมัติ:

```powershell
.\scripts\bump-qa-build.ps1 -NextBuildNumber 12 -WhatIf
.\scripts\bump-qa-build.ps1 -NextBuildNumber 12
```

ใช้ release-note template ที่เตรียมไว้ด้วย `-ReleaseNotesPath`:

```powershell
.\scripts\deploy-test.ps1 -ReleaseNotesPath .\release_notes\0.8.5-build-12-template.md
```

คำสั่ง bump เดิมด้านล่างเป็น historical workflow เท่านั้น และห้ามสร้าง Build 13
จนกว่าผู้ใช้จะยืนยันการติดตั้ง Build 12 จริงบน Android

## Signing และ update

TEST ทุก build ต้องใช้ `android/relio-test.keystore` เดิมและ application ID เดิม
เพื่อให้ Android มองเป็นการ update ไม่ใช่แอปใหม่:

```text
TEST vN → TEST vN+1
same application ID
same signing key
SQLite/app data remains
```

ถ้า test keystore สูญหาย APK ใหม่จะ update การติดตั้ง TEST เดิมไม่ได้ ผู้ทดสอบ
ต้องถอนการติดตั้งก่อน และข้อมูล local TEST อาจถูกลบ ดังนั้นต้องสำรอง key และ
password ก่อนแจก build แรก

ห้าม commit `*.jks`, `*.keystore`, `android/key.properties`, passwords,
Firebase tokens หรือ service-account JSON

## ประสบการณ์ของผู้ทดสอบ

การติดตั้งครั้งแรก:

1. ผู้พัฒนาแจก build ผ่าน Firebase App Distribution
2. ผู้ทดสอบเปิด invitation และ sign in ด้วย Google account
3. ผู้ทดสอบติดตั้ง Firebase App Tester หรือเปิด tester experience
4. ผู้ทดสอบกดยอมรับการติดตั้งเมื่อ Android ขออนุญาต

ครั้งต่อไป ผู้ทดสอบจะได้รับ notification/release ใหม่และติดตั้ง update ของ
RELIO Test เดิมได้โดยไม่ต้องเสียบ USB ทุกครั้ง แต่ Android ยังคงให้ผู้ใช้ยืนยัน
การติดตั้งตามปกติ ไม่มี silent APK installation

ก่อนแจกทุกครั้ง ควรทำ USB smoke test ที่สำคัญก่อน เช่น เปิดแอป, theme,
Nearby, Chat, SOS, media และ location

## Tester management

ใช้กลุ่ม `relio-testers` เป็นค่าแนะนำ หรือส่ง tester emails ให้สคริปต์:

```powershell
.\scripts\deploy-test.ps1 -Testers 'tester@example.com'
```

ไม่ใส่ email จริงไว้ใน repository

## Troubleshooting

- **Firebase CLI ไม่พบ:** ติดตั้ง Firebase CLI และใช้ `firebase login`
- **ยังไม่ได้ตั้งค่า Firebase:** ตั้ง `FIREBASE_APP_ID` และ `FIREBASE_GROUPS`
  หรือ `FIREBASE_TESTERS`; script จะสร้าง APK แล้วหยุดที่สถานะ DEFERRED
- **ติดตั้งทับไม่ได้:** ตรวจว่าใช้ `com.relio.relio_mobile.test` และ keystore
  เดิม หาก signing key เปลี่ยน ต้องถอนการติดตั้ง TEST เดิม
- **ข้อมูลไม่ตรงกับ USB app:** DEV และ TEST ใช้คนละ application ID และ database
  เป็นพฤติกรรมที่ตั้งใจ
- **เครื่องไม่เห็น release:** ตรวจ invitation, Google account, tester/group
  access และการหมดอายุของ release ใน Firebase

## Firebase live status

v0.8.6 เพิ่ม public QA update provider, strict manifest/APK verification และ
QA-only Android installer permission ขณะที่ full App Distribution SDK ยังคงอยู่
ใน QA เท่านั้น ไฟล์ QA Firebase config ถูกเพิ่มจาก Firebase project จริงและ
ตรวจ package เป็น `com.relio.relio_mobile.test`; จะไม่ invent App ID, tester
email หรือ credential ใด ๆ Firebase Hosting deploy มีเฉพาะ page/manifest และ
APK อยู่ใน GitHub release asset.

ตรวจ isolation ได้ด้วย:

```powershell
.\scripts\verify-qa-update-isolation.ps1
```

รายละเอียด update architecture และ first-install/update flow อยู่ที่
[docs/QA_UPDATE_SYSTEM.md](QA_UPDATE_SYSTEM.md)

Official references:

- [Firebase CLI distribution](https://firebase.google.com/docs/app-distribution/android/distribute-cli)
- [Firebase tester setup](https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester)
- [Firebase Android in-app alerts](https://firebase.google.com/docs/app-distribution/set-up-alerts?platform=android)
