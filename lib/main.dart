import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

// Global backend base URL and image resolver for use across screens
const String kBackendBaseUrl = 'https://superdailys.com/superdailyapp/';
const String kStorageProductsBase = 'https://superdailys.com/storage/products/';
const String kGoogleMapsApiKey = 'AIzaSyDx_sQ51Uv1zBO2CfQSaM5tWMmnUFMIJaA';

// Razorpay Configuration
const String kRazorpayKeyId = 'rzp_test_R8Ilarj7qdqAOS';
const String kRazorpayKeySecret = 'PDiOJq6d7MTHgFCRfFzzVAxs';
const String kRazorpayWebhookSecret = 'whsec_test.';

String _resolveImageUrl(String raw) {
  if (raw.isEmpty) return raw;
  String p = raw.trim();
  p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
  
  // Already absolute URL starting with https://superdailys.com/storage/products/
  if (p.startsWith('https://superdailys.com/storage/products/')) {
    return p;
  }
  
  // Already absolute URL (any other URL)
  if (p.startsWith('http://') || p.startsWith('https://')) {
    // If it's a full URL but not from the storage/products path, try to extract filename
    if (!p.contains('/storage/products/')) {
      final filename = p.split('/').last.split('?').first.split('#').first;
      if (filename.isNotEmpty && filename.contains('.')) {
        return kStorageProductsBase + filename;
      }
    }
    return p;
  }
  
  // Extract just the filename from the path
  String filename = p.split('/').last.split('\\').last;
  // Remove query parameters and hash
  filename = filename.split('?').first.split('#').first;
  
  // If filename is empty or doesn't have extension, try to find it
  if (filename.isEmpty || !filename.contains('.')) {
    // Try to find filename in the path
    final parts = p.split('/');
    for (var part in parts.reversed) {
      if (part.contains('.') && part.length > 3) {
        filename = part.split('?').first.split('#').first;
        break;
      }
    }
  }
  
  // Build full URL with storage/products base
  if (filename.isNotEmpty && filename.contains('.')) {
    final url = kStorageProductsBase + filename;
    debugPrint('Resolved image URL (storage): ' + url);
    return url;
  }
  
  // Fallback to old method
  while (p.startsWith('./') || p.startsWith('../')) {
    p = p.startsWith('./') ? p.substring(2) : p.substring(3);
  }
  final spdIdx = p.indexOf('/spdbackend/');
  if (spdIdx != -1) {
    p = p.substring(spdIdx + '/spdbackend/'.length);
  }
  for (final marker in ['/htdocs/', '/www/']) {
    final idx = p.indexOf(marker);
    if (idx != -1) {
      p = p.substring(idx + marker.length);
    }
  }
  if (p.startsWith('/')) p = p.substring(1);
  final fileName = _basename(p);
  if (fileName.isNotEmpty) {
    final url = kStorageProductsBase + fileName;
    debugPrint('Resolved image URL (storage fallback): ' + url);
    return url;
  }
  final url = kBackendBaseUrl + p;
  debugPrint('Resolved image URL (fallback backend): ' + url);
  return url;
}

String _getBackendBaseUrl() {
  // Always use production URL for hosted backend
    return kBackendBaseUrl;
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPD App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          primary: Colors.green.shade700,
          secondary: Colors.green.shade600,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const AuthWrapper(),
    );
  }
}

// A widget that tries multiple URLs in order until one loads successfully
class FallbackImage extends StatefulWidget {
  final List<String> urls;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? error;

  const FallbackImage({
    super.key,
    required this.urls,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  @override
  State<FallbackImage> createState() => _FallbackImageState();
}

class _FallbackImageState extends State<FallbackImage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.urls.length) {
      return widget.error ?? const SizedBox.shrink();
    }
    final resolved = _resolveImageUrl(widget.urls[_index]);
    final url = Uri.encodeFull(resolved + (resolved.contains('?') ? '&' : '?') + 'v=' + DateTime.now().millisecondsSinceEpoch.toString());
    debugPrint('Image try [' + _index.toString() + "/" + widget.urls.length.toString() + ']: ' + resolved);
    return CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      placeholder: (context, _) => widget.placeholder ?? const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (context, _, __) {
        debugPrint('Image failed: ' + resolved);
        if (_index < widget.urls.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() { _index += 1; });
            }
          });
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return widget.error ?? const SizedBox.shrink();
      },
    );
  }
}

String _basename(String p) {
  if (p.isEmpty) return p;
  p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
  final i = p.lastIndexOf('/');
  return i == -1 ? p : p.substring(i + 1);
}

// Auth Wrapper to check login status on app start
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _hasSeenOnboarding = false;
  bool _showSplash = true;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      final userDataJson = prefs.getString('userData');
      final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

      if (isLoggedIn && userDataJson != null) {
    setState(() {
          _isLoggedIn = true;
          _userData = jsonDecode(userDataJson);
          _hasSeenOnboarding = true;
          _isLoading = false;
          _showSplash = false;
        });
      } else {
        setState(() {
          _isLoggedIn = false;
          _hasSeenOnboarding = hasSeenOnboarding;
          _isLoading = false;
        });
        
        // Show splash screen for 2 seconds if user hasn't seen onboarding
        if (!hasSeenOnboarding) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            setState(() {
              _showSplash = false;
            });
          }
        } else {
          setState(() {
            _showSplash = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoggedIn = false;
        _hasSeenOnboarding = false;
        _isLoading = false;
        _showSplash = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _showSplash) {
      return const SplashScreen();
    }

    if (_isLoggedIn && _userData != null) {
      return HomeScreen(userData: _userData!);
    }

    if (!_hasSeenOnboarding) {
      return const GetStartedPage();
    }

    return const LoginPage();
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));
    
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF00BFA5),
        body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
                child: Image.asset(
                  'images/logo.png',
                  height: 80,
                  width: 80,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.image,
                        color: Colors.white,
                        size: 40,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              // Super Daily Text
              Text(
                'Super Daily',
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          ),
        ),
      );
  }
}

class GetStartedPage extends StatefulWidget {
  const GetStartedPage({super.key});

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

class _GetStartedPageState extends State<GetStartedPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final List<String> _images = ['images/1.png', 'images/2.png', 'images/3.png'];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onGetStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    
    if (mounted) {
      // Navigate back to AuthWrapper which will show LoginPage
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _images.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                    ),
                    child: Image.asset(
                      _images[index],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            'Image ${index + 1}',
                            style: const TextStyle(fontSize: 24),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            // Page indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _images.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.green.shade700
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Get Started button (only on last page)
            if (_currentPage == _images.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _onGetStarted,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Get Started',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  // Sign-up controllers
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _signupPhoneController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _addressController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureSignupPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isSignupLoading = false;
  late TabController _tabController;
  late AnimationController _animationController;
  late ScrollController _scrollController;
  
  final List<String> _imagePaths = [
    'images/gs1.png',
    'images/gs2.png',
    'images/gs3.png',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15), // Medium speed
    )..repeat();
    
    _scrollController = ScrollController();
    
    // Start auto-scrolling with seamless loop
    _animationController.addListener(_animateImages);
    
    // Initialize scroll position after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _animationController.isAnimating) {
        _animateImages();
      }
    });
  }
  
  void _animateImages() {
    if (!_scrollController.hasClients) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll == 0) return;
    
    final oneSetWidth = maxScroll / 3; // Since we have 3 sets
    final scrollPosition = _animationController.value * oneSetWidth * 2;
    
    // Reset to beginning when reaching end for seamless loop
    if (scrollPosition >= oneSetWidth * 2) {
      _scrollController.jumpTo(scrollPosition - oneSetWidth * 2);
    } else {
      _scrollController.jumpTo(scrollPosition);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _signupPhoneController.dispose();
    _signupPasswordController.dispose();
    _confirmPasswordController.dispose();
    _addressController.dispose();
    _tabController.dispose();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    // Remove spaces and special characters for validation
    final cleanPhone = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Check if it contains only digits
    if (!RegExp(r'^\d+$').hasMatch(cleanPhone)) {
      return 'Phone number must contain only digits';
    }
    // Must be exactly 10 digits
    if (cleanPhone.length != 10) {
      return 'Phone number must be exactly 10 digits';
    }
    // Check if it doesn't start with 0
    if (cleanPhone.startsWith('0')) {
      return 'Phone number cannot start with 0';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your full name';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email address';
    }
    // Trim whitespace
    final email = value.trim().toLowerCase();
    
    // More comprehensive email regex
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
      caseSensitive: false,
    );
    
    if (!emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address\n(Example: name@example.com)';
    }
    
    // Additional validations
    if (email.startsWith('.') || email.startsWith('@')) {
      return 'Email cannot start with . or @';
    }
    
    if (email.contains('..')) {
      return 'Email cannot contain consecutive dots';
    }
    
    if (email.length > 254) {
      return 'Email address is too long';
    }
    
    // Check for common TLD
    final parts = email.split('@');
    if (parts.length != 2) {
      return 'Invalid email format';
    }
    
    final domain = parts[1];
    if (domain.length < 4) {
      return 'Invalid email domain';
    }
    
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _signupPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  String? _validateAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your address';
    }
    if (value.trim().length < 5) {
      return 'Address must be at least 5 characters';
    }
    return null;
  }

  Future<void> _handleSignup() async {
    if (_signupFormKey.currentState!.validate()) {
      setState(() {
        _isSignupLoading = true;
      });

      try {
        // API endpoint - Production
        const String apiUrl = 'https://superdailys.com/superdailyapp/register.php';
        
        // Prepare request body
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'name': _fullNameController.text.trim(),
            'email': _emailController.text.trim(),
            'phone': _signupPhoneController.text.trim(),
            'password': _signupPasswordController.text,
            'address': _addressController.text.trim(),
          }),
        );

        if (mounted) {
          setState(() {
            _isSignupLoading = false;
          });

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true) {
              // Registration successful - Show success message and switch to login
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(data['message'] ?? 'Registration successful! Please login.'),
                  backgroundColor: Colors.green,
                ),
              );
              
              // Clear sign-up form
              _fullNameController.clear();
              _emailController.clear();
              _signupPhoneController.clear();
              _signupPasswordController.clear();
              _confirmPasswordController.clear();
              _addressController.clear();
              
              // Switch to login tab
              _tabController.animateTo(0);
            } else {
              // Registration failed
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(data['message'] ?? 'Registration failed'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } else {
            // HTTP error
            final data = jsonDecode(response.body);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Server error occurred'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSignupLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleLogin() async {
    if (_loginFormKey.currentState!.validate()) {
    setState(() {
        _isLoading = true;
      });

      try {
        // API endpoint - Production
        const String apiUrl = 'https://superdailys.com/superdailyapp/login.php';
        
        // Prepare request body
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'phone': _phoneController.text.trim(),
            'password': _passwordController.text,
          }),
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true) {
              // Save login state and user data
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isLoggedIn', true);
              await prefs.setString('userData', jsonEncode(data['user']));
              
              // Login successful - Navigate to Home Screen
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HomeScreen(userData: data['user']),
                  ),
                );
              }
            } else {
              // Login failed
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(data['message'] ?? 'Login failed'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } else {
            // HTTP error
            final data = jsonDecode(response.body);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Server error occurred'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
    setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showForgotPasswordDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ForgotPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Animated Image Carousel in the middle with title
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Image Carousel
                  Flexible(
                    flex: 3,
                    child: SizedBox(
                      height: size.height * 0.35,
                      child: Center(
                        child: ListView.builder(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(), // Disable manual scrolling
                          shrinkWrap: true,
                          itemCount: _imagePaths.length * 3, // Repeat 3 times for seamless loop
                          itemBuilder: (context, index) {
                            final imageIndex = index % _imagePaths.length;
                            return Container(
                              width: size.width * 0.75,
                              margin: const EdgeInsets.symmetric(horizontal: 15),
                              child: Image.asset(
                                _imagePaths[imageIndex],
                                fit: BoxFit.contain,
                                width: size.width * 0.75,
                                height: size.height * 0.35,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // Title and Subtitle Section
                  Flexible(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Title Text
                          Flexible(
                            child: Text(
                            'Super Daily...!',
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Subtitle Text
                          const SizedBox(height: 6),
                          Flexible(
                            child: Text(
                            'Get everything delivered.',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Login/Signup Card at bottom
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  children: [
                    Card(
                      elevation: 8,
                      color: const Color(0xFF00D1B2), // teal from provided image
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          // Tab Bar
                          TabBar(
                            controller: _tabController,
                            indicatorColor: Colors.white,
                            indicatorWeight: 3,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white70,
                            labelStyle: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            unselectedLabelStyle: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                            ),
                            tabs: const [
                              Tab(text: 'Login'),
                              Tab(text: 'Sign Up'),
                            ],
                          ),
                          // Tab Bar View
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                // Login Form
                                Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Form(
                                    key: _loginFormKey,
                                    child: SingleChildScrollView(
        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Phone Field
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Phone Number',
                                  hintText: 'Enter 10 digits (e.g., 9876543210)',
                                  helperText: 'Must be exactly 10 digits',
                                  prefixIcon: const Icon(Icons.phone_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                validator: _validatePhone,
                              ),
                              const SizedBox(height: 20),
                              
                              // Password Field
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outlined),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                validator: _validatePassword,
                              ),
                              const SizedBox(height: 12),
                              
                              // Forgot Password
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    _showForgotPasswordDialog(context);
                                  },
                                  child: Text(
                                    'Forgot Password?',
                                    style: GoogleFonts.poppins(
                                      color: const Color(0xFF00BFA5),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              // Login Button
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF8F9FA),
                                  foregroundColor: Colors.black87,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.black87,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        'Login',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Sign Up Form
                                  Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Form(
                                    key: _signupFormKey,
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          // Full Name Field
                                          TextFormField(
                                            controller: _fullNameController,
                                            keyboardType: TextInputType.name,
                                            decoration: InputDecoration(
                                              labelText: 'Full Name',
                                              hintText: 'Enter your full name',
                                              prefixIcon: const Icon(Icons.person_outlined),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                            ),
                                            validator: _validateFullName,
                                          ),
                                          const SizedBox(height: 16),
                                          
                                          // Email Field
                                          TextFormField(
                                            controller: _emailController,
                                            keyboardType: TextInputType.emailAddress,
                                            textInputAction: TextInputAction.next,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.deny(RegExp(r'\s')),
                                              LengthLimitingTextInputFormatter(254),
                                            ],
                                            decoration: InputDecoration(
                                              labelText: 'Email Address',
                                              hintText: 'Enter your email (e.g., name@example.com)',
                                              helperText: 'Example: user@example.com',
                                              prefixIcon: const Icon(Icons.email_outlined),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                            ),
                                            validator: _validateEmail,
                                          ),
                                          const SizedBox(height: 16),
                                          
                                          // Phone Number Field
                                          TextFormField(
                                            controller: _signupPhoneController,
                                            keyboardType: TextInputType.number,
                                            textInputAction: TextInputAction.next,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.digitsOnly,
                                              LengthLimitingTextInputFormatter(10),
                                            ],
                                            decoration: InputDecoration(
                                              labelText: 'Phone Number',
                                              hintText: 'Enter 10 digits (e.g., 9876543210)',
                                              helperText: 'Must be exactly 10 digits',
                                              prefixIcon: const Icon(Icons.phone_outlined),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                            ),
                                            validator: _validatePhone,
                                          ),
                                          const SizedBox(height: 16),
                                          
                                          // Password Field
                                          TextFormField(
                                            controller: _signupPasswordController,
                                            obscureText: _obscureSignupPassword,
                                            decoration: InputDecoration(
                                              labelText: 'Password',
                                              hintText: 'Enter your password',
                                              prefixIcon: const Icon(Icons.lock_outlined),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscureSignupPassword
                                                      ? Icons.visibility_outlined
                                                      : Icons.visibility_off_outlined,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    _obscureSignupPassword = !_obscureSignupPassword;
                                                  });
                                                },
                                              ),
                                              border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                            ),
                                            validator: _validatePassword,
                                          ),
                                          const SizedBox(height: 16),
                                          
                                          // Confirm Password Field
                                          TextFormField(
                                            controller: _confirmPasswordController,
                                            obscureText: _obscureConfirmPassword,
                                            decoration: InputDecoration(
                                              labelText: 'Confirm Password',
                                              hintText: 'Confirm your password',
                                              prefixIcon: const Icon(Icons.lock_outlined),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscureConfirmPassword
                                                      ? Icons.visibility_outlined
                                                      : Icons.visibility_off_outlined,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                                  });
                                                },
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                            ),
                                            validator: _validateConfirmPassword,
                                          ),
                                          const SizedBox(height: 16),
                                          
                                          // Address Field
                                          TextFormField(
                                            controller: _addressController,
                                            keyboardType: TextInputType.streetAddress,
                                            maxLines: 2,
                                            decoration: InputDecoration(
                                              labelText: 'Address',
                                              hintText: 'Enter your address',
                                              prefixIcon: const Icon(Icons.location_on_outlined),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                            ),
                                            validator: _validateAddress,
                    ),
                    const SizedBox(height: 24),
                    
                                          // Sign Up Button
                                          ElevatedButton(
                                            onPressed: _isSignupLoading ? null : _handleSignup,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFF8F9FA),
                                              foregroundColor: Colors.black87,
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              elevation: 2,
                                            ),
                                            child: _isSignupLoading
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        Colors.black87,
                                                      ),
                                                    ),
                                                  )
                                                : Text(
                            'Sign Up',
                            style: GoogleFonts.poppins(
                                                      fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
            ),
          ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Widget for product details image with proxy fallback
class _ProductDetailsImageWidget extends StatefulWidget {
  final String imageUrl;
  final String productName;

  const _ProductDetailsImageWidget({
    required this.imageUrl,
    required this.productName,
  });

  @override
  State<_ProductDetailsImageWidget> createState() => _ProductDetailsImageWidgetState();
}

class _ProductDetailsImageWidgetState extends State<_ProductDetailsImageWidget> {
  int _currentFallbackIndex = 0; // 0 = direct, 1 = proxy
  bool _hasError = false;

  String _getProxiedUrl(String url) {
    final encodedUrl = Uri.encodeComponent(url);
    return 'https://superdailys.com/superdailyapp/proxy_image.php?url=$encodedUrl';
  }

  String _getCurrentImageUrl() {
    // If direct URL failed and we haven't tried proxy yet, use proxy
    if (_currentFallbackIndex == 1) {
      return _getProxiedUrl(widget.imageUrl);
    }
    return widget.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Icon(
          Icons.image_not_supported,
          size: 80,
          color: Colors.grey.shade400,
        ),
      );
    }

    final imageUrl = _getCurrentImageUrl();
    debugPrint('🖼️ Product Details - Trying to load image (${_currentFallbackIndex == 0 ? 'direct' : 'proxy'}) for "${widget.productName}": $imageUrl');

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      httpHeaders: {
        'Accept': 'image/*',
      },
      placeholder: (context, url) => Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
        ),
      ),
      errorWidget: (context, url, error) {
        debugPrint('❌ Product Details - Image failed to load (${_currentFallbackIndex == 0 ? 'direct' : 'proxy'}) for "${widget.productName}": $url');
        debugPrint('   Error type: ${error.runtimeType}');
        debugPrint('   Error: $error');
        
        // If direct URL failed, try proxy
        if (_currentFallbackIndex == 0) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _currentFallbackIndex = 1; // Try proxy
              });
            }
          });
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
            ),
          );
        } else {
          // Proxy also failed
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _hasError = true;
              });
            }
          });
          return Center(
            child: Icon(
              Icons.image_not_supported,
              size: 80,
              color: Colors.grey.shade400,
            ),
          );
        }
      },
    );
  }
}

// Home Screen Widget
// Product Details Screen
class ProductDetailsScreen extends StatefulWidget {
  final int productId;

  const ProductDetailsScreen({super.key, required this.productId});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  Map<String, dynamic>? _product;
  bool _isLoading = true;
  String? _errorMessage;
  PageController _imageController = PageController();
  int _currentImageIndex = 0;
  Razorpay? _razorpay;
  bool _isProcessingPayment = false;
  static const Color _tealColor = Color(0xFF00BFA5);
  static const Color _tealLight = Color(0xFFE0F2F1);

