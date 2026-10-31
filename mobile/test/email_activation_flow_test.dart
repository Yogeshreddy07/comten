import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/theme/theme_view_model.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import 'package:frontend/features/auth/model/api_result.dart';
import 'package:frontend/features/auth/repository/auth_repository.dart';
import 'package:frontend/features/auth/viewmodel/auth_viewmodel.dart';
import 'package:frontend/features/auth/view/activate_account_screen.dart';
import 'package:frontend/features/auth/view/create_password_screen.dart';
import 'package:frontend/features/auth/view/login_screen.dart';
import 'package:frontend/features/auth/view/phonenumber_verification_screen.dart';
import 'package:frontend/features/auth/view/activation_phone_screen.dart';

class EmailRepository extends AuthRepository {
  int sends=0,verifications=0,passwordSets=0;
  @override
  Future<ApiResult> sendActivationOtp(String employeeCode) async {
    sends++;return ApiResult(success:true,message:'OTP sent to your registered email',data:{'maskedEmail':'t**t@example.com'});
  }
  @override
  Future<ApiResult> verifyActivationOtp(String employeeCode,String otp) async {
    verifications++;
    return otp=='123456' ? ApiResult(success:true,message:'Verified',data:{'employeeCode':employeeCode,'signupToken':'synthetic-proof'})
      : ApiResult(success:false,message:'Invalid or expired verification code');
  }
  @override
  Future<ApiResult> setPassword({required String employeeCode,required String signupToken,required String newPassword,required String confirmPassword}) async {
    passwordSets++;return ApiResult(success:true,message:'Password set. Verify phone.',data:{'phoneVerificationToken':'synthetic-phone-proof','maskedPhone':'+********3210'});
  }
  @override
  Future<ApiResult> sendActivationPhoneOtp(String employeeCode,String token) async => ApiResult(success:true,message:'Phone OTP sent');
  @override
  Future<ApiResult> verifyActivationPhoneOtp(String employeeCode,String token,String otp) async =>
      ApiResult(success:otp=='123456',message:otp=='123456'?'Account activated':'Invalid phone OTP');
}

class ResumeRepository extends EmailRepository {
  @override
  Future<ApiResult> sendActivationOtp(String employeeCode) async => ApiResult(success:true,message:'Verify your enrolled phone',
    data:{'stage':'PHONE','employeeCode':employeeCode,'phoneVerificationToken':'synthetic-phone-proof','maskedPhone':'+********3210'});
}

class EmailViewModel extends AuthViewModel {
  EmailViewModel(EmailRepository repository):super(repository:repository,secureStorage:SecureStorageService());
  @override
  Future<void> checkBiometricSupport() async {}
}

class CooldownRepository extends ResumeRepository {
  int phoneSends=0;
  @override
  Future<ApiResult> sendActivationPhoneOtp(String employeeCode,String token) async {
    phoneSends++;
    return phoneSends==1 ? ApiResult(success:true,message:'Sent',data:{'resendAfterSeconds':60})
        : ApiResult(success:false,message:'Please wait 90 seconds before requesting another code.',data:{'retryAfterSeconds':90});
  }
  @override
  Future<ApiResult> verifyActivationPhoneOtp(String employeeCode,String token,String otp) async =>
      ApiResult(success:false,message:'Too many incorrect attempts. Tap Resend OTP to get a new code.');
}

class AttemptsRepository extends ResumeRepository {
  int phoneAttempts = 0;
  @override
  Future<ApiResult> verifyActivationPhoneOtp(String employeeCode, String token, String otp) async {
    phoneAttempts++;
    if (otp == '123456') return ApiResult(success: true, message: 'Account activated');
    final left = 3 - phoneAttempts;
    return ApiResult(success: false,
      message: left > 0 ? 'Incorrect OTP. $left attempt${left == 1 ? '' : 's'} left.'
          : 'No attempts left. Please try again after 15 minutes.',
      data: left <= 0 ? {'retryAfterSeconds':900} : null);
  }
}

