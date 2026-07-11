import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:path/path.dart' as p;
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';

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

  List<Widget> _parseMarkdownWithMath(String text, String folderPath) {
    final List<Widget> widgets = [];
    final List<String> parts = text.split('\$\$');

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) continue;

      if (i % 2 == 1) {
        // Block display math $$
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  part,
                  textStyle: const TextStyle(fontSize: 18, color: Colors.white),
                  onErrorFallback: (err) => Text(part, style: const TextStyle(color: Colors.red)),
                ),
              ),
            ),
          ),
        );
      } else {
        // Standard markdown chunk (may contain inline math $)
        widgets.add(_renderMarkdownBlock(part, folderPath));
      }
    }
    return widgets;
  }

  Widget _renderMarkdownBlock(String text, String folderPath) {
    // If it contains inline math '$'
    if (text.contains('\$')) {
      final List<InlineSpan> spans = [];
      final List<String> parts = text.split('\$');
      
      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        if (i % 2 == 1) {
          // Inline Math
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Math.tex(
                part,
                textStyle: const TextStyle(fontSize: 15, color: Colors.white),
                onErrorFallback: (err) => Text(part, style: const TextStyle(color: Colors.red)),
              ),
            ),
          );
        } else {
          // Regular Text
          spans.add(TextSpan(text: part, style: TextStyle(color: Colors.grey[300])));
        }
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text.rich(
          TextSpan(children: spans),
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
      );
    }

    // Standard Markdown render with local image asset resolution
    return MarkdownBody(
      data: text,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: Colors.grey[350], fontSize: 16, height: 1.5),
        h1: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        h2: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        code: const TextStyle(backgroundColor: Colors.black38, fontFamily: 'monospace'),
      ),
      imageBuilder: (uri, title, alt) {
        // Decode and sanitize relative path
        String relativePath = Uri.decodeComponent(uri.path);
        
        // Strip leading slash or relative dots so path.join treats it as relative
        while (relativePath.startsWith('/')) {
          relativePath = relativePath.substring(1);
        }
        if (relativePath.startsWith('./')) {
          relativePath = relativePath.substring(2);
        }

        final absolutePath = p.join(folderPath, relativePath);
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
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.white, // Solid white background for transparent PDF assets
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = screenSize.width * 0.92;
    final cardHeight = screenSize.height * 0.85;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Matches PC dark theme
      body: SafeArea(
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
                    color: const Color(0xFF111928),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 25,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedCrossFade(
                      firstChild: _buildFrontFace(cardHeight, cardWidth),
                      secondChild: _buildBackFace(cardHeight, cardWidth),
                      crossFadeState: !_revealed
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      duration: const Duration(milliseconds: 300),
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
                  color: Colors.black45,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                _revealed ? 'Tap card to hide answer' : 'Tap card to reveal answer',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontFace(double cardHeight, double cardWidth) {
    return Container(
      key: const ValueKey('front'),
      height: cardHeight,
      width: cardWidth,
      padding: const EdgeInsets.all(32.0),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.help_outline, color: Theme.of(context).primaryColor, size: 48),
          const SizedBox(height: 24),
          Text(
            widget.card.question,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: widget.card.tags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Text('#$tag', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBackFace(double cardHeight, double cardWidth) {
    return Container(
      key: const ValueKey('back'),
      height: cardHeight,
      width: cardWidth,
      padding: const EdgeInsets.all(28.0),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                        style: TextStyle(color: Colors.grey[500], fontSize: 12, fontStyle: FontStyle.italic),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _parseMarkdownWithMath(_markdownContent, widget.card.folderPath),
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
