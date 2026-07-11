import os
import json
import hashlib
import zipfile
from datetime import datetime
from pathlib import Path
import logging
from pydantic import BaseModel, Field
from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

# Pydantic models for structured output from Gemini
class FlashcardGen(BaseModel):
    question: str = Field(
        description="A short, concise question representing the front side of the flashcard."
    )
    answer: str = Field(
        description="The back side of the flashcard, formatted in Markdown. Can include LaTeX formulas (use '$' for inline and '$$' for block math, e.g. $E=mc^2$). If referencing an image, use standard markdown: ![Diagram](assets/image_name.png) where image_name.png is from the page's Available Images list."
    )
    tags: list[str] = Field(
        description="A list of relevant tags or topics for this flashcard. Max Limit of 2 tags."
    )
    pdf_ref_line: int = Field(
        description="Approximate line number on the page where the content was found. Set to 0 if not identifiable."
    )
    pdf_page: int = Field(
        description="The page number in the PDF where the content was found."
    )
    attachments: list[str] = Field(
        description="The exact filenames of any diagrams or images on this page that are crucial to this flashcard. Must only be chosen from the provided 'Available Images' list. If none are needed, keep empty."
    )

class FlashcardListGen(BaseModel):
    cards: list[FlashcardGen]

def compute_card_hash(question: str, answer: str, tags: list[str]) -> str:
    """Compute a unique stable SHA-256 hash for the flashcard contents."""
    tag_str = ",".join(sorted(tags))
    raw_content = f"{question.strip()}|{answer.strip()}|{tag_str}"
    return hashlib.sha256(raw_content.encode("utf-8")).hexdigest()

def package_flashcard(
    card_data: FlashcardGen,
    source_pdf_name: str,
    temp_img_dir: Path,
    output_dir: Path
) -> str:
    """
    Packages a flashcard into a <card_hash>.flash zip file.
    Returns the computed card hash.
    """
    os.makedirs(output_dir, exist_ok=True)
    
    # Calculate hash
    card_hash = compute_card_hash(card_data.question, card_data.answer, card_data.tags)
    created_at = datetime.utcnow().isoformat() + "Z"
    
    # Standardize attachments paths
    zip_attachments = []
    for attachment_name in card_data.attachments:
        zip_attachments.append(f"assets/{attachment_name}")
        
    # Build metadata.json
    metadata = {
        "id": card_hash,
        "question": card_data.question,
        "created_at": created_at,
        "tags": card_data.tags,
        "source_pdf": source_pdf_name,
        "pdf_ref_line": card_data.pdf_ref_line,
        "attachments": zip_attachments
    }
    
    # Save target path
    flash_filename = f"{card_hash}.flash"
    flash_path = output_dir / flash_filename
    
    with zipfile.ZipFile(flash_path, "w", zipfile.ZIP_DEFLATED) as zip_file:
        # Write metadata.json
        zip_file.writestr("metadata.json", json.dumps(metadata, indent=2))
        
        # Write content.md
        zip_file.writestr("content.md", card_data.answer)
        
        # Write attachments
        for attachment_name in card_data.attachments:
            src_path = temp_img_dir / attachment_name
            if src_path.exists():
                zip_file.write(src_path, arcname=f"assets/{attachment_name}")
            else:
                logger.warning(f"Attachment {attachment_name} specified by LLM but not found in temp images.")
                
    logger.info(f"Packaged flashcard {card_hash} into {flash_filename}")
    return card_hash

