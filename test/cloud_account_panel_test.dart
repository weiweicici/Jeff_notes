import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jeff_notes/services/cloud_account_service.dart';
import 'package:jeff_notes/services/supabase_config.dart';
import 'package:jeff_notes/widgets/cloud_account_panel.dart';

class _FakeAuth implements CloudAccountAuthAdapter {
  int signInCalls = 0;
  @override
  String? userId = 'anonymous-user';
  @override
  String? email;
  @override
  bool isAnonymous = true;
  @override
  bool hasValidSession = true;
  @override
  bool emailConfirmed = true;
  @override
  Future<void> updateEmail(String value) async => email = value;
  @override
  Future<void> signInExistingEmail(String value) async => signInCalls++;
  @override
  Future<void> verifyEmailChange(String value, String token) async {
    email = value;
    isAnonymous = false;
  }

  @override
  Future<void> verifyEmailSignIn(String value, String token) async {
    email = value;
    userId = 'email-user';
    isAnonymous = false;
    hasValidSession = true;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'supabase_last_authenticated_user_id': 'anonymous-user',
    });
    SupabaseConfig.setAuthAdapterForTesting(null);
  });

  tearDown(() {
    SupabaseConfig.setAuthAdapterForTesting(null);
  });

  testWidgets('anonymous account requires explicit upload consent to bind', (
    tester,
  ) async {
    final service = CloudAccountService.forTesting(_FakeAuth());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CloudAccountPanel(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已有匿名云账号，可绑定邮箱保留数据'), findsOneWidget);
    expect(find.text('绑定当前云账号'), findsOneWidget);
    expect(find.text('同意把本机待同步笔记上传到此邮箱'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '绑定当前云账号'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('existing account flow offers email sign in and numeric code', (
    tester,
  ) async {
    final auth = _FakeAuth()
      ..userId = 'existing-user'
      ..isAnonymous = false
      ..hasValidSession = false;
    final service = CloudAccountService.forTesting(auth);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CloudAccountPanel(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录已有邮箱'), findsOneWidget);
    expect(find.text('绑定当前云账号'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'owner@example.com');
    await tester.tap(find.text('登录已有邮箱'));
    await tester.pumpAndSettle();
    expect(find.text('验证码（6–10位数字）'), findsOneWidget);
    final resend = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '重新发送验证邮件'),
    );
    expect(resend.onPressed, isNull);
  });

  testWidgets('sign in consent and OTP call authenticated callback once', (
    tester,
  ) async {
    final auth = _FakeAuth()
      ..userId = 'existing-user'
      ..isAnonymous = false
      ..hasValidSession = false;
    final service = CloudAccountService.forTesting(auth);
    var authenticated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudAccountPanel(
            service: service,
            onAuthenticated: () async => authenticated++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'owner@example.com');
    await tester.tap(find.text('登录已有邮箱'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('验证并继续'));
    await tester.pumpAndSettle();
    expect(authenticated, 1);
    expect(find.text('已连接：owner@example.com'), findsOneWidget);
  });

  testWidgets('connected account has no login entry', (tester) async {
    final auth = _FakeAuth()
      ..email = 'owner@example.com'
      ..isAnonymous = false
      ..hasValidSession = true;
    final service = CloudAccountService.forTesting(auth);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CloudAccountPanel(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已连接：owner@example.com'), findsOneWidget);
    expect(find.text('登录已有邮箱'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('panel preserves pending bind email at 340px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = _FakeAuth();
    final service = CloudAccountService.forTesting(auth);
    await service.requestBind('owner@example.com');
    final panel = MaterialApp(
      home: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: CloudAccountPanel(service: service),
        ),
      ),
    );
    await tester.pumpWidget(panel);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: CloudAccountPanel(service: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('重新发送验证邮件'), findsOneWidget);
    expect(find.text('取消邮箱请求'), findsOneWidget);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
