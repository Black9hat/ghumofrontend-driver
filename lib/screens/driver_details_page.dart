// driver_details_page.dart
import 'dart:io';
import 'package:drivergoo/screens/documents_review_page.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drivergoo/config.dart';
import 'package:drivergoo/services/api_service.dart';

class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color onPrimary = Colors.white;
  static const Color onSurfaceSecondary = Colors.black54;
  static const Color onSurfaceTertiary = Colors.black38;
  static const Color divider = Color(0xFFEEEEEE);
  static const Color success = Color.fromARGB(255, 0, 66, 3);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
}

class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: AppColors.onSurface,
    letterSpacing: -0.5,
  );

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
    letterSpacing: -0.3,
  );

  static TextStyle get heading3 => GoogleFonts.plusJakartaSans(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
  );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurface,
  );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurfaceSecondary,
  );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurfaceTertiary,
    letterSpacing: 0.5,
  );

  static TextStyle get button => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );
}

// ============================================================
// 🔥 HIGH QUALITY DOCUMENT CAMERA PAGE (FOR OCR)
// ============================================================
class DocumentCameraPage extends StatefulWidget {
  final String docType;
  final String side;
  final bool isFrontCamera;

  const DocumentCameraPage({
    super.key,
    required this.docType,
    required this.side,
    this.isFrontCamera = false,
  });

  @override
  State<DocumentCameraPage> createState() => _DocumentCameraPageState();
}