  @override
  void initState() {
    super.initState();
    _imageController = PageController();
    // Initialize Razorpay only for mobile platforms (Android/iOS)
    if (!kIsWeb) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    }
    _fetchProductDetails();
  }

  @override
  void dispose() {
    _imageController.dispose();
    if (!kIsWeb && _razorpay != null) {
      _razorpay!.clear();
    }
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (mounted) {
      setState(() {
        _isProcessingPayment = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment successful! Order placed successfully. Payment ID: ${response.paymentId ?? "N/A"}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
      // Optionally navigate back or show order confirmation
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop(); // Go back to product list
        }
      });
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() {
        _isProcessingPayment = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: ${response.message ?? "Unknown error"}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External wallet selected: ${response.walletName}'),
        ),
      );
    }
  }

  Future<void> _initiateProductPayment() async {
    if (_product == null) return;

    try {
      // Get product price
      final sellingPrice = _product!['selling_price'] ?? _product!['price'] ?? 0.0;
      final price = (sellingPrice is String) ? double.tryParse(sellingPrice) ?? 0.0 : (sellingPrice as num).toDouble();
      
      if (price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid product price'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final productName = _product!['name'] ?? 'Product';
      
      setState(() {
        _isProcessingPayment = true;
      });

      // Get user data from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = prefs.getString('userData');
      Map<String, dynamic>? userData;
      if (userDataJson != null) {
        userData = jsonDecode(userDataJson);
      }

      final options = {
        'key': kRazorpayKeyId,
        'amount': (price * 100).toInt(), // Amount in paise
        'name': 'Super Daily',
        'description': 'Product Purchase: $productName',
        'prefill': {
          'contact': userData?['phone'] ?? '',
          'email': userData?['email'] ?? '',
        },
        'external': {
          'wallets': ['paytm']
        },
      };

      if (kIsWeb) {
        // For web, show payment dialog
        await _initiateRazorpayWeb(options, price);
      } else {
        // Use Razorpay Flutter SDK for mobile
        if (_razorpay != null) {
          _razorpay!.open(options);
        } else {
          setState(() {
            _isProcessingPayment = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initiating payment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initiateRazorpayWeb(Map<String, dynamic> options, double amount) async {
    if (mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Payment Required'),
          content: Text(
            'Product purchase requires payment of ₹${amount.toStringAsFixed(2)}.\n\n'
            'For web payments, Razorpay integration requires server-side order creation.\n\n'
            'Would you like to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      
      if (confirm == true) {
        setState(() {
          _isProcessingPayment = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete payment via mobile app or contact support.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        setState(() {
          _isProcessingPayment = false;
        });
      }
    }
  }

  Future<void> _fetchProductDetails() async {
    try {
      final response = await http.get(
        Uri.parse('https://superdailys.com/superdailyapp/get_product_details.php?id=${widget.productId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            setState(() {
              _product = data['product'];
              _isLoading = false;
            });
            // Set image count for page indicator
            if (_product != null) {
              List<String> images = _getProductImages();
              if (images.isNotEmpty && _imageController.hasClients) {
                _imageController.jumpToPage(0);
              }
            }
          } else {
            setState(() {
              _errorMessage = data['message'] ?? 'Failed to load product';
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _errorMessage = 'Failed to load product. Status: ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<String> _getProductImages() {
    if (_product == null) return [];
    List<String> images = [];
    
    // Collect all available images and resolve URLs
    for (var imgKey in ['image', 'image_2', 'image_3', 'image_4']) {
      final imgValue = _product![imgKey];
      if (imgValue != null && imgValue.toString().trim().isNotEmpty) {
        final resolvedUrl = _resolveImageUrl(imgValue.toString());
        if (resolvedUrl.isNotEmpty && resolvedUrl.startsWith('http')) {
          images.add(resolvedUrl);
          debugPrint('🖼️ Product Details - Found image from $imgKey: $resolvedUrl');
        }
      }
    }
    
    return images; // Return empty list if no images
  }
  
  String _resolveImageUrl(String raw) {
    if (raw.isEmpty) return raw;
    String p = raw.trim();
    // Normalize slashes
    p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
    
    // Already absolute URL starting with https://superdailys.com/storage/products/
    if (p.startsWith('https://superdailys.com/storage/products/')) {
      return p;
    }
    
    // Handle URLs with superdailyapp/storage/products/ and convert to storage/products/
    if (p.contains('/superdailyapp/storage/products/')) {
      final filename = p.split('/').last.split('?').first.split('#').first;
      if (filename.isNotEmpty && filename.contains('.')) {
        final correctedUrl = 'https://superdailys.com/storage/products/' + filename;
        debugPrint('🔄 Product Details - Corrected URL from superdailyapp path: $correctedUrl');
        return correctedUrl;
      }
    }
    
    // Already absolute URL (any other URL)
    if (p.startsWith('http://') || p.startsWith('https://')) {
      // If it's a full URL but not from the storage/products path, try to extract filename
      if (!p.contains('/storage/products/')) {
        final filename = p.split('/').last.split('?').first.split('#').first;
        if (filename.isNotEmpty && filename.contains('.')) {
          return 'https://superdailys.com/storage/products/' + filename;
        }
      }
      return p;
    }
    
    // Extract just the filename from the path
    String filename = p.split('/').last.split('\\').last;
    // Remove query parameters and hash
    filename = filename.split('?').first.split('#').first;
    
    // If filename is empty or doesn't have extension, try to find it
    if (filename.isEmpty || !filename.contains('.')) {
      // Try to find filename in the path
      final parts = p.split('/');
      for (var part in parts.reversed) {
        if (part.contains('.') && part.length > 3) {
          filename = part.split('?').first.split('#').first;
          break;
        }
      }
    }
    
    // Build full URL with storage/products base
    if (filename.isNotEmpty && filename.contains('.')) {
      final url = 'https://superdailys.com/storage/products/' + filename;
      debugPrint('Resolved image URL: $url');
      return url;
    }
    
    // Fallback to old method
    while (p.startsWith('./') || p.startsWith('../')) {
      p = p.startsWith('./') ? p.substring(2) : p.substring(3);
    }
    final spdIdx = p.indexOf('/spdbackend/');
    if (spdIdx != -1) {
      p = p.substring(spdIdx + '/spdbackend/'.length);
    }
    for (final marker in ['/htdocs/', '/www/']) {
      final idx = p.indexOf(marker);
      if (idx != -1) {
        p = p.substring(idx + marker.length);
      }
    }
    if (p.startsWith('/')) p = p.substring(1);
    final url = 'https://superdailys.com/storage/products/' + _basename(p);
    debugPrint('Resolved image URL (fallback): ' + url);
    return url;
  }
  
  String _basename(String p) {
    if (p.isEmpty) return p;
    p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i == -1 ? p : p.substring(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _tealColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Product Details',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
            )
          : _errorMessage != null
              ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
            Text(
                        _errorMessage!,
                        style: GoogleFonts.poppins(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                          _fetchProductDetails();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _tealColor,
                        ),
                        child: Text(
                          'Retry',
                          style: GoogleFonts.poppins(color: Colors.white),
                        ),
            ),
          ],
        ),
                )
              : _product == null
                  ? const Center(child: Text('Product not found'))
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Image Carousel
                          _buildImageCarousel(),
                          // Product Details
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Product Name
                                Text(
                                  _product!['name'] ?? 'Product Name',
                                  style: GoogleFonts.poppins(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Brand Name
                                if (_product!['brand_name'] != null && _product!['brand_name'].toString().isNotEmpty)
                                  Text(
                                    _product!['brand_name'].toString(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                // Price Section
                                _buildPriceSection(),
                                const SizedBox(height: 16),
                                // Stock Status
                                _buildStockStatus(),
                                const SizedBox(height: 24),
                                // Divider
                                Divider(color: Colors.grey.shade300),
                                const SizedBox(height: 24),
                                // Description Section
                                _buildDescriptionSection(),
                                const SizedBox(height: 24),
                                // Specifications Section
                                if (_product!['specifications'] != null && _product!['specifications'].toString().isNotEmpty)
                                  _buildSpecificationsSection(),
                                // Additional Details
                                const SizedBox(height: 24),
                                _buildAdditionalDetails(),
                                const SizedBox(height: 80), // Space for bottom button
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
      bottomNavigationBar: _product != null
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessingPayment ? null : _initiateProductPayment,
                        icon: _isProcessingPayment
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.shopping_cart),
                        label: Text(
                          _isProcessingPayment ? 'Processing...' : 'Add to Cart',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _tealColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildImageCarousel() {
    List<String> images = _getProductImages();

    return SizedBox(
      height: 350,
      child: Stack(
        children: [
          images.isEmpty
              ? Container(
                  width: double.infinity,
                  color: _tealLight,
                  child: Center(
                    child: Icon(
                      Icons.image,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                  ),
                )
              : PageView.builder(
            controller: _imageController,
            itemCount: images.length,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final imageUrl = images[index];
              return Container(
                width: double.infinity,
                color: _tealLight,
                      child: _ProductDetailsImageWidget(
                        imageUrl: imageUrl,
                        productName: _product?['name'] ?? 'Product',
                      ),
              );
            },
          ),
          // Page Indicator
          if (images.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentImageIndex == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    final sellingPrice = _product!['selling_price'] ?? _product!['price'] ?? 0;
    final mrpPrice = _product!['mrp_price'] ?? sellingPrice;
    final discountPercentage = _product!['discount_percentage'] ?? 0;

    // Convert to numbers safely - handle null, string, and number types
    double sellingPriceNum = 0.0;
    if (sellingPrice != null) {
      if (sellingPrice is String) {
        sellingPriceNum = double.tryParse(sellingPrice) ?? 0.0;
      } else if (sellingPrice is num) {
        sellingPriceNum = sellingPrice.toDouble();
      }
    }
    
    double mrpPriceNum = sellingPriceNum;
    if (mrpPrice != null) {
      if (mrpPrice is String) {
        mrpPriceNum = double.tryParse(mrpPrice) ?? sellingPriceNum;
      } else if (mrpPrice is num) {
        mrpPriceNum = mrpPrice.toDouble();
      } else {
        mrpPriceNum = sellingPriceNum;
      }
    }
    
    double discountPercentageNum = 0.0;
    if (discountPercentage != null) {
      if (discountPercentage is String) {
        discountPercentageNum = double.tryParse(discountPercentage) ?? 0.0;
      } else if (discountPercentage is num) {
        discountPercentageNum = discountPercentage.toDouble();
      }
    }

    final hasDiscount = discountPercentageNum > 0 && mrpPriceNum > sellingPriceNum;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '₹${sellingPriceNum.toStringAsFixed(2)}',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: _tealColor,
          ),
        ),
        if (hasDiscount) ...[
          const SizedBox(width: 12),
          Text(
            '₹${mrpPriceNum.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 18,
              decoration: TextDecoration.lineThrough,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${discountPercentageNum.toStringAsFixed(0)}% OFF',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStockStatus() {
    final stockQuantity = _product!['stock_quantity'] ?? 0;
    final isInStock = stockQuantity > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isInStock ? _tealLight : Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isInStock ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: isInStock ? _tealColor : Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            isInStock ? 'In Stock ($stockQuantity available)' : 'Out of Stock',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isInStock ? _tealColor : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    final description = _product!['description'] ?? 'No description available';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _tealLight.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _tealColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, color: _tealColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Description',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.6,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecificationsSection() {
    String specificationsText = _product!['specifications'].toString();
    
    // Try to parse as JSON if it looks like JSON
    dynamic specsData;
    bool isMap = false;
    bool isList = false;
    
    try {
      if (specificationsText.trim().startsWith('{') || specificationsText.trim().startsWith('[')) {
        specsData = jsonDecode(specificationsText);
        isMap = specsData is Map<String, dynamic>;
        isList = specsData is List;
      }
    } catch (e) {
      // If not JSON, treat as plain text
      specsData = null;
    }

    // Build list of specification items
    List<String> specItems = [];
    
    if (isMap) {
      // If it's a map, format as "Key : Value"
      (specsData as Map<String, dynamic>).forEach((key, value) {
        final formattedKey = key.toString().replaceAll('_', ' ').trim();
        // Clean value - remove escape characters and backslashes
        String formattedValue = value.toString().trim();
        formattedValue = formattedValue.replaceAll('\\n', ' '); // Replace escaped newlines with space
        formattedValue = formattedValue.replaceAll('\\t', ' '); // Replace escaped tabs with space
        formattedValue = formattedValue.replaceAll('\\"', '"'); // Replace escaped double quotes
        formattedValue = formattedValue.replaceAll("\\'", "'"); // Replace escaped single quotes
        formattedValue = formattedValue.replaceAll('\\', ''); // Remove any remaining backslashes
        
        if (formattedKey.isNotEmpty && formattedValue.isNotEmpty) {
          // Format key with first letter uppercase for each word
          final formattedKeyTitle = formattedKey.split(' ').map((word) {
            if (word.isEmpty) return word;
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          }).join(' ');
          specItems.add('$formattedKeyTitle : $formattedValue');
        }
      });
    } else if (isList) {
      // If it's a list, use the values directly (each item should already be formatted)
      specItems = (specsData as List)
          .map((e) {
            String item = e.toString().trim();
            // Clean escape characters and backslashes
            item = item.replaceAll('\\n', ' '); // Replace escaped newlines with space
            item = item.replaceAll('\\t', ' '); // Replace escaped tabs with space
            item = item.replaceAll('\\"', '"'); // Replace escaped double quotes
            item = item.replaceAll("\\'", "'"); // Replace escaped single quotes
            item = item.replaceAll('\\', ''); // Remove any remaining backslashes
            return item;
          })
          .where((item) => item.isNotEmpty)
          .toList();
    } else {
      // If it's plain text, split by common separators
      specItems = _parseSpecificationsText(specificationsText);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Specifications',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 16),
          // Specification items with checkmarks and dividers
          ...specItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isLast = index == specItems.length - 1;
            
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Green checkmark icon
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    // Specification text
                    Expanded(
                      child: Text(
                        item,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.grey.shade800,
                          height: 1.5,
                        ),
                        overflow: TextOverflow.visible,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                // Divider line (not after last item)
                if (!isLast) ...[
                  const SizedBox(height: 12),
                  Divider(
                    color: Colors.grey.shade300,
                    height: 1,
                    thickness: 1,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  List<String> _parseSpecificationsText(String text) {
    // Parse text into list items
    List<String> items = [];
    
    // Try splitting by newlines first
    if (text.contains('\n')) {
      items = text.split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } 
    // Try splitting by semicolons
    else if (text.contains(';')) {
      items = text.split(';')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    // Try splitting by pipes
    else if (text.contains('|')) {
      items = text.split('|')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    // Try splitting by commas (but only if it looks like a list, not a single sentence)
    else if (text.contains(',') && text.split(',').length > 2) {
      items = text.split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    // Otherwise, return as single item
    else {
      items = [text.trim()];
    }
    
    // Clean up items - remove bullet points, dashes, escape characters, and extra formatting
    items = items.map((item) {
      item = item.trim();
      // Remove backslashes and escape characters first (order matters - escape sequences before backslash)
      item = item.replaceAll('\\n', ' '); // Replace escaped newlines with space
      item = item.replaceAll('\\t', ' '); // Replace escaped tabs with space
      item = item.replaceAll('\\"', '"'); // Replace escaped double quotes
      item = item.replaceAll("\\'", "'"); // Replace escaped single quotes
      item = item.replaceAll('\\', ''); // Remove any remaining backslashes
      
      // Remove bullet points and dashes at the start
      while (item.isNotEmpty && 
             (item.startsWith('•') || item.startsWith('-') || item.startsWith('*') || item.startsWith('○'))) {
        item = item.substring(1).trim();
      }
      // Remove any leading brackets or quotes
      while (item.isNotEmpty && 
             (item.startsWith('[') || item.startsWith('{') || item.startsWith('(') || 
              item.startsWith('"') || item.startsWith("'"))) {
        item = item.substring(1).trim();
      }
      // Remove any trailing brackets or quotes
      while (item.isNotEmpty && 
             (item.endsWith(']') || item.endsWith('}') || item.endsWith(')') || 
              item.endsWith('"') || item.endsWith("'"))) {
        item = item.substring(0, item.length - 1).trim();
      }
      return item;
    }).toList();
    
    return items.where((item) => item.isNotEmpty).toList();
  }

  String _formatSpecificationsText(String text) {
    // Format the text - replace common separators with line breaks
    String formatted = text
        .replaceAll('\\n', '\n')
        .replaceAll('; ', '\n• ')
        .replaceAll(', ', '\n• ')
        .replaceAll('|', '\n• ');
    
    // Add bullet point if lines don't start with one
    if (!formatted.trim().startsWith('•') && !formatted.trim().startsWith('-')) {
      List<String> lines = formatted.split('\n');
      lines = lines.map((line) {
        line = line.trim();
        if (line.isNotEmpty && !line.startsWith('•') && !line.startsWith('-')) {
          return '• $line';
        }
        return line;
      }).toList();
      formatted = lines.join('\n');
    }
    
    return formatted;
  }

  Widget _buildAdditionalDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: _tealColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Product Information',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Unit', _product!['unit']),
          _buildInfoRow('Size', _product!['size']),
          _buildInfoRow('Weight', _product!['weight']),
          _buildInfoRow('Dimensions', _product!['dimensions']),
          _buildInfoRow('Color', _product!['color']),
          _buildInfoRow('Material', _product!['material']),
          _buildInfoRow('SKU', _product!['sku'] ?? _product!['sku_code']),
          _buildInfoRow('HSN Code', _product!['hsn_code']),
          _buildInfoRow('Barcode', _product!['barcode']),
          if (_product!['tax_rate'] != null) ...[
            Builder(
              builder: (context) {
              final taxRate = _product!['tax_rate'];
              final taxRateNum = taxRate is String 
                  ? double.tryParse(taxRate) ?? 0.0 
                  : (taxRate is num ? taxRate.toDouble() : 0.0);
              if (taxRateNum > 0) {
                return _buildInfoRow('Tax Rate', '${taxRateNum.toStringAsFixed(2)}% (${_product!['tax_type'] ?? 'Inclusive'})');
              }
                return const SizedBox.shrink();
              },
            ),
          ],
          if (_product!['expiry_date'] != null && _product!['expiry_date'].toString().isNotEmpty)
            _buildInfoRow('Expiry Date', _product!['expiry_date'].toString()),
          if (_product!['variant_name'] != null && _product!['variant_name'].toString().isNotEmpty)
            _buildInfoRow('Variant', _product!['variant_name'].toString()),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget for service images with proxy fallback
class _ServiceImageWidget extends StatefulWidget {
  final List<String> imageUrls;
  final String serviceName;

  const _ServiceImageWidget({
    super.key,
    required this.imageUrls,
    required this.serviceName,
  });

  @override
  State<_ServiceImageWidget> createState() => _ServiceImageWidgetState();
}

class _ServiceImageWidgetState extends State<_ServiceImageWidget> {
  int _currentImageIndex = 0;
  int _currentUrlIndex = 0; // 0 = primary URL, 1 = fallback URL, 2 = proxy
  bool _hasError = false;

  String _getFallbackUrl(String originalUrl) {
    // Convert Hostinger file server URLs to regular domain (since file server is failing)
    if (originalUrl.contains('srv1881-files.hstgr.io')) {
      final filename = originalUrl.split('/').last.split('?').first.split('#').first;
      return 'https://superdailys.com/storage/services/' + filename;
    }
    // If already using regular domain, try Hostinger file server as fallback
    if (originalUrl.contains('superdailys.com/storage/services/')) {
      final filename = originalUrl.split('/').last.split('?').first.split('#').first;
      return 'https://srv1881-files.hstgr.io/4663f5e73332121d/files/public_html/public/storage/services/' + filename;
    }
    return originalUrl;
  }

  String _getProxiedUrl(String url) {
    final encodedUrl = Uri.encodeComponent(url);
    return 'https://superdailys.com/superdailyapp/proxy_image.php?url=$encodedUrl';
  }

  String _getCurrentImageUrl() {
    if (_currentImageIndex >= widget.imageUrls.length) return '';
    final baseUrl = widget.imageUrls[_currentImageIndex];
    
    // Try proxy first (bypasses CORS), then direct URL, then fallback
    // 0 = proxy (try first to bypass CORS)
    if (_currentUrlIndex == 0) {
      return _getProxiedUrl(baseUrl);
    }
    // 1 = primary URL (from API)
    if (_currentUrlIndex == 1) {
      return baseUrl;
    }
    // 2 = fallback URL (alternative server)
    if (_currentUrlIndex == 2) {
      return _getFallbackUrl(baseUrl);
    }
    return baseUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || _currentImageIndex >= widget.imageUrls.length) {
      // All images failed or no images
      return Container(
        color: const Color(0xFFE0F2F1),
        child: Icon(Icons.room_service, color: Colors.grey.shade400, size: 40),
      );
    }

    final imageUrl = _getCurrentImageUrl();
    if (imageUrl.isEmpty) {
      return Container(
        color: const Color(0xFFE0F2F1),
        child: Icon(Icons.room_service, color: Colors.grey.shade400, size: 40),
      );
    }

    final urlType = ['proxy', 'primary', 'fallback'][_currentUrlIndex];
    debugPrint('🖼️ Service - Trying to load image [${_currentImageIndex + 1}/${widget.imageUrls.length}] ($urlType) for "${widget.serviceName}": $imageUrl');

    return CachedNetworkImage(
      key: ValueKey('${imageUrl}_${_currentUrlIndex}_${_currentImageIndex}'), // Force rebuild on URL change
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      maxWidthDiskCache: 1000,
      maxHeightDiskCache: 1000,
      cacheKey: '${imageUrl}_${_currentUrlIndex}_${_currentImageIndex}', // Unique cache key per URL/fallback/image
      httpHeaders: {
        'Accept': 'image/*',
      },
      placeholder: (context, url) => Container(
        color: const Color(0xFFE0F2F1),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
      ),
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 100),
      errorWidget: (context, url, error) {
        final urlType = ['proxy', 'primary', 'fallback'][_currentUrlIndex];
        debugPrint('❌ Service - Image failed to load [${_currentImageIndex + 1}/${widget.imageUrls.length}] ($urlType) for "${widget.serviceName}": $url');
        debugPrint('   Error type: ${error.runtimeType}');
        debugPrint('   Error: $error');
        
        // Add delay before retrying to avoid rapid state changes
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          
          // Try primary URL if proxy failed
          if (_currentUrlIndex == 0) {
            setState(() {
              _currentUrlIndex = 1; // Try primary URL
            });
            return;
          }
          
          // Try fallback URL if primary also failed
          if (_currentUrlIndex == 1) {
            setState(() {
              _currentUrlIndex = 2; // Try fallback URL
            });
            return;
          }
          
          // All URLs failed for this image, try next image if available
          if (_currentImageIndex < widget.imageUrls.length - 1) {
            setState(() {
              _currentImageIndex++;
              _currentUrlIndex = 0; // Reset to try primary first
            });
            return;
          }
          
          // No more images to try
          setState(() {
            _hasError = true;
          });
        });
        
        // Show loading indicator while retrying
        return Container(
          color: const Color(0xFFE0F2F1),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
            ),
          ),
        );
      },
    );
  }
}

// Widget to try multiple images in sequence if one fails
class _ProductImageWidget extends StatefulWidget {
  final List<String> imageUrls;
  final String productName;

  const _ProductImageWidget({
    required this.imageUrls,
    required this.productName,
  });

  @override
  State<_ProductImageWidget> createState() => _ProductImageWidgetState();
}

class _ProductImageWidgetState extends State<_ProductImageWidget> {
  int _currentImageIndex = 0;
  int _currentFallbackIndex = 0; // 0 = direct, 1 = proxy
  bool _hasError = false;

  String _getProxiedUrl(String url) {
    final encodedUrl = Uri.encodeComponent(url);
    // Try proxy - adjust path if your proxy_image.php is in a different location
    return 'https://superdailys.com/superdailyapp/proxy_image.php?url=$encodedUrl';
  }

  String _getCurrentImageUrl() {
    if (_currentImageIndex >= widget.imageUrls.length) return '';
    final baseUrl = widget.imageUrls[_currentImageIndex];
    // Try proxy first (bypasses CORS), then direct URL
    // 0 = proxy (try first to bypass CORS)
    if (_currentFallbackIndex == 0) {
      return _getProxiedUrl(baseUrl);
    }
    // 1 = direct URL (from API)
    if (_currentFallbackIndex == 1) {
      return baseUrl;
    }
    return baseUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || _currentImageIndex >= widget.imageUrls.length) {
      // All images failed or no images
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFE0F2F1),
        child: Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 32),
      );
    }

    final imageUrl = _getCurrentImageUrl();
    if (imageUrl.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFE0F2F1),
        child: Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 32),
      );
    }

    final urlType = ['proxy', 'direct'][_currentFallbackIndex];
    debugPrint('🖼️ Product - Trying to load image [${_currentImageIndex + 1}/${widget.imageUrls.length}] ($urlType) for "${widget.productName}": $imageUrl');

    return CachedNetworkImage(
      key: ValueKey('${imageUrl}_${_currentFallbackIndex}_${_currentImageIndex}'),
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      maxWidthDiskCache: 1000,
      maxHeightDiskCache: 1000,
      cacheKey: '${imageUrl}_${_currentFallbackIndex}_${_currentImageIndex}',
      httpHeaders: {
        'Accept': 'image/*',
      },
      placeholder: (context, url) => Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFE0F2F1),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
      ),
      errorWidget: (context, url, error) {
        final urlType = ['proxy', 'direct'][_currentFallbackIndex];
        debugPrint('❌ Image failed to load [${_currentImageIndex + 1}/${widget.imageUrls.length}] ($urlType) for "${widget.productName}": $url');
        debugPrint('   Error type: ${error.runtimeType}');
        debugPrint('   Error: $error');
        
        // If proxy failed, try direct URL for same image
        if (_currentFallbackIndex == 0) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _currentFallbackIndex = 1; // Try direct URL
              });
            }
          });
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFFE0F2F1),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
            ),
          );
        }
        
        // Direct URL also failed, try next image if available
        if (_currentImageIndex < widget.imageUrls.length - 1) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _currentImageIndex++;
                _currentFallbackIndex = 0; // Reset to try proxy first for next image
              });
            }
          });
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFFE0F2F1),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
            ),
          );
        } else {
          // No more images to try
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _hasError = true;
              });
            }
          });
          return Container(
            color: const Color(0xFFE0F2F1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 32),
                const SizedBox(height: 4),
                Text(
                  'No image',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const HomeScreen({super.key, required this.userData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<dynamic> _featuredProducts = [];
  bool _isLoadingProducts = true;
  List<dynamic> _allProducts = [];
  bool _isLoadingAllProducts = true;
  List<dynamic> _categories = [];
  bool _isLoadingCategories = true;
  List<dynamic> _oneTimeServices = [];
  bool _isLoadingServices = true;
  List<dynamic> _monthlySubscriptionServices = [];
  bool _isLoadingMonthlyServices = true;
  List<dynamic> _myBookings = [];
  bool _isLoadingBookings = true;
  late PageController _carouselController;
  int _currentCarouselIndex = 0;
  static const Color _tealColor = Color(0xFF00BFA5);
  static const Color _tealLight = Color(0xFFE0F2F1);
  static const Color _tealLighter = Color(0xFFF0F9F8);
  static const Color _priceDarkBlue = Color(0xFF0D47A1);
  static const String _backendBaseUrl = 'https://superdailys.com/superdailyapp/';

  String _resolveImageUrl(String raw) {
    if (raw.isEmpty) return raw;
    String p = raw.trim();
    // Normalize slashes
    p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
    
    // Already absolute URL starting with https://superdailys.com/storage/products/
    if (p.startsWith('https://superdailys.com/storage/products/')) {
      return p;
    }
    
    // Already absolute URL (any other URL)
    if (p.startsWith('http://') || p.startsWith('https://')) {
      // If it's a full URL but not from the storage/products path, try to extract filename
      if (!p.contains('/storage/products/')) {
        final filename = p.split('/').last.split('?').first.split('#').first;
        if (filename.isNotEmpty && filename.contains('.')) {
          return 'https://superdailys.com/storage/products/' + filename;
        }
      }
      return p;
    }
    
    // Extract just the filename from the path
    String filename = p.split('/').last.split('\\').last;
    // Remove query parameters and hash
    filename = filename.split('?').first.split('#').first;
    
    // If filename is empty or doesn't have extension, try to find it
    if (filename.isEmpty || !filename.contains('.')) {
      // Try to find filename in the path
      final parts = p.split('/');
      for (var part in parts.reversed) {
        if (part.contains('.') && part.length > 3) {
          filename = part.split('?').first.split('#').first;
          break;
        }
      }
    }
    
    // Build full URL with storage/products base
    if (filename.isNotEmpty && filename.contains('.')) {
      final url = 'https://superdailys.com/storage/products/' + filename;
      debugPrint('Resolved image URL: $url');
      return url;
    }
    
    // Fallback to old method
    // Remove leading ./ or ../
    while (p.startsWith('./') || p.startsWith('../')) {
      p = p.startsWith('./') ? p.substring(2) : p.substring(3);
    }
    // If path contains spdbackend in the middle (e.g., C:/xampp/htdocs/spdbackend/uploads/img.png)
    final spdIdx = p.indexOf('/spdbackend/');
    if (spdIdx != -1) {
      p = p.substring(spdIdx + '/spdbackend/'.length);
    }
    // If path contains htdocs/ or www/ folders, strip up to them
    for (final marker in ['/htdocs/', '/www/']) {
      final idx = p.indexOf(marker);
      if (idx != -1) {
        p = p.substring(idx + marker.length);
      }
    }
    // Ensure no leading slash duplication
    if (p.startsWith('/')) p = p.substring(1);
    final url = _backendBaseUrl + p;
    debugPrint('Resolved image URL (fallback): ' + url);
    return url;
  }

  @override
  void initState() {
    super.initState();
    _carouselController = PageController(viewportFraction: 1.0);
    _fetchFeaturedProducts();
    _fetchCategories();
    _fetchOneTimeServices();
    _fetchMonthlySubscriptionServices();
    _fetchMyBookings();
    _startCarouselTimer();
  }

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
  }

  void _startCarouselTimer() {
    // Auto-switch carousel every 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _currentCarouselIndex = (_currentCarouselIndex + 1) % 4;
        _carouselController.animateToPage(
          _currentCarouselIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        _startCarouselTimer();
      }
    });
  }

  Future<void> _fetchFeaturedProducts() async {
    try {
      const String apiUrl = 'https://superdailys.com/superdailyapp/get_all_products.php';
      
      print('🌐 Fetching products from: $apiUrl');
      
      final response = await http.get(
        Uri.parse(apiUrl),
        // Don't set Content-Type for GET requests to avoid CORS issues
      );

      print('📡 Response Status Code: ${response.statusCode}');
      print('📡 Response Headers: ${response.headers}');

      if (mounted) {
        if (response.statusCode == 200) {
          try {
          final data = jsonDecode(response.body);
            print('✅ JSON decoded successfully');
            print('📋 Response keys: ${data.keys.toList()}');
            
          if (data['success'] == true) {
            final products = data['products'] ?? [];
              print('✅ Fetched ${products.length} products'); // Debug
            print('📊 Product count from API: ${data['count']}'); // Debug
              print('📊 Total in DB: ${data['total_in_db'] ?? 'N/A'}'); // Debug
              
              print('📦 Products array length: ${products.length}'); // Debug
              if (products.isNotEmpty) {
                print('✅ First product sample: ${products[0]}'); // Debug
              } else {
                print('⚠️ Products array is empty even though success=true');
                print('📋 Full API Response: ${response.body}');
            }
            
            setState(() {
              _featuredProducts = products;
              _isLoadingProducts = false;
            });
          } else {
            print('❌ API returned success=false: ${data['message']}'); // Debug
              print('📋 Full API Response: ${response.body}'); // Debug
              setState(() {
                _isLoadingProducts = false;
              });
            }
          } catch (jsonError) {
            print('❌ JSON Decode Error: $jsonError');
            print('📋 Raw Response Body: ${response.body}');
            setState(() {
              _isLoadingProducts = false;
            });
          }
        } else {
          print('❌ API Error Status: ${response.statusCode}'); // Debug
          print('📋 Full Response Body: ${response.body}'); // Debug
          setState(() {
            _isLoadingProducts = false;
          });
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error fetching products: $e'); // Debug
      print('📋 Stack Trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoadingProducts = false;
        });
      }
    }
  }

  Future<void> _fetchAllProducts() async {
    try {
      const String apiUrl = 'https://superdailys.com/superdailyapp/get_featured_products.php';
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final products = data['products'] ?? [];
            setState(() {
              _allProducts = products;
              _isLoadingAllProducts = false;
            });
          } else {
            setState(() {
              _isLoadingAllProducts = false;
            });
          }
        } else {
          setState(() {
            _isLoadingAllProducts = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAllProducts = false;
        });
      }
    }
  }

  Future<void> _fetchCategories() async {
    try {
      const String apiUrl = 'https://superdailys.com/superdailyapp/get_categories.php';
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final categories = data['categories'] ?? [];
            print('Fetched ${categories.length} categories'); // Debug
            setState(() {
              _categories = categories;
              _isLoadingCategories = false;
            });
          } else {
            print('Categories API returned success=false: ${data['message']}'); // Debug
            setState(() {
              _isLoadingCategories = false;
            });
          }
        } else {
          print('Categories API Error Status: ${response.statusCode}'); // Debug
          print('Response: ${response.body}'); // Debug
          setState(() {
            _isLoadingCategories = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        print('Categories fetch error: $e'); // Debug
        setState(() {
          _isLoadingCategories = false;
        });
      }
    }
  }

  Future<void> _fetchOneTimeServices() async {
    try {
      const String apiUrl = 'https://superdailys.com/superdailyapp/get_one_time_services.php';
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final services = data['services'] ?? [];
            print('✅ Fetched ${services.length} one-time services'); // Debug
            
            // Debug: Check first service images
            if (services.isNotEmpty) {
              final firstService = services[0];
              print('🔍 First service sample: ${firstService['name']}');
              print('   image: ${firstService['image']}');
              print('   image_2: ${firstService['image_2']}');
              print('   image_3: ${firstService['image_3']}');
              print('   image_4: ${firstService['image_4']}');
            }
            
            setState(() {
              _oneTimeServices = services;
              _isLoadingServices = false;
            });
          } else {
            print('❌ One-time services API returned success=false: ${data['message']}'); // Debug
            setState(() {
              _isLoadingServices = false;
            });
          }
        } else {
          print('❌ One-time services API Error Status: ${response.statusCode}'); // Debug
          print('📋 Response: ${response.body}'); // Debug
          setState(() {
            _isLoadingServices = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        print('One-time services fetch error: $e'); // Debug
        setState(() {
          _isLoadingServices = false;
        });
      }
    }
  }

  Future<void> _fetchMonthlySubscriptionServices() async {
    try {
      const String apiUrl = 'https://superdailys.com/superdailyapp/get_monthly_subscription_services.php';
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final services = data['services'] ?? [];
            print('✅ Fetched ${services.length} monthly subscription services'); // Debug
            
            // Debug: Check first service images
            if (services.isNotEmpty) {
              final firstService = services[0];
              print('🔍 First monthly service sample: ${firstService['name']}');
              print('   image: ${firstService['image']}');
              print('   image_2: ${firstService['image_2']}');
              print('   image_3: ${firstService['image_3']}');
              print('   image_4: ${firstService['image_4']}');
            }
            
            setState(() {
              _monthlySubscriptionServices = services;
              _isLoadingMonthlyServices = false;
            });
          } else {
            print('❌ Monthly subscription services API returned success=false: ${data['message']}'); // Debug
            setState(() {
              _isLoadingMonthlyServices = false;
            });
          }
        } else {
          print('❌ Monthly subscription services API Error Status: ${response.statusCode}'); // Debug
          print('📋 Response: ${response.body}'); // Debug
          setState(() {
            _isLoadingMonthlyServices = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        print('Monthly subscription services fetch error: $e'); // Debug
        setState(() {
          _isLoadingMonthlyServices = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navbar
            _buildAppBar(),
            // Main Content
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: _tealColor,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book_online),
            label: 'My Bookings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildImageCarousel() {
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            controller: _carouselController,
            itemCount: 4,
            onPageChanged: (index) {
              setState(() {
                _currentCarouselIndex = index;
              });
            },
            itemBuilder: (context, index) {
              // Carousel images: b1, b2, b3, b4
              final imagePaths = [
                'images/b1.png',
                'images/b2.png',
                'images/b3.png',
                'images/b4.png',
              ];
              
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    imagePaths[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: _tealColor.withOpacity(0.8),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported,
                                size: 64,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Banner ${index + 1}',
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          // Page Indicator
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                4,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentCarouselIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF00BFA5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side: Logo
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            ),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: Image.asset(
                'images/logo.png',
                height: 36,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          // Right side: Search and Account Icons
          Row(
            children: [
              // Search Icon
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: () {
                  // Search functionality can be added here
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Search'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              // Account Icon
              IconButton(
                icon: const Icon(Icons.account_circle, color: Colors.white),
                onPressed: () {
                  // Navigate to profile or show account options
                  setState(() {
                    _currentIndex = 2; // Navigate to Profile tab
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildBookingsTab();
      case 2:
        return _buildProfileTab();
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Carousel
          const SizedBox(height: 24),
          _buildImageCarousel(),
          const SizedBox(height: 16),
          // Featured Products Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'All Products',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                if (!_isLoadingProducts && _featuredProducts.isNotEmpty)
                  Text(
                    '${_featuredProducts.length} products',
                      style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Featured Products List - Vertical List View
          _isLoadingProducts
              ? const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_tealColor),
                    ),
                  ),
                )
              : _featuredProducts.isEmpty
                  ? SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No products available',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Check console for API errors',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 200,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: _featuredProducts.length,
                        itemBuilder: (context, index) {
                          try {
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == _featuredProducts.length - 1 ? 0 : 12,
                            ),
                              child: SizedBox(
                                width: 160,
                                child: _buildProductListItem(_featuredProducts[index]),
                              ),
                            );
                          } catch (e, stackTrace) {
                            print('❌ Error building product item at index $index: $e');
                            print('📋 Stack trace: $stackTrace');
                            print('📦 Product data: ${_featuredProducts[index]}');
                            // Return error widget instead of crashing
                            return Container(
                              width: 160,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                'Error loading product: ${e.toString()}',
                                style: GoogleFonts.poppins(fontSize: 12, color: Colors.red.shade700),
                              ),
                            );
                          }
                        },
                      ),
                    ),
          const SizedBox(height: 24),
          // Categories Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Categories',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _isLoadingCategories
              ? const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                    ),
                  ),
                )
              : _categories.isEmpty
                  ? SizedBox(
                      height: 120,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.category_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No categories available',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == _categories.length - 1 ? 0 : 12,
                            ),
                            child: _buildCategoryCardFromData(_categories[index]),
                          );
                        },
                      ),
                    ),
          const SizedBox(height: 24),
          // One Time Service Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'One Time Service',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                if (!_isLoadingServices && _oneTimeServices.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AllServicesScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'View All',
                      style: GoogleFonts.poppins(
                        color: _tealColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _isLoadingServices
              ? const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                    ),
                  ),
                )
              : _oneTimeServices.isEmpty
                  ? SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.room_service_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No one-time services available',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 200,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: _oneTimeServices.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == _oneTimeServices.length - 1 ? 0 : 12,
                            ),
                            child: _buildOneTimeServiceCard(_oneTimeServices[index]),
                          );
                        },
                      ),
                    ),
          const SizedBox(height: 24),
          // Monthly Subscription Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Monthly Subscription',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                if (!_isLoadingMonthlyServices && _monthlySubscriptionServices.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AllServicesScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'View All',
                      style: GoogleFonts.poppins(
                        color: _tealColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _isLoadingMonthlyServices
              ? const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                    ),
                  ),
                )
              : _monthlySubscriptionServices.isEmpty
                  ? SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.subscriptions_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No monthly subscription services available',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 200,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: _monthlySubscriptionServices.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == _monthlySubscriptionServices.length - 1 ? 0 : 12,
                            ),
                            child: _buildOneTimeServiceCard(_monthlySubscriptionServices[index]),
                          );
                        },
                      ),
                    ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    // Fetch products when tab is opened
    if (_isLoadingAllProducts && _allProducts.isEmpty) {
      _fetchAllProducts();
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All Products',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),
          _isLoadingAllProducts
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _allProducts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No products available',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: _allProducts.length,
                      itemBuilder: (context, index) {
                        return _buildProductCardFromData(_allProducts[index]);
                      },
                    ),
        ],
      ),
    );
  }

  Future<void> _fetchMyBookings() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingBookings = true;
    });
    
    try {
      final userId = widget.userData['id'] ?? widget.userData['user_id'];
      if (userId == null) {
        setState(() {
          _isLoadingBookings = false;
          _myBookings = [];
        });
        return;
      }
      
      final apiUrl = 'https://superdailys.com/superdailyapp/get_my_bookings.php?user_id=' + userId.toString();
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
      );
      
      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['bookings'] != null) {
            setState(() {
              _myBookings = data['bookings'];
              _isLoadingBookings = false;
            });
          } else {
            setState(() {
              _myBookings = [];
              _isLoadingBookings = false;
            });
          }
        } else {
          setState(() {
            _myBookings = [];
            _isLoadingBookings = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error fetching bookings: $e');
        setState(() {
          _myBookings = [];
          _isLoadingBookings = false;
        });
      }
    }
  }

  Widget _buildBookingsTab() {
    return RefreshIndicator(
      onRefresh: _fetchMyBookings,
      color: _tealColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and refresh button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Bookings',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
                ),
                IconButton(
                  icon: _isLoadingBookings
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                          ),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: _isLoadingBookings ? null : _fetchMyBookings,
                  tooltip: 'Refresh',
                  color: _tealColor,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _isLoadingBookings
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
                      ),
                    ),
                  )
                : _myBookings.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.book_online_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No bookings found',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your bookings will appear here',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: _myBookings.map((booking) => _buildBookingCard(booking)).toList(),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final bookingRef = booking['booking_reference'] ?? 'N/A';
    final bookingDate = booking['booking_date'] ?? '';
    final bookingTime = booking['booking_time'] ?? '';
    final status = booking['status'] ?? 'pending';
    final paymentStatus = booking['payment_status'] ?? 'pending';
    final finalAmount = double.tryParse(booking['final_amount']?.toString() ?? '0') ?? 0.0;
    final address = booking['address'] ?? 'No address';
    final serviceId = booking['service_id'];
    final serviceName = serviceId != null ? 'Service #$serviceId' : 'Service';
    
    // Status colors
    Color statusColor;
    String statusText;
    switch (status.toLowerCase()) {
      case 'confirmed':
        statusColor = Colors.green;
        statusText = 'Confirmed';
        break;
      case 'completed':
        statusColor = Colors.blue;
        statusText = 'Completed';
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusText = 'Cancelled';
        break;
      case 'in_progress':
      case 'started':
        statusColor = Colors.orange;
        statusText = 'In Progress';
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Pending';
    }
    
    // Payment status colors
    Color paymentColor;
    String paymentText;
    switch (paymentStatus.toLowerCase()) {
      case 'paid':
      case 'completed':
        paymentColor = Colors.green;
        paymentText = 'Paid';
        break;
      case 'failed':
        paymentColor = Colors.red;
        paymentText = 'Failed';
        break;
      case 'pending':
      default:
        paymentColor = Colors.orange;
        paymentText = 'Pending';
    }
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookingDetailsScreen(booking: booking),
          ),
        );
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status badges
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _tealLight,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ref: $bookingRef',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        serviceName,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusText,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: paymentColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        paymentText,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: paymentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Booking details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date and Time
                if (bookingDate.isNotEmpty || bookingTime.isNotEmpty)
                  _buildBookingDetailRow(
                    Icons.calendar_today,
                    '${bookingDate.isNotEmpty ? bookingDate : "Not set"} ${bookingTime.isNotEmpty ? "at $bookingTime" : ""}',
                  ),
                const SizedBox(height: 8),
                // Address
                _buildBookingDetailRow(Icons.location_on, address),
                if (booking['phone'] != null && booking['phone'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildBookingDetailRow(Icons.phone, booking['phone'].toString()),
                ],
                if (finalAmount > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        '₹${finalAmount.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _priceDarkBlue,
                        ),
                      ),
                    ],
                  ),
                ],
                if (booking['special_instructions'] != null && booking['special_instructions'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Special Instructions',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          booking['special_instructions'].toString(),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBookingDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServicesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Our Services',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),
          _buildServiceCard('Consultation Service', 'Expert consultation for your needs', Icons.chat),
          const SizedBox(height: 12),
          _buildServiceCard('Technical Support', '24/7 technical assistance', Icons.support),
          const SizedBox(height: 12),
          _buildServiceCard('Maintenance', 'Regular maintenance services', Icons.build),
          const SizedBox(height: 12),
          _buildServiceCard('Installation', 'Professional installation services', Icons.settings),
          const SizedBox(height: 12),
          _buildServiceCard('Training', 'Comprehensive training programs', Icons.school),
          const SizedBox(height: 12),
          _buildServiceCard('Custom Development', 'Tailored solutions for you', Icons.code),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Profile Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _tealColor,
                  const Color(0xFF00A692),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.person,
                    size: 50,
                    color: _tealColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.userData['name'] ?? 'User',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.userData['phone'] ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                if (widget.userData['email'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.userData['email'] ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Menu Items
          _buildProfileMenuItem(Icons.edit, 'Edit Profile', () {}),
          const SizedBox(height: 12),
          _buildProfileMenuItem(Icons.shopping_cart_outlined, 'My Orders', () {}),
          const SizedBox(height: 12),
          _buildProfileMenuItem(Icons.favorite_border, 'Favorites', () {}),
          const SizedBox(height: 12),
          _buildProfileMenuItem(Icons.settings, 'Settings', () {}),
          const SizedBox(height: 12),
          _buildProfileMenuItem(Icons.help_outline, 'Help & Support', () {}),
          const SizedBox(height: 12),
          _buildProfileMenuItem(Icons.logout, 'Logout', () async {
            // Clear saved login data
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('isLoggedIn', false);
            await prefs.remove('userData');
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            }
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(IconData icon, String title, Color color) {
    return Container(
      width: 100,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // Helper function to convert icon string to IconData
  IconData _getIconFromString(String iconName) {
    // Map common icon names to Flutter icons
    switch (iconName.toLowerCase()) {
      case 'shopping_cart':
      case 'cart':
        return Icons.shopping_cart;
      case 'room_service':
      case 'service':
        return Icons.room_service;
      case 'support_agent':
      case 'support':
        return Icons.support_agent;
      case 'local_offer':
      case 'offer':
        return Icons.local_offer;
      case 'category':
        return Icons.category;
      case 'inventory':
        return Icons.inventory;
      case 'phone':
        return Icons.phone;
      case 'email':
        return Icons.email;
      case 'location':
        return Icons.location_on;
      case 'home':
        return Icons.home;
      case 'store':
        return Icons.store;
      default:
        return Icons.category; // Default icon
    }
  }

  // Helper function to parse hex color string to Color
  Color _parseColorFromString(String colorString) {
    try {
      // Remove # if present
      String hex = colorString.replaceAll('#', '');
      // Handle both 6 and 8 character hex codes
      if (hex.length == 6) {
        hex = 'FF$hex'; // Add alpha if missing
      }
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      // Default to teal color if parsing fails
      return _tealColor;
    }
  }

  Widget _buildCategoryCardFromData(Map<String, dynamic> category) {
    final iconName = category['icon'] ?? 'category';
    final icon = _getIconFromString(iconName);
    final colorString = category['color'] ?? '#00BFA5';
    final color = _parseColorFromString(colorString);
    final name = category['name'] ?? 'Category';
    final image = category['image'] ?? '';

    return Container(
      width: 100,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Show image if available, otherwise show icon
          if (image != null && image.toString().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: Uri.encodeFull(_resolveImageUrl(image.toString())),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                placeholder: (context, url) => SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                errorWidget: (context, url, error) => Icon(icon, size: 40, color: color),
              ),
            )
          else
            Icon(icon, size: 40, color: color),
          const SizedBox(height: 8),
          Text(
            name,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Helper function to parse price value
  double? _parsePrice(dynamic priceValue) {
    if (priceValue == null || priceValue == '' || priceValue == 'null') return null;
    if (priceValue is String) {
      String s = priceValue.trim();
      // Remove currency symbols, commas, and any non-numeric (keep first dot and minus)
      s = s.replaceAll(RegExp(r'[₹$,]'), '');
      s = s.replaceAll(RegExp(r'[^0-9\.-]'), '');
      // If multiple dots, keep first
      final firstDot = s.indexOf('.');
      if (firstDot != -1) {
        final before = s.substring(0, firstDot + 1);
        final after = s.substring(firstDot + 1).replaceAll('.', '');
        s = before + after;
      }
      if (s.isEmpty || s == '-' || s == '.') return null;
      return double.tryParse(s);
    } else if (priceValue is num) {
      return priceValue.toDouble();
    }
    return null;
  }

  // Helper function to get the appropriate price based on service type
  double? _getServicePrice(Map<String, dynamic> service) {
    final name = (service['name'] ?? '').toString().toLowerCase();
    final subcategory = (service['subcategory'] ?? '').toString().toLowerCase();
    final mainCategory = (service['main_category'] ?? '').toString().toLowerCase();
    final propertyType = (service['property_type'] ?? '').toString().toLowerCase();
    final personsCount = service['persons_count'];

    // Check if this is a monthly subscription service
    final isMonthlySubscription = mainCategory.contains('monthly') || mainCategory.contains('subscription');

    // Determine service type from name or subcategory
    final isWashroomCleaning = name.contains('washroom') || subcategory.contains('washroom');
    final isHouseCleaning = name.contains('house cleaning') || name.contains('home cleaning') || 
                           subcategory.contains('house') || subcategory.contains('home') ||
                           (!isWashroomCleaning && (name.contains('cleaning') || subcategory.contains('cleaning')));
    final isSuperCleaning = name.contains('super cleaning') || subcategory.contains('super cleaning');
    final isCooking = name.contains('chef') || name.contains('cooking') || 
                     subcategory.contains('chef') || subcategory.contains('cooking');

    // 1. WASHROOM CLEANING - Use washroom prices (priority order)
    if (isWashroomCleaning) {
      final washroom2Price = _parsePrice(service['price_2_washroom']);
      final washroom3Price = _parsePrice(service['price_3_washroom']);
      final washroom4Price = _parsePrice(service['price_4_washroom']);
      final washroom4PlusPrice = _parsePrice(service['price_4_plus_washroom']);
      
      // Return first available washroom price
      if (washroom2Price != null && washroom2Price > 0) return washroom2Price;
      if (washroom3Price != null && washroom3Price > 0) return washroom3Price;
      if (washroom4Price != null && washroom4Price > 0) return washroom4Price;
      if (washroom4PlusPrice != null && washroom4PlusPrice > 0) return washroom4PlusPrice;
    }

    // 2. HOUSE CLEANING / SUPER CLEANING - Use BHK prices
    if (isHouseCleaning || isSuperCleaning) {
      // Check property_type first
      if (propertyType.isNotEmpty) {
        if (propertyType.contains('1') || propertyType.contains('1bhk')) {
          final bhk1Price = _parsePrice(service['price_1_bhk']);
          if (bhk1Price != null && bhk1Price > 0) return bhk1Price;
        }
        if (propertyType.contains('2') || propertyType.contains('2bhk')) {
          final bhk2Price = _parsePrice(service['price_2_bhk']);
          if (bhk2Price != null && bhk2Price > 0) return bhk2Price;
        }
        if (propertyType.contains('3') || propertyType.contains('3bhk')) {
          final bhk3Price = _parsePrice(service['price_3_bhk']);
          if (bhk3Price != null && bhk3Price > 0) return bhk3Price;
        }
        if (propertyType.contains('4') || propertyType.contains('4bhk')) {
          final bhk4Price = _parsePrice(service['price_4_bhk']);
          if (bhk4Price != null && bhk4Price > 0) return bhk4Price;
        }
      }
      
      // If property_type not available, return first available BHK price
      final bhk1Price = _parsePrice(service['price_1_bhk']);
      final bhk2Price = _parsePrice(service['price_2_bhk']);
      final bhk3Price = _parsePrice(service['price_3_bhk']);
      final bhk4Price = _parsePrice(service['price_4_bhk']);
      
      if (bhk1Price != null && bhk1Price > 0) return bhk1Price;
      if (bhk2Price != null && bhk2Price > 0) return bhk2Price;
      if (bhk3Price != null && bhk3Price > 0) return bhk3Price;
      if (bhk4Price != null && bhk4Price > 0) return bhk4Price;
    }

    // 3. COOKING / CHEF SERVICES - Use person-based prices or cooking_price
    if (isCooking) {
      // First check cooking_price
      final cookingPrice = _parsePrice(service['cooking_price']);
      if (cookingPrice != null && cookingPrice > 0) return cookingPrice;

      // Then check person count prices
      if (personsCount != null) {
        final count = personsCount is String ? int.tryParse(personsCount) : (personsCount is num ? personsCount.toInt() : null);
        if (count != null) {
          if (count == 1) {
            final price1 = _parsePrice(service['price_1_person']);
            if (price1 != null && price1 > 0) return price1;
          } else if (count == 2) {
            final price2 = _parsePrice(service['price_2_persons']);
            if (price2 != null && price2 > 0) return price2;
          } else if (count >= 1 && count <= 2) {
            final price12 = _parsePrice(service['price_1_2_persons']);
            if (price12 != null && price12 > 0) return price12;
          } else if (count >= 2 && count <= 5) {
            final price25 = _parsePrice(service['price_2_5_persons']);
            if (price25 != null && price25 > 0) return price25;
          } else if (count >= 5 && count <= 10) {
            final price510 = _parsePrice(service['price_5_10_persons']);
            if (price510 != null && price510 > 0) return price510;
          } else if (count > 10) {
            final price10Plus = _parsePrice(service['price_10_plus_persons']);
            if (price10Plus != null && price10Plus > 0) return price10Plus;
          }
        }
      }
      
      // Return first available person-based price
      final price1 = _parsePrice(service['price_1_person']);
      final price2 = _parsePrice(service['price_2_persons']);
      final price12 = _parsePrice(service['price_1_2_persons']);
      if (price1 != null && price1 > 0) return price1;
      if (price2 != null && price2 > 0) return price2;
      if (price12 != null && price12 > 0) return price12;
    }

    // 4. MONTHLY SUBSCRIPTION - Check ALL price columns and return first valid price
    if (isMonthlySubscription) {
      // FIRST: Check monthly_plan_price (specific to monthly subscriptions)
      final monthlyPlanPrice = _parsePrice(service['monthly_plan_price']);
      if (monthlyPlanPrice != null && monthlyPlanPrice > 0) {
        print('Monthly Subscription $name: Using monthly_plan_price = $monthlyPlanPrice');
        return monthlyPlanPrice;
      }
      
      // Create a list of all price columns to check
      List<Map<String, dynamic>> priceChecks = [];
      
      // Add property-specific prices if property_type matches
      if (propertyType.isNotEmpty) {
        if (propertyType.contains('1') || propertyType.contains('1bhk')) {
          priceChecks.add({'key': 'price_1_bhk', 'priority': 1});
        }
        if (propertyType.contains('2') || propertyType.contains('2bhk')) {
          priceChecks.add({'key': 'price_2_bhk', 'priority': 1});
        }
        if (propertyType.contains('3') || propertyType.contains('3bhk')) {
          priceChecks.add({'key': 'price_3_bhk', 'priority': 1});
        }
        if (propertyType.contains('4') || propertyType.contains('4bhk')) {
          priceChecks.add({'key': 'price_4_bhk', 'priority': 1});
        }
      }
      
      // Add person count specific prices
      if (personsCount != null) {
        final count = personsCount is String ? int.tryParse(personsCount) : (personsCount is num ? personsCount.toInt() : null);
        if (count != null) {
          if (count == 1) priceChecks.add({'key': 'price_1_person', 'priority': 2});
          if (count == 2) priceChecks.add({'key': 'price_2_persons', 'priority': 2});
          if (count >= 1 && count <= 2) priceChecks.add({'key': 'price_1_2_persons', 'priority': 2});
          if (count >= 2 && count <= 5) priceChecks.add({'key': 'price_2_5_persons', 'priority': 2});
          if (count >= 5 && count <= 10) priceChecks.add({'key': 'price_5_10_persons', 'priority': 2});
          if (count > 10) priceChecks.add({'key': 'price_10_plus_persons', 'priority': 2});
        }
      }
      
      // Check service-specific prices
      if (isWashroomCleaning || name.contains('washroom')) {
        priceChecks.addAll([
          {'key': 'price_2_washroom', 'priority': 3},
          {'key': 'price_3_washroom', 'priority': 3},
          {'key': 'price_4_washroom', 'priority': 3},
          {'key': 'price_4_plus_washroom', 'priority': 3},
        ]);
      }
      
      if (isCooking || name.contains('chef') || name.contains('cooking')) {
        priceChecks.add({'key': 'cooking_price', 'priority': 4});
      }
      
      if (isHouseCleaning || isSuperCleaning || name.contains('cleaning')) {
        priceChecks.add({'key': 'cleaning_price', 'priority': 4});
      }
      
      // Sort by priority and check
      priceChecks.sort((a, b) => a['priority'].compareTo(b['priority']));
      for (var check in priceChecks) {
        final price = _parsePrice(service[check['key']]);
        if (price != null && price > 0) {
          print('Monthly Subscription $name: Using ${check['key']} = $price');
          return price;
        }
      }
      
      // Check ALL price columns systematically (fallback)
      final allPriceColumns = [
        'cleaning_price',
        'cooking_price',
        'price_1_bhk', 'price_2_bhk', 'price_3_bhk', 'price_4_bhk',
        'price_1_person', 'price_2_persons', 'price_1_2_persons',
        'price_2_5_persons', 'price_5_10_persons', 'price_10_plus_persons',
        'price_2_washroom', 'price_3_washroom', 'price_4_washroom', 'price_4_plus_washroom',
        'price', // Base price last
      ];
      
      for (var column in allPriceColumns) {
        final price = _parsePrice(service[column]);
        if (price != null && price > 0) {
          print('Monthly Subscription $name: Using $column = $price (fallback)');
          return price;
        }
      }
      
      // If all checks fail, return base price even if 0
      final basePrice = _parsePrice(service['price']);
      if (basePrice != null) {
        print('Monthly Subscription $name: Using base price = $basePrice');
        return basePrice;
      }
    }

    // 5. GENERIC CLEANING - Use cleaning_price or BHK prices
    final cleaningPrice = _parsePrice(service['cleaning_price']);
    if (cleaningPrice != null && cleaningPrice > 0) return cleaningPrice;

    // 6. FALLBACK - Check all person-based prices for any service
    if (personsCount != null) {
      final count = personsCount is String ? int.tryParse(personsCount) : (personsCount is num ? personsCount.toInt() : null);
      if (count != null) {
        if (count == 1) {
          final price1 = _parsePrice(service['price_1_person']);
          if (price1 != null && price1 > 0) return price1;
        } else if (count == 2) {
          final price2 = _parsePrice(service['price_2_persons']);
          if (price2 != null && price2 > 0) return price2;
        } else if (count >= 1 && count <= 2) {
          final price12 = _parsePrice(service['price_1_2_persons']);
          if (price12 != null && price12 > 0) return price12;
        } else if (count >= 2 && count <= 5) {
          final price25 = _parsePrice(service['price_2_5_persons']);
          if (price25 != null && price25 > 0) return price25;
        } else if (count >= 5 && count <= 10) {
          final price510 = _parsePrice(service['price_5_10_persons']);
          if (price510 != null && price510 > 0) return price510;
        } else if (count > 10) {
          final price10Plus = _parsePrice(service['price_10_plus_persons']);
          if (price10Plus != null && price10Plus > 0) return price10Plus;
        }
      }
    }

    // 7. FINAL FALLBACK - Use base price (ALWAYS show this)
    final basePrice = _parsePrice(service['price']);
    if (basePrice != null) return basePrice; // Return even if 0, to show it's from database

    return null;
  }

  String _resolveServiceImageUrl(String raw) {
    if (raw.isEmpty) return raw;
    String p = raw.trim();
    // Normalize slashes
    p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
    
    // Already absolute URL starting with https://superdailys.com/storage/services/
    if (p.startsWith('https://superdailys.com/storage/services/')) {
      return p;
    }
    
    // Handle URLs with superdailyapp/storage/services/ and convert to storage/services/
    if (p.contains('/superdailyapp/storage/services/')) {
      final filename = p.split('/').last.split('?').first.split('#').first;
      if (filename.isNotEmpty && filename.contains('.')) {
        return 'https://superdailys.com/storage/services/' + filename;
      }
    }
    
    // Handle Hostinger file server URLs - convert to regular domain (since those are failing)
    if (p.contains('srv1881-files.hstgr.io')) {
      final filename = p.split('/').last.split('?').first.split('#').first;
      if (filename.isNotEmpty && filename.contains('.')) {
        return 'https://superdailys.com/storage/services/' + filename;
      }
    }
    
    // Already absolute URL (any other URL)
    if (p.startsWith('http://') || p.startsWith('https://')) {
      // If it's a full URL but not from the storage/services path, try to extract filename
      if (!p.contains('/storage/services/')) {
        final filename = p.split('/').last.split('?').first.split('#').first;
        if (filename.isNotEmpty && filename.contains('.')) {
          return 'https://superdailys.com/storage/services/' + filename;
        }
      }
      return p;
    }
    
    // Extract just the filename from the path
    String filename = p.split('/').last.split('\\').last;
    // Remove query parameters and hash
    filename = filename.split('?').first.split('#').first;
    
    // If filename is empty or doesn't have extension, try to find it
    if (filename.isEmpty || !filename.contains('.')) {
      // Try to find filename in the path
      final parts = p.split('/');
      for (var part in parts.reversed) {
        if (part.contains('.') && part.length > 3) {
          filename = part.split('?').first.split('#').first;
          break;
        }
      }
    }
    
    // Build full URL - use same as monthly subscription (which works)
    if (filename.isNotEmpty && filename.contains('.')) {
      final url = 'https://superdailys.com/storage/services/' + filename;
      debugPrint('Resolved service image URL: $url');
      return url;
    }
    
    return '';
  }

  Widget _buildOneTimeServiceCard(Map<String, dynamic> service) {
    final name = service['name'] ?? 'Service';
    final description = service['description'] ?? '';
    
    // Collect all available service images (image, image_2, image_3, image_4)
    final List<String> serviceImages = [];
    debugPrint('🔍 Service "$name" - Checking for images...');
    debugPrint('   Raw service data - image: ${service['image']}, image_2: ${service['image_2']}, image_3: ${service['image_3']}, image_4: ${service['image_4']}');
    
    for (var imgKey in ['image', 'image_2', 'image_3', 'image_4']) {
      final imgValue = service[imgKey];
      debugPrint('   Checking $imgKey: ${imgValue != null ? imgValue.toString() : "null"}');
      
      if (imgValue != null && imgValue.toString().trim().isNotEmpty) {
        final rawUrl = imgValue.toString().trim();
        debugPrint('   Raw URL from $imgKey: $rawUrl');
        
        // If it's already a valid HTTPS URL starting with superdailys.com/storage/services/, use it directly
        if (rawUrl.startsWith('https://superdailys.com/storage/services/')) {
          serviceImages.add(rawUrl);
          debugPrint('✅ Service "$name" - Added direct URL from $imgKey: $rawUrl');
        } 
        // If it's any other HTTP/HTTPS URL, use it directly too
        else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
          serviceImages.add(rawUrl);
          debugPrint('✅ Service "$name" - Added direct URL from $imgKey: $rawUrl');
        } 
        // If it's just a filename or relative path, build the full URL
        else {
          // Extract filename from the path
          String filename = rawUrl.split('/').last.split('\\').last;
          filename = filename.split('?').first.split('#').first;
          
          // Build full URL
          if (filename.isNotEmpty && filename.contains('.')) {
            final fullUrl = 'https://superdailys.com/storage/services/' + filename;
            serviceImages.add(fullUrl);
            debugPrint('✅ Service "$name" - Built full URL from $imgKey: $fullUrl (from: $rawUrl)');
          } else {
            debugPrint('❌ Service "$name" - Invalid filename from $imgKey: $rawUrl');
          }
        }
      } else {
        debugPrint('   $imgKey is empty or null');
      }
    }
    
    debugPrint('📊 Service "$name" - Total images collected: ${serviceImages.length}');
    if (serviceImages.isEmpty) {
      debugPrint('⚠️ Service "$name" - NO IMAGES FOUND! Service keys: ${service.keys.toList()}');
    }
    
    final priceNumNullable = _getServicePrice(service);
    double finalPriceNum = (priceNumNullable ?? _parsePrice(service['price']) ?? 0.0);
    // Ensure finalPriceNum is always a valid double
    finalPriceNum = finalPriceNum.isNaN || finalPriceNum.isInfinite ? 0.0 : finalPriceNum;
    final priceNum = finalPriceNum;
    final discountPriceNum = _parsePrice(service['discount_price']);
    final finalDiscountPrice = (discountPriceNum != null && discountPriceNum > 0 && !discountPriceNum.isNaN && !discountPriceNum.isInfinite && finalPriceNum > 0 && discountPriceNum < finalPriceNum) ? discountPriceNum : null;
    final displayPrice = (finalDiscountPrice ?? finalPriceNum);
    // Ensure displayPrice is always a valid double
    final double safeDisplayPrice = displayPrice.isNaN || displayPrice.isInfinite ? 0.0 : displayPrice;
    final hasDiscount = finalDiscountPrice != null;

    final card = Container(
      width: 160,
      constraints: const BoxConstraints(maxWidth: 160),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 160,
          height: 130,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_tealLight, _tealLighter]),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: serviceImages.isNotEmpty
              ? ClipRRect(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  child: _ServiceImageWidget(
                    key: ValueKey('service_${service['id']}_${serviceImages.join('_')}'), // Unique key to force rebuild
                    imageUrls: serviceImages,
                    serviceName: name,
                  ),
                )
              : Container(
                  // Show debug info if no images
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.room_service, size: 40, color: Colors.grey.shade400),
                      if (service['image'] == null && service['image_2'] == null)
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Text(
                            'No images',
                            style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey.shade500),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            if (description.isNotEmpty)
              Text(description, style: GoogleFonts.poppins(fontSize: 8, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
              Flexible(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('₹' + safeDisplayPrice.toStringAsFixed(2), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: _priceDarkBlue), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (hasDiscount && priceNum > safeDisplayPrice)
                    Text('₹' + priceNum.toStringAsFixed(2), style: GoogleFonts.poppins(fontSize: 7, decoration: TextDecoration.lineThrough, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: 4),
              Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: _tealColor, borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.add, color: Colors.white, size: 12)),
            ]),
          ]),
        ),
      ]),
    );

    return GestureDetector(
      onTap: () {
        final dynamic rawId = service['id'];
        final int intId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '0') ?? 0;
        if (intId > 0) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => ServiceDetailsScreen(serviceId: intId)));
        }
      },
      child: card,
    );
  }

  Widget _buildProductCard(String name, String price, IconData icon, bool isFeatured) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
            border: isFeatured
            ? Border.all(color: _tealColor, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _tealLight,
                  _tealLighter,
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Center(
              child: Icon(icon, size: 60, color: _tealColor),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isFeatured)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _tealColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'FEATURED',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (isFeatured) const SizedBox(height: 8),
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      price,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _tealColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _tealColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCardFromData(Map<String, dynamic> product) {
    final sellingPrice = (product['selling_price'] ?? product['price'] ?? 0);
    final mrpPrice = (product['mrp_price'] ?? sellingPrice);
    
    // Get the first available image
    String? imageUrl;
    final images = [
      product['image'],
      product['image_2'],
      product['image_3'],
      product['image_4'],
    ];
    for (var img in images) {
      if (img != null && img.toString().trim().isNotEmpty) {
        imageUrl = _resolveImageUrl(img.toString());
        break;
      }
    }
    
    // Convert to numbers safely - handle null, string, and number types
    double sellingPriceNum = 0.0;
    if (sellingPrice != null) {
      if (sellingPrice is String) {
        sellingPriceNum = double.tryParse(sellingPrice) ?? 0.0;
      } else if (sellingPrice is num) {
        sellingPriceNum = sellingPrice.toDouble();
      }
    }
    
    double mrpPriceNum = sellingPriceNum;
    if (mrpPrice != null) {
      if (mrpPrice is String) {
        mrpPriceNum = double.tryParse(mrpPrice) ?? sellingPriceNum;
      } else if (mrpPrice is num) {
        mrpPriceNum = mrpPrice.toDouble();
      } else {
        mrpPriceNum = sellingPriceNum;
      }
    }
    
    final hasDiscount = mrpPriceNum > sellingPriceNum;
    final productName = product['name'] ?? 'Product';
    
    return GestureDetector(
      onTap: () {
        final productId = product['id'];
        if (productId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailsScreen(
                productId: productId is int ? productId : int.tryParse(productId.toString()) ?? 0,
              ),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Container(
                height: 150,
                width: double.infinity,
                color: _tealLight,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(_tealColor),
                          ),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Icon(Icons.shopping_bag, size: 40, color: _tealColor),
                        ),
                      )
                    : Center(
                        child: Icon(Icons.shopping_bag, size: 40, color: _tealColor),
                      ),
              ),
            ),
            // Product Details
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '₹${sellingPriceNum.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _priceDarkBlue,
                              ),
                            ),
                            if (hasDiscount)
                              Text(
                                '₹${mrpPriceNum.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _tealColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGridCard(String name, String price, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green.shade100,
                    Colors.green.shade50,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Center(
                child: Icon(icon, size: 50, color: _tealColor),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      price,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _tealColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _tealColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(String title, String description, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _tealLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 32, color: Colors.green.shade700),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
            Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
      ),
          Icon(Icons.arrow_forward_ios, size: 20, color: _tealColor),
        ],
      ),
    );
  }

  Widget _buildProfileMenuItem(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: _tealColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedProductCardHorizontal(Map<String, dynamic> product) {
    final sellingPrice = (product['selling_price'] ?? product['price'] ?? 0);
    final mrpPrice = (product['mrp_price'] ?? sellingPrice);
    final discountPercentage = (product['discount_percentage'] ?? 0);
    
    // Collect all available images for the product
    final List<String> images = [
      product['image'],
      product['image_2'],
      product['image_3'],
      product['image_4'],
    ]
        .where((img) => img != null && img.toString().trim().isNotEmpty)
        .map((img) => _resolveImageUrl(img.toString()))
        .toList();
    
    // Convert to numbers safely - handle null, string, and number types
    double sellingPriceNum = 0.0;
    if (sellingPrice != null) {
      if (sellingPrice is String) {
        sellingPriceNum = double.tryParse(sellingPrice) ?? 0.0;
      } else if (sellingPrice is num) {
        sellingPriceNum = sellingPrice.toDouble();
      }
    }
    
    double mrpPriceNum = sellingPriceNum;
    if (mrpPrice != null) {
      if (mrpPrice is String) {
        mrpPriceNum = double.tryParse(mrpPrice) ?? sellingPriceNum;
      } else if (mrpPrice is num) {
        mrpPriceNum = mrpPrice.toDouble();
      } else {
        mrpPriceNum = sellingPriceNum;
      }
    }
    
    double discountPercentageNum = 0.0;
    if (discountPercentage != null) {
      if (discountPercentage is String) {
        discountPercentageNum = double.tryParse(discountPercentage) ?? 0.0;
      } else if (discountPercentage is num) {
        discountPercentageNum = discountPercentage.toDouble();
      }
    }
    
    final hasDiscount = discountPercentageNum > 0 && mrpPriceNum > sellingPriceNum;
    
    return GestureDetector(
      onTap: () {
        final productId = product['id'];
        if (productId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailsScreen(
                productId: productId is int ? productId : int.tryParse(productId.toString()) ?? 0,
              ),
            ),
          );
        }
      },
      child: Container(
        width: 220,
        height: 280,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product Images (swipeable if multiple)
            Container(
              width: 220,
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _tealLight,
                    _tealLighter,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: images.isNotEmpty
                  ? ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      child: Stack(
                        children: [
                          PageView.builder(
                            itemCount: images.length,
                            itemBuilder: (context, index) {
                              final raw = images[index];
                              final base = _basename(raw);
                              final candidates = <String>[
                                raw,
                                'products/' + base,
                                'uploads/' + base,
                                'uploads/products/' + base,
                              ];
                              return FallbackImage(
                                urls: candidates,
                                fit: BoxFit.cover,
                                placeholder: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(_tealColor),
                                  ),
                                ),
                                error: Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 40,
                                    color: _tealColor,
                                  ),
                                ),
                              );
                            },
                          ),
                          // Small image count badge
                          if (images.length > 1)
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.45),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${images.length} images',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.inventory_2,
                        size: 50,
                        color: _tealColor,
                      ),
                    ),
            ),
            // Product Details - Flexible layout
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Brand Name
                  if (product['brand_name'] != null && product['brand_name'].toString().isNotEmpty)
                    Text(
                      product['brand_name'].toString().toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: _tealColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (product['brand_name'] != null && product['brand_name'].toString().isNotEmpty)
                    const SizedBox(height: 3),
                  // Product Name
                  Flexible(
                    child: Text(
                      product['name'] ?? 'Product',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Price Row
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      Text(
                        '₹${sellingPriceNum.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _priceDarkBlue,
                        ),
                      ),
                      if (hasDiscount)
            Text(
                          '₹${mrpPriceNum.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                  if (hasDiscount) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${discountPercentageNum.toStringAsFixed(0)}% OFF',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Stock and Add Button Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Stock Info
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                          decoration: BoxDecoration(
                            color: (product['stock_quantity'] ?? 0) > 0
                                ? _tealLight
                                : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (product['stock_quantity'] ?? 0) > 0
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                size: 11,
                                color: (product['stock_quantity'] ?? 0) > 0
                                    ? _tealColor
                                    : Colors.red.shade700,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  (product['stock_quantity'] ?? 0) > 0
                                      ? 'In Stock'
                                      : 'Out',
                                  style: GoogleFonts.poppins(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: (product['stock_quantity'] ?? 0) > 0
                                        ? _tealColor
                                        : Colors.red.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Add to Cart Button
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _tealColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.shopping_cart,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListItem(Map<String, dynamic> product) {
    try {
      // Collect all available images (image, image_2, image_3, image_4)
      final List<String> productImages = [];
      for (var imgKey in ['image', 'image_2', 'image_3', 'image_4']) {
        final imgValue = product[imgKey];
        if (imgValue != null && imgValue.toString().trim().isNotEmpty) {
          final resolvedUrl = _resolveImageUrl(imgValue.toString());
          if (resolvedUrl.isNotEmpty && resolvedUrl.startsWith('http')) {
            productImages.add(resolvedUrl);
            debugPrint('🖼️ Product "${product['name'] ?? 'Unknown'}" - Found image from $imgKey: $resolvedUrl');
          } else {
            debugPrint('⚠️ Product "${product['name'] ?? 'Unknown'}" - Invalid image URL from $imgKey: $imgValue -> resolved: $resolvedUrl');
          }
        }
      }
      
      // Use first available image, or null if none
      final productImage = productImages.isNotEmpty ? productImages[0] : null;
      
      if (productImage == null) {
        debugPrint('❌ Product "${product['name'] ?? 'Unknown'}" - No valid images found. Available keys: image=${product['image']}, image_2=${product['image_2']}, image_3=${product['image_3']}, image_4=${product['image_4']}');
      }
      
      // Helper function to safely parse numbers
      double parseNumber(dynamic value, [double defaultValue = 0.0]) {
        if (value == null) return defaultValue;
        if (value is double) return value.isNaN || value.isInfinite ? defaultValue : value;
        if (value is int) return value.toDouble();
        if (value is String) {
          final parsed = double.tryParse(value.trim());
          if (parsed != null && !parsed.isNaN && !parsed.isInfinite) return parsed;
        }
        return defaultValue;
      }
      
      // Helper function to safely parse integers (for stock_quantity)
      int parseInteger(dynamic value, [int defaultValue = 0]) {
        if (value == null) return defaultValue;
        if (value is int) return value;
        if (value is double) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null) return parsed;
        }
        return defaultValue;
      }
      
      // Parse prices with safe parsing
      final sellingPriceRaw = product['selling_price'] ?? product['price'] ?? 0;
      final mrpPriceRaw = product['mrp_price'] ?? sellingPriceRaw;
      final discountPercentageRaw = product['discount_percentage'] ?? 0;
      final stockQuantityRaw = product['stock_quantity'] ?? 0;
      
      double sellingPriceNum = parseNumber(sellingPriceRaw, 0.0);
      double mrpPriceNum = parseNumber(mrpPriceRaw, sellingPriceNum);
      double discountPercentageNum = parseNumber(discountPercentageRaw, 0.0);
      int stockQuantityNum = parseInteger(stockQuantityRaw, 0);
      
      // Ensure values are valid
      sellingPriceNum = sellingPriceNum.isNaN || sellingPriceNum.isInfinite ? 0.0 : sellingPriceNum;
      mrpPriceNum = mrpPriceNum.isNaN || mrpPriceNum.isInfinite ? sellingPriceNum : mrpPriceNum;
      discountPercentageNum = discountPercentageNum.isNaN || discountPercentageNum.isInfinite ? 0.0 : discountPercentageNum;
      
      final hasDiscount = mrpPriceNum > sellingPriceNum && sellingPriceNum > 0;
      
      return GestureDetector(
      onTap: () {
        final productId = product['id'];
        if (productId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailsScreen(
                productId: productId is int ? productId : int.tryParse(productId.toString()) ?? 0,
              ),
            ),
          );
        }
      },
      child: Container(
        width: 160,
        constraints: const BoxConstraints(maxWidth: 160),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product Image
            Container(
              width: 160,
              height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_tealLight, _tealLighter]),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              ),
              child: Stack(
                children: [
                  if (productImages.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                      child: SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: _ProductImageWidget(
                          imageUrls: productImages,
                          productName: product['name'] ?? 'Unknown',
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      child: Center(
                        child: Icon(Icons.inventory_2, color: _tealColor, size: 32),
                      ),
                    ),
                  // Show indicator if there are multiple images
                  if (productImages.length > 1)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library, size: 10, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '${productImages.length}',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Product Details
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product Name
                  Text(
                    product['name'] ?? 'Product',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // Brand Name (smaller)
                  if (product['brand_name'] != null && product['brand_name'].toString().isNotEmpty)
                    Text(
                      product['brand_name'].toString(),
                      style: GoogleFonts.poppins(
                        fontSize: 8,
                        color: _tealColor,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (product['brand_name'] != null && product['brand_name'].toString().isNotEmpty)
                    const SizedBox(height: 2),
                  // Price Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '₹${sellingPriceNum.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _priceDarkBlue,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (hasDiscount)
                              Text(
                                '₹${mrpPriceNum.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 7,
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey.shade500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _tealColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    } catch (e, stackTrace) {
      print('❌ Error in _buildProductListItem: $e');
      print('📋 Stack trace: $stackTrace');
      print('📦 Product data: $product');
      // Return error widget instead of crashing
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Error loading product: ${product['name'] ?? 'Unknown'}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Error: ${e.toString()}',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.red.shade600,
              ),
            ),
          ],
        ),
      );
    }
  }
}

// Widget for service details image with proxy fallback
class _ServiceDetailsImageWidget extends StatefulWidget {
  final String imageUrl;
  final String serviceName;

  const _ServiceDetailsImageWidget({
    required this.imageUrl,
    required this.serviceName,
  });

  @override
  State<_ServiceDetailsImageWidget> createState() => _ServiceDetailsImageWidgetState();
}

class _ServiceDetailsImageWidgetState extends State<_ServiceDetailsImageWidget> {
  int _currentUrlIndex = 0; // 0 = primary URL, 1 = fallback URL, 2 = proxy
  bool _hasError = false;

  String _getFallbackUrl(String originalUrl) {
    // Try to convert to fallback URL format
    // If it's from Hostinger file server, try superdailys.com
    if (originalUrl.contains('srv1881-files.hstgr.io')) {
      final filename = originalUrl.split('/').last.split('?').first.split('#').first;
      return 'https://superdailys.com/storage/services/' + filename;
    }
    // If it's from superdailys.com, try Hostinger file server
    if (originalUrl.contains('superdailys.com/storage/services/')) {
      final filename = originalUrl.split('/').last.split('?').first.split('#').first;
      return 'https://srv1881-files.hstgr.io/4663f5e73332121d/files/public_html/public/storage/services/' + filename;
    }
    return originalUrl;
  }

  String _getProxiedUrl(String url) {
    final encodedUrl = Uri.encodeComponent(url);
    return 'https://superdailys.com/superdailyapp/proxy_image.php?url=$encodedUrl';
  }

  String _getCurrentImageUrl() {
    // 0 = primary URL (from API)
    if (_currentUrlIndex == 0) {
      return widget.imageUrl;
    }
    // 1 = fallback URL (alternative server)
    if (_currentUrlIndex == 1) {
      return _getFallbackUrl(widget.imageUrl);
    }
    // 2 = proxy
    if (_currentUrlIndex == 2) {
      return _getProxiedUrl(widget.imageUrl);
    }
    return widget.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.grey.shade100,
        child: Center(
          child: Icon(
            Icons.image_not_supported,
            size: 64,
            color: Colors.grey.shade400,
          ),
        ),
      );
    }

    final imageUrl = _getCurrentImageUrl();
    final urlType = ['primary', 'fallback', 'proxy'][_currentUrlIndex];
    debugPrint('🖼️ Service Details - Trying to load image ($urlType) for "${widget.serviceName}": $imageUrl');

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      httpHeaders: {
        'Accept': 'image/*',
      },
      placeholder: (context, url) => Container(
        color: Colors.grey.shade100,
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
          ),
        ),
      ),
      errorWidget: (context, url, error) {
        final urlType = ['primary', 'fallback', 'proxy'][_currentUrlIndex];
        debugPrint('❌ Service Details - Image failed to load ($urlType) for "${widget.serviceName}": $url');
        debugPrint('   Error type: ${error.runtimeType}');
        debugPrint('   Error: $error');
        
        // Try fallback URL (alternative server)
        if (_currentUrlIndex == 0) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _currentUrlIndex = 1; // Try fallback URL
              });
            }
          });
          return Container(
            color: Colors.grey.shade100,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
            ),
          );
        }
        
        // Try proxy if fallback URL also failed
        if (_currentUrlIndex == 1) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _currentUrlIndex = 2; // Try proxy
              });
            }
          });
          return Container(
            color: Colors.grey.shade100,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
            ),
          );
        }
        
        // All URLs failed
        Future.microtask(() {
          if (mounted) {
            setState(() {
              _hasError = true;
            });
          }
        });
        return Container(
          color: Colors.grey.shade100,
          child: Center(
            child: Icon(
              Icons.image_not_supported,
              size: 64,
              color: Colors.grey.shade400,
            ),
          ),
        );
      },
    );
  }
}

