"""
Metadata Ingestion Engine: EPUB & Audio inspection, canonical metadata correction,
embedded file tagging, and safe atomic library publishing.
"""

import hashlib
import io
import json
import logging
import os
import shutil
import tempfile
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

logger = logging.getLogger("metadata_engine")


def _safe_filename(s: str) -> str:
    """Sanitize string for safe filesystem usage across Linux/macOS."""
    keep = "".join(c for c in s if c.isalnum() or c in (" ", "-", "_", ".", "'", "(", ")")).strip()
    return keep or "Unknown"


def compute_file_sha256(path: str) -> str:
    """Compute SHA-256 hash of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return f"sha256:{h.hexdigest()}"


class MetadataIngestionEngine:
    def __init__(self, books_library_path=None, audiobooks_library_path=None):
        if books_library_path:
            self.books_library_path = books_library_path
        elif os.environ.get("BOOKS_LIBRARY_PATH"):
            self.books_library_path = os.environ["BOOKS_LIBRARY_PATH"]
        elif os.path.exists("/mnt/media/Books"):
            self.books_library_path = "/mnt/media/Books"
        else:
            self.books_library_path = os.path.join(tempfile.gettempdir(), "finamp_books")

        if audiobooks_library_path:
            self.audiobooks_library_path = audiobooks_library_path
        elif os.environ.get("AUDIOBOOKS_LIBRARY_PATH"):
            self.audiobooks_library_path = os.environ["AUDIOBOOKS_LIBRARY_PATH"]
        elif os.path.exists("/mnt/media/Audiobooks"):
            self.audiobooks_library_path = "/mnt/media/Audiobooks"
        else:
            self.audiobooks_library_path = os.path.join(tempfile.gettempdir(), "finamp_audiobooks")

    # --- EPUB Inspection and Embedded Tagging ---

    def validate_epub(self, epub_path: str) -> dict:
        """Validate EPUB zip container, extract OPF package metadata."""
        if not os.path.exists(epub_path):
            raise FileNotFoundError(f"EPUB file not found: {epub_path}")

        if not zipfile.is_zipfile(epub_path):
            raise ValueError(f"File is not a valid zip archive: {epub_path}")

        with zipfile.ZipFile(epub_path, "r") as z:
            namelist = z.namelist()
            if "META-INF/container.xml" not in namelist:
                raise ValueError("Invalid EPUB: META-INF/container.xml missing")

            # Parse container.xml to locate OPF file
            container_xml = z.read("META-INF/container.xml")
            c_root = ET.fromstring(container_xml)
            ns = {"c": "urn:oasis:names:tc:opendocument:xmlns:container"}
            rootfile = c_root.find(".//c:rootfile", ns)
            if rootfile is None or "full-path" not in rootfile.attrib:
                raise ValueError("Invalid EPUB: rootfile not found in container.xml")

            opf_path = rootfile.attrib["full-path"]
            if opf_path not in namelist:
                raise ValueError(f"Invalid EPUB: OPF package not found at {opf_path}")

            # Parse OPF package metadata
            opf_xml = z.read(opf_path)
            opf_root = ET.fromstring(opf_xml)
            dc_ns = {"dc": "http://purl.org/dc/elements/1.1/", "opf": "http://www.idpf.org/2007/opf"}

            title_elem = opf_root.find(".//dc:title", dc_ns)
            creator_elem = opf_root.find(".//dc:creator", dc_ns)
            lang_elem = opf_root.find(".//dc:language", dc_ns)
            pub_elem = opf_root.find(".//dc:publisher", dc_ns)
            date_elem = opf_root.find(".//dc:date", dc_ns)
            id_elem = opf_root.find(".//dc:identifier", dc_ns)

            return {
                "valid": True,
                "opf_path": opf_path,
                "title": title_elem.text.strip() if title_elem is not None and title_elem.text else "",
                "author": creator_elem.text.strip() if creator_elem is not None and creator_elem.text else "",
                "language": lang_elem.text.strip() if lang_elem is not None and lang_elem.text else "en",
                "publisher": pub_elem.text.strip() if pub_elem is not None and pub_elem.text else "",
                "date": date_elem.text.strip() if date_elem is not None and date_elem.text else "",
                "identifier": id_elem.text.strip() if id_elem is not None and id_elem.text else "",
                "file_size": os.path.getsize(epub_path),
                "sha256": compute_file_sha256(epub_path),
            }

    def write_epub_metadata(
        self,
        epub_path: str,
        title: str,
        author: str,
        publisher: str = None,
        year: int = None,
        language: str = "en",
        isbn: str = None,
    ) -> str:
        """
        Embed verified canonical metadata into EPUB OPF package document.
        Maintains IDPF compliance: mimetype file remains uncompressed as the first entry.
        Atomic operation: writes to .tmp before replacing original.
        """
        info = self.validate_epub(epub_path)
        opf_path = info["opf_path"]

        dir_name = os.path.dirname(epub_path)
        fd, tmp_epub = tempfile.mkstemp(suffix=".epub", dir=dir_name if os.path.isdir(dir_name) else None)
        os.close(fd)

        try:
            with zipfile.ZipFile(epub_path, "r") as zin:
                # Read and update OPF
                opf_data = zin.read(opf_path).decode("utf-8", errors="replace")
                root = ET.fromstring(opf_data)

                # Ensure namespaces
                ns_dc = "http://purl.org/dc/elements/1.1/"
                metadata = root.find("{http://www.idpf.org/2007/opf}metadata")
                if metadata is None:
                    metadata = root.find("metadata")
                if metadata is None:
                    metadata = ET.SubElement(root, "metadata")

                # Helper to update or append DC element
                def _set_dc(tag, val):
                    if not val:
                        return
                    full_tag = f"{{{ns_dc}}}{tag}"
                    elem = metadata.find(full_tag)
                    if elem is None:
                        elem = ET.SubElement(metadata, full_tag)
                    elem.text = str(val)

                _set_dc("title", title)
                _set_dc("creator", author)
                if publisher:
                    _set_dc("publisher", publisher)
                if year:
                    _set_dc("date", str(year))
                if language:
                    _set_dc("language", language)
                if isbn:
                    _set_dc("identifier", f"urn:isbn:{isbn}")

                updated_opf = ET.tostring(root, encoding="utf-8", xml_declaration=True)

                # Write out new EPUB ensuring mimetype is stored first uncompressed
                with zipfile.ZipFile(tmp_epub, "w") as zout:
                    # 1. mimetype first
                    mimetype_data = b"application/epub+zip"
                    if "mimetype" in zin.namelist():
                        mimetype_data = zin.read("mimetype").strip()
                    zout.writestr("mimetype", mimetype_data, compress_type=zipfile.ZIP_STORED)

                    # 2. copy other files, replacing OPF
                    for item in zin.infolist():
                        if item.filename == "mimetype":
                            continue
                        if item.filename == opf_path:
                            zout.writestr(item, updated_opf)
                        else:
                            zout.writestr(item, zin.read(item.filename))

            # Validate newly built EPUB
            self.validate_epub(tmp_epub)

            # Atomic replace
            shutil.move(tmp_epub, epub_path)
            return epub_path
        finally:
            if os.path.exists(tmp_epub):
                try:
                    os.remove(tmp_epub)
                except Exception:
                    pass

    # --- Audio Inspection and Embedded Tagging ---

    def inspect_audio_file(self, audio_path: str) -> dict:
        """Inspect audio file format, size, duration, and embedded tags."""
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Audio file not found: {audio_path}")

        file_size = os.path.getsize(audio_path)
        ext = os.path.splitext(audio_path)[1].lower().lstrip(".")
        duration = 0.0
        title = ""
        artist = ""
        album = ""
        track_num = 1

        try:
            import mutagen
            audio = mutagen.File(audio_path)
            if audio is not None:
                duration = getattr(audio.info, "length", 0.0)
                # Parse tags
                if audio.tags:
                    tags = audio.tags
                    # ID3 / MP3
                    if hasattr(tags, "getall"):
                        title = str(tags.get("TIT2") or "")
                        artist = str(tags.get("TPE1") or "")
                        album = str(tags.get("TALB") or "")
                    # Vorbis / FLAC
                    elif isinstance(tags, dict):
                        title = (tags.get("title") or [""])[0]
                        artist = (tags.get("artist") or [""])[0]
                        album = (tags.get("album") or [""])[0]
        except ImportError:
            # Fallback when mutagen is not loaded in current process
            pass
        except Exception as e:
            logger.warning(f"Audio tag inspection warning for {audio_path}: {e}")

        return {
            "file_path": audio_path,
            "format": ext,
            "file_size": file_size,
            "duration_seconds": round(duration, 2),
            "title": title,
            "artist": artist,
            "album": album,
            "track_number": track_num,
            "sha256": compute_file_sha256(audio_path),
        }

    def write_audio_metadata(
        self,
        audio_path: str,
        title: str,
        artist: str,
        album: str,
        track_number: int = None,
        total_tracks: int = None,
        year: int = None,
        cover_image_bytes: bytes = None,
    ) -> bool:
        """Embed ID3 / Vorbis metadata and optional cover artwork into audio file."""
        try:
            import mutagen
            audio = mutagen.File(audio_path)
            if audio is None:
                return False

            ext = os.path.splitext(audio_path)[1].lower()

            if ext == ".flac":
                audio["title"] = [title]
                audio["artist"] = [artist]
                audio["album"] = [album]
                if track_number is not None:
                    audio["tracknumber"] = [str(track_number)]
                if year is not None:
                    audio["date"] = [str(year)]
                if cover_image_bytes:
                    from mutagen.flac import Picture
                    pic = Picture()
                    pic.data = cover_image_bytes
                    pic.type = 3  # Cover (front)
                    pic.mime = "image/jpeg"
                    audio.clear_pictures()
                    audio.add_picture(pic)
                audio.save()
                return True

            elif ext == ".mp3":
                from mutagen.id3 import ID3, TIT2, TPE1, TALB, TRCK, TDRC, APIC, ID3NoHeaderError
                try:
                    tags = ID3(audio_path)
                except ID3NoHeaderError:
                    tags = ID3()

                tags.add(TIT2(encoding=3, text=title))
                tags.add(TPE1(encoding=3, text=artist))
                tags.add(TALB(encoding=3, text=album))
                if track_number is not None:
                    track_str = f"{track_number}/{total_tracks}" if total_tracks else str(track_number)
                    tags.add(TRCK(encoding=3, text=track_str))
                if year is not None:
                    tags.add(TDRC(encoding=3, text=str(year)))
                if cover_image_bytes:
                    tags.delall("APIC")
                    tags.add(APIC(
                        encoding=3,
                        mime="image/jpeg",
                        type=3,
                        desc="Cover",
                        data=cover_image_bytes
                    ))
                tags.save(audio_path)
                return True

            elif ext in (".m4b", ".m4a"):
                audio["\xa9nam"] = [title]
                audio["\xa9ART"] = [artist]
                audio["\xa9alb"] = [album]
                if track_number is not None:
                    audio["trkn"] = [(track_number, total_tracks or 0)]
                if year is not None:
                    audio["\xa9day"] = [str(year)]
                if cover_image_bytes:
                    from mutagen.mp4 import MP4Cover
                    audio["covr"] = [MP4Cover(cover_image_bytes, imageformat=MP4Cover.FORMAT_JPEG)]
                audio.save()
                return True

        except ImportError:
            logger.info("mutagen not installed in this environment; skipping embedded audio tag writing")
        except Exception as e:
            logger.warning(f"Could not write audio metadata tags for {audio_path}: {e}")
        return False

    # --- Safe Atomic Publishing to Permanent Library ---

    def publish_epub_to_library(self, source_epub_path: str, author: str, title: str) -> str:
        """
        Safely publish verified EPUB to permanent library:
        `${books_library_path}/${author}/${title}/${title}.epub`
        """
        self.validate_epub(source_epub_path)

        safe_author = _safe_filename(author)
        safe_title = _safe_filename(title)
        dest_dir = os.path.join(self.books_library_path, safe_author, safe_title)
        os.makedirs(dest_dir, exist_ok=True)

        dest_file = os.path.join(dest_dir, f"{safe_title}.epub")
        tmp_dest = dest_file + f".tmp-{os.getpid()}"

        shutil.copy2(source_epub_path, tmp_dest)
        # Verify copied file in destination
        self.validate_epub(tmp_dest)
        # Atomic replace
        os.replace(tmp_dest, dest_file)
        # Ensure permissions allow Audiobookshelf read
        try:
            os.chmod(dest_file, 0o664)
        except Exception:
            pass

        return dest_file

    def publish_audiobook_to_library(self, source_track_paths: list[str], author: str, title: str) -> list[str]:
        """
        Safely publish verified audiobook tracks to permanent library:
        `${audiobooks_library_path}/${author}/${title}/Track 01.mp3`, etc.
        """
        if not source_track_paths:
            raise ValueError("No audio tracks provided for publishing")

        safe_author = _safe_filename(author)
        safe_title = _safe_filename(title)
        dest_dir = os.path.join(self.audiobooks_library_path, safe_author, safe_title)
        os.makedirs(dest_dir, exist_ok=True)

        published_paths = []
        for idx, src in enumerate(sorted(source_track_paths), 1):
            ext = os.path.splitext(src)[1]
            dest_name = f"{idx:02d} - Chapter {idx}{ext}"
            dest_file = os.path.join(dest_dir, dest_name)
            tmp_dest = dest_file + f".tmp-{os.getpid()}"
            shutil.copy2(src, tmp_dest)
            os.replace(tmp_dest, dest_file)
            try:
                os.chmod(dest_file, 0o664)
            except Exception:
                pass
            published_paths.append(dest_file)

        return published_paths
