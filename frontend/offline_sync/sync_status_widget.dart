//sync_status_widget.dart

import 'package:flutter/material.dart';
import 'local_db_helper.dart';
import 'sync_service.dart';
import 'network_service.dart';

class SyncStatusWidget extends StatefulWidget {
  const SyncStatusWidget({Key? key}) : super(key: key);

  @override
  _SyncStatusWidgetState createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  final LocalDBHelper _localDB = LocalDBHelper();
  final SyncService _syncService = SyncService();
  final NetworkService _networkService = NetworkService();
  
  int _pendingRecords = 0;
  bool _isSyncing = false;
  bool _isOnline = true;
  
  @override
  void initState() {
    super.initState();
    _loadPendingRecords();
    _setupNetworkListener();
    _startAutoSync();
  }
  
  void _setupNetworkListener() {
    _networkService.onConnectionChange.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        if (isOnline) {
          _startAutoSync();
        }
      }
    });
  }
  
  void _startAutoSync() async {
    if (_isSyncing) return;
    
    final isOnline = await _networkService.isConnected();
    if (isOnline && _pendingRecords > 0) {
      _syncNow();
    }
  }
  
  Future<void> _loadPendingRecords() async {
    final count = await _localDB.getPendingRecordsCount();
    if (mounted) {
      setState(() {
        _pendingRecords = count;
      });
    }
  }
  
  Future<void> _syncNow() async {
    if (_isSyncing) return;
    
    setState(() {
      _isSyncing = true;
    });
    
    final success = await _syncService.syncPendingRecords();
    
    if (mounted) {
      setState(() {
        _isSyncing = false;
      });
      
      await _loadPendingRecords();
      
      if (success && _pendingRecords == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ All records synced successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_pendingRecords == 0 && _isOnline) return SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isSyncing) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            SizedBox(width: 6),
          ] else ...[
            Icon(_getStatusIcon(), size: 14, color: Colors.white),
            SizedBox(width: 6),
          ],
          Text(
            _getStatusText(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_pendingRecords > 0 && !_isSyncing) ...[
            SizedBox(width: 4),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_pendingRecords',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Color _getStatusColor() {
    if (_isSyncing) return Colors.blue;
    if (!_isOnline) return Colors.orange;
    if (_pendingRecords > 0) return Colors.blue;
    return Colors.green;
  }
  
  IconData _getStatusIcon() {
    if (!_isOnline) return Icons.cloud_off;
    if (_pendingRecords > 0) return Icons.sync_problem;
    return Icons.cloud_done;
  }
  
  String _getStatusText() {
    if (_isSyncing) return 'Syncing...';
    if (!_isOnline) return 'Offline';
    if (_pendingRecords > 0) return 'Pending sync';
    return 'Synced';
  }
}