class AllServicesScreen extends StatefulWidget {
  const AllServicesScreen({super.key});

  @override
  State<AllServicesScreen> createState() => _AllServicesScreenState();
}

class _AllServicesScreenState extends State<AllServicesScreen> {
  List<dynamic> _services = [];
  bool _isLoading = true;
  static const Color _tealColor = Color(0xFF00BFA5);
  static const Color _priceDarkBlue = Color(0xFF0D47A1);

  @override
  void initState() {
    super.initState();
    _fetchNonFeaturedServices();
  }

  Future<void> _fetchNonFeaturedServices() async {
    try {
      const String apiUrl = 'https://superdailys.com/superdailyapp/get_non_featured_services.php';
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final services = data['services'] ?? [];
            setState(() {
              _services = services;
              _isLoading = false;
            });
          } else {
            setState(() {
              _services = [];
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _services = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error fetching non-featured services: $e');
        setState(() {
          _services = [];
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final name = service['name'] ?? 'Service';
    final description = service['description'] ?? '';
    final List<String> serviceImages = [];
    
    for (var imgKey in ['image', 'image_2', 'image_3', 'image_4']) {
      final imgValue = service[imgKey];
      if (imgValue != null && imgValue.toString().trim().isNotEmpty) {
        final rawUrl = imgValue.toString().trim();
        if (rawUrl.startsWith('https://superdailys.com/storage/services/')) {
          serviceImages.add(rawUrl);
        } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
          serviceImages.add(rawUrl);
        } else {
          String filename = rawUrl.split('/').last.split('\\').last;
          filename = filename.split('?').first.split('#').first;
          if (filename.isNotEmpty && filename.contains('.')) {
            serviceImages.add('https://superdailys.com/storage/services/' + filename);
          }
        }
      }
    }
    
    final priceNum = _parsePrice(service['price']) ?? 0.0;
    final discountPriceNum = _parsePrice(service['discount_price']);
    final displayPrice = discountPriceNum ?? priceNum;
    final hasDiscount = discountPriceNum != null && discountPriceNum > 0 && discountPriceNum < priceNum;

    return GestureDetector(
      onTap: () {
        final dynamic rawId = service['id'];
        final int intId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '0') ?? 0;
        if (intId > 0) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ServiceDetailsScreen(serviceId: intId),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: serviceImages.isNotEmpty
                  ? ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: serviceImages.first,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(_tealColor),
                          ),
                        ),
                        errorWidget: (context, url, error) => Icon(
                          Icons.room_service,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.room_service,
                      size: 40,
                      color: Colors.grey.shade400,
                    ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '₹${displayPrice.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _priceDarkBlue,
                              ),
                            ),
                            if (hasDiscount)
                              Text(
                                '₹${priceNum.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _tealColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double? _parsePrice(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
      final parsed = double.tryParse(cleaned);
      return parsed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'All Services',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: _tealColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
            )
          : _services.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.room_service_outlined,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No services available',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchNonFeaturedServices,
                  color: _tealColor,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _services.map((service) => _buildServiceCard(service)).toList(),
                  ),
                ),
    );
  }
}

