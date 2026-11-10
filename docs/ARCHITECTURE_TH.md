# สถาปัตยกรรม RELIO

## จากเปิดแอปถึงการส่งข้อมูล

[main.dart](../lib/main.dart) รอให้ Flutter binding พร้อมและโหลดธีมจาก preferences แล้วเรียก `runApp` [RelioApp](../lib/app/app.dart) สร้าง [RelioDependencies](../lib/core/relio_dependencies.dart) และสังเกต lifecycle [Router](../lib/app/router.dart) เริ่มที่ `/startup` และใช้สถานะ auth และ recovery ตัดสิน redirect ส่วน dependency scope ส่งบริการไปยังหน้าจอโดยไม่ให้ UI เรียก native transport โดยตรง

~~~mermaid
flowchart LR
  UI["หน้าจอ Flutter"] --> R["Repository / Service"]
  R --> DB["Drift / SQLite"]
  DB --> N["NearbyService และ RelayEngine"]
  N --> AND["Android bridge / Nearby transport"]
  DB --> S["SyncEngine"]
  S --> C["CloudDataSource / Supabase"]
~~~

[OwnerContext](../lib/core/identity/owner_context.dart) แยก principal ของบัญชีและ Guest ออกจาก device ID และ endpoint ID เปลี่ยนบัญชีแล้วงาน async เก่าต้องผ่านการตรวจบริบทก่อนเขียนหรือซิงก์ Guest มีข้อมูลในเครื่องและ Cloud backup เฉพาะกรณีที่การตั้งค่าและตัวตนรองรับ การกู้รหัสผ่านใช้สถานะ recovery แยกจาก session ปกติ

## Nearby, Direct และ Relay

[NearbyService](../lib/core/nearby/nearby_service.dart) ประสาน discovery, advertising, permission และ handshake [AndroidNearbyTransport](../lib/core/nearby/android_nearby_transport.dart) ใช้ Nearby Connections จาก dependency ใน `third_party/nearby_connections` Android ที่เปิด diagnostics มีทางเลือก Bluetooth Classic ผ่าน [compatibility transport](../lib/core/nearby/bluetooth_classic_transport.dart) ความพร้อมของ Bluetooth, Wi-Fi และสิทธิ์ตาม Android มีผลต่อการค้นหาและเชื่อมต่อ แอปไม่ได้ใช้ Internet เป็นตัวบ่งชี้ว่า peer อยู่ใกล้

`hello` ผูก endpoint กับ device และ capability การรับข้อมูล private ตรวจ principal และปลายทางตามเส้นทางที่รองรับ การอนุมัติและ trust ช่วย reconnect กับ peer ที่ยืนยันตัวตนตรงกับ pin และล้างสิทธิ์อัตโนมัติได้เมื่อเลิก trust การเห็นชื่อซ้ำหรือ endpoint เดิมไม่เพียงพอสำหรับจับคู่แชต

[RelayEngine](../lib/core/relay/relay_engine.dart) ใช้เส้นทางตรงก่อนเมื่อมี และคำนวณ next hop ด้วย [RelayRoutePlanner](../lib/core/relay/relay_route_planner.dart) ตามนโยบายและ peer ที่พร้อม ซอง `relay-v1` มี `packetId`, `payloadId`, `destinationDeviceId`, TTL และ hop count ค่าเริ่มต้น TTL 15 นาทีและ 3 hops ส่วน QA Automatic Text อนุญาตสูงสุด 8 hops ตาม [RelayPolicy](../lib/core/relay/relay_models.dart) ค่าเหล่านี้เป็นเพดานซอฟต์แวร์ ภาคสนามยังขึ้นกับ topology, เวอร์ชันของทุกเครื่อง และการเชื่อมจริง

เครื่องกลางบันทึกซองและ forward history เพื่อหลีกเลี่ยงการวนและประมวลผลซ้ำ `stored` และ `forwarded` มีความหมายต่างจาก `delivered` เมื่อได้รับ receipt ปลายทาง ACK อาจย้อนผ่าน peer เดิมและลองใหม่ภายในข้อจำกัดของซอง QA relay receipt ไม่ใช่หลักฐานลายเซ็น end-to-end สำหรับทุก topology ดู [protocol](NEARBY_PROTOCOL.md) และ [ผล Build 39](AUTOMATIC_TEXT_RELAY_BUILD39_ACCEPTANCE.md) กับ [Build 43](BUILD43_ONLINE_AUTH_RELAY_ACCEPTANCE_20261028.md) เป็นหลักฐานเฉพาะรุ่น

## Chat, SOS, Rescue และการแจ้งเตือน

[Chat](../lib/features/chat/chat_screens.dart) อ่านจาก SQLite และให้ repository จัดการข้อความ ผู้ส่ง ผู้รับ และสถานะ ข้อความและพิกัดใช้ packet ตามประเภท รูปและวิดีโอใช้ file payload และจับคู่กับ attachment ผ่าน `transferId` การ preview/thumbnail ทำในเครื่องตามขอบเขตของสื่อ Relay สำหรับข้อความไม่ส่งไฟล์สื่อไปตาม hop

