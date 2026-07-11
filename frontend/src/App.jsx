import React, { useState, useEffect, useRef } from 'react';
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

function App() {
  // Library & Device state
  const [pcCards, setPcCards] = useState([]);
  const [phoneCards, setPhoneCards] = useState([]);
  const [pairedDevices, setPairedDevices] = useState([]);
  const [activeDevice, setActiveDevice] = useState(null);
  
  // Selection and Visibility
  const [selectedHashes, setSelectedHashes] = useState(new Set());
  const [showSyncedCards, setShowSyncedCards] = useState(true);
  
  // Modals & Forms
  const [showPairModal, setShowPairModal] = useState(false);
  const [pairingInfo, setPairingInfo] = useState(null);
  const [selectedModel, setSelectedModel] = useState('gemini-2.5-flash');
  const [isGenerating, setIsGenerating] = useState(false);
  const [generationLogs, setGenerationLogs] = useState('');
  
  // File drag & drop
  const [dragActive, setDragActive] = useState(false);
  const fileInputRef = useRef(null);

  // Poll for paired devices and compare status
  useEffect(() => {
    fetchPcLibrary();
    fetchPairedDevices();

    const interval = setInterval(() => {
      fetchPairedDevices();
    }, 3000);

    return () => clearInterval(interval);
  }, []);

  // Fetch comparison when active device changes or periodically
  useEffect(() => {
    if (activeDevice) {
      fetchComparison();
      const compareInterval = setInterval(() => {
        fetchComparison();
      }, 2500);
      return () => clearInterval(compareInterval);
    } else {
      setPhoneCards([]);
    }
  }, [activeDevice]);

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

  const fetchComparison = async () => {
    if (!activeDevice) return;
    try {
      const res = await fetch(`${API_BASE}/api/sync/device/${activeDevice.device_id}/compare`);
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
    
    const formData = new FormData();
    formData.append('file', file);
    formData.append('model', selectedModel);

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

  // Filter lists based on toggle
  const visiblePcCards = showSyncedCards ? pcCards : pcCards.filter(c => c.sync_status !== 'synced');
  const visiblePhoneCards = showSyncedCards ? phoneCards : phoneCards.filter(c => c.sync_status !== 'synced');

  return (
    <div className="app-container">
      {/* Header */}
      <header className="app-header glass-panel">
        <div className="logo-container">
          <Sparkles className="logo-icon" size={28} />
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

          <button className="btn btn-primary" onClick={handleOpenPairing}>
            <Link size={18} />
            Pair Device
          </button>
        </div>
      </header>

      {/* Main Grid */}
      <div className="sync-grid">
        {/* Left Card Creation & Upload */}
        <section className="glass-panel" style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <h2 style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '1.25rem' }}>
            <FileText color="var(--primary)" />
            PDF Card Generator
          </h2>

          <div style={{ display: 'flex', gap: '12px' }}>
            <div style={{ flex: 1 }}>
              <label style={{ display: 'block', fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: '6px' }}>LLM Model</label>
              <select 
                className="btn btn-secondary" 
                style={{ width: '100%', padding: '10px', background: 'rgba(255,255,255,0.02)' }}
                value={selectedModel}
                onChange={(e) => setSelectedModel(e.target.value)}
              >
                <option value="gemini-2.5-flash">Gemini 2.5 Flash (Fast, Multimodal)</option>
                <option value="gemini-2.0-flash">Gemini 2.0 Flash</option>
                <option value="gemini-1.5-flash">Gemini 1.5 Flash</option>
                <option value="gemma2-27b-it">Gemma 2 27B IT</option>
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
            onClick={() => fileInputRef.current.click()}
          >
            <FileUp size={40} color={isGenerating ? 'var(--primary)' : 'var(--text-secondary)'} style={{ animation: isGenerating ? 'pulse 2s infinite' : 'none' }} />
            {isGenerating ? (
              <span style={{ fontWeight: '600' }}>Analyzing PDF with Gemini Multimodal AI...</span>
            ) : (
              <>
                <span style={{ fontWeight: '600' }}>Drag & Drop PDF or Click to Browse</span>
                <span style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>Supports text, figures, equations, diagrams</span>
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
              padding: '12px', 
              borderRadius: '8px', 
              fontSize: '0.8rem', 
              fontFamily: 'JetBrains Mono, monospace',
              color: 'var(--text-secondary)',
              whiteSpace: 'pre-wrap',
              maxHeight: '150px',
              overflowY: 'auto',
              border: '1px solid var(--panel-border)'
            }}>
              {generationLogs}
            </div>
          )}
        </section>

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

          {activeDevice ? (
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', height: '550px' }}>
              {/* PC Cards Side */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0 4px' }}>
                  <h3 style={{ fontSize: '0.9rem', color: 'var(--text-secondary)' }}>PC Storage ({visiblePcCards.length})</h3>
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

                <div className="cards-list">
                  {visiblePcCards.length === 0 ? (
                    <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No cards to display.</div>
                  ) : (
                    visiblePcCards.map(card => (
                      <div 
                        key={card.id} 
                        className={`flashcard-row ${selectedHashes.has(card.id) ? 'selected' : ''}`}
                        onClick={() => card.sync_status !== 'synced' && toggleSelectCard(card.id)}
                        style={{ cursor: card.sync_status === 'synced' ? 'default' : 'pointer' }}
                      >
                        <div className="card-title-area">
                          <span className="card-question" title={card.question}>{card.question}</span>
                          <div className="card-meta-tags">
                            <span className="tag-badge primary">{card.source_pdf}</span>
                            {card.tags.slice(0, 2).map((t, i) => (
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

              {/* Phone Cards Side */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', borderLeft: '1px solid var(--panel-border)', paddingLeft: '16px' }}>
                <h3 style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', padding: '0 4px' }}>Phone Storage ({visiblePhoneCards.length})</h3>
                <div className="cards-list">
                  {visiblePhoneCards.length === 0 ? (
                    <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No cards synced to phone.</div>
                  ) : (
                    visiblePhoneCards.map(card => (
                      <div key={card.id} className="flashcard-row" style={{ opacity: 0.85 }}>
                        <div className="card-title-area">
                          <span className="card-question" title={card.question}>{card.question}</span>
                          <span className="tag-badge">Synced</span>
                        </div>
                        <CheckCircle2 color="var(--success)" size={18} />
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>
          ) : (
            <div style={{ 
              height: '550px', 
              display: 'flex', 
              flexDirection: 'column', 
              alignItems: 'center', 
              justifyContent: 'center', 
              color: 'var(--text-secondary)',
              gap: '12px',
              border: '1px dashed var(--panel-border)',
              borderRadius: '12px'
            }}>
              <Smartphone size={48} color="var(--text-muted)" />
              <p style={{ fontWeight: '500' }}>Please pair and connect your phone to synchronize flashcards.</p>
              <button className="btn btn-secondary" onClick={handleOpenPairing}>
                Pair Now
              </button>
            </div>
          )}
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
    </div>
  );
}

export default App;
