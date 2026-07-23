import React, { useState, useRef, useEffect } from 'react';
import { 
  Bold, Italic, Strikethrough, Underline, Code, 
  Heading1, Heading2, Heading3, List, ListOrdered, CheckSquare, 
  Quote, AlertCircle, Table, Link as LinkIcon, Minus, 
  Eye, Columns, Edit3, Copy, Check, FileText, Sparkles, Image as ImageIcon, Sigma
} from 'lucide-react';

// KaTeX helper for rendering math equations
const renderKatex = (mathString, displayMode = false) => {
  if (typeof window !== 'undefined' && window.katex) {
    try {
      return window.katex.renderToString(mathString, {
        displayMode,
        throwOnError: false
      });
    } catch (e) {
      return `<code class="katex-error">${mathString}</code>`;
    }
  }
  return `<code class="katex-fallback">${mathString}</code>`;
};

// Custom Markdown + KaTeX + Callouts HTML Renderer
export const renderMarkdownHTML = (markdownText, getAttachmentUrl) => {
  if (!markdownText) return '';

  let lines = markdownText.split('\n');
  let inCodeBlock = false;
  let codeBlockLang = '';
  let codeBlockBuffer = [];
  let inMathBlock = false;
  let mathBlockBuffer = [];
  let htmlLines = [];
  let inTable = false;
  let tableRows = [];

  const flushTable = () => {
    if (tableRows.length > 0) {
      let tableHtml = '<div class="editor-table-wrapper"><table>';
      tableRows.forEach((row, index) => {
        let cells = row.split('|').filter((_, i, arr) => i > 0 && i < arr.length - 1);
        if (row.includes('---')) return; // Skip separator line
        let isHeader = index === 0;
        tableHtml += '<tr>';
        cells.forEach(cell => {
          let tag = isHeader ? 'th' : 'td';
          tableHtml += `<${tag}>${formatInlineText(cell.trim(), getAttachmentUrl)}</${tag}>`;
        });
        tableHtml += '</tr>';
      });
      tableHtml += '</table></div>';
      htmlLines.push(tableHtml);
      tableRows = [];
      inTable = false;
    }
  };

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];

    // Multi-line Math Block Accumulation
    if (inMathBlock) {
      const trimmed = line.trim();
      if (trimmed === '$$' || (trimmed.endsWith('$$') && !trimmed.startsWith('$$'))) {
        const lineContent = trimmed === '$$' ? '' : trimmed.slice(0, -2).trim();
        if (lineContent) {
          mathBlockBuffer.push(lineContent);
        }
        const fullMathExpr = mathBlockBuffer.join('\n');
        htmlLines.push(`<div class="editor-math-block">${renderKatex(fullMathExpr, true)}</div>`);
        inMathBlock = false;
        mathBlockBuffer = [];
      } else {
        mathBlockBuffer.push(line);
      }
      continue;
    }

    // Code Block Toggle
    if (line.trim().startsWith('```')) {
      if (inCodeBlock) {
        let codeContent = codeBlockBuffer.join('\n');
        let escapedCode = codeContent
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;');
        htmlLines.push(`
          <div class="editor-code-block">
            <div class="code-header">
              <span class="code-lang">${codeBlockLang || 'code'}</span>
              <button class="code-copy-btn" onclick="navigator.clipboard.writeText(this.getAttribute('data-code'))" data-code="${escapedCode.replace(/"/g, '&quot;')}">
                Copy
              </button>
            </div>
            <pre><code>${escapedCode}</code></pre>
          </div>
        `);
        inCodeBlock = false;
        codeBlockBuffer = [];
        codeBlockLang = '';
      } else {
        if (inTable) flushTable();
        inCodeBlock = true;
        codeBlockLang = line.trim().replace('```', '').trim();
      }
      continue;
    }

    if (inCodeBlock) {
      codeBlockBuffer.push(line);
      continue;
    }

    // Tables
    if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
      inTable = true;
      tableRows.push(line.trim());
      continue;
    } else if (inTable) {
      flushTable();
    }

    // Block Math $$ ... $$ (Single-line or Multi-line opening)
    if (line.trim().startsWith('$$')) {
      const trimmed = line.trim();
      if (trimmed.endsWith('$$') && trimmed.length > 2) {
        let mathExpr = trimmed.slice(2, -2).trim();
        htmlLines.push(`<div class="editor-math-block">${renderKatex(mathExpr, true)}</div>`);
      } else {
        if (inTable) flushTable();
        inMathBlock = true;
        const initialContent = trimmed.slice(2).trim();
        mathBlockBuffer = initialContent ? [initialContent] : [];
      }
      continue;
    }

    // Callouts / Alerts (> [!NOTE], > [!WARNING], > [!TIP], > [!IMPORTANT])
    if (line.trim().startsWith('> [!')) {
      let match = line.trim().match(/^>\s*\[\!(NOTE|WARNING|TIP|IMPORTANT|CAUTION)\]\s*(.*)$/i);
      if (match) {
        let type = match[1].toUpperCase();
        let content = match[2];
        htmlLines.push(`
          <div class="editor-callout callout-${type.toLowerCase()}">
            <div class="callout-title">${type}</div>
            <div class="callout-content">${formatInlineText(content, getAttachmentUrl)}</div>
          </div>
        `);
        continue;
      }
    }

    // Standard Blockquotes
    if (line.trim().startsWith('> ')) {
      htmlLines.push(`<blockquote>${formatInlineText(line.trim().substring(2), getAttachmentUrl)}</blockquote>`);
      continue;
    }

    // Headings
    if (line.startsWith('# ')) {
      htmlLines.push(`<h1>${formatInlineText(line.substring(2), getAttachmentUrl)}</h1>`);
      continue;
    } else if (line.startsWith('## ')) {
      htmlLines.push(`<h2>${formatInlineText(line.substring(3), getAttachmentUrl)}</h2>`);
      continue;
    } else if (line.startsWith('### ')) {
      htmlLines.push(`<h3>${formatInlineText(line.substring(4), getAttachmentUrl)}</h3>`);
      continue;
    } else if (line.startsWith('#### ')) {
      htmlLines.push(`<h4>${formatInlineText(line.substring(5), getAttachmentUrl)}</h4>`);
      continue;
    }

    // Task Checkboxes
    if (line.trim().startsWith('- [ ] ') || line.trim().startsWith('- [x] ')) {
      let checked = line.trim().startsWith('- [x] ');
      let text = line.trim().substring(6);
      htmlLines.push(`
        <div class="editor-task-item ${checked ? 'completed' : ''}">
          <input type="checkbox" ${checked ? 'checked' : ''} disabled />
          <span>${formatInlineText(text, getAttachmentUrl)}</span>
        </div>
      `);
      continue;
    }

    // Bullet & Numbered Lists
    if (line.trim().startsWith('- ') || line.trim().startsWith('* ')) {
      htmlLines.push(`<ul><li>${formatInlineText(line.trim().substring(2), getAttachmentUrl)}</li></ul>`);
      continue;
    }
    if (/^\d+\.\s/.test(line.trim())) {
      let text = line.trim().replace(/^\d+\.\s/, '');
      htmlLines.push(`<ol><li>${formatInlineText(text, getAttachmentUrl)}</li></ol>`);
      continue;
    }

    // Horizontal Rule
    if (line.trim() === '---' || line.trim() === '***') {
      htmlLines.push('<hr class="editor-hr" />');
      continue;
    }

    // Empty lines
    if (line.trim() === '') {
      htmlLines.push('<div class="editor-empty-line"></div>');
      continue;
    }

    // Paragraph
    htmlLines.push(`<p>${formatInlineText(line, getAttachmentUrl)}</p>`);
  }

  if (inTable) flushTable();
  if (inMathBlock && mathBlockBuffer.length > 0) {
    const fullMathExpr = mathBlockBuffer.join('\n');
    htmlLines.push(`<div class="editor-math-block">${renderKatex(fullMathExpr, true)}</div>`);
  }

  return htmlLines.join('');
};

