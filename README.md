# RELIO Mobile

RELIO เป็นโปรเจกต์วิชา Mobile Application สำหรับศึกษาการสื่อสารเมื่ออินเทอร์เน็ตไม่เสถียรหรือใช้งานไม่ได้ ออกแบบให้ผู้ใช้ Android บันทึกข้อมูลและสื่อสารกับอุปกรณ์ที่อยู่ใกล้กันได้ในสถานการณ์ทั่วไปหรือฉุกเฉิน ผู้ใช้ต้องอนุญาตให้แอปเข้าถึงวิทยุและยืนยันการเชื่อมต่อเมื่อจำเป็น โครงการนี้เป็นซอฟต์แวร์สำหรับศึกษาและทดสอบภาคสนาม การส่ง SOS ขึ้นกับเส้นทางที่มีอยู่และไม่ได้แจ้งหน่วยกู้ภัยสาธารณะอัตโนมัติ

## สารบัญ

- [ความสามารถ](#features)
- [เทคโนโลยีและโครงสร้าง](#structure)
- [การทำงานของแอป](#flow)
- [Nearby, Relay, Chat และ SOS](#communication)
- [ฐานข้อมูลและ Cloud](#storage)
- [ติดตั้ง สร้าง APK และทดสอบ](#setup)
- [Developer Mode และข้อจำกัด](#qa)
- [ประวัติและเอกสาร](#history)
- [สิทธิ์การใช้งาน](#license)

<a id="features"></a>
## ความสามารถ

| ฟีเจอร์ | การทำงานปัจจุบัน |
| --- | --- |
| Nearby และ Direct | ค้นหาและประกาศตัวผ่าน Android transport จับคู่ ยืนยันตัวตน และสื่อสารตรงกับ peer ที่จับคู่แล้ว |
| Automatic Relay และ Multi-Hop | พยายามส่งตรงก่อน แล้วเลือกเส้นทางส่งต่อสำหรับ payload ที่นโยบายอนุญาต เครื่องกลางเก็บซองและลองส่งต่อเมื่อมีลิงก์ |
| Chat | บันทึกข้อความในเครื่อง ส่งข้อความ ตำแหน่ง รูปและวิดีโอตามเส้นทางที่รองรับ แสดงสถานะการรับและสถานะ Cloud แยกกัน |
| SOS และ Rescue | ผู้ใช้ยืนยันเริ่มและหยุด SOS ได้ แอปแสดงคำขอและสถานะตอบรับ ตำแหน่งขึ้นกับสิทธิ์และความสดของข้อมูล |
| Maps | แผนที่ประเทศไทยแบบ offline มีรายละเอียดตามข้อมูลต้นทางถึง z15 ภาพที่ซูมต่อถึง z18 ใช้ข้อมูล z15 เดิม |
| Guest, โปรไฟล์และ Settings | เริ่มใช้ในเครื่องได้ มีธีม โปรไฟล์ รายชื่อฉุกเฉิน และข้อมูลแยกตามตัวตน Guest/บัญชี |
| Cloud Backup และ Sync | Supabase รองรับบัญชีและการซิงก์ข้อมูลตามเจ้าของเมื่อมีการตั้งค่าและอินเทอร์เน็ต คิวคงอยู่ใน SQLite เมื่อออฟไลน์ |

<a id="structure"></a>
## เทคโนโลยีและโครงสร้าง

| เทคโนโลยี | หน้าที่ | ตำแหน่ง |
| --- | --- | --- |
| Flutter, Dart, go_router | UI, lifecycle และเส้นทางหน้าจอ | [lib/app](lib/app/) |
| Drift, SQLite | แหล่งข้อมูลหลักในเครื่องและ migration | [lib/core/database](lib/core/database/) |
| Kotlin, Android, Nearby Connections | permission, native bridge และ transport; ใช้ปลั๊กอินที่รวมมากับ repo | [android](android/), [third_party](third_party/) |
| MapLibre, PMTiles, geolocator | แผนที่เวกเตอร์และตำแหน่งตามสิทธิ์ | [assets/maps](assets/maps/), [lib/features/nearby](lib/features/nearby/) |
| Supabase | Auth, RPC, RLS, Storage และ Sync | [lib/core/cloud](lib/core/cloud/), [supabase](supabase/) |
| shared_preferences, image_picker | จำธีมและเลือกสื่อ | [pubspec.yaml](pubspec.yaml) |

~~~text
lib/
  main.dart                 โหลดธีมและเริ่ม RelioApp
  app/                      Router, environment และธีม
  core/                     services, database, repositories และ transport
  features/                 หน้าจอ Chat, Nearby, SOS, Rescue, Settings และอื่น ๆ
  shared/                   widgets ใช้ร่วมกัน
android/                    Kotlin bridge, manifest, flavors และ Gradle Wrapper
assets/                     branding, ฟอนต์, map style, sprites, glyphs และ PMTiles
test/                       automated tests และ golden images
supabase/                   migrations และ Edge Functions
third_party/                local dependency ของ Nearby
scripts/                    งาน build, deploy และตรวจ QA
docs/                       เอกสารและแผนทดสอบ
~~~

<a id="flow"></a>
## การทำงานของแอป

`main.dart` โหลดธีม จากนั้น `RelioApp` สร้าง `RelioDependencies` และ Router เริ่มที่ `/startup` เพื่อรอสถานะบัญชี เมื่อใช้ Guest หรือบัญชีแล้ว หน้าแอปอ่านข้อมูลผ่าน repositories ส่วน Nearby, Relay และ Sync เริ่มตาม lifecycle และเงื่อนไขสิทธิ์ของแต่ละบริการ

~~~mermaid
flowchart TD
  A["main.dart โหลดธีม"] --> B["RelioApp และ RelioDependencies"]
  B --> C["ตรวจบัญชีและข้อมูลในเครื่อง"]
  C --> D["Router: Welcome, Guest หรือหน้าหลัก"]
  D --> E["หน้าจอและ repositories"]
  E --> F["Drift / SQLite"]
  F --> G["Nearby / Direct / Relay"]
  F --> H["Cloud Sync เมื่อบัญชีและเครือข่ายพร้อม"]
~~~

<a id="communication"></a>
## Nearby, Relay, Chat และ SOS

Discovery พบ endpoint ชั่วคราว ส่วน advertising ประกาศอุปกรณ์ให้ผู้อื่นพบ หลังเชื่อมต่อ แอปรอ `hello` และตรวจ identity ก่อนรับข้อมูล private แยก endpoint ID, RELIO device ID และ principal ของผู้ใช้ ผู้ที่เคยอนุญาตจะ reconnect อัตโนมัติได้ตามนโยบายและหลักฐาน identity ที่บันทึกไว้

~~~mermaid
flowchart LR
  A["A: ส่งข้อความ"] -->|ซอง relay-v1| B["B: เก็บและส่งต่อ"]
  B -->|เมื่อเชื่อมได้| C["C: ผู้รับ"]
  C -.->|ACK| B
  B -.->|ส่ง ACK กลับ| A
~~~

Relay ใช้ ID เดิมป้องกันข้อมูลซ้ำ จำกัด TTL และจำนวน hop หลีกเลี่ยงลูป และลองใหม่ตามเงื่อนไขของระบบ ค่าเริ่มต้นคือ TTL 15 นาทีและ 3 hops โดย QA Automatic Text มีเพดานแยก 8 hops การเก็บซองในเครื่องกลางยังไม่เท่ากับผู้รับได้รับข้อความ แยก presence จาก receipt และสถานะ Cloud

Chat เขียน SQLite ก่อนส่ง ข้อความและตำแหน่งใช้ packet ตามประเภท รูปและวิดีโอใช้ file payload บนลิงก์ที่รองรับ SOS มีลำดับก่อน Rescue ในโหมดฉุกเฉิน การบันทึกประวัติ การซ่อนรายการ และการหยุด SOS เป็นคนละการกระทำ รายละเอียดสุขภาพและรายชื่อฉุกเฉินเป็นข้อมูลอ่อนไหวของเจ้าของ ดู [สถาปัตยกรรม](docs/ARCHITECTURE_TH.md) สำหรับขอบเขตและเส้นทาง ACK

<a id="storage"></a>
## ฐานข้อมูลและ Cloud

Drift schema ปัจจุบันคือ 14 ตาราง `conversations` เชื่อมเชิงตรรกะกับ `messages.conversation_id` ส่วน `attachments.message_id` ผูกไฟล์กับข้อความ `cloud_conversation_links` เก็บ mapping และ cursor แยกตามบัญชี `sync_queue` เก็บงานที่รอและ `relay_packets` เก็บซองสำหรับส่งต่อ ดู [ตารางและ ER diagram](docs/ARCHITECTURE_TH.md#database)

Cloud เป็นตัวเลือก เมื่อเปิดใช้ `SyncEngine` ตรวจ owner ก่อนทำงาน ใช้สถานะ `pending`, `processing`, `completed`, `failed` และกำหนดเวลาลองใหม่ ข้อมูล Guest และข้อมูลฉุกเฉินที่เป็น local-only ใช้ได้โดยไม่ต้องมีบัญชี การสำรองส่วนตัวและการแชร์ผ่าน Cloud เป็นคนละกรณีและอยู่ภายใต้เงื่อนไขบัญชี นโยบายเซิร์ฟเวอร์ และการยินยอมที่รองรับ

<a id="setup"></a>
## ติดตั้ง สร้าง APK และทดสอบ

ใช้ Windows PowerShell, Flutter stable ที่มี Dart ตาม `^3.12.2`, Android SDK/Platform Tools, JDK 17 ขึ้นไปที่รองรับ Gradle 9.1.0 และ Git LFS ติดตั้งแผนที่ตาม [คู่มือตั้งค่า](docs/DEVELOPMENT_TH.md#map-setup) ก่อนรัน

~~~powershell
Set-Location D:\RELIO_Mobile
flutter doctor -v
flutter pub get
flutter devices
flutter run --flavor dev --dart-define=RELIO_ENV=development
~~~

DEV เป็นจุดเริ่มต้นสำหรับผู้ตรวจงาน สำหรับคำสั่ง QA Debug/Release, signing, VersionCode, ADB แบบระบุ serial และการติดตั้งทับอย่างปลอดภัย ดู [คู่มือ Build และ ADB](docs/DEVELOPMENT_TH.md#android-build) เปิด USB Debugging และตรวจ serial ก่อนทุกครั้ง

ใช้ [รายการทดสอบ](docs/DEVELOPMENT_TH.md#test-cases) เพื่อตรวจ Guest ในเครื่อง, Direct สองเครื่อง, Relay สามเครื่อง, ACK, SOS, Offline Map และ Sync แยกผลจำลอง ผลทดสอบจริง และข้อที่ยังต้องตรวจ

<a id="qa"></a>
## Developer Mode และข้อจำกัด

Developer Mode เปิดจาก Settings ใน environment ที่อนุญาตและจำค่าในเครื่อง มี Demo, Nearby, Cloud และ Relay diagnostics โดยค่าเริ่มต้นปิด QA-only Internet simulator และ public QA update มี gate ของ TEST แยกต่างหาก Production ปิด developer diagnostics ผ่าน `RelioBuildInfo`

- การทดสอบวิทยุต้องใช้ Android และสิทธิ์ที่เหมาะสม ข้อจำกัดแบตเตอรี่ การปิดวิทยุ Force stop หรือ process death อาจตัดการส่งต่อ
- Store-and-forward มีเพดาน hop/TTL และต้องมี peer ที่เข้ากันได้ จึงไม่รับประกันระยะหรือการส่งสำเร็จ รูปและวิดีโอไม่ได้ผ่าน text relay
- มีหลักฐานทดสอบจริงเฉพาะบางกรณีของ Build 39 และ 43 เอกสารเหล่านั้นแสดงผลตามรุ่น การติดตั้งและการทดสอบครบสามเครื่องสำหรับ Build 84 ยังไม่มีหลักฐานยืนยันในรอบนี้
- Cloud ต้องมีอินเทอร์เน็ตและ backend ที่ตั้งค่าแล้ว ผลจาก FakeCloud ไม่แทนผลการทดสอบเซิร์ฟเวอร์จริง

<a id="history"></a>
## ประวัติและเอกสาร

`main` คือ branch สำหรับส่งงาน ส่วน `master` เป็น default branch บน GitHub ณ วันที่ตรวจและเก็บสายงานเผยแพร่ QA เดิม `feature/*` และ `fix/*` เก็บการพัฒนาจริงตามงาน `codex/automatic-relay-and-map-freshness` คือ branch ที่ใช้เตรียม source ปัจจุบัน ดู [Git Workflow และประวัติ](docs/GIT_WORKFLOW_TH.md) ก่อนเลือก branch จากหน้า GitHub

- [สถาปัตยกรรมและฐานข้อมูล](docs/ARCHITECTURE_TH.md)
- [ติดตั้ง สร้าง และทดสอบ](docs/DEVELOPMENT_TH.md)
- [Git และ GitHub](docs/GIT_WORKFLOW_TH.md)
- [Nearby protocol](docs/NEARBY_PROTOCOL.md)
- [ขั้นตอนทดสอบด้วยอุปกรณ์](docs/MANUAL_DEVICE_TESTS.md)
- [หลักฐาน Automatic Relay Build 39](docs/AUTOMATIC_TEXT_RELAY_BUILD39_ACCEPTANCE.md)
- [ที่มาและเงื่อนไขการใช้แผนที่](assets/maps/README.md)

<a id="license"></a>
## สิทธิ์การใช้งาน

ไม่พบไฟล์ LICENSE สำหรับ RELIO ที่ root ของ repository การเข้าถึง source เพื่อประเมินงานไม่ใช่การอนุญาตให้นำไปใช้ซ้ำ ให้ติดต่อเจ้าของโครงการก่อนเผยแพร่ต่อ ส่วน dependency และข้อมูลแผนที่ใช้เงื่อนไขของผู้ให้บริการตามไฟล์ license และ attribution ของแต่ละชุด
