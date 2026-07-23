import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

String _defaultUploadUrl() {
  const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  if (configuredBaseUrl.isNotEmpty) {
    return configuredBaseUrl;
  }

  if (kIsWeb) {
    return 'http://localhost:8000/api/v1/upload-pdf';
  }

  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000/api/v1/upload-pdf';
  }

  return 'http://localhost:8000/api/v1/upload-pdf';
}

class PDFUploadScreen extends StatefulWidget {
  const PDFUploadScreen({super.key});

  @override
  State<PDFUploadScreen> createState() => _PDFUploadScreenState();
}

class _PDFUploadScreenState extends State<PDFUploadScreen> {
  static const _defaultUploadPath = '/api/v1/upload-pdf';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _backendUrlController = TextEditingController(
    text: _defaultUploadUrl(),
  );
  final TextEditingController _courseNameController = TextEditingController(
    text: 'Ayrık Matematik',
  );
  final TextEditingController _userIdController = TextEditingController(
    text: 'test_user_1',
  );
  final TextEditingController _studyFocusController = TextEditingController(
    text:
        'Tanımlar, formüller, örnek sorular ve sınavda çıkma ihtimali yüksek konular',
  );

  PlatformFile? _selectedFile;
  bool _isUploading = false;

  Uri _normalizeBackendUri(Uri inputUri) {
    var normalizedUri = inputUri;

    // If user enters only a host URL, append the default upload path.
    if (normalizedUri.path.isEmpty || normalizedUri.path == '/') {
      normalizedUri = normalizedUri.replace(path: _defaultUploadPath);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (normalizedUri.host == 'localhost' ||
          normalizedUri.host == '127.0.0.1') {
        return normalizedUri.replace(host: '10.0.2.2');
      }
    }

    return normalizedUri;
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _courseNameController.dispose();
    _userIdController.dispose();
    _studyFocusController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    if (!file.name.toLowerCase().endsWith('.pdf')) {
      _showSnackBar('Lütfen yalnızca PDF dosyası seçin.', isError: true);
      return;
    }

    setState(() {
      _selectedFile = file;
    });
  }

  Future<void> _uploadPdf() async {
    if (_isUploading) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final file = _selectedFile;
    if (file == null) {
      _showSnackBar('Lütfen önce bir PDF dosyası seçin.', isError: true);
      return;
    }

    final backendUrl = _backendUrlController.text.trim();
    final parsedEndpoint = Uri.tryParse(backendUrl);
    if (parsedEndpoint == null || !parsedEndpoint.isAbsolute) {
      _showSnackBar('Geçerli bir backend URL girin.', isError: true);
      return;
    }

    final endpoint = _normalizeBackendUri(parsedEndpoint);
    if (endpoint.toString() != backendUrl) {
      _backendUrlController.text = endpoint.toString();
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final request = http.MultipartRequest('POST', endpoint);

      request.fields['course_name'] = _courseNameController.text.trim();
      request.fields['user_id'] = _userIdController.text.trim();
      request.fields['study_focus'] = _studyFocusController.text.trim();

      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          throw Exception('Web ortamında dosya verisi okunamadı.');
        }

        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: file.name),
        );
      } else {
        final path = file.path;
        if (path == null || path.isEmpty) {
          throw Exception('Dosya yolu bulunamadı.');
        }

        request.files.add(await http.MultipartFile.fromPath('file', path));
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 25),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) {
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _showSnackBar('PDF başarıyla yüklendi.');
      } else {
        final responseDetails = response.body.trim();
        _showSnackBar(
          responseDetails.isEmpty
              ? 'Yükleme başarısız oldu (${response.statusCode}).'
              : 'Yükleme başarısız oldu (${response.statusCode}): $responseDetails',
          isError: true,
        );
      }
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      _showSnackBar(
        'İstek zaman aşımına uğradı. Backend çalışıyor mu ve ağ bağlantısı açık mı kontrol edin.',
        isError: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final errorText = error.toString();
      final friendlyMessage =
          errorText.contains('Cleartext HTTP traffic') ||
              errorText.contains('CLEARTEXT communication')
          ? 'Android cleartext (http) trafiği engellenmiş görünüyor. Uygulama ayarını güncelledim; uygulamayı tamamen kapatıp tekrar çalıştırın.'
          : errorText.contains('Failed to fetch') ||
                errorText.contains('Connection refused') ||
                errorText.contains('SocketException')
          ? 'Yükleme başarısız: backend çalışmıyor veya $backendUrl adresine ulaşılamıyor. Android emülatörde host makine için 10.0.2.2 kullanın; gerçek cihazda bilgisayarınızın LAN IP adresini girin.'
          : 'Yükleme sırasında hata oluştu: $errorText';

      _showSnackBar(friendlyMessage, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }

    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7F8FC), Color(0xFFEAF1FF)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Card(
                      elevation: 10,
                      shadowColor: Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'PDF Upload',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'PDF dosyanızı yükleyin, ardından RAG sistemi için ders adı, öğrenci kimliği ve odak alanını verin.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Colors.black54,
                                            height: 1.4,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _backendUrlController,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Backend URL',
                                  hintText:
                                      'http://10.0.2.2:8000/api/v1/upload-pdf',
                                  helperText:
                                      'Sadece host da girebilirsiniz (örn: http://10.0.2.2:8000). Web/iOS için localhost, Android emülatör için 10.0.2.2, gerçek cihaz için bilgisayar IP adresi.',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final url = value?.trim() ?? '';
                                  if (url.isEmpty) {
                                    return 'Backend URL boş olamaz.';
                                  }

                                  final parsedUrl = Uri.tryParse(url);
                                  if (parsedUrl == null ||
                                      !parsedUrl.isAbsolute) {
                                    return 'Geçerli bir URL girin.';
                                  }

                                  if (parsedUrl.scheme != 'http' &&
                                      parsedUrl.scheme != 'https') {
                                    return 'URL http veya https ile başlamalıdır.';
                                  }

                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _courseNameController,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Course Name',
                                  hintText: 'Ayrık Matematik',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Course name boş olamaz.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _userIdController,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'User ID',
                                  hintText: 'test_user_1',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'User ID boş olamaz.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _studyFocusController,
                                textInputAction: TextInputAction.newline,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Study Focus',
                                  hintText:
                                      'Özet, tanımlar, formüller, çıkabilecek soru tipleri',
                                  helperText:
                                      'RAG sisteminin önemli kısımları ve sınavda çıkma olasılığı yüksek bölümleri önceliklendirmesi için kullanılır.',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Study focus boş olamaz.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              OutlinedButton.icon(
                                onPressed: _isUploading ? null : _pickPdf,
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('PDF Seç'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 18,
                                  ),
                                  side: BorderSide(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _selectedFile == null
                                      ? Colors.black.withValues(alpha: 0.03)
                                      : colorScheme.primary.withValues(
                                          alpha: 0.06,
                                        ),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: _selectedFile == null
                                        ? Colors.black12
                                        : colorScheme.primary.withValues(
                                            alpha: 0.25,
                                          ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.insert_drive_file_outlined,
                                      color: _selectedFile == null
                                          ? Colors.black38
                                          : colorScheme.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _selectedFile == null
                                            ? 'Henüz PDF seçilmedi'
                                            : '${_selectedFile!.name} • ${_formatFileSize(_selectedFile!.size)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 54,
                                child: ElevatedButton.icon(
                                  onPressed: _isUploading ? null : _uploadPdf,
                                  icon: const Icon(Icons.cloud_upload_outlined),
                                  label: Text(
                                    _isUploading ? 'Yükleniyor...' : 'Yükle',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_isUploading)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.08),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
