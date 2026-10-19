import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_spacing.dart';
import '../../core/identity/owner_context.dart';
import '../../core/repositories/principal_profile_repository.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';
import 'emergency_contact_repository.dart';
import 'emergency_dialer.dart';

class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  State<EmergencyContactScreen> createState() => _EmergencyContactScreenState();
}

class _EmergencyContactScreenState extends State<EmergencyContactScreen> {
  EmergencyContactRepository? _repository;
  PrincipalProfileRepository? _profiles;
  Future<List<EmergencyContactEntry>>? _contacts;
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
    _profiles!.addListener(_reload);
    _contacts = _repository!.list();
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
            const Text(
              'บันทึกผู้ติดต่อฉุกเฉินไว้ในเครื่อง เพื่อให้เปิดดูและติดต่อได้เมื่อจำเป็น',
            ),
            const SizedBox(height: 16),
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
          ],
        );
      },
    ),
  );
}

class _ContactInput {
  const _ContactInput(this.name, this.phone, this.relationship, this.note);
  final String name;
  final String phone;
  final String relationship;
  final String note;
}

class _ContactEditor extends StatefulWidget {
  const _ContactEditor({this.contact});
  final EmergencyContactEntry? contact;
  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

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
