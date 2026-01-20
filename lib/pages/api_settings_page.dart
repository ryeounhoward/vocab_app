import 'package:flutter/material.dart';

import '../database/db_helper.dart';

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final DBHelper _dbHelper = DBHelper();

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();

  // Default button image if none selected yet
  final List<String> _buttonImages = const <String>[
    'assets/images/gemini-1.png',
    'assets/images/gemini-2.png',
    'assets/images/gemini-3.png',
    'assets/images/gemini-4.png',
  ];

  String _selectedButtonImage = 'assets/images/gemini-2.png';
  bool _obscureKey = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final String? storedKey = await _dbHelper.getPreference('gemini_api_key');
    final String? storedModel = await _dbHelper.getPreference('gemini_model');
    final String? storedButton = await _dbHelper.getPreference(
      'gemini_button_image',
    );

    if (!mounted) return;

    setState(() {
      if (storedKey != null) {
        _apiKeyController.text = storedKey;
      }
      if (storedModel != null && storedModel.isNotEmpty) {
        _modelController.text = storedModel;
      } else {
        _modelController.text = 'gemini-2.5-flash';
      }
      if (storedButton != null && storedButton.isNotEmpty) {
        _selectedButtonImage = storedButton;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final String apiKey = _apiKeyController.text.trim();
    final String model = _modelController.text.trim();

    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Gemini API key.')),
      );
      return;
    }

    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a model name.')),
      );
      return;
    }

    await _dbHelper.setPreference('gemini_api_key', apiKey);
    await _dbHelper.setPreference('gemini_model', model);
    await _dbHelper.setPreference('gemini_button_image', _selectedButtonImage);

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('API settings saved.')));

    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Settings'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gemini API Key',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Enter your Gemini API key',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureKey = !_obscureKey;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Model',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _modelController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. gemini-2.5-flash',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Customize AI Button',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose which Gemini button image to use on the Add Word page.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _buttonImages.map((path) {
                      final bool isSelected = path == _selectedButtonImage;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedButtonImage = path;
                          });
                        },
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.indigo
                                  : Colors.grey[300]!,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.asset(path, fit: BoxFit.contain),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _saveSettings,
                      child: const Text(
                        'SAVE SETTINGS',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
