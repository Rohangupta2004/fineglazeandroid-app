import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'project_details_screen.dart';
import 'account_settings_screen.dart';
import '../services/auth_manager.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Stream<List<Map<String, dynamic>>>? _projectStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final auth = AuthManager();
    final role = auth.role;
    final customerId = auth.customerId;

    if (role == 'admin') {
      _projectStream = Supabase.instance.client
          .from('projects')
          .stream(primaryKey: ['id'])
          .order('created_at');
    } else if (role == 'customer' && customerId != null) {
      _projectStream = Supabase.instance.client
          .from('projects')
          .stream(primaryKey: ['id'])
          .eq('customer_id', customerId)
          .order('created_at');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthManager();
    final role = auth.role;
    final customerId = auth.customerId;

    // Safety check - though handled by global navigator gate
    if (role == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    if (role == 'customer' && customerId == null) {
      final user = Supabase.instance.client.auth.currentUser;
      return Scaffold(
        appBar: AppBar(title: const Text('FineGlaze Dashboard')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_person_outlined, size: 64, color: Colors.redAccent),
                const SizedBox(height: 24),
                const Text('ACCESS DENIED', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.0)),
                const SizedBox(height: 12),
                const Text('NO CUSTOMER REFERENCE LINKED TO THIS ACCOUNT.', 
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text('TECHNICAL DIAGNOSTICS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text('UID: ${user?.id ?? 'Unknown'}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                      Text('RESOLVED ROLE: ${role.toUpperCase()}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: () => AuthManager().signOut(),
                  child: const Text('SIGN OUT AND RE-AUTHENTICATE'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_projectStream == null) {
      return const Scaffold(
        body: Center(child: Text('STREAM INITIALIZATION ERROR')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'asset/fineglaze.png',
              height: 28,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text('PROJECTS'),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AccountSettingsScreen()),
                );
              },
              icon: const Icon(Icons.person_outline_rounded, size: 20),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              role == 'admin' ? 'Management Console' : 'Active Portfolio',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _projectStream!,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Technical Error: ${snapshot.error}', 
                      style: const TextStyle(color: Colors.redAccent)),
                  );
                }

                final projects = snapshot.data ?? [];

                if (projects.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text('No records found', 
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  itemCount: projects.length,
                  itemBuilder: (context, index) {
                    final project = projects[index];
                    final status = project['status']?.toString().toLowerCase() ?? 'enquiry';
                    final statusSteps = ['enquiry', 'design', 'material', 'installation', 'completed'];
                    final currentStepIndex = statusSteps.indexOf(status);
                    final progress = (currentStepIndex + 1) / statusSteps.length;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEEEEEE), width: 1.5),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProjectDetailsScreen(
                                project: project,
                                userRole: role ?? 'customer',
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          project['project_name']?.toString().toUpperCase() ?? 'UNNAMED PROJECT',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            letterSpacing: 1.0,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[500]),
                                            const SizedBox(width: 4),
                                            Text(
                                              project['location'] ?? 'Location specified on request',
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: progress == 1.0 ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                        color: progress == 1.0 ? Colors.green[700] : Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(100),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        backgroundColor: const Color(0xFFF0F0F0),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          progress == 1.0 ? Colors.green : const Color(0xFF1A1A1A),
                                        ),
                                        minHeight: 4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${(progress * 100).toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}



