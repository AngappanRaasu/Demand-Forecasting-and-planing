import 'package:flutter/material.dart';
import '../../services/api_service.dart';

import 'package:file_picker/file_picker.dart';

class DatabaseConfigPage extends StatefulWidget {
  const DatabaseConfigPage({super.key});

  @override
  State<DatabaseConfigPage> createState() => _DatabaseConfigPageState();
}

class _DatabaseConfigPageState extends State<DatabaseConfigPage> {
  // Source fields
  final _serverCtrl = TextEditingController();
  final _portCtrl = TextEditingController(); // Leave blank for named instances like localhost\sqlexpress
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Target fields
  final _tServerCtrl = TextEditingController();
  final _tPortCtrl = TextEditingController(); // Leave blank for named instances like localhost\sqlexpress
  final _tUserCtrl = TextEditingController();
  final _tPassCtrl = TextEditingController();

  bool _isTesting = false;
  bool _isLoadingData = false;
  bool _isUploading = false;
  bool _connectionOk = false;
  bool _sameAsSource = false;
  List<String> _dbs = [];
  String? _selectedDb;

  // ── Helpers ───────────────────────────────────────────────────────

  void _snack(String msg, {Color? bg}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ── Test Connection ───────────────────────────────────────────────

  Future<void> _testConnection() async {
    if (_serverCtrl.text.isEmpty ||
        _portCtrl.text.isEmpty ||
        _userCtrl.text.isEmpty ||
        _passCtrl.text.isEmpty) {
      _snack('Please fill in Server, Port, Username and Password.', bg: Colors.orange);
      return;
    }
    setState(() => _isTesting = true);
    try {
      final api = ApiService();
      final res = await api.testConnection(
        _serverCtrl.text,
        _portCtrl.text,
        _userCtrl.text,
        _passCtrl.text,
      );

      if (res['success'] == true) {
        final res2 = await api.listDatabases(
          _serverCtrl.text,
          _portCtrl.text,
          _userCtrl.text,
          _passCtrl.text,
        );
        if (res2['success'] == true) {
          setState(() {
            _dbs = List<String>.from(res2['databases'] ?? []);
            _selectedDb = null; // Show placeholder by default
            _connectionOk = true;
            _isTesting = false;
          });
          _snack(
            'Database connection successful ✓',
            bg: const Color(0xFF059669),
          );
        }
      } else {
        _snack('Connection failed: ${res['message']}', bg: Colors.red);
      }
    } catch (e) {
      _snack('Error: $e', bg: Colors.red);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  // ── Load Dataset ──────────────────────────────────────────────────

  Future<void> _loadDataset() async {
    if (_selectedDb == null) {
      _snack('Please select a database.');
      return;
    }

    if (!_sameAsSource &&
        (_tServerCtrl.text.isEmpty ||
            _tPortCtrl.text.isEmpty ||
            _tUserCtrl.text.isEmpty ||
            _tPassCtrl.text.isEmpty)) {
      _snack('Please fill in Target Server, Port, Username and Password.', bg: Colors.orange);
      return;
    }

    setState(() => _isLoadingData = true);
    try {
      final api = ApiService();
      final res = await api.loadDataset(
        sourceServer: _serverCtrl.text,
        sourcePort: _portCtrl.text,
        sourceUsername: _userCtrl.text,
        sourcePassword: _passCtrl.text,
        database: _selectedDb!,
        sameAsSource: _sameAsSource,
        targetServer: _sameAsSource ? _serverCtrl.text : _tServerCtrl.text,
        targetPort: _sameAsSource ? _portCtrl.text : _tPortCtrl.text,
        targetUsername: _sameAsSource ? _userCtrl.text : _tUserCtrl.text,
        targetPassword: _sameAsSource ? _passCtrl.text : _tPassCtrl.text,
      );

      if (res['success'] == true) {
        _snack('Dataset loaded successfully ✓', bg: const Color(0xFF059669));
      } else {
        _snack('Failed: ${res['message']}', bg: Colors.red);
      }
    } catch (e) {
      _snack('Error: $e', bg: Colors.red);
    } finally {
      setState(() => _isLoadingData = false);
    }
  }

  // ── Upload Excel ──────────────────────────────────────────────────

  Future<void> _uploadExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        withData: true, // Need bytes for web/desktop crossover
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes == null) {
          _snack('Could not read file data.', bg: Colors.red);
          return;
        }

        setState(() => _isUploading = true);

        final api = ApiService();
        final res = await api.uploadExcel(file.bytes!, file.name);

        if (res['success'] == true) {
          _snack('Uploaded successfully ✓', bg: const Color(0xFF059669));
        } else {
          _snack('Upload failed: ${res['message']}', bg: Colors.red);
        }
      }
    } catch (e) {
      _snack('Error: $e', bg: Colors.red);
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSourceCard(),
                      const SizedBox(height: 24),
                      if (_connectionOk) ...[
                        _buildDatabaseCard(),
                        const SizedBox(height: 24),
                        _buildTargetCard(),
                      ],
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isUploading ? null : _uploadExcel,
                            icon: _isUploading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.upload_file, size: 18),
                            label: const Text('Upload Data File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: const Row(
        children: [
          Icon(Icons.settings_outlined, color: Color(0xFF2563EB), size: 22),
          SizedBox(width: 10),
          Text(
            'Database Configuration',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard() {
    return _card(
      title: 'Source Database',
      icon: Icons.storage_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _field('Server Name / IP', _serverCtrl)),
              const SizedBox(width: 16),
              Expanded(child: _field('Port', _portCtrl)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _field('Username', _userCtrl)),
              const SizedBox(width: 16),
              Expanded(child: _field('Password', _passCtrl, obscure: true)),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cable_outlined, size: 16),
              label: const Text('Test Connection'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabaseCard() {
    return _card(
      title: 'Select Database',
      icon: Icons.table_chart_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Database',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          _DbDropdown(
            hint: 'Select database',
            value: _selectedDb,
            items: _dbs,
            onChange: (val) {
              if (val != null) setState(() => _selectedDb = val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard() {
    return _card(
      title: 'Target Database',
      icon: Icons.cloud_upload_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Same-as-source checkbox
          Row(
            children: [
              Checkbox(
                value: _sameAsSource,
                activeColor: const Color(0xFF2563EB),
                onChanged: (v) => setState(() => _sameAsSource = v ?? false),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Same as Source',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
            ],
          ),

          if (!_sameAsSource) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _field('Server Name / IP', _tServerCtrl)),
                const SizedBox(width: 16),
                Expanded(child: _field('Port', _tPortCtrl)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _field('Username', _tUserCtrl)),
                const SizedBox(width: 16),
                Expanded(child: _field('Password', _tPassCtrl, obscure: true)),
              ],
            ),
          ],

          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _isLoadingData ? null : _loadDataset,
              icon: _isLoadingData
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: const Text('Load Dataset'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}

class _DbDropdown extends StatefulWidget {
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChange;

  const _DbDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChange,
  });

  @override
  State<_DbDropdown> createState() => _DbDropdownState();
}

class _DbDropdownState extends State<_DbDropdown> {
  final _key = GlobalKey();
  bool _isOpen = false;

  Future<void> _open() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final rect = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + size.height,
      topLeft.dx + size.width,
      topLeft.dy + size.height,
    );

    setState(() => _isOpen = true);

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      initialValue: widget.value,
      elevation: 4,
      constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: widget.items
          .map(
            (e) => PopupMenuItem<String>(
              value: e,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                e,
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF1E293B),
                  fontWeight: e == widget.value
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
    );

    if (!mounted) return;
    setState(() => _isOpen = false);
    if (selected != null) widget.onChange(selected);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.value != null && widget.value!.isNotEmpty;
    return GestureDetector(
      onTap: _open,
      child: Container(
        key: _key,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _isOpen ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
            width: _isOpen ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hasValue ? widget.value! : widget.hint,
                style: TextStyle(
                  fontSize: 14,
                  color: hasValue
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF94A3B8),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AnimatedRotation(
              turns: _isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
