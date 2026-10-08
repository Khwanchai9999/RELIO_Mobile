# คู่มือสาธิต RELIO Week 3

คู่มือนี้ใช้กับ RELIO QA Build 38 บน Huawei Y9s (`YDVNW19B23003867`) เน้นสิ่งที่แสดงและคำอธิบายสำหรับการบันทึกวิดีโอ ไม่ใช้ภาพหรือข้อมูลจำลองเป็นหลักฐาน runtime

## 1. Run from VS Code

เปิดไฟล์: `D:\RELIO_Mobile\scripts\run-week3-demo.ps1`

ชี้: ตัวตรวจ serial/QA configuration และคำสั่ง `flutter run --flavor qa`

พูด: “ผมเปิด source ของ RELIO ใน VS Code แล้วรัน QA flavor บนอุปกรณ์ Huawei ที่กำหนด”

ทำบนมือถือ: เชื่อม Huawei ที่อนุญาตกับ ADB; จาก terminal ที่ project root รัน `scripts\run-week3-demo.ps1`; รอแอปเปิดและยืนยันหน้า Home ก่อนเริ่มอัดคลิป

## 2. Authentication

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\auth\auth_screens.dart`, `D:\RELIO_Mobile\lib\core\cloud\auth_service.dart`, `D:\RELIO_Mobile\lib\core\relio_dependencies.dart`

ชี้: `LoginScreen._login()`, `CloudAuthService.restoreSession()` และ `RelioDependencies.initializeAuth()`

พูด: “AuthService กู้คืน session ก่อนตัดสินใจหน้าเริ่มต้น; session ที่ยังใช้ได้กลับเข้า Home ส่วนผู้ใช้ที่ไม่มี session จะเห็น Welcome”

ทำบนมือถือ: เปิด Profile เพื่อแสดงบัญชี QA เดิม; ปิด RELIO ด้วยการนำออกจาก Recent Apps แล้วเปิด package เดิมอีกครั้ง โดยไม่ reinstall หรือ clear data; แสดงว่าเข้า Home/Profile กลับมาได้

## 3. Error handling

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\auth\auth_screens.dart`, `D:\RELIO_Mobile\lib\core\cloud\cloud_error_mapper.dart`

ชี้: validators ใน `LoginScreen` และ `CloudErrorMapper.messageFor()`

พูด: “ฟอร์มตรวจข้อมูลที่จำเป็นก่อนส่ง Auth และแปลงข้อผิดพลาดให้เป็นข้อความที่เข้าใจได้ โดยไม่เปิดเผยรายละเอียดภายใน”

ทำบนมือถือ: แสดงการตรวจช่องอีเมล/รหัสผ่านว่าง แล้วแสดงกรณีเข้าสู่ระบบไม่สำเร็จ; จากนั้นกลับหน้า login ปกติ

## 4. CRUD Create

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\chat\chat_screens.dart`, `D:\RELIO_Mobile\lib\core\repositories\local_repositories.dart`

ชี้: `ChatRoomScreen._send()` และ `DriftMessageRepository.createOutgoingText()`

พูด: “เมื่อส่งข้อความ UI เรียก Repository ให้บันทึกข้อความใน SQLite ก่อนส่งต่อ transport”

ทำบนมือถือ: เปิดบทสนทนาที่ต้องการและส่งข้อความสาธิตที่ได้รับอนุมัติหนึ่งข้อความ; ยืนยันว่าข้อความปรากฏในห้องสนทนา

## 5. CRUD Read

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\chat\chat_screens.dart`, `D:\RELIO_Mobile\lib\core\repositories\local_repositories.dart`

ชี้: `ChatRoomScreen` และ `DriftMessageRepository.watchMessages()`

พูด: “หน้าสนทนาสังเกต stream จาก Repository จึงอ่านข้อมูล local ที่ persist ไว้ ไม่ได้สร้างข้อความขึ้นมาสำหรับภาพสาธิต”

ทำบนมือถือ: ออกจากห้องสนทนาแล้วเปิดห้องเดิมใหม่; ตรวจว่าข้อความเดิมยังแสดง

## 6. CRUD Update

เปิดไฟล์: `D:\RELIO_Mobile\lib\core\sync\sync_engine.dart`, `D:\RELIO_Mobile\lib\core\repositories\local_repositories.dart`

ชี้: `SyncEngine.run()` และ `DriftMessageRepository.updateCloudSyncStatus()`

พูด: “Cloud sync กับ Nearby delivery เป็นคนละสถานะ; การซิงก์สำเร็จไม่ได้แปลว่าส่งถึง peer ผ่าน Nearby แล้ว”

ทำบนมือถือ: ใช้ผลสาธิตที่มีอยู่เพื่ออธิบายการเปลี่ยน Cloud queue จาก pending เป็น completed เมื่อเครือข่ายกลับมา; อย่าสร้างรายการซ้ำเพื่อถ่ายคลิป

## 7. CRUD Delete

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\chat\chat_screens.dart`, `D:\RELIO_Mobile\lib\core\repositories\local_repositories.dart`

ชี้: `ChatRoomScreen._confirmDeleteDemoMessage()` และ `DriftMessageRepository.deleteWeek3DemoMessage()`

พูด: “การลบข้อความสาธิตจำกัดเฉพาะรายการที่อนุญาตและยังไม่ซิงก์; UI ขอการยืนยันก่อนลบ local row กับคิว”

ทำบนมือถือ: ถ้ามี marker ที่ลบได้อยู่แล้ว ให้แสดง dialog โดยยังไม่ยืนยันลบ; ห้ามลบข้อความใช้งานจริง

## 8. Offline / local-first

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\chat\chat_screens.dart`, `D:\RELIO_Mobile\lib\core\repositories\local_repositories.dart`, `D:\RELIO_Mobile\lib\core\sync\sync_engine.dart`

