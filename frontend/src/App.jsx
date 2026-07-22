import React, { useState, useEffect, useRef } from 'react';
import MarkdownEditor, { renderMarkdownHTML } from './components/MarkdownEditor';
import { 
  FileUp, 
  Smartphone, 
  RefreshCw, 
  CheckCircle2, 
  DownloadCloud, 
  Trash2, 
  Plus, 
  Eye, 
  EyeOff, 
  FileText, 
  Layers, 
  Tag, 
  Sparkles,
  Link,
  Check,
  AlertTriangle
} from 'lucide-react';

const API_BASE = 'http://localhost:6769';

// Markdown & LaTeX Renderers using global window.katex
function MathBlock({ tex }) {
  const containerRef = useRef(null);

  useEffect(() => {
    if (containerRef.current && window.katex) {
      try {
        window.katex.render(tex, containerRef.current, {
          displayMode: true,
          throwOnError: false
        });
      } catch (err) {
        console.error("KaTeX error:", err);
      }
    }
  }, [tex]);

  return <div ref={containerRef} style={{ margin: '12px 0', overflowX: 'auto', textAlign: 'center' }} />;
}

function InlineMath({ tex }) {
  const elRef = useRef(null);

  useEffect(() => {
    if (elRef.current && window.katex) {
      try {
        window.katex.render(tex, elRef.current, {
          displayMode: false,
          throwOnError: false
        });
      } catch (err) {
        console.error("KaTeX error:", err);
      }
    }
  }, [tex]);

  return <span ref={elRef} style={{ padding: '0 2px' }} />;
}

function parseBold(txt) {
  if (!txt) return "";
  const boldParts = txt.split(/\*\*/g);
  return boldParts.map((part, index) => {
    if (index % 2 === 1) {
      return <strong key={index} style={{ fontWeight: '600', color: '#fff' }}>{part}</strong>;
    }
    return part;
  });
}

function FormattedText({ text, cardId }) {
  const imgRegex = /!\[(.*?)\]\((.*?)\)/g;
  const matches = [...text.matchAll(imgRegex)];
  
  if (matches.length > 0) {
    const parts = [];
    let lastIndex = 0;
    
    matches.forEach((match, idx) => {
      const [fullMatch, alt, src] = match;
      const matchIndex = match.index;
      
      if (matchIndex > lastIndex) {
        parts.push(<span key={`t-${idx}`}>{parseBold(text.substring(lastIndex, matchIndex))}</span>);
      }
      
      let resolvedSrc = src;
      if (src.startsWith('assets/')) {
        const filename = src.substring(7);
        resolvedSrc = `${API_BASE}/api/cards/${cardId}/assets/${filename}`;
      }
      
      parts.push(
        <div key={`img-${idx}`} style={{ margin: '14px 0', textAlign: 'center' }}>
          <img 
            src={resolvedSrc} 
            alt={alt} 
            style={{ 
              maxWidth: '100%', 
              maxHeight: '280px',
              borderRadius: '8px', 
              border: '1px solid var(--panel-border)', 
              boxShadow: '0 4px 16px rgba(0,0,0,0.2)' 
            }} 
          />
          {alt && <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '4px' }}>{alt}</div>}
        </div>
      );
      
      lastIndex = matchIndex + fullMatch.length;
    });
    
    if (lastIndex < text.length) {
      parts.push(<span key="t-end">{parseBold(text.substring(lastIndex))}</span>);
    }
    
    return <>{parts}</>;
  }
  
  return <>{parseBold(text)}</>;
}

function InlineMarkdown({ text, cardId }) {
  if (!text) return null;
  const mathParts = text.split(/\$/g);
  return (
    <>
      {mathParts.map((part, index) => {
        if (index % 2 === 1) {
          return <InlineMath key={index} tex={part} />;
        }
        return <FormattedText key={index} text={part} cardId={cardId} />;
      })}
    </>
  );
}

function TextBlock({ text, cardId }) {
  const lines = text.split('\n');
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
      {lines.map((line, idx) => {
        const trimmed = line.trim();
        if (!trimmed) return <div key={idx} style={{ height: '4px' }} />;
        
        if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
          return (
            <ul key={idx} style={{ margin: 0, paddingLeft: '20px' }}>
              <li style={{ color: 'var(--text-main)' }}>
                <InlineMarkdown text={trimmed.substring(2)} cardId={cardId} />
              </li>
            </ul>
          );
        }
        
        if (trimmed.startsWith('### ')) {
          return <h4 key={idx} style={{ margin: '12px 0 4px', fontSize: '0.95rem', fontWeight: '600', color: '#fff' }}><InlineMarkdown text={trimmed.substring(4)} cardId={cardId} /></h4>;
        }
        if (trimmed.startsWith('## ')) {
          return <h3 key={idx} style={{ margin: '16px 0 6px', fontSize: '1.1rem', fontWeight: '600', color: '#fff' }}><InlineMarkdown text={trimmed.substring(3)} cardId={cardId} /></h3>;
        }
        if (trimmed.startsWith('# ')) {
          return <h2 key={idx} style={{ margin: '20px 0 8px', fontSize: '1.25rem', fontWeight: '700', color: '#fff' }}><InlineMarkdown text={trimmed.substring(2)} cardId={cardId} /></h2>;
        }
        
        return (
          <p key={idx} style={{ margin: 0, lineHeight: '1.5', color: 'var(--text-secondary)' }}>
            <InlineMarkdown text={line} cardId={cardId} />
          </p>
        );
      })}
    </div>
  );
}

function MarkdownRenderer({ content, cardId }) {
  if (!content) return null;

  const resolveUrl = (src) => {
    if (!src) return '';
    if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:')) {
      return src;
    }
    const filename = src.replace(/^assets\//, '');
    if (cardId) {
      return `${API_BASE}/api/cards/${cardId}/assets/${filename}`;
    }
    return src;
  };

  return (
    <div 
      className="preview-markdown-body"
      dangerouslySetInnerHTML={{ 
        __html: renderMarkdownHTML(content, resolveUrl) 
      }}
    />
  );
}

