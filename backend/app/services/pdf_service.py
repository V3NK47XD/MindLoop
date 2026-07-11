import fitz  # PyMuPDF
import os
from pathlib import Path
import logging

logger = logging.getLogger(__name__)

def extract_pdf_content(pdf_path: Path, session_temp_dir: Path) -> list[dict]:
    """
    Extracts text and embedded images from a PDF page-by-page.
    Saves extracted images to session_temp_dir.
    
    Returns a list of page objects:
    [
      {
        "page_num": 1,
        "text": "Page text...",
        "images": ["page_1_img_1.png", ...]
      },
      ...
    ]
    """
    if not pdf_path.exists():
        raise FileNotFoundError(f"PDF file not found at {pdf_path}")
        
    os.makedirs(session_temp_dir, exist_ok=True)
    pages_data = []
    
    try:
        doc = fitz.open(str(pdf_path))
        logger.info(f"Successfully opened PDF: {pdf_path.name} with {len(doc)} pages.")
        
        for page_idx in range(len(doc)):
            page_num = page_idx + 1
            page = doc[page_idx]
            
            # Extract text
            page_text = page.get_text("text")
            
            # Extract images
            page_images = []
            image_list = page.get_images(full=True)
            
            for img_idx, img in enumerate(image_list):
                xref = img[0]
                base_image = doc.extract_image(xref)
                image_bytes = base_image["image"]
                image_ext = base_image["ext"]
                
                # Standardize to png if not already png/jpg
                if image_ext not in ["png", "jpg", "jpeg"]:
                    image_ext = "png"
                    
                image_name = f"page_{page_num}_img_{img_idx + 1}.{image_ext}"
                image_path = session_temp_dir / image_name
                
                with open(image_path, "wb") as img_file:
                    img_file.write(image_bytes)
                
                page_images.append(image_name)
                logger.debug(f"Extracted image {image_name} from page {page_num}")
            
            pages_data.append({
                "page_num": page_num,
                "text": page_text or "",
                "images": page_images
            })
            
        doc.close()
        return pages_data
        
    except Exception as e:
        logger.error(f"Error extracting PDF: {str(e)}", exc_info=True)
        raise e
