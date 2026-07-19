import 'package:flutter/material.dart';

import '../api/ping_api.dart';
import '../network/api_client.dart';
import '../services/ping_service.dart';

/// UI 계층: 비즈니스 로직 계층만 호출한다. Dio나 엔드포인트를 알지 못한다.
class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  final _service = PingService(PingApi(ApiClient()));

  String _result = '아직 테스트하지 않음';
  bool _loading = false;

  Future<void> _runTest() async {
    setState(() => _loading = true);
    final result = await _service.checkServerConnection();
    setState(() {
      _loading = false;
      _result = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Runner Jeju')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_result),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _runTest,
              child: Text(_loading ? '확인 중...' : '서버 연결 테스트'),
            ),
          ],
        ),
      ),
    );
  }
}