ชี้: ลำดับใน `_send()` จาก `createOutgoingText()` ไป `nearbyService.sendMessage()` และคิว `SyncQueue`

พูด: “RELIO เก็บข้อมูลในเครื่องก่อน; Internet, Nearby และ Cloud Sync มีสถานะแยกกัน”

ทำบนมือถือ: ชี้สถานะเครือข่ายจริงบน Home และอธิบาย pending/synced ที่มีอยู่แล้ว; ไม่เปลี่ยน network settings ระหว่างถ่าย

## 9. Vertical Slice

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\chat\chat_screens.dart`, `D:\RELIO_Mobile\lib\core\repositories\local_repositories.dart`, `D:\RELIO_Mobile\lib\core\sync\sync_engine.dart`, `D:\RELIO_Mobile\lib\core\cloud\supabase_cloud_data_source.dart`

ชี้: `_send()` → `DriftMessageRepository` → Drift/SQLite → `SyncQueue` → `SyncEngine` → `SupabaseCloudDataSource.upsertMessage()`

พูด: “ข้อความ UUID `cb49bccb-05f3-4f03-9884-2b82b3035ef7` ตรวจพบโดยตรงใน RELIO-QA `public.messages` แล้ว เป็นหลักฐานปลายทางของเส้นทาง UI → Drift/SQLite → Sync Queue → SyncEngine → Supabase”

ทำบนมือถือ: ใช้เฉพาะ record เดิมที่มีอยู่; ไม่สร้าง `W3VERTICAL` เพิ่ม

## 10. Local schema

เปิดไฟล์: `D:\RELIO_Mobile\lib\core\database\app_database.dart`

ชี้: Drift tables `Conversations`, `Messages`, `Attachments`, `SyncQueue`, `SosEvents`, `CloudConversationLinks`, `NearbyDevices`, `AppSettings`, `RelayPackets` และ `RelayForwardHistory` พร้อม primary keys ที่ประกาศในแต่ละ table

พูด: “SQLite เป็น source of truth ในเครื่อง; ความสัมพันธ์บางรายการใช้ logical ID และไม่ได้ประกาศเป็น SQL foreign key”

ทำบนมือถือ: เปิดหน้า Chat/Sync เพื่อประกอบคำอธิบายกับข้อมูลแอป; ไม่แก้ SQLite โดยตรง

## 11. Cloud schema

เปิดไฟล์: `D:\RELIO_Mobile\supabase\migrations\0001_initial_schema.sql`, `D:\RELIO_Mobile\supabase\migrations\0005_communication_platform.sql`, `D:\RELIO_Mobile\supabase\migrations\0007_cloud_direct_chat.sql`

ชี้: ตารางหลัก `profiles`, `devices`, `conversations`, `conversation_members`, `messages`, `attachments`, `sos_events` และ `message_receipts`; migrations ภายหลังเพิ่ม policy/RPC และตาราง Cloud เพิ่มเติม

พูด: “Cloud schema มาจาก migration; direct chat ใช้ membership ที่จัดการฝั่ง server และ RLS จำกัดการอ่านตามสิทธิ์สมาชิก”

ทำบนมือถือ: แสดงสถานะบัญชี/Cloud ในแอปโดยไม่เปิด credential, token หรือข้อมูลบัญชีส่วนตัว

## 12. Chat

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\chat\chat_screens.dart`

ชี้: `ChatListScreen`, `ChatRoomScreen` และ `ChatRoomScreen._send()`

พูด: “ข้อความแสดงจากข้อมูลที่ผ่าน Repository; สถานะข้อความในหน้าจอไม่ใช่หลักฐานว่า Nearby เชื่อมต่ออยู่”

ทำบนมือถือ: เปิด Chat list และบทสนทนาที่มีอยู่; ไม่ส่งข้อความใหม่ระหว่างการบันทึกช่วงนี้

## 13. SOS

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\sos\sos_screens.dart`

ชี้: `SOSScreen._openSOS()` และ `SOSActiveScreen`

พูด: “การเปิด SOS ต้องยืนยันก่อน จึงเริ่มอ่านตำแหน่งและบันทึกเหตุ”

ทำบนมือถือ: เปิดหน้า SOS และอธิบายขั้นตอน; อย่ายืนยันเปิดเหตุจริง

## 14. Rescue

เปิดไฟล์: `D:\RELIO_Mobile\lib\features\rescue\rescue_screen.dart`

ชี้: `RescueScreen._toggle()` และ dialog ยืนยันการเปิดโหมด

พูด: “Rescue เป็นสถานะแยกจาก SOS และจะแสดงต่อ peer หลังผู้ใช้ยืนยัน”

ทำบนมือถือ: เปิดหน้า Rescue และอธิบายปุ่ม; ไม่ยืนยันเปิดสถานะจริง

## หมายเหตุ Cloud สำหรับผู้บรรยาย

Local evidence ของ UUID `cb49bccb-05f3-4f03-9884-2b82b3035ef7` แสดง `cloud_sync_status=synced` และ `messageUpsert=completed`; ยังไม่มี direct read-only proof ว่า row ตรงกันอยู่ใน RELIO-QA `public.messages` เพราะ HTTPS จาก workstation ไปไม่ถึง HTTP response จึงห้ามกล่าวอ้างว่า Cloud row ผ่านการตรวจแล้ว
