# RELIO

RELIO เป็นแอป Flutter สำหรับสื่อสารกับอุปกรณ์ Android ที่อยู่ใกล้กันในช่วงที่อินเทอร์เน็ตใช้งานไม่ได้หรือไม่เสถียร ข้อมูลหลักถูกเก็บไว้ในเครื่องก่อน แล้วจึงส่งผ่าน Nearby หรือซิงก์กับ Cloud เมื่อพร้อม

โปรเจกต์นี้พัฒนาขึ้นเพื่อทดลองแนวคิดการสื่อสารแบบ offline-first สำหรับแชท การขอความช่วยเหลือ และการส่งข้อความต่อผ่านโทรศัพท์เครื่องกลาง โดยเน้นให้สถานะที่แสดงในแอปตรงกับสิ่งที่เกิดขึ้นจริง

## RELIO คืออะไร?

โทรศัพท์ที่ติดตั้ง RELIO สามารถค้นหาและเชื่อมต่อกันผ่านการสื่อสารระยะใกล้ เมื่อเชื่อมต่อสำเร็จ ผู้ใช้สามารถส่งข้อความ ไฟล์ขนาดจำกัด ตำแหน่ง และสถานะช่วยเหลือได้โดยไม่ต้องพึ่งการเชื่อมต่ออินเทอร์เน็ตตามปกติ

ฐานข้อมูล SQLite ในเครื่องเป็นแหล่งข้อมูลหลักของแอป การส่ง Nearby และ Cloud เป็นขั้นตอนที่ตามหลังการบันทึกข้อมูล จึงยังเปิดดูข้อมูลเดิมและติดตามรายการที่รอส่งได้เมื่อการเชื่อมต่อขาดหาย

## ฟีเจอร์หลัก

- ค้นหา เชื่อมต่อ และยืนยันตัวตนอุปกรณ์ RELIO ที่อยู่ใกล้กัน
- แชทแบบ local-first พร้อมสถานะรอส่ง ส่งผ่าน Nearby และ ACK
- ส่งรูปภาพ วิดีโอ และตำแหน่งผ่านการเชื่อมต่อ Nearby โดยมีการตรวจชนิดและขนาดไฟล์
- โหมด SOS และ Rescue พร้อมขั้นตอนยืนยันก่อนเปิดใช้งาน
- Nearby Map และมุมมองรายการอุปกรณ์ พร้อมตำแหน่งล่าสุดที่ผู้ใช้เลือกแชร์
- Relay v1 สำหรับส่งต่อข้อความ ตำแหน่ง และ SOS แบบจำกัดจำนวน hop พร้อม TTL และ deduplication
- โปรไฟล์ ธีม รายชื่อผู้ติดต่อฉุกเฉิน และประวัติการสนทนาที่แยกตามเจ้าของข้อมูล
- Cloud sync แบบเลือกใช้ผ่าน Supabase โดย SQLite ในเครื่องยังเป็นข้อมูลหลัก
- QA diagnostics สำหรับตรวจ Nearby, Relay และสถานะระบบ โดยแยกออกจาก PROD

แผนที่ใช้ MapLibre แบบ lazy loading การค้นหาอุปกรณ์ แชท และ Relay ยังทำงานได้เมื่อ map style โหลดไม่สำเร็จ แต่ tile แผนที่จากเครือข่ายจะไม่พร้อมแบบออฟไลน์หากยังไม่มี cache หรือข้อมูลออฟไลน์

## RELIO ทำงานอย่างไร?

กรณีเชื่อมต่อโดยตรง โทรศัพท์ A ส่งข้อมูลให้โทรศัพท์ B ผ่าน Nearby transport หลังจากทั้งสองฝั่งยืนยัน device identity และ principal ของผู้ใช้แล้ว

Relay ใช้แนวคิด store-and-forward เช่น A → B → C โดย B รับและเก็บ envelope ก่อนส่งต่อให้ C แต่ละ hop มี ACK ของตัวเอง พร้อมจำกัด TTL, จำนวน hop และการส่งซ้ำ สื่อไบนารีอย่างรูปหรือวิดีโอยังไม่ถูกส่งต่อผ่าน Relay

QA Relay Tester สามารถ pin เครื่องกลางสำหรับ synthetic probe ได้ แม้ A และ C จะมีลิงก์ตรงอยู่ probe นั้นจะส่งไปยัง B เป็น first hop โดยไม่เปลี่ยน routing ของแชทหรือ SOS ปกติ

## เทคโนโลยีที่ใช้