def generate_flashcards_from_pdf(
    api_key: str,
    model_name: str,
    pdf_path: Path,
    pages_data: list[dict],
    temp_img_dir: Path,
    storage_dir: Path
) -> list[str]:
    """
    Uploads the PDF to Gemini, triggers multimodal generation, 
    and packages the resulting cards. Returns list of generated card hashes.
    """
    # 1. Initialize Gemini client
    client = genai.Client(api_key=api_key)
    
    # Determine if model is text-only (Gemma)
    is_text_only = "gemma" in model_name.lower()
    
    uploaded_file = None
    if not is_text_only:
        # 2. Upload PDF file to Gemini
        logger.info(f"Uploading PDF {pdf_path.name} to Gemini API...")
        uploaded_file = client.files.upload(file=pdf_path)
        logger.info(f"PDF uploaded. File name: {uploaded_file.name}")
    
    # 3. Build image mappings prompt
    image_mapping_text = ""
    for page in pages_data:
        if page["images"]:
            image_mapping_text += f"\nPage {page['page_num']} has the following extracted images:\n"
            for img in page["images"]:
                image_mapping_text += f" - {img}\n"
                
    if is_text_only:
        pdf_text = ""
        for page in pages_data:
            pdf_text += f"\n--- PDF Page {page['page_num']} ---\n{page['text']}\n"
            
        prompt = f"""
You are an expert educator. Your goal is to analyze the text of a PDF document and create high-quality study flashcards from it.

Here is the extracted text content of the PDF:
{pdf_text}

Here is a list of pre-extracted image filenames matching specific pages in the PDF:
{image_mapping_text}

Instructions:
1. Review the PDF text content, including all conceptual details, definitions, and equations.
2. Generate comprehensive flashcards targeting important definitions, concepts, mathematical formulas, and visual diagrams.
3. Limit the tags array for each flashcard to EXACTLY 2 tags (no more, no less). The tags should be concise single-word identifiers related to the topic.
4. Ensure the question is clear, direct, and concise. The answer must be highly descriptive, detailed, and clear, explaining all relevant details, using formatting (bullet points, bold text) and LaTeX equations where appropriate.
5. If a concept is best explained by a diagram, graph, or formula in the PDF:
   - Identify which image filename (e.g. `page_3_img_1.png`) matches that graphic.
   - Reference it inside the flashcard's `answer` markdown using standard relative path markdown format: `![Description](assets/page_3_img_1.png)`.
   - Add that exact filename string to the `attachments` array.
6. If a card does not require a visual asset, keep `attachments` empty.
7. Format mathematical equations cleanly using LaTeX math notation:
   - Use standard `$` for inline math (e.g. $E=mc^2$)
   - Use `$$` for block display equations on their own lines.
8. Provide output strictly matching the requested JSON schema.
"""
    else:
        prompt = f"""
You are an expert educator. Your goal is to analyze the attached PDF and create high-quality study flashcards from it.

Here is a list of pre-extracted image filenames matching specific pages in the PDF:
{image_mapping_text}

Instructions:
1. Visually review the PDF pages, including all text, formulas, diagrams, charts, and drawings.
2. Generate comprehensive flashcards targeting important definitions, concepts, mathematical formulas, and visual diagrams.
3. Limit the tags array for each flashcard to EXACTLY 2 tags (no more, no less). The tags should be concise single-word identifiers related to the topic.
4. Ensure the question is clear, direct, and concise. The answer must be highly descriptive, detailed, and clear, explaining all relevant details, using formatting (bullet points, bold text) and LaTeX equations where appropriate.
5. If a concept is best explained by a diagram, graph, or formula in the PDF:
   - Identify which image filename (e.g. `page_3_img_1.png`) matches that graphic.
   - Reference it inside the flashcard's `answer` markdown using standard relative path markdown format: `![Description](assets/page_3_img_1.png)`.
   - Add that exact filename string to the `attachments` array.
6. If a card does not require a visual asset, keep `attachments` empty.
7. Format mathematical equations cleanly using LaTeX math notation:
   - Use standard `$` for inline math (e.g. $E=mc^2$)
   - Use `$$` for block display equations on their own lines.
8. Provide output strictly matching the requested JSON schema.
"""

    try:
        logger.info(f"Invoking Gemini model {model_name}...")
        # Build generator configuration
        config_args = {
            "response_mime_type": "application/json",
            "response_schema": FlashcardListGen,
        }
        
        # Add thinking configuration for reasoning models like gemma-4-31b-it
        if "gemma-4" in model_name or "thinking" in model_name:
            config_args["thinking_config"] = types.ThinkingConfig(
                thinking_level="HIGH"
            )
        else:
            config_args["temperature"] = 0.2
            
        logger.info(f"Invoking Gemini model {model_name} with config: {config_args}...")
        
        contents = [prompt] if is_text_only else [uploaded_file, prompt]
        
        response = client.models.generate_content(
            model=model_name,
            contents=contents,
            config=types.GenerateContentConfig(**config_args)
        )
        
        # Clean up file on Gemini servers if uploaded
        if uploaded_file:
            try:
                client.files.delete(name=uploaded_file.name)
                logger.info("Cleaned up uploaded file from Gemini server.")
            except Exception as cleanup_err:
                logger.warning(f"Failed to delete uploaded file from Gemini server: {cleanup_err}")
            
        # 4. Parse response JSON
        raw_json = response.text
        logger.debug(f"Raw response from Gemini: {raw_json}")
        
        data = json.loads(raw_json)
        cards = data.get("cards", [])
        logger.info(f"Gemini successfully generated {len(cards)} flashcards.")
        
        # 5. Package each card
        generated_hashes = []
        for card_dict in cards:
            card_obj = FlashcardGen(**card_dict)
            card_hash = package_flashcard(
                card_data=card_obj,
                source_pdf_name=pdf_path.name,
                temp_img_dir=temp_img_dir,
                output_dir=storage_dir
            )
            generated_hashes.append(card_hash)
            
        return generated_hashes
        
    except Exception as e:
        logger.error(f"Error during flashcard generation: {str(e)}", exc_info=True)
        # Attempt cleanup if something failed before deletion
        if uploaded_file:
            try:
                client.files.delete(name=uploaded_file.name)
            except:
                pass
        raise e
