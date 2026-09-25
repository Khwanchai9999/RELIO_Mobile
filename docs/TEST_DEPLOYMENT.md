# RELIO Test Deployment — v0.5.2

เอกสารนี้อธิบายการแจก Android TEST build ของ RELIO ผ่าน Firebase App
Distribution เท่านั้น โดย Supabase ยังคงเป็น cloud backend ของแอป และไม่ได้
เพิ่ม Firebase Auth, Firestore, Storage หรือ Realtime Database

## ช่องทางของแอป

| Channel | Application ID | ใช้สำหรับ |
| --- | --- | --- |
| DEV | `com.relio.relio_mobile.dev` | USB debugging และ developer diagnostics |
| TEST | `com.relio.relio_mobile.test` | Firebase App Distribution |
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

Firebase CLI distribution ใช้ Firebase App ID, release notes และ testers/groups;
โปรเจกต์นี้จึงไม่เพิ่ม Firebase runtime plugin หรือ `google-services.json`
เพียงเพื่ออัปโหลด TEST APK

## Quality gate และการแจก

จาก root `D:\RELIO\RELIO_Mobile`:

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
6. ตรวจ APK และคัดลอกไป `dist\relio-test-0.5.2+7.apk`
7. ใช้ release notes จาก `release_notes\0.5.2.md`
8. อัปโหลดเมื่อ Firebase CLI, `FIREBASE_APP_ID` และ tester/group config พร้อม

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

v0.5.2 เตรียม local pipeline และ Firebase CLI integration แล้ว แต่จะไม่ invent
Firebase project ID, App ID, tester email หรือ credential ใด ๆ การ upload จริง
จะทำได้เมื่อผู้ใช้ตั้งค่าบัญชีและ Firebase project เอง

Official references:

- [Firebase CLI distribution](https://firebase.google.com/docs/app-distribution/android/distribute-cli)
- [Firebase tester setup](https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester)
