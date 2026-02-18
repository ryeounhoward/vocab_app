import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CheatSheetHtmlPreviewPage extends StatefulWidget {
  final String title;
  final String filePath;

  const CheatSheetHtmlPreviewPage({
    super.key,
    required this.title,
    required this.filePath,
  });

  @override
  State<CheatSheetHtmlPreviewPage> createState() =>
      _CheatSheetHtmlPreviewPageState();
}

class _CheatSheetHtmlPreviewPageState extends State<CheatSheetHtmlPreviewPage> {
  bool _loading = true;
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHtml();
  }

  Future<void> _loadHtml() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        setState(() {
          _error = 'HTML file not found.';
          _loading = false;
        });
        return;
      }

      final rawHtml = await file.readAsString();

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (!mounted) return;
              setState(() {
                _loading = true;
              });
            },
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() {
                _loading = false;
              });
            },
            onWebResourceError: (error) {
              if (!mounted) return;
              setState(() {
                _error = 'Failed to render HTML (${error.errorCode}).';
                _loading = false;
              });
            },
          ),
        )
        ..loadHtmlString(rawHtml);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _error = null;
      });
    } on MissingPluginException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'WebView plugin is not available yet. ${e.message ?? ''}'
            .trim();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to open HTML preview: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : Stack(
                children: [
                  if (_controller != null)
                    WebViewWidget(controller: _controller!),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
      ),
    );
  }
}
