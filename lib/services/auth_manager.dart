import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthManager extends ChangeNotifier {
  static final AuthManager _instance = AuthManager._internal();
  factory AuthManager() => _instance;

  AuthManager._internal() {
    _initialize();
  }

  void _initialize() {
    // Single global subscription to auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final Session? newSession = data.session;
      
      if (newSession == null) {
        _session = null;
        _role = null;
        _customerId = null;
        _isInitializing = false;
        notifyListeners();
      } else {
        // Only refresh if session changed or we haven't initialized yet
        if (_session?.user.id != newSession.user.id || _session == null) {
          _session = newSession;
          _refreshUserData();
        }
      }
    });
    
    // Initial check
    final initialSession = Supabase.instance.client.auth.currentSession;
    if (initialSession != null) {
      _session = initialSession;
      _refreshUserData();
    } else {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Session? _session;
  String? _role;
  String? _customerId;
  bool _isInitializing = true;
  bool _isRefreshing = false;

  Session? get session => _session;
  String? get role => _role;
  String? get customerId => _customerId;
  bool get isInitializing => _isInitializing;

  Future<void> _refreshUserData() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _isInitializing = true;
    
    final user = _session?.user;
    if (user == null) {
      _isRefreshing = false;
      _isInitializing = false;
      notifyListeners();
      return;
    }

    debugPrint('AUTH_SYNC: Initiating resilient sync for UID: ${user.id}');
    
    try {
      Map<String, dynamic>? profile;
      int retries = 0;
      
      // Step 1: Resilient Profile Fetch (Allowing for trigger lag)
      while (retries < 3) {
        profile = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
        
        if (profile != null) break;
        
        retries++;
        debugPrint('AUTH_SYNC: Profile not found. Retry $retries/3...');
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      if (profile == null) {
        debugPrint('RESTRICTED ACCESS: Profile missing after retries.');
        await signOut();
        return;
      }

      _role = profile['role'];

      // Step 2: Resilient Customer Linkage
      if (_role == 'customer') {
        Map<String, dynamic>? customer;
        retries = 0;
        
        while (retries < 3) {
          customer = await Supabase.instance.client
              .from('customers')
              .select('id')
              .eq('user_id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));
          
          if (customer != null) break;
          
          retries++;
          debugPrint('AUTH_SYNC: Customer reference not found. Retry $retries/3...');
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (customer == null) {
          debugPrint('RESTRICTED ACCESS: Customer linkage failed.');
          await signOut();
          return;
        }
        _customerId = customer['id'];
      }
      
      _isInitializing = false;
    } catch (e) {
      debugPrint('CRITICAL: Sync Engine Failure: $e');
      await signOut();
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    // Only sign out if we actually have a session to avoid loops
    if (_session != null || Supabase.instance.client.auth.currentSession != null) {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    }
    _session = null;
    _role = null;
    _customerId = null;
    _isInitializing = false;
    _isRefreshing = false;
    notifyListeners();
  }
}