[SOS](../lib/features/sos/sos_screens.dart) เริ่มจากการยืนยันและเก็บ event พร้อมสถานะและตำแหน่งเมื่ออนุญาต [Rescue](../lib/features/rescue/rescue_screen.dart) แสดงคำขอและสถานะตอบรับ รายชื่อฉุกเฉินและโปรไฟล์สุขภาพแยกตาม principal การแสดงหน้ารายละเอียดไม่อนุญาตเปิดเผยข้อมูลสุขภาพโดยปริยาย ประวัติ SOS ที่ซ่อนในเครื่องไม่หยุดเหตุที่ยัง active [Local notifications](../lib/core/notifications/local_notification_service.dart) และ foreground service ของ Android ขึ้นกับสิทธิ์และ lifecycle ระบบหยุดทำงานได้เมื่อ process ถูกปิดหรือวิทยุถูกปิด

<a id="database"></a>
## Drift และ SQLite

[AppDatabase](../lib/core/database/app_database.dart) มี schema version 14 และ migration สำหรับข้อมูลเดิม ตารางด้านล่างใช้ชื่อ SQL แบบ snake_case คอลัมน์เชื่อมเป็นความสัมพันธ์เชิงตรรกะที่ repository ใช้ ภาพแสดงการเชื่อมข้อมูลที่ repository ใช้โดยไม่ได้ระบุข้อบังคับ foreign key

| ตาราง | Primary key | หน้าที่ |
| --- | --- | --- |
| `conversations` | `id` | ห้องสนทนาและ unread |
| `messages` | `id` | ข้อความและสถานะ แยก `conversation_id`, `delivery_status`, `cloud_sync_status` |
| `attachments` | `id` | ไฟล์ผ่าน `message_id`, `transfer_id` และสถานะ metadata/file |
| `conversation_aliases` | `conversation_id` | ตาราง SQL ของ schema 14 ชี้ห้องเดิมไปที่ `canonical_id` |
| `cloud_conversation_links` | `local_conversation_id, owner_user_id` | เชื่อม local กับ cloud conversation และเก็บ cursor ข้อความ/receipt |
| `nearby_devices` | `device_id` | ข้อมูล peer, trust และ last seen |
| `sync_queue` | `id` | งาน Cloud แยก owner และ `next_attempt_at` |
| `relay_packets` | `packet_id` | ซอง relay, state, TTL และจำนวน hop |
| `relay_forward_history` | `packet_id, target_device_id` | ประวัติการส่งต่อ/จำนวนครั้ง |
| `sos_events` | `id` | เหตุ SOS, active flag และสถานะส่ง |
| `sos_history_entries` | `viewer_principal_id, event_id` | ประวัติและสถานะซ่อนแยกผู้ดู |
| `app_settings` | `key` | ค่าของแอป |
| `emergency_contacts`, `emergency_profiles` | `id`, `principal_id` ตามลำดับ | ข้อมูลฉุกเฉินในเครื่อง |

~~~mermaid
erDiagram
  CONVERSATIONS ||--o{ MESSAGES : "conversation_id"
  MESSAGES ||--o{ ATTACHMENTS : "message_id"
  CONVERSATIONS ||--o{ CLOUD_CONVERSATION_LINKS : "local_conversation_id"
  RELAY_PACKETS ||--o{ RELAY_FORWARD_HISTORY : "packet_id"
  SOS_EVENTS ||--o{ SOS_HISTORY_ENTRIES : "event_id"
~~~

[Conversation reconciliation](../lib/core/database/conversation_reconciliation.dart) และ [repositories](../lib/core/repositories/local_repositories.dart) ตรวจตัวตนของคู่สนทนาและรวมข้อมูลเดิมอย่างระวัง ชื่อที่แสดงไม่ใช่ตัวระบุสำหรับ merge สถานะข้อความ Nearby และ Cloud เก็บแยกกัน

## Supabase, การสำรอง และ Offline Map

[Supabase adapter](../lib/core/cloud/supabase_cloud_data_source.dart) ซ่อน SDK หลัง CloudDataSource ส่วน [SyncEngine](../lib/core/sync/sync_engine.dart) ใช้ SQLite queue ตรวจ owner ของงานและ session ก่อน push/pull เมื่อออฟไลน์เก็บงานไว้แล้วรอ retry สถานะคิวมี pending, processing, completed และ failed การสำรองส่วนตัวต่างจาก Cloud chat ที่ตรวจ membership ตาม [migrations](../supabase/migrations/) และ Storage policy ห้ามใส่ service-role secret ในแอป รายชื่อฉุกเฉินและโปรไฟล์สุขภาพเป็นข้อมูล local ตามนโยบายที่รองรับ ทดสอบขอบเขตด้วย [FakeCloudDataSource](../lib/core/cloud/fake_cloud_data_source.dart) ได้โดยไม่ใช้ backend จริง

[PackagedMapService](../lib/core/location/packaged_map_service.dart) ขอให้ Android เตรียม PMTiles, style, sprites และ glyphs จาก asset ลง app-private storage จึงเปิดแผนที่ออฟไลน์หลังเตรียมเสร็จ ใช้พื้นที่เพิ่มประมาณ 601 MB และมีข้อมูล native ถึง z15 Nearby list ยังแยกจากการเตรียม map การแชร์พิกัดเป็นการกระทำครั้งเดียวตามสิทธิ์ ไม่ใช่การติดตามต่อเนื่อง ดู [ที่มาและข้อจำกัดแผนที่](../assets/maps/README.md)

Android [manifest](../android/app/src/main/AndroidManifest.xml) ระบุสิทธิ์ Bluetooth scan/connect/advertise, Wi-Fi, ตำแหน่ง, แจ้งเตือนและ foreground service ตามเวอร์ชันระบบ Developer Mode ผูกกับ environment และ preference ผ่าน [InternalExperienceController](../lib/core/developer/internal_experience_controller.dart) Demo และ diagnostics ไม่ใช่ผลภาคสนาม
