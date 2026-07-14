import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/widgets/paper_background.dart';

class CardView extends StatefulWidget {
  final Flashcard card;

  const CardView({Key? key, required this.card}) : super(key: key);

  @override
  State<CardView> createState() => _CardViewState();
}

class _CardViewState extends State<CardView> {
  bool _revealed = false;
  String _markdownContent = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final content = await StorageService().getCardMarkdownContent(widget.card);
      if (mounted) {
        setState(() {
          _markdownContent = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading card markdown: $e");
      if (mounted) {
        setState(() {
          _markdownContent = "Error loading content: $e";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = screenSize.width * 0.92;
    final cardHeight = screenSize.height * 0.82;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final panelBg = isDark ? const Color(0xFF111827) : Colors.white;
    final borderColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      body: PaperBackground(
        isDark: isDark,
        child: SafeArea(
          child: Stack(
            children: [
              // Center card container
              Center(
                child: GestureDetector(
                  onTap: () => setState(() => _revealed = !_revealed),
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      color: panelBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor, width: 3.0),
                      boxShadow: [
                        BoxShadow(
                          color: borderColor,
                          offset: const Offset(6, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedCrossFade(
                        firstChild: _buildFrontFace(cardHeight, cardWidth, textColor, borderColor, panelBg),
                        secondChild: _buildBackFace(cardHeight, cardWidth, textColor, borderColor, panelBg),
                        crossFadeState: !_revealed
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                        duration: const Duration(milliseconds: 250),
                        firstCurve: Curves.easeInOut,
                        secondCurve: Curves.easeInOut,
                        sizeCurve: Curves.easeInOut,
                      ),
                    ),
                  ),
                ),
              ),
              // Floating back button on the top left
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: panelBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 2.0),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.arrow_back, color: textColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              // Helper text at the bottom
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Text(
                  _revealed ? 'TAP CARD TO HIDE ANSWER' : 'TAP CARD TO REVEAL ANSWER',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFrontFace(double cardHeight, double cardWidth, Color textColor, Color borderColor, Color panelBg) {
    return Container(
      key: const ValueKey('front'),
      height: cardHeight,
      width: cardWidth,
      padding: const EdgeInsets.all(32.0),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.help_outline, color: textColor, size: 52),
          const SizedBox(height: 24),
          Text(
            widget.card.question,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: widget.card.tags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: panelBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: borderColor, width: 2.0),
              ),
              child: Text(
                '#$tag',
                style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w900),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBackFace(double cardHeight, double cardWidth, Color textColor, Color borderColor, Color panelBg) {
    return Container(
      key: const ValueKey('back'),
      height: cardHeight,
      width: cardWidth,
      padding: const EdgeInsets.all(24.0),
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: borderColor))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ref: ${widget.card.sourcePdf} (Page ${widget.card.pdfRefLine})',
                        style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Divider(color: borderColor, thickness: 2.0, height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: SmoothMarkdown(
                      data: _markdownContent,
                      config: const MarkdownConfig(
                        enableLatex: true,
                        enableCodeHighlight: true,
                      ),
                      styleSheet: MarkdownStyleSheet(
                        paragraphStyle: TextStyle(color: textColor.withOpacity(0.85), fontSize: 16, height: 1.5, fontWeight: FontWeight.bold),
                        h1Style: TextStyle(color: textColor, fontWeight: FontWeight.w900),
                        h2Style: TextStyle(color: textColor, fontWeight: FontWeight.w900),
                        inlineCodeStyle: const TextStyle(backgroundColor: Colors.black12, fontFamily: 'monospace'),
                      ),
                      imageBuilder: (url, title, alt) {
                        String relativePath = Uri.decodeComponent(url);
                        while (relativePath.startsWith('/')) {
                          relativePath = relativePath.substring(1);
                        }
                        if (relativePath.startsWith('./')) {
                          relativePath = relativePath.substring(2);
                        }

                        final absolutePath = p.join(widget.card.folderPath, relativePath);
                        final file = File(absolutePath);

                        if (file.existsSync()) {
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ImageZoomViewer(file: file),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(8.0),
                                  child: Hero(
                                     tag: absolutePath,
                                     child: Image.file(
                                       file,
                                       fit: BoxFit.contain,
                                     ),
                                   ),
                                 ),
                               ),
                             ),
                           );
                         }
                         return Padding(
                           padding: const EdgeInsets.symmetric(vertical: 8),
                           child: Row(
                             children: [
                               const Icon(Icons.broken_image, color: Colors.grey),
                               const SizedBox(width: 8),
                               Text('Asset missing: $relativePath', style: const TextStyle(color: Colors.grey)),
                             ],
                           ),
                         );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// Pinch-to-zoom Image Viewer with Hero transitions
class ImageZoomViewer extends StatelessWidget {
  final File file;

  const ImageZoomViewer({Key? key, required this.file}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Container(
                color: Colors.white, // Standard white background for PDF images
                padding: const EdgeInsets.all(16.0),
                child: Hero(
                  tag: file.path,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            left: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
