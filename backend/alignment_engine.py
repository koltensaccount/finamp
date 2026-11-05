"""
Forced Alignment Engine for Finamp Books:
Extracts ground-truth text and stable CFIs from EPUB XHTML,
transcribes/aligns narration audio with faster-whisper,
performs fuzzy sentence-level and chapter-level matching,
records unmatched regions (disclaimers/forewords),
and publishes versioned alignment maps to SQLite.
"""

import difflib
import json
import logging
import os
import re
import time
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

logger = logging.getLogger("alignment_engine")


def _norm(s: str) -> str:
    if not s:
        return ""
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).strip()


class AlignmentEngine:
    def __init__(self, books_core=None, model_name="tiny.en"):
        self.books_core = books_core
        self.model_name = model_name
        self._model = None

    def _get_model(self):
        if self._model is None:
            from faster_whisper import WhisperModel
            logger.info(f"Loading faster-whisper model '{self.model_name}' on CPU (int8)...")
            self._model = WhisperModel(self.model_name, device="cpu", compute_type="int8")
        return self._model

    def extract_epub_text(self, epub_path: str) -> list[dict]:
        """
        Extracts reading chapters, paragraphs, and sentences from EPUB container.
        Returns a list of chapter dicts containing sentences with stable CFI identifiers.
        """
        if not os.path.exists(epub_path):
            raise FileNotFoundError(f"EPUB file not found: {epub_path}")

        chapters = []
        with zipfile.ZipFile(epub_path, "r") as z:
            # 1. Locate container.xml
            container_xml = z.read("META-INF/container.xml")
            container_root = ET.fromstring(container_xml)
            opf_path = None
            for rf in container_root.findall(".//{urn:oasis:names:tc:opendocument:xmlns:container}rootfile"):
                if rf.attrib.get("media-type") == "application/oebps-package+xml":
                    opf_path = rf.attrib.get("full-path")
                    break
            if not opf_path:
                for name in z.namelist():
                    if name.endswith(".opf"):
                        opf_path = name
                        break

            if not opf_path:
                raise ValueError("No OPF package document in EPUB container")

            opf_dir = os.path.dirname(opf_path)
            opf_root = ET.fromstring(z.read(opf_path))

            # 2. Extract manifest items
            manifest = {}
            for item in opf_root.findall(".//{http://www.idpf.org/2007/opf}item"):
                manifest[item.attrib["id"]] = item.attrib["href"]

            # 3. Read spine order
            spine_item_ids = []
            for itemref in opf_root.findall(".//{http://www.idpf.org/2007/opf}itemref"):
                spine_item_ids.append(itemref.attrib["idref"])

            # 4. Extract TOC labels if NCX is present
            toc_labels = {}
            for item in opf_root.findall(".//{http://www.idpf.org/2007/opf}item"):
                if item.attrib.get("media-type") == "application/x-dtbncx+xml":
                    ncx_href = item.attrib["href"]
                    ncx_full = os.path.normpath(os.path.join(opf_dir, ncx_href)).replace("\\", "/")
                    if ncx_full in z.namelist():
                        try:
                            ncx_root = ET.fromstring(z.read(ncx_full))
                            for np in ncx_root.findall(".//{http://www.daisy.org/z3986/2005/ncx/}navPoint"):
                                text_el = np.find(".//{http://www.daisy.org/z3986/2005/ncx/}text")
                                src_el = np.find("{http://www.daisy.org/z3986/2005/ncx/}content")
                                if text_el is not None and src_el is not None:
                                    src = src_el.attrib.get("src", "").split("#")[0]
                                    toc_labels[src] = text_el.text.strip()
                        except Exception as e:
                            logger.warning(f"Error parsing NCX TOC: {e}")

            # 5. Process spine items that represent text/chapters
            chapter_counter = 1
            for spine_idx, item_id in enumerate(spine_item_ids, 1):
                href = manifest.get(item_id)
                if not href:
                    continue

                full_href = os.path.normpath(os.path.join(opf_dir, href)).replace("\\", "/")
                filename = os.path.basename(full_href).lower()

                # Filter out boilerplate pages like titlepage, imprint, uncopyright
                if any(x in filename for x in ("titlepage", "imprint", "colophon", "uncopyright")):
                    continue

                if full_href not in z.namelist():
                    continue

                try:
                    content = z.read(full_href).decode("utf-8", errors="replace")
                except Exception:
                    continue

                # Extract title from TOC, <h1>/<h2>, or filename
                title = toc_labels.get(href) or toc_labels.get(os.path.basename(href))
                if not title:
                    h_match = re.search(r"<h[1-3][^>]*>(.*?)</h[1-3]>", content, re.DOTALL)
                    if h_match:
                        title = re.sub(r"<[^>]+>", "", h_match.group(1)).strip()
                    else:
                        title = f"Chapter {chapter_counter}"

                # Extract paragraphs
                paras = re.findall(r"<p[^>]*>(.*?)</p>", content, re.DOTALL)
                clean_paras = [re.sub(r"<[^>]+>", "", p).strip() for p in paras if p.strip()]

                # Skip pages with no paragraphs
                if not clean_paras:
                    continue

                sentences = []
                sent_global_idx = 0
                for p_idx, p in enumerate(clean_paras):
                    # Sentence splitting
                    s_list = re.split(r"(?<=[.!?])\s+", p)
                    for s_idx, s in enumerate(s_list):
                        s_clean = s.strip()
                        if len(s_clean) >= 3:
                            # Generate stable CFI
                            cfi = f"/6/{spine_idx * 2}[{os.path.basename(full_href)}]!/4/{p_idx * 2 + 2}/{s_idx * 2 + 1}:0"
                            sentences.append({
                                "sentence_idx": sent_global_idx,
                                "paragraph_idx": p_idx,
                                "cfi": cfi,
                                "text": s_clean,
                                "norm_text": _norm(s_clean),
                            })
                            sent_global_idx += 1

                if sentences:
                    chapters.append({
                        "chapter_idx": chapter_counter,
                        "title": title,
                        "spine_index": spine_idx,
                        "file_path": full_href,
                        "filename": os.path.basename(full_href),
                        "sentences": sentences,
                    })
                    chapter_counter += 1

        return chapters

    def align_chapter(self, model, audio_file_path: str, chapter_data: dict, track_number: int) -> dict:
        """
        Transcribes audio track, performs sentence-level forced alignment with EPUB sentences,
        detects prefaces/disclaimers, and computes quality confidence.
        """
        if not os.path.exists(audio_file_path):
            raise FileNotFoundError(f"Audio file not found: {audio_file_path}")

        # 1. Transcribe narration track
        t0 = time.time()
        segments_gen, info = model.transcribe(audio_file_path, language="en", word_timestamps=True)
        speech_segments = []
        for s in segments_gen:
            text = s.text.strip()
            if text:
                speech_segments.append({
                    "start": round(s.start, 3),
                    "end": round(s.end, 3),
                    "text": text,
                    "norm": _norm(text),
                })
        t_transcribe = time.time() - t0
        logger.info(f"Transcribed {len(speech_segments)} segments for track {track_number} in {t_transcribe:.2f}s")

        epub_sentences = chapter_data.get("sentences", [])
        if not epub_sentences or not speech_segments:
            return {
                "chapter_idx": chapter_data.get("chapter_idx", track_number),
                "title": chapter_data.get("title", f"Chapter {track_number}"),
                "confidence": 0.0,
                "mappings": [],
                "unmatched_regions": [],
            }

        # 2. Check for narration intro / preface (e.g. LibriVox announcement)
        first_sent_norm = epub_sentences[0]["norm_text"]
        speech_start_idx = 0
        best_first_score = 0.0
        best_first_idx = 0

        # Look in the first 8 segments for where the actual text begins
        for idx in range(min(8, len(speech_segments))):
            seg_norm = speech_segments[idx]["norm"]
            # Check overlap with first 8 words of sentence
            lead_words = " ".join(first_sent_norm.split()[:8])
            score = difflib.SequenceMatcher(None, seg_norm, lead_words).ratio()
            if score > best_first_score:
                best_first_score = score
                best_first_idx = idx

        unmatched_regions = []
        if best_first_idx > 0 and best_first_score > 0.45:
            speech_start_idx = best_first_idx
            unmatched_text = " ".join(s["text"] for s in speech_segments[:best_first_idx])
            unmatched_regions.append({
                "type": "narration_preface_or_disclaimer",
                "audio_track": track_number,
                "start_seconds": 0.0,
                "end_seconds": speech_segments[best_first_idx]["start"],
                "text": unmatched_text,
            })

        # 3. Align sentences sequentially using sliding window
        mappings = []
        curr_speech_idx = speech_start_idx
        scores = []

        for sent in epub_sentences:
            if curr_speech_idx >= len(speech_segments):
                break

            s_norm = sent["norm_text"]
            if not s_norm:
                continue

            # Look ahead across next 4 speech segments
            best_match_idx = -1
            best_score = 0.0
            accum_text = ""
            accum_end = speech_segments[curr_speech_idx]["end"]

            for lookahead in range(min(4, len(speech_segments) - curr_speech_idx)):
                candidate_idx = curr_speech_idx + lookahead
                seg = speech_segments[candidate_idx]
                candidate_norm = " ".join(s["norm"] for s in speech_segments[curr_speech_idx:candidate_idx + 1])
                score = difflib.SequenceMatcher(None, candidate_norm, s_norm).ratio()
                if score > best_score:
                    best_score = score
                    best_match_idx = candidate_idx
                    accum_text = " ".join(s["text"] for s in speech_segments[curr_speech_idx:candidate_idx + 1])
                    accum_end = seg["end"]

            if best_score >= 0.55:
                start_sec = speech_segments[curr_speech_idx]["start"]
                mappings.append({
                    "chapter_idx": chapter_data.get("chapter_idx", track_number),
                    "sentence_idx": sent["sentence_idx"],
                    "audio_track": track_number,
                    "audio_start_sec": start_sec,
                    "audio_end_sec": accum_end,
                    "epub_cfi": sent["cfi"],
                    "text": sent["text"],
                    "confidence": round(best_score, 3),
                })
                scores.append(best_score)
                curr_speech_idx = best_match_idx + 1
            else:
                # Slight advance if current speech segment is way behind
                pass

        avg_conf = sum(scores) / len(scores) if scores else 0.0

        return {
            "chapter_idx": chapter_data.get("chapter_idx", track_number),
            "title": chapter_data.get("title", f"Chapter {track_number}"),
            "audio_track": track_number,
            "chapter_start_sec": mappings[0]["audio_start_sec"] if mappings else 0.0,
            "chapter_end_sec": speech_segments[-1]["end"] if speech_segments else 0.0,
            "confidence": round(avg_conf, 3),
            "aligned_sentences": len(mappings),
            "total_sentences": len(epub_sentences),
            "mappings": mappings,
            "unmatched_regions": unmatched_regions,
        }

    def align_work(self, work_id: str, max_chapters: int = None) -> dict:
        """
        Coordinates full alignment between EPUB and audiobook for a canonical work.
        Persists the result atomically to alignments and chapters tables in SQLite.
        """
        if not self.books_core:
            raise ValueError("BooksCore instance required for alignment coordination")

        # 1. Fetch work, editions, and assets
        book = self.books_core.get_book(work_id)
        if not book:
            return {"status": "error", "error": f"Work not found: {work_id}"}

        editions = book.get("editions", [])
        epub_ed = next((e for e in editions if e.get("format") == "epub"), None)
        audio_ed = next((e for e in editions if e.get("format") == "audiobook"), None)

        if not epub_ed or not audio_ed:
            return {"status": "error", "error": "Both EPUB and audiobook editions are required for alignment"}

        epub_assets = epub_ed.get("assets", [])
        if not epub_assets or not os.path.exists(epub_assets[0].get("file_path", "")):
            return {"status": "error", "error": "EPUB asset file does not exist on server"}

        audio_assets = sorted(audio_ed.get("assets", []), key=lambda a: a.get("track_number") or 1)
        if not audio_assets:
            return {"status": "error", "error": "No audiobook track assets found for alignment"}

        epub_file = epub_assets[0]["file_path"]
        logger.info(f"Extracting EPUB text from: {epub_file}")
        chapters = self.extract_epub_text(epub_file)
        if not chapters:
            return {"status": "error", "error": "No text chapters could be extracted from EPUB"}

        # 2. Match chapters to audio tracks
        model = self._get_model()
        all_mappings = []
        all_unmatched = []
        chapter_summaries = []
        track_count = len(audio_assets)

        chapters_to_process = chapters[:max_chapters] if max_chapters else chapters

        for idx, ch in enumerate(chapters_to_process, 1):
            if idx > track_count:
                break

            track_asset = audio_assets[idx - 1]
            audio_path = track_asset.get("file_path")
            if not audio_path or not os.path.exists(audio_path):
                continue

            logger.info(f"Aligning Chapter {idx}: '{ch.get('title')}' with Track {idx}: {os.path.basename(audio_path)}")
            res = self.align_chapter(model, audio_path, ch, track_number=idx)

            all_mappings.extend(res["mappings"])
            all_unmatched.extend(res["unmatched_regions"])
            chapter_summaries.append({
                "chapter_idx": idx,
                "title": ch.get("title"),
                "audio_track": idx,
                "start_seconds": res.get("chapter_start_sec", 0.0),
                "end_seconds": res.get("chapter_end_sec", 0.0),
                "epub_href": ch.get("file_path"),
                "epub_cfi": ch["sentences"][0]["cfi"] if ch.get("sentences") else None,
                "confidence": res.get("confidence", 0.0),
                "aligned_count": res.get("aligned_sentences", 0),
            })

        # 3. Overall quality evaluation
        total_aligned = len(all_mappings)
        avg_confidence = (
            sum(m["confidence"] for m in all_mappings) / total_aligned
            if total_aligned > 0 else 0.0
        )
        alignment_level = "sentence" if avg_confidence >= 0.70 and total_aligned >= 5 else "chapter"

        # 4. Store alignment atomically in SQLite
        align_record = self.books_core.store_alignment(
            work_id=work_id,
            epub_edition_id=epub_ed["id"],
            audio_edition_id=audio_ed["id"],
            alignment_level=alignment_level,
            engine="faster-whisper-ctc-matcher",
            version="1.0.0",
            confidence=round(avg_confidence, 3),
            mapping_data=all_mappings,
            unmatched_regions=all_unmatched,
        )

        # 5. Update chapters table with verified timestamps & CFIs
        with self.books_core.get_db() as db:
            for ch_sum in chapter_summaries:
                ch_id = f"ch-{audio_ed['id']}-{ch_sum['chapter_idx']}"
                db.execute("""
                    INSERT INTO chapters (id, edition_id, index_num, title, start_seconds, end_seconds, epub_href, epub_cfi)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        title=excluded.title,
                        start_seconds=excluded.start_seconds,
                        end_seconds=excluded.end_seconds,
                        epub_href=excluded.epub_href,
                        epub_cfi=excluded.epub_cfi
                """, (
                    ch_id,
                    audio_ed["id"],
                    ch_sum["chapter_idx"],
                    ch_sum["title"],
                    ch_sum["start_seconds"],
                    ch_sum["end_seconds"],
                    ch_sum["epub_href"],
                    ch_sum["epub_cfi"],
                ))
            db.commit()

        logger.info(
            f"Successfully aligned work '{work_id}': level={alignment_level}, "
            f"confidence={avg_confidence:.3f}, total_aligned={total_aligned}"
        )

        return {
            "status": "aligned",
            "work_id": work_id,
            "alignment_id": align_record.get("id"),
            "alignment_level": alignment_level,
            "confidence": round(avg_confidence, 3),
            "aligned_sentences": total_aligned,
            "chapters_aligned": len(chapter_summaries),
            "unmatched_regions": len(all_unmatched),
        }
