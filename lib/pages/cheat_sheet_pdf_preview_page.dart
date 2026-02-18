import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class CheatSheetPdfPreviewPage extends StatefulWidget {
  final String title;
  final String filePath;

  const CheatSheetPdfPreviewPage({
    super.key,
    required this.title,
    required this.filePath,
  });

  @override
  State<CheatSheetPdfPreviewPage> createState() =>
      _CheatSheetPdfPreviewPageState();
}

class _CheatSheetPdfPreviewPageState extends State<CheatSheetPdfPreviewPage> {
  final PdfViewerController _controller = PdfViewerController();

  int _currentPage = 1;
  int _totalPages = 0;

  void _goToPreviousPage() {
    if (_currentPage <= 1) return;
    _controller.previousPage();
  }

  void _goToNextPage() {
    if (_totalPages == 0 || _currentPage >= _totalPages) return;
    _controller.nextPage();
  }

  void _zoomIn() {
    final next = (_controller.zoomLevel + 0.25).clamp(1.0, 4.0);
    _controller.zoomLevel = next;
  }

  void _zoomOut() {
    final next = (_controller.zoomLevel - 0.25).clamp(1.0, 4.0);
    _controller.zoomLevel = next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _zoomOut,
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Zoom out',
          ),
          IconButton(
            onPressed: _zoomIn,
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Zoom in',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SfPdfViewer.file(
              File(widget.filePath),
              controller: _controller,
              scrollDirection: PdfScrollDirection.vertical,
              pageLayoutMode: PdfPageLayoutMode.continuous,
              canShowScrollHead: true,
              canShowPaginationDialog: true,
              onDocumentLoaded: (details) {
                if (!mounted) return;
                setState(() {
                  _totalPages = details.document.pages.count;
                  _currentPage = 1;
                });
              },
              onPageChanged: (details) {
                if (!mounted) return;
                setState(() {
                  _currentPage = details.newPageNumber;
                });
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Colors.black.withOpacity(0.08)),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _goToPreviousPage,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous page',
                  ),
                  Expanded(
                    child: Text(
                      _totalPages == 0
                          ? 'Loading...'
                          : 'Page $_currentPage of $_totalPages',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: _goToNextPage,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next page',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
