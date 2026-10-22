import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../features/auth/viewmodel/auth_viewmodel.dart';
import '../enums/user_role.dart';
import '../../core/services/file_service.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'app_loader.dart';

/// The original app has no attachment picker. This necessary addition reuses
/// its AppBar, cards, buttons, dialogs, colors and inherited typography.
class FilesScreen extends StatefulWidget {
  final int targetId;
  final bool readOnly;
  final Map<String, String> categories;
  const FilesScreen({super.key, required this.targetId, required this.categories, this.readOnly = false});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _service = FileService();
  late String _category;
  List<Map<String, dynamic>> _files = [];
  bool _loading = true, _busy = false;
  double? _progress;
  String? _error;
  @override
  void initState() { super.initState(); _category = widget.categories.keys.first; _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final files = await _service.list(_category, widget.targetId);
      if (mounted) setState(() => _files = files);
    } catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; _progress = null; });
    try { await action(); }
    catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() { _busy = false; _progress = null; }); }
  }

  Future<void> _pick() => _run(() async {
    final result = await FilePicker.pickFiles(type: FileType.custom,
        allowedExtensions: _category == 'profile_image' ? ['jpg', 'jpeg', 'png'] : ['pdf', 'jpg', 'jpeg', 'png', 'xlsx'], withData: false, withReadStream: true);
    if (result == null || !mounted) return;
    final file = result.files.single;
    const types = {'pdf':'application/pdf','jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png','xlsx':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'};
    final type = types[file.extension?.toLowerCase()];
    if (file.size > 10 * 1024 * 1024 || type == null || file.readStream == null) throw Exception('Choose a PDF, image or workbook up to 10 MB');
    final buffer = await file.readStream!.fold<BytesBuilder>(BytesBuilder(), (builder, chunk) {
      if (builder.length + chunk.length > 10 * 1024 * 1024) throw Exception('Choose a file up to 10 MB');
      return builder..add(chunk);
    });
    await _service.upload(_category, widget.targetId, file.name, type, buffer.takeBytes(), (sent, total) {
      if (mounted && total > 0) setState(() => _progress = sent / total);
    });
    if (mounted) await _load();
  });

  Future<void> _download(Map<String, dynamic> file, {bool preview = false}) => _run(() async {
    final bytes = await _service.download(file['id'] as String);
    if (!mounted) return;
    if (preview) {
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text(file['name'] as String),
        content: SizedBox(width: 500, child: Image.memory(bytes, errorBuilder: (_, _, _) => const Text('Unable to preview this image'))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
    } else {
      await FilePicker.saveFile(fileName: file['name'] as String, bytes: bytes);
    }
  });

  Future<void> _delete(Map<String, dynamic> file) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete attachment'), content: Text('Delete "${file['name']}"?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (confirmed != true || !mounted) return;
    await _run(() async { await _service.delete(file['id'] as String); if (mounted) await _load(); });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attachments'), centerTitle: true),
    body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      if (widget.categories.length > 1) DropdownButtonFormField<String>(
        initialValue: _category,
        items: widget.categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: _busy ? null : (value) { if (value != null) { _category = value; _load(); } },
      ),
      const SizedBox(height: 12),
      if (!widget.readOnly) AppButton(text: 'Choose file', icon: Icons.attach_file, onPressed: _busy ? null : _pick, isLoading: _busy),
      if (_busy) Padding(padding: const EdgeInsets.only(top: 12), child: LinearProgressIndicator(value: _progress)),
      if (_error != null) AppCard(child: Column(children: [Text(_error!), TextButton(onPressed: _busy ? null : _load, child: const Text('Retry'))])),
      Expanded(child: _loading ? const AppLoader(message: 'Loading attachments...') : RefreshIndicator(onRefresh: _load, child: ListView(children: [
        if (_files.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No attachments yet')),
        for (final file in _files) AppCard(child: ListTile(
          title: Text(file['name'] as String), subtitle: Text('${file['size']} bytes'),
          onTap: _busy ? null : () => _download(file),
          trailing: PopupMenuButton<String>(enabled: !_busy, onSelected: (value) {
            if (value == 'delete') { _delete(file); } else { _download(file, preview: value == 'preview'); }
          }, itemBuilder: (_) => [
            const PopupMenuItem(value: 'download', child: Text('Download')),
            if ((file['contentType'] as String).startsWith('image/')) const PopupMenuItem(value: 'preview', child: Text('Preview')),
            if (!widget.readOnly && (file['ownerId'].toString() == FirebaseAuth.instance.currentUser?.uid || [UserRole.captain, UserRole.projectManager].contains(context.read<AuthViewModel>().role)))
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ]),
        )),
      ]))),
    ]))),
  );
}
