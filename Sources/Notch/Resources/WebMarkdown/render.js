function escapeHtml(value) {
  return value.replace(/[&<>"]/g, c => ({ '&': '&', '<': '<', '>': '>', '"': '"' }[c]));
}

function escapeHtmlKeepMath(value) {
  // Extract inline math before HTML escaping so KaTeX output stays raw
  const inline = [];
  value = value.replace(/(^|[^\\$])\$([^\n$]+?)\$/g, (match, prefix, formula) => {
    const id = '__MI' + inline.length + '__';
    try {
      inline.push({ id, html: katex.renderToString(formula.trim(), { displayMode: false, throwOnError: false }) });
    } catch (e) {
      inline.push({ id, html: '<code>' + escapeHtml(formula.trim()) + '</code>' });
    }
    return prefix + id;
  });

  // Escape HTML in remaining text
  let escaped = escapeHtml(value);

  // Restore inline math
  inline.forEach(({ id, html: m }) => { escaped = escaped.split(id).join(m); });
  return escaped;
}

function inlineMarkdown(htmlEscapedText) {
  // These are already HTML-escaped at this point, just convert markdown syntax
  return htmlEscapedText
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>');
}

function renderMarkdownBlocks(source) {
  const lines = source.replace(/\r\n/g, '\n').split('\n');
  let html = '';
  let paragraph = [];
  let inCode = false;
  let codeLanguage = '';
  let codeLines = [];

  function flushParagraph() {
    if (paragraph.length === 0) return;
    const text = inlineMarkdown(escapeHtmlKeepMath(paragraph.join('\n')));
    html += '<p>' + text + '</p>';
    paragraph = [];
  }

  function flushCode() {
    const escapedCode = escapeHtml(codeLines.join('\n'));
    html += '<pre><code class="language-' + escapeHtml(codeLanguage) + '">' + escapedCode + '</code></pre>';
    codeLines = [];
    codeLanguage = '';
  }

  function isTableSeparator(line) {
    const cells = line.trim().replace(/^\||\|$/g, '').split('|');
    return cells.every(cell => /^:?\s*-{3,}\s*:?$/.test(cell.trim()));
  }

  function renderMathBlock(formula) {
    try {
      return katex.renderToString(formula.trim(), { displayMode: true, throwOnError: false });
    } catch (e) {
      return '<pre><code>' + escapeHtml(formula.trim()) + '</code></pre>';
    }
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    if (trimmed.startsWith('```')) {
      if (inCode) {
        flushCode();
        inCode = false;
      } else {
        flushParagraph();
        inCode = true;
        codeLanguage = trimmed.slice(3).trim();
      }
      continue;
    }

    if (inCode) {
      codeLines.push(line);
      continue;
    }

    // Single-line math block: $$formula$$
    if (trimmed.startsWith('$$') && trimmed.endsWith('$$') && trimmed.length > 4) {
      flushParagraph();
      html += '<div class="katex-display">' + renderMathBlock(trimmed.slice(2, -2)) + '</div>';
      continue;
    }

    // Multi-line math block: starts with $$ and ends with $$
    if (trimmed.startsWith('$$')) {
      flushParagraph();
      const formula = [trimmed.slice(2)];
      while (i + 1 < lines.length) {
        i += 1;
        const curr = lines[i].trim();
        if (curr.endsWith('$$')) {
          formula.push(curr.replace(/\$\$\s*$/, ''));
          break;
        }
        formula.push(lines[i]);
      }
      html += '<div class="katex-display">' + renderMathBlock(formula.join('\n')) + '</div>';
      continue;
    }

    if (/^#{1,6}\s+/.test(trimmed)) {
      flushParagraph();
      const level = trimmed.match(/^#+/)[0].length;
      html += '<h' + level + '>' + escapeHtmlKeepMath(trimmed.replace(/^#{1,6}\s+/, '')) + '</h' + level + '>';
      continue;
    }

    if (trimmed.startsWith('> ')) {
      flushParagraph();
      html += '<blockquote>' + escapeHtmlKeepMath(trimmed.slice(2)) + '</blockquote>';
      continue;
    }

    if (trimmed.includes('|') && i + 1 < lines.length && isTableSeparator(lines[i + 1])) {
      flushParagraph();
      const headers = trimmed.replace(/^\||\|$/g, '').split('|').map(cell => cell.trim());
      i += 1;
      const rows = [];
      while (i + 1 < lines.length && lines[i + 1].includes('|') && !lines[i + 1].trim().startsWith('```')) {
        i += 1;
        const rowText = lines[i].trim();
        if (isTableSeparator(rowText)) break;
        rows.push(rowText.replace(/^\||\|$/g, '').split('|').map(cell => cell.trim()));
      }
      html += '<table><thead><tr>' + headers.map(cell => '<th>' + escapeHtmlKeepMath(cell) + '</th>').join('') + '</tr></thead><tbody>';
      html += rows.map(row => '<tr>' + row.map(cell => '<td>' + escapeHtmlKeepMath(cell) + '</td>').join('') + '</tr>').join('');
      html += '</tbody></table>';
      continue;
    }

    if (trimmed === '') {
      flushParagraph();
    } else {
      paragraph.push(line);
    }
  }

  if (inCode) flushCode();
  flushParagraph();
  return html;
}

window.renderMarkdown = function(payload) {
  document.documentElement.style.setProperty('--max-width', payload.maxWidth || '100%');
  document.body.style.fontSize = payload.proseFontSize + 'px';
  const html = renderMarkdownBlocks(payload.text || '');
  const root = document.getElementById('root');
  root.innerHTML = '<div class="markdown ' + (payload.isUser ? 'user ' : '') + (payload.maxWidth ? 'hug' : '') + '">' + html + '</div>';
  if (window.hljs) root.querySelectorAll('pre code').forEach(block => {
    if (block.className && block.className.startsWith('language-')) hljs.highlightElement(block);
  });
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.height) {
    window.webkit.messageHandlers.height.postMessage(Math.max(24, Math.ceil(document.documentElement.scrollHeight)));
  }
}