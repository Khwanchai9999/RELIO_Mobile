# Build 39 — ทดสอบออฟไลน์สามเครื่องซ้ำ 28 ตุลาคม 2026

ทดสอบเวลาประมาณ 11:26–11:43 น. เวลาไทย โดยใช้ Native ADB และ QA APK เดิม ไม่แก้ source แอปหรือสร้าง APK ใหม่ในรอบนี้

## อุปกรณ์และเงื่อนไข

- Samsung SM-G990E, Realme RMX3661 และ Huawei STK-L22: ADB เห็นครบ 3/3 และอ่าน versionCode 39 ครบ
- APK provenance ใช้หลักฐาน installed SHA-256 ที่ตรวจครบสามเครื่องก่อนหน้า ไม่มีการติดตั้งอื่นในรอบนี้
- ทดสอบ IP ก่อนและหลัง: ทั้งสามเครื่องตอบ `Network is unreachable` ไม่เปลี่ยน Internet, Wi-Fi หรือ Bluetooth settings
- ใช้ข้อความ synthetic เท่านั้น ไม่ส่ง SOS และไม่ล้างข้อมูลหรือ trusted peers

## ผลบนเครื่องจริง

| กรณี | โหมด / เส้นทางจริง | Payload alias | Envelope alias | ผล |
| --- | --- | --- | --- | --- |
| อยู่ใกล้กัน | Automatic: Samsung → Huawei โดยตรง | `9c6bb97cab1f` | ไม่มี Relay envelope | PASS: text_direct_sent และ direct_ack_received ตรงกัน |
| ไม่มีลิงก์ตรง | Automatic: Samsung → Realme → Huawei | `e0e02f33fa3e` | `d6f176b05b95` | PASS: hop 1/2 และ delivered ACK กลับ A |
| ทิศทางกลับ | Automatic: Huawei → Realme → Samsung | `314beaf5029d` | `627c36f7c322` | PASS: B รับ/เก็บ/ส่งต่อ, C payload_delivered hop 2 |
| เปลี่ยนเป็น Samsung กลาง | QA forced: Realme → Samsung → Huawei | `d8b1e2030684` | `14ceb4c93f41` | PASS: Samsung forward hop 2, Huawei รับ, ACK กลับ Realme |
| เปลี่ยนเป็น Huawei กลาง | QA forced: Samsung → Huawei → Realme | `43ff75ade87c` | `ab292fb37ed1` | PASS: Huawei forward hop 2, Realme รับ, ACK กลับ Samsung |
| เครื่องกลางไม่พร้อมแล้วกลับมา | QA forced: Samsung → Huawei → Realme | `3719913ba6d3` | `2620e5f50f33` | PASS ภายใต้เงื่อนไขด้านล่าง |

กรณี Automatic ไม่มีลิงก์ตรง ใช้ connection diagnostics disconnect เฉพาะ Samsung–Huawei โดยคง Samsung–Realme และ Realme–Huawei ไว้ ไม่ได้ใช้การเดินแยกระยะ เมื่อทดสอบ forced route ภายหลังมี direct A–C อยู่ แต่ packet ไป B และต่อ C ตามที่เลือกจริง

อ่าน correlated events จากทั้งสามเครื่องขณะทดสอบ ได้แก่ A packet_enqueued / forward_sent hop 1, B envelope_stored / ACK stored / forward_sent hop 2, C payload_delivered / ACK delivered และ B final_ack_propagated / A ACK delivered รหัส envelope และ payload ตรงกันในแต่ละกรณี ไม่ใช้ ACK stored แทนการส่งถึง C

## เครื่องกลางไม่พร้อมและความคงทนของข้อความ

1. คง Samsung เป็น forced-through-Huawei ปลายทาง Realme โดย Samsung–Realme ยังมีลิงก์ตรง
2. หยุดเฉพาะ process แอป Huawei ด้วย `am force-stop` ไม่เปลี่ยนวิทยุหรือข้อมูล
3. ส่ง Text synthetic จาก Chat ปกติบน Samsung หนึ่งครั้ง ข้อความขึ้น **ค้างส่ง** และ route unavailable ไม่ fallback Direct และไม่ขึ้น delivered
4. restart Samsung แล้วเข้าใช้งานแบบ offline พบข้อความเดิมหนึ่งรายการยังค้างส่ง และโหมด forced ยังคงอยู่
5. เปิด Huawei กลับเข้าใช้งานแบบ offline รอ trusted reconnection และ foreground retry โดยไม่กดส่งข้อความเดิมใหม่
6. Samsung enqueue envelope `2620e5f50f33` เพียงครั้งเดียว ส่งให้ Huawei; Huawei ส่ง hop 2 ไป Realme; Realme มี payload_delivered หนึ่งครั้ง; Samsung ได้ delivered ACK และ Realme Chat แสดงข้อความหนึ่งรายการ