// Formatting inline text (Bold, Italic, Inline Math, Images, Links, Inline Code, Highlight)
const formatInlineText = (text, getAttachmentUrl) => {
  if (!text) return '';

  let result = text;

  // Images ![alt](src)
  result = result.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (match, alt, src) => {
    let resolvedSrc = src;
    if (getAttachmentUrl) {
      resolvedSrc = getAttachmentUrl(src);
    }
    return `<img src="${resolvedSrc}" alt="${alt}" class="editor-inline-image" />`;
  });

  // Inline Math $...$
  result = result.replace(/\$([^$]+)\$/g, (match, mathExpr) => {
    return renderKatex(mathExpr, false);
  });

  // Inline Code `...`
  result = result.replace(/`([^`]+)`/g, (match, codeSnippet) => {
    const escaped = codeSnippet.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return `<code class="editor-inline-code">${escaped}</code>`;
  });

  // Bold **...**
  result = result.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

  // Italic *...*
  result = result.replace(/\*([^*]+)\*/g, '<em>$1</em>');

  // Strikethrough ~~...~~
  result = result.replace(/~~([^~]+)~~/g, '<del>$1</del>');

  // Highlight <mark>...</mark> or ==...==
  result = result.replace(/==([^=]+)==/g, '<mark>$1</mark>');

  // Links [text](url)
  result = result.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

  return result;
};

// Slash Commands Definition
const SLASH_COMMANDS = [
  { id: 'p', label: 'Text / Paragraph', icon: FileText, syntax: '', description: 'Plain body text' },
  { id: 'h1', label: 'Heading 1', icon: Heading1, syntax: '# ', description: 'Large section heading' },
  { id: 'h2', label: 'Heading 2', icon: Heading2, syntax: '## ', description: 'Medium subsection heading' },
  { id: 'h3', label: 'Heading 3', icon: Heading3, syntax: '### ', description: 'Small heading' },
  { id: 'bullet', label: 'Bullet List', icon: List, syntax: '- ', description: 'Create a bulleted list item' },
  { id: 'number', label: 'Numbered List', icon: ListOrdered, syntax: '1. ', description: 'Create a numbered list item' },
  { id: 'task', label: 'Task List', icon: CheckSquare, syntax: '- [ ] ', description: 'Track tasks with checkboxes' },
  { id: 'quote', label: 'Quote', icon: Quote, syntax: '> ', description: 'Capture a quote or citation' },
  { id: 'callout_note', label: 'Callout Note', icon: AlertCircle, syntax: '> [!NOTE] ', description: 'Highlighted information block' },
  { id: 'callout_warning', label: 'Callout Warning', icon: AlertCircle, syntax: '> [!WARNING] ', description: 'Warning alert banner' },
  { id: 'callout_tip', label: 'Callout Tip', icon: Sparkles, syntax: '> [!TIP] ', description: 'Pro tip recommendation' },
  { id: 'code', label: 'Code Block', icon: Code, syntax: '```js\n// Write your code here\n```\n', description: 'Syntax highlighted code block' },
  { id: 'math', label: 'Math Block (KaTeX)', icon: Sigma, syntax: '$$\nE = mc^2\n$$\n', description: 'LaTeX math equation block' },
  { id: 'table', label: 'Table Template', icon: Table, syntax: '| Header 1 | Header 2 |\n| --- | --- |\n| Cell 1 | Cell 2 |\n', description: 'Insert a Markdown data table' },
  { id: 'divider', label: 'Horizontal Divider', icon: Minus, syntax: '---\n', description: 'Visual line separator' },
];