class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({super.key});

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  String _step = 'phone'; // 'phone', 'otp', 'reset'
  bool _isLoading = false;
  String? _otpSentPhone;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final response = await http.post(
          Uri.parse('${kBackendBaseUrl}generate_otp.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': _phoneController.text.trim(),
          }),
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            setState(() {
              _step = 'otp';
              _otpSentPhone = _phoneController.text.trim();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'OTP sent successfully'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Failed to send OTP'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _verifyOTP() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final response = await http.post(
          Uri.parse('${kBackendBaseUrl}verify_otp.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': _otpSentPhone,
            'otp': _otpController.text.trim(),
          }),
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            setState(() {
              _step = 'reset';
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Invalid OTP'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _verifyOTPAndReset() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final response = await http.post(
          Uri.parse('${kBackendBaseUrl}reset_password.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': _otpSentPhone,
            'otp': _otpController.text.trim(),
            'new_password': _newPasswordController.text,
            'confirm_password': _confirmPasswordController.text,
          }),
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Password reset successfully'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Failed to reset password'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    if (value.length < 10) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  String? _validateOTP(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter OTP';
    }
    if (value.length != 6) {
      return 'OTP must be 6 digits';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter new password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm password';
    }
    if (value != _newPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _step == 'phone' 
                          ? 'Forgot Password'
                          : _step == 'otp'
                              ? 'Verify OTP'
                              : 'Reset Password',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                if (_step == 'phone') ...[
                  Text(
                    'Enter your phone number to receive OTP',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'Enter 10 digits (e.g., 9876543210)',
                      helperText: 'Must be exactly 10 digits',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: _validatePhone,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _sendOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Send OTP',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ] else if (_step == 'otp') ...[
                  Text(
                    'Enter the OTP sent to ${_otpSentPhone}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'OTP',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: _validateOTP,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _step = 'phone'),
                        child: Text(
                          'Change Phone',
                          style: GoogleFonts.poppins(color: const Color(0xFF00BFA5)),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _isLoading ? null : _sendOTP,
                        child: Text(
                          'Resend OTP',
                          style: GoogleFonts.poppins(color: const Color(0xFF00BFA5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Verify OTP',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ] else if (_step == 'reset') ...[
                  Text(
                    'Enter your new password',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: _obscureNewPassword,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNewPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscureNewPassword = !_obscureNewPassword);
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: _validateConfirmPassword,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTPAndReset,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Reset Password',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BookingDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> booking;

  const BookingDetailsScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    // Debug: Print booking data to see what we're receiving
    print('🔍 Booking Details - maid_id: ${booking['maid_id']}');
    print('🔍 Booking Details - maid_info: ${booking['maid_info']}');
    
    final maidInfo = booking['maid_info'];
    final bookingDate = booking['booking_date'] ?? '';
    final bookingTime = booking['booking_time'] ?? '';
    final status = booking['status'] ?? 'pending';
    final paymentStatus = booking['payment_status'] ?? 'pending';
    final finalAmount = double.tryParse(booking['final_amount']?.toString() ?? '0') ?? 0.0;
    final address = booking['address'] ?? 'No address';
    final phone = booking['phone'] ?? '';
    final serviceId = booking['service_id'];
    final bookingRef = booking['booking_reference'] ?? 'N/A';
    final assignedAt = booking['assigned_at'];
    final assignedBy = booking['assigned_by'];
    final assignmentNotes = booking['assignment_notes'];
    final specialInstructions = booking['special_instructions'] ?? '';
    final durationHours = booking['duration_hours'];
    final totalAmount = double.tryParse(booking['total_amount']?.toString() ?? '0') ?? 0.0;
    final discountAmount = double.tryParse(booking['discount_amount']?.toString() ?? '0') ?? 0.0;
    final paymentMethod = booking['payment_method'];
    final paymentId = booking['payment_id'];
    final transactionId = booking['transaction_id'];
    final paymentCompletedAt = booking['payment_completed_at'];
    final customerNotes = booking['customer_notes'];
    final maidNotes = booking['maid_notes'];
    final confirmedAt = booking['confirmed_at'];
    final startedAt = booking['started_at'];
    final completedAt = booking['completed_at'];
    final cancelledAt = booking['cancelled_at'];
    final createdAt = booking['created_at'];
    final serviceRequirements = booking['service_requirements'] ?? '';

    // Status colors
    Color statusColor;
    String statusText;
    switch (status.toLowerCase()) {
      case 'confirmed':
        statusColor = Colors.green;
        statusText = 'Confirmed';
        break;
      case 'completed':
        statusColor = Colors.blue;
        statusText = 'Completed';
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusText = 'Cancelled';
        break;
      case 'in_progress':
      case 'started':
        statusColor = Colors.orange;
        statusText = 'In Progress';
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Pending';
    }

    // Payment status colors
    Color paymentColor;
    String paymentText;
    switch (paymentStatus.toLowerCase()) {
      case 'paid':
      case 'completed':
        paymentColor = Colors.green;
        paymentText = 'Paid';
        break;
      case 'failed':
        paymentColor = Colors.red;
        paymentText = 'Failed';
        break;
      case 'pending':
      default:
        paymentColor = Colors.orange;
        paymentText = 'Pending';
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Booking Details',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF00BFA5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Booking Reference and Status Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Booking Reference',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                bookingRef,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusText,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: paymentColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                paymentText,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: paymentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Booking Information
            _buildSectionTitle('Booking Information'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Service ID', serviceId?.toString() ?? 'N/A'),
                    if (bookingDate.isNotEmpty)
                      _buildDetailRow('Date', bookingDate),
                    if (bookingTime.isNotEmpty)
                      _buildDetailRow('Time', bookingTime),
                    if (durationHours != null)
                      _buildDetailRow('Duration', '${durationHours} hours'),
                    _buildDetailRow('Address', address),
                    if (phone.isNotEmpty)
                      _buildDetailRow('Phone', phone),
                    if (specialInstructions.isNotEmpty) ...[
                      const Divider(height: 24),
                      _buildDetailRow('Special Instructions', specialInstructions, isMultiline: true),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Payment Information
            _buildSectionTitle('Payment Information'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (totalAmount > 0)
                      _buildDetailRow('Total Amount', '₹${totalAmount.toStringAsFixed(2)}'),
                    if (discountAmount > 0)
                      _buildDetailRow('Discount', '₹${discountAmount.toStringAsFixed(2)}'),
                    const Divider(height: 24),
                    _buildDetailRow('Final Amount', '₹${finalAmount.toStringAsFixed(2)}', isBold: true),
                    if (paymentMethod != null && paymentMethod.toString().isNotEmpty)
                      _buildDetailRow('Payment Method', paymentMethod.toString()),
                    if (paymentId != null && paymentId.toString().isNotEmpty)
                      _buildDetailRow('Payment ID', paymentId.toString()),
                    if (transactionId != null && transactionId.toString().isNotEmpty)
                      _buildDetailRow('Transaction ID', transactionId.toString()),
                    if (paymentCompletedAt != null && paymentCompletedAt.toString().isNotEmpty)
                      _buildDetailRow('Paid At', paymentCompletedAt.toString()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Maid Assignment Information - Always show this section
            _buildSectionTitle('Maid Assignment'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (maidInfo != null && maidInfo is Map) ...[
                      _buildDetailRow('Maid ID', booking['maid_id']?.toString() ?? 'N/A'),
                      _buildDetailRow('Maid Name', maidInfo['name'] ?? 'N/A'),
                      if (maidInfo['phone'] != null && maidInfo['phone'].toString().isNotEmpty)
                        _buildDetailRow('Maid Phone', maidInfo['phone'].toString()),
                      if (maidInfo['email'] != null && maidInfo['email'].toString().isNotEmpty)
                        _buildDetailRow('Maid Email', maidInfo['email'].toString()),
                    ] else if (booking['maid_id'] != null && booking['maid_id'].toString().isNotEmpty) ...[
                      // Has maid_id but no maid_info - might be data issue
                      _buildDetailRow('Maid ID', booking['maid_id'].toString()),
                      Text(
                        'Maid information not available',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Maid not yet assigned',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (assignedAt != null && assignedAt.toString().isNotEmpty) ...[
                      if (maidInfo != null || (booking['maid_id'] != null && booking['maid_id'].toString().isNotEmpty))
                        const Divider(height: 24),
                      _buildDetailRow('Assigned At', assignedAt.toString()),
                    ],
                    if (assignedBy != null && assignedBy.toString().isNotEmpty) ...[
                      if (assignedAt != null && assignedAt.toString().isNotEmpty) const SizedBox(height: 12),
                      _buildDetailRow('Assigned By', assignedBy.toString()),
                    ],
                    if (assignmentNotes != null && assignmentNotes.toString().isNotEmpty) ...[
                      if (assignedAt != null || assignedBy != null) const Divider(height: 24),
                      _buildDetailRow('Assignment Notes', assignmentNotes.toString(), isMultiline: true),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Booking Timeline
            _buildSectionTitle('Booking Timeline'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (createdAt != null && createdAt.toString().isNotEmpty)
                      _buildDetailRow('Created At', createdAt.toString()),
                    if (confirmedAt != null && confirmedAt.toString().isNotEmpty)
                      _buildDetailRow('Confirmed At', confirmedAt.toString()),
                    if (startedAt != null && startedAt.toString().isNotEmpty)
                      _buildDetailRow('Started At', startedAt.toString()),
                    if (completedAt != null && completedAt.toString().isNotEmpty)
                      _buildDetailRow('Completed At', completedAt.toString()),
                    if (cancelledAt != null && cancelledAt.toString().isNotEmpty)
                      _buildDetailRow('Cancelled At', cancelledAt.toString(), textColor: Colors.red),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Additional Notes
            if (customerNotes != null || maidNotes != null || serviceRequirements.isNotEmpty) ...[
              _buildSectionTitle('Additional Information'),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (serviceRequirements.isNotEmpty) ...[
                        Text(
                          'Service Requirements',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _cleanText(serviceRequirements),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (customerNotes != null && customerNotes.toString().isNotEmpty) ...[
                        if (serviceRequirements.isNotEmpty) const SizedBox(height: 16),
                        Text(
                          'Customer Notes',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _cleanText(customerNotes.toString()),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (maidNotes != null && maidNotes.toString().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Maid Notes',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _cleanText(maidNotes.toString()),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  // Helper function to clean and format text with special characters
  String _cleanText(String text) {
    if (text.isEmpty) return text;
    
    // Convert to string and trim
    String cleaned = text.toString().trim();
    
    // Decode Unicode escape sequences first (like \u2019)
    try {
      // Handle \uXXXX Unicode escapes
      cleaned = cleaned.replaceAllMapped(
        RegExp(r'\\u([0-9a-fA-F]{4})'),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
      );
    } catch (e) {
      // If parsing fails, continue with other cleaning
    }
    
    // Decode HTML entities if any
    cleaned = cleaned
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/');
    
    // Handle escaped quotes and newlines
    cleaned = cleaned
        .replaceAll('\\"', '"')
        .replaceAll("\\'", "'")
        .replaceAll('\\n', '\n')
        .replaceAll('\\r\\n', '\n')
        .replaceAll('\\r', '\n')
        .replaceAll('\\t', '\t')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    
    // Remove unwanted quotes around individual words/phrases (like "word" -> word)
    // This handles cases where quotes were added incorrectly
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'"([^"]+)"'),
      (match) {
        String content = match.group(1)!;
        // Only remove quotes if they seem to be around single words or short phrases
        // and not part of proper quoted text
        if (content.length < 50 && !content.contains('\n')) {
          return content;
        }
        return match.group(0)!; // Keep original if it's likely intentional quoting
      },
    );
    
    // Remove multiple consecutive newlines (more than 2)
    while (cleaned.contains('\n\n\n')) {
      cleaned = cleaned.replaceAll('\n\n\n', '\n\n');
    }
    
    // Trim each line and remove trailing whitespace
    List<String> lines = cleaned.split('\n');
    lines = lines.map((line) => line.trimRight()).toList();
    cleaned = lines.join('\n').trim();
    
    return cleaned;
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, bool isMultiline = false, Color? textColor}) {
    // Clean the value text if it's multiline
    String displayValue = isMultiline ? _cleanText(value) : value;
    
    return Padding(
      padding: EdgeInsets.only(bottom: isMultiline ? 12 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            displayValue,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: textColor ?? Colors.grey.shade900,
              height: isMultiline ? 1.5 : null,
            ),
            maxLines: isMultiline ? null : 2,
            overflow: isMultiline ? null : TextOverflow.ellipsis,
          ),
          if (!isMultiline) const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class ServiceDetailsScreen extends StatefulWidget {
  final int serviceId;
  const ServiceDetailsScreen({super.key, required this.serviceId});

  @override
  State<ServiceDetailsScreen> createState() => _ServiceDetailsScreenState();
}

class _ServiceDetailsScreenState extends State<ServiceDetailsScreen> {
  Map<String, dynamic>? _service;
  bool _loading = true;
  late PageController _imgCtrl;
  int _imgIndex = 0;
  Razorpay? _razorpay;
  Map<String, dynamic>? _pendingBookingPayload;
  bool _isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    _imgCtrl = PageController();
    // Initialize Razorpay only for mobile platforms (Android/iOS)
    if (!kIsWeb) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    }
    _fetch();
  }

  @override
  void dispose() {
    _imgCtrl.dispose();
    if (!kIsWeb && _razorpay != null) {
      _razorpay!.clear();
    }
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (_pendingBookingPayload != null) {
      // Update payload with payment details
      _pendingBookingPayload!['payment_status'] = 'paid';
      _pendingBookingPayload!['payment_method'] = 'razorpay';
      _pendingBookingPayload!['payment_id'] = response.paymentId;
      _pendingBookingPayload!['transaction_id'] = response.orderId ?? response.paymentId;
      _pendingBookingPayload!['payment_completed_at'] = DateTime.now().toIso8601String();
      
      // Submit booking with payment details
      _submitBooking(_pendingBookingPayload!).then((success) {
        if (mounted) {
          setState(() {
            _isProcessingPayment = false;
            _pendingBookingPayload = null;
          });
          if (success) {
            Navigator.of(context).pop(); // Close booking sheet if open
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment successful! Booking confirmed.'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment successful but booking creation failed. Please contact support.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      });
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() {
        _isProcessingPayment = false;
        _pendingBookingPayload = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: ${response.message ?? "Unknown error"}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External wallet selected: ${response.walletName}'),
        ),
      );
    }
  }

  Future<void> _initiateRazorpayPayment(double amount, Map<String, dynamic> bookingPayload) async {
    try {
      setState(() {
        _isProcessingPayment = true;
        _pendingBookingPayload = bookingPayload;
      });

      final options = {
        'key': kRazorpayKeyId,
        'amount': (amount * 100).toInt(), // Amount in paise
        'name': 'Super Daily',
        'description': 'Monthly Subscription Service',
        'prefill': {
          'contact': bookingPayload['phone'] ?? '',
          'email': '', // You can add email to booking payload if available
        },
        'external': {
          'wallets': ['paytm']
        },
        'handler': (response) {
          // This will be handled by platform-specific code
        }
      };

      if (kIsWeb) {
        // Use Razorpay JavaScript SDK for web
        await _initiateRazorpayWeb(options, amount, bookingPayload);
      } else {
        // Use Razorpay Flutter SDK for mobile
        if (_razorpay != null) {
          _razorpay!.open(options);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _pendingBookingPayload = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initiating payment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initiateRazorpayWeb(Map<String, dynamic> options, double amount, Map<String, dynamic> bookingPayload) async {
    // For web, we need to use JavaScript interop to call Razorpay Checkout
    // Since dart:html/js interop requires additional setup, we'll use a simpler approach
    try {
      // Create a script element to initialize Razorpay
      final phone = bookingPayload['phone'] ?? '';
      
      // Use dart:js_interop or create an HTML file that handles payment
      // For now, show a message and allow direct booking for web
      if (mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Payment Required'),
            content: Text(
              'Monthly subscription requires payment of ₹${amount.toStringAsFixed(2)}.\n\n'
              'For web payments, Razorpay integration requires server-side order creation.\n\n'
              'Would you like to proceed with booking confirmation? (Payment can be completed later)',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        
        if (confirm == true) {
          // Submit booking with pending payment status for web
          bookingPayload['payment_status'] = 'pending';
          bookingPayload['payment_method'] = 'razorpay_web';
          final success = await _submitBooking(bookingPayload);
          if (mounted) {
            setState(() {
              _isProcessingPayment = false;
              _pendingBookingPayload = null;
            });
            if (success) {
              Navigator.of(context).pop(); // Close booking sheet if open
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Booking created. Please complete payment via mobile app or contact support.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
            }
          }
        } else {
          setState(() {
            _isProcessingPayment = false;
            _pendingBookingPayload = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Web payment error: $e');
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _pendingBookingPayload = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment initialization failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetch() async {
    try {
      final uri = Uri.parse('https://superdailys.com/superdailyapp/get_service_details.php?id=' + widget.serviceId.toString());
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (mounted) {
          setState(() {
            _service = data['service'];
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() { _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF00BFA5);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        title: const Text('Service Details'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _service == null
              ? const Center(child: Text('Service not found'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildImages(),
                      const SizedBox(height: 12),
                      _buildBadges(),
                      const SizedBox(height: 16),
                      Text(
                        (_service!['name'] ?? '').toString(),
                        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.grey.shade900),
                      ),
                      const SizedBox(height: 8),
                      _buildPriceBlock(),
                      const SizedBox(height: 12),
                      _buildBookingNotice(primary),
                      const SizedBox(height: 16),
                      _buildOptionsSection(),
                      const SizedBox(height: 12),
                      if ((_service!['description'] ?? '').toString().isNotEmpty)
                        _buildTitledBox('Description', (_service!['description'] ?? '').toString()),
                      // Information section hidden as requested
                      if ((_service!['features'] ?? '').toString().isNotEmpty)
                        _buildBulletedBox('Features', (_service!['features'] ?? '').toString()),
                      if ((_service!['requirements'] ?? '').toString().isNotEmpty)
                        _buildRequirementsBox((_service!['requirements'] ?? '').toString()),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
      bottomNavigationBar: _service == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                  child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () { _openBookingSheet(); },
                    child: const Text('Book Now'),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBadges() {
    final mainCat = (_service!['main_category'] ?? '').toString();
    final subCat = (_service!['subcategory'] ?? '').toString();
    final isFeatured = ((_service!['is_featured'] ?? 0).toString() == '1');
    List<Widget> chips = [];
    if (mainCat.isNotEmpty) chips.add(_pill(mainCat));
    if (subCat.isNotEmpty) chips.add(_pill(subCat));
    if (isFeatured) chips.add(_pill('Featured', color: Colors.orange));
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _pill(String text, {Color color = const Color(0xFF00BFA5)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(24), border: Border.all(color: color.withOpacity(0.4))),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: _darken(color))),
    );
  }

  Color _darken(Color c, [double amount = 0.2]) {
    final hsl = HSLColor.fromColor(c);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }

  Widget _buildBookingNotice(Color primary) {
    final hrs = (_service!['booking_advance_hours'] ?? '').toString();
    if (hrs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: primary.withOpacity(0.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: primary),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(style: GoogleFonts.poppins(color: Colors.grey.shade800, fontSize: 13), children: [
              const TextSpan(text: 'Booking Notice Required\n', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: 'Please book this service at least '),
              TextSpan(text: hrs + ' hours ', style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: 'in advance.'),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildOptionsSection() {
    final Map<String, double> options = {};
    void addOpt(String label, dynamic v) {
      final d = _parsePriceForDetails(v);
      if (d != null && d > 0) options[label] = d;
    }
    addOpt('1 BHK', _service!['price_1_bhk']);
    addOpt('2 BHK', _service!['price_2_bhk']);
    addOpt('3 BHK', _service!['price_3_bhk']);
    addOpt('4 BHK', _service!['price_4_bhk']);
    addOpt('2 Washrooms', _service!['price_2_washroom']);
    addOpt('3 Washrooms', _service!['price_3_washroom']);
    addOpt('4 Washrooms', _service!['price_4_washroom']);
    addOpt('4+ Washrooms', _service!['price_4_plus_washroom']);
    addOpt('1 Person', _service!['price_1_person']);
    addOpt('2 Persons', _service!['price_2_persons']);
    addOpt('1-2 Persons', _service!['price_1_2_persons']);
    addOpt('2-5 Persons', _service!['price_2_5_persons']);
    addOpt('5-10 Persons', _service!['price_5_10_persons']);
    addOpt('10+ Persons', _service!['price_10_plus_persons']);
    addOpt('Cooking', _service!['cooking_price']);
    addOpt('Cleaning', _service!['cleaning_price']);

    if (options.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Please Select Your Option:', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: options.entries.map((e) => _optionCard(e.key, e.value)).toList(),
      ),
    ]);
  }

  double? _parsePriceForDetails(dynamic priceValue) {
    if (priceValue == null || priceValue == '' || priceValue == 'null') return null;
    if (priceValue is String) {
      String s = priceValue.trim();
      s = s.replaceAll(RegExp(r'[₹$,]'), '');
      s = s.replaceAll(RegExp(r'[^0-9\.-]'), '');
      final firstDot = s.indexOf('.');
      if (firstDot != -1) {
        final before = s.substring(0, firstDot + 1);
        final after = s.substring(firstDot + 1).replaceAll('.', '');
        s = before + after;
      }
      if (s.isEmpty || s == '-' || s == '.') return null;
      return double.tryParse(s);
    } else if (priceValue is num) {
      return priceValue.toDouble();
    }
    return null;
  }

  Widget _optionCard(String label, double price) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Text('₹' + price.toStringAsFixed(2), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0D47A1))),
      ]),
    );
  }

  Widget _buildBulletedBox(String title, String text) {
    final items = _formatBullets(text);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade900)),
        const SizedBox(height: 8),
        ...items.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.check_circle, size: 12, color: Color(0xFF00BFA5))),
            const SizedBox(width: 8),
            Expanded(child: Text(s, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade800, height: 1.5))),
          ]),
        )),
      ]),
    );
  }

  Widget _buildRequirementsBox(String text) {
    final items = _formatBullets(text);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Requirements',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.info,
                      size: 12,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openBookingSheet() async {
    DateTime? preferredDate;
    TimeOfDay? preferredTime;
    final locationCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? selectedPriceKey;
    double selectedPriceValue = 0.0;
    
    // Map state variables
    GoogleMapController? mapController;
    LatLng? selectedLocation;
    Set<Marker> mapMarkers = {};
    List<Map<String, dynamic>> autocompleteSuggestions = [];
    bool isLoadingSuggestions = false;
    bool isMapInitialized = false;
    
    // Service location and distance calculation
    double? serviceLat = _service?['service_latitude'] != null ? double.tryParse(_service!['service_latitude'].toString()) : null;
    double? serviceLng = _service?['service_longitude'] != null ? double.tryParse(_service!['service_longitude'].toString()) : null;
    double? distanceInMeters;
    bool isServiceAvailable = false;
    
    // Initialize service location marker if available
    if (serviceLat != null && serviceLng != null) {
      mapMarkers.add(
        Marker(
          markerId: const MarkerId('service_location'),
          position: LatLng(serviceLat!, serviceLng!),
          infoWindow: const InfoWindow(title: 'Service Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    Map<String, double> personPrices = _extractPersonPrices(_service!);
    Map<String, double> bhkPrices = _extractBhkPrices(_service!);
    final double? monthlyPrice = _extractMonthlyPrice(_service!);

    // Preselect a price if only one option exists; if none, fall back to base service price
    final Map<String, double> allOptions = {}..addAll(personPrices)..addAll(bhkPrices);
    if (monthlyPrice != null && monthlyPrice > 0) {
      allOptions['Monthly Subscription'] = monthlyPrice;
    }
    if (allOptions.length == 1) {
      selectedPriceKey = allOptions.keys.first;
      selectedPriceValue = allOptions.values.first;
    } else if (allOptions.isEmpty) {
      final base = _fallbackBasePrice(_service!);
      if (base != null) {
        selectedPriceKey = 'Base Price';
        selectedPriceValue = base;
      }
    }

    void setSelected(String key, double value, void Function(void Function()) setModalState) {
      setModalState(() { selectedPriceKey = key; selectedPriceValue = value; });
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          // Function to fetch autocomplete suggestions
          Future<void> fetchAutocompleteSuggestions(String query) async {
            if (query.trim().isEmpty) {
              setModalState(() {
                autocompleteSuggestions = [];
              });
              return;
            }
            
            setModalState(() {
              isLoadingSuggestions = true;
            });
            
            try {
              final url = Uri.parse('https://superdailys.com/superdailyapp/places_autocomplete.php?input=' + Uri.encodeComponent(query));
              final response = await http.get(url);
              
              if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                final predictions = data['predictions'] ?? [];
                setModalState(() {
                  autocompleteSuggestions = List<Map<String, dynamic>>.from(predictions);
                  isLoadingSuggestions = false;
                });
              } else {
                setModalState(() {
                  autocompleteSuggestions = [];
                  isLoadingSuggestions = false;
                });
              }
            } catch (e) {
              setModalState(() {
                autocompleteSuggestions = [];
                isLoadingSuggestions = false;
              });
            }
          }
          
          // Function to calculate distance and availability
          void calculateDistanceAndAvailability(LatLng bookingLocation) {
            if (serviceLat == null || serviceLng == null) {
              setModalState(() {
                distanceInMeters = null;
                isServiceAvailable = false;
              });
              return;
            }
            
            // Calculate distance in meters using Geolocator
            final distance = Geolocator.distanceBetween(
              serviceLat!,
              serviceLng!,
              bookingLocation.latitude,
              bookingLocation.longitude,
            );
            
            setModalState(() {
              distanceInMeters = distance;
              isServiceAvailable = distance <= 200; // Within 200 meters
            });
          }
          
          // Function to get place details and update map
          Future<void> selectPlace(Map<String, dynamic> prediction) async {
            final placeId = prediction['place_id'];
            if (placeId == null) return;
            
            try {
              final url = Uri.parse('https://superdailys.com/superdailyapp/place_details.php?place_id=' + Uri.encodeComponent(placeId));
              final response = await http.get(url);
              
              if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                final result = data['result'];
                if (result != null && result['geometry'] != null) {
                  final location = result['geometry']['location'];
                  final lat = location['lat'] as double;
                  final lng = location['lng'] as double;
                  final bookingLatLng = LatLng(lat, lng);
                  
                  // Calculate distance and availability first
                  calculateDistanceAndAvailability(bookingLatLng);
                  
                  // Update map markers - show both service location and booking location
                  Set<Marker> newMarkers = Set.from(mapMarkers);
                  // Remove old booking location marker if exists
                  newMarkers.removeWhere((m) => m.markerId.value == 'selected_location' || m.markerId.value == 'current_location');
                  // Add new booking location marker
                  newMarkers.add(
                    Marker(
                      markerId: const MarkerId('selected_location'),
                      position: bookingLatLng,
                      infoWindow: InfoWindow(title: prediction['description'] ?? 'Booking Location'),
                    ),
                  );
                  
                  setModalState(() {
                    selectedLocation = bookingLatLng;
                    locationCtrl.text = prediction['description'] ?? '';
                    autocompleteSuggestions = [];
                    mapMarkers = newMarkers;
                  });
                  
                  // Move map camera to show both locations (after state update)
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mapController != null && selectedLocation != null) {
                      try {
                        if (serviceLat != null && serviceLng != null) {
                          // Calculate bounds to show both locations
                          final bounds = LatLngBounds(
                            southwest: LatLng(
                              bookingLatLng.latitude < serviceLat! ? bookingLatLng.latitude : serviceLat!,
                              bookingLatLng.longitude < serviceLng! ? bookingLatLng.longitude : serviceLng!,
                            ),
                            northeast: LatLng(
                              bookingLatLng.latitude > serviceLat! ? bookingLatLng.latitude : serviceLat!,
                              bookingLatLng.longitude > serviceLng! ? bookingLatLng.longitude : serviceLng!,
                            ),
                          );
                          mapController!.animateCamera(
                            CameraUpdate.newLatLngBounds(bounds, 100),
                          );
                        } else {
                          mapController!.animateCamera(
                            CameraUpdate.newLatLngZoom(bookingLatLng, 15),
                          );
                        }
                      } catch (e) {
                        debugPrint('Error animating camera: $e');
                      }
                    }
                  });
                }
              }
            } catch (e) {
              debugPrint('Error getting place details: $e');
            }
          }
          
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Book Service', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Preferred Date
                  Text('Preferred Date', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
                      if (picked != null) setModalState(() { preferredDate = picked; });
                    },
                    child: _formBox(
                      child: Row(children: [
                        const Icon(Icons.calendar_today, size: 18, color: Color(0xFF00BFA5)),
                        const SizedBox(width: 8),
                        Text(preferredDate == null ? 'Select date' : _fmtDate(preferredDate!), style: GoogleFonts.poppins(fontSize: 14)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Preferred Time
                  Text('Preferred Time', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                      if (picked != null) setModalState(() { preferredTime = picked; });
                    },
                    child: _formBox(
                      child: Row(children: [
                        const Icon(Icons.access_time, size: 18, color: Color(0xFF00BFA5)),
                        const SizedBox(width: 8),
                        Text(preferredTime == null ? 'Select time' : preferredTime!.format(context), style: GoogleFonts.poppins(fontSize: 14)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Location Search Bar with Autocomplete
                  Text('Search Location', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _formBox(
                        child: TextField(
                          controller: locationCtrl,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search address or area',
                            prefixIcon: isLoadingSuggestions
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00BFA5)),
                                    ),
                                  )
                                : const Icon(Icons.search, color: Color(0xFF00BFA5)),
                            suffixIcon: locationCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () => setModalState(() {
                                      locationCtrl.clear();
                                      autocompleteSuggestions = [];
                                      selectedLocation = null;
                                      mapMarkers = {};
                                    }),
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            setModalState(() {});
                            if (value.length >= 3) {
                              fetchAutocompleteSuggestions(value);
                            } else {
                              setModalState(() {
                                autocompleteSuggestions = [];
                              });
                            }
                          },
                        ),
                      ),
                      // Autocomplete suggestions dropdown - placed below the search box
                      if (autocompleteSuggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: autocompleteSuggestions.length > 5 ? 5 : autocompleteSuggestions.length,
                              itemBuilder: (context, index) {
                                final suggestion = autocompleteSuggestions[index];
                                return InkWell(
                                  onTap: () {
                                    selectPlace(suggestion);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on, color: Color(0xFF00BFA5), size: 20),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            suggestion['description'] ?? '',
                                            style: GoogleFonts.poppins(fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Google Map
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: GoogleMap(
                        key: const ValueKey('booking_map'), // Stable key to prevent unnecessary rebuilds
                        initialCameraPosition: CameraPosition(
                          target: selectedLocation ?? (serviceLat != null && serviceLng != null ? LatLng(serviceLat!, serviceLng!) : const LatLng(28.6139, 77.2090)),
                          zoom: selectedLocation != null ? 15 : (serviceLat != null && serviceLng != null ? 14 : 12),
                        ),
                        mapType: MapType.normal,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        markers: mapMarkers,
                        onMapCreated: (GoogleMapController controller) {
                          if (mapController == null) {
                            mapController = controller;
                            isMapInitialized = true;
                            
                            // If we already have a selected location, move camera to it after a short delay
                            if (selectedLocation != null) {
                              Future.delayed(const Duration(milliseconds: 500), () {
                                if (mapController != null && selectedLocation != null) {
                                  try {
                                    mapController!.animateCamera(
                                      CameraUpdate.newLatLngZoom(selectedLocation!, 15),
                                    );
                                  } catch (e) {
                                    debugPrint('Error animating camera on map created: $e');
                                  }
                                }
                              });
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  // Distance and Availability Status
                  if (selectedLocation != null && distanceInMeters != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isServiceAvailable ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isServiceAvailable ? Colors.green.shade300 : Colors.red.shade300,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isServiceAvailable ? Icons.check_circle : Icons.cancel,
                            color: isServiceAvailable ? Colors.green.shade700 : Colors.red.shade700,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isServiceAvailable ? 'Service Available' : 'Service Unavailable',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isServiceAvailable ? Colors.green.shade700 : Colors.red.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Distance: ${distanceInMeters!.toStringAsFixed(0)} meters (${(distanceInMeters! / 1000).toStringAsFixed(2)} km)',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                if (!isServiceAvailable)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Service is only available within 200 meters',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.red.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Current Location Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessingPayment ? null : () async {
                        // Show loading
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Getting your location...'),
                              ],
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );

                        try {
                          // Request location permission
                          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                          if (!serviceEnabled) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Location services are disabled. Please enable location services in settings.')),
                            );
                            return;
                          }

                          LocationPermission permission = await Geolocator.checkPermission();
                          if (permission == LocationPermission.denied) {
                            permission = await Geolocator.requestPermission();
                            if (permission == LocationPermission.denied) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Location permission denied. Please enable location permission to use this feature.')),
                              );
                              return;
                            }
                          }

                          if (permission == LocationPermission.deniedForever) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Location permissions are permanently denied. Please enable them in app settings.')),
                            );
                            return;
                          }

                          // Ensure we have permission
                          if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Location permission not granted')),
                            );
                            return;
                          }

                          // Get current position with timeout
                          Position position = await Geolocator.getCurrentPosition(
                            desiredAccuracy: LocationAccuracy.high,
                            timeLimit: const Duration(seconds: 10),
                          ).timeout(
                            const Duration(seconds: 15),
                            onTimeout: () {
                              throw Exception('Location request timed out. Please try again.');
                            },
                          );

                          debugPrint('📍 Current location obtained: ${position.latitude}, ${position.longitude}');

                          // Update location and map immediately
                          final currentLatLng = LatLng(position.latitude, position.longitude);
                          
                          // Calculate distance and availability
                          calculateDistanceAndAvailability(currentLatLng);
                          
                          // Update map markers - keep service location, replace booking location
                          Set<Marker> newMarkers = Set.from(mapMarkers);
                          // Remove old booking location markers
                          newMarkers.removeWhere((m) => m.markerId.value == 'selected_location' || m.markerId.value == 'current_location');
                          
                          // Try to reverse geocode for address
                          String address = '';
                          try {
                            List<Placemark> placemarks = await placemarkFromCoordinates(
                              position.latitude,
                              position.longitude,
                            ).timeout(const Duration(seconds: 5));

                            if (placemarks.isNotEmpty) {
                              Placemark place = placemarks[0];
                              address = [
                                place.street,
                                place.subThoroughfare,
                                place.thoroughfare,
                                place.locality,
                                place.administrativeArea,
                                place.postalCode,
                                place.country,
                              ].where((s) => s != null && s.isNotEmpty && s.toString().trim().isNotEmpty).join(', ');
                            }
                          } catch (e) {
                            debugPrint('Geocoding error: $e');
                            // Continue without address
                          }

                          // Add new current location marker
                          newMarkers.add(
                            Marker(
                              markerId: const MarkerId('current_location'),
                              position: currentLatLng,
                              infoWindow: InfoWindow(title: address.isEmpty ? 'Your Current Location' : address),
                              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                            ),
                          );
                          
                          // Update state first
                          setModalState(() {
                            locationCtrl.text = address.isEmpty 
                                ? 'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}'
                                : address;
                            selectedLocation = currentLatLng;
                            mapMarkers = newMarkers;
                          });
                          
                          // Wait a bit for state to update and map to be ready
                          await Future.delayed(const Duration(milliseconds: 500));
                          
                          // Move map camera - ensure controller is ready
                          if (mapController != null && mounted) {
                            try {
                              if (serviceLat != null && serviceLng != null) {
                                // Show both locations in bounds with padding
                                final bounds = LatLngBounds(
                                  southwest: LatLng(
                                    currentLatLng.latitude < serviceLat! ? currentLatLng.latitude : serviceLat!,
                                    currentLatLng.longitude < serviceLng! ? currentLatLng.longitude : serviceLng!,
                                  ),
                                  northeast: LatLng(
                                    currentLatLng.latitude > serviceLat! ? currentLatLng.latitude : serviceLat!,
                                    currentLatLng.longitude > serviceLng! ? currentLatLng.longitude : serviceLng!,
                                  ),
                                );
                                await mapController!.animateCamera(
                                  CameraUpdate.newLatLngBounds(bounds, 150),
                                );
                              } else {
                                // Just show current location
                                await mapController!.animateCamera(
                                  CameraUpdate.newLatLngZoom(
                                    currentLatLng,
                                    16,
                                  ),
                                );
                              }
                              
                              debugPrint('✅ Map camera moved to current location');
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    address.isEmpty 
                                        ? 'Location found: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}'
                                        : 'Location: $address',
                                  ),
                                  duration: const Duration(seconds: 3),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              debugPrint('❌ Error animating camera: $e');
                              // Try direct set instead
                              try {
                                await mapController!.moveCamera(
                                  CameraUpdate.newLatLngZoom(currentLatLng, 16),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Location found and map updated'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e2) {
                                debugPrint('❌ Error moving camera: $e2');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Location found but map update failed: $e2'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            }
                          } else {
                            debugPrint('⚠️ Map controller is null');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Location found. Please wait for map to load.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('❌ Error getting location: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error getting location: ${e.toString()}'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.my_location, color: Colors.white),
                      label: Text('Current Location', style: GoogleFonts.poppins(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BFA5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Contact
                  Text('Contact Number', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  _formBox(child: TextField(controller: contactCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(border: InputBorder.none, hintText: 'e.g. 9876543210'))),
                  const SizedBox(height: 12),
                  // Notes
                  Text('Special Instructions', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  _formBox(child: TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(border: InputBorder.none, hintText: 'Any notes for professional'))),

                  const SizedBox(height: 16),
                  // Price Options
                  if (personPrices.isNotEmpty)
                    Text('Choose Price - Persons', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                  if (personPrices.isNotEmpty)
                    ...personPrices.entries.map((e) => RadioListTile<String>(
                          dense: true,
                          value: e.key,
                          groupValue: selectedPriceKey,
                          onChanged: (v) => setSelected(e.key, e.value, setModalState),
                          title: Text(e.key, style: GoogleFonts.poppins(fontSize: 14)),
                          secondary: Text('₹' + e.value.toStringAsFixed(2), style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                        )),
                  if (bhkPrices.isNotEmpty) const SizedBox(height: 8),
                  if (bhkPrices.isNotEmpty)
                    Text('Choose Price - BHKs', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                  if (bhkPrices.isNotEmpty)
                    ...bhkPrices.entries.map((e) => RadioListTile<String>(
                          dense: true,
                          value: e.key,
                          groupValue: selectedPriceKey,
                          onChanged: (v) => setSelected(e.key, e.value, setModalState),
                          title: Text(e.key, style: GoogleFonts.poppins(fontSize: 14)),
                          secondary: Text('₹' + e.value.toStringAsFixed(2), style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                        )),

                  if (monthlyPrice != null && monthlyPrice > 0) const SizedBox(height: 8),
                  if (monthlyPrice != null && monthlyPrice > 0)
                    Text('Subscription', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                  if (monthlyPrice != null && monthlyPrice > 0)
                    RadioListTile<String>(
                      dense: true,
                      value: 'Monthly Subscription',
                      groupValue: selectedPriceKey,
                      onChanged: (v) => setSelected('Monthly Subscription', monthlyPrice, setModalState),
                      title: Text('Monthly Subscription', style: GoogleFonts.poppins(fontSize: 14)),
                      secondary: Text('₹' + monthlyPrice.toStringAsFixed(2), style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                    ),

                  const SizedBox(height: 12),
                  if (selectedPriceKey != null)
                    Row(
                      children: [
                        Expanded(child: Text('Selected: ' + selectedPriceKey!, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600))),
                        Text('₹' + selectedPriceValue.toStringAsFixed(2), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0D47A1))),
                      ],
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (serviceLat != null && serviceLng != null && selectedLocation != null && distanceInMeters != null && !isServiceAvailable)
                            ? Colors.grey.shade400
                            : const Color(0xFF00BFA5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (_isProcessingPayment || (serviceLat != null && serviceLng != null && selectedLocation != null && distanceInMeters != null && !isServiceAvailable))
                          ? null
                          : () async {
                        // Lazy-select first option if nothing chosen yet
                        if (selectedPriceKey == null) {
                          if (allOptions.isNotEmpty) {
                            final first = allOptions.entries.first;
                            setModalState(() { selectedPriceKey = first.key; selectedPriceValue = first.value; });
                          } else {
                            final base = _fallbackBasePrice(_service!);
                            if (base != null) {
                              setModalState(() { selectedPriceKey = 'Base Price'; selectedPriceValue = base; });
                            }
                          }
                        }
                        if (selectedPriceKey == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please choose a price option')));
                          return;
                        }
                        if (preferredDate == null || preferredTime == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select date and time')));
                          return;
                        }
                        if (locationCtrl.text.trim().isEmpty || contactCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter location and phone')));
                          return;
                        }
                        // Check if service is available at the selected location (within 200 meters)
                        if (serviceLat != null && serviceLng != null && selectedLocation != null) {
                          // Recalculate to ensure latest distance
                          calculateDistanceAndAvailability(selectedLocation!);
                          if (distanceInMeters != null && !isServiceAvailable) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Service unavailable. Distance: ${distanceInMeters!.toStringAsFixed(0)} meters. Service is only available within 200 meters.'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                            return;
                          }
                        } else if (serviceLat != null && serviceLng != null && selectedLocation == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a location to check service availability')));
                          return;
                        }
                        final payload = await _buildBookingPayload(
                          bookingDate: preferredDate!,
                          bookingTime: preferredTime!,
                          address: locationCtrl.text.trim(),
                          phone: contactCtrl.text.trim(),
                          notes: notesCtrl.text.trim(),
                          selectedLabel: selectedPriceKey!,
                          selectedPrice: selectedPriceValue,
                        );
                        
                        // Check if this is a monthly subscription service
                        final isMonthlySubscription = (_service!['main_category'] ?? '').toString().toLowerCase().contains('monthly') ||
                                                       selectedPriceKey!.toLowerCase().contains('monthly');
                        
                        if (isMonthlySubscription) {
                          // For monthly subscriptions, use Razorpay payment
                          Navigator.of(ctx).pop(); // Close booking sheet first
                          await _initiateRazorpayPayment(selectedPriceValue, payload);
                        } else {
                          // For one-time services, submit directly
                        final ok = await _submitBooking(payload);
                        if (!mounted) return;
                        if (ok) {
                          Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Booking successful! Awaiting maid assignment.',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                                ),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 4),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                        } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to create booking'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                        },
                      child: _isProcessingPayment
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                        (serviceLat != null && serviceLng != null && selectedLocation != null && distanceInMeters != null && !isServiceAvailable)
                            ? 'Service Unavailable'
                            : 'Confirm Booking',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _formBox({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: child,
    );
  }

  Map<String, double> _extractPersonPrices(Map svc) {
    double? p(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }
    final Map<String, double> out = {};
    void add(String label, dynamic val) { final v = p(val); if (v != null && v > 0) out[label] = v; }
    add('1 person', svc['price_1_person']);
    add('2 persons', svc['price_2_persons']);
    add('1-2 persons', svc['price_1_2_persons']);
    add('2-5 persons', svc['price_2_5_persons']);
    add('5-10 persons', svc['price_5_10_persons']);
    add('10+ persons', svc['price_10_plus_persons']);
    return out;
  }

  Map<String, double> _extractBhkPrices(Map svc) {
    double? p(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }
    final Map<String, double> out = {};
    void add(String label, dynamic val) { final v = p(val); if (v != null && v > 0) out[label] = v; }
    add('1 BHK', svc['price_1_bhk']);
    add('2 BHK', svc['price_2_bhk']);
    add('3 BHK', svc['price_3_bhk']);
    add('4 BHK', svc['price_4_bhk']);
    add('2 washrooms', svc['price_2_washroom']);
    add('3 washrooms', svc['price_3_washroom']);
    add('4 washrooms', svc['price_4_washroom']);
    add('4+ washrooms', svc['price_4_plus_washroom']);
    return out;
  }

  double? _extractMonthlyPrice(Map svc) {
    double? p(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }
    final m = p(svc['monthly_plan_price']);
    if (m != null && m > 0) return m;
    return null;
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  }

  double? _fallbackBasePrice(Map svc) {
    double? parse(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }
    final base = parse(svc['price']) ?? 0;
    final discount = parse(svc['discount_price']);
    if (discount != null && discount > 0 && discount < base) return discount;
    return base > 0 ? base : null;
  }

  Future<Map<String, dynamic>> _buildBookingPayload({
    required DateTime bookingDate,
    required TimeOfDay bookingTime,
    required String address,
    required String phone,
    required String notes,
    required String selectedLabel,
    required double selectedPrice,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? user;
    try {
      final s = prefs.getString('userData');
      if (s != null) user = jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {}
    final userId = user != null ? (user['id'] ?? user['user_id']) : null;

    final serviceId = _service!['id'];
    final durationRaw = (_service!['duration'] ?? '').toString();
    final durationHours = double.tryParse(RegExp(r'[0-9]+(\.[0-9]+)?').firstMatch(durationRaw)?.group(0) ?? '') ?? 0.0;

    final discountAmount = 0.0; // can be computed if you apply coupons
    final totalAmount = selectedPrice;
    final finalAmount = totalAmount - discountAmount;

    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${bookingDate.year}-${two(bookingDate.month)}-${two(bookingDate.day)}';
    final timeStr = '${two(bookingTime.hour)}:${two(bookingTime.minute)}:00';
    // Simple time slot: start to start+duration_hours (rounded to minutes)
    String? timeSlot;
    if (durationHours > 0) {
      final start = DateTime(bookingDate.year, bookingDate.month, bookingDate.day, bookingTime.hour, bookingTime.minute);
      final end = start.add(Duration(minutes: (durationHours * 60).round()));
      timeSlot = '${two(start.hour)}:${two(start.minute)} - ${two(end.hour)}:${two(end.minute)}';
    }

    final bookingRef = 'BK' + DateTime.now().millisecondsSinceEpoch.toString();
    final nowIso = DateTime.now().toIso8601String();

    final isMonthly = selectedLabel.toLowerCase().contains('monthly');

    return {
      'user_id': userId,
      'maid_id': null,
      'assigned_at': null,
      'assigned_by': null,
      'assignment_notes': null,
      'service_id': serviceId,
      'subscription_plan': isMonthly ? 'monthly' : null,
      'subscription_plan_details': isMonthly ? (_service!['subscription_plans'] ?? '').toString() : null,
      'booking_reference': bookingRef,
      'booking_date': dateStr,
      'booking_time': timeStr,
      'time_slot': timeSlot,
      'address': address,
      'phone': phone,
      'special_instructions': notes,
      'duration_hours': durationHours,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'final_amount': finalAmount,
      'status': 'pending',
      'payment_status': 'pending',
      'payment_method': null,
      'payment_id': null,
      'transaction_id': null,
      'gateway_response': null,
      'billing_name': null,
      'billing_phone': null,
      'billing_address': null,
      'payment_completed_at': null,
      'payment_failed_at': null,
      'customer_notes': null,
      'maid_notes': null,
      'admin_notes': null,
      'address_details': address,
      'service_requirements': (_service!['requirements'] ?? '').toString(),
      'confirmed_at': null,
      'started_at': null,
      'completed_at': null,
      'allocated_at': null,
      'cancelled_at': null,
      'created_at': nowIso,
      'updated_at': nowIso,
    };
  }

  Future<bool> _submitBooking(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse(_getBackendBaseUrl() + 'bookings_create.php');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && (data['success'] == true || data['status'] == 'ok')) {
          return true;
        }
        debugPrint('Booking create response (not success): ' + jsonEncode(data));
      }
      debugPrint('Booking create failed: ' + res.statusCode.toString() + ' ' + res.body);
      return false;
    } catch (e) {
      debugPrint('Booking create error: ' + e.toString());
      return false;
    }
  }

  List<String> _formatBullets(String text) {
    // Normalize common escape sequences first
    String normalize(String s) {
      String n = s
          .replaceAll('\\r\\n', '\n')
          .replaceAll('\\n', '\n')
          .replaceAll('\\t', ' ')
          .replaceAll('\\u2019', "'");
      // Trim any surrounding quotes/brackets artifacts
      if (n.startsWith('"') && n.endsWith('"')) {
        n = n.substring(1, n.length - 1);
      }
      return n;
    }

    List<String> splitLoose(String s) {
      // Primary: newlines, semicolons or vertical bars
      final primary = s.split(RegExp(r'\n+|;|\|')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (primary.length > 1) return primary;
      // Fallback: split by sentence boundaries if still a single blob
      final sentences = s.split(RegExp(r'(?<=[.!?])\s+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      return sentences.isEmpty ? [s.trim()] : sentences;
    }

    // Attempt to parse JSON array strings like ["a","b"]
    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((e) => normalize(e.toString()))
            .expand((e) => splitLoose(e))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (decoded is String) {
        final n = normalize(decoded);
        return splitLoose(n);
      }
    } catch (_) {
      // not JSON, fall back to loose parsing
    }

    final n = normalize(text);
    return splitLoose(n);
  }

  String _resolveServiceImageUrlForDetails(String raw) {
    if (raw.isEmpty) return raw;
    String p = raw.trim();
    // Normalize slashes
    p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
    
    // Already absolute URL starting with https://superdailys.com/storage/services/
    if (p.startsWith('https://superdailys.com/storage/services/')) {
      return p;
    }
    
    // Handle URLs with superdailyapp/storage/services/ or superdailyapp/storage/products/
    if (p.contains('/superdailyapp/storage/')) {
      final filename = p.split('/').last.split('?').first.split('#').first;
      if (filename.isNotEmpty && filename.contains('.')) {
        return 'https://superdailys.com/storage/services/' + filename;
      }
    }
    
    // Handle Hostinger file server URLs - convert to regular domain (since those are failing)
    if (p.contains('srv1881-files.hstgr.io')) {
      final filename = p.split('/').last.split('?').first.split('#').first;
      if (filename.isNotEmpty && filename.contains('.')) {
        return 'https://superdailys.com/storage/services/' + filename;
      }
    }
    
    // Already absolute URL (any other URL)
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return p;
    }
    
    // Extract just the filename from the path
    String filename = p.split('/').last.split('\\').last;
    // Remove query parameters and hash
    filename = filename.split('?').first.split('#').first;
    
    // If filename is empty or doesn't have extension, try to find it
    if (filename.isEmpty || !filename.contains('.')) {
      final parts = p.split('/');
      for (var part in parts.reversed) {
        if (part.contains('.') && part.length > 3) {
          filename = part.split('?').first.split('#').first;
          break;
        }
      }
    }
    
    // Build full URL - use same as monthly subscription (which works)
    if (filename.isNotEmpty && filename.contains('.')) {
      return 'https://superdailys.com/storage/services/' + filename;
    }
    
    return '';
  }

  Widget _buildImages() {
    // Collect all available service images (image, image_2, image_3, image_4)
    final List<String> serviceImages = [];
    for (var imgKey in ['image', 'image_2', 'image_3', 'image_4']) {
      final imgValue = _service![imgKey];
      if (imgValue != null && imgValue.toString().trim().isNotEmpty) {
        final resolvedUrl = _resolveServiceImageUrlForDetails(imgValue.toString());
        if (resolvedUrl.isNotEmpty && resolvedUrl.startsWith('http')) {
          serviceImages.add(resolvedUrl);
          debugPrint('🖼️ Service Details - Found image from $imgKey: $resolvedUrl');
        }
      }
    }
    
    if (serviceImages.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
        child: const Center(child: Icon(Icons.image_not_supported, size: 64, color: Colors.grey)),
      );
    }
    
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          PageView.builder(
            controller: _imgCtrl,
            itemCount: serviceImages.length,
            onPageChanged: (i) => setState(() { _imgIndex = i; }),
            itemBuilder: (context, i) {
              final imageUrl = serviceImages[i];
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _ServiceDetailsImageWidget(
                  imageUrl: imageUrl,
                  serviceName: _service!['name']?.toString() ?? 'Service',
                ),
              );
            },
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(serviceImages.length, (i) {
                final active = i == _imgIndex;
                return Container(
                  width: active ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(color: active ? Colors.white : Colors.white70, borderRadius: BorderRadius.circular(8)),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBlock() {
    double? parse(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
    final base = parse(_service!['price']) ?? 0;
    final discount = parse(_service!['discount_price']);
    final monthly = parse(_service!['monthly_plan_price']);
    final chosen = monthly != null && monthly > 0 ? monthly : (discount != null && discount > 0 && discount < base ? discount : base);
    return Row(
      children: [
        Text('₹' + chosen.toStringAsFixed(2), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: const Color(0xFF0D47A1))),
        const SizedBox(width: 12),
        if (discount != null && discount < base && discount > 0)
          Text('₹' + base.toStringAsFixed(2), style: GoogleFonts.poppins(decoration: TextDecoration.lineThrough, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTitledBox(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade900)),
        const SizedBox(height: 8),
        Text(content, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade800, height: 1.5)),
      ]),
    );
  }

  Widget _buildFacts() {
    List<Widget> rows = [];
    void add(String label, dynamic value) {
      if (value == null) return;
      final s = value.toString();
      if (s.isEmpty) return;
      rows.add(_factRow(label, s));
    }
    add('Main Category', _service!['main_category']);
    add('Subcategory', _service!['subcategory']);
    add('Persons Count', _service!['persons_count']);
    add('Property Type', _service!['property_type']);
    add('Duration', _service!['duration']);
    add('Advance (hrs)', _service!['booking_advance_hours']);
    add('Category', _service!['category']);
    add('Subscription Plans', _service!['subscription_plans']);
    add('Coupon Type', _service!['coupon_type']);
    add('Coupon Discount', _service!['coupon_discount_price']);
    add('Booking Requirements', _service!['booking_requirements']);
    add('Location Id', _service!['location_id']);
    add('Unit', _service!['unit']);
    add('Latitude', _service!['service_latitude']);
    add('Longitude', _service!['service_longitude']);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Information', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade900)),
        const SizedBox(height: 12),
        ...rows,
      ]),
    );
  }

  Widget _factRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
        Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade900))),
      ]),
    );
  }
}