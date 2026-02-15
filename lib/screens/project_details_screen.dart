import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

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
  bool _isUploading = false;
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

  Future<void> _addAdminFile(String name, String path) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      await Supabase.instance.client.from('project_files').insert({
        'project_id': widget.project['id'],
        'file_name': name,
        'file_url': path,
        'uploaded_by': user?.id,
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

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;

      setState(() => _isUploading = true);
      
      final file = result.files.first;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final path = '${widget.project['id']}/$fileName';

      if (file.bytes != null) {
        await Supabase.instance.client.storage
            .from('project-files')
            .uploadBinary(path, file.bytes!);
      } else if (file.path != null) {
        await Supabase.instance.client.storage
            .from('project-files')
            .upload(path, File(file.path!));
      } else {
        throw 'No file data available';
      }

      await _addAdminFile(file.name, path);
    } catch (e) {
      debugPrint('Upload Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload Failure: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
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

  void _showAddUpdateDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TRANSMIT PROJECT UPDATE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter status report...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                final text = ctrl.text.trim();
                final user = Supabase.instance.client.auth.currentUser;
                await Supabase.instance.client.from('project_activity').insert({
                  'project_id': widget.project['id'],
                  'message': text.toUpperCase(),
                  'created_by': user?.id,
                });
                if (mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('DISPATCH'),
          ),
        ],
      ),
    );
  }

  void _showAdminMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MANAGEMENT OVERRIDE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
            const SizedBox(height: 24),
            _buildMenuOption(
              icon: Icons.sync_rounded,
              title: 'PHASE SYNCHRONIZATION',
              subtitle: 'Update current project status',
              onTap: () {
                Navigator.pop(context);
                _showStatusPicker();
              },
            ),
            const SizedBox(height: 16),
            _buildMenuOption(
              icon: Icons.upload_file_rounded,
              title: 'TECHNICAL DOCUMENTATION',
              subtitle: 'Upload site drawings or specs',
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadFile();
              },
            ),
            const SizedBox(height: 16),
            _buildMenuOption(
              icon: Icons.assignment_turned_in_rounded,
              title: 'DAILY PROGRESS REPORT',
              subtitle: 'Submit work log, materials & manpower',
              onTap: () {
                Navigator.pop(context);
                _showDPRForm();
              },
            ),
            const SizedBox(height: 16),
            _buildMenuOption(
              icon: Icons.notification_add_rounded,
              title: 'SYSTEM BROADCAST',
              subtitle: 'Dispatch project update to client',
              onTap: () {
                Navigator.pop(context);
                _showAddUpdateDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuOption({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: const Color(0xFF1A1A1A)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
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

  Future<void> _openFile(String? path, String fileName) async {
    if (path == null || path.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Technical Error: Data empty')),
        );
      }
      return;
    }

    try {
      // SECURE ACCESS: Generate a signed URL for 1 hour for the private bucket
      final signedUrl = await Supabase.instance.client.storage
          .from('project-files')
          .createSignedUrl(path, 3600);
      
      final uri = Uri.parse(signedUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Launch failed';
      }
    } catch (e) {
      debugPrint('Signed URL Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('System Alert: Access denied for $fileName')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.project['id'];

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.white,
        floatingActionButton: widget.userRole == 'admin' ? FloatingActionButton(
          onPressed: _showAdminMenu,
          backgroundColor: Colors.black,
          elevation: 0,
          shape: const CircleBorder(),
          child: const Icon(Icons.add_moderator_rounded, color: Colors.white),
        ) : null,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 0,
              toolbarHeight: 0,
              scrolledUnderElevation: 0,
              backgroundColor: const Color(0xFF1E1E1E), // Match hero background
            ),
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 60, 28, 48),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back Button & Status Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                        _buildStatusBadge(_currentStatus, isDark: true),
                      ],
                    ),
                    const SizedBox(height: 40),
                    
                    // Project Title
                    Text(
                      widget.project['project_name']?.toString() ?? 'Project',
                      style: const TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.w800, 
                        letterSpacing: -0.5, 
                        color: Colors.white,
                        height: 1.1
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.project['location'] ?? 'Access Restricted',
                      style: const TextStyle(fontSize: 16, color: Colors.white54, fontWeight: FontWeight.w500),
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Progress Section (Dark Mode)
                    _buildHeroProgress(isDark: true),
                  ],
                ),
              ),
            ),
            
            // Floating Stats Row
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: _buildQuickStats(projectId),
              ),
            ),

            // Persistent Tabs
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFF0F0F0)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const TabBar(
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorColor: Colors.black,
                    indicatorWeight: 3,
                    labelColor: Colors.black,
                    unselectedLabelColor: Color(0xFF999999),
                    labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.5),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    tabs: [
                      Tab(text: 'TIMELINE'),
                      Tab(text: 'DOCS'),
                      Tab(text: 'LOGS'),
                      Tab(text: 'CHAT'),
                    ],
                  ),
                ),
                90.0,
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _buildTimelineTab(projectId),
              _buildDocumentsTab(projectId),
              _buildSiteDiaryTab(projectId),
              _buildChatTab(projectId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, {bool isDark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4CAF50) : Colors.black, 
              shape: BoxShape.circle
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 11, 
              fontWeight: FontWeight.w700, 
              letterSpacing: 0.5, 
              color: isDark ? Colors.white : Colors.black
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroProgress({bool isDark = false}) {
    final steps = ['enquiry', 'design', 'material', 'installation', 'completed'];
    final idx = steps.indexOf(_currentStatus.toLowerCase());
    final progress = (idx + 1) / steps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('COMPLETION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.white54 : const Color(0xFF999999), letterSpacing: 1.0)),
            Text('${(progress * 100).toInt()}%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFEEEEEE),
            valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white : Colors.black),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(dynamic projectId) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _buildQuickStatCard('DOCUMENTS', Icons.folder_open_rounded, projectId, 'project_files'),
          const SizedBox(width: 16),
          _buildQuickStatCard('SITE LOGS', Icons.grid_view_rounded, projectId, 'project_dpr'),
          const SizedBox(width: 16),
          _buildQuickStatCard('TEAM', Icons.people_outline_rounded, projectId, null),
        ],
      ),
    );
  }

  Widget _buildQuickStatCard(String label, IconData icon, dynamic projectId, String? table) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: Colors.black87),
          const SizedBox(height: 24),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF999999), letterSpacing: 0.5)),
          const SizedBox(height: 8),
          if (table != null)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client.from(table).stream(primaryKey: ['id']).eq('project_id', projectId.toString()),
              builder: (context, snapshot) => Text(
                '${snapshot.data?.length ?? 0}',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111111)),
              ),
            )
          else
             const Text('3', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111111))),
        ],
      ),
    );
  }

  Widget _buildTimelineTab(dynamic projectId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getMergedTimeline(projectId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        
        final events = snapshot.data ?? [];
        if (events.isEmpty) return Center(child: _buildEmptyState('Project history starting soon...'));
 
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            final type = event['type'] ?? 'system';
            final isLast = index == events.length - 1;
 
            IconData icon;
            Color iconColor;
            String title;
            String? details;
 
            switch (type) {
              case 'dpr':
                icon = Icons.assignment_turned_in_rounded;
                iconColor = const Color(0xFF111111);
                title = 'SITE REPORT';
                details = event['work_done'];
                break;
              case 'file':
                icon = Icons.attach_file_rounded;
                iconColor = Colors.blueGrey;
                title = event['message'] ?? 'NEW DOCUMENT';
                break;
              default:
                icon = Icons.info_outline_rounded;
                iconColor = Colors.grey;
                title = event['message'] ?? 'UPDATE';
            }
 
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: iconColor, width: 3),
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (!isLast)
                        Expanded(child: Container(width: 2, color: const Color(0xFFF5F5F7))),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                title,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF111111), letterSpacing: 0.5),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  DateTime.parse(event['created_at']).toLocal().toString().substring(5, 16).replaceAll('-', '/'),
                                  style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (details != null) 
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFF5F5F7)),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Text(details, style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87)),
                          ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getMergedTimeline(dynamic projectId) async {
    try {
      final activity = await Supabase.instance.client
          .from('project_activity')
          .select()
          .eq('project_id', projectId.toString());
          
      final dpr = await Supabase.instance.client
          .from('project_dpr')
          .select()
          .eq('project_id', projectId.toString());

      final files = await Supabase.instance.client
          .from('project_files')
          .select()
          .eq('project_id', projectId.toString());
      
      final all = <Map<String, dynamic>>[];
      
      for (var a in activity) {
        if (a['created_by'] == null) {
          all.add({...a, 'type': 'system'});
        }
      }
      for (var d in dpr) {
        all.add({...d, 'type': 'dpr', 'created_at': d['created_at']}); // Ensure timestamp key matches
      }
      for (var f in files) {
        all.add({
          ...f, 
          'type': 'file', 
          'message': 'DOCUMENT UPLOADED: ${f['file_name']}'.toUpperCase(),
          'created_at': f['uploaded_at'] 
        });
      }

      all.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
      return all;
    } catch (e) {
      debugPrint('Timeline Error: $e');
      return [];
    }
  }

  Widget _buildDocumentsTab(dynamic projectId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('project_files').stream(primaryKey: ['id']).eq('project_id', projectId.toString()).order('uploaded_at'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        final files = snapshot.data ?? [];
        if (files.isEmpty) return Center(child: _buildEmptyState('No engineering documents shared'));

        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.1),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            return InkWell(
              onTap: () => _openFile(file['file_url'], file['file_name']),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF0F0F0)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.description_outlined, size: 32, color: Color(0xFF111111)),
                    const SizedBox(height: 12),
                    Text(
                      file['file_name']?.toUpperCase() ?? 'DOC',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file['uploaded_at'].toString().substring(0, 10),
                      style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSiteDiaryTab(dynamic projectId) {
    return _buildDPRTab(projectId);
  }

  Widget _buildChatTab(dynamic projectId) {
    return _buildChatInterface(projectId);
  }

  Widget _buildChatInterface(dynamic projectId) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Safety check: If available height is too small (e.g. keyboard open + header expanded),
        // prioritize the input field and avoid overflow errors.
        if (constraints.maxHeight < 120) {
          return Column(
            children: [
              const Spacer(),
              _buildMessageInput(),
            ],
          );
        }

        return Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('project_activity')
                    .stream(primaryKey: ['id'])
                    .eq('project_id', projectId.toString())
                    .order('created_at'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  }
    
                  final activities = snapshot.data ?? [];
                  // Filter out system messages for this tab
                  final humanActivities = activities.where((a) => a['created_by'] != null).toList();
                  final sortedActivities = List<Map<String, dynamic>>.from(humanActivities)
                    ..sort((a, b) => b['created_at'].compareTo(a['created_at']));
    
                  if (sortedActivities.isEmpty) {
                    return Center(child: _buildEmptyState('Direct secure channel active'));
                  }
    
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(24),
                    itemCount: sortedActivities.length,
                    itemBuilder: (context, index) {
                      final activity = sortedActivities[index];
                      final isMe = activity['created_by'] == currentUserId;
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
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 4),
              child: Text('FINEGLAZE TEAM', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF111111) : const Color(0xFFF5F5F5),
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
                    color: isMe ? Colors.white : const Color(0xFF111111),
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
        ],
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

  Widget _buildDPRTab(dynamic projectId) {
    if (projectId == null) return Center(child: _buildEmptyState('Project ID missing from context'));
    
    // Trim ID to prevent filter mismatch if spaces exist
    final idString = projectId.toString().trim();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('project_dpr')
          .stream(primaryKey: ['id'])
          .eq('project_id', idString)
          .order('report_date', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('DPR Stream Error: ${snapshot.error}');
          return Center(child: _buildEmptyState('Sync Error: Check Realtime/RLS settings'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final reports = snapshot.data ?? [];
        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildEmptyState('No daily logs found in database'),
                const SizedBox(height: 12),
                Text('PROJECT ID: ${idString.substring(0, 8)}...', style: const TextStyle(fontSize: 8, color: Colors.grey)),
                Text('RAW COUNT: ${reports.length}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            return _buildDPRCard(report);
          },
        );
      },
    );
  }

  Widget _buildDPRCard(Map<String, dynamic> report) {
    final dateStr = _formatDPRDate(report['report_date'] ?? '');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DAILY SITE LOG', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(dateStr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF111111))),
                  ],
                ),
                _buildStatusBadge('LOGGED'),
              ],
            ),
          ),
          
          // Photo if available
          if (report['photo_url'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildDPRImage(report['photo_url']),
              ),
            ),

          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChip(Icons.people_outline, 'WORKERS: ${report['workers_count']}'),
                    if (report['material_used']?.toString().isNotEmpty == true)
                      _buildChip(Icons.inventory_2_outlined, 'MATERIALS LOGGED'),
                  ],
                ),
                const SizedBox(height: 24),
                _buildDPRSection('WORK DONE', report['work_done']),
                if (report['remarks']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  _buildDPRSection('SITE NOTES', report['remarks']),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey[800])),
        ],
      ),
    );
  }

  Widget _buildDPRImage(String path) {
    return FutureBuilder<String>(
      future: Supabase.instance.client.storage
          .from('dpr-photos')
          .createSignedUrl(path, 3600),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
          if (snapshot.hasError) {
            return Container(
              height: 200,
              width: double.infinity,
              color: const Color(0xFFF5F5F5),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image_outlined, color: Colors.grey, size: 32),
                  SizedBox(height: 8),
                  Text('IMAGE ACCESS DENIED', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w900)),
                ],
              ),
            );
          }
          return Container(
            height: 200, 
            color: const Color(0xFFF0F0F0), 
            child: const Center(child: CircularProgressIndicator(strokeWidth: 1)),
          );
        }
        return Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            image: DecorationImage(image: NetworkImage(snapshot.data!), fit: BoxFit.cover),
          ),
        );
      },
    );
  }

  Widget _buildDPRSection(String label, String? content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(content ?? 'NO DATA RECORDED', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1A1A1A), height: 1.4)),
      ],
    );
  }

  String _formatDPRDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
      return "${date.day} ${months[date.month - 1]}, ${date.year}";
    } catch (e) {
      return dateStr;
    }
  }

  void _showDPRForm() {
    final workCtrl = TextEditingController();
    final materialCtrl = TextEditingController();
    final workersCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    PlatformFile? pickedPhoto;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            titlePadding: EdgeInsets.zero,
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            content: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SITE PROGRESS REPORT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
                  const SizedBox(height: 24),
                  
                  // Date Picker
                  _buildFormLabel('REPORT DATE'),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setModalState(() => selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${selectedDate.toLocal()}".split(' ')[0], style: const TextStyle(fontWeight: FontWeight.w700)),
                          const Icon(Icons.calendar_today_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildFormField(workCtrl, 'WORK EXECUTED', 'Describe tasks completed...', maxLines: 3),
                  _buildFormField(materialCtrl, 'MATERIALS USED', 'List materials utilized...'),
                  _buildFormField(workersCtrl, 'MANPOWER', 'Number of workers occupied', keyboardType: TextInputType.number),
                  _buildFormField(remarksCtrl, 'ADDITIONAL REMARKS', 'Any site alerts or notes...', maxLines: 2),
                  
                  const SizedBox(height: 12),
                  _buildFormLabel('SITE PHOTOGRAPH'),
                  InkWell(
                    onTap: () async {
                      final result = await FilePicker.platform.pickFiles(type: FileType.image);
                      if (result != null) setModalState(() => pickedPhoto = result.files.first);
                    },
                    child: Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9F9),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                        borderRadius: BorderRadius.circular(12),
                        image: pickedPhoto != null ? DecorationImage(
                          image: pickedPhoto!.bytes != null 
                            ? MemoryImage(pickedPhoto!.bytes!) 
                            : FileImage(File(pickedPhoto!.path!)) as ImageProvider,
                          fit: BoxFit.cover) : null,
                      ),
                      child: pickedPhoto == null ? const Center(child: Icon(Icons.add_a_photo_outlined, color: Colors.grey)) : null,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: () => _submitDPR(context, workCtrl.text, materialCtrl.text, workersCtrl.text, remarksCtrl.text, selectedDate, pickedPhoto),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('SUBMIT DPR'),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildFormLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.grey)),
    );
  }

  Widget _buildFormField(TextEditingController ctrl, String label, String hint, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormLabel(label),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEEEEEE))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEEEEEE))),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitDPR(BuildContext context, String work, String material, String workers, String remarks, DateTime date, PlatformFile? photo) async {
    if (work.isEmpty) return;

    // Show loading on top of dialog
    setState(() => _isUploading = true);
    Navigator.pop(context); // Close form

    try {
      String? photoPath;
      if (photo != null) {
        // Use flat structure instead of nested folders
        photoPath = 'dpr_${DateTime.now().millisecondsSinceEpoch}_${photo.name}';

        if (photo.bytes != null) {
          await Supabase.instance.client.storage.from('dpr-photos').uploadBinary(photoPath, photo.bytes!);
        } else if (photo.path != null) {
          await Supabase.instance.client.storage.from('dpr-photos').upload(photoPath, File(photo.path!));
        }
      }

      await Supabase.instance.client.from('project_dpr').insert({
        'project_id': widget.project['id'],
        'report_date': date.toIso8601String().split('T')[0],
        'work_done': work,
        'material_used': material,
        'workers_count':  int.tryParse(workers) ?? 0,
        'remarks': remarks,
        'photo_url': photoPath,
        'created_by': Supabase.instance.client.auth.currentUser?.id,
      });

      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('DPR Submitted Successfully')));
      }
    } catch (e) {
      debugPrint('DPR Submission Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Submission Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._child, this._height);

  final Widget _child;
  final double _height;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: _child,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