// Simple, robust client-side BM25 ranker for searching questions + PDF sources
function bm25Search(documents, query, k1 = 1.2, b = 0.75) {
  if (!query || !query.trim()) return documents;

  const tokenize = (text) => {
    return text.toLowerCase()
      .replace(/[^\w\s]/g, '')
      .split(/\s+/)
      .filter(token => token.length > 0);
  };

  const queryTerms = tokenize(query);
  if (queryTerms.length === 0) return documents;

  const N = documents.length;
  
  const docsData = documents.map(doc => {
    const textToSearch = `${doc.question} ${doc.source_pdf || ''}`;
    const tokens = tokenize(textToSearch);
    const tf = {};
    tokens.forEach(token => {
      tf[token] = (tf[token] || 0) + 1;
    });
    return {
      doc,
      length: tokens.length,
      tf
    };
  });

  const avgdl = docsData.reduce((sum, d) => sum + d.length, 0) / N || 1;

  const df = {};
  queryTerms.forEach(term => {
    df[term] = docsData.filter(d => d.tf[term] > 0).length;
  });

  const idf = {};
  queryTerms.forEach(term => {
    const n = df[term] || 0;
    idf[term] = Math.log((N - n + 0.5) / (n + 0.5) + 1);
  });

  const scoredDocs = docsData.map(d => {
    let score = 0;
    queryTerms.forEach(term => {
      const f = d.tf[term] || 0;
      if (f > 0) {
        const idfVal = idf[term];
        const numerator = f * (k1 + 1);
        const denominator = f + k1 * (1 - b + b * (d.length / avgdl));
        score += idfVal * (numerator / denominator);
      }
    });
    return {
      doc: d.doc,
      score
    };
  });

  return scoredDocs
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .map(item => item.doc);
}

