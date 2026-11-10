// หน้าจัดการผู้ติดต่อฉุกเฉินและข้อมูลสุขภาพส่วนตัว ซึ่งบันทึกในเครื่องและคำนึงถึงเจ้าของข้อมูล
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/identity/owner_context.dart';
import '../../core/repositories/principal_profile_repository.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';
import 'emergency_contact_repository.dart';
import 'emergency_dialer.dart';
import 'emergency_profile_repository.dart';

// จัดการรายชื่อฉุกเฉินและ health profile ที่ผูกกับ principal ใน SQLite
// ค่าการแชร์เป็นเพียงความตั้งใจของผู้ใช้และยังไม่อนุญาตให้เผยข้อมูลผ่าน SOS หรือ Nearby
class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  State<EmergencyContactScreen> createState() => _EmergencyContactScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Emergency Contact Screen State)
class _EmergencyContactScreenState extends State<EmergencyContactScreen> {
  EmergencyContactRepository? _repository;
  EmergencyProfileRepository? _profileRepository;
  PrincipalProfileRepository? _profiles;
  Future<List<EmergencyContactEntry>>? _contacts;
  Future<EmergencyProfileData>? _profile;
  int _revision = 0;
  bool _busy = false;
  bool _dialogOpen = false;
  OwnerSnapshot? _dialogOwner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (_profiles == dependencies.repositories.profiles) return;
    _profiles?.removeListener(_reload);
    _profiles = dependencies.repositories.profiles;
    _repository = EmergencyContactRepository(dependencies.database, _profiles!);
    _profileRepository = EmergencyProfileRepository(
      dependencies.database,
      _profiles!,
    );
    _profiles!.addListener(_reload);
    _contacts = _repository!.list();
    _profile = _profileRepository!.read();
  }

  void _reload() {
    if (!mounted) return;
    if (_dialogOpen &&
        _dialogOwner != null &&
        !_profiles!.owners.isCurrent(_dialogOwner!)) {
      Navigator.of(context, rootNavigator: true).pop();
      _dialogOpen = false;
      _dialogOwner = null;
    }
    setState(() {
      _revision++;
      _contacts = _repository!.list();
      _profile = _profileRepository!.read();
    });
  }

  @override
  void dispose() {
    _profiles?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _edit(EmergencyContactEntry? contact) async {
    final owner = _profiles!.owners.capture();
    _dialogOpen = true;
    _dialogOwner = owner;
    final input = await showDialog<_ContactInput>(
      context: context,
      builder: (_) => _ContactEditor(contact: contact),
    );
    _dialogOpen = false;
    _dialogOwner = null;
    if (!mounted || input == null) return;
    try {
      _profiles!.owners.requireCurrent(owner);
      setState(() => _busy = true);
      await _repository!.save(
        id: contact?.id,
        name: input.name,
        phone: input.phone,
        relationship: input.relationship,
        note: input.note,
      );
      if (mounted) _reload();
    } on OwnerChangedException {
      if (mounted) _reload();
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('บันทึกผู้ติดต่อไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(EmergencyContactEntry contact) async {
    final owner = _profiles!.owners.capture();
    _dialogOpen = true;
    _dialogOwner = owner;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบผู้ติดต่อฉุกเฉิน?'),
        content: Text('ลบ ${contact.name} จากข้อมูลในเครื่อง'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    _dialogOwner = null;
    if (!mounted || confirmed != true) return;
    try {
      _profiles!.owners.requireCurrent(owner);
      setState(() => _busy = true);
      await _repository!.delete(contact.id);
      if (mounted) _reload();
    } on OwnerChangedException {
      if (mounted) _reload();
    } catch (_) {
      if (mounted) _message('ลบผู้ติดต่อไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dial(String phone) async {
    try {
      await const EmergencyDialer().open(phone);
    } on PlatformException {
      if (mounted) _message('ไม่สามารถเปิดแอปโทรศัพท์ได้');
    } on MissingPluginException {
      if (mounted) _message('อุปกรณ์นี้ไม่รองรับการเปิดแอปโทรศัพท์');
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: RelioAppBar(title: 'ข้อมูลฉุกเฉิน', onBack: () => context.pop()),
    body: FutureBuilder<List<EmergencyContactEntry>>(
      key: ValueKey(_revision),
      future: _contacts,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _reload,
              child: const Text('โหลดข้อมูลไม่สำเร็จ แตะเพื่อลองอีกครั้ง'),
            ),
          );
        }
        final contacts = snapshot.data ?? const <EmergencyContactEntry>[];
        final visibleOwner = _profiles!.owners.capture();
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            RelioSpacing.lg,
            16,
            RelioSpacing.lg,
            32,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(RelioSpacing.lg),
              decoration: BoxDecoration(
                color: RelioColors.rescue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: RelioColors.rescue.withValues(alpha: 0.28),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.health_and_safety_outlined,
                    color: RelioColors.rescue,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'เตรียมข้อมูลฉุกเฉินไว้ในเครื่องของคุณ ข้อมูลสุขภาพเป็นทางเลือกและไม่จำเป็นต่อการใช้ SOS',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ผู้ติดต่อฉุกเฉิน',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: RelioColors.brandNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text('เก็บไว้ในเครื่อง • แก้ไขหรือลบได้ทุกเมื่อ'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : () => _edit(null),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('เพิ่มผู้ติดต่อ'),
            ),
            const SizedBox(height: 16),
            if (contacts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('ยังไม่มีผู้ติดต่อฉุกเฉินที่บันทึกไว้'),
                ),
              ),
            ...contacts.map(
              (contact) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(contact.phone),
                      if (contact.relationship != null)
                        Text('ความสัมพันธ์: ${contact.relationship}'),
                      if (contact.note != null) Text(contact.note!),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () {
                                    if (_profiles!.owners.isCurrent(
                                      visibleOwner,
                                    )) {
                                      _dial(contact.phone);
                                    }
                                  },
                            icon: const Icon(Icons.phone_outlined),
                            label: const Text('เปิดแอปโทรศัพท์'),
                          ),
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () {
                                    if (_profiles!.owners.isCurrent(
                                      visibleOwner,
                                    )) {
                                      _edit(contact);
                                    }
                                  },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('แก้ไข'),
                          ),
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () {
                                    if (_profiles!.owners.isCurrent(
                                      visibleOwner,
                                    )) {
                                      _delete(contact);
                                    }
                                  },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('ลบ'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<EmergencyProfileData>(
              key: ValueKey('health-$_revision'),
              future: _profile,
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (profileSnapshot.hasError) {
                  return TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      'โหลดข้อมูลสุขภาพไม่สำเร็จ แตะเพื่อลองใหม่',
                    ),
                  );
                }
                return _EmergencyHealthProfileEditor(
                  initialValue: profileSnapshot.data!,
                  repository: _profileRepository!,
                  owners: _profiles!.owners,
                  owner: _profiles!.owners.capture(),
                  onSaved: _reload,
                  onMessage: _message,
                );
              },
            ),
          ],
        );
      },
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Contact Input)
class _ContactInput {
  const _ContactInput(this.name, this.phone, this.relationship, this.note);
  final String name;
  final String phone;
  final String relationship;
  final String note;
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Contact Editor)
class _ContactEditor extends StatefulWidget {
  const _ContactEditor({this.contact});
  final EmergencyContactEntry? contact;
  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Contact Editor State)