class _DocumentCameraPageState extends State<DocumentCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _isFlashOn = false;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No camera available'),
              backgroundColor: AppColors.error,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      final camera = _cameras!.firstWhere(
        (c) =>
            c.lensDirection ==
            (widget.isFrontCamera
                ? CameraLensDirection.front
                : CameraLensDirection.back),
        orElse: () => _cameras!.first,
      );

      // 🔥 HIGH RESOLUTION FOR BETTER OCR
      _controller = CameraController(
        camera,
        ResolutionPreset.max, // ✅ Maximum resolution for OCR
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // 🔥 Get zoom levels
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();

      // 🔥 Set optimal zoom (slight zoom helps focus on document)
      _currentZoom = (_minZoom + 0.3).clamp(_minZoom, _maxZoom);
      await _controller!.setZoomLevel(_currentZoom);

      // 🔥 Lock focus mode for sharp images
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint("Focus mode not supported: $e");
      }

      // 🔥 Set exposure mode
      try {
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint("Exposure mode not supported: $e");
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  // 🔥 TOGGLE FLASH
  Future<void> _toggleFlash() async {
    if (_controller == null) return;

    try {
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.off);
      } else {
        await _controller!.setFlashMode(FlashMode.torch);
      }

      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (e) {
      debugPrint("Flash toggle error: $e");
    }
  }

  // 🔥 TAP TO FOCUS
  Future<void> _onTapToFocus(
    TapDownDetails details,
    BoxConstraints constraints,
  ) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );

    try {
      await _controller!.setFocusPoint(offset);
      await _controller!.setExposurePoint(offset);
    } catch (e) {
      debugPrint("Focus error: $e");
    }
  }

  // 🔥 HIGH QUALITY CAPTURE
  Future<void> _captureImage() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      // 🔥 Turn off torch before capture, use flash instead
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.always);
      } else {
        await _controller!.setFlashMode(FlashMode.off);
      }

      // 🔥 Lock focus and exposure before capture
      try {
        await _controller!.setFocusMode(FocusMode.locked);
        await _controller!.setExposureMode(ExposureMode.locked);
      } catch (e) {
        debugPrint("Lock modes not supported: $e");
      }

      // Small delay to ensure focus is locked
      await Future.delayed(const Duration(milliseconds: 200));

      final XFile image = await _controller!.takePicture();

      // 🔥 Reset to auto modes
      try {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint("Reset modes error: $e");
      }

      // Restore torch if it was on
      if (_isFlashOn) {
        try {
          await _controller!.setFlashMode(FlashMode.torch);
        } catch (e) {
          debugPrint("Restore torch error: $e");
        }
      }

      // ✅ SAVE TO TEMP DIRECTORY (no compression - keep original quality)
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_hq.jpg';
      final File savedFile = await File(image.path).copy(targetPath);

      // Log file size for debugging
      final fileSize = await savedFile.length();
      debugPrint(
        "📷 Captured image size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB",
      );

      if (mounted) {
        Navigator.pop(context, savedFile);
      }
    } catch (e) {
      debugPrint("Capture error: $e");

      // Reset modes on error
      try {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  List<Widget> _buildCornerIndicators() {
    const size = 30.0;
    const thickness = 4.0;
    const color = AppColors.primary;

    return [
      // Top-left
      Positioned(
        top: 0,
        left: 0,
        child: Container(width: size, height: thickness, color: color),
      ),
      Positioned(
        top: 0,
        left: 0,
        child: Container(width: thickness, height: size, color: color),
      ),
      // Top-right
      Positioned(
        top: 0,
        right: 0,
        child: Container(width: size, height: thickness, color: color),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: Container(width: thickness, height: size, color: color),
      ),
      // Bottom-left
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(width: size, height: thickness, color: color),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(width: thickness, height: size, color: color),
      ),
      // Bottom-right
      Positioned(
        bottom: 0,
        right: 0,
        child: Container(width: size, height: thickness, color: color),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        child: Container(width: thickness, height: size, color: color),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized
          ? Stack(
              children: [
                // Camera Preview with tap to focus
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTapDown: (details) =>
                            _onTapToFocus(details, constraints),
                        child: CameraPreview(_controller!),
                      );
                    },
                  ),
                ),

                // Top bar with flash and close
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Close button
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),

                          // Title
                          Column(
                            children: [
                              Text(
                                widget.docType.toUpperCase(),
                                style: AppTextStyles.heading3.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                widget.side.toUpperCase(),
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),

                          // Flash toggle
                          IconButton(
                            onPressed: _toggleFlash,
                            icon: Icon(
                              _isFlashOn ? Icons.flash_on : Icons.flash_off,
                              color: _isFlashOn
                                  ? AppColors.warning
                                  : Colors.white,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Document guide overlay
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 120,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        // Corner indicators
                        ..._buildCornerIndicators(),
                      ],
                    ),
                  ),
                ),

                // Instructions
                Positioned(
                  bottom: 160,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: AppColors.warning,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Tips for best quality:',
                              style: AppTextStyles.body2.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Ensure good lighting\n• Keep document flat\n• Avoid shadows\n• Tap to focus',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                // Zoom slider
                Positioned(
                  right: 20,
                  top: MediaQuery.of(context).size.height * 0.3,
                  bottom: MediaQuery.of(context).size.height * 0.4,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Slider(
                      value: _currentZoom,
                      min: _minZoom,
                      max: _maxZoom.clamp(_minZoom, 5.0), // Limit max zoom
                      activeColor: AppColors.primary,
                      inactiveColor: Colors.white30,
                      onChanged: (value) async {
                        setState(() {
                          _currentZoom = value;
                        });
                        await _controller?.setZoomLevel(value);
                      },
                    ),
                  ),
                ),

                // Zoom indicator
                Positioned(
                  right: 16,
                  top: MediaQuery.of(context).size.height * 0.25,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentZoom.toStringAsFixed(1)}x',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Capture button
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _isCapturing ? null : _captureImage,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.5),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isCapturing
                                ? Colors.grey
                                : AppColors.primary,
                          ),
                          child: _isCapturing
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 32,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Quality indicator
                Positioned(
                  bottom: 130,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hd, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'HIGH QUALITY MODE',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text(
                    'Initializing high-quality camera...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// 🔥 HIGH QUALITY PROFILE PHOTO CAMERA PAGE (FRONT CAMERA)
// ============================================================
class ProfileCameraPage extends StatefulWidget {
  const ProfileCameraPage({super.key});

  @override
  State<ProfileCameraPage> createState() => _ProfileCameraPageState();
}

class _ProfileCameraPageState extends State<ProfileCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No camera available'),
              backgroundColor: AppColors.error,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      // ✅ Use FRONT camera for profile
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      // 🔥 HIGH RESOLUTION for clear profile photo
      _controller = CameraController(
        camera,
        ResolutionPreset.high, // High for front camera
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // 🔥 Set focus mode
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint("Focus mode not supported: $e");
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      // 🔥 Lock focus before capture
      try {
        await _controller!.setFocusMode(FocusMode.locked);
      } catch (e) {
        debugPrint("Focus lock not supported: $e");
      }

      await Future.delayed(const Duration(milliseconds: 150));

      final XFile image = await _controller!.takePicture();

      // Reset focus mode
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint("Focus reset error: $e");
      }

      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}_hq.jpg';
      final File savedFile = await File(image.path).copy(targetPath);

      // Log file size
      final fileSize = await savedFile.length();
      debugPrint(
        "📷 Profile photo size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB",
      );

      if (mounted) {
        Navigator.pop(context, savedFile);
      }
    } catch (e) {
      debugPrint("Capture error: $e");
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized
          ? Stack(
              children: [
                // Camera Preview
                Positioned.fill(child: CameraPreview(_controller!)),

                // Top bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          Text(
                            'Profile Photo',
                            style: AppTextStyles.heading3.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 48), // Balance
                        ],
                      ),
                    ),
                  ),
                ),

                // Face guide overlay (oval)
                Center(
                  child: Container(
                    width: 250,
                    height: 320,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 3),
                      borderRadius: BorderRadius.circular(125),
                    ),
                  ),
                ),

                // Instructions
                Positioned(
                  bottom: 160,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Position your face within the oval\nEnsure good lighting on your face',
                      style: AppTextStyles.body2.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // Capture button
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _isCapturing ? null : _captureImage,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isCapturing
                                ? Colors.grey
                                : AppColors.primary,
                          ),
                          child: _isCapturing
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 32,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Quality badge
                Positioned(
                  bottom: 130,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hd, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'HD QUALITY',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text(
                    'Initializing camera...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// MAIN PAGE
// ============================================================
class DriverDocumentUploadPage extends StatefulWidget {
  final String driverId;
  final List<String>? uploadedDocTypes;
  final bool isReuploadingProfile;
  final String? preselectDocType;
  final String? preselectDocSide;

  const DriverDocumentUploadPage({
    super.key,
    required this.driverId,
    this.uploadedDocTypes,
    this.preselectDocType,
    this.preselectDocSide,
    this.isReuploadingProfile = false,
  });

  @override
  State<DriverDocumentUploadPage> createState() =>
      _DriverDocumentUploadPageState();
}

class _DriverDocumentUploadPageState extends State<DriverDocumentUploadPage> {
  String? vehicleType;
  int currentStep = 0;
  final Map<String, File?> uploadedDocs = {};
  final Map<String, String?> extractedDataMap = {};
  final Map<String, bool> uploadStatus = {};
  final Map<String, bool> confirmedDocs = {};
  File? profilePhoto;
  bool profilePhotoConfirmed = false;
  final picker = ImagePicker();
  bool isUploading = false;
  List<String> requiredDocs = [];
  List<String> alreadyUploadedDocs = [];
  bool get _isSingleReuploadFlow => widget.preselectDocType != null;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _vehicleNumberController =
      TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _detailsSaved = false;

  final Map<String, String> docTypeMapping = {
    'license': 'license',
    'pan': 'pan',
    'aadhaar': 'aadhaar',
    'insurance': 'insurance',
    'permit': 'permit',
    'fitnessCertificate': 'fitnesscertificate',
    'rc': 'rc',
  };

  @override
  void initState() {
    super.initState();
    alreadyUploadedDocs = widget.uploadedDocTypes ?? [];
    _loadVehicleTypeAndInitialize();
    _loadSavedDetails();
    _restoreTempProfilePhoto();

    if (widget.preselectDocType != null) {
      final pre = widget.preselectDocType!.toLowerCase();

      Future.microtask(() async {
        if (vehicleType == null) {
          final prefs = await SharedPreferences.getInstance();
          final savedVehicleType = prefs.getString('vehicleType');
          if (savedVehicleType != null && savedVehicleType.isNotEmpty) {
            vehicleType = savedVehicleType;
          }
        }

        requiredDocs = (vehicleType != null && vehicleType!.isNotEmpty)
            ? getRequiredDocs(vehicleType!)
            : requiredDocs;

        final idx = requiredDocs.indexWhere((d) => d.toLowerCase() == pre);
        if (idx >= 0) {
          setState(() {
            currentStep = idx + 1;
          });
        } else {
          setState(() {
            currentStep = 1;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  // ✅ SAFE IMAGE COPY FUNCTION
  Future<File> safeCopyImage(File file) async {
    final dir = await getTemporaryDirectory();
    final target = File(
      '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    return await file.copy(target.path);
  }

  Future<String?> getPhoneNumber() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (user.phoneNumber != null) {
        return user.phoneNumber!.replaceAll(RegExp(r'[^\d]'), '');
      }
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('phoneNumber');
    }
    return null;
  }

  Future<void> _saveTempProfilePhoto(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tempProfilePhotoPath', path);
  }

  Future<void> _restoreTempProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('tempProfilePhotoPath');

    if (path != null) {
      final file = File(path);
      if (file.existsSync() && mounted) {
        setState(() {
          profilePhoto = file;
        });
      }
    }
  }

  Future<void> _clearTempProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tempProfilePhotoPath');
  }

  Future<void> _loadSavedDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('driverName');
    final savedVehicleNumber = prefs.getString('vehicleNumber');

    if (savedName != null) {
      _nameController.text = savedName;
    }
    if (savedVehicleNumber != null) {
      _vehicleNumberController.text = savedVehicleNumber;
    }

    _detailsSaved = (savedName != null && savedVehicleNumber != null);
  }

  Future<void> _saveDriverDetails() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => isUploading = true);

    try {
      final phoneNumber = await getPhoneNumber();
      if (phoneNumber == null) {
        throw Exception("Phone number not found");
      }

      final body = {
        "phoneNumber": phoneNumber,
        "name": _nameController.text.trim(),
        "vehicleNumber": _vehicleNumberController.text.trim().toUpperCase(),
        "vehicleType": vehicleType,
      };

      await ApiService.instance.postJson('/api/driver/updateProfile', body);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driverName', _nameController.text.trim());
      await prefs.setString(
        'vehicleNumber',
        _vehicleNumberController.text.trim().toUpperCase(),
      );

      setState(() {
        _detailsSaved = true;
        currentStep = 1;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Details saved successfully'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Error saving driver details: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save details: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => isUploading = false);
    }
  }

  Future<void> _loadVehicleTypeAndInitialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVehicleType = prefs.getString('vehicleType');

    if (savedVehicleType != null && savedVehicleType.isNotEmpty) {
      setState(() {
        vehicleType = savedVehicleType;
        requiredDocs = getRequiredDocs(savedVehicleType);

        if (alreadyUploadedDocs.isNotEmpty) {
          for (int i = 0; i < requiredDocs.length; i++) {
            if (!alreadyUploadedDocs.contains(requiredDocs[i])) {
              currentStep = i + 1;
              break;
            }
          }
          if (currentStep == 0 &&
              alreadyUploadedDocs.length >= requiredDocs.length) {
            currentStep = requiredDocs.length + 1;
          }
        }
      });
    }
  }

  Future<String?> getToken() async =>
      await FirebaseAuth.instance.currentUser?.getIdToken();

  List<String> getRequiredDocs(String type) {
    switch (type.toLowerCase()) {
      case 'bike':
        return ['license', 'rc', 'pan', 'aadhaar'];
      case 'auto':
        return ['license', 'rc', 'pan', 'aadhaar', 'fitnesscertificate'];
      case 'car':
        return [
          'license',
          'rc',
          'pan',
          'aadhaar',
          'fitnesscertificate',
          'permit',
          'insurance',
        ];
      default:
        return [];
    }
  }

  // 🔥 HIGH QUALITY GALLERY PICKER
  Future<void> pickFromGallery(String docType, String side) async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90, // ✅ HIGH QUALITY (was 70)
      maxWidth: 2048, // ✅ LARGER (was 1280)
      maxHeight: 2048, // ✅ LARGER (was 1280)
    );

    if (picked == null || !mounted) return;

    final rawFile = File(picked.path);
    final file = await safeCopyImage(rawFile);

    // Log file size
    final fileSize = await file.length();
    debugPrint(
      "📷 Gallery image size: ${(fileSize / 1024).toStringAsFixed(0)} KB",
    );

    setState(() {
      uploadedDocs["${docType}_$side"] = file;
      extractedDataMap["${docType}_$side"] = '{}';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${docType.toUpperCase()} $side selected'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ✅ CAMERA - USING HIGH QUALITY CAMERAX
  Future<void> captureFromCamera(String docType, String side) async {
    final File? capturedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentCameraPage(docType: docType, side: side),
      ),
    );

    if (capturedFile == null || !mounted) return;

    setState(() {
      uploadedDocs["${docType}_$side"] = capturedFile;
      extractedDataMap["${docType}_$side"] = '{}';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${docType.toUpperCase()} $side captured in HD'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ✅ PROFILE PHOTO CAPTURE - USING HIGH QUALITY CAMERAX
  Future<void> captureProfilePhoto() async {
    final File? capturedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(builder: (context) => const ProfileCameraPage()),
    );

    if (capturedFile == null || !mounted) return;

    await _saveTempProfilePhoto(capturedFile.path);

    setState(() {
      profilePhoto = capturedFile;
    });
  }

  Future<void> _confirmAndUploadDocument(String docType) async {
    if (confirmedDocs[docType] == true) {
      return;
    }

    setState(() => isUploading = true);

    try {
      final phoneNumber = await getPhoneNumber();
      if (phoneNumber == null) throw Exception("Phone number not found");

      for (String side in ['front', 'back']) {
        final file = uploadedDocs["${docType}_$side"];
        if (file == null) continue;

        final request = http.MultipartRequest(
          "POST",
          Uri.parse('${AppConfig.backendBaseUrl}/api/driver/uploadDocument'),
        );

        String getMimeType(String path) {
          final ext = path.toLowerCase();
          if (ext.endsWith(".png")) return "image/png";
          if (ext.endsWith(".jpg") || ext.endsWith(".jpeg"))
            return "image/jpeg";
          if (ext.endsWith(".webp")) return "image/webp";
          return "application/octet-stream";
        }

        final mimeType = getMimeType(file.path);
        request.files.add(
          await http.MultipartFile.fromPath(
            "document",
            file.path,
            contentType: MediaType.parse(mimeType),
          ),
        );

        final backendDocType = (docTypeMapping[docType] ?? docType)
            .toLowerCase();
        request.fields['docType'] = backendDocType;
        request.fields['docSide'] = side;
        request.fields['vehicleType'] = (vehicleType ?? '').toLowerCase();
        request.fields['phoneNumber'] = phoneNumber;
        request.fields['extractedData'] =
            extractedDataMap["${docType}_$side"] ?? '{}';

        final streamed = await ApiService.instance.multipartUpload(
          '/api/driver/uploadDocument',
          request,
        );

        final res = await http.Response.fromStream(streamed);
        if (streamed.statusCode != 200) {
          throw Exception("Upload failed: ${res.body}");
        }

        setState(() {
          uploadStatus["${docType}_$side"] = true;
        });
      }

      setState(() {
        confirmedDocs[docType] = true;
      });

      if (!alreadyUploadedDocs.contains(docType)) {
        final prefs = await SharedPreferences.getInstance();
        alreadyUploadedDocs.add(docType);
        await prefs.setStringList('uploadedDocTypes', alreadyUploadedDocs);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 6),
                Text('${_getDocDisplayName(docType)} uploaded successfully!'),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }

      if (widget.preselectDocType != null) {
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint("❌ Error uploading document: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isUploading = false);
      }
    }
  }

  Future<void> uploadProfilePhoto() async {
    if (profilePhoto == null) return;

    setState(() => isUploading = true);

    try {
      // 🔐 Profile photo upload using secure environment-based URL
      // Prevents hardcoded development URLs in production
      final uploadUrl =
          '${AppConfig.backendBaseUrl}/api/driver/uploadProfilePhoto';

      final request = http.MultipartRequest("POST", Uri.parse(uploadUrl));

      String getMimeType(String path) {
        final ext = path.toLowerCase();
        if (ext.endsWith(".png")) return "image/png";
        if (ext.endsWith(".jpg") || ext.endsWith(".jpeg")) return "image/jpeg";
        return "image/jpeg";
      }

      final mimeType = getMimeType(profilePhoto!.path);

      request.files.add(
        await http.MultipartFile.fromPath(
          "image",
          profilePhoto!.path,
          contentType: MediaType.parse(mimeType),
        ),
      );

      final streamed = await ApiService.instance.multipartUpload(
        '/api/driver/uploadProfilePhoto',
        request,
      );

      if (streamed.statusCode == 200) {
        debugPrint("✅ Profile photo uploaded successfully");

        await _clearTempProfilePhoto();

        if (!mounted) return;
        setState(() {
          profilePhotoConfirmed = true;
        });

        if (widget.isReuploadingProfile && mounted) {
          Navigator.pop(context, true);
          return;
        }
      } else {
        final res = await http.Response.fromStream(streamed);
        throw Exception("Upload failed: ${res.body}");
      }
    } catch (e) {
      debugPrint("❌ Error uploading profile photo: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload profile photo: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isUploading = false);
      }
    }
  }

  // ✅ SAFE IMAGE DISPLAY WIDGET
  Widget buildSafeImage(File file, {double height = 180}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image(
        image: ResizeImage(FileImage(file), width: 1024),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: height,
            width: double.infinity,
            color: AppColors.surface,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 48, color: AppColors.error),
                const SizedBox(height: 8),
                Text("Failed to load image", style: AppTextStyles.caption),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVehicleDetailsForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.badge, size: 80, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text("Driver Details", style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(
            "Please enter your name and vehicle number",
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: _nameController,
              style: AppTextStyles.body1,
              decoration: InputDecoration(
                labelText: "Full Name",
                labelStyle: AppTextStyles.body2.copyWith(
                  color: AppColors.primary,
                ),
                hintText: "Enter your full name",
                hintStyle: AppTextStyles.body2,
                prefixIcon: Container(
                  margin: EdgeInsets.all(12),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person, color: AppColors.primary, size: 20),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                if (value.trim().length < 3) {
                  return 'Name must be at least 3 characters';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: _vehicleNumberController,
              style: AppTextStyles.body1.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                labelText: "Vehicle Number",
                labelStyle: AppTextStyles.body2.copyWith(
                  color: AppColors.primary,
                ),
                hintText: "e.g., KA01AB1234",
                hintStyle: AppTextStyles.body2,
                prefixIcon: Container(
                  margin: EdgeInsets.all(12),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.directions_car,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter vehicle number';
                }
                final regex = RegExp(r'^[A-Z]{2}\d{2}[A-Z]{0,2}\d{4}$');
                if (!regex.hasMatch(value.trim().toUpperCase())) {
                  return 'Invalid format (e.g., KA01AB1234)';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "This information will be shown to customers during rides",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isUploading ? null : _saveDriverDetails,
              icon: isUploading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.onPrimary,
                        ),
                      ),
                    )
                  : Icon(Icons.check_circle),
              label: Text(
                isUploading ? "Saving..." : "Save & Continue",
                style: AppTextStyles.button.copyWith(
                  color: AppColors.onPrimary,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDocBox(String docType) {
    final frontFile = uploadedDocs["${docType}_front"];
    final backFile = uploadedDocs["${docType}_back"];
    final isConfirmed = confirmedDocs[docType] == true;

    Widget buildSide(String side, File? file) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isConfirmed ? AppColors.success : AppColors.divider,
            width: isConfirmed ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.onSurface.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isConfirmed
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    side == 'front' ? Icons.credit_card : Icons.flip_to_back,
                    color: isConfirmed ? AppColors.success : AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${_getDocDisplayName(docType)}",
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        side.toUpperCase(),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isConfirmed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: AppColors.onPrimary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Confirmed",
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ✅ SAFE IMAGE DISPLAY
            file != null
                ? buildSafeImage(file, height: 180)
                : Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.divider,
                        width: 2,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.upload_file,
                          size: 48,
                          color: AppColors.onSurfaceTertiary,
                        ),
                        const SizedBox(height: 8),
                        Text("No file selected", style: AppTextStyles.body2),
                      ],
                    ),
                  ),
            if (file != null && !isConfirmed) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () {
                          setState(() {
                            uploadedDocs["${docType}_$side"] = null;
                            extractedDataMap["${docType}_$side"] = null;
                          });
                        },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    "Retake",
                    style: AppTextStyles.button.copyWith(fontSize: 14),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            if (file == null && !isConfirmed) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isUploading
                          ? null
                          : () => pickFromGallery(docType, side),
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: Text(
                        "Gallery",
                        style: AppTextStyles.button.copyWith(
                          color: AppColors.onPrimary,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      // ✅ CAMERA USING HIGH QUALITY CAMERAX
                      onPressed: isUploading
                          ? null
                          : () => captureFromCamera(docType, side),
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: Text(
                        "Camera",
                        style: AppTextStyles.button.copyWith(fontSize: 14),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [buildSide("front", frontFile), buildSide("back", backFile)],
    );
  }

  String _getDocDisplayName(String docType) {
    final displayNames = {
      'license': 'Driving License',
      'aadhaar': 'Aadhaar Card',
      'pan': 'PAN Card',
      'rc': 'Vehicle RC',
      'permit': 'Permit',
      'insurance': 'Insurance',
      'fitnessCertificate': 'Fitness Certificate',
    };
    return displayNames[docType] ?? docType.toUpperCase();
  }

  bool _canProceedToNext() {
    if (vehicleType == null || currentStep >= requiredDocs.length + 1) {
      return false;
    }

    if (currentStep == 0) {
      return _detailsSaved;
    }

    final docIndex = currentStep - 1;
    if (docIndex < 0 || docIndex >= requiredDocs.length) {
      return false;
    }

    final docType = requiredDocs[docIndex];

    return confirmedDocs[docType] == true ||
        alreadyUploadedDocs.contains(docType);
  }

  bool _canConfirmDocument(String docType) {
    final frontFile = uploadedDocs["${docType}_front"];
    final backFile = uploadedDocs["${docType}_back"];
    final isConfirmed = confirmedDocs[docType] == true;

    return frontFile != null && backFile != null && !isConfirmed;
  }

  Widget _buildVehicleSelectionScreen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double h = constraints.maxHeight;
        final bool isSmall = h < 600;

        final content = Column(
          children: [
            Container(
              width: double.infinity,
              height: 210,
              decoration: BoxDecoration(color: AppColors.primary),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(0),
                  bottomRight: Radius.circular(0),
                ),
                child: Image.asset(
                  'assets/images/ghumo_partner_rider.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: AppColors.background,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Select Your Vehicle Type",
                        style: AppTextStyles.heading2.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Choose the type of vehicle you'll be driving",
                        style: AppTextStyles.body2,
                      ),
                      const SizedBox(height: 40),
                      _buildVehicleTypeButton('bike'),
                      const SizedBox(height: 10),
                      _buildVehicleTypeButton('auto'),
                      const SizedBox(height: 10),
                      _buildVehicleTypeButton('car'),
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        if (isSmall) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: h),
              child: content,
            ),
          );
        }

        return content;
      },
    );
  }

  Widget buildStepContent() {
    if (vehicleType == null) {
      return const SizedBox.shrink();
    } else if (currentStep == 0) {
      return _buildVehicleDetailsForm();
    } else if (currentStep <= requiredDocs.length) {
      final docIndex = currentStep - 1;
      final docType = requiredDocs[docIndex];
      final totalDocs = requiredDocs.length;
      final canProceed = _canProceedToNext();
      final canConfirm = _canConfirmDocument(docType);
      final isConfirmed = confirmedDocs[docType] == true;
      final isAlreadyUploaded = alreadyUploadedDocs.contains(docType);
      final remainingDocs = requiredDocs
          .where(
            (doc) =>
                confirmedDocs[doc] != true &&
                !alreadyUploadedDocs.contains(doc),
          )
          .length;

      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Document $currentStep of $totalDocs",
                          style: AppTextStyles.heading3.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          remainingDocs > 0
                              ? "$remainingDocs remaining"
                              : "All documents uploaded!",
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        "${(((totalDocs - remainingDocs) / totalDocs) * 100).toStringAsFixed(0)}%",
                        style: AppTextStyles.body1.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (totalDocs - remainingDocs) / totalDocs,
                    backgroundColor: AppColors.surface,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          buildDocBox(docType),
          if (canConfirm) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Review the images carefully. Once confirmed, you cannot make changes.",
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isUploading
                    ? null
                    : () async {
                        await _confirmAndUploadDocument(docType);
                      },
                icon: isUploading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.onPrimary,
                          ),
                        ),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  isUploading ? "Uploading..." : "Confirm & Upload Document",
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.onPrimary,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!_isSingleReuploadFlow) ...[
            Builder(
              builder: (context) {
                final double horizontalPadding = 40.0;
                final double gapBetweenButtons = 12.0;
                final double maxButtonWidth = 160.0;

                final double screenWidth = MediaQuery.of(context).size.width;
                final double availableForButtons =
                    screenWidth - horizontalPadding - gapBetweenButtons;
                final bool showPrevious = currentStep > 1;
                final double buttonWidth = showPrevious
                    ? (availableForButtons / 2).clamp(96.0, maxButtonWidth)
                    : (availableForButtons * 0.85).clamp(
                        110.0,
                        maxButtonWidth + 40,
                      );

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showPrevious) ...[
                      SizedBox(
                        width: buttonWidth,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => currentStep--),
                          icon: const Icon(Icons.arrow_back),
                          label: Text(
                            "Previous",
                            style: AppTextStyles.button.copyWith(fontSize: 14),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(
                              color: AppColors.primary,
                              width: 2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: gapBetweenButtons),
                    ],
                    SizedBox(
                      width: buttonWidth,
                      child: ElevatedButton.icon(
                        onPressed: canProceed
                            ? () => setState(() => currentStep++)
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(
                          currentStep == totalDocs
                              ? "Continue"
                              : "Next Document",
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.onPrimary,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canProceed
                              ? AppColors.primary
                              : AppColors.onSurfaceSecondary,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: canProceed ? 2 : 0,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (!canProceed && !isConfirmed && !isAlreadyUploaded) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Please upload both sides and confirm to proceed",
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      );
    } else {
      // Profile Photo Step
      return Column(
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_circle,
              size: 80,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 24),
          Text("Almost Done!", style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(
            "Take your profile photo",
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.1),
                  AppColors.success.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 28,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "All Documents Uploaded",
                        style: AppTextStyles.heading3.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        Icons.description,
                        "${requiredDocs.length}",
                        "Documents",
                      ),
                      Container(width: 1, height: 30, color: AppColors.divider),
                      _buildSummaryItem(
                        Icons.check_circle_outline,
                        "100%",
                        "Complete",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: profilePhotoConfirmed
                    ? AppColors.success
                    : AppColors.divider,
                width: profilePhotoConfirmed ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                if (profilePhotoConfirmed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: AppColors.onPrimary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Photo Confirmed",
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                // ✅ SAFE PROFILE PHOTO DISPLAY
                profilePhoto != null
                    ? buildSafeImage(profilePhoto!, height: 250)
                    : Container(
                        height: 250,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.divider,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person,
                              size: 80,
                              color: AppColors.onSurfaceTertiary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Take your profile photo",
                              style: AppTextStyles.body1,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Make sure your face is clearly visible",
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                const SizedBox(height: 16),

                if (!profilePhotoConfirmed) ...[
                  if (profilePhoto != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        // ✅ RETAKE USING HIGH QUALITY CAMERAX
                        onPressed: isUploading ? null : captureProfilePhoto,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(
                          "Retake Photo",
                          style: AppTextStyles.button.copyWith(fontSize: 14),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.warning.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Once confirmed, you cannot change your photo",
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isUploading
                            ? null
                            : () async {
                                await uploadProfilePhoto();
                              },
                        icon: isUploading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.onPrimary,
                                  ),
                                ),
                              )
                            : const Icon(Icons.cloud_upload),
                        label: Text(
                          isUploading
                              ? "Uploading..."
                              : "Confirm & Upload Photo",
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        // ✅ TAKE PHOTO USING HIGH QUALITY CAMERAX
                        onPressed: isUploading ? null : captureProfilePhoto,
                        icon: const Icon(Icons.camera_alt),
                        label: Text(
                          "Take Photo",
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ],

                if (profilePhotoConfirmed) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isUploading
                          ? null
                          : () async {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => Dialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          "Finalizing registration...",
                                          style: AppTextStyles.body1,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "Please wait",
                                          style: AppTextStyles.caption,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );

                              await Future.microtask(() {});

                              if (mounted) Navigator.pop(context);

                              if (mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DocumentsReviewPage(
                                      driverId: widget.driverId,
                                    ),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.check_circle),
                      label: Text(
                        "Complete Registration",
                        style: AppTextStyles.button.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildSummaryItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.success, size: 24),
        SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.heading3.copyWith(color: AppColors.success),
        ),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  Widget _buildVehicleTypeButton(String type) {
    IconData icon;
    String label;
    String description;

    switch (type) {
      case 'bike':
        icon = Icons.two_wheeler;
        label = 'BIKE';
        description = 'Two-wheeler vehicle';
        break;
      case 'auto':
        icon = Icons.electric_rickshaw;
        label = 'AUTO';
        description = 'Auto rickshaw';
        break;
      case 'car':
        icon = Icons.directions_car;
        label = 'CAR';
        description = 'Four-wheeler vehicle';
        break;
      default:
        icon = Icons.help;
        label = type.toUpperCase();
        description = '';
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final token = await getToken();
            if (token == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Authentication error. Please login again.'),
                  backgroundColor: AppColors.error,
                ),
              );
              return;
            }

            try {
              await ApiService.instance.postJson('/api/driver/setVehicleType', {
                "vehicleType": type,
              });

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString("vehicleType", type);

              setState(() {
                vehicleType = type;
                requiredDocs = getRequiredDocs(type);
                currentStep = 0;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Vehicle type set to ${type.toUpperCase()}'),
                    ],
                  ),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to set vehicle type: $e'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 32, color: AppColors.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTextStyles.heading3),
                      SizedBox(height: 4),
                      Text(description, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (isUploading) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please wait, upload in progress"),
              duration: Duration(seconds: 2),
            ),
          );
          return false;
        }

        if (vehicleType != null && currentStep > 0) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text("Exit Registration?", style: AppTextStyles.heading3),
              content: Text(
                "Your progress will be saved. You can continue from where you left off.",
                style: AppTextStyles.body2,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    "Cancel",
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.onSurfaceSecondary,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    "Exit",
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        }

        return true;
      },
      child: vehicleType == null
          ? Scaffold(
              backgroundColor: AppColors.background,
              body: _buildVehicleSelectionScreen(),
            )
          : Scaffold(
              appBar: AppBar(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  color: AppColors.onPrimary,
                  onPressed: () async {
                    if (vehicleType != null && currentStep == 0) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('vehicleType');

                      setState(() {
                        vehicleType = null;
                        requiredDocs = [];
                        currentStep = 0;
                      });
                    } else {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                ),
                title: Text(
                  (vehicleType != null && currentStep == 0)
                      ? "Driver Details"
                      : "Driver Registration",
                  style: AppTextStyles.heading3.copyWith(
                    color: AppColors.onPrimary,
                  ),
                ),
                centerTitle: true,
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: buildStepContent(),
                ),
              ),
            ),
    );
  }
}
