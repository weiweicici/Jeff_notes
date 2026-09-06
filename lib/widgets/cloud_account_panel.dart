import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cloud_account_service.dart';

class CloudAccountPanel extends StatefulWidget {
  final CloudAccountService? service;
  final Future<void> Function()? onAuthenticated;
  const CloudAccountPanel({super.key, this.service, this.onAuthenticated});
  @override
  State<CloudAccountPanel> createState() => _CloudAccountPanelState();
}

class _CloudAccountPanelState extends State<CloudAccountPanel> {
  late final CloudAccountService _service;
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  Timer? _resendTimer;
  DateTime? _scheduledCooldownAt;
  bool _allowLocalUpload = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CloudAccountService.instance;
    unawaited(_service.refreshStatus());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _request(bool bind) async {
    final email = _emailController.text.trim();
    final snapshot = _service.snapshot;
    if (email.isEmpty || snapshot.authInProgress) return;
    if (_resendBlocked(snapshot)) return;
    final pendingBind =
        snapshot.pendingAction == CloudAccountAction.verifyEmailChange;
    bind = bind || pendingBind;
    if (bind && !_allowLocalUpload) return;
    if (bind) {
      await _service.requestBind(email);
    } else {
      await _service.requestSignIn(email);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(code) || !_allowLocalUpload) return;
    final ok = await _service.verify(code: code, allowLocalUpload: true);
    // Authentication is already durably approved by the service. The sync
    // callback must run even when this panel was closed while verification
    // was in flight; only UI updates require mounted checks.
    if (ok) await widget.onAuthenticated?.call();
  }

  bool _resendBlocked(CloudAccountSnapshot snapshot) {
    final availableAt = snapshot.resendAvailableAt;
    return availableAt != null && DateTime.now().isBefore(availableAt);
  }

  void _scheduleCooldownRefresh(CloudAccountSnapshot snapshot) {
    final availableAt = snapshot.resendAvailableAt;
    if (availableAt == _scheduledCooldownAt) return;
    _scheduledCooldownAt = availableAt;
    _resendTimer?.cancel();
    if (availableAt == null) return;
    final delay = availableAt.difference(DateTime.now());
    if (delay.isNegative) return;
    _resendTimer = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final snapshot = _service.snapshot;
        _scheduleCooldownRefresh(snapshot);
        final anonymous =
            snapshot.valid &&
            snapshot.isAnonymous &&
            (snapshot.hasKnownIdentity || snapshot.userId != null);
        final pendingBind =
            snapshot.pendingAction == CloudAccountAction.verifyEmailChange;
        final connected = snapshot.valid && !snapshot.isAnonymous;
        final waiting = snapshot.authInProgress;
        if (snapshot.pendingEmail != null &&
            _emailController.text != snapshot.pendingEmail) {
          _emailController.text = snapshot.pendingEmail!;
        }
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '云账号',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(_statusText(snapshot)),
                if (connected)
                  Text(
                    '账号 ID：${snapshot.userId ?? '未知'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (!connected) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailController,
                    enabled: !waiting && snapshot.pendingAction == null,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowLocalUpload,
                    onChanged: waiting
                        ? null
                        : (v) => setState(() => _allowLocalUpload = v ?? false),
                    title: const Text('同意把本机待同步笔记上传到此邮箱'),
                    subtitle: const Text('已有云端数据不会自动迁移'),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (anonymous ||
                          pendingBind ||
                          snapshot.pendingAction ==
                              CloudAccountAction.verifyEmailSignIn)
                        FilledButton.tonal(
                          onPressed:
                              waiting ||
                                  ((pendingBind || anonymous) &&
                                      !_allowLocalUpload) ||
                                  _resendBlocked(snapshot)
                              ? null
                              : () => _request(anonymous || pendingBind),
                          child: Text(
                            pendingBind ||
                                    snapshot.pendingAction ==
                                        CloudAccountAction.verifyEmailSignIn
                                ? '重新发送验证邮件'
                                : '绑定当前云账号',
                          ),
                        ),
                      if (!anonymous &&
                          !pendingBind &&
                          snapshot.pendingAction == null)
                        FilledButton.tonal(
                          onPressed: waiting || _resendBlocked(snapshot)
                              ? null
                              : () => _request(false),
                          child: Text(
                            _resendBlocked(snapshot) ? '请稍候再发送' : '登录已有邮箱',
                          ),
                        ),
                    ],
                  ),
                  if (snapshot.canCancelRequest)
                    TextButton(
                      onPressed: waiting
                          ? null
                          : () => _service.cancelPendingRequest(),
                      child: const Text('取消邮箱请求'),
                    ),
                ],
                if (snapshot.pendingAction != null) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _codeController,
                    enabled: !waiting,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: '验证码（6–10位数字）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  FilledButton(
                    onPressed: waiting || !_allowLocalUpload ? null : _verify,
                    child: Text(waiting ? '验证中…' : '验证并继续'),
                  ),
                ],
                if (snapshot.errorMessage != null)
                  Text(
                    snapshot.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 4),
                const Text(
                  '请先在 iPad 绑定，再在手机用同一邮箱登录。仅支持已有邮箱，不会创建新的空账号。若邮件没有数字验证码，需要管理员在邮件模板加入验证码。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusText(CloudAccountSnapshot snapshot) {
    if (snapshot.authInProgress) return '正在请求云会话…';
    if (snapshot.email != null && snapshot.valid) {
      return '已连接：${snapshot.email}';
    }
    if (snapshot.valid &&
        snapshot.isAnonymous &&
        (snapshot.hasKnownIdentity || snapshot.userId != null))
      return '已有匿名云账号，可绑定邮箱保留数据（原账号 ID：${snapshot.knownUserId ?? snapshot.userId}）';
    if (snapshot.pendingAction != null && snapshot.knownUserId != null)
      return '待验证邮箱请求（原账号 ID：${snapshot.knownUserId}）';
    return '云会话未恢复';
  }
}