export default function MarkdownEditor({ value, onChange, getAttachmentUrl, placeholder }) {
  const [viewMode, setViewMode] = useState('split'); // 'edit', 'split', 'preview'
  const [showSlashMenu, setShowSlashMenu] = useState(false);
  const [slashQuery, setSlashQuery] = useState('');
  const [selectedSlashIndex, setSelectedSlashIndex] = useState(0);
  const textareaRef = useRef(null);
  const slashMenuRef = useRef(null);

  // Statistics calculation
  const stats = React.useMemo(() => {
    const text = value || '';
    const charCount = text.length;
    const words = text.trim() ? text.trim().split(/\s+/).length : 0;
    const lines = text ? text.split('\n').length : 0;
    const readTimeMinutes = Math.ceil(words / 200);
    return { charCount, words, lines, readTimeMinutes };
  }, [value]);

  // Insert or Wrap text helper
  const applyFormat = (prefix, suffix = '') => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const selectedText = value.substring(start, end);

    let replacement = '';
    if (selectedText) {
      replacement = `${prefix}${selectedText}${suffix}`;
    } else {
      replacement = `${prefix}${suffix}`;
    }

    const newValue = value.substring(0, start) + replacement + value.substring(end);
    onChange(newValue);

    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(
        start + prefix.length,
        start + prefix.length + selectedText.length
      );
    }, 10);
  };

  // Insert block syntax at cursor or newline
  const insertBlockSyntax = (syntax) => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    const start = textarea.selectionStart;

    // Remove the slash query if triggered by slash menu
    let currentText = value;
    let insertPos = start;

    if (showSlashMenu) {
      const lineStart = currentText.lastIndexOf('\n', start - 1) + 1;
      currentText = currentText.substring(0, lineStart) + currentText.substring(start);
      insertPos = lineStart;
    }

    const newValue = currentText.substring(0, insertPos) + syntax + currentText.substring(insertPos);
    onChange(newValue);

    setShowSlashMenu(false);
    setSlashQuery('');

    setTimeout(() => {
      textarea.focus();
      const newCursorPos = insertPos + syntax.length;
      textarea.setSelectionRange(newCursorPos, newCursorPos);
    }, 10);
  };

  // Handle keydown for slash commands navigation
  const handleKeyDown = (e) => {
    if (showSlashMenu) {
      const filtered = SLASH_COMMANDS.filter(cmd => 
        cmd.label.toLowerCase().includes(slashQuery.toLowerCase()) ||
        cmd.description.toLowerCase().includes(slashQuery.toLowerCase())
      );

      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSelectedSlashIndex(prev => (prev + 1) % Math.max(1, filtered.length));
        return;
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSelectedSlashIndex(prev => (prev - 1 + filtered.length) % Math.max(1, filtered.length));
        return;
      }
      if (e.key === 'Enter') {
        e.preventDefault();
        if (filtered[selectedSlashIndex]) {
          insertBlockSyntax(filtered[selectedSlashIndex].syntax);
        }
        return;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        setShowSlashMenu(false);
        return;
      }
    }

    // Keyboard Shortcuts (Ctrl+B, Ctrl+I, Ctrl+K)
    if (e.ctrlKey || e.metaKey) {
      if (e.key === 'b') {
        e.preventDefault();
        applyFormat('**', '**');
      } else if (e.key === 'i') {
        e.preventDefault();
        applyFormat('*', '*');
      } else if (e.key === 'k') {
        e.preventDefault();
        applyFormat('[', '](https://)');
      }
    }
  };

  // Handle textarea text change & slash detection
  const handleTextChange = (e) => {
    const val = e.target.value;
    onChange(val);

    const cursor = e.target.selectionStart;
    const textBeforeCursor = val.substring(0, cursor);
    const lastLine = textBeforeCursor.split('\n').pop();

    if (lastLine.startsWith('/')) {
      setShowSlashMenu(true);
      setSlashQuery(lastLine.substring(1));
      setSelectedSlashIndex(0);
    } else {
      setShowSlashMenu(false);
    }
  };

  // Close slash menu on outside click
  useEffect(() => {
    const handleClickOutside = (e) => {
      if (slashMenuRef.current && !slashMenuRef.current.contains(e.target)) {
        setShowSlashMenu(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const filteredCommands = SLASH_COMMANDS.filter(cmd => 
    cmd.label.toLowerCase().includes(slashQuery.toLowerCase()) ||
    cmd.description.toLowerCase().includes(slashQuery.toLowerCase())
  );

  return (
    <div className="notion-editor-container">
      {/* Editor Top Bar Controls */}
      <div className="editor-toolbar">
        {/* Formatting Tools */}
        <div className="toolbar-group">
          <button type="button" title="Bold (Ctrl+B)" className="tb-btn" onClick={() => applyFormat('**', '**')}>
            <Bold size={16} />
          </button>
          <button type="button" title="Italic (Ctrl+I)" className="tb-btn" onClick={() => applyFormat('*', '*')}>
            <Italic size={16} />
          </button>
          <button type="button" title="Strikethrough" className="tb-btn" onClick={() => applyFormat('~~', '~~')}>
            <Strikethrough size={16} />
          </button>
          <button type="button" title="Underline" className="tb-btn" onClick={() => applyFormat('<u>', '</u>')}>
            <Underline size={16} />
          </button>
          <button type="button" title="Inline Code" className="tb-btn" onClick={() => applyFormat('`', '`')}>
            <Code size={16} />
          </button>
        </div>

        <div className="toolbar-divider" />

        {/* Headings */}
        <div className="toolbar-group">
          <button type="button" title="Heading 1" className="tb-btn" onClick={() => applyFormat('# ')}>
            <Heading1 size={16} />
          </button>
          <button type="button" title="Heading 2" className="tb-btn" onClick={() => applyFormat('## ')}>
            <Heading2 size={16} />
          </button>
          <button type="button" title="Heading 3" className="tb-btn" onClick={() => applyFormat('### ')}>
            <Heading3 size={16} />
          </button>
        </div>

        <div className="toolbar-divider" />

        {/* Lists & Checklists */}
        <div className="toolbar-group">
          <button type="button" title="Bullet List" className="tb-btn" onClick={() => applyFormat('- ')}>
            <List size={16} />
          </button>
          <button type="button" title="Numbered List" className="tb-btn" onClick={() => applyFormat('1. ')}>
            <ListOrdered size={16} />
          </button>
          <button type="button" title="Task Checkbox" className="tb-btn" onClick={() => applyFormat('- [ ] ')}>
            <CheckSquare size={16} />
          </button>
        </div>

        <div className="toolbar-divider" />

        {/* Blocks & KaTeX */}
        <div className="toolbar-group">
          <button type="button" title="Quote" className="tb-btn" onClick={() => applyFormat('> ')}>
            <Quote size={16} />
          </button>
          <button type="button" title="Callout Alert" className="tb-btn" onClick={() => applyFormat('> [!NOTE] ')}>
            <AlertCircle size={16} />
          </button>
          <button type="button" title="LaTeX Math Block" className="tb-btn" onClick={() => applyFormat('$$\n', '\n$$')}>
            <Sigma size={16} />
          </button>
          <button type="button" title="Table Template" className="tb-btn" onClick={() => applyFormat('| Header 1 | Header 2 |\n| --- | --- |\n| Cell 1 | Cell 2 |\n')}>
            <Table size={16} />
          </button>
          <button type="button" title="Link (Ctrl+K)" className="tb-btn" onClick={() => applyFormat('[', '](https://)')}>
            <LinkIcon size={16} />
          </button>
        </div>

        <div className="toolbar-spacer" />

        {/* Canvas View Switcher */}
        <div className="toolbar-group view-switcher">
          <button 
            type="button" 
            className={`tb-mode-btn ${viewMode === 'edit' ? 'active' : ''}`}
            onClick={() => setViewMode('edit')}
            title="Edit Only Mode"
          >
            <Edit3 size={15} /> Edit
          </button>
          <button 
            type="button" 
            className={`tb-mode-btn ${viewMode === 'split' ? 'active' : ''}`}
            onClick={() => setViewMode('split')}
            title="Split Side-by-Side View"
          >
            <Columns size={15} /> Split
          </button>
          <button 
            type="button" 
            className={`tb-mode-btn ${viewMode === 'preview' ? 'active' : ''}`}
            onClick={() => setViewMode('preview')}
            title="Live Preview Mode"
          >
            <Eye size={15} /> Preview
          </button>
        </div>
      </div>

      {/* Editor & Preview Split Canvas */}
      <div className={`editor-workspace-canvas mode-${viewMode}`}>
        {/* Left Pane: Interactive Text Area */}
        {(viewMode === 'edit' || viewMode === 'split') && (
          <div className="editor-pane editor-input-pane">
            <textarea
              ref={textareaRef}
              className="notion-textarea"
              value={value}
              onChange={handleTextChange}
              onKeyDown={handleKeyDown}
              placeholder={placeholder || "Type your markdown content here... Tip: Type '/' to trigger block commands!"}
            />

            {/* Notion-style Floating Slash Command Menu */}
            {showSlashMenu && (
              <div className="slash-menu-popup" ref={slashMenuRef}>
                <div className="slash-menu-header">BASIC BLOCKS</div>
                {filteredCommands.length === 0 ? (
                  <div className="slash-menu-empty">No matching block found</div>
                ) : (
                  filteredCommands.map((cmd, index) => {
                    const IconComp = cmd.icon;
                    const isSelected = index === selectedSlashIndex;
                    return (
                      <div
                        key={cmd.id}
                        className={`slash-menu-item ${isSelected ? 'selected' : ''}`}
                        onClick={() => insertBlockSyntax(cmd.syntax)}
                        onMouseEnter={() => setSelectedSlashIndex(index)}
                      >
                        <div className="slash-icon-wrapper">
                          <IconComp size={16} />
                        </div>
                        <div className="slash-text-wrapper">
                          <span className="slash-label">{cmd.label}</span>
                          <span className="slash-desc">{cmd.description}</span>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            )}
          </div>
        )}

        {/* Right Pane: Live Rendered Output */}
        {(viewMode === 'preview' || viewMode === 'split') && (
          <div className="editor-pane editor-preview-pane">
            <div 
              className="preview-markdown-body"
              dangerouslySetInnerHTML={{ 
                __html: renderMarkdownHTML(value, getAttachmentUrl) || '<p class="preview-empty-hint">Live preview will render here...</p>' 
              }}
            />
          </div>
        )}
      </div>

      {/* Footer Document Stats */}
      <div className="editor-footer-stats">
        <div className="stat-pill">
          <span>Words:</span> <strong>{stats.words}</strong>
        </div>
        <div className="stat-pill">
          <span>Characters:</span> <strong>{stats.charCount}</strong>
        </div>
        <div className="stat-pill">
          <span>Lines:</span> <strong>{stats.lines}</strong>
        </div>
        <div className="stat-pill">
          <span>Est. Read Time:</span> <strong>{stats.readTimeMinutes} min</strong>
        </div>
        <div className="stat-spacer" />
        <div className="stat-hint">
          <span>Pro Tip: Press <strong>Ctrl+B</strong> (Bold), <strong>Ctrl+I</strong> (Italic), or type <strong>/</strong> for block menu</span>
        </div>
      </div>
    </div>
  );
}
