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

class EmailViewModel extends AuthViewModel {
  EmailViewModel(EmailRepository repository):super(repository:repository,secureStorage:SecureStorageService());
  @override
  Future<void> checkBiometricSupport() async {}
}

void main(){
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
}
