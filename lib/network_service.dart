import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  final Connectivity _connectivity = Connectivity();
  
  Future<bool> isConnected() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      print('🔍 DEBUG: Connectivity result: $connectivityResult');
      
      final bool isConnected = connectivityResult != ConnectivityResult.none;
      print('🔍 DEBUG: Is connected: $isConnected');
      
      return isConnected;
    } catch (e) {
      print('🔍 DEBUG: Connectivity check error: $e');
      return false;
    }
  }
  
  Stream<bool> get onConnectionChange {
    return _connectivity.onConnectivityChanged.map(
      (result) {
        final isConnected = result != ConnectivityResult.none;
        print('🔍 DEBUG: Connection changed - Online: $isConnected');
        return isConnected;
      }
    );
  }
}