class _ContactEditorState extends State<_ContactEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.contact?.name);
  late final _phone = TextEditingController(text: widget.contact?.phone);
  late final _relationship = TextEditingController(
    text: widget.contact?.relationship,
  );
  late final _note = TextEditingController(text: widget.contact?.note);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.contact == null
          ? 'เพิ่มผู้ติดต่อฉุกเฉิน'
          : 'แก้ไขผู้ติดต่อฉุกเฉิน',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'ชื่อ *'),
              validator: (value) =>
                  value?.trim().isEmpty == true ? 'กรุณาระบุชื่อ' : null,
            ),
            TextFormField(
              controller: _phone,
              maxLength: 40,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'หมายเลขโทรศัพท์ *'),
              validator: (value) {
                final phone = value?.trim() ?? '';
                final digits = phone.replaceAll(RegExp(r'\D'), '');
                return RegExp(r'^\+?[0-9() .-]+$').hasMatch(phone) &&
                        digits.length >= 3 &&
                        digits.length <= 20
                    ? null
                    : 'หมายเลขโทรศัพท์ไม่ถูกต้อง';
              },
            ),
            TextField(
              controller: _relationship,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'ความสัมพันธ์ (ไม่บังคับ)',
              ),
            ),
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ (ไม่บังคับ)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState?.validate() != true) return;
          Navigator.pop(
            context,
            _ContactInput(
              _name.text,
              _phone.text,
              _relationship.text,
              _note.text,
            ),
          );
        },
        child: const Text('บันทึก'),
      ),
    ],
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Emergency Health Profile Editor)
class _EmergencyHealthProfileEditor extends StatefulWidget {
  const _EmergencyHealthProfileEditor({
    required this.initialValue,
    required this.repository,
    required this.owners,
    required this.owner,
    required this.onSaved,
    required this.onMessage,
  });

