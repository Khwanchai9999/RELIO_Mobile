# Build 39 — ผล Automatic Text Relay

ตรวจวันที่ 27 ตุลาคม 2026 (เวลาไทย) บน branch `fix/relio-offline-acceptance`

## ขอบเขตที่ทำเสร็จ

QA มีสามโหมดในหน้าทดสอบ Relay: เส้นทางอัตโนมัติ, ส่งตรงเท่านั้น และ QA บังคับผ่านเครื่องกลาง การตั้งค่านี้ใช้กับ Text ใน Chat จริงด้วย โดย UI ส่งผ่าน Repository/SQLite ก่อน Nearby ไม่ใช่ส่งเฉพาะ simulation

Automatic ใช้ Direct ก่อน หากไม่มีจึงตรวจ B–C สดและเลือกเครื่องกลางที่ authenticated เพียงเครื่องเดียว จำกัดสอง hops ไม่มี flooding เปลี่ยนเครื่องกลางได้สำหรับข้อความใหม่ ส่วน envelope ที่เริ่มแล้วคงเส้นทางเดิม ใช้ ID เดิมในการ retry และไม่ทำให้ delivered ย้อนกลับเป็น sent

Log จัดกลุ่มตาม payload alias เรียงเหตุการณ์ตามเวลา แยก stored จาก delivered และแสดงชื่อ peer จากข้อมูลในเครื่อง Final receipt เป็นการส่งต่อรายงานจาก authenticated peer ไม่ใช่ลายเซ็น end-to-end ของ C

ทำงานเฉพาะ QA Text ขณะเปิดแอปและ Nearby ทำงาน ไม่เพิ่ม background daemon ไม่เปลี่ยน DEV/PROD routing, SOS, media, Auth, OwnerContext หรือ schema

## Automated verification

- Format ผ่าน; Flutter analyze --no-pub ผ่าน
- Full QA suite: **452 passed**, ไม่มี skipped
- Default DEV suite: **447 passed, 5 QA-only skipped**
- ครอบคลุมเครือข่ายจำลอง 2/3/4/5 เครื่อง, direct-first, forced-middle, เปลี่ยนตัวกลางสำหรับข้อความใหม่, รอเส้นทาง, envelope reuse, ACK และไม่ materialize ข้อความส่วนตัวที่ B
- QA/PROD isolation ผ่าน
- Signed QA Build 39 ผ่าน `scripts/deploy-test.ps1 -NoUpload`; ไม่ upload

แก้ปัญหาที่พบระหว่าง verification: foreground retry timer ไม่ควรเริ่มใน Mock/unknown lifecycle, late updater callback หลัง dispose และ test navigation ที่อาศัยระยะ scroll คงที่ ใช้ regression tests ตรวจซ้ำจน full suite ผ่าน

## APK และการติดตั้ง

ไฟล์ `dist/relio-test-0.9.0+39.apk` ขนาด 101151537 bytes

SHA-256: `D55A39E16F12C28B099AF5B0CDA3DB419D01F7A0AFC833FCDFD4C9B1C010E7C6`

Samsung SM-G990E และ Realme RMX3661 อัปเดตด้วย `adb install -r` สำเร็จ ทั้งสองเครื่องอ่าน APK ที่ติดตั้งกลับมาตรวจ SHA-256 แล้วตรงกับไฟล์นี้ ข้อมูลเดิมและ trusted peers ยังคงอยู่ ไม่มี clear data หรือ uninstall เก็บ APK Build 38 เดิมไว้

Huawei ยังสื่อสารผ่าน Nearby ได้ แต่ไม่ปรากฏใน USB/ADB รอบนี้ จึงไม่ได้อัปเดตหรือยืนยัน installed build ของ Huawei ใหม่ ไม่อ้างว่าทั้งสามเครื่องเป็น Build 39

## Physical evidence

Samsung และ Realme ทดสอบ IP ไป 8.8.8.8 ได้ `Network is unreachable` ก่อน/หลังการทดสอบ ไม่มีการเปลี่ยน Internet settings ของมือถือ Huawei เป็นสถานะ offline ตามผู้ใช้แจ้ง แต่ไม่ได้ตรวจ IP แยกผ่าน ADB รอบนี้

1. Automatic Direct Samsung → Realme: payload `80d14f777a78` มี `text_direct_sent` และ `direct_ack_received` ตรงกัน
2. Direct-only Samsung → Huawei: payload `373dac0ea1de` ได้ Direct ACK
3. ถอดเฉพาะ connection Samsung–Huawei ด้วย Nearby diagnostics โดยไม่ลบ trust; Samsung–Realme และ Realme–Huawei ยัง active
4. Direct-only ตรวจเส้นทางไม่พร้อมและไม่เปิดปุ่มส่ง; เปลี่ยน Automatic แล้วตรวจพบ Realme เป็นเครื่องกลางที่เชื่อม Huawei อยู่
5. ส่ง synthetic Text จริงผ่านเส้นทาง **Samsung (A) → Realme (B) → Huawei (C)** เวลา 22:47 ไทย:

| เครื่อง | หลักฐานจาก native QA log |
| --- | --- |
| Samsung | packet_enqueued, forward_attempt/sent hop 1 ไป Realme, ACK stored แล้ว delivered |
| Realme | envelope_stored hop 1, ACK stored, forward_attempt/sent hop 2 ไป Huawei, รับ ACK delivered, final_ack_propagated กลับ Samsung |

ทุกเหตุการณ์ตรงกันที่ payload alias **`6a9de77dc6e9`** และ envelope alias **`3a1fbbfcdf7e`** เป้าหมาย hop 2 คือ Huawei alias `7eaa913c9cfd` เครื่องกลางคือ Realme alias `a80ab9e75e3c` Samsung แสดงผล delivered ของรายการเดียวกันใน UI

Samsung ไม่มี Direct connection ไป Huawei ขณะส่ง probe นี้ หลักฐานจึงยืนยันการส่งต่อจริงผ่าน Realme ใน topology ที่ควบคุมด้วยการ disconnect ไม่ใช่ simulation และไม่ใช่การทดสอบเดินออกนอกระยะวิทยุ

หลักฐาน log sanitized เก็บใน `build/qa39-physical-RFCT611DBBP.json` และ `build/qa39-physical-c821a16d.json` (local ignored artifacts) ผล tests อยู่ใน `build/qa39-verified-tests.log` และ `build/qa39-pipeline.log`

## ข้อจำกัดและสถานะสุดท้าย

- **Physical automatic forwarding และ final ACK: PASS** สำหรับเส้นทางและเงื่อนไขข้างต้น
- ไม่มี log/หน้าจอปลายทาง Huawei ที่ดึงตรงผ่าน ADB รอบนี้; การยืนยัน C อาศัย ACK จากลิงก์ B–C ที่ authenticated และส่งกลับ A
- เดินทดสอบระยะจริง, เปลี่ยนตัวกลางบน hardware หลายเครื่อง และ 4/5 เครื่องจริง: **UNVERIFIED**; 4/5 เครื่องผ่าน automated integration เท่านั้น
- สถานะปิดงานคง Automatic และ topology สำหรับทดสอบ Samsung–Realme–Huawei; ลิงก์ตรง Samsung–Huawei ถูก disconnect ในการทดสอบ โดยไม่ได้ลบ trust
- ข้อความที่เริ่ม Relay แล้วไม่ย้ายตัวกลางกลางทาง; retry มีขอบเขต ไม่รับประกันส่งสำเร็จเมื่อ peer หายหรือแอปปิด
- ปุ่ม synthetic probe ยังใช้ชื่อ “เริ่ม QA Relay Probe” แม้เส้นทางเป็น Direct; route status และ log ระบุ Direct/Relay จริง
- ไม่ส่ง SOS จริง ไม่ล้างข้อมูล ไม่แก้ระบบความปลอดภัย Windows ไม่ push/merge และไม่ใช้ GPT-PC-Agent

เปิดโหมดได้ที่ Settings → ทดสอบ Relay (QA) โหมดที่เลือกมีผลกับ Text ใหม่ใน QA Chat ของเครื่องนั้น

## ตรวจ Huawei เพิ่มเติมหลังเชื่อม USB กลับมา

เวลา 23:08 ไทย วันที่ 27 ตุลาคม 2026 พบ Huawei STK-L22 ผ่าน ADB ตามปกติ ตรวจเครื่องเดิมเป็น Build 38 และตรวจ APK signer เดิมตรงกับ Build 39 ก่อนอัปเดตด้วย `adb install -r` สำเร็จ

หลังอัปเดตอ่าน `versionCode=39`, `versionName=0.9.0`; `firstInstallTime=2026-10-20 11:16:25` เท่าเดิม และ `lastUpdateTime=2026-10-27 23:08:20` อ่าน APK ที่ติดตั้งกลับมาแล้ว SHA-256 ตรงกับ artifact Build 39 ข้างต้น เปิด MainActivity ได้ `Status: ok` และทดสอบ IP ได้ `Network is unreachable` ไม่มี clear data หรือเปลี่ยน Internet settings

ปัจจุบันทั้ง Samsung, Realme และ Huawei มี installed Build 39 ที่ตรวจ hash แล้ว และ ADB มองเห็นครบ 3/3 ข้อจำกัดเรื่อง Huawei provenance ข้างต้นเป็นสถานะของการทดสอบก่อนการอัปเดตครั้งนี้ การติดตั้งเพิ่มเติมนี้ไม่ได้เป็นการทดสอบ physical relay ซ้ำบน Build 39 ครบทุก hop

วันที่ 28 ตุลาคม 2026 ทดสอบซ้ำบน Build 39 ครบสามเครื่องแล้ว รวม Automatic ทั้งสองทิศทาง, Samsung/Huawei เป็นตัวกลาง และ pending recovery ดู [ผลรอบทดสอบใหม่และข้อจำกัด](BUILD39_THREE_DEVICE_RETEST_20261028.md) การเดินระยะจริงยัง UNVERIFIED ตามผู้ใช้เลื่อนไว้