- **Flutter / Dart** — UI และ application logic โดยเน้น Android เป็นหลัก
- **Drift + SQLite** — เก็บข้อความ โปรไฟล์ อุปกรณ์ที่เชื่อถือ คิว sync และ relay state ในเครื่อง
- **Nearby Connections** — transport หลักสำหรับสื่อสารระหว่างอุปกรณ์ Android ใกล้กัน
- **MapLibre** — แสดง Nearby Map โดยเริ่มทำงานเมื่อผู้ใช้เปิดแผนที่
- **go_router** — จัดการ navigation ของแอป
- **Supabase** — authentication, optional cloud sync และ storage boundary
- **Firebase** — ใช้กับ QA distribution, diagnostics และการตั้งค่า QA ที่แยกจาก PROD

รายละเอียดโครงสร้างอยู่ใน [docs/architecture.md](docs/architecture.md) และ protocol อยู่ใน [docs/NEARBY_PROTOCOL.md](docs/NEARBY_PROTOCOL.md)

## วิธีรันโปรเจกต์

ต้องมี Flutter stable, Android SDK และอุปกรณ์หรือ emulator ที่ตั้งค่าไว้แล้ว จากโฟลเดอร์โปรเจกต์ให้รัน:

```powershell
flutter pub get
flutter run --flavor dev --dart-define=RELIO_ENV=development
```

ตรวจ source และ automated tests:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub --reporter compact
```

สร้าง DEV debug APK:

```powershell
flutter build apk --flavor dev --debug --dart-define=RELIO_ENV=development
```

การสร้าง QA ต้องใช้ configuration และ signing ที่เก็บไว้เฉพาะเครื่องผู้พัฒนา สคริปต์นี้จะตรวจ format, analyze, tests, QA/PROD isolation, package และ signer ก่อนสร้าง artifact โดยไม่ upload:

```powershell
.\scripts\deploy-test.ps1 -NoUpload
```

ห้ามนำ signing key, password, token หรือไฟล์ local environment ขึ้น repository ดูขั้นตอน QA เพิ่มเติมได้ที่ [docs/QA_RELEASE_WORKFLOW.md](docs/QA_RELEASE_WORKFLOW.md)

## การทดสอบ

ชุดทดสอบปกติใช้ Mock transport และ Fake Cloud เพื่อให้รันได้โดยไม่ต้องเชื่อมอินเทอร์เน็ต มี test ครอบคลุม persistence, identity isolation, Nearby handshake, chat, media, Relay, SyncEngine, feature flags และ QA/PROD boundary

การทดสอบอัตโนมัติไม่ใช้แทนผลทดสอบวิทยุจริง รอบ QA ล่าสุดยืนยัน Relay บนอุปกรณ์ Android จริงสามเครื่องด้วยเส้นทาง Huawei → Realme → Samsung โดย Realme รับ เก็บ และส่ง envelope ต่อให้ Samsung พร้อม per-hop ACK ลิงก์ตรง Huawei–Samsung มีอยู่ แต่ synthetic probe รอบนั้นไม่ได้ใช้ลิงก์ตรง

รายการทดสอบอุปกรณ์ที่ยังต้องตรวจในแต่ละ release อยู่ใน [docs/MANUAL_DEVICE_TESTS.md](docs/MANUAL_DEVICE_TESTS.md)

## ข้อจำกัดที่ควรรู้

- ความพร้อมของ Nearby ขึ้นกับ Android version, Google Play Services, permission และวิทยุของแต่ละเครื่อง
- map tile จากผู้ให้บริการภายนอกไม่รับประกันว่าเปิดได้แบบออฟไลน์หากไม่มี cache
- Relay v1 รองรับ text, location และ SOS แบบ bounded store-and-forward แต่ยังไม่ relay media
- ACK ของ Relay เป็นราย hop ต้นทางจึงไม่ควรตีความ `stored` จากเครื่องกลางว่า C ได้รับแล้ว
- ไม่มี background relay daemon หรือ continuous location tracking
- QA diagnostics และ test controls มีไว้ทดสอบเท่านั้น และไม่รวมอยู่ใน PROD flow
- การตั้งค่า Supabase จริงต้องใช้ environment ที่แยกจาก production และข้อมูลทดสอบที่ได้รับอนุญาต

## สถานะโปรเจกต์

RELIO อยู่ในสถานะ Android QA ของเวอร์ชัน `0.9.0+38` ฟังก์ชันหลักและ Relay core มี automated coverage และผ่านการทดสอบบนอุปกรณ์จริงชุดหนึ่งแล้ว ยังไม่ควรสรุปว่ารองรับโทรศัพท์ Android ทุกรุ่นหรือพร้อมใช้งาน production โดยไม่ผ่าน release gate และ physical acceptance ของรุ่นเป้าหมาย

Repository นี้ไม่มี license สำหรับการเผยแพร่ซ้ำโดยอัตโนมัติ หากต้องการนำไปใช้ต่อควรติดต่อเจ้าของ repository ก่อน