  final EmergencyProfileData initialValue;
  final EmergencyProfileRepository repository;
  final OwnerContext owners;
  final OwnerSnapshot owner;
  final VoidCallback onSaved;
  final ValueChanged<String> onMessage;

  @override
  State<_EmergencyHealthProfileEditor> createState() =>
      _EmergencyHealthProfileEditorState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Emergency Health Profile Editor State)
class _EmergencyHealthProfileEditorState
    extends State<_EmergencyHealthProfileEditor> {
  late final _conditions = TextEditingController(
    text: widget.initialValue.medicalConditions,
  );
  late final _allergies = TextEditingController(
    text: widget.initialValue.allergies,
  );
  late final _medications = TextEditingController(
    text: widget.initialValue.medications,
  );
  late final _careNotes = TextEditingController(
    text: widget.initialValue.careNotes,
  );
  late bool _shareContacts = widget.initialValue.shareContactsOnSos;
  late bool _shareHealth = widget.initialValue.shareHealthOnSos;
  bool _busy = false;

  @override
  void dispose() {
    _conditions.dispose();
    _allergies.dispose();
    _medications.dispose();
    _careNotes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      widget.owners.requireCurrent(widget.owner);
      await widget.repository.save(
        expectedOwner: widget.owner,
        medicalConditions: _conditions.text,
        allergies: _allergies.text,
        medications: _medications.text,
        careNotes: _careNotes.text,
        shareContactsOnSos: _shareContacts,
        shareHealthOnSos: _shareHealth,
      );
      if (!mounted) return;
      widget.onMessage('บันทึกข้อมูลฉุกเฉินไว้ในเครื่องแล้ว');
      widget.onSaved();
    } on FormatException catch (error) {
      if (mounted) widget.onMessage(error.message);
    } on OwnerChangedException {
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) widget.onMessage('บันทึกข้อมูลฉุกเฉินไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบข้อมูลสุขภาพที่บันทึกไว้?'),
        content: const Text(
          'ข้อมูลสุขภาพและการตั้งค่าความประสงค์แชร์ของบัญชีนี้จะถูกลบจากเครื่อง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบข้อมูล'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.delete(expectedOwner: widget.owner);
      if (!mounted) return;
      widget.onMessage('ลบข้อมูลสุขภาพจากเครื่องแล้ว');
      widget.onSaved();
    } on OwnerChangedException {
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) widget.onMessage('ลบข้อมูลสุขภาพไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: RelioColors.brandNavy,
      fontWeight: FontWeight.w800,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ข้อมูลสุขภาพที่ควรทราบ', style: titleStyle),
        const SizedBox(height: 4),
        const Text('ไม่บังคับ • กรอกเฉพาะข้อมูลที่ต้องการเตรียมไว้'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(RelioSpacing.md),
            child: Column(
              children: [
                _HealthField(
                  controller: _conditions,
                  label: 'โรคประจำตัว',
                  hint: 'เช่น โรคประจำตัวที่ผู้ช่วยควรทราบ',
                  maxLines: 2,
                ),
                _HealthField(
                  controller: _allergies,
                  label: 'การแพ้ยา / สิ่งที่แพ้',
                  hint: 'ถ้าไม่มีหรือไม่ต้องการระบุ เว้นว่างได้',
                  maxLines: 2,
                ),
                _HealthField(
                  controller: _medications,
                  label: 'ยาที่ใช้ประจำ',
                  hint: 'ระบุชื่อหรือคำแนะนำที่จำเป็น',
                  maxLines: 2,
                ),
                _HealthField(
                  controller: _careNotes,
                  label: 'ข้อควรระวังในการช่วยเหลือ',
                  hint: 'ข้อมูลเพิ่มเติมที่ผู้ช่วยควรทราบ',
                  maxLines: 3,
                  maxLength: 1000,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('การตั้งค่าความประสงค์แชร์เมื่อส่ง SOS', style: titleStyle),
        const SizedBox(height: 4),
        const Text(
          'เลือกแยกกันได้และปิดไว้เป็นค่าเริ่มต้น การเปิดสวิตช์จะบันทึกความประสงค์ไว้เท่านั้น ขณะนี้ RELIO ยังไม่ส่งข้อมูลฉุกเฉินหรือสุขภาพให้ Rescue',
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                value: _shareContacts,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _shareContacts = value),
                secondary: const Icon(
                  Icons.contact_emergency_outlined,
                  color: RelioColors.rescue,
                ),
                title: const Text('ผู้ติดต่อฉุกเฉิน'),
                subtitle: const Text(
                  'บันทึกความประสงค์ไว้ • ยังไม่ได้กำหนดผู้รับเป็นรายอุปกรณ์',
                ),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _shareHealth,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _shareHealth = value),
                secondary: const Icon(
                  Icons.monitor_heart_outlined,
                  color: RelioColors.rescue,
                ),
                title: const Text('ข้อมูลสุขภาพ'),
                subtitle: const Text(
                  'บันทึกความประสงค์ไว้ • ยังไม่มีการส่งข้อมูลนี้',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          color: RelioColors.rescue.withValues(alpha: 0.06),
          child: const Padding(
            padding: EdgeInsets.all(RelioSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, color: RelioColors.rescue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ข้อมูลสุขภาพจัดเก็บใน SQLite ของโปรไฟล์นี้เท่านั้น ยังไม่มีการส่งผ่าน Nearby, Relay หรือ Cloud และผู้เปิด Rescue ไม่มีสิทธิ์เห็นข้อมูลนี้โดยอัตโนมัติ หากในอนาคตมีการส่งสำเนาไปยังอุปกรณ์อื่น อาจเรียกคืนสำเนาที่ส่งแล้วไม่ได้ การปิดความประสงค์จะหยุดการส่งในอนาคตเมื่อมีระบบรองรับ',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: RelioColors.rescueStrong,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_busy ? 'กำลังบันทึก…' : 'บันทึกข้อมูลฉุกเฉิน'),
        ),
        if (widget.initialValue.hasHealthInformation ||
            widget.initialValue.shareContactsOnSos ||
            widget.initialValue.shareHealthOnSos) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('ลบข้อมูลสุขภาพและการตั้งค่าแชร์'),
          ),
        ],
      ],
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Health Field)
class _HealthField extends StatelessWidget {
  const _HealthField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.maxLines,
    this.maxLength = 500,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final int maxLength;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      minLines: maxLines == 2 ? 1 : 2,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: 'ไม่เกิน $maxLength ตัวอักษร',
        alignLabelWithHint: maxLines > 1,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
