// ignore_for_file: avoid_relative_lib_imports, curly_braces_in_flow_control_structures
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/core/theme/theme_view_model.dart';
import 'package:frontend/features/auth/view/welcome_screen.dart';
import 'package:frontend/features/auth/view/login_screen.dart';
import 'package:frontend/features/auth/view/app_lock_screen.dart';
import 'package:frontend/features/auth/viewmodel/auth_viewmodel.dart';
import 'package:frontend/features/auth/repository/auth_repository.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import '../../tests/reference_mobile/lib/core/theme/app_theme.dart' as original;
import '../../tests/reference_mobile/lib/core/theme/theme_view_model.dart' as original;
import '../../tests/reference_mobile/lib/features/auth/view/welcome_screen.dart' as original;
import '../../tests/reference_mobile/lib/features/auth/view/login_screen.dart' as original;
import '../../tests/reference_mobile/lib/features/auth/view/app_lock_screen.dart' as original;
import '../../tests/reference_mobile/lib/features/auth/viewmodel/auth_viewmodel.dart' as original;
import '../../tests/reference_mobile/lib/features/auth/repository/auth_repository.dart' as original;
import '../../tests/reference_mobile/lib/core/utils/secure_storage_service.dart' as original;

class AuthFixture extends AuthViewModel {
 AuthFixture():super(repository:AuthRepository(),secureStorage:SecureStorageService());
 @override Future<void> checkBiometricSupport() async {}
}
class OriginalAuthFixture extends original.AuthViewModel {
 OriginalAuthFixture():super(repository:original.AuthRepository(),secureStorage:original.SecureStorageService());
 @override Future<void> checkBiometricSupport() async {}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final width in [390.0,800.0]) for(final dark in [false,true]) for(final screen in ['welcome','login','lock']) {
  testWidgets('$screen width=$width dark=$dark original and copied UI pixels match',(tester) async {
   tester.view.physicalSize=Size(width,900);tester.view.devicePixelRatio=1;
   addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
   final captures=<List<int>>[];
   for(final baseline in [true,false]){
    final key=GlobalKey();
    final child=baseline?MultiProvider(providers:[ChangeNotifierProvider<original.ThemeViewModel>(create:(_)=>original.ThemeViewModel()),ChangeNotifierProvider<original.AuthViewModel>(create:(_)=>OriginalAuthFixture())],child:MaterialApp(theme:dark?original.AppTheme.darkTheme:original.AppTheme.lightTheme,home:RepaintBoundary(key:key,child:screen=='welcome'?const original.WelcomeScreen():screen=='lock'?const original.AppLockScreen():const original.LoginScreen()))):MultiProvider(providers:[ChangeNotifierProvider<ThemeViewModel>(create:(_)=>ThemeViewModel()),ChangeNotifierProvider<AuthViewModel>(create:(_)=>AuthFixture())],child:MaterialApp(theme:dark?AppTheme.darkTheme:AppTheme.lightTheme,home:RepaintBoundary(key:key,child:screen=='welcome'?const WelcomeScreen():screen=='lock'?const AppLockScreen():const LoginScreen())));
    await tester.pumpWidget(child);await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(const AssetImage('assets/images/AppIcon.png'),key.currentContext!);
      await precacheImage(const AssetImage('assets/images/DarkThemeLogo.png'),key.currentContext!);
    });
    await tester.pumpAndSettle();
    final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final data=(await tester.runAsync(() async {
      final image=await boundary.toImage(pixelRatio:1);
      return (await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();
    }))!;
    captures.add(data);
    await tester.runAsync(() async {
      final file=File('../tests/visual/mobile/${baseline?'original':'new'}-${width.toInt()}-${dark?'dark':'light'}-$screen.png');
      await file.parent.create(recursive:true);await file.writeAsBytes(data);
    });
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
   }
   expect(captures[1],captures[0],reason:'Copied UI must preserve every rendered pixel');
  });
 }
}