กรณีนี้เป็นการหยุดเครื่องกลาง **ก่อนข้อความเริ่มเดินทาง** แล้วตรวจ pending persistence / recovery ไม่ใช่การตัดเครื่องกลางหลัง B รับฝากแล้ว การขาด ACK ระหว่างส่ง, retransmission ซองเดิมบนวิทยุจริง และการย้ายตัวกลางให้ envelope ที่เริ่มแล้ว ยังไม่ถูกยืนยันด้วยกรณีนี้

## Endpoint recovery

ปุ่ม Connect ใน diagnostics ที่ชี้ endpoint เก่าถูก `stale_endpoint_connect_blocked / waiting_for_fresh_endpoint` ตามการตรวจ freshness ไม่ได้ข้าม guard หลังเริ่ม Huawei ใหม่และได้รับ endpoint ใหม่ trusted peers เชื่อมกลับและ handshake สำเร็จโดยไม่ reset trust ภายหลังทั้งสามเครื่องมี topology ครบคู่ ไม่อ้างว่าการ reconnect ทันทีจาก endpoint เก่าผ่าน

## หลักฐานและ Automated tests

- เก็บ retained native relay events ที่ตัดข้อมูลข้อความ/ตำแหน่ง/secret แล้วใน [retained-relay-events.json](evidence/build39-20261028/retained-relay-events.json)
- Device log buffers เก็บรายการย้อนหลังไม่ครบทุกกรณีเมื่อ export ปิดรอบ โดยเฉพาะ Huawei หลัง restart; ผลตารางก่อนหน้าอ้างอิง output ที่อ่านจริงระหว่างแต่ละ test ใน chat นี้ ไม่ได้สร้าง native events ที่หายขึ้นใหม่
- สำหรับ outage recovery มี retained events ครบ A/B/C ตรวจด้วยสคริปต์: source enqueue = 1, Huawei forward hop 2 = 1, Realme payload_delivered = 1, source final ACK = 1
- รัน regression ซ้ำรอบนี้: `relay_route_planner_test`, `automatic_relay_integration_test`, `relay_engine_test` ใน QA configuration: **21 tests passed** (`build/qa39-retest-focused-tests.log`)
- Full QA 452 tests, DEV 447 passed/5 QA-only skipped, Analyze, signed QA และ isolation เป็น baseline ที่ผ่านก่อนหน้า ไม่ได้อ้างว่ารัน full suite หรือ build ใหม่วันนี้

## สถานะปิดรอบ

คืนโหมด Automatic สำหรับข้อความใหม่ทั้งสามเครื่อง Samsung ตรวจ route ไป Huawei ได้ Direct พร้อม ส่วน Realme/Huawei Home แสดง Nearby เชื่อมอีกสองเครื่อง ทั้งสามเครื่องยัง offline และ ADB มองเห็นครบ ข้อมูลเก่าและ trust ยังคงอยู่ ไม่มี push/merge

**ผ่าน:** direct-first, Automatic relay แบบ disconnect ลิงก์ตรง, บทบาทเครื่องกลางครบทั้งสามเครื่อง, pending persistence หลัง restart และ recovery เมื่อเครื่องกลางกลับมา ตามกรณีข้างต้น

**ยัง UNVERIFIED:** การเดินห่างจริง (ผู้ใช้แจ้งว่าไม่มีเวลาทำ ให้ทดสอบเฉพาะที่ทำได้), loss หลัง B รับฝาก/ACK ขาดระหว่างส่ง, physical network มากกว่า 3 เครื่อง และการย้ายตัวกลางกลางทางของข้อความที่เริ่มแล้ว ไม่สรุปว่าระบบไม่มีบั๊กทุกเงื่อนไข