function App() {
  // Library & Device state
  const [pcCards, setPcCards] = useState([]);
  const [phoneCards, setPhoneCards] = useState([]);
  const [pairedDevices, setPairedDevices] = useState([]);
  const [activeDevice, setActiveDevice] = useState(null);

  // Sync ref to keep activeDevice state fresh inside long-polling watch closures
  const activeDeviceRef = useRef(null);
  useEffect(() => {
    activeDeviceRef.current = activeDevice;
  }, [activeDevice]);
  
  // Selection and Visibility
  const [selectedHashes, setSelectedHashes] = useState(new Set());
  const [showSyncedCards, setShowSyncedCards] = useState(true);
  
  // Modals & Forms
  const [showPairModal, setShowPairModal] = useState(false);
  const [pairingInfo, setPairingInfo] = useState(null);
  const [selectedModel, setSelectedModel] = useState('gemma-4-31b-it');
  const [isGenerating, setIsGenerating] = useState(false);
  const [generationLogs, setGenerationLogs] = useState('');
  const [isRefreshing, setIsRefreshing] = useState(false);
  
  // Card viewer details modal
  const [selectedCard, setSelectedCard] = useState(null);
  const [cardContent, setCardContent] = useState(null);
  const [isLoadingContent, setIsLoadingContent] = useState(false);
  
  // Search & Generator Modal states
  const [showGeneratorModal, setShowGeneratorModal] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedFilterTag, setSelectedFilterTag] = useState('All');
  
  // Navigation & Workspace states
  const [currentView, setCurrentView] = useState('sync-center'); // 'sync-center', 'pc-manage', 'phone-manage', 'workspace'
  const [selectedWorkspaceCard, setSelectedWorkspaceCard] = useState(null);
  const [wsQuestion, setWsQuestion] = useState('');
  const [wsAnswer, setWsAnswer] = useState('');
  const [wsTag, setWsTag] = useState('');
  const [wsSourcePdf, setWsSourcePdf] = useState('Manual');
  const [wsPdfRefLine, setWsPdfRefLine] = useState(0);
  const [wsError, setWsError] = useState('');
  const [isSavingWs, setIsSavingWs] = useState(false);
  const [wsImages, setWsImages] = useState([]);
  const [wsExistingAttachments, setWsExistingAttachments] = useState([]);
  
  // File drag & drop
  const [dragActive, setDragActive] = useState(false);
  const fileInputRef = useRef(null);

  // Compute unique tags from PC cards
  const allTags = React.useMemo(() => {
    const tags = new Set();
    pcCards.forEach(c => {
      if (c.tags) {
        c.tags.forEach(t => tags.add(t));
      }
    });
    return Array.from(tags);
  }, [pcCards]);

  // Filtered PC cards
  const filteredPcCards = React.useMemo(() => {
    let cards = pcCards;
    
    // Apply synced/unsynced filter
    if (!showSyncedCards) {
      cards = cards.filter(c => c.sync_status !== 'synced');
    }
    
    // Apply BM25 search ranking
    if (searchQuery.trim()) {
      cards = bm25Search(cards, searchQuery);
    }
    
    // Apply tag filter
    if (selectedFilterTag && selectedFilterTag !== "All") {
      cards = cards.filter(c => c.tags && c.tags.includes(selectedFilterTag));
    }
    
    return cards;
  }, [pcCards, searchQuery, selectedFilterTag, showSyncedCards]);

  // Fetch card content (markdown answer) when a card is clicked
  useEffect(() => {
    if (selectedCard) {
      fetchCardContent(selectedCard.id);
    } else {
      setCardContent(null);
    }
  }, [selectedCard]);

  const fetchCardContent = async (hash) => {
    setIsLoadingContent(true);
    try {
      const res = await fetch(`${API_BASE}/api/cards/${hash}/content`);
      if (res.ok) {
        const data = await res.json();
        setCardContent(data);
      } else {
        console.error("Failed to fetch card content");
      }
    } catch (err) {
      console.error("Network error fetching card content:", err);
    } finally {
      setIsLoadingContent(false);
    }
  };

  // Load initial PC data and check pairing
  useEffect(() => {
    fetchPcLibrary();
    fetchPairedDevices();

    // Set up long polling watch listener for real-time pairing/sync updates
    let activeWatch = true;
    const watchDevices = async () => {
      while (activeWatch) {
        try {
          const res = await fetch(`${API_BASE}/api/pairing/watch?timeout=25`);
          if (!activeWatch) break;
          if (res.ok) {
            const data = await res.json();
            setPairedDevices(data);
            
            // Auto-select active device or first device from fresh list
            let nextActive = null;
            if (data.length > 0) {
              const currentActive = activeDeviceRef.current;
              const stillExists = data.find(d => currentActive && d.device_id === currentActive.device_id);
              nextActive = stillExists || data[0];
            }
            
            setActiveDevice(nextActive);
            
            // Trigger comparison update immediately using the active device ID
            if (nextActive) {
              fetchComparison(nextActive.device_id);
            } else {
              setPhoneCards([]);
              setSelectedHashes(new Set());
            }
          }
        } catch (err) {
          console.error("Watch failed, retrying in 5s...", err);
          await new Promise(resolve => setTimeout(resolve, 5000));
        }
      }
    };
    
    watchDevices();
    
    return () => {
      activeWatch = false;
    };
  }, []);

  // Fetch comparison when active device changes
  useEffect(() => {
    if (activeDevice) {
      fetchComparison();
    } else {
      setPhoneCards([]);
      setSelectedHashes(new Set());
    }
  }, [activeDevice]);

  const handleRefreshAll = async () => {
    setIsRefreshing(true);
    try {
      await Promise.all([
        fetchPcLibrary(),
        fetchPairedDevices(),
        activeDevice ? fetchComparison() : Promise.resolve()
      ]);
    } catch (err) {
      console.error("Refresh failed:", err);
    } finally {
      setIsRefreshing(false);
    }
  };

  const fetchPcLibrary = async () => {
    try {
      const res = await fetch(`${API_BASE}/api/cards`);
      if (res.ok) {
        const data = await res.json();
        setPcCards(data);
      }
    } catch (err) {
      console.error("Failed to fetch PC library:", err);
    }
  };

  const fetchPairedDevices = async () => {
    try {
      const res = await fetch(`${API_BASE}/api/pairing/devices`);
      if (res.ok) {
        const data = await res.json();
        setPairedDevices(data);
        
        // Auto-select first device if none is selected
        if (data.length > 0 && !activeDevice) {
          setActiveDevice(data[0]);
        }
      }
    } catch (err) {
      console.error("Failed to fetch paired devices:", err);
    }
  };

  const fetchComparison = async (deviceId = null) => {
    const targetId = deviceId || (activeDeviceRef.current ? activeDeviceRef.current.device_id : null);
    if (!targetId) return;
    try {
      const res = await fetch(`${API_BASE}/api/sync/device/${targetId}/compare`);
      if (res.ok) {
        const data = await res.json();
        setPcCards(data.pc_cards || []);
        setPhoneCards(data.phone_cards || []);
      }
    } catch (err) {
      console.error("Failed to fetch comparison:", err);
    }
  };

  // Open Pairing QR Modal
  const handleOpenPairing = async () => {
    try {
      const res = await fetch(`${API_BASE}/api/pairing/info`);
      if (res.ok) {
        const data = await res.json();
        setPairingInfo(data);
        setShowPairModal(true);
      }
    } catch (err) {
      alert("Failed to connect to backend server. Make sure FastAPI is running on port 6769.");
    }
  };

  // Handle PDF Drag & Drop
  const handleDrag = (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true);
    } else if (e.type === "dragleave") {
      setDragActive(false);
    }
  };

  const handleDrop = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);
    
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      uploadPdf(e.dataTransfer.files[0]);
    }
  };

  const handleFileChange = (e) => {
    if (e.target.files && e.target.files[0]) {
      uploadPdf(e.target.files[0]);
    }
  };

  const uploadPdf = async (file) => {
    if (!file.name.endsWith('.pdf')) {
      alert("Please select a PDF file.");
      return;
    }
    
    setIsGenerating(true);
    setGenerationLogs(`Uploading ${file.name} to FastAPI backend...\n`);
    
    // Extract unique tags from PC and Phone cards to pass to backend generator
    const existingTagsSet = new Set();
    pcCards.forEach(c => c.tags?.forEach(t => existingTagsSet.add(t)));
    phoneCards.forEach(c => c.tags?.forEach(t => existingTagsSet.add(t)));
    const existingTags = Array.from(existingTagsSet);

    const formData = new FormData();
    formData.append('file', file);
    formData.append('model', selectedModel);
    formData.append('existing_tags', JSON.stringify(existingTags));

    try {
      setGenerationLogs(prev => prev + `PDF processing started. Gemini (${selectedModel}) is analyzing pages and visual assets...\nThis might take a minute depending on PDF size...\n`);
      
      const res = await fetch(`${API_BASE}/api/generate/pdf`, {
        method: 'POST',
        body: formData,
      });

      const data = await res.json();
      if (res.ok) {
        setGenerationLogs(prev => prev + `Successfully generated ${data.count} flashcards!\nFiles saved in local storage.\n`);
        fetchPcLibrary();
        if (activeDevice) fetchComparison();
      } else {
        setGenerationLogs(prev => prev + `Error: ${data.detail || 'Unknown error occurred.'}\n`);
      }
    } catch (err) {
      setGenerationLogs(prev => prev + `Network error: ${err.message}\n`);
    } finally {
      setIsGenerating(false);
    }
  };

  // Select / Deselect Cards
  const toggleSelectCard = (hash) => {
    const updated = new Set(selectedHashes);
    if (updated.has(hash)) {
      updated.delete(hash);
    } else {
      updated.add(hash);
    }
    setSelectedHashes(updated);
  };

  const selectAllUnsynced = () => {
    const unsynced = pcCards.filter(c => c.sync_status !== 'synced');
    const updated = new Set(selectedHashes);
    unsynced.forEach(c => updated.add(c.id));
    setSelectedHashes(updated);
  };

  const clearSelection = () => {
    setSelectedHashes(new Set());
  };

  // Queue cards for sync
  const handleSyncToPhone = async () => {
    if (!activeDevice) {
      alert("Please connect/pair a phone first.");
      return;
    }
    if (selectedHashes.size === 0) {
      alert("Please select at least one card to sync.");
      return;
    }

    try {
      const res = await fetch(`${API_BASE}/api/sync/device/${activeDevice.device_id}/queue`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ card_hashes: Array.from(selectedHashes) })
      });

      if (res.ok) {
        alert(`Queued ${selectedHashes.size} cards for transfer. The phone app will download them automatically.`);
        setSelectedHashes(new Set());
        fetchComparison();
      } else {
        const data = await res.json();
        alert(`Sync failed: ${data.detail}`);
      }
    } catch (err) {
      alert(`Sync network error: ${err.message}`);
    }
  };

  const handleDeleteCard = async (hash) => {
    if (!confirm("Are you sure you want to delete this flashcard from the PC library?")) return;
    try {
      const res = await fetch(`${API_BASE}/api/cards/${hash}`, {
        method: 'DELETE'
      });
      if (res.ok) {
        fetchPcLibrary();
        if (activeDevice) fetchComparison();
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleEnterEditWorkspace = async (card) => {
    setIsLoadingContent(true);
    setWsError('');
    try {
      const res = await fetch(`${API_BASE}/api/cards/${card.id}/content`);
      if (res.ok) {
        const data = await res.json();
        setWsQuestion(data.question || '');
        setWsAnswer(data.answer || '');
        setWsTag(data.tags && data.tags.length > 0 ? data.tags[0] : '');
        setWsSourcePdf(data.source_pdf || 'Manual');
        setWsPdfRefLine(data.pdf_ref_line || 0);
        setWsExistingAttachments(data.attachments || []);
        setWsImages([]);
        setSelectedWorkspaceCard(card);
        setCurrentView('workspace');
      } else {
        alert("Failed to load flashcard content for editing.");
      }
    } catch (err) {
      alert("Network error loading card: " + err.message);
    } finally {
      setIsLoadingContent(false);
    }
  };

  const handleSaveWorkspaceCard = async () => {
    if (!wsQuestion.trim()) {
      setWsError("Question/Headline is required.");
      return;
    }
    if (!wsAnswer.trim()) {
      setWsError("Answer/Content is required.");
      return;
    }
    
    setIsSavingWs(true);
    setWsError('');
    
    // Construct tag list (max 1 tag)
    const tags = wsTag.trim() ? [wsTag.trim()] : [];
    
    const payload = {
      question: wsQuestion,
      answer: wsAnswer,
      tags: tags,
      source_pdf: wsSourcePdf,
      pdf_ref_line: parseInt(wsPdfRefLine) || 0,
      attachments: wsExistingAttachments
    };

    const formData = new FormData();
    formData.append("card_data", JSON.stringify(payload));
    
    wsImages.forEach(imgFile => {
      formData.append("images", imgFile);
    });
    
    try {
      let res;
      if (selectedWorkspaceCard) {
        // Edit existing
        res = await fetch(`${API_BASE}/api/cards/${selectedWorkspaceCard.id}`, {
          method: 'PUT',
          body: formData
        });
      } else {
        // Create new
        res = await fetch(`${API_BASE}/api/cards`, {
          method: 'POST',
          body: formData
        });
      }
      
      const data = await res.json();
      if (res.ok) {
        alert(selectedWorkspaceCard ? "Flashcard updated successfully!" : "Flashcard created successfully!");
        fetchPcLibrary();
        if (activeDevice) fetchComparison();
        // Return to PC manage view
        setCurrentView('pc-manage');
      } else {
        setWsError(data.detail || "Failed to save flashcard.");
      }
    } catch (err) {
      setWsError("Network error: " + err.message);
    } finally {
      setIsSavingWs(false);
    }
  };

  // Filter lists based on toggle
  const visiblePcCards = showSyncedCards ? pcCards : pcCards.filter(c => c.sync_status !== 'synced');
  const visiblePhoneCards = showSyncedCards ? phoneCards : phoneCards.filter(c => c.sync_status !== 'synced');

  const renderPcManageView = () => {
    return (
      <div className="app-container">
        <header className="app-header glass-panel">
          <div className="logo-container" style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <img src="/icon.png" alt="MindLoop Logo" style={{ height: '32px', width: '32px', borderRadius: '6px' }} />
            <h1 className="logo-text">MindLoop / PC Storage</h1>
          </div>
          <button className="btn btn-secondary" onClick={() => setCurrentView('sync-center')}>
            Back to Sync Center
          </button>
        </header>

        <div style={{ padding: '0 24px 24px 24px', width: '100%' }}>
          <section className="glass-panel" style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <h2>PC Storage Manager ({filteredPcCards.length} cards)</h2>
              <button className="btn btn-primary" onClick={() => { setSelectedWorkspaceCard(null); setWsQuestion(''); setWsAnswer(''); setWsTag(''); setWsSourcePdf('Manual'); setWsPdfRefLine(0); setWsExistingAttachments([]); setWsImages([]); setWsError(''); setCurrentView('workspace'); }}>
                Create Manual Card
              </button>
            </div>

            <div style={{ display: 'flex', gap: '8px' }}>
              <input 
                type="text" 
                placeholder="Search question or PDF..." 
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                style={{ flex: 1 }}
              />
              <select
                value={selectedFilterTag}
                onChange={(e) => setSelectedFilterTag(e.target.value)}
                style={{ maxWidth: '200px' }}
              >
                <option value="All">All Tags</option>
                {allTags.map((tag, idx) => (
                  <option key={idx} value={tag}>{tag}</option>
                ))}
              </select>
            </div>

            <div className="cards-list" style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxHeight: '600px', overflowY: 'auto' }}>
              {filteredPcCards.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No cards found.</div>
              ) : (
                filteredPcCards.map(card => (
                  <div 
                    key={card.id} 
                    className="flashcard-row"
                    style={{ padding: '16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}
                  >
                    <div className="card-title-area" onClick={() => setSelectedCard(card)} style={{ cursor: 'pointer', flex: 1 }}>
                      <span className="card-question" style={{ fontSize: '1rem', fontWeight: 'bold' }}>{card.question}</span>
                      <div className="card-meta-tags" style={{ marginTop: '8px' }}>
                        <span className="tag-badge primary">{card.source_pdf}</span>
                        {card.tags && card.tags.map((t, i) => (
                          <span key={i} className="tag-badge">{t}</span>
                        ))}
                      </div>
                    </div>

                    <div style={{ display: 'flex', gap: '8px', marginLeft: '16px' }} onClick={e => e.stopPropagation()}>
                      <button className="btn btn-secondary" style={{ padding: '6px 12px', fontSize: '0.8rem' }} onClick={() => handleEnterEditWorkspace(card)}>
                        Edit
                      </button>
                      <button className="btn btn-danger" style={{ padding: '6px 12px', fontSize: '0.8rem', background: 'var(--red)', color: '#fff' }} onClick={() => handleDeleteCard(card.id)}>
                        Delete
                      </button>
                    </div>
                  </div>
                ))
              )}
            </div>
          </section>
        </div>
      </div>
    );
  };

  const renderPhoneManageView = () => {
    return (
      <div className="app-container">
        <header className="app-header glass-panel">
          <div className="logo-container" style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <img src="/icon.png" alt="MindLoop Logo" style={{ height: '32px', width: '32px', borderRadius: '6px' }} />
            <h1 className="logo-text">MindLoop / Phone Storage</h1>
          </div>
          <button className="btn btn-secondary" onClick={() => setCurrentView('sync-center')}>
            Back to Sync Center
          </button>
        </header>

        <div style={{ padding: '0 24px 24px 24px', width: '100%' }}>
          <section className="glass-panel" style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
            <h2>Phone Storage Manager {activeDevice ? `(${visiblePhoneCards.length} cards)` : ''}</h2>

            <div className="cards-list" style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxHeight: '600px', overflowY: 'auto' }}>
              {!activeDevice ? (
                <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No device connected.</div>
              ) : visiblePhoneCards.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No cards synced to phone.</div>
              ) : (
                visiblePhoneCards.map(card => (
                  <div 
                    key={card.id} 
                    className="flashcard-row"
                    onClick={() => setSelectedCard(card)}
                    style={{ padding: '16px', cursor: 'pointer', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}
                  >
                    <div className="card-title-area" style={{ flex: 1 }}>
                      <span className="card-question" style={{ fontSize: '1rem', fontWeight: 'bold' }}>{card.question}</span>
                      <div className="card-meta-tags" style={{ marginTop: '8px' }}>
                        <span className="tag-badge primary">{card.source_pdf}</span>
                        {card.tags && card.tags.map((t, i) => (
                          <span key={i} className="tag-badge">{t}</span>
                        ))}
                      </div>
                    </div>
                    <CheckCircle2 color="var(--success)" size={20} />
                  </div>
                ))
              )}
            </div>
          </section>
        </div>
      </div>
    );
  };

  const renderWorkspaceView = () => {
    return (
      <div className="app-container">
        <header className="app-header glass-panel">
          <div className="logo-container" style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <img src="/icon.png" alt="MindLoop Logo" style={{ height: '32px', width: '32px', borderRadius: '6px' }} />
            <h1 className="logo-text">MindLoop / Workspace</h1>
          </div>
          <button className="btn btn-secondary" onClick={() => setCurrentView('sync-center')}>
            Back to Sync Center
          </button>
        </header>

        <div style={{ padding: '0 24px 24px 24px', width: '92vw', maxWidth: '92vw', margin: '0 auto' }}>
          <section className="glass-panel" style={{ padding: '32px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
            <h2>{selectedWorkspaceCard ? "Edit Flashcard" : "Create Flashcard Manually"}</h2>
            
            {wsError && (
              <div style={{ color: 'var(--red)', background: 'rgba(239,68,68,0.1)', padding: '12px', border: '2px solid var(--red)', borderRadius: '8px', fontWeight: 'bold', textTransform: 'uppercase', fontSize: '0.85rem' }}>
                {wsError}
              </div>
            )}

            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', textAlign: 'left' }}>
              <div>
                <label style={{ display: 'block', fontWeight: 'bold', marginBottom: '8px' }}>Topic Headline (Question / Front Side)</label>
                <input 
                  type="text" 
                  value={wsQuestion} 
                  onChange={(e) => setWsQuestion(e.target.value)} 
                  placeholder="e.g. KaTeX Equation Engine Implementation"
                  style={{ width: '100%' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', fontWeight: 'bold', marginBottom: '8px' }}>
                  Detailed Content (Notion / AppFlowy Rich Workspace Editor)
                </label>
                <MarkdownEditor 
                  value={wsAnswer} 
                  onChange={setWsAnswer} 
                  getAttachmentUrl={(src) => {
                    if (!src) return '';
                    if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:')) {
                      return src;
                    }
                    const filename = src.replace(/^assets\//, '');
                    const localFile = wsImages.find(f => f.name === filename);
                    if (localFile) {
                      return URL.createObjectURL(localFile);
                    }
                    if (selectedWorkspaceCard) {
                      return `${API_BASE}/api/cards/${selectedWorkspaceCard.id}/assets/${filename}`;
                    }
                    return src;
                  }}
                  placeholder="Type your markdown content here... Press '/' for block commands or use the toolbar above!"
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div>
                  <label style={{ display: 'block', fontWeight: 'bold', marginBottom: '8px' }}>Tag (Exactly 1 Tag Allowed)</label>
                  <input 
                    type="text" 
                    value={wsTag} 
                    onChange={(e) => setWsTag(e.target.value)} 
                    placeholder="e.g. machine-learning"
                    style={{ width: '100%' }}
                  />
                  {allTags.length > 0 && (
                    <div style={{ marginTop: '8px' }}>
                      <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Quick Select Library Tag:</span>
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginTop: '4px' }}>
                        {allTags.map((t, idx) => (
                          <span 
                            key={idx} 
                            className="tag-badge" 
                            style={{ cursor: 'pointer' }}
                            onClick={() => setWsTag(t)}
                          >
                            #{t}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                  <div>
                    <label style={{ display: 'block', fontWeight: 'bold', marginBottom: '8px' }}>Source PDF (Optional)</label>
                    <input 
                      type="text" 
                      value={wsSourcePdf} 
                      onChange={(e) => setWsSourcePdf(e.target.value)} 
                      style={{ width: '100%' }}
                    />
                  </div>
                  <div>
                    <label style={{ display: 'block', fontWeight: 'bold', marginBottom: '8px' }}>PDF Page / Reference Line (Optional)</label>
                    <input 
                      type="number" 
                      value={wsPdfRefLine} 
                      onChange={(e) => setWsPdfRefLine(parseInt(e.target.value) || 0)} 
                      style={{ width: '100%' }}
                    />
                  </div>
                </div>
              </div>
              
              {/* Images & Diagrams Section */}
              <div style={{ marginTop: '20px', borderTop: '2.5px dashed var(--border-color)', paddingTop: '20px', textAlign: 'left' }}>
                <label style={{ display: 'block', fontWeight: 'bold', marginBottom: '8px' }}>Images / Diagrams (Optional)</label>
                <div style={{ display: 'flex', gap: '16px', alignItems: 'center', marginBottom: '16px' }}>
                  <input 
                    type="file" 
                    multiple 
                    accept="image/*" 
                    id="ws-image-upload"
                    style={{ display: 'none' }}
                    onChange={(e) => {
                      if (e.target.files) {
                        setWsImages(prev => [...prev, ...Array.from(e.target.files)]);
                      }
                    }}
                  />
                  <label htmlFor="ws-image-upload" className="btn btn-secondary" style={{ cursor: 'pointer', margin: 0 }}>
                    Select Image Files
                  </label>
                  <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                    Choose images to package inside the flashcard.
                  </span>
                </div>

                {/* Combined list of files */}
                {((wsExistingAttachments && wsExistingAttachments.length > 0) || (wsImages && wsImages.length > 0)) && (
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', background: 'var(--panel-bg)', padding: '16px', borderRadius: '8px', border: '1.5px solid var(--border-color)' }}>
                    {/* Existing attachments */}
                    <div>
                      <h4 style={{ fontSize: '0.85rem', fontWeight: 'bold', marginBottom: '8px', textTransform: 'uppercase' }}>Active Card Attachments ({wsExistingAttachments.length})</h4>
                      {wsExistingAttachments.length === 0 ? (
                        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>No active attachments.</span>
                      ) : (
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                          {wsExistingAttachments.map((att, i) => {
                            const filename = att.split('/').pop();
                            const imageUrl = selectedWorkspaceCard ? `${API_BASE}/api/cards/${selectedWorkspaceCard.id}/assets/${filename}` : '';
                            return (
                              <div key={i} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '6px', background: 'rgba(255,255,255,0.03)', borderRadius: '6px', border: '1px solid var(--panel-border)' }}>
                                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', overflow: 'hidden' }}>
                                  {imageUrl && <img src={imageUrl} alt={filename} style={{ width: '32px', height: '32px', borderRadius: '4px', objectFit: 'cover', border: '1px solid var(--border-color)' }} />}
                                  <span style={{ fontSize: '0.75rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={filename}>{filename}</span>
                                </div>
                                <div style={{ display: 'flex', gap: '6px' }}>
                                  <button 
                                    className="btn btn-secondary" 
                                    style={{ padding: '2px 6px', fontSize: '0.7rem' }}
                                    onClick={() => setWsAnswer(prev => prev + `\n![${filename.split('.')[0]}](assets/${filename})`)}
                                  >
                                    Insert Ref
                                  </button>
                                  <button 
                                    className="btn btn-danger" 
                                    style={{ padding: '2px 6px', fontSize: '0.7rem', background: 'var(--red)', color: '#fff' }}
                                    onClick={() => setWsExistingAttachments(prev => prev.filter(a => a !== att))}
                                  >
                                    Delete
                                  </button>
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </div>

                    {/* New uploads */}
                    <div>
                      <h4 style={{ fontSize: '0.85rem', fontWeight: 'bold', marginBottom: '8px', textTransform: 'uppercase' }}>New Uploads ({wsImages.length})</h4>
                      {wsImages.length === 0 ? (
                        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>No new files added.</span>
                      ) : (
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                          {wsImages.map((file, i) => {
                            const tempUrl = URL.createObjectURL(file);
                            return (
                              <div key={i} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '6px', background: 'rgba(255,255,255,0.03)', borderRadius: '6px', border: '1px solid var(--panel-border)' }}>
                                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', overflow: 'hidden' }}>
                                  <img src={tempUrl} alt={file.name} style={{ width: '32px', height: '32px', borderRadius: '4px', objectFit: 'cover', border: '1px solid var(--border-color)' }} />
                                  <span style={{ fontSize: '0.75rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={file.name}>{file.name}</span>
                                </div>
                                <div style={{ display: 'flex', gap: '6px' }}>
                                  <button 
                                    className="btn btn-secondary" 
                                    style={{ padding: '2px 6px', fontSize: '0.7rem' }}
                                    onClick={() => setWsAnswer(prev => prev + `\n![${file.name.split('.')[0]}](assets/${file.name})`)}
                                  >
                                    Insert Ref
                                  </button>
                                  <button 
                                    className="btn btn-danger" 
                                    style={{ padding: '2px 6px', fontSize: '0.7rem', background: 'var(--red)', color: '#fff' }}
                                    onClick={() => setWsImages(prev => prev.filter((_, idx) => idx !== i))}
                                  >
                                    Delete
                                  </button>
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '12px' }}>
              <button 
                className="btn btn-secondary" 
                onClick={() => setCurrentView(selectedWorkspaceCard ? 'pc-manage' : 'sync-center')}
                disabled={isSavingWs}
              >
                Cancel
              </button>
              <button 
                className="btn btn-primary" 
                onClick={handleSaveWorkspaceCard}
                disabled={isSavingWs}
              >
                {isSavingWs ? "Saving..." : "Save Flashcard"}
              </button>
            </div>
          </section>
        </div>
      </div>
    );
  };

  if (currentView === 'pc-manage') {
    return renderPcManageView();
  }
  if (currentView === 'phone-manage') {
    return renderPhoneManageView();
  }
  if (currentView === 'workspace') {
    return renderWorkspaceView();
  }

  return (
    <div className="app-container">
      {/* Header */}
      <header className="app-header glass-panel">
        <div className="logo-container" style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <img src="/icon.png" alt="MindLoop Logo" style={{ height: '32px', width: '32px', borderRadius: '6px' }} />
          <h1 className="logo-text">MindLoop</h1>
        </div>
        
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          {/* Active Device Info */}
          {activeDevice ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--success)', fontWeight: '600' }}>
              <Smartphone size={20} />
              <span>Connected: {activeDevice.device_name}</span>
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--text-secondary)' }}>
              <Smartphone size={20} />
              <span>No Device Connected</span>
            </div>
          )}

          <button className="btn btn-secondary" onClick={() => { setSelectedWorkspaceCard(null); setWsQuestion(''); setWsAnswer(''); setWsTag(''); setWsSourcePdf('Manual'); setWsPdfRefLine(0); setWsExistingAttachments([]); setWsImages([]); setWsError(''); setCurrentView('workspace'); }} style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Plus size={18} />
            Workspace
          </button>

          <button className="btn btn-secondary" onClick={() => setShowGeneratorModal(true)} style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Plus size={18} />
            Generate Flashcards
          </button>

          <button className="btn btn-primary" onClick={handleOpenPairing}>
            <Link size={18} />
            Pair Device
          </button>
        </div>
      </header>

      {/* Main Grid */}
      <div style={{ padding: '0 24px 24px 24px', width: '100%' }}>
        {/* Sync Center Split Columns */}
        <section className="glass-panel" style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h2 style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '1.25rem' }}>
              <Layers color="var(--secondary)" />
              Library Sync Center
            </h2>

            {/* Controls */}
            <div style={{ display: 'flex', gap: '8px' }}>
              <button 
                className="btn btn-secondary" 
                onClick={handleRefreshAll}
                disabled={isRefreshing}
                title="Refresh Libraries"
                style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
              >
                <RefreshCw size={16} className={isRefreshing ? 'spin' : ''} style={{ animation: isRefreshing ? 'spin 1.2s linear infinite' : 'none' }} />
                Refresh
              </button>

              <button 
                className="btn btn-secondary" 
                onClick={() => setShowSyncedCards(!showSyncedCards)}
                title={showSyncedCards ? "Hide Synced Cards" : "Show Synced Cards"}
              >
                {showSyncedCards ? <EyeOff size={16} /> : <Eye size={16} />}
                {showSyncedCards ? "Hide Synced" : "Show Synced"}
              </button>
              
              {activeDevice && (
                <button 
                  className="btn btn-primary" 
                  onClick={handleSyncToPhone}
                  disabled={selectedHashes.size === 0}
                >
                  <DownloadCloud size={16} />
                  Upload Selected ({selectedHashes.size})
                </button>
              )}
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px', minHeight: '550px' }}>
            {/* PC Cards Side */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0 4px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <h3 style={{ fontSize: '0.9rem', color: 'var(--text-secondary)' }}>PC Storage ({filteredPcCards.length})</h3>
                  <button className="btn" style={{ padding: '2px 8px', fontSize: '0.75rem', border: '1.5px solid var(--border-color)', boxShadow: '1.5px 1.5px 0px var(--shadow-color)', textTransform: 'uppercase' }} onClick={() => setCurrentView('pc-manage')}>
                    Manage
                  </button>
                </div>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <button style={{ background: 'none', border: 'none', color: 'var(--primary)', fontSize: '0.75rem', cursor: 'pointer', fontWeight: '600' }} onClick={selectAllUnsynced}>
                    Select Unsynced
                  </button>
                  {selectedHashes.size > 0 && (
                    <button style={{ background: 'none', border: 'none', color: 'var(--text-muted)', fontSize: '0.75rem', cursor: 'pointer' }} onClick={clearSelection}>
                      Clear
                    </button>
                  )}
                </div>
              </div>

              {/* Search & Tags Filters */}
              <div style={{ display: 'flex', gap: '8px', marginBottom: '4px' }}>
                <input 
                  type="text" 
                  placeholder="Search question or PDF..." 
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  style={{ flex: 1 }}
                />
                <select
                  value={selectedFilterTag}
                  onChange={(e) => setSelectedFilterTag(e.target.value)}
                  style={{ maxWidth: '140px' }}
                >
                  <option value="All">All Tags</option>
                  {allTags.map((tag, idx) => (
                    <option key={idx} value={tag}>{tag}</option>
                  ))}
                </select>
              </div>

              <div className="cards-list" style={{ height: '480px', overflowY: 'auto' }}>
                {filteredPcCards.length === 0 ? (
                  <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No cards found.</div>
                ) : (
                  filteredPcCards.map(card => (
                    <div 
                      key={card.id} 
                      className={`flashcard-row ${selectedHashes.has(card.id) ? 'selected' : ''}`}
                      onClick={() => setSelectedCard(card)}
                      style={{ cursor: 'pointer' }}
                    >
                      <div className="card-title-area">
                        <span className="card-question" title={card.question}>{card.question}</span>
                        <div className="card-meta-tags">
                          <span className="tag-badge primary">{card.source_pdf}</span>
                          {card.tags && card.tags.slice(0, 2).map((t, i) => (
                            <span key={i} className="tag-badge">{t}</span>
                          ))}
                        </div>
                      </div>

                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }} onClick={e => e.stopPropagation()}>
                        {card.sync_status === 'synced' ? (
                          <CheckCircle2 color="var(--success)" size={18} title="Synced to phone" />
                        ) : (
                          <input 
                            type="checkbox" 
                            checked={selectedHashes.has(card.id)} 
                            onChange={() => toggleSelectCard(card.id)}
                            style={{ width: '16px', height: '16px', accentColor: 'var(--primary)', cursor: 'pointer' }}
                          />
                        )}
                        <button 
                          style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer' }}
                          onClick={() => handleDeleteCard(card.id)}
                          className="hover-danger"
                        >
                          <Trash2 size={15} />
                        </button>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>

            {/* Phone Cards Side (Right Column) */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', borderLeft: '1px solid var(--panel-border)', paddingLeft: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '0 4px' }}>
                <h3 style={{ fontSize: '0.9rem', color: 'var(--text-secondary)' }}>
                  Phone Storage {activeDevice ? `(${visiblePhoneCards.length})` : ''}
                </h3>
                {activeDevice && (
                  <button className="btn" style={{ padding: '2px 8px', fontSize: '0.75rem', border: '1.5px solid var(--border-color)', boxShadow: '1.5px 1.5px 0px var(--shadow-color)', textTransform: 'uppercase' }} onClick={() => setCurrentView('phone-manage')}>
                    Manage
                  </button>
                )}
              </div>
              
              {activeDevice ? (
                <div className="cards-list" style={{ height: '528px', overflowY: 'auto' }}>
                  {visiblePhoneCards.length === 0 ? (
                    <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No cards synced to phone.</div>
                  ) : (
                    visiblePhoneCards.map(card => (
                      <div 
                        key={card.id} 
                        className="flashcard-row" 
                        style={{ opacity: 0.85, cursor: 'pointer' }}
                        onClick={() => setSelectedCard(card)}
                      >
                        <div className="card-title-area">
                          <span className="card-question" title={card.question}>{card.question}</span>
                          <span className="tag-badge">Synced</span>
                        </div>
                        <CheckCircle2 color="var(--success)" size={18} />
                      </div>
                    ))
                  )}
                </div>
              ) : (
                <div style={{ 
                  flex: 1,
                  display: 'flex', 
                  flexDirection: 'column', 
                  alignItems: 'center', 
                  justifyContent: 'center', 
                  color: 'var(--text-muted)',
                  gap: '12px',
                  background: 'var(--panel-bg)',
                  borderRadius: '12px',
                  border: '3px dashed var(--border-color)',
                  boxShadow: '4px 4px 0px var(--shadow-color)',
                  padding: '40px',
                  textAlign: 'center'
                }}>
                  <Smartphone size={40} color="var(--text-muted)" style={{ opacity: 0.5 }} />
                  <p style={{ fontSize: '0.9rem', fontWeight: '800', textTransform: 'uppercase' }}>Phone Not Connected</p>
                  <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', maxWidth: '240px' }}>
                    Pair your mobile app using the notification bell screen to synchronize flashcards.
                  </p>
                </div>
              )}
            </div>
          </div>
        </section>
      </div>

      {/* Pairing QR Modal */}
      {showPairModal && pairingInfo && (
        <div className="modal-overlay" onClick={() => setShowPairModal(false)}>
          <div className="modal-content glass-panel" onClick={e => e.stopPropagation()}>
            <h3 style={{ fontSize: '1.25rem', fontWeight: '700' }}>Pair Mobile Device</h3>
            <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
              Open MindLoop on your phone, tap "Scan QR" and point it at the screen. Make sure your phone is connected to the same local Wi-Fi.
            </p>

            <div className="qr-frame">
              <img 
                src={`${API_BASE}/api/pairing/qr?t=${new Date().getTime()}`} 
                alt="Pairing QR Code" 
                className="qr-image"
              />
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', width: '100%' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', padding: '6px 12px', background: 'rgba(255,255,255,0.03)', borderRadius: '6px' }}>
                <span style={{ color: 'var(--text-secondary)' }}>Pairing Code:</span>
                <strong style={{ fontFamily: 'JetBrains Mono', color: 'var(--primary)' }}>{pairingInfo.pairing_code}</strong>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', padding: '6px 12px', background: 'rgba(255,255,255,0.03)', borderRadius: '6px' }}>
                <span style={{ color: 'var(--text-secondary)' }}>Port:</span>
                <strong>{pairingInfo.port}</strong>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', fontSize: '0.8rem', padding: '6px 12px', background: 'rgba(255,255,255,0.03)', borderRadius: '6px', textAlign: 'left' }}>
                <span style={{ color: 'var(--text-secondary)' }}>Available Server IP(s):</span>
                {pairingInfo.ips.map((ip, i) => (
                  <span key={i} style={{ fontFamily: 'JetBrains Mono', color: 'var(--accent)' }}>{ip}</span>
                ))}
              </div>
            </div>

            <button className="btn btn-secondary" style={{ width: '100%' }} onClick={() => setShowPairModal(false)}>
              Close
            </button>
          </div>
        </div>
      )}

      {/* PDF Generator Modal */}
      {showGeneratorModal && (
        <div className="modal-overlay" onClick={() => !isGenerating && setShowGeneratorModal(false)}>
          <div className="modal-content glass-panel" style={{ width: '90vw', maxWidth: '1100px', height: '85vh', maxHeight: '90vh', padding: '32px', display: 'flex', flexDirection: 'column', textAlign: 'left', overflowY: 'auto' }} onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <h3 style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '1.25rem', margin: 0, fontWeight: '700' }}>
                <FileText color="var(--primary)" size={22} />
                PDF Card Generator
              </h3>
              {!isGenerating && (
                <button 
                  style={{ background: 'none', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer', fontSize: '1.5rem', lineHeight: 1 }}
                  onClick={() => setShowGeneratorModal(false)}
                >
                  &times;
                </button>
              )}
            </div>

            <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: '16px', textAlign: 'left' }}>
              Upload any study PDF (lecture slides, notes, papers) and let the reasoning model extract cards containing mathematical text and visual assets automatically.
            </p>

            <div style={{ display: 'flex', gap: '12px', marginBottom: '16px', textAlign: 'left' }}>
              <div style={{ flex: 1 }}>
                <label style={{ display: 'block', fontSize: '0.8rem', color: 'var(--text-secondary)', marginBottom: '6px' }}>LLM Model</label>
                <select 
                  className="btn btn-secondary" 
                  style={{ width: '100%', padding: '10px', background: 'rgba(255,255,255,0.02)' }}
                  value={selectedModel}
                  onChange={(e) => setSelectedModel(e.target.value)}
                >
                  <option value="gemma-4-31b-it">Gemma 4 31B IT (Reasoning, Default)</option>
                  <option value="gemini-2.5-flash">Gemini 2.5 Flash (Fast, Multimodal)</option>
                  <option value="gemini-2.0-flash">Gemini 2.0 Flash</option>
                  <option value="gemini-1.5-flash">Gemini 1.5 Flash</option>
                </select>
              </div>
            </div>

            {/* Drag and Drop Zone */}
            <div 
              className={`upload-zone ${dragActive ? 'active' : ''}`}
              onDragEnter={handleDrag}
              onDragOver={handleDrag}
              onDragLeave={handleDrag}
              onDrop={handleDrop}
              onClick={() => !isGenerating && fileInputRef.current.click()}
              style={{ pointerEvents: isGenerating ? 'none' : 'auto', marginBottom: '16px', minHeight: '180px', flex: 1, justifyContent: 'center' }}
            >
              <FileUp size={48} color={isGenerating ? 'var(--primary)' : 'var(--text-secondary)'} style={{ animation: isGenerating ? 'pulse 2s infinite' : 'none' }} />
              {isGenerating ? (
                <span style={{ fontWeight: '600', color: 'var(--primary)', fontSize: '1rem' }}>Analyzing PDF with Multimodal AI ({selectedModel})...</span>
              ) : (
                <>
                  <span style={{ fontWeight: '600', fontSize: '1.1rem' }}>Drag & Drop PDF or Click to Browse</span>
                  <span style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>Supports text, figures, equations, diagrams</span>
                </>
              )}
              <input 
                type="file" 
                ref={fileInputRef} 
                style={{ display: 'none' }} 
                accept=".pdf" 
                onChange={handleFileChange}
                disabled={isGenerating}
              />
            </div>

            {/* Generator Logs */}
            {generationLogs && (
              <div style={{ 
                background: 'rgba(0,0,0,0.3)', 
                padding: '16px', 
                borderRadius: '8px', 
                fontSize: '0.8rem', 
                fontFamily: 'JetBrains Mono, monospace',
                color: 'var(--text-secondary)',
                whiteSpace: 'pre-wrap',
                maxHeight: '260px',
                flex: 1,
                overflowY: 'auto',
                border: '1px solid var(--panel-border)',
                textAlign: 'left',
                marginBottom: '16px'
              }}>
                {generationLogs}
              </div>
            )}

            <button 
              className="btn btn-secondary" 
              style={{ width: '100%' }} 
              onClick={() => setShowGeneratorModal(false)}
              disabled={isGenerating}
            >
              Close
            </button>
          </div>
        </div>
      )}

      {/* Flashcard Detail Modal */}
      {selectedCard && (
        <div className="modal-overlay" onClick={() => setSelectedCard(null)}>
          <div className="modal-content glass-panel" style={{ width: '90vw', maxWidth: '1300px', height: '88vh', maxHeight: '90vh', padding: '32px', display: 'flex', flexDirection: 'column', textAlign: 'left', overflow: 'hidden' }} onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <span className="tag-badge primary" style={{ margin: 0 }}>
                {selectedCard.source_pdf}
              </span>
              <button 
                style={{ background: 'none', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer', fontSize: '1.5rem', lineHeight: 1 }}
                onClick={() => setSelectedCard(null)}
              >
                &times;
              </button>
            </div>

            <h3 style={{ fontSize: '1.35rem', fontWeight: '800', color: '#fff', marginBottom: '12px', lineHeight: 1.4 }}>
              {selectedCard.question}
            </h3>

            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginBottom: '20px' }}>
              {selectedCard.tags && selectedCard.tags.map((t, i) => (
                <span key={i} className="tag-badge">{t}</span>
              ))}
              {selectedCard.pdf_page && (
                <span className="tag-badge" style={{ borderColor: 'var(--primary)', color: 'var(--primary)' }}>Page {selectedCard.pdf_page}</span>
              )}
            </div>

            <div style={{ 
              flex: 1, 
              overflowY: 'auto', 
              padding: '24px', 
              background: 'rgba(0,0,0,0.2)', 
              borderRadius: '8px',
              border: '1px solid var(--panel-border)',
              marginBottom: '20px'
            }}>
              {isLoadingContent ? (
                <div style={{ textAlign: 'center', padding: '20px', color: 'var(--text-muted)' }}>Loading flashcard details...</div>
              ) : cardContent ? (
                <MarkdownRenderer content={cardContent.answer} cardId={selectedCard.id} />
              ) : (
                <div style={{ textAlign: 'center', padding: '20px', color: 'var(--text-muted)' }}>Failed to load flashcard.</div>
              )}
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button className="btn btn-secondary" onClick={() => setSelectedCard(null)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
