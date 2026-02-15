import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> project;
  final String userRole;

  const ProjectDetailsScreen({
    super.key, 
    required this.project,
    this.userRole = 'customer',
  });

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  bool _isUpdatingStatus = false;
  late String _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.project['status']?.toString().toLowerCase() ?? 'enquiry';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _updateProjectStatus(String newStatus) async {
    setState(() => _isUpdatingStatus = true);
    try {
      await Supabase.instance.client
          .from('projects')
          .update({'status': newStatus})
          .eq('id', widget.project['id']);
      
      // Also add a system activity for this
      await Supabase.instance.client.from('project_activity').insert({
        'project_id': widget.project['id'],
        'message': 'PHASE UPDATED TO ${newStatus.toUpperCase()}',
        'created_by': null, // System message
      });

      if (mounted) {
        setState(() => _currentStatus = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status Synchronized: ${newStatus.toUpperCase()}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('System Update Failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _addAdminFile(String name, String url) async {
    try {
      await Supabase.instance.client.from('project_files').insert({
        'project_id': widget.project['id'],
        'file_name': name,
        'file_url': url,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document Indexed Successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indexing Failed')),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.from('project_activity').insert({
        'project_id': widget.project['id'],
        'message': text,
        'created_by': user.id,
      });

      _messageController.clear();
      // Scroll to bottom after sending
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      debugPrint('Chat Transmission Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Comms Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showStatusPicker() {
    final statusSteps = ['enquiry', 'design', 'material', 'installation', 'completed'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SET PROJECT PHASE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.0)),
              const SizedBox(height: 16),
              ...statusSteps.map((s) => ListTile(
                title: Text(s.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(
                  fontWeight: s == _currentStatus ? FontWeight.w900 : FontWeight.w500,
                  color: s == _currentStatus ? const Color(0xFF1A1A1A) : Colors.grey,
                )),
                onTap: () {
                  Navigator.pop(context);
                  _updateProjectStatus(s);
                },
              )),
            ],
          ),
        );
      },
    );
  }

  void _showFileUploadDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('INDEX TECHNICAL DOCUMENT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'DOCUMENT NAME', labelStyle: TextStyle(fontSize: 10))),
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'FILE URL', labelStyle: TextStyle(fontSize: 10))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && urlCtrl.text.isNotEmpty) {
                _addAdminFile(nameCtrl.text, urlCtrl.text);
                Navigator.pop(context);
              }
            },
            child: const Text('INDEX'),
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(String? url, String fileName) async {
    // ... (existing code remains same)
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Technical Error: Data empty')),
        );
      }
      return;
    }

    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Launch failed';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('System Alert: Could not open document $fileName')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.project['id'];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(widget.project['project_name']?.toString().toUpperCase() ?? 'DETAILS'),
          elevation: 0,
          backgroundColor: Colors.white,
          centerTitle: false,
          bottom: const TabBar(
            indicatorColor: Color(0xFF1A1A1A),
            indicatorWeight: 3,
            labelColor: Color(0xFF1A1A1A),
            unselectedLabelColor: Colors.grey,
            labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.0),
            tabs: [
              Tab(text: 'OVERVIEW'),
              Tab(text: 'COMMUNICATION'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Overview
            SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAdminControls(),
                  _buildSectionHeader('Phase Tracking'),
                  const SizedBox(height: 16),
                  _buildProgressTracker(),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Specifications'),
                  const SizedBox(height: 16),
                  _buildInfoCard(),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Documentation'),
                  const SizedBox(height: 16),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Supabase.instance.client
                        .from('project_files')
                        .stream(primaryKey: ['id'])
                        .eq('project_id', projectId)
                        .order('uploaded_at'),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(strokeWidth: 2)));
                      }
                      final files = snapshot.data ?? [];
                      return _buildFilesList(files);
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            // Tab 2: Communication
            _buildChatInterface(projectId),
          ],
        ),
      ),
    );
  }

  Widget _buildChatInterface(dynamic projectId) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('project_activity')
                .stream(primaryKey: ['id'])
                .eq('project_id', projectId)
                .order('created_at'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }

              final activities = snapshot.data ?? [];
              final sortedActivities = List<Map<String, dynamic>>.from(activities)
                ..sort((a, b) => b['created_at'].compareTo(a['created_at']));

              if (sortedActivities.isEmpty) {
                return Center(child: _buildEmptyState('No communications found on frequency'));
              }

              return ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.all(24),
                itemCount: sortedActivities.length,
                itemBuilder: (context, index) {
                  final activity = sortedActivities[index];
                  final isSystem = activity['created_by'] == null;
                  final isMe = activity['created_by'] == currentUserId;

                  if (isSystem) {
                    return _buildSystemLogTile(activity);
                  }
                  return _buildChatBubble(activity, isMe);
                },
              );
            },
          ),
        ),
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildSystemLogTile(Map<String, dynamic> activity) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'SYSTEM UPDATE: ${activity['message']?.toString().toUpperCase()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: Colors.grey,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            activity['created_at'] != null
                ? DateTime.parse(activity['created_at']).toLocal().toString().substring(11, 16)
                : '--:--',
            style: TextStyle(fontSize: 8, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> activity, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activity['message'] ?? '',
              style: TextStyle(
                color: isMe ? Colors.white : const Color(0xFF1A1A1A),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              activity['created_at'] != null
                  ? DateTime.parse(activity['created_at']).toLocal().toString().substring(11, 16)
                  : '',
              style: TextStyle(
                color: isMe ? Colors.white60 : Colors.grey[400],
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Transmit message...',
                hintStyle: TextStyle(color: Colors.grey[300], fontSize: 13, letterSpacing: 0.5),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1A1A1A)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    // ... (rest of helper methods remain same)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 24,
          height: 2,
          color: const Color(0xFF1A1A1A),
        ),
      ],
    );
  }

  Widget _buildProgressTracker() {
    final statusSteps = ['enquiry', 'design', 'material', 'installation', 'completed'];
    final currentStatus = _currentStatus;
    final currentStepIndex = statusSteps.indexOf(currentStatus);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(statusSteps.length, (index) {
              final isCompleted = index <= currentStepIndex;
              final isLast = index == statusSteps.length - 1;

              return Expanded(
                flex: isLast ? 0 : 1,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isCompleted ? const Color(0xFF1A1A1A) : Colors.white,
                        border: Border.all(
                          color: isCompleted ? const Color(0xFF1A1A1A) : Colors.grey[300]!,
                          width: 2,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          height: 1.5,
                          color: index < currentStepIndex ? const Color(0xFF1A1A1A) : Colors.grey[200],
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(statusSteps.length, (index) {
              final isCurrent = index == currentStepIndex;
              final label = statusSteps[index];
              return Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w500,
                  letterSpacing: 0.5,
                  color: isCurrent ? const Color(0xFF1A1A1A) : Colors.grey[400],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminControls() {
    if (widget.userRole != 'admin') return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Management Actions'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _showStatusPicker,
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: const Text('SYNC STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showFileUploadDialog,
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('INDEX FILE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A1A1A),
                  side: const BorderSide(color: Color(0xFF1A1A1A)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1.5),
      ),
      child: Column(
        children: [
          _buildInfoTile('Site Location', widget.project['location'] ?? 'Information restricted', Icons.map_outlined),
          const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 24, endIndent: 24),
          _buildInfoTile('Current Phase', widget.project['status']?.toString().toUpperCase() ?? 'RECONNAISSANCE', Icons.architecture_outlined),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1A1A1A)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 1.0),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTimeline(List<Map<String, dynamic>> activities) {
    if (activities.isEmpty) {
      return _buildEmptyState('No events recorded in system log');
    }

    final sortedActivities = List<Map<String, dynamic>>.from(activities)
      ..sort((a, b) => b['created_at'].compareTo(a['created_at']));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedActivities.length,
      itemBuilder: (context, index) {
        final activity = sortedActivities[index];
        final isLast = index == sortedActivities.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1A),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 1,
                    height: 60,
                    color: const Color(0xFFEEEEEE),
                  ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity['message'] ?? 'SYSTEM LOG ENTRY',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        activity['created_at'] != null
                            ? DateTime.parse(activity['created_at']).toLocal().toString().substring(0, 16)
                            : 'TIMESTAMP RECORDED',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey[500]),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• SYSTEM UPDATED',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilesList(List<Map<String, dynamic>> files) {
    if (files.isEmpty) {
      return _buildEmptyState('No engineering documents shared');
    }

    final sortedFiles = List<Map<String, dynamic>>.from(files)
      ..sort((a, b) => b['uploaded_at'].compareTo(a['uploaded_at']));

    return Column(
      children: sortedFiles.map((file) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const Icon(Icons.description_outlined, color: Color(0xFF1A1A1A), size: 20),
            title: Text(
              file['file_name']?.toString().toUpperCase() ?? 'DOCUMENT',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            subtitle: Text(
              'RELEASED: ${file['uploaded_at']?.toString().substring(0, 10) ?? 'RECENT'}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            trailing: const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
            onTap: () => _openFile(file['file_url'], file['file_name'] ?? 'File'),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F0), width: 1),
      ),
      child: Center(
        child: Text(
          message.toUpperCase(),
          style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0),
        ),
      ),
    );
  }
}
