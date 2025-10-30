import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Global backend base URL and image resolver for use across screens
const String kBackendBaseUrl = 'http://localhost/spdbackend/';
const String kStorageProductsBase = 'http://127.0.0.1:8000/storage/products/';

String _resolveImageUrl(String raw) {
  if (raw.isEmpty) return raw;
  String p = raw.trim();
  p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
  if (p.startsWith('http://') || p.startsWith('https://')) {
    // If the API returns a URL pointing to spdbackend, remap to Laravel storage using filename
    final baseName = _basename(p);
    if (baseName.isNotEmpty) {
      return kStorageProductsBase + baseName;
    }
    return p;
  }
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
  // Prefer Laravel storage for non-absolute paths
  final fileName = _basename(p);
  if (fileName.isNotEmpty) {
    final url = kStorageProductsBase + fileName;
    debugPrint('Resolved image URL (storage): ' + url);
    return url;
  }
  final url = kBackendBaseUrl + p;
  debugPrint('Resolved image URL (fallback backend): ' + url);
  return url;
}

String _getBackendBaseUrl() {
  // Auto-detect correct host for emulator vs desktop/web
  if (kIsWeb) return kBackendBaseUrl; // assume browser and backend on same host
  try {
    if (Platform.isAndroid) {
      // Android emulator cannot reach development machine via localhost
      return 'http://10.0.2.2/spdbackend/';
    }
    // iOS simulator, Windows/macOS/Linux desktop
    return kBackendBaseUrl;
  } catch (_) {
    return kBackendBaseUrl;
  }
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

      if (isLoggedIn && userDataJson != null) {
    setState(() {
          _isLoggedIn = true;
          _userData = jsonDecode(userDataJson);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoggedIn = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoggedIn = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
        ),
      );
    }

    if (_isLoggedIn && _userData != null) {
      return HomeScreen(userData: _userData!);
    }

    return const LoginPage();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    // Remove spaces and special characters for validation
    final cleanPhone = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleanPhone.length < 10) {
      return 'Please enter a valid phone number';
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

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
    setState(() {
        _isLoading = true;
      });

      try {
        // API endpoint
        // For Android Emulator use: http://10.0.2.2/spdbackend/login.php
        // For iOS Simulator use: http://localhost/spdbackend/login.php
        // For Physical Device use: http://YOUR_COMPUTER_IP/spdbackend/login.php
        // For Web/Windows Desktop use: http://localhost/spdbackend/login.php
        const String apiUrl = 'http://localhost/spdbackend/login.php';
        
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Spacer to push login box to bottom
            const Spacer(),
            
            // Login Card at bottom
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
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Form(
                          key: _formKey,
        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Phone Field
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: 'Phone Number',
                                  hintText: 'Enter your phone number',
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
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Forgot password feature'),
                                      ),
                                    );
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
                              const SizedBox(height: 24),
                              
                              // Divider
                              Row(
                                children: [
                                  Expanded(child: Divider(color: Colors.grey.shade300)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      'OR',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider(color: Colors.grey.shade300)),
                                ],
                              ),
                              const SizedBox(height: 24),
                              
                              // Social Login Buttons
                              OutlinedButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Google login feature'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.g_mobiledata, size: 28),
                                label: Text(
                                  'Continue with Google',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Sign Up Link
                    Row(
          mainAxisAlignment: MainAxisAlignment.center,
                      children: [
            Text(
                          "Don't have an account? ",
                          style: GoogleFonts.poppins(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sign up feature'),
                              ),
                            );
                          },
                          child: Text(
                            'Sign Up',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF00BFA5),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
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
  static const Color _tealColor = Color(0xFF00BFA5);
  static const Color _tealLight = Color(0xFFE0F2F1);

  @override
  void initState() {
    super.initState();
    _fetchProductDetails();
    _imageController = PageController();
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _fetchProductDetails() async {
    try {
      final response = await http.get(
        Uri.parse('http://localhost/spdbackend/get_product_details.php?id=${widget.productId}'),
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
    if (_product!['image'] != null && _product!['image'].toString().isNotEmpty) {
      images.add(_product!['image'].toString());
    }
    if (_product!['image_2'] != null && _product!['image_2'].toString().isNotEmpty) {
      images.add(_product!['image_2'].toString());
    }
    if (_product!['image_3'] != null && _product!['image_3'].toString().isNotEmpty) {
      images.add(_product!['image_3'].toString());
    }
    if (_product!['image_4'] != null && _product!['image_4'].toString().isNotEmpty) {
      images.add(_product!['image_4'].toString());
    }
    return images.isEmpty ? [''] : images; // Return empty string if no images
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
                        onPressed: () {
                          // Add to cart functionality
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added to cart'),
                              backgroundColor: _tealColor,
                            ),
                          );
                        },
                        icon: const Icon(Icons.shopping_cart),
                        label: Text(
                          'Add to Cart',
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
    if (images.isEmpty) {
      images = ['']; // Placeholder
    }

    return SizedBox(
      height: 350,
      child: Stack(
        children: [
          PageView.builder(
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
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: Uri.encodeFull(_resolveImageUrl(imageUrl)),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(_tealColor),
                          ),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Icon(
                            Icons.image_not_supported,
                            size: 80,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.image,
                          size: 80,
                          color: Colors.grey.shade400,
                        ),
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

    final sellingPriceNum = sellingPrice is String
        ? double.tryParse(sellingPrice) ?? 0.0
        : (sellingPrice is num ? sellingPrice.toDouble() : 0.0);
    final mrpPriceNum = mrpPrice is String
        ? double.tryParse(mrpPrice) ?? sellingPriceNum
        : (mrpPrice is num ? mrpPrice.toDouble() : sellingPriceNum);
    final discountPercentageNum = discountPercentage is String
        ? double.tryParse(discountPercentage) ?? 0.0
        : (discountPercentage is num ? discountPercentage.toDouble() : 0.0);

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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
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
                'Specifications',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isMap)
            // Display as key-value pairs if it's a map
            ...(specsData as Map<String, dynamic>).entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        entry.key.toString().replaceAll('_', ' ').toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        entry.value.toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList()
          else if (isList)
            // Display as list items if it's a list
            ...(specsData as List).asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6, right: 12),
                      decoration: BoxDecoration(
                        color: _tealColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value.toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList()
          else
            // Display as formatted text if it's plain text
            Text(
              _formatSpecificationsText(specificationsText),
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade800,
                height: 1.6,
                letterSpacing: 0.2,
              ),
            ),
        ],
      ),
    );
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
  List<dynamic> _categories = [];
  bool _isLoadingCategories = true;
  List<dynamic> _oneTimeServices = [];
  bool _isLoadingServices = true;
  List<dynamic> _monthlySubscriptionServices = [];
  bool _isLoadingMonthlyServices = true;
  late PageController _carouselController;
  int _currentCarouselIndex = 0;
  static const Color _tealColor = Color(0xFF00BFA5);
  static const Color _tealLight = Color(0xFFE0F2F1);
  static const Color _tealLighter = Color(0xFFF0F9F8);
  static const Color _priceDarkBlue = Color(0xFF0D47A1);
  static const String _backendBaseUrl = 'http://localhost/spdbackend/';

  String _resolveImageUrl(String raw) {
    if (raw.isEmpty) return raw;
    String p = raw.trim();
    // Normalize slashes
    p = p.replaceAll('\\\\', '/').replaceAll('\\', '/');
    // Already absolute URL
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return p;
    }
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
    debugPrint('Resolved image URL: ' + url);
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
      const String apiUrl = 'http://localhost/spdbackend/get_featured_products.php';
      
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
            print('Fetched ${products.length} featured products'); // Debug
            print('Product count from API: ${data['count']}'); // Debug
            setState(() {
              _featuredProducts = products;
              _isLoadingProducts = false;
            });
          } else {
            print('API returned success=false: ${data['message']}'); // Debug
            setState(() {
              _isLoadingProducts = false;
            });
          }
        } else {
          print('API Error Status: ${response.statusCode}'); // Debug
          print('Response: ${response.body}'); // Debug
          setState(() {
            _isLoadingProducts = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
    setState(() {
          _isLoadingProducts = false;
        });
      }
    }
  }

  Future<void> _fetchCategories() async {
    try {
      const String apiUrl = 'http://localhost/spdbackend/get_categories.php';
      
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
      const String apiUrl = 'http://localhost/spdbackend/get_one_time_services.php';
      
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
            print('Fetched ${services.length} one-time services'); // Debug
            setState(() {
              _oneTimeServices = services;
              _isLoadingServices = false;
            });
          } else {
            print('One-time services API returned success=false: ${data['message']}'); // Debug
            setState(() {
              _isLoadingServices = false;
            });
          }
        } else {
          print('One-time services API Error Status: ${response.statusCode}'); // Debug
          print('Response: ${response.body}'); // Debug
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
      const String apiUrl = 'http://localhost/spdbackend/get_monthly_subscription_services.php';
      
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
            print('Fetched ${services.length} monthly subscription services'); // Debug
            setState(() {
              _monthlySubscriptionServices = services;
              _isLoadingMonthlyServices = false;
            });
          } else {
            print('Monthly subscription services API returned success=false: ${data['message']}'); // Debug
            setState(() {
              _isLoadingMonthlyServices = false;
            });
          }
        } else {
          print('Monthly subscription services API Error Status: ${response.statusCode}'); // Debug
          print('Response: ${response.body}'); // Debug
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
            icon: Icon(Icons.shopping_bag),
            label: 'Products',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.room_service),
            label: 'Services',
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
          // Menu Icon (Left)
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {
              // Menu drawer functionality can be added here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Menu'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          // Search and Account Icons (Right)
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
                    _currentIndex = 3; // Navigate to Profile tab
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
        return _buildProductsTab();
      case 2:
        return _buildServicesTab();
      case 3:
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
                  'Featured Products',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                if (!_isLoadingProducts && _featuredProducts.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _currentIndex = 1;
                      });
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
          // Featured Products List - Horizontal Scrollable
          _isLoadingProducts
              ? const SizedBox(
                  height: 280,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_tealColor),
                    ),
                  ),
                )
              : _featuredProducts.isEmpty
                  ? SizedBox(
                      height: 280,
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
                              'No featured products available',
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
                      height: 280,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: _featuredProducts.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == _featuredProducts.length - 1 ? 0 : 12,
                            ),
                            child: _buildFeaturedProductCardHorizontal(_featuredProducts[index]),
                          );
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
                      setState(() {
                        _currentIndex = 2; // Navigate to Services tab
                      });
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
                      setState(() {
                        _currentIndex = 2; // Navigate to Services tab
                      });
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            itemCount: 8,
            itemBuilder: (context, index) {
              final products = [
                {'name': 'Product A', 'price': '\$79.99', 'icon': Icons.devices},
                {'name': 'Product B', 'price': '\$59.99', 'icon': Icons.computer},
                {'name': 'Product C', 'price': '\$89.99', 'icon': Icons.phone_android},
                {'name': 'Product D', 'price': '\$39.99', 'icon': Icons.tablet},
                {'name': 'Product E', 'price': '\$69.99', 'icon': Icons.laptop},
                {'name': 'Product F', 'price': '\$49.99', 'icon': Icons.watch},
                {'name': 'Product G', 'price': '\$99.99', 'icon': Icons.headphones},
                {'name': 'Product H', 'price': '\$29.99', 'icon': Icons.speaker},
              ];
              return _buildProductGridCard(
                products[index]['name'] as String,
                products[index]['price'] as String,
                products[index]['icon'] as IconData,
              );
            },
          ),
        ],
      ),
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

  Widget _buildOneTimeServiceCard(Map<String, dynamic> service) {
    final name = service['name'] ?? 'Service';
    final description = service['description'] ?? '';
    final image = service['image'] ?? '';
    final priceNumNullable = _getServicePrice(service);
    double finalPriceNum = priceNumNullable ?? _parsePrice(service['price']) ?? 0.0;
    final priceNum = finalPriceNum;
    final discountPriceNum = _parsePrice(service['discount_price']);
    final finalDiscountPrice = (discountPriceNum != null && discountPriceNum > 0 && finalPriceNum > 0 && discountPriceNum < finalPriceNum) ? discountPriceNum : null;
    final displayPrice = finalDiscountPrice ?? finalPriceNum;
    final hasDiscount = finalDiscountPrice != null;

    final card = Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 280,
          height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_tealLight, _tealLighter]),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: image.toString().isNotEmpty
              ? ClipRRect(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  child: CachedNetworkImage(
                    imageUrl: Uri.encodeFull(_resolveImageUrl(image.toString())),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Center(child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(_tealColor))),
                    errorWidget: (context, url, error) => const Center(child: Icon(Icons.room_service, size: 40)),
                  ),
                )
              : const Center(child: Icon(Icons.room_service, size: 40)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            if (description.isNotEmpty)
              Text(description, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
              Flexible(
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 2, children: [
                  Text('₹' + displayPrice.toStringAsFixed(2), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: _priceDarkBlue)),
                  if (hasDiscount && priceNum > displayPrice)
                    Text('₹' + priceNum.toStringAsFixed(2), style: GoogleFonts.poppins(fontSize: 9, decoration: TextDecoration.lineThrough, color: Colors.grey.shade500)),
                ]),
              ),
              Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: _tealColor, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add, color: Colors.white, size: 16)),
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
    
    // Convert to numbers if they are strings
    final sellingPriceNum = sellingPrice is String 
        ? double.tryParse(sellingPrice) ?? 0.0 
        : (sellingPrice is num ? sellingPrice.toDouble() : 0.0);
    final mrpPriceNum = mrpPrice is String 
        ? double.tryParse(mrpPrice) ?? sellingPriceNum 
        : (mrpPrice is num ? mrpPrice.toDouble() : sellingPriceNum);
    final discountPercentageNum = discountPercentage is String 
        ? double.tryParse(discountPercentage) ?? 0.0 
        : (discountPercentage is num ? discountPercentage.toDouble() : 0.0);
    
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

  @override
  void initState() {
    super.initState();
    _imgCtrl = PageController();
    _fetch();
  }

  @override
  void dispose() {
    _imgCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final uri = Uri.parse('http://localhost/spdbackend/get_service_details.php?id=' + widget.serviceId.toString());
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
                  // Location
                  Text('Search Location', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  _formBox(child: TextField(controller: locationCtrl, decoration: const InputDecoration(border: InputBorder.none, hintText: 'Type address or area'))),
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
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFA5), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () async {
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
                        final payload = await _buildBookingPayload(
                          bookingDate: preferredDate!,
                          bookingTime: preferredTime!,
                          address: locationCtrl.text.trim(),
                          phone: contactCtrl.text.trim(),
                          notes: notesCtrl.text.trim(),
                          selectedLabel: selectedPriceKey!,
                          selectedPrice: selectedPriceValue,
                        );
                        final ok = await _submitBooking(payload);
                        if (!mounted) return;
                        if (ok) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking created')));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create booking'), backgroundColor: Colors.red));
                        }
                      },
                      child: const Text('Confirm Booking'),
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

  Widget _buildImages() {
    final imgs = [
      _service!['image'],
      _service!['image_2'],
      _service!['image_3'],
      _service!['image_4'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).map((e) => e.toString()).toList();
    if (imgs.isEmpty) {
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
            itemCount: imgs.length,
            onPageChanged: (i) => setState(() { _imgIndex = i; }),
            itemBuilder: (context, i) {
              final raw = imgs[i];
              final base = _basename(raw);
              final candidates = <String>[raw, 'products/' + base, 'uploads/' + base, 'uploads/products/' + base];
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FallbackImage(
                  urls: candidates,
                  fit: BoxFit.cover,
                  placeholder: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  error: const Center(child: Icon(Icons.image_not_supported, size: 64, color: Colors.grey)),
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
              children: List.generate(imgs.length, (i) {
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