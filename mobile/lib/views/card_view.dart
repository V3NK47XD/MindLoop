import 'dart:io';
import 'package:flutter/material';
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
    final content = await StorageService().getCardMarkdownContent(widget.card);
    if (mounted) {
      setState(() {
        _markdownContent = content;
        _isLoading = false;
      });
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
                  style: const TextStyle(fontSize: 18, color: Colors.white),
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
                style: const TextStyle(fontSize: 15, color: Colors.white),
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
        // Resolve assets/page_X_img_Y.png relative to folderPath
        final relativePath = uri.path;
        final absolutePath = p.join(folderPath, relativePath);
        final file = File(absolutePath);

        if (file.existsSync()) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                file,
                fit: BoxFit.contain,
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
    final theme = Theme.of(context);
    final cardHeight = MediaQuery.of(context).size.height * 0.6;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Matches PC dark theme
      appBar: AppBar(
        title: const Text('Flashcard Review', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _revealed = !_revealed),
                  child: Container(
                    width: double.infinity,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111928).withOpacity(0.8), // Glass panel color
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) {
                          // Standard card flip animation
                          final rotateAnim = Tween(begin: 3.14, end: 0.0).animate(anim);
                          return AnimatedBuilder(
                            animation: rotateAnim,
                            child: child,
                            builder: (context, widget) {
                              final isBack = child.key == const ValueKey('back');
                              final rotationValue = isBack ? rotateAnim.value : rotateAnim.value + 3.14;
                              return Transform(
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.001)
                                  ..rotateY(rotationValue),
                                alignment: Alignment.center,
                                child: rotationValue >= 1.57 && rotationValue <= 4.71
                                    ? const SizedBox() // Hide back face when flipping
                                    : widget,
                              );
                            },
                          );
                        },
                        child: !_revealed
                            ? _buildFrontFace()
                            : _buildBackFace(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _revealed ? 'Tap card to hide answer' : 'Tap card to reveal answer',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontFace() {
    return Container(
      key: const ValueKey('front'),
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

  Widget _buildBackFace() {
    return Container(
      key: const ValueKey('back'),
      // Keep alignment transformation corrected for Y rotation (horizontal flip)
      transform: Matrix4.rotationY(3.14)..translate(-MediaQuery.of(context).size.width + 40, 0),
      transformAlignment: Alignment.center,
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
                        'Ref: ${widget.card.sourcePdf} (Line ${widget.card.pdfRefLine})',
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
