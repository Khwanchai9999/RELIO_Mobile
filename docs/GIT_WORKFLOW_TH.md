# Git และ GitHub สำหรับ RELIO

## เลือก branch ให้ตรงกับงาน

ตรวจจาก repository จริงก่อนจัดทำเอกสาร พบฐานงาน `326f02c` เป็น merge ของ `fix/relio-offline-acceptance` เข้ากับ `main` สำหรับ QA Build 45 ณ วันที่ตรวจ `origin/main` อยู่ที่ commit นี้ ส่วน `origin/master` อยู่ที่ `48f11d1` ซึ่งเป็นสายงานเผยแพร่ QA ผ่าน GitHub Releases และเป็น default ของ repository แบบ Private

| Branch | บทบาท |
| --- | --- |
| `main` | ปลายทางส่งงานและรวมงานที่ผ่านการตรวจ |
| `master` | branch เดิมบน GitHub และ default ณ วันที่ตรวจ เก็บประวัติ deployment เดิม |
| `feature/*` | งานเฉพาะเรื่อง เช่น `feature/local-feature-flags`, `feature/nearby-map-battery`, `feature/profile-settings-account-polish` |
| `fix/*` | การแก้ปัญหา เช่น `fix/nearby-lifecycle-stability` และ `fix/relio-offline-acceptance` |
| `codex/automatic-relay-and-map-freshness` | branch ที่ใช้รวบรวม source ปัจจุบันและเอกสารไทยก่อนรวมเข้า `main` |

Git คือประวัติในเครื่อง ส่วน GitHub เป็น remote ที่เข้าถึงตามสิทธิ์ `origin/main` ในเครื่องเป็นภาพของ remote ณ ตอน fetch ล่าสุด ตรวจค่าจริงจากเซิร์ฟเวอร์ก่อนส่งงาน ประวัติเดิมมีหลักฐาน QA ที่ควรตรวจความเป็นส่วนตัวก่อนเปิดให้บุคคลภายนอก

## ทำงานและบันทึกการเปลี่ยนแปลง

ตัวอย่างสำหรับงานรอบใหม่เมื่อ working tree สะอาดและได้สิทธิ์ repo แล้ว

~~~powershell
git status --short --branch
git fetch origin
git switch main
git merge --ff-only origin/main
git switch -c feature/nearby-ui
# แก้ไขและตรวจไฟล์ที่ต้องการก่อน stage
git diff
git add -- lib/features/nearby/nearby_screen.dart
git diff --cached --name-status
git diff --cached --check
git commit -m "fix(nearby): clarify connection state"
git push -u origin feature/nearby-ui
~~~

`git add` เลือกไฟล์เข้า index ส่วน `commit` บันทึก snapshot และ parent commit ให้ทบทวนไฟล์ใหม่ด้วย `git status --untracked-files=all` หลีกเลี่ยงการเลือกทั้ง workspace เพราะมี APK, QA artifacts และไฟล์ส่วนตัว หากต้องเอาไฟล์ออกจาก staging ใช้ `git restore --staged -- PATH` ซึ่งเก็บ working file ไว้

บน GitHub เปิด Pull Request เลือก base `main` และ compare branch ของงาน ระบุสิ่งที่เปลี่ยน วิธีตรวจและข้อจำกัด ให้ผู้ตรวจอ่าน diff และผลทดสอบก่อน merge งาน ใช้ merge ปกติหรือ fast-forward ตามนโยบายทีมเพื่อรักษา commit จริง เมื่อ remote มีงานใหม่ให้ fetch และอ่านความต่างก่อนรวม branch หาก fast-forward ทำไม่ได้ ให้ตรวจสาเหตุและแก้ conflict ทีละไฟล์

~~~powershell
git fetch origin
git log --oneline --graph --decorate --all -25
git rev-list --left-right --count main...origin/main
git diff --stat origin/main...HEAD
~~~

ก่อน Push ตรวจ staged blobs ขนาดใหญ่, LFS และประวัติที่จะเปิดเผย ห้าม Stage `.task_appdata`, `qa_logs`, device dumps, databases, APK, private env หรือ signing credentials หลีกเลี่ยง force push, reset แบบทำลายข้อมูลและการเขียนประวัติใหม่ ใช้ commit ใหม่สำหรับการแก้ไขหรือ revert ที่ตรวจสอบได้

เมื่อปลายทางและประวัติผ่านการตรวจแล้ว ให้เจ้าของ repository กำหนดสิทธิ์อ่านของผู้สอน บน GitHub เลือก `main` จากตัวเลือก branch เพื่ออ่าน source และเปิดหน้า Commits หากต้องการตั้ง landing page หลังส่งสำเร็จ ให้ผู้ดูแลไปที่ `Settings → General → Default branch` เลือก `main` และยืนยัน
