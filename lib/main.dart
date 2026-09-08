import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/analisis_screen.dart';
import 'screens/project_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'AutoDocs AI',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              scaffoldBackgroundColor: AppColors.lightBackground,
              colorScheme: const ColorScheme.light(
                primary: AppColors.lightPrimary,
                secondary: AppColors.lightSecondary,
                surface: AppColors.lightSurface,
                onSurface: AppColors.lightOnSurface,
                onSurfaceVariant: AppColors.lightOnSurfaceVariant,
                error: Color(0xFFBA1A1A),
              ),
              fontFamily: 'Geist',
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              scaffoldBackgroundColor: AppColors.background,
              colorScheme: const ColorScheme.dark(
                primary: AppColors.primary,
                secondary: AppColors.secondary,
                surface: AppColors.surface,
                onSurface: AppColors.onSurface,
                onSurfaceVariant: AppColors.onSurfaceVariant,
                error: AppColors.error,
              ),
              fontFamily: 'Geist',
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
              ),
            ),
            themeMode: themeProvider.themeMode,
            initialRoute: '/',
            routes: {
              '/': (context) => const SplashScreen(),
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/home': (context) => const HomeScreen(),
              '/analisis': (context) => const AnalisisScreen(),
              '/dashboard': (context) => DashboardScreen(),
              '/project': (context) {
                final args = ModalRoute.of(context)?.settings.arguments;
                final projectId = args is String ? args : (args?.toString() ?? '');
                return ProjectDetailScreen(projectId: projectId);
              },
              '/profile': (context) => ProfileScreen(),
            },
          ); // closes MaterialApp
        }, // closes builder
      ), // closes Consumer
    ); // closes MultiProvider
  }
}