void main(){
  for (final complete in [true, false]) {
    testWidgets('phone shows two then one attempts left, then ${complete ? 'accepts correct code' : 'shows no attempts left'}', (tester) async {
      tester.view.physicalSize = const Size(480, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = AttemptsRepository();
      final model = EmailViewModel(repository);
      await model.sendActivationOtp('EMP009');
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<AuthViewModel>.value(value: model),
        ChangeNotifierProvider(create: (_) => ThemeViewModel()),
      ], child: const MaterialApp(home: ActivationPhoneScreen())));
      await tester.tap(find.text('Send Phone OTP'));
      await tester.pumpAndSettle();
      for (final left in [2, 1]) {
        await tester.enterText(find.widgetWithText(TextFormField, 'Phone OTP'), '000000');
        await tester.tap(find.text('Verify Phone OTP'));
        await tester.pumpAndSettle();
        expect(find.text('Incorrect OTP. $left attempt${left == 1 ? '' : 's'} left.'), findsOneWidget);
        expect(find.textContaining('OTP has expired'), findsNothing);
        expect(find.textContaining('Resend OTP in'), findsOneWidget);
      }
      await tester.enterText(find.widgetWithText(TextFormField, 'Phone OTP'), complete ? '123456' : '000000');
      await tester.tap(find.text('Verify Phone OTP'));
      await tester.pumpAndSettle();
      if (complete) {
        expect(find.text('Account activated'), findsOneWidget);
      } else {
        expect(find.text('No attempts left. Please try again after 15 minutes.'), findsOneWidget);
        expect(find.textContaining('OTP has expired'), findsNothing);
        final resend = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Resend OTP in 900 seconds'));
        expect(resend.onPressed, isNull);
      }
      expect(repository.phoneAttempts, 3);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });
  }
  testWidgets('retired OTP permits resend and server cooldown disables further sends',(tester) async {
    tester.view.physicalSize=const Size(480,1100);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final repository=CooldownRepository();
    final model=EmailViewModel(repository);
    await model.sendActivationOtp('EMP009');
    await tester.pumpWidget(MultiProvider(providers:[
      ChangeNotifierProvider<AuthViewModel>.value(value:model),
      ChangeNotifierProvider(create:(_)=>ThemeViewModel()),
    ],child:const MaterialApp(home:ActivationPhoneScreen())));
    await tester.tap(find.text('Send Phone OTP'));await tester.pumpAndSettle();
    expect(find.textContaining('Resend OTP in'),findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField,'Phone OTP'),'000000');
    await tester.tap(find.text('Verify Phone OTP'));await tester.pumpAndSettle();
    expect(find.text('Resend Phone OTP'),findsOneWidget);
    await tester.tap(find.text('Resend Phone OTP'));await tester.pumpAndSettle();
    expect(repository.phoneSends,2);
    expect(find.textContaining('Resend OTP in 90 seconds'),findsOneWidget);
    final resend=tester.widget<TextButton>(find.widgetWithText(TextButton,'Resend OTP in 90 seconds'));
    expect(resend.onPressed,isNull);
    await tester.pumpWidget(const SizedBox());model.dispose();
  });
  testWidgets('employee code -> masked email OTP -> password -> enrolled phone OTP -> login',(tester) async {
    tester.view.physicalSize=const Size(480,1100);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final repository=EmailRepository();
    await tester.pumpWidget(MultiProvider(providers:[
      ChangeNotifierProvider<AuthViewModel>(create:(_)=>EmailViewModel(repository)),
      ChangeNotifierProvider(create:(_)=>ThemeViewModel()),
    ], child:const MaterialApp(home:ActivateAccountScreen())));
    expect(find.text('Temporary Password'),findsNothing);
    expect(repository.sends,0);
    await tester.tap(find.text('Send OTP'));await tester.pumpAndSettle();
    expect(repository.sends,0);
    await tester.enterText(find.widgetWithText(TextFormField,'Employee Code'),'EMP010');
    await tester.pumpAndSettle();
    expect(repository.sends,0);
    await tester.tap(find.text('Send OTP'));await tester.pumpAndSettle();
    expect(repository.sends,1);
    expect(find.text('Email OTP'),findsOneWidget);
    expect(find.textContaining('t**t@example.com'),findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField,'Email OTP'),'000000');
    await tester.tap(find.text('Verify OTP'));await tester.pumpAndSettle();
    expect(find.byType(CreatePasswordScreen),findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField,'Email OTP'),'123456');
    await tester.tap(find.text('Verify OTP'));await tester.pumpAndSettle();
    expect(find.byType(CreatePasswordScreen),findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField,'New Password'),'ValidPassword123!');
    await tester.enterText(find.widgetWithText(TextFormField,'Confirm Password'),'ValidPassword123!');
    await tester.ensureVisible(find.text('Continue'));await tester.tap(find.text('Continue'));await tester.pumpAndSettle();
    expect(repository.passwordSets,1);
    expect(find.byType(LoginScreen),findsNothing);
    expect(find.byType(ActivationPhoneScreen),findsOneWidget);
    expect(find.textContaining('+********3210'),findsOneWidget);
    await tester.tap(find.text('Send Phone OTP'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField,'Phone OTP'),'000000');
    await tester.tap(find.text('Verify Phone OTP'));await tester.pumpAndSettle();
    expect(find.byType(LoginScreen),findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField,'Phone OTP'),'123456');
    await tester.tap(find.text('Verify Phone OTP'));await tester.pumpAndSettle();
    expect(find.text('Account activated'),findsOneWidget);
    await tester.tap(find.text('Go to Login'));await tester.pumpAndSettle();
    expect(find.byType(LoginScreen),findsOneWidget);
    expect(find.byType(PhoneNumberScreen),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('phone-pending employee code resumes at phone verification with no way back',(tester) async {
    tester.view.physicalSize=const Size(480,1100);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(providers:[
      ChangeNotifierProvider<AuthViewModel>(create:(_)=>EmailViewModel(ResumeRepository())),
      ChangeNotifierProvider(create:(_)=>ThemeViewModel()),
    ], child:const MaterialApp(home:ActivateAccountScreen())));
    await tester.enterText(find.widgetWithText(TextFormField,'Employee Code'),'EMP009');
    await tester.tap(find.text('Send OTP'));await tester.pumpAndSettle();
    expect(find.byType(ActivationPhoneScreen),findsOneWidget);
    expect(find.text('Email OTP'),findsNothing);
    expect(find.text('Send Phone OTP'),findsOneWidget);
    expect(find.text('Start activation again'),findsNothing);
    await tester.tap(find.text('Send Phone OTP'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField,'Phone OTP'),'123456');
    await tester.tap(find.text('Verify Phone OTP'));await tester.pumpAndSettle();
    expect(find.text('Account activated'),findsOneWidget);
  });
